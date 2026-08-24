import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { criteriosAvaliacao } from "../data/modeloAvaliacao";
import { getColaboradores } from "./colaboradorStorage";
import { getFeedbacks, saveFeedback } from "./feedbackStorage";
import { getColaboradoresVisiveis } from "./visibilidadeColaboradores";

export type SituacaoAvaliacaoCiclo =
  | "NAO_INICIADA"
  | "EM_ANDAMENTO"
  | "PRONTA_PARA_FEEDBACK"
  | "CONCLUIDA";

export interface LinhaPainelCiclo {
  colaborador: Colaborador;
  feedback?: Feedback;
  situacao: SituacaoAvaliacaoCiclo;
}

function criarFeedbackVazio(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao
): Feedback {
  const agora = new Date().toISOString();

  return {
    id: crypto.randomUUID(),
    colaboradorId: colaborador.matricula,
    colaboradorNome: colaborador.nome,
    status: "RASCUNHO",
    data: agora,
    dataCriacao: agora,
    dataUltimaAtualizacao: agora,
    ano: ciclo.ano,
    ciclo: ciclo.ciclo,
    notaMedia: 0,
    competencias: criteriosAvaliacao.map((criterio) => ({
      competenciaId: criterio.id,
      competenciaNome: criterio.nome,
      nota: 0,
      comentario: "",
    })),
    criteriosDetalhados: criteriosAvaliacao.map((criterio) => ({
      criterioId: criterio.id,
      criterioNome: criterio.nome,
      nota: 0,
      subcriterios: criterio.subcriterios.map((subcriterio) => ({
        nome: subcriterio,
        notaGerente: 0,
        notaCoordenador: 0,
        notaColegiado: 0,
        votosColegiado: [],
        notaFinal: 0,
      })),
      observacaoGerente: "",
      observacaoCoordenador: "",
    })),
    feedbackFinalGerente: "",
    feedbackFinalCoordenador: "",
  };
}

export function criarAvaliacoesDoCicloAtivado(
  ciclo: CicloAvaliacao
): {
  criadas: number;
  existentes: number;
  elegiveis: number;
} {
  const colaboradores = getColaboradores();
  const feedbacks = getFeedbacks();

  const elegiveis = colaboradores.filter(
    (colaborador) =>
      colaborador.status === "ATIVO" &&
      colaborador.funcao !== "GERENTE" &&
      colaborador.gestorDiretoMatricula !== undefined
  );

  let criadas = 0;
  let existentes = 0;

  elegiveis.forEach((colaborador) => {
    const jaExiste = feedbacks.some(
      (feedback) =>
        feedback.colaboradorId === colaborador.matricula &&
        feedback.ano === ciclo.ano &&
        feedback.ciclo === ciclo.ciclo
    );

    if (jaExiste) {
      existentes += 1;
      return;
    }

    saveFeedback(criarFeedbackVazio(colaborador, ciclo));
    criadas += 1;
  });

  return {
    criadas,
    existentes,
    elegiveis: elegiveis.length,
  };
}

function temPreenchimento(feedback: Feedback): boolean {
  const temNotas =
    feedback.criteriosDetalhados?.some((criterio) =>
      criterio.subcriterios.some(
        (subcriterio) =>
          subcriterio.notaGerente > 0 ||
          subcriterio.notaCoordenador > 0 ||
          subcriterio.notaColegiado > 0 ||
          (subcriterio.votosColegiado?.length ?? 0) > 0
      )
    ) ?? false;

  const temObservacoes =
    feedback.criteriosDetalhados?.some(
      (criterio) =>
        criterio.observacaoGerente.trim().length > 0 ||
        criterio.observacaoCoordenador.trim().length > 0
    ) ?? false;

  const temFeedbackFinal =
    (feedback.feedbackFinalGerente?.trim().length ?? 0) > 0 ||
    (feedback.feedbackFinalCoordenador?.trim().length ?? 0) > 0;

  return temNotas || temObservacoes || temFeedbackFinal;
}

export function getSituacaoAvaliacaoCiclo(
  feedback?: Feedback
): SituacaoAvaliacaoCiclo {
  if (!feedback) return "NAO_INICIADA";

  if (feedback.status === "CONCLUIDA") return "CONCLUIDA";

  if (feedback.status === "PRONTA_PARA_FEEDBACK") {
    return "PRONTA_PARA_FEEDBACK";
  }

  return temPreenchimento(feedback)
    ? "EM_ANDAMENTO"
    : "NAO_INICIADA";
}

export function getPainelCiclo(
  ciclo: CicloAvaliacao,
  gerente: Colaborador
): LinhaPainelCiclo[] {
  const colaboradores = getColaboradores();
  const feedbacks = getFeedbacks();

  const elegiveis = getColaboradoresVisiveis(
    gerente,
    colaboradores
  )
    .filter(
      (colaborador) =>
        colaborador.status === "ATIVO" &&
        colaborador.funcao !== "GERENTE"
    )
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  return elegiveis.map((colaborador) => {
    const feedback = feedbacks.find(
      (item) =>
        item.colaboradorId === colaborador.matricula &&
        item.ano === ciclo.ano &&
        item.ciclo === ciclo.ciclo
    );

    return {
      colaborador,
      feedback,
      situacao: getSituacaoAvaliacaoCiclo(feedback),
    };
  });
}
