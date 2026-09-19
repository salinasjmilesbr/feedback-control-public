import { describe, expect, it, vi } from "vitest";
import acessoFonte from "../acessoCiclosSoberanos.ts?raw";
import edgeFonte from "../../infrastructure/supabase/ciclos/edgeCiclos.ts?raw";
import repositorioFonte from "../../infrastructure/supabase/ciclos/repositorioCiclosSoberanos.ts?raw";
import paginaFonte from "../../pages/CiclosAvaliacaoPage.tsx?raw";
import {
  DEFINICAO_POR_OPERACAO,
  OPERACOES_CICLO,
} from "../../infrastructure/supabase/ciclos/contrato";
import type { CicloSoberano, ResultadoCiclos } from "../../application/ports/CycleRepository";
import type { EdgeCiclos, ResultadoEdgeCiclos } from "../../infrastructure/supabase/ciclos/edgeCiclos";
import { instalarLocalStorageEmMemoria } from "../../test/localStorageMock";
import { criarControladorGestaoCiclos } from "./controladorGestaoCiclos";
import controladorFonte from "./controladorGestaoCiclos.ts?raw";
import {
  criarGestaoCiclosSoberanos,
  novoOperationId,
} from "./gestaoCiclosSoberanos";
import gestaoFonte from "./gestaoCiclosSoberanos.ts?raw";

/**
 * F5-09/P9 — MATRIZ INTEGRADA (lado cliente).
 *
 * A P9 é validação integrada: aqui ficam as provas que NÃO dependem de
 * PostgreSQL (as provas de cross-tenant/IDOR/membership/capability/stale/
 * concorrência real/idempotência/rollback/auditoria/RLS vivem nos validadores
 * SQL 14–18). Este arquivo cobre:
 *   - contrato das 8 operações e do mapa operação -> gate -> capability;
 *   - caminho ÚNICO de mutation (página -> controlador -> gestão -> Edge) sem
 *     `.rpc(`, sem storage local, sem UUID de ciclo no cliente;
 *   - `operationId` como CHAVE DE IDEMPOTÊNCIA (nunca identidade funcional);
 *   - ausência de dual-read/dual-write/fallback local no caminho soberano;
 *   - ausência de antecipação de F5-10 (metas) e F5-11 (observações);
 *   - regressões P5–P8 (gerações de leitura/mutation, filtro preservado,
 *     fail-closed sem caminho soberano).
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";

/** Código sem comentários: os cabeçalhos citam, por texto, o que NÃO é feito. */
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

const CAMINHO_SOBERANO = [
  ["pagina", paginaFonte as string],
  ["controlador", controladorFonte as string],
  ["gestao", gestaoFonte as string],
  ["acesso", acessoFonte as string],
  ["repositorio", repositorioFonte as string],
  ["edge", edgeFonte as string],
] as const;

const OPERACOES_ESPERADAS = [
  "cycle.historico.listar",
  "cycle.criar",
  "cycle.editar",
  "cycle.ativar",
  "cycle.encerrar",
  "cycle.cancelar",
  "cycle.reabrir",
  "cycle.corrigir_periodo",
  "cycle.admissao.incluir",
] as const;

function soberano(id: string, status: CicloSoberano["status"], version: number): CicloSoberano {
  return {
    id,
    organizationId: ORG,
    ano: 2042,
    numero: 1,
    status,
    dataInicio: "2042-01-01",
    dataFim: "2042-03-31",
    dataAtivacao: null,
    dataEncerramento: null,
    encerradoComPendencias: false,
    quantidadePendencias: 0,
    version,
    criadoEm: "2042-01-01T00:00:00.000Z",
    atualizadoEm: "2042-01-01T00:00:00.000Z",
  };
}

function repositorioFake(ciclos: readonly CicloSoberano[]) {
  return {
    listarCiclos: vi.fn(async (): Promise<ResultadoCiclos<readonly CicloSoberano[]>> => ({
      ok: true,
      data: ciclos,
    })),
    obterCiclo: vi.fn(async () => ({ ok: true as const, data: null })),
    obterCicloAtivo: vi.fn(async () => ({ ok: true as const, data: null })),
    listarEventos: vi.fn(async () => ({ ok: true as const, data: [] })),
  };
}

function edgeGravador(chamadas: { metodo: string; entrada: Record<string, unknown> }[]): EdgeCiclos {
  const registrar = (metodo: string) => async (entrada: unknown) => {
    chamadas.push({ metodo, entrada: entrada as Record<string, unknown> });
    return { ok: true, data: { version: 9 } } satisfies ResultadoEdgeCiclos<unknown>;
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
    listarHistorico: registrar("listarHistorico"),
  } as unknown as EdgeCiclos;
}

describe("F5-09 P9 — matriz integrada: contrato das operações e capabilities", () => {
  it("P9-1: existem EXATAMENTE as 8 operações contratadas, com o gate/capability do contrato", () => {
    expect([...OPERACOES_CICLO].sort()).toEqual([...OPERACOES_ESPERADAS].sort());

    const esperado: Record<string, string> = {
      "cycle.historico.listar": "cycle.read",
      "cycle.criar": "cycle.manage",
      "cycle.editar": "cycle.manage",
      "cycle.ativar": "cycle.manage",
      "cycle.encerrar": "cycle.manage",
      "cycle.admissao.incluir": "cycle.manage",
      "cycle.cancelar": "cycle.cancel",
      "cycle.reabrir": "cycle.reopen",
      "cycle.corrigir_periodo": "cycle.period.correct",
    };
    for (const operacao of OPERACOES_ESPERADAS) {
      expect(DEFINICAO_POR_OPERACAO[operacao]!.capability, operacao).toBe(esperado[operacao]);
    }
    // `cycle.criar` é o ÚNICO gate administrativo (plano administrativo, D19/D21).
    expect(DEFINICAO_POR_OPERACAO["cycle.criar"]!.gate).toBe("administrativo");
    for (const operacao of OPERACOES_ESPERADAS) {
      if (operacao === "cycle.criar") continue;
      expect(DEFINICAO_POR_OPERACAO[operacao]!.gate, operacao).toBe("funcional");
    }
  });

  it("P9-2: NENHUMA operação/capability de metas (F5-10) ou observações (F5-11) foi antecipada", () => {
    for (const operacao of OPERACOES_CICLO) {
      expect(operacao).not.toMatch(/meta|goal|observac|observ/i);
    }
    for (const definicao of Object.values(DEFINICAO_POR_OPERACAO)) {
      expect(definicao.capability).not.toMatch(/meta|goal|observac/i);
    }
    for (const [, fonte] of CAMINHO_SOBERANO) {
      const codigo = codigoSemComentarios(fonte);
      for (const proibido of ["cycle_goals", "cycle_goal", "meta_ciclo", "observac"]) {
        expect(codigo, proibido).not.toContain(proibido);
      }
    }
  });
});

describe("F5-09 P9 — matriz integrada: caminho único de leitura e mutation", () => {
  it("P9-3: a página não fala com o banco nem com storage local (só com o controlador)", () => {
    const codigo = codigoSemComentarios(paginaFonte as string);
    for (const proibido of [
      ".rpc(",
      "functions.invoke",
      "localStorage",
      "sessionStorage",
      "localCycleRepository",
      "crypto.randomUUID",
    ]) {
      expect(codigo, proibido).not.toContain(proibido);
    }
    expect(codigo).toContain("criarControladorGestaoCiclos");
  });

  it("P9-4: `functions.invoke` aparece SÓ no adapter da Edge e nenhuma camada soberana usa storage local", () => {
    expect(codigoSemComentarios(edgeFonte as string)).toContain("functions.invoke");
    for (const [nome, fonte] of CAMINHO_SOBERANO) {
      if (nome === "edge") continue;
      const codigo = codigoSemComentarios(fonte);
      expect(codigo, nome).not.toContain("functions.invoke");
      expect(codigo, nome).not.toContain("localStorage");
      expect(codigo, nome).not.toContain("localCycleRepository");
      expect(codigo, nome).not.toContain(".rpc(");
    }
  });

  it("P9-5: a composição exige o caminho soberano (sem Edge/cliente ⇒ fail-closed, sem fallback)", async () => {
    const gestao = criarGestaoCiclosSoberanos({ cliente: null });
    const resultado = await gestao.listar(ORG);

    expect(resultado.ok).toBe(false);
    if (resultado.ok) throw new Error("esperava falha fail-closed");
    expect(typeof resultado.error.code).toBe("string");
    // Nenhuma superfície de escrita local foi criada para "compensar".
    expect(Object.keys(gestao)).not.toContain("salvarLocalmente");
  });
});

describe("F5-09 P9 — matriz integrada: idempotência e ausência de dual-write", () => {
  it("P9-6: `operationId` é chave de idempotência (única por chamada) e a identidade é o UUID do ciclo", async () => {
    const chamadas: { metodo: string; entrada: Record<string, unknown> }[] = [];
    const controlador = criarControladorGestaoCiclos({
      repositorio: repositorioFake([soberano(CICLO, "PLANEJADO", 4)]),
      edge: edgeGravador(chamadas),
    });
    await controlador.carregar(ORG);

    await controlador.editar({
      cicloId: CICLO,
      ano: 2042,
      numero: 1,
      dataInicio: "2042-02-01",
      dataFim: "2042-04-30",
    });
    await controlador.ativar(CICLO);

    const ids = chamadas.map((c) => c.entrada.operationId);
    expect(ids).toHaveLength(2);
    expect(ids[0]).not.toBe(ids[1]);
    for (const id of ids) {
      expect(typeof id).toBe("string");
      expect(id as string).toMatch(/^[0-9a-f-]{36}$/i);
    }
    // Identidade funcional continua sendo o UUID soberano — nunca o operationId.
    expect(chamadas[0]!.entrada.cycleId).toBe(CICLO);
    expect(chamadas[0]!.entrada.expectedVersion).toBe(4);
    expect(ids[0]).not.toBe(CICLO);
    // A Edge recebe INTENÇÃO: nenhum campo de autoridade viaja no payload.
    for (const chamada of chamadas) {
      for (const proibido of ["actor", "role", "cargo", "funcao", "capability", "status"]) {
        expect(chamada.entrada, proibido).not.toHaveProperty(proibido);
      }
    }
  });

  it("P9-7: mutation soberana NÃO escreve em storage local (sem dual-write)", async () => {
    const armazenamento = instalarLocalStorageEmMemoria();
    const gravacoes: string[] = [];
    const setItemOriginal = armazenamento.setItem.bind(armazenamento);
    armazenamento.setItem = (chave: string, valor: string) => {
      gravacoes.push(chave);
      setItemOriginal(chave, valor);
    };

    const controlador = criarControladorGestaoCiclos({
      repositorio: repositorioFake([soberano(CICLO, "PLANEJADO", 2)]),
      edge: edgeGravador([]),
    });
    await controlador.carregar(ORG);
    await controlador.ativar(CICLO);

    expect(gravacoes).toEqual([]);
    expect(armazenamento.length).toBe(0);
  });

  it("P9-8: `novoOperationId` é UUID v4 sintético e distinto a cada chamada", () => {
    const ids = new Set([novoOperationId(), novoOperationId(), novoOperationId()]);
    expect(ids.size).toBe(3);
    for (const id of ids) {
      expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
    }
  });
});

describe("F5-09 P9 — matriz integrada: regressões P5–P8 preservadas", () => {
  it("P9-9: as gerações monotônicas (leitura e mutation) e o filtro preservado seguem no controlador", () => {
    const codigo = codigoSemComentarios(controladorFonte as string);
    for (const simbolo of [
      "geracaoDeLeitura",
      "geracaoDeMutacao",
      "mutationCorrente",
      "invalidarMutacoesEmVoo",
      "opcoesLeituraAtuais",
      "MSG_CONFIRMACAO_INDISPONIVEL",
    ]) {
      expect(codigo, simbolo).toContain(simbolo);
    }
  });

  it("P9-10: a leitura soberana continua vindo do repositório RLS (P5) e a mutation da Edge (P7)", () => {
    const gestao = codigoSemComentarios(gestaoFonte as string);
    expect(gestao).toContain("controlador.carregar");
    expect(gestao).toContain("projetarCicloParaUi");
    const acesso = codigoSemComentarios(acessoFonte as string);
    expect(acesso).toContain("criarRepositorioCiclosSoberanos");
    // O repositório soberano é RLS/PostgREST: nada de RPC direta no browser.
    const repositorio = codigoSemComentarios(repositorioFonte as string);
    expect(repositorio).toContain("listarCiclos");
    expect(repositorio).not.toContain(".rpc(");
    expect(repositorio).toContain("evaluation_cycles");
  });
});
