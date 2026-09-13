import { describe, expect, it, vi } from "vitest";
import controladorFonte from "./controladorGestaoCiclos.ts?raw";
import gestaoFonte from "./gestaoCiclosSoberanos.ts?raw";
import type { CicloSoberano, ResultadoCiclos } from "../../application/ports/CycleRepository";
import type { EdgeCiclos, ResultadoEdgeCiclos } from "../../infrastructure/supabase/ciclos/edgeCiclos";
import { criarControladorGestaoCiclos } from "./controladorGestaoCiclos";
import type { ResultadoGestao } from "./gestaoCiclosSoberanos";

/**
 * F5-09 P8 (Issue #204) — CONTROLADOR de UI da gestão de ciclos (opção B).
 *
 * Testes COMPORTAMENTAIS em node (sem DOM/jsdom), cobrindo o que a página
 * assíncrona precisa provar: loading (AI), erro soberano sem fallback (AJ),
 * resposta obsoleta de organização anterior (AK), reload após sucesso (AC),
 * falha preservando o estado anterior (AD), botões que não presumem sucesso
 * (AL), cancelamento de PLANEJADO e ATIVO (AE/AF) — além de ausência de delete
 * físico, de metas e de autoridade local (X/Y/Z) e ausência de RPC direta (AG).
 *
 * Correção pós-auditoria GPT (Issue #204): filtro da última leitura preservado no
 * reload pós-mutation (M1–M6), geração monotônica no controlador de gestão —
 * duas leituras da MESMA organização (S1–S6) — e mutation com sucesso cujo reload
 * falha (nada de estado otimista nem fallback local).
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const CICLO = "55555555-5555-4555-8555-555555555555";

function soberano(id: string, status: CicloSoberano["status"], version: number): CicloSoberano {
  return {
    id,
    organizationId: ORG,
    ano: 2035,
    numero: 1,
    status,
    dataInicio: "2035-01-01",
    dataFim: "2035-03-31",
    dataAtivacao: "2035-01-02T00:00:00.000Z",
    dataEncerramento: null,
    encerradoComPendencias: false,
    quantidadePendencias: 0,
    version,
    criadoEm: "2035-01-01T00:00:00.000Z",
    atualizadoEm: "2035-01-02T00:00:00.000Z",
  };
}

function repositorio(ciclos: readonly CicloSoberano[]) {
  return {
    listarCiclos: vi.fn(async (): Promise<ResultadoCiclos<readonly CicloSoberano[]>> => ({
      ok: true,
      data: ciclos,
    })),
    obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
    obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
  };
}

function edgeFalso(
  resposta: ResultadoEdgeCiclos<unknown> = { ok: true, data: { version: 5 } },
  chamadas: { metodo: string; entrada: Record<string, unknown> }[] = []
): EdgeCiclos {
  const registrar = (metodo: string) => async (entrada: unknown) => {
    chamadas.push({ metodo, entrada: entrada as Record<string, unknown> });
    return resposta;
  };
  return {
    criar: registrar("criar"),
    editar: registrar("editar"),
    ativar: registrar("ativar"),
    encerrar: registrar("encerrar"),
    cancelar: registrar("cancelar"),
    reabrir: registrar("reabrir"),
    corrigirPeriodo: registrar("corrigirPeriodo"),
    incluirAdmissao: registrar("incluirAdmissao"),
  } as unknown as EdgeCiclos;
}

/**
 * Estreita o union de `ResultadoGestao` (o `expect` do vitest não estreita
 * tipos): devolve o erro público da falha e aborta se o resultado foi sucesso.
 */
function erroDe(resultado: ResultadoGestao<unknown>): {
  readonly code: string;
  readonly message: string;
} {
  if (resultado.ok) throw new Error("esperava um resultado de falha");
  return resultado.error;
}

describe("F5-09 P8 — controlador: leitura assíncrona (AI/AJ/AK)", () => {
  it("AI: publica `carregando` durante a leitura e `pronto` ao concluir", async () => {
    let resolver!: (valor: ResultadoCiclos<readonly CicloSoberano[]>) => void;
    const pendente = new Promise<ResultadoCiclos<readonly CicloSoberano[]>>((r) => {
      resolver = r;
    });
    const fonte = {
      listarCiclos: vi.fn(() => pendente),
      obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
      obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
    };
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte });

    const carga = controlador.carregar(ORG);
    expect(controlador.estado().fase).toBe("carregando");
    expect(controlador.estado().organizacaoId).toBe(ORG);

    resolver({ ok: true, data: [soberano(CICLO, "PLANEJADO", 2)] });
    await carga;

    expect(controlador.estado()).toMatchObject({ fase: "pronto", erro: null });
    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([CICLO]);
    expect(controlador.versaoDe(CICLO)).toBe(2);
  });

  it("AJ: erro soberano é publicado e NÃO existe fallback local", async () => {
    const fonte = {
      listarCiclos: vi.fn(async (): Promise<ResultadoCiclos<readonly CicloSoberano[]>> => ({
        ok: false,
        error: { code: "INTERNAL", message: "Não foi possível consultar os ciclos agora." },
      })),
      obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
      obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
    };
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte });

    const resultado = await controlador.carregar(ORG);

    expect(resultado.ok).toBe(false);
    expect(controlador.estado().fase).toBe("erro");
    expect(controlador.estado().erro?.code).toBe("INTERNAL");
  });

  it("AK: troca de organização não publica resposta obsoleta", async () => {
    let resolverA!: (valor: ResultadoCiclos<readonly CicloSoberano[]>) => void;
    const pendenteA = new Promise<ResultadoCiclos<readonly CicloSoberano[]>>((r) => {
      resolverA = r;
    });
    let chamadas = 0;
    const fonte = {
      listarCiclos: vi.fn(() => {
        chamadas += 1;
        if (chamadas === 1) return pendenteA;
        return Promise.resolve({ ok: true as const, data: [soberano(CICLO, "ATIVO", 9)] });
      }),
      obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
      obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
    };
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte });

    const requestA = controlador.carregar(ORG);
    const requestB = controlador.carregar(ORG_B);
    await requestB;
    resolverA({ ok: true, data: [soberano(CICLO, "PLANEJADO", 1)] });
    await requestA;

    expect(controlador.estado().organizacaoId).toBe(ORG_B);
    expect(controlador.estado().fase).toBe("pronto");
    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([CICLO]);
    expect(controlador.versaoDe(CICLO)).toBe(9);
  });

  it("organização ausente NÃO opera (fail-closed, sem tocar o repositório)", async () => {
    const fonte = repositorio([soberano(CICLO, "ATIVO", 1)]);
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte });

    const resultado = await controlador.carregar(null);

    expect(resultado.ok).toBe(false);
    expect(controlador.estado().fase).toBe("erro");
    expect(fonte.listarCiclos).not.toHaveBeenCalled();
  });
});

describe("F5-09 P8 — controlador: mutações (AC/AD/AL/AE/AF)", () => {
  it("AC: sucesso dispara RELOAD soberano (leitura + recarga)", async () => {
    const fonte = repositorio([soberano(CICLO, "PLANEJADO", 3)]);
    const chamadas: { metodo: string; entrada: Record<string, unknown> }[] = [];
    const controlador = criarControladorGestaoCiclos({
      repositorio: fonte,
      edge: edgeFalso(undefined, chamadas),
    });
    await controlador.carregar(ORG);
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(1);

    const resultado = await controlador.ativar(CICLO);

    expect(resultado.ok).toBe(true);
    expect(chamadas[0]!.metodo).toBe("ativar");
    // A versão enviada é a SOBERANA lida (nunca local).
    expect(chamadas[0]!.entrada.expectedVersion).toBe(3);
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(2);
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });

  it("AD: falha da mutation preserva o estado soberano anterior", async () => {
    const fonte = repositorio([soberano(CICLO, "ATIVO", 4)]);
    const controlador = criarControladorGestaoCiclos({
      repositorio: fonte,
      edge: edgeFalso({ ok: false, error: { code: "CONFLICT", message: "estado atual" } }),
    });
    await controlador.carregar(ORG);
    const antes = controlador.estado().ciclos;

    const resultado = await controlador.encerrar(CICLO, "Fim");

    expect(resultado.ok).toBe(false);
    expect(controlador.estado().ciclos).toEqual(antes);
    expect(controlador.estado().erro?.code).toBe("CONFLICT");
    // Nenhuma releitura foi disparada por falha (estado anterior intacto).
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(1);
  });

  it("AL: `operacaoEmAndamento` fica ativo durante a mutation (botões não presumem sucesso)", async () => {
    const fonte = repositorio([soberano(CICLO, "PLANEJADO", 1)]);
    let liberar!: (valor: ResultadoEdgeCiclos<unknown>) => void;
    const pendente = new Promise<ResultadoEdgeCiclos<unknown>>((r) => {
      liberar = r;
    });
    const edge = edgeFalso();
    const comEspera: EdgeCiclos = { ...edge, ativar: () => pendente } as EdgeCiclos;
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte, edge: comEspera });
    await controlador.carregar(ORG);

    const mutation = controlador.ativar(CICLO);
    expect(controlador.estado().operacaoEmAndamento).toBe(true);
    expect(controlador.estado().fase).toBe("pronto");

    liberar({ ok: true, data: { version: 2 } });
    await mutation;

    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });

  it("AE/AF: cancelamento enviado para PLANEJADO e para ATIVO com a versão soberana", async () => {
    const chamadas: { metodo: string; entrada: Record<string, unknown> }[] = [];
    const fonte = repositorio([soberano(CICLO, "PLANEJADO", 1)]);
    const controlador = criarControladorGestaoCiclos({
      repositorio: fonte,
      edge: edgeFalso(undefined, chamadas),
    });
    await controlador.carregar(ORG);

    await controlador.cancelar(CICLO, "Interrupcao"); // PLANEJADO
    controlador.registrarVersao(CICLO, 2);
    await controlador.cancelar(CICLO, "Interrupcao"); // ATIVO (versão nova)

    expect(chamadas.map((c) => c.metodo)).toEqual(["cancelar", "cancelar"]);
    expect(chamadas[0]!.entrada.cycleId).toBe(CICLO);
    expect(chamadas[0]!.entrada.expectedVersion).toBe(1);
    expect(chamadas[1]!.entrada.expectedVersion).toBe(2);
    // Nenhum campo de autoridade atravessa.
    for (const chamada of chamadas) {
      for (const proibido of ["actorId", "authorId", "role", "cargo", "funcao", "papel", "capability", "status"]) {
        expect(chamada.entrada, proibido).not.toHaveProperty(proibido);
      }
    }
  });

  it("sem versão soberana conhecida a mutation é recusada fail-closed", async () => {
    const chamadas: { metodo: string; entrada: Record<string, unknown> }[] = [];
    const controlador = criarControladorGestaoCiclos({
      repositorio: repositorio([]),
      edge: edgeFalso(undefined, chamadas),
    });
    await controlador.carregar(ORG);

    const resultado = await controlador.ativar(CICLO);

    expect(resultado.ok).toBe(false);
    expect(chamadas).toEqual([]);
  });
});

describe("F5-09 P8 — controlador: filtro preservado e geração monotônica (M/S)", () => {
  const CANCELADO_ID = "66666666-6666-4666-8666-666666666666";
  const SO_EM_A = "77777777-7777-4777-8777-777777777777";

  /** Repositório com respostas CONTROLÁVEIS (deferred) para provar concorrência. */
  function fonteControlavel() {
    const pendentes: {
      resolver: (valor: ResultadoCiclos<readonly CicloSoberano[]>) => void;
    }[] = [];
    const fonte = {
      listarCiclos: vi.fn(
        () =>
          new Promise<ResultadoCiclos<readonly CicloSoberano[]>>((resolver) => {
            pendentes.push({ resolver });
          })
      ),
      obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
      obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
    };
    return { fonte, pendentes };
  }

  /** Libera as microtasks/timers pendentes (sem DOM). */
  const tick = () => new Promise<void>((resolver) => setTimeout(resolver, 0));

  it("M1/M2/M3: `incluirCancelados: false` é PRESERVADO no reload pós-mutation", async () => {
    const fonte = repositorio([
      soberano(CICLO, "ATIVO", 3),
      soberano(CANCELADO_ID, "CANCELADO", 1),
    ]);
    const controlador = criarControladorGestaoCiclos({
      repositorio: fonte,
      edge: edgeFalso(),
    });

    // M1: leitura com o filtro DESMARCADO (cancelados fora).
    await controlador.carregar(ORG, { incluirCancelados: false });
    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([CICLO]);

    // M2: mutation com sucesso.
    const resultado = await controlador.ativar(CICLO);
    expect(resultado.ok).toBe(true);

    // M3: o reload reusa o filtro da última leitura (NÃO força `true`).
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(2);
    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([CICLO]);
    expect(controlador.estado().fase).toBe("pronto");
  });

  it("M4/M5/M6: `incluirCancelados: true` é PRESERVADO no reload pós-mutation", async () => {
    const fonte = repositorio([
      soberano(CICLO, "ATIVO", 3),
      soberano(CANCELADO_ID, "CANCELADO", 1),
    ]);
    const controlador = criarControladorGestaoCiclos({
      repositorio: fonte,
      edge: edgeFalso(),
    });

    // M4: leitura com o filtro MARCADO (cancelados dentro).
    await controlador.carregar(ORG, { incluirCancelados: true });
    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([
      CICLO,
      CANCELADO_ID,
    ]);

    // M5: mutation com sucesso.
    const resultado = await controlador.ativar(CICLO);
    expect(resultado.ok).toBe(true);

    // M6: o reload mantém o filtro marcado.
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(2);
    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([
      CICLO,
      CANCELADO_ID,
    ]);
  });

  it("S1–S5: mesma organização — resposta atrasada NÃO substitui a mais recente", async () => {
    const { fonte, pendentes } = fonteControlavel();
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte });

    // A começa com filtro DESMARCADO e fica pendente.
    const leituraA = controlador.carregar(ORG, { incluirCancelados: false });
    // B começa DEPOIS, com filtro diferente, na MESMA organização.
    const leituraB = controlador.carregar(ORG, { incluirCancelados: true });
    expect(pendentes).toHaveLength(2);

    // B resolve primeiro e publica a lista B.
    pendentes[1]!.resolver({ ok: true, data: [soberano(CICLO, "ATIVO", 9)] });
    await leituraB;
    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([CICLO]);

    // A resolve atrasada: a lista A NÃO pode vencer.
    pendentes[0]!.resolver({ ok: true, data: [soberano(SO_EM_A, "PLANEJADO", 1)] });
    await leituraA;

    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([CICLO]);
    expect(controlador.estado().organizacaoId).toBe(ORG);
    expect(controlador.estado().fase).toBe("pronto");
    expect(controlador.estado().erro).toBeNull();
  });

  it("S6: resposta stale NÃO altera o mapa de `expectedVersion`", async () => {
    const { fonte, pendentes } = fonteControlavel();
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte });

    const leituraA = controlador.carregar(ORG);
    const leituraB = controlador.carregar(ORG);
    pendentes[1]!.resolver({ ok: true, data: [soberano(CICLO, "ATIVO", 9)] });
    await leituraB;
    expect(controlador.versaoDe(CICLO)).toBe(9);

    // A traz outra versão e um ciclo que só existe nela: nada disso é registrado.
    pendentes[0]!.resolver({
      ok: true,
      data: [soberano(CICLO, "PLANEJADO", 1), soberano(SO_EM_A, "ATIVO", 1)],
    });
    await leituraA;

    expect(controlador.versaoDe(CICLO)).toBe(9);
    expect(Number.isNaN(controlador.versaoDe(SO_EM_A))).toBe(true);
  });

  it("reload pós-mutation não sobrescreve leitura MAIS RECENTE iniciada depois", async () => {
    const { fonte, pendentes } = fonteControlavel();
    let liberarEdge!: (valor: ResultadoEdgeCiclos<unknown>) => void;
    const edgePendente = new Promise<ResultadoEdgeCiclos<unknown>>((resolver) => {
      liberarEdge = resolver;
    });
    const controlador = criarControladorGestaoCiclos({
      repositorio: fonte,
      edge: edgeFalso(edgePendente as unknown as ResultadoEdgeCiclos<unknown>),
    });

    const primeira = controlador.carregar(ORG, { incluirCancelados: false });
    pendentes[0]!.resolver({ ok: true, data: [soberano(CICLO, "ATIVO", 3)] });
    await primeira;

    // Mutation dispara a Edge e, depois dela, o reload (leitura #2) fica pendente.
    const mutacao = controlador.ativar(CICLO);
    liberarEdge({ ok: true, data: { version: 4 } });
    await tick();
    expect(pendentes).toHaveLength(2);

    // Leitura #3 começa DEPOIS do reload e resolve primeiro.
    const maisRecente = controlador.carregar(ORG, { incluirCancelados: true });
    pendentes[2]!.resolver({
      ok: true,
      data: [soberano(CICLO, "ATIVO", 5), soberano(CANCELADO_ID, "CANCELADO", 2)],
    });
    await maisRecente;
    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([
      CICLO,
      CANCELADO_ID,
    ]);

    // O reload (geração anterior) resolve atrasado e NÃO sobrescreve.
    pendentes[1]!.resolver({ ok: true, data: [soberano(CICLO, "ATIVO", 4)] });
    await mutacao;

    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([
      CICLO,
      CANCELADO_ID,
    ]);
    expect(controlador.versaoDe(CICLO)).toBe(5);
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });

  it("T6: Edge ok + FALHA no reload ⇒ `ok: false` (confirmação indisponível)", async () => {
    let chamadas = 0;
    const fonte = {
      listarCiclos: vi.fn(async (): Promise<ResultadoCiclos<readonly CicloSoberano[]>> => {
        chamadas += 1;
        if (chamadas === 1) return { ok: true, data: [soberano(CICLO, "PLANEJADO", 4)] };
        return {
          ok: false,
          error: { code: "INTERNAL", message: "Não foi possível reler os ciclos agora." },
        };
      }),
      obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
      obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
    };
    const controlador = criarControladorGestaoCiclos({
      repositorio: fonte,
      edge: edgeFalso(),
    });
    await controlador.carregar(ORG, { incluirCancelados: false });
    const antes = controlador.estado().ciclos;

    const resultado = await controlador.ativar(CICLO);

    // A Edge respondeu ok, mas a UI NÃO pode tratar a operação como confirmada.
    expect(resultado.ok).toBe(false);
    const erroConfirmacao = erroDe(resultado);
    expect(erroConfirmacao.code).toBe("INTERNAL");
    expect(erroConfirmacao.message).toContain("não pôde ser confirmado");
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(2);
    expect(controlador.estado().fase).toBe("erro");
    expect(controlador.estado().erro?.code).toBe("INTERNAL");
    // Último estado soberano VÁLIDO preservado (nenhum fallback local).
    expect(controlador.estado().ciclos).toEqual(antes);
    expect(controlador.estado().ciclos.map((c) => c.status)).toEqual(["PLANEJADO"]);
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });
});

describe("F5-09 P8 — controlador: mutation stale, concorrência e confirmação (T1–T8)", () => {
  /** Edge com respostas CONTROLÁVEIS (uma por chamada) e métodos observados. */
  function edgeControlavel() {
    const pendentes: {
      resolver: (valor: ResultadoEdgeCiclos<unknown>) => void;
    }[] = [];
    const metodos: string[] = [];
    const construir = (metodo: string) => async () => {
      metodos.push(metodo);
      return new Promise<ResultadoEdgeCiclos<unknown>>((resolver) => {
        pendentes.push({ resolver });
      });
    };
    const edge = {
      criar: construir("criar"),
      editar: construir("editar"),
      ativar: construir("ativar"),
      encerrar: construir("encerrar"),
      cancelar: construir("cancelar"),
      reabrir: construir("reabrir"),
      corrigirPeriodo: construir("corrigirPeriodo"),
      incluirAdmissao: construir("incluirAdmissao"),
    } as unknown as EdgeCiclos;
    return { edge, pendentes, metodos };
  }

  /** Repositório que responde por organização (ORG e ORG_B). */
  function repositorioPorOrganizacao() {
    return {
      listarCiclos: vi.fn(
        async (
          organizationId: string
        ): Promise<ResultadoCiclos<readonly CicloSoberano[]>> => ({
          ok: true,
          data:
            organizationId === ORG_B
              ? [soberano(CICLO, "ATIVO", 7)]
              : [soberano(CICLO, "PLANEJADO", 3)],
        })
      ),
      obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
      obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
    };
  }

  it("T1: erro tardio da mutation de A não publica nada em B", async () => {
    const fonte = repositorioPorOrganizacao();
    const { edge, pendentes } = edgeControlavel();
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte, edge });

    await controlador.carregar(ORG, { incluirCancelados: false });
    const mutacaoA = controlador.ativar(CICLO);
    expect(controlador.estado().operacaoEmAndamento).toBe(true);

    // Contexto muda para B (invalida a geração da mutation de A).
    await controlador.carregar(ORG_B, { incluirCancelados: false });
    expect(controlador.estado().organizacaoId).toBe(ORG_B);
    expect(controlador.estado().operacaoEmAndamento).toBe(false);

    // A falha DEPOIS da troca: nada de A aparece no contexto B.
    pendentes[0]!.resolver({
      ok: false,
      error: { code: "CONFLICT", message: "estado atual da organização A" },
    });
    const resultadoA = await mutacaoA;

    expect(resultadoA.ok).toBe(false);
    expect(erroDe(resultadoA).message).toContain("organização ativa mudou");
    expect(controlador.estado().organizacaoId).toBe(ORG_B);
    expect(controlador.estado().fase).toBe("pronto");
    expect(controlador.estado().erro).toBeNull();
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });

  it("T2: sucesso tardio da mutation de A não faz reload nem publica em B", async () => {
    const fonte = repositorioPorOrganizacao();
    const { edge, pendentes } = edgeControlavel();
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte, edge });

    await controlador.carregar(ORG, { incluirCancelados: false });
    const mutacaoA = controlador.ativar(CICLO);
    await controlador.carregar(ORG_B, { incluirCancelados: false });
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(2);

    pendentes[0]!.resolver({ ok: true, data: { version: 4 } });
    const resultadoA = await mutacaoA;

    // Nenhum reload de A sobre B: a contagem de leituras não cresceu.
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(2);
    expect(resultadoA.ok).toBe(false);
    expect(controlador.estado().organizacaoId).toBe(ORG_B);
    expect(controlador.estado().fase).toBe("pronto");
    expect(controlador.estado().erro).toBeNull();
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });

  it("T3: mutation antiga não encerra a mutation mais recente (flag de B intacta)", async () => {
    const fonte = repositorioPorOrganizacao();
    const { edge, pendentes } = edgeControlavel();
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte, edge });

    await controlador.carregar(ORG);
    const mutacaoA = controlador.ativar(CICLO);
    await controlador.carregar(ORG_B);
    expect(controlador.estado().operacaoEmAndamento).toBe(false);

    // Nova mutation VÁLIDA no contexto B.
    const mutacaoB = controlador.ativar(CICLO);
    expect(controlador.estado().operacaoEmAndamento).toBe(true);
    expect(pendentes).toHaveLength(2);

    // A resolve atrasada e NÃO pode desligar a flag de B.
    pendentes[0]!.resolver({ ok: true, data: { version: 4 } });
    expect((await mutacaoA).ok).toBe(false);
    expect(controlador.estado().operacaoEmAndamento).toBe(true);
    expect(controlador.estado().organizacaoId).toBe(ORG_B);

    // B conclui: agora a flag cai e a confirmação é de B.
    pendentes[1]!.resolver({ ok: true, data: { version: 8 } });
    expect((await mutacaoB).ok).toBe(true);
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
    expect(controlador.estado().organizacaoId).toBe(ORG_B);
    expect(controlador.estado().fase).toBe("pronto");
  });

  it("T4: segunda mutation no MESMO contexto é recusada fail-closed (Edge 1×)", async () => {
    const fonte = repositorio([soberano(CICLO, "PLANEJADO", 3)]);
    const { edge, pendentes, metodos } = edgeControlavel();
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte, edge });

    await controlador.carregar(ORG);
    const primeira = controlador.ativar(CICLO);
    const segunda = await controlador.ativar(CICLO);

    expect(segunda.ok).toBe(false);
    const erroSegunda = erroDe(segunda);
    expect(erroSegunda.code).toBe("CONFLICT");
    expect(erroSegunda.message).toContain("em andamento");
    // A Edge foi chamada SOMENTE pela primeira mutation.
    expect(metodos).toHaveLength(1);
    expect(controlador.estado().operacaoEmAndamento).toBe(true);

    pendentes[0]!.resolver({ ok: true, data: { version: 4 } });
    expect((await primeira).ok).toBe(true);
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });

  it("T5: Edge ok + reload ok ⇒ resultado final continua `ok: true`", async () => {
    const fonte = repositorio([soberano(CICLO, "ATIVO", 6)]);
    const controlador = criarControladorGestaoCiclos({
      repositorio: fonte,
      edge: edgeFalso(),
    });
    await controlador.carregar(ORG);

    const resultado = await controlador.ativar(CICLO);

    expect(resultado.ok).toBe(true);
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(2);
    expect(controlador.estado().fase).toBe("pronto");
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });

  it("T7: Edge falha ⇒ `ok: false` e estado soberano anterior preservado", async () => {
    const fonte = repositorio([soberano(CICLO, "ATIVO", 4)]);
    const controlador = criarControladorGestaoCiclos({
      repositorio: fonte,
      edge: edgeFalso({
        ok: false,
        error: { code: "CONFLICT", message: "estado atual" },
      }),
    });
    await controlador.carregar(ORG);
    const antes = controlador.estado().ciclos;

    const resultado = await controlador.encerrar(CICLO, "Fim de ciclo");

    expect(resultado.ok).toBe(false);
    expect(erroDe(resultado).code).toBe("CONFLICT");
    expect(controlador.estado().ciclos).toEqual(antes);
    expect(controlador.estado().erro?.code).toBe("CONFLICT");
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
    // Falha da Edge não dispara reload.
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(1);
  });

  it("T8: `descartar()` durante a mutation — resposta posterior não publica nada", async () => {
    const fonte = repositorio([soberano(CICLO, "PLANEJADO", 3)]);
    const { edge, pendentes } = edgeControlavel();
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte, edge });

    await controlador.carregar(ORG);
    const mutacao = controlador.ativar(CICLO);
    expect(controlador.estado().operacaoEmAndamento).toBe(true);

    controlador.descartar();
    expect(controlador.estado().fase).toBe("ocioso");
    expect(controlador.estado().operacaoEmAndamento).toBe(false);

    pendentes[0]!.resolver({ ok: true, data: { version: 4 } });
    const resultado = await mutacao;

    expect(resultado.ok).toBe(false);
    expect(controlador.estado().fase).toBe("ocioso");
    expect(controlador.estado().organizacaoId).toBeNull();
    expect(controlador.estado().ciclos).toEqual([]);
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
    // Nenhum reload disparado pela mutation descartada.
    expect(fonte.listarCiclos).toHaveBeenCalledTimes(1);
  });
  it("T9: mutation em A + `carregar(null)` + erro tardio não publica no contexto vazio", async () => {
    const fonte = repositorioPorOrganizacao();
    const { edge, pendentes } = edgeControlavel();
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte, edge });

    await controlador.carregar(ORG, { incluirCancelados: false });
    const mutacaoA = controlador.ativar(CICLO);
    expect(controlador.estado().operacaoEmAndamento).toBe(true);

    // Contexto passa a SEM organização (fail-closed), invalidando a mutation de A.
    const semOrganizacao = await controlador.carregar(null);
    expect(semOrganizacao.ok).toBe(false);
    expect(controlador.estado().organizacaoId).toBeNull();
    expect(controlador.estado().ciclos).toEqual([]);
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
    expect(controlador.estado().erro?.code).toBe("FORBIDDEN");

    // Erro tardio da mutation de A: nada substitui o contexto/erro atuais.
    pendentes[0]!.resolver({
      ok: false,
      error: { code: "CONFLICT", message: "estado atual da organização A" },
    });
    const resultadoA = await mutacaoA;

    expect(resultadoA.ok).toBe(false);
    expect(erroDe(resultadoA).message).toContain("organização ativa mudou");
    expect(controlador.estado().organizacaoId).toBeNull();
    expect(controlador.estado().ciclos).toEqual([]);
    expect(controlador.estado().fase).toBe("erro");
    expect(controlador.estado().erro?.code).toBe("FORBIDDEN");
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });

  it("T10: mutation em A + `carregar(null)` + sucesso tardio não reintroduz o contexto A", async () => {
    const fonte = repositorioPorOrganizacao();
    const { edge, pendentes } = edgeControlavel();
    const controlador = criarControladorGestaoCiclos({ repositorio: fonte, edge });

    await controlador.carregar(ORG, { incluirCancelados: false });
    const leiturasAposContextoA = fonte.listarCiclos.mock.calls.length;
    const mutacaoA = controlador.ativar(CICLO);
    await controlador.carregar(null);
    expect(fonte.listarCiclos.mock.calls.length).toBe(leiturasAposContextoA);

    pendentes[0]!.resolver({ ok: true, data: { version: 4 } });
    const resultadoA = await mutacaoA;

    // Contexto obsoleto: devolve CONFLICT e NÃO relê A.
    expect(resultadoA.ok).toBe(false);
    expect(erroDe(resultadoA).code).toBe("CONFLICT");
    expect(erroDe(resultadoA).message).toContain("organização ativa mudou");
    expect(fonte.listarCiclos.mock.calls.length).toBe(leiturasAposContextoA);
    expect(controlador.estado().organizacaoId).toBeNull();
    expect(controlador.estado().ciclos).toEqual([]);
    expect(controlador.estado().fase).toBe("erro");
    expect(controlador.estado().operacaoEmAndamento).toBe(false);
  });
});

describe("F5-09 P8 — controlador: ausência de autoridade local (X/Y/Z/AG/AH)", () => {
  /** Código sem comentários (os cabeçalhos documentam o que NÃO é feito). */
  function codigoSemComentarios(codigo: string): string {
    return codigo
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .split("\n")
      .map((linha) => {
        const indice = linha.indexOf("//");
        return indice === -1 ? linha : linha.slice(0, indice);
      })
      .join("\n");
  }

  it("X/AH: o módulo do controlador e o da gestão não tocam storage local nem RPC direta", () => {
    const fontes = [controladorFonte as string, gestaoFonte as string].map(codigoSemComentarios);

    for (const fonte of fontes) {
      expect(fonte).not.toContain("cicloAvaliacaoStorage");
      expect(fonte).not.toContain("localCycleRepository");
      expect(fonte).not.toContain("localStorage");
      expect(fonte).not.toContain(".rpc(");
    }
  });

  it("Y/Z/AA: o controlador não expõe exclusão física nem configuração de metas", () => {
    const controlador = criarControladorGestaoCiclos({
      repositorio: repositorio([]),
      edge: edgeFalso(),
    });
    const acoes = Object.keys(controlador);

    for (const proibida of ["excluir", "excluirCiclo", "delete", "remover"]) {
      expect(acoes, proibida).not.toContain(proibida);
    }
    for (const metas of ["atualizarMetas", "quantidadeMetasNegocio", "quantidadeMetasIndividuais"]) {
      expect(acoes, metas).not.toContain(metas);
    }
    // Histórico detalhado não é fornecido pelo modelo soberano desta fase.
    expect(acoes).not.toContain("historico");
  });
});
