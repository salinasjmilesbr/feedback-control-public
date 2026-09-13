import { describe, expect, it, vi } from "vitest";
import controladorFonte from "./controladorGestaoCiclos.ts?raw";
import gestaoFonte from "./gestaoCiclosSoberanos.ts?raw";
import type { CicloSoberano, ResultadoCiclos } from "../../application/ports/CycleRepository";
import type { EdgeCiclos, ResultadoEdgeCiclos } from "../../infrastructure/supabase/ciclos/edgeCiclos";
import { criarControladorGestaoCiclos } from "./controladorGestaoCiclos";

/**
 * F5-09 P8 (Issue #204) — CONTROLADOR de UI da gestão de ciclos (opção B).
 *
 * Testes COMPORTAMENTAIS em node (sem DOM/jsdom), cobrindo o que a página
 * assíncrona precisa provar: loading (AI), erro soberano sem fallback (AJ),
 * resposta obsoleta de organização anterior (AK), reload após sucesso (AC),
 * falha preservando o estado anterior (AD), botões que não presumem sucesso
 * (AL), cancelamento de PLANEJADO e ATIVO (AE/AF) — além de ausência de delete
 * físico, de metas e de autoridade local (X/Y/Z) e ausência de RPC direta (AG).
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
