import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback, StatusFeedback } from "../types/Feedback";
import type { AprovacaoSoberana, MetaSoberana } from "../application/ports/GoalRepository";
import type { CicloSoberano } from "../services/acessoCiclosSoberanos";
import PainelCicloPageFonte from "./PainelCicloPage.tsx?raw";
import { obterAcaoAvaliacaoPainel } from "./painelCicloAvaliacaoAction";
import {
  cicloLegadoDeApresentacao,
  contarAprovacoesPendentes,
  metaEntraNoKpiDeAprovacoes,
  colaboradoresComMetaSoberana,
} from "./painelCicloMetasSoberanas";
import PainelCicloMetasSoberanasFonte from "./painelCicloMetasSoberanas.ts?raw";
import { getStatusGeralPainel } from "./painelCicloStatus";

function pessoa(matricula: number, funcao: Colaborador["funcao"], gestor?: number): Colaborador {
  return { matricula, funcao, gestorDiretoMatricula: gestor, status: "ATIVO", nome: `Pessoa ${matricula}`, email: `${matricula}@example.com`, cargo: "Cargo", area: "Área", respondePara: "" };
}

const gerente = pessoa(1, "GERENTE");
const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
const avaliado = pessoa(3, "ANALISTA", coordenador.matricula);
const colaboradores = [gerente, coordenador, avaliado];
const ciclo: CicloAvaliacao = { id: "ciclo", ano: 2026, ciclo: 1, status: "ATIVO", dataCriacao: "2026-01-01", dataUltimaAtualizacao: "2026-01-01" };

function feedback(status: StatusFeedback): Feedback {
  return { id: `feedback-${status}`, colaboradorId: avaliado.matricula, colaboradorNome: avaliado.nome, status, data: "2026-01-01", ano: 2026, ciclo: 1, competencias: [], notaMedia: 0 };
}

describe("ação de avaliação no painel do ciclo", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());
  it("abre edição somente quando há capability efetiva", () => {
    expect(obterAcaoAvaliacaoPainel(gerente, avaliado, colaboradores, ciclo, feedback("RASCUNHO"))).toEqual({ label: "Abrir avaliação", destino: "/colaborador/3/feedback/feedback-RASCUNHO/editar" });
  });

  it.each(["CONCLUIDA", "CANCELADA"] as const)("abre consulta, nunca /editar, para %s", (status) => {
    const acao = obterAcaoAvaliacaoPainel(gerente, avaliado, colaboradores, ciclo, feedback(status));
    expect(acao?.label).toBe("Ver avaliação");
    expect(acao?.destino).not.toContain("/editar");
  });

  it("abre consulta quando o ciclo está cancelado", () => {
    const acao = obterAcaoAvaliacaoPainel(gerente, avaliado, colaboradores, { ...ciclo, status: "CANCELADO" }, feedback("RASCUNHO"));
    expect(acao).toEqual({ label: "Ver avaliação", destino: "/colaborador/3/feedback/feedback-RASCUNHO" });
  });

  it("apresenta ciclo cancelado com label curto e estilo histórico neutro", () => {
    expect(getStatusGeralPainel("EM_ANDAMENTO", "CANCELADO")).toEqual({
      label: "Cancelado",
      className: "is-historical",
    });
  });
});

// ---------------------------------------------------------------------------
// F5-10 P6 (Issue #220) — KPI "Minhas aprovações de metas" pelos FATOS da
// leitura soberana (`aprovacoes[].exigida`/`vigente`), com exclusão de
// colaboradores NAO_APLICAVEL/SUSPENSA e erro NUNCA convertido em zero.
// ---------------------------------------------------------------------------

const OUTRO_COLABORADOR = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

function aprovacao(
  papel: AprovacaoSoberana["papel"],
  exigida: boolean,
  vigente: boolean
): AprovacaoSoberana {
  return {
    papel,
    exigida,
    vigente,
    aprovacaoId: vigente ? `aprovacao-${papel}` : null,
    decididoEm: vigente ? "2026-01-02T00:00:00.000Z" : null,
    motivo: null,
    aprovadorCollaboratorId: null,
  };
}

function meta(parcial: Partial<MetaSoberana> = {}): MetaSoberana {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    organizationId: "22222222-2222-4222-8222-222222222222",
    cycleId: "33333333-3333-4333-8333-333333333333",
    collaboratorId: "44444444-4444-4444-8444-444444444444",
    tipo: "INDIVIDUAL",
    descricao: "Meta fictícia",
    kpi: "KPI fictício",
    valorAlvo: "10",
    status: "EM_ANDAMENTO",
    progressoPercentual: null,
    resultadoAtual: null,
    resultadoFinal: null,
    atingida: null,
    excluida: false,
    version: 1,
    relacao: "APROVADOR_GERENTE_CONGELADO",
    criadoEm: "2026-01-01T00:00:00.000Z",
    atualizadoEm: "2026-01-01T00:00:00.000Z",
    dataUltimoAcompanhamento: null,
    dataFechamento: null,
    dataExclusao: null,
    aprovacoes: [
      aprovacao("GERENTE", true, false),
      aprovacao("COORDENADOR", false, false),
    ],
    aprovacoesVigentes: [],
    ...parcial,
  };
}

describe("F5-10 P6 — KPI pelos fatos da leitura soberana", () => {
  const todosElegiveis = () => true;

  it("conta a aprovação EXIGIDA e PENDENTE do papel soberano do ator", () => {
    expect(
      contarAprovacoesPendentes([meta()], todosElegiveis)
    ).toBe(1);
  });

  it("NÃO conta aprovação concedida (vigente) nem papel não exigido", () => {
    const concedida = meta({
      id: "55555555-5555-4555-8555-555555555555",
      aprovacoes: [
        aprovacao("GERENTE", true, true),
        aprovacao("COORDENADOR", false, false),
      ],
    });
    const coordenadorNaoExigido = meta({
      id: "66666666-6666-4666-8666-666666666666",
      relacao: "APROVADOR_COORDENADOR_CONGELADO",
      aprovacoes: [
        aprovacao("GERENTE", true, true),
        aprovacao("COORDENADOR", false, false),
      ],
    });

    expect(contarAprovacoesPendentes([concedida, coordenadorNaoExigido], todosElegiveis)).toBe(0);
  });

  it("conta o papel COORDENADOR pelo próprio item de `aprovacoes[]`", () => {
    const doCoordenador = meta({
      relacao: "APROVADOR_COORDENADOR_CONGELADO",
      aprovacoes: [
        aprovacao("GERENTE", true, true),
        aprovacao("COORDENADOR", true, false),
      ],
    });
    expect(contarAprovacoesPendentes([doCoordenador], todosElegiveis)).toBe(1);
  });

  it("meta em que o ator é apenas DONO (SELF) não é 'minha aprovação'", () => {
    const propria = meta({
      relacao: "SELF",
      aprovacoes: [
        aprovacao("GERENTE", true, false),
        aprovacao("COORDENADOR", true, false),
      ],
    });
    expect(contarAprovacoesPendentes([propria], todosElegiveis)).toBe(0);
    expect(metaEntraNoKpiDeAprovacoes(propria, todosElegiveis)).toBe(false);
  });

  it("meta excluída logicamente fica fora do KPI", () => {
    expect(contarAprovacoesPendentes([meta({ excluida: true })], todosElegiveis)).toBe(0);
  });

  it("colaborador NAO_APLICAVEL/SUSPENSA é excluído pela elegibilidade (D6)", () => {
    const metas = [meta(), meta({ id: "77777777-7777-4777-8777-777777777777", collaboratorId: OUTRO_COLABORADOR })];
    expect(contarAprovacoesPendentes(metas, todosElegiveis)).toBe(2);
    // Somente o colaborador da primeira meta é elegível no ciclo.
    expect(
      contarAprovacoesPendentes(metas, (collaboratorId) => collaboratorId !== OUTRO_COLABORADOR)
    ).toBe(1);
  });

  it("conjunto autorizado sem meta é ZERO REAL (ausência explícita, não erro)", () => {
    expect(contarAprovacoesPendentes([], todosElegiveis)).toBe(0);
  });

  it("os colaboradores com meta autorizada vêm do próprio conjunto autorizado", () => {
    // O consumidor só pergunta "existe meta autorizada deste colaborador?" — a
    // propriedade modelada é BOOLEANA, sem reduzir várias relações do MESMO
    // colaborador a "a última vista" (achado LOW da auditoria do PR #228).
    const colaboradores = colaboradoresComMetaSoberana([
      meta(),
      meta({ id: "88888888-8888-4888-8888-888888888888", collaboratorId: OUTRO_COLABORADOR, relacao: "SELF" }),
    ]);

    expect(colaboradores.has("44444444-4444-4444-8444-444444444444")).toBe(true);
    expect(colaboradores.has(OUTRO_COLABORADOR)).toBe(true);
    // Colaborador fora do conjunto autorizado NÃO aparece: sem meta, sem botão.
    expect(colaboradores.has("99999999-9999-4999-8999-999999999999")).toBe(false);
  });

  it("o MESMO colaborador com as duas relações continua presente e meta excluída não conta", () => {
    const mesmoColaborador = "55555555-5555-4555-8555-555555555555";
    const semBotao = "99999999-9999-4999-8999-999999999999";
    const colaboradores = colaboradoresComMetaSoberana([
      meta({
        id: "aaaaaaaa-1111-4111-8111-111111111111",
        collaboratorId: mesmoColaborador,
        relacao: "APROVADOR_GERENTE_CONGELADO",
      }),
      meta({
        id: "bbbbbbbb-2222-4222-8222-222222222222",
        collaboratorId: mesmoColaborador,
        relacao: "APROVADOR_COORDENADOR_CONGELADO",
      }),
      meta({
        id: "cccccccc-3333-4333-8333-333333333333",
        collaboratorId: semBotao,
        excluida: true,
      }),
    ]);

    // A presença não depende de QUAL relação foi vista por último.
    expect(colaboradores.has(mesmoColaborador)).toBe(true);
    // Meta excluída logicamente não habilita o botão.
    expect(colaboradores.has(semBotao)).toBe(false);
  });
});

describe("F5-10 P6 — ponte de APRESENTAÇÃO do ciclo soberano", () => {
  const cicloSoberano: CicloSoberano = {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    organizationId: "22222222-2222-4222-8222-222222222222",
    ano: 2026,
    numero: 2,
    status: "ATIVO",
    dataInicio: "2026-05-01",
    dataFim: "2026-06-30",
    dataAtivacao: "2026-05-01T00:00:00.000Z",
    dataEncerramento: null,
    encerradoComPendencias: false,
    quantidadePendencias: 0,
    version: 3,
    criadoEm: "2026-04-01T00:00:00.000Z",
    atualizadoEm: "2026-05-01T00:00:00.000Z",
  };

  it("projeta identidade/status/datas SOMENTE a partir da linha soberana", () => {
    const legado = cicloLegadoDeApresentacao(cicloSoberano);
    expect(legado.id).toBe(cicloSoberano.id);
    expect(legado.ano).toBe(2026);
    expect(legado.ciclo).toBe(2);
    expect(legado.status).toBe("ATIVO");
    expect(legado.dataInicio).toBe("2026-05-01");
    expect(legado.dataFim).toBe("2026-06-30");
    // Datas anuláveis ausentes NÃO são inventadas.
    expect(legado.dataEncerramento).toBeUndefined();
  });
});

/** Código sem comentários: os cabeçalhos CITAM, por texto, o que a tela NÃO usa. */
function apenasCodigo(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

describe("F5-10 P6 — guardas estáticas da autoridade de METAS do painel", () => {
  const fonte = apenasCodigo(PainelCicloPageFonte as string);
  /** Companheiro: onde vivem os helpers PUROS de metas soberanas do painel. */
  const fonteMetas = apenasCodigo(PainelCicloMetasSoberanasFonte as string);

  /**
   * Recorte do corpo do KPI (não-vacuidade: a assinatura tem de existir). A
   * autoridade do KPI vale para o CÓDIGO desse recorte, não para a prosa.
   */
  function recorteDoKpi(): string {
    const inicio = fonteMetas.indexOf(
      "export function metaEntraNoKpiDeAprovacoes("
    );
    expect(inicio, "assinatura do KPI ausente no companheiro").toBeGreaterThan(
      -1
    );
    const fim = fonteMetas.indexOf("\n}", inicio);
    expect(fim, "fim da função do KPI ausente").toBeGreaterThan(inicio);
    return fonteMetas.slice(inicio, fim);
  }

  it("não lê o storage legado de metas nem resolve ciclo por storage", () => {
    for (const proibido of [
      "metaStorage",
      "getMetasDoCiclo",
      "getCiclosAvaliacao",
      "localStorage",
      "sessionStorage",
      "aprovacaoGerente",
      "aprovacaoCoordenador",
      'from("evaluation_goal',
      ".rpc(",
    ]) {
      expect(fonte, proibido).not.toContain(proibido);
      expect(fonteMetas, proibido).not.toContain(proibido);
    }
  });

  it("a decisão de metas não usa can()/localWorld/funcao/gestorDiretoMatricula", () => {
    // A autoridade de metas é `relacao` + `aprovacoes[]`; nenhum portão local.
    // O KPI descarta a própria meta (`SELF`), a excluída e o colaborador não
    // elegível (D6), e só conta o papel EXIGIDO e ainda PENDENTE.
    const kpi = recorteDoKpi();
    expect(kpi).toContain('meta.relacao === "SELF"');
    expect(kpi).toContain("meta.excluida");
    expect(kpi).toContain("aprovacao?.exigida === true");
    expect(kpi).toContain("aprovacao.vigente === false");
    // O gate legado de metas saiu da tela inteira.
    expect(fonte).not.toContain("goal.view.admin");
    expect(fonte).not.toContain("localWorld");
    expect(fonte).not.toContain("GoalResource");
    expect(fonte).not.toContain("podeVerMetas");
    // O gate GERAL da página permanece (dívida separada de ciclo/avaliação, D5).
    expect(fonte).toContain('"cycle.team.panel.view"');
    // O companheiro não decide por portão local nenhum.
    for (const proibido of [
      "funcao",
      "gestorDiretoMatricula",
      "localWorld",
      "goal.view.admin",
      "can(",
    ]) {
      expect(fonteMetas, `companheiro:${proibido}`).not.toContain(proibido);
    }
  });

  it("os helpers de runtime do painel vivem no companheiro, não na página", () => {
    for (const nome of [
      "colaboradoresComMetaSoberana",
      "metaEntraNoKpiDeAprovacoes",
      "contarAprovacoesPendentes",
      "cicloLegadoDeApresentacao",
    ]) {
      expect(fonte, `página:${nome}`).not.toContain(`export function ${nome}`);
      expect(fonteMetas, `companheiro:${nome}`).toContain(
        `export function ${nome}`
      );
    }
  });

  it("lê pela porta soberana e trata erro como indisponível explícito", () => {
    expect(fonte).toContain("obterRepositorioCiclosSoberanos");
    expect(fonte).toContain("obterRepositorioMetasSoberanas");
    expect(fonte).toContain("listarMetasPorEscopo");
    expect(fonteMetas).toContain('fase: "indisponivel"');
    expect(fonte).toContain("Tentar novamente");
    // `setState` depois do desmonte é descartado pelo marcador de atividade.
    expect(fonte).toContain("let ativo = true");
    expect(fonte).toContain("ativo = false");
  });
});
