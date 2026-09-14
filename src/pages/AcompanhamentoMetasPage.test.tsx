import { describe, expect, it } from "vitest";
import paginaFonte from "./AcompanhamentoMetasPage.tsx?raw";
import apoioFonte from "./acompanhamentoMetasApoio.ts?raw";
import type { MetaSoberana } from "../application/ports/GoalRepository";
import {
  aprovacaoDoPapel,
  mensagemDoErro,
  metaFormalmenteAprovada,
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

  it("pendência acionável só existe para o papel que a RELAÇÃO do ator autoriza", () => {
    const alvo = comAprovacoes(false, true, false);

    expect(pendenteDoPerfil(alvo, "GERENTE")).toBe(true);
    expect(pendenteDoPerfil(alvo, "COORDENADOR")).toBe(true);
    expect(pendenteDoPerfil(alvo, null)).toBe(false);

    const aprovada = comAprovacoes(true, true, true);
    expect(pendenteDoPerfil(aprovada, "GERENTE")).toBe(false);
    expect(pendenteDoPerfil(aprovada, "COORDENADOR")).toBe(false);

    const naoExigida = comAprovacoes(false, false, false);
    expect(pendenteDoPerfil(naoExigida, "COORDENADOR")).toBe(false);
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

  it("só entram metas cuja relação pertence ao conjunto congelado do ator", () => {
    expect(codigoApoio).toContain("APROVADOR_GERENTE_CONGELADO");
    expect(codigoApoio).toContain("APROVADOR_COORDENADOR_CONGELADO");
    expect(codigo).toMatch(/colegiado[\s\S]{0,80}concede acesso/);
  });
});