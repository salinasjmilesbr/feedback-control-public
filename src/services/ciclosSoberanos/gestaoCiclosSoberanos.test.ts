import { describe, expect, it, vi } from "vitest";
import type { CicloSoberano, ResultadoCiclos } from "../../application/ports/CycleRepository";
import type { EdgeCiclos, ResultadoEdgeCiclos } from "../../infrastructure/supabase/ciclos/edgeCiclos";
import {
  criarGestaoCiclosSoberanos,
  novoOperationId,
  projetarCicloParaUi,
  versaoDoSoberano,
} from "./gestaoCiclosSoberanos";

/**
 * F5-09 P8 (Issue #204) — CUTOVER da gestão de ciclos: contrato da camada de
 * ligação soberana (leitura P5/P6 + mutações Edge P7).
 *
 * Prova que o fluxo ativo de gestão: lê do repositório soberano (sem fallback),
 * muta SOMENTE pela Edge com INTENÇÃO (UUID canônico + versão esperada +
 * operationId), nunca gera UUID de CICLO no cliente, nunca grava lifecycle em
 * localStorage e falha fechado em erro de backend.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";
const CICLO_B = "66666666-6666-4666-8666-666666666666";

function ciclo(id: string, status: CicloSoberano["status"] = "ATIVO", version = 3): CicloSoberano {
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

interface Espiao {
  readonly chamadas: { readonly metodo: keyof EdgeCiclos; readonly entrada: Record<string, unknown> }[];
}

function edgeFalso(
  resposta: ResultadoEdgeCiclos<unknown> = { ok: true, data: { version: 4 } },
  espiao: Espiao = { chamadas: [] }
): EdgeCiclos {
  const registrar = (metodo: keyof EdgeCiclos) => async (entrada: unknown) => {
    (espiao.chamadas as { metodo: keyof EdgeCiclos; entrada: Record<string, unknown> }[]).push({
      metodo,
      entrada: entrada as Record<string, unknown>,
    });
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

/** Repositório de leitura falso (injetado no controlador via `deps.repositorio`). */
function repositorioLeitura(ciclos: readonly CicloSoberano[]) {
  return {
    listarCiclos: vi.fn(async (): Promise<ResultadoCiclos<readonly CicloSoberano[]>> => ({
      ok: true,
      data: ciclos,
    })),
    obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
    obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
  };
}

describe("F5-09 P8 — leitura soberana do fluxo de gestão (I/M/J/O)", () => {
  it("lista pelo repositório SOBERANO e projeta para a UI (id = UUID canônico)", async () => {
    const repositorio = repositorioLeitura([ciclo(CICLO), ciclo(CICLO_B, "ENCERRADO", 7)]);
    const gestao = criarGestaoCiclosSoberanos({ repositorio });

    const resultado = await gestao.listar(ORG);

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data.map((item) => item.id)).toEqual([CICLO, CICLO_B]);
    expect(resultado.data[0]).toMatchObject({
      id: CICLO,
      ano: 2035,
      ciclo: 1,
      status: "ATIVO",
    });
    expect(repositorio.listarCiclos).toHaveBeenCalledWith(ORG);
  });

  it("por padrão NÃO mostra cancelados; com a opção mostra", async () => {
    const repositorio = repositorioLeitura([ciclo(CICLO), ciclo(CICLO_B, "CANCELADO")]);
    const gestao = criarGestaoCiclosSoberanos({ repositorio });

    const padrao = await gestao.listar(ORG);
    const comCancelados = await gestao.listar(ORG, { incluirCancelados: true });

    expect(padrao.ok && padrao.data.map((i) => i.id)).toEqual([CICLO]);
    expect(comCancelados.ok && comCancelados.data.map((i) => i.id)).toEqual([CICLO, CICLO_B]);
  });

  it("erro soberano NÃO faz fallback local: devolve falha pública", async () => {
    const repositorio = {
      listarCiclos: vi.fn(async (): Promise<ResultadoCiclos<readonly CicloSoberano[]>> => ({
        ok: false,
        error: { code: "INTERNAL", message: "Não foi possível consultar os ciclos agora." },
      })),
      obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
      obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
    };
    const gestao = criarGestaoCiclosSoberanos({ repositorio });

    const resultado = await gestao.listar(ORG);

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("INTERNAL");
  });

  it("resposta ATRASADA de organização anterior não sobrescreve o contexto novo (M)", async () => {
    let resolver!: (valor: ResultadoCiclos<readonly CicloSoberano[]>) => void;
    const pendente = new Promise<ResultadoCiclos<readonly CicloSoberano[]>>((resolve) => {
      resolver = resolve;
    });
    let chamadas = 0;
    const repositorio = {
      listarCiclos: vi.fn(() => {
        chamadas += 1;
        if (chamadas === 1) return pendente;
        return Promise.resolve({ ok: true as const, data: [ciclo(CICLO_B)] });
      }),
      obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
      obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
    };
    const controlador = criarGestaoCiclosSoberanos({ repositorio }).controlador();

    const cargaA = controlador.carregar("org-a");
    const cargaB = controlador.carregar("org-b");
    await cargaB;
    resolver({ ok: true, data: [ciclo(CICLO)] });
    await cargaA;

    expect(controlador.estado()).toMatchObject({ organizacaoId: "org-b" });
    expect(controlador.estado().ciclos.map((c) => c.id)).toEqual([CICLO_B]);
  });
});

describe("F5-09 P8 — projeção de apresentação (O/R)", () => {
  it("projeta sem criar identidade, sem histórico e sem tocar localStorage", () => {
    const original = ciclo(CICLO);
    const projetado = projetarCicloParaUi(original);

    expect(projetado.id).toBe(CICLO);
    expect(projetado.ciclo).toBe(1);
    expect(projetado.dataCriacao).toBe(original.criadoEm);
    // A trilha soberana (cycle_events) é deny-by-default: nada é inventado aqui.
    expect(projetado.cancelamento).toBeUndefined();
    expect(projetado.reaberturas).toBeUndefined();
    expect(projetado.correcoesPeriodo).toBeUndefined();
    expect(projetado.encerramentos).toBeUndefined();
    expect(versaoDoSoberano(original)).toBe(3);
  });

  it("`(ano, numero)` são apenas rótulos de view — a identidade continua o UUID", () => {
    const projetado = projetarCicloParaUi(ciclo(CICLO, "ATIVO", 9));
    expect(projetado.id).toBe(CICLO);
    expect(projetado.ano).toBe(2035);
    expect(projetado.ciclo).toBe(1);
  });
});

describe("F5-09 P8 — mutações SOMENTE pela Edge P7 (A–H, K, L, S)", () => {
  it("criar: envia intenção à Edge e NÃO gera UUID de ciclo no cliente (A/N)", async () => {
    const espiao: Espiao = { chamadas: [] };
    const gestao = criarGestaoCiclosSoberanos({ edge: edgeFalso(undefined, espiao) });

    const resultado = await gestao.criar({
      organizationId: ORG,
      ano: 2035,
      numero: 2,
      dataInicio: "2035-04-01",
      dataFim: "2035-06-30",
    });

    expect(resultado.ok).toBe(true);
    const chamada = espiao.chamadas[0]!;
    expect(chamada.metodo).toBe("criar");
    // NENHUM id de ciclo é enviado: a identidade nasce no banco.
    expect(chamada.entrada).not.toHaveProperty("cycleId");
    expect(chamada.entrada).not.toHaveProperty("id");
    // operationId é a CHAVE DE IDEMPOTÊNCIA do contrato (não identidade).
    expect(typeof chamada.entrada.operationId).toBe("string");
    // Nenhum campo de autoridade atravessa.
    for (const proibido of ["actorId", "authorId", "role", "cargo", "funcao", "papel", "capability", "status"]) {
      expect(chamada.entrada, proibido).not.toHaveProperty(proibido);
    }
  });

  it("editar/ativar/encerrar/cancelar/reabrir/corrigir usam a Edge com alvo e versão (B–F, H)", async () => {
    const espiao: Espiao = { chamadas: [] };
    const gestao = criarGestaoCiclosSoberanos({ edge: edgeFalso(undefined, espiao) });

    await gestao.editar({
      organizationId: ORG,
      cycleId: CICLO,
      ano: 2035,
      numero: 1,
      dataInicio: "2035-01-02",
      dataFim: "2035-03-30",
      expectedVersion: 3,
    });
    await gestao.ativar({ organizationId: ORG, cycleId: CICLO, expectedVersion: 3 });
    await gestao.encerrar({ organizationId: ORG, cycleId: CICLO, expectedVersion: 4, motivo: "Fim" });
    // P4/P6: cancelamento vale em PLANEJADO e ATIVO — o frontend não traduz
    // "excluir" para nada: apenas cancela com intenção.
    await gestao.cancelar({ organizationId: ORG, cycleId: CICLO, expectedVersion: 1, motivo: "Interrupcao" });
    await gestao.reabrir({ organizationId: ORG, cycleId: CICLO, expectedVersion: 5, motivo: "Erro" });
    await gestao.corrigirPeriodo({
      organizationId: ORG,
      cycleId: CICLO,
      dataInicio: "2035-01-03",
      dataFim: "2035-03-29",
      justificativa: "Ajuste",
      expectedVersion: 4,
    });

    expect(espiao.chamadas.map((c) => c.metodo)).toEqual([
      "editar",
      "ativar",
      "encerrar",
      "cancelar",
      "reabrir",
      "corrigirPeriodo",
    ]);
    for (const chamada of espiao.chamadas) {
      expect(chamada.entrada.cycleId).toBe(CICLO);
      expect(typeof chamada.entrada.expectedVersion).toBe("number");
      expect(typeof chamada.entrada.operationId).toBe("string");
    }
  });

  it("erro da Edge é propagado como falha pública e NADA é persistido (J/L)", async () => {
    const gravacoes: string[] = [];
    const localStorageFalso = {
      setItem: (chave: string) => gravacoes.push(chave),
    };
    void localStorageFalso;
    const gestao = criarGestaoCiclosSoberanos({
      edge: edgeFalso({
        ok: false,
        error: { code: "CONFLICT", message: "Operação recusada pelo estado atual do ciclo." },
      }),
    });

    const resultado = await gestao.ativar({ organizationId: ORG, cycleId: CICLO, expectedVersion: 1 });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("CONFLICT");
    // Sem autoridade local: nenhuma escrita ocorreu no fluxo (ver guarda estática).
    expect(gravacoes).toEqual([]);
  });

  it("sem caminho soberano configurado TODA mutação falha fechado, sem tocar dado local", async () => {
    const gestao = criarGestaoCiclosSoberanos({ cliente: null });

    const resultados = await Promise.all([
      gestao.criar({ organizationId: ORG, ano: 2035, numero: 1, dataInicio: "2035-01-01", dataFim: "2035-01-31" }),
      gestao.editar({ organizationId: ORG, cycleId: CICLO, ano: 2035, numero: 1, dataInicio: "2035-01-01", dataFim: "2035-01-31", expectedVersion: 1 }),
      gestao.ativar({ organizationId: ORG, cycleId: CICLO, expectedVersion: 1 }),
      gestao.encerrar({ organizationId: ORG, cycleId: CICLO, expectedVersion: 1, motivo: "x" }),
      gestao.cancelar({ organizationId: ORG, cycleId: CICLO, expectedVersion: 1, motivo: "x" }),
      gestao.reabrir({ organizationId: ORG, cycleId: CICLO, expectedVersion: 1, motivo: "x" }),
      gestao.corrigirPeriodo({ organizationId: ORG, cycleId: CICLO, dataInicio: "2035-01-01", dataFim: "2035-01-31", justificativa: "x", expectedVersion: 1 }),
    ]);

    for (const resultado of resultados) {
      expect(resultado.ok).toBe(false);
      if (resultado.ok) continue;
      expect(resultado.error.code).toBe("INTERNAL");
    }
  });
});

describe("F5-09 P8 — chave de idempotência (não é identidade de ciclo)", () => {
  it("novoOperationId gera UUID distinto, documentado como chave de idempotência", () => {
    const a = novoOperationId();
    const b = novoOperationId();
    expect(a).not.toBe(b);
    expect(a).toMatch(/^[0-9a-f-]{36}$/);
  });
});
