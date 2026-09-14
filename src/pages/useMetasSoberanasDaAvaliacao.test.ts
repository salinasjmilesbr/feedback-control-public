/**
 * F5-10 P6 (Issue #220) — REGRESSÃO do achado HIGH da auditoria do PR #228.
 *
 * As metas DO AVALIADO são recortadas por `collaboratorId` (+ `!excluida`); a
 * `relacao` diz apenas COMO o ator está autorizado. Exigir `relacao === "SELF"`
 * descartava metas legítimas do avaliado quando o ator é o APROVADOR CONGELADO
 * dele (feedback de terceiro autorizado) e produzia falso estado benigno de
 * "sem pendências" no formulário.
 *
 * O projeto não tem ambiente DOM (nenhum `jsdom` instalado) e o
 * `renderToStaticMarkup` não executa efeitos, então a prova é feita sobre as
 * FUNÇÕES PURAS do módulo — recorte das metas, estado de aprovação e tradução do
 * resultado da leitura — mais uma guarda de fonte contra a reintrodução do filtro
 * por SELF (as duas provas, comportamental e estática, sem regex vacuamente verde).
 */
import { describe, expect, it } from "vitest";
import type {
  AprovacaoSoberana,
  EscopoMetasSoberanas,
  MetaSoberana,
  ResultadoMetas,
} from "../application/ports/GoalRepository";
import {
  metasDoAvaliadoSoberanas,
  metasSemAprovacaoFormal,
  resultadoDaLeituraDaAvaliacao,
} from "./useMetasSoberanasDaAvaliacao";
import fonteDoHook from "./useMetasSoberanasDaAvaliacao.ts?raw";

const ORGANIZACAO = "11111111-1111-4111-8111-111111111111";
const CICLO = "22222222-2222-4222-8222-222222222222";
const AVALIADO = "66666666-6666-4666-8666-666666666666";
const OUTRO_COLABORADOR = "77777777-7777-4777-8777-777777777777";

/** Fato de aprovação FICTÍCIO (a UI não reconstrói a regra de exigência). */
function aprovacao(
  papel: "GERENTE" | "COORDENADOR",
  exigida: boolean,
  vigente: boolean
): AprovacaoSoberana {
  return {
    papel,
    exigida,
    vigente,
    aprovacaoId: null,
    decididoEm: null,
    motivo: null,
    aprovadorCollaboratorId: null,
  };
}

function meta(parcial: Partial<MetaSoberana> = {}): MetaSoberana {
  return {
    id: "aaaaaaaa-0000-4000-8000-000000000000",
    organizationId: ORGANIZACAO,
    cycleId: CICLO,
    collaboratorId: AVALIADO,
    tipo: "INDIVIDUAL",
    descricao: "Meta sintetica",
    kpi: "KPI",
    valorAlvo: "100",
    status: "EM_ANDAMENTO",
    progressoPercentual: null,
    resultadoAtual: null,
    resultadoFinal: null,
    atingida: null,
    excluida: false,
    version: 1,
    relacao: "SELF",
    criadoEm: "2026-01-01T00:00:00.000Z",
    atualizadoEm: "2026-01-01T00:00:00.000Z",
    dataUltimoAcompanhamento: null,
    dataFechamento: null,
    dataExclusao: null,
    aprovacoes: [
      aprovacao("GERENTE", true, true),
      aprovacao("COORDENADOR", false, false),
    ],
    aprovacoesVigentes: [],
    ...parcial,
  };
}

/** META A: do avaliado, ator é o APROVADOR GERENTE CONGELADO, pendente. */
const META_A = meta({
  id: "aaaaaaaa-1111-4111-8111-111111111111",
  relacao: "APROVADOR_GERENTE_CONGELADO",
  aprovacoes: [aprovacao("GERENTE", true, false), aprovacao("COORDENADOR", false, false)],
});

/** META B: do avaliado, ator é o APROVADOR COORDENADOR CONGELADO, pendente. */
const META_B = meta({
  id: "bbbbbbbb-2222-4222-8222-222222222222",
  relacao: "APROVADOR_COORDENADOR_CONGELADO",
  aprovacoes: [aprovacao("GERENTE", false, false), aprovacao("COORDENADOR", true, false)],
});

/** META C: de OUTRO colaborador (não é do avaliado). */
const META_C = meta({
  id: "cccccccc-3333-4333-8333-333333333333",
  collaboratorId: OUTRO_COLABORADOR,
  relacao: "APROVADOR_GERENTE_CONGELADO",
});

/** META D: do avaliado, mas EXCLUÍDA logicamente. */
const META_D = meta({
  id: "dddddddd-4444-4444-8444-444444444444",
  relacao: "SELF",
  excluida: true,
});

/** META E: do avaliado e FORMALMENTE aprovada (não entra em pendências). */
const META_E = meta({
  id: "eeeeeeee-5555-4555-8555-555555555555",
  relacao: "APROVADOR_GERENTE_CONGELADO",
  aprovacoes: [aprovacao("GERENTE", true, true), aprovacao("COORDENADOR", false, false)],
});

function escopo(metas: readonly MetaSoberana[]): EscopoMetasSoberanas {
  return {
    organizationId: ORGANIZACAO,
    cycleId: CICLO,
    cicloStatus: "ATIVO",
    escopo: "ESCOPO_APLICADO",
    metas,
    limites: [],
  };
}

describe("F5-10 P6 (auditoria Codex do PR #228) — metas DO AVALIADO por colaboradorId", () => {
  it("A e B (relações de aprovador congelado) são PRESERVADAS", () => {
    const metas = metasDoAvaliadoSoberanas(
      [META_A, META_B, META_C, META_D],
      AVALIADO
    );

    // Nenhuma exigência de SELF: as metas do avaliado chegam pelo escopo
    // autorizado com as relações de aprovador congelado.
    expect(metas.map((item) => item.id)).toEqual([META_A.id, META_B.id]);
  });

  it("C é excluída por collaboratorId (não é meta do avaliado)", () => {
    const metas = metasDoAvaliadoSoberanas([META_A, META_C], AVALIADO);

    expect(metas.map((item) => item.id)).toEqual([META_A.id]);
    expect(metas.map((item) => item.id)).not.toContain(META_C.id);
  });

  it("D é excluída por estar logicamente excluída", () => {
    const metas = metasDoAvaliadoSoberanas([META_A, META_D], AVALIADO);

    expect(metas.map((item) => item.id)).toEqual([META_A.id]);
    expect(metas.map((item) => item.id)).not.toContain(META_D.id);
  });

  it("semAprovacaoFormal contém A e B pendentes e não contém a aprovada", () => {
    const metas = metasDoAvaliadoSoberanas(
      [META_A, META_B, META_C, META_D, META_E],
      AVALIADO
    );
    const pendentes = metasSemAprovacaoFormal(metas);

    expect(pendentes.map((item) => item.id)).toEqual([META_A.id, META_B.id]);
    expect(pendentes.map((item) => item.id)).not.toContain(META_E.id);
  });

  it("leitura soberana com sucesso devolve o recorte do avaliado e nenhum erro", () => {
    const estado = resultadoDaLeituraDaAvaliacao(
      { ok: true, data: escopo([META_A, META_B, META_C, META_D]) },
      AVALIADO
    );

    expect(estado.erro).toBe("");
    expect(estado.carregando).toBe(false);
    expect(estado.metas.map((item) => item.id)).toEqual([META_A.id, META_B.id]);
  });

  it("sucesso com zero metas do avaliado é vazio EXPLÍCITO (sem erro de leitura)", () => {
    const estado = resultadoDaLeituraDaAvaliacao(
      { ok: true, data: escopo([META_C, META_D]) },
      AVALIADO
    );

    expect(estado.erro).toBe("");
    expect(estado.carregando).toBe(false);
    expect(estado.metas).toEqual([]);
  });

  it("erro soberano NUNCA vira sucesso vazio", () => {
    const erro: ResultadoMetas<EscopoMetasSoberanas> = {
      ok: false,
      error: { code: "INTERNAL", message: "falha" },
    };

    for (const codigo of ["INTERNAL", "FORBIDDEN", "NOT_FOUND", "CONFLICT"] as const) {
      const estado = resultadoDaLeituraDaAvaliacao(
        { ok: false, error: { code: codigo, message: "falha" } },
        AVALIADO
      );
      // A falha é EXPLÍCITA: mensagem presente e nenhuma meta apresentada.
      expect(estado.erro.length, codigo).toBeGreaterThan(0);
      expect(estado.metas, codigo).toEqual([]);
      expect(estado.carregando, codigo).toBe(false);
    }

    expect(resultadoDaLeituraDaAvaliacao(erro, AVALIADO).erro).toContain(
      "Não foi possível carregar as metas do ciclo."
    );
  });

  it("o hook não exige SELF para as metas do avaliado (guarda de regressão)", () => {
    const fonte = fonteDoHook as string;
    // Não-vacuidade: a fonte precisa existir e ser o arquivo real do hook.
    expect(typeof fonte).toBe("string");
    expect(fonte.length).toBeGreaterThan(1000);
    expect(fonte).toContain("useMetasSoberanasDaAvaliacao");

    const codigo = fonte
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .split("\n")
      .map((linha) => {
        const indice = linha.indexOf("//");
        return indice === -1 ? linha : linha.slice(0, indice);
      })
      .join("\n");

    // O recorte é por DONO (`collaboratorId`) + exclusão lógica...
    expect(codigo).toContain("meta.collaboratorId === collaboratorIdDoAvaliado");
    expect(codigo).toContain("!meta.excluida");
    // ...e NUNCA por relação SELF (a `relacao` diz COMO, não QUEM).
    expect(codigo).not.toContain('relacao === "SELF"');
    expect(codigo).not.toMatch(/meta\.relacao/);
  });
});
