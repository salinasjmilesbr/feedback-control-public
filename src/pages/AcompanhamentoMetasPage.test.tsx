import { describe, expect, it } from "vitest";
import paginaFonte from "./AcompanhamentoMetasPage.tsx?raw";
import apoioFonte from "./acompanhamentoMetasApoio.ts?raw";
import type { AprovacaoSoberana, MetaSoberana } from "../application/ports/GoalRepository";
import {
  aprovacaoDoPapel,
  mensagemDoErro,
  metaFormalmenteAprovada,
  papelAprovadorDaRelacao,
  pendenteDoPerfil,
  relacaoAutorizaPapel,
} from "./acompanhamentoMetasApoio";

/**
 * F5-10 P6 (Issue #220) — testes DEDICADOS da tela de acompanhamento de metas.
 *
 * O projeto NÃO tem ambiente DOM nos testes (nenhum `jsdom` instalado) e o
 * `renderToStaticMarkup` não executa efeitos: a tela assíncrona só é renderizável
 * com DOM real. Por isso este arquivo prova exaustivamente as DECISÕES puras
 * (relação congelada, estado de aprovação por papel, mensagem pública) e, por
 * leitura da FONTE, as proibições estruturais do cutover (zero legado de metas,
 * zero autorização local, zero RPC/tabela direta).
 */

function meta(parcial: Partial<MetaSoberana> = {}): MetaSoberana {
  return {
    id: "33333333-3333-4333-8333-333333333333",
    organizationId: "11111111-1111-4111-8111-111111111111",
    cycleId: "22222222-2222-4222-8222-222222222222",
    collaboratorId: "66666666-6666-4666-8666-666666666666",
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
    version: 0,
    relacao: "SELF",
    criadoEm: "2026-01-01T00:00:00.000Z",
    atualizadoEm: "2026-01-01T00:00:00.000Z",
    dataUltimoAcompanhamento: null,
    dataFechamento: null,
    dataExclusao: null,
    aprovacoes: [
      {
        papel: "GERENTE",
        exigida: true,
        vigente: false,
        aprovacaoId: null,
        decididoEm: null,
        motivo: null,
        aprovadorCollaboratorId: null,
      },
      {
        papel: "COORDENADOR",
        exigida: false,
        vigente: false,
        aprovacaoId: null,
        decididoEm: null,
        motivo: null,
        aprovadorCollaboratorId: null,
      },
    ],
    aprovacoesVigentes: [],
    ...parcial,
  };
}

function comAprovacoes(
  gerenteVigente: boolean,
  coordenadorExigida: boolean,
  coordenadorVigente: boolean
): MetaSoberana {
  return meta({
    aprovacoes: [
      {
        papel: "GERENTE",
        exigida: true,
        vigente: gerenteVigente,
        aprovacaoId: null,
        decididoEm: null,
        motivo: null,
        aprovadorCollaboratorId: null,
      },
      {
        papel: "COORDENADOR",
        exigida: coordenadorExigida,
        vigente: coordenadorVigente,
        aprovacaoId: null,
        decididoEm: null,
        motivo: null,
        aprovadorCollaboratorId: null,
      },
    ],
  });
}

describe("F5-10 P6 — decisões puras do acompanhamento de metas", () => {
  it("aprovacaoDoPapel lê o FATO da projeção, sem reconstruir a regra", () => {
    const alvo = comAprovacoes(true, true, false);

    expect(aprovacaoDoPapel(alvo, "GERENTE")?.vigente).toBe(true);
    expect(aprovacaoDoPapel(alvo, "COORDENADOR")?.exigida).toBe(true);
    expect(aprovacaoDoPapel(alvo, "COORDENADOR")?.vigente).toBe(false);
  });

  it("meta é formalmente aprovada somente quando TODOS os papéis EXIGIDOS estão vigentes", () => {
    expect(metaFormalmenteAprovada(comAprovacoes(false, false, false))).toBe(false);
    expect(metaFormalmenteAprovada(comAprovacoes(true, false, false))).toBe(true);
    expect(metaFormalmenteAprovada(comAprovacoes(true, true, false))).toBe(false);
    expect(metaFormalmenteAprovada(comAprovacoes(true, true, true))).toBe(true);
  });

  it("pendência acionável é derivada da relação CONGELADA da própria meta", () => {
    const pendente = comAprovacoes(false, true, false).aprovacoes;

    const gerente = meta({
      relacao: "APROVADOR_GERENTE_CONGELADO",
      aprovacoes: pendente,
    });
    const coordenador = meta({
      relacao: "APROVADOR_COORDENADOR_CONGELADO",
      aprovacoes: pendente,
    });
    const self = meta({ relacao: "SELF", aprovacoes: pendente });

    expect(pendenteDoPerfil(gerente)).toBe(true);
    expect(pendenteDoPerfil(coordenador)).toBe(true);
    // SELF nunca é pendência acionável do perfil.
    expect(pendenteDoPerfil(self)).toBe(false);

    const aprovada = meta({
      relacao: "APROVADOR_GERENTE_CONGELADO",
      aprovacoes: comAprovacoes(true, true, true).aprovacoes,
    });
    expect(pendenteDoPerfil(aprovada)).toBe(false);

    const naoExigida = meta({
      relacao: "APROVADOR_COORDENADOR_CONGELADO",
      aprovacoes: comAprovacoes(false, false, false).aprovacoes,
    });
    expect(pendenteDoPerfil(naoExigida)).toBe(false);
  });

  it("relação → papel: só as duas relações CONGELADAS habilitam aprovação", () => {
    expect(relacaoAutorizaPapel("APROVADOR_GERENTE_CONGELADO", "GERENTE")).toBe(true);
    expect(
      relacaoAutorizaPapel("APROVADOR_COORDENADOR_CONGELADO", "COORDENADOR")
    ).toBe(true);
    expect(
      relacaoAutorizaPapel("APROVADOR_GERENTE_CONGELADO", "COORDENADOR")
    ).toBe(false);
    expect(
      relacaoAutorizaPapel("APROVADOR_COORDENADOR_CONGELADO", "GERENTE")
    ).toBe(false);
    expect(relacaoAutorizaPapel("SELF", "GERENTE")).toBe(false);
    expect(relacaoAutorizaPapel("SELF", "COORDENADOR")).toBe(false);
  });

  it("mensagem pública é explícita para CONFLITO, autorização, entrada e ausência", () => {
    const padrao = "padrao";

    expect(mensagemDoErro({ code: "CONFLICT", message: "x" }, padrao)).toContain(
      "alterada por outra pessoa"
    );
    expect(mensagemDoErro({ code: "NOT_AUTHORIZED", message: "x" }, padrao)).toContain(
      "autorização"
    );
    expect(mensagemDoErro({ code: "FORBIDDEN", message: "x" }, padrao)).toContain(
      "autorização"
    );
    expect(mensagemDoErro({ code: "INVALID_INPUT", message: "x" }, padrao)).toContain(
      "inválidos"
    );
    expect(mensagemDoErro({ code: "NOT_FOUND", message: "x" }, padrao)).toContain(
      "não foi encontrada"
    );
    expect(mensagemDoErro({ code: "INTERNAL", message: "  " }, padrao)).toBe(padrao);
  });
});

describe("F5-10 P6 (auditoria GPT do PR #228) — a relação é POR META", () => {
  /** Fato de aprovação FICTÍCIO de um papel (a UI não reconstrói a regra). */
  const aprovacoesDe = (
    gerente: { exigida: boolean; vigente: boolean },
    coordenador: { exigida: boolean; vigente: boolean }
  ): readonly AprovacaoSoberana[] => [
    {
      papel: "GERENTE",
      exigida: gerente.exigida,
      vigente: gerente.vigente,
      aprovacaoId: null,
      decididoEm: null,
      motivo: null,
      aprovadorCollaboratorId: null,
    },
    {
      papel: "COORDENADOR",
      exigida: coordenador.exigida,
      vigente: coordenador.vigente,
      aprovacaoId: null,
      decididoEm: null,
      motivo: null,
      aprovadorCollaboratorId: null,
    },
  ];

  const comRelacao = (
    id: string,
    relacao: MetaSoberana["relacao"],
    aprovacoes: readonly AprovacaoSoberana[]
  ): MetaSoberana => meta({ id, relacao, aprovacoes });

  /** A: só GERENTE é exigido e está pendente. */
  const metaGerente = comRelacao(
    "aaaaaaaa-1111-4111-8111-111111111111",
    "APROVADOR_GERENTE_CONGELADO",
    aprovacoesDe({ exigida: true, vigente: false }, { exigida: false, vigente: false })
  );
  /** B: só COORDENADOR é exigido e está pendente. */
  const metaCoordenador = comRelacao(
    "bbbbbbbb-2222-4222-8222-222222222222",
    "APROVADOR_COORDENADOR_CONGELADO",
    aprovacoesDe({ exigida: false, vigente: false }, { exigida: true, vigente: false })
  );
  /** C: SELF — o ator é apenas dono; nenhum papel aprovador. */
  const metaSelf = comRelacao(
    "cccccccc-3333-4333-8333-333333333333",
    "SELF",
    aprovacoesDe({ exigida: true, vigente: false }, { exigida: true, vigente: false })
  );

  it("A. relação GERENTE conta e permite SOMENTE GERENTE", () => {
    expect(papelAprovadorDaRelacao(metaGerente.relacao)).toBe("GERENTE");
    expect(pendenteDoPerfil(metaGerente)).toBe(true);
    expect(relacaoAutorizaPapel(metaGerente.relacao, "GERENTE")).toBe(true);
    expect(relacaoAutorizaPapel(metaGerente.relacao, "COORDENADOR")).toBe(false);
  });

  it("B. relação COORDENADOR conta e permite SOMENTE COORDENADOR", () => {
    expect(papelAprovadorDaRelacao(metaCoordenador.relacao)).toBe("COORDENADOR");
    expect(pendenteDoPerfil(metaCoordenador)).toBe(true);
    expect(relacaoAutorizaPapel(metaCoordenador.relacao, "COORDENADOR")).toBe(true);
    expect(relacaoAutorizaPapel(metaCoordenador.relacao, "GERENTE")).toBe(false);
  });

  it("C. SELF não conta como pendência e não habilita aprovação", () => {
    expect(papelAprovadorDaRelacao(metaSelf.relacao)).toBeNull();
    expect(pendenteDoPerfil(metaSelf)).toBe(false);
    expect(relacaoAutorizaPapel(metaSelf.relacao, "GERENTE")).toBe(false);
    expect(relacaoAutorizaPapel(metaSelf.relacao, "COORDENADOR")).toBe(false);
  });

  it("a relação de UMA meta NÃO habilita o papel em OUTRA meta", () => {
    const conjunto = [metaGerente, metaCoordenador];

    // O conjunto MISTO contém as duas relações congeladas...
    expect(conjunto.some((m) => relacaoAutorizaPapel(m.relacao, "GERENTE"))).toBe(true);
    expect(conjunto.some((m) => relacaoAutorizaPapel(m.relacao, "COORDENADOR"))).toBe(true);

    // ...e ainda assim cada meta responde pela PRÓPRIA relação: nenhuma delas
    // habilita o papel da outra (era o bug do "papel global do ator").
    expect(relacaoAutorizaPapel(metaCoordenador.relacao, "GERENTE")).toBe(false);
    expect(relacaoAutorizaPapel(metaGerente.relacao, "COORDENADOR")).toBe(false);
  });

  it("no conjunto MISTO o perfil conta 2 pendências (uma por meta), nunca 4", () => {
    const conjunto = [metaGerente, metaCoordenador, metaSelf];

    expect(conjunto.filter(pendenteDoPerfil)).toHaveLength(2);
    expect(
      conjunto.filter((m) => relacaoAutorizaPapel(m.relacao, "GERENTE"))
    ).toHaveLength(1);
    expect(
      conjunto.filter((m) => relacaoAutorizaPapel(m.relacao, "COORDENADOR"))
    ).toHaveLength(1);
  });
});

describe("F5-10 P6 — proibições estruturais do cutover (leitura da fonte)", () => {
  const codigo = (paginaFonte as string)
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");

  /** Módulo companheiro: após a extração a autoridade de metas vive lá. */
  const codigoApoio = (apoioFonte as string)
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");

  it("zero autoridade legada de metas no CÓDIGO da tela", () => {
    for (const proibido of [
      "metaStorage",
      "localStorage",
      "sessionStorage",
      "getMetasDoColaboradorNoCiclo",
      "metaEstaAprovada",
      "metaExigeAprovacaoCoordenador",
      "goal.view.admin",
      "goal.approve.manager",
      "goal.approve.coordinator",
      "authorizationPolicy",
      "localWorld",
    ]) {
      expect(codigo, proibido).not.toContain(proibido);
    }
    expect(codigo).not.toMatch(/\bcan\s*\(/);
  });

  it("a leitura e a aprovação passam exclusivamente pelo repositório soberano", () => {
    expect(codigo).toContain("listarMetasPorEscopo");
    expect(codigo).toContain("aprovarMeta");
    expect(codigo).toContain("expectedVersion: meta.version");
    expect(codigo).toContain("operationId");
    expect(codigo).toContain("crypto.randomUUID()");
    expect(codigo).not.toMatch(/\.rpc\s*\(/);
    expect(codigo).not.toContain('from("evaluation_goal');
    expect(codigo).not.toContain("supabase/functions");
  });

  it("a autorização de aprovação é POR META, sem papel global do ator", () => {
    // Achado MEDIUM da auditoria do PR #228: o CONJUNTO de metas nunca define o
    // papel do ator — cada checkbox responde pela relação da própria meta.
    expect(codigo).not.toContain("podeAprovarComo");
    expect(codigo).not.toContain("papelDoAtor");
    expect(codigo).not.toContain("metas.some(");
    expect(codigo).toContain('relacaoAutorizaPapel(meta.relacao, "GERENTE")');
    expect(codigo).toContain('relacaoAutorizaPapel(\n      meta.relacao,\n      "COORDENADOR"\n    )');
  });

  it("só entram metas cuja relação pertence ao conjunto congelado do ator", () => {
    expect(codigoApoio).toContain("APROVADOR_GERENTE_CONGELADO");
    expect(codigoApoio).toContain("APROVADOR_COORDENADOR_CONGELADO");
    expect(codigo).toMatch(/colegiado[\s\S]{0,80}concede acesso/);
  });
});