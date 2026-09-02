import type { Colaborador } from "../types/Colaborador";
import type {
  Feedback,
  FeedbackCriterioDetalhado,
  FeedbackSubcriterioDetalhado,
  VotoColegiado,
} from "../types/Feedback";
import { getCiclosAvaliacao } from "./cicloAvaliacaoStorage";
import { getColaboradores } from "./colaboradorStorage";
import { getColaboradorEfetivoNoCiclo } from "./historicoOrganizacionalStorage";
import { obterPermissoesAvaliacao } from "./permissaoAvaliacao";

const STORAGE_KEY = "feedback-control-feedbacks";

export function getFeedbacks(): Feedback[] {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) {
    return [];
  }

  try {
    return JSON.parse(data) as Feedback[];
  } catch {
    return [];
  }
}

export function getFeedbacksByColaborador(colaboradorId: number): Feedback[] {
  return getFeedbacks().filter(
    (feedback) => feedback.colaboradorId === colaboradorId
  );
}

function encontrarGerenteResponsavelEmData(
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  feedback: Feedback,
  dataReferencia: string
): Colaborador | undefined {
  const ciclo = getCiclosAvaliacao().find(
    (item) => item.ano === feedback.ano && item.ciclo === feedback.ciclo
  );
  if (!ciclo) return undefined;

  const porMatricula = new Map(
    colaboradores.map((item) => [item.matricula, item])
  );
  const visitados = new Set<number>();
  let atual = getColaboradorEfetivoNoCiclo(
    colaborador,
    ciclo,
    colaboradores,
    dataReferencia.slice(0, 10)
  );

  while (atual.gestorDiretoMatricula) {
    const matricula = atual.gestorDiretoMatricula;
    if (visitados.has(matricula)) return undefined;
    visitados.add(matricula);

    const gestorBase = porMatricula.get(matricula);
    if (!gestorBase) return undefined;
    const gestor = getColaboradorEfetivoNoCiclo(
      gestorBase,
      ciclo,
      colaboradores,
      dataReferencia.slice(0, 10)
    );
    if (gestor.funcao === "GERENTE") return gestor;
    atual = gestor;
  }

  return undefined;
}

function inferirResponsaveisLegados(
  feedback: Feedback,
  colaborador: Colaborador,
  colaboradores: Colaborador[]
) {
  const ciclo = getCiclosAvaliacao().find(
    (item) => item.ano === feedback.ano && item.ciclo === feedback.ciclo
  );
  const dataReferencia = (
    feedback.dataCriacao ?? feedback.data ?? new Date().toISOString()
  ).slice(0, 10);

  const efetivo = ciclo
    ? getColaboradorEfetivoNoCiclo(
        colaborador,
        ciclo,
        colaboradores,
        dataReferencia
      )
    : colaborador;
  const gestorDireto = efetivo.gestorDiretoMatricula
    ? colaboradores.find(
        (item) => item.matricula === efetivo.gestorDiretoMatricula
      )
    : undefined;
  const coordenador = gestorDireto?.funcao === "COORDENADOR"
    ? gestorDireto
    : undefined;
  const gerente = encontrarGerenteResponsavelEmData(
    colaborador,
    colaboradores,
    feedback,
    dataReferencia
  );

  return { gerente, coordenador };
}

function comAutorLegado(
  original: Feedback,
  colaborador: Colaborador,
  colaboradores: Colaborador[]
): Feedback {
  const { gerente, coordenador } = inferirResponsaveisLegados(
    original,
    colaborador,
    colaboradores
  );
  const data = original.dataUltimaAtualizacao ?? original.dataCriacao ?? original.data;

  return {
    ...original,
    criteriosDetalhados: original.criteriosDetalhados?.map((criterio) => ({
      ...criterio,
      observacaoGerenteAutorMatricula:
        criterio.observacaoGerenteAutorMatricula ??
        (criterio.observacaoGerente.trim() ? gerente?.matricula : undefined),
      observacaoGerenteAutorNome:
        criterio.observacaoGerenteAutorNome ??
        (criterio.observacaoGerente.trim() ? gerente?.nome : undefined),
      observacaoGerenteData:
        criterio.observacaoGerenteData ??
        (criterio.observacaoGerente.trim() ? data : undefined),
      observacaoCoordenadorAutorMatricula:
        criterio.observacaoCoordenadorAutorMatricula ??
        (criterio.observacaoCoordenador.trim() ? coordenador?.matricula : undefined),
      observacaoCoordenadorAutorNome:
        criterio.observacaoCoordenadorAutorNome ??
        (criterio.observacaoCoordenador.trim() ? coordenador?.nome : undefined),
      observacaoCoordenadorData:
        criterio.observacaoCoordenadorData ??
        (criterio.observacaoCoordenador.trim() ? data : undefined),
      subcriterios: criterio.subcriterios.map((sub) => ({
        ...sub,
        avaliadorGerenteMatricula:
          sub.avaliadorGerenteMatricula ??
          (sub.notaGerente > 0 ? gerente?.matricula : undefined),
        avaliadorGerenteNome:
          sub.avaliadorGerenteNome ??
          (sub.notaGerente > 0 ? gerente?.nome : undefined),
        dataAvaliacaoGerente:
          sub.dataAvaliacaoGerente ?? (sub.notaGerente > 0 ? data : undefined),
        avaliadorCoordenadorMatricula:
          sub.avaliadorCoordenadorMatricula ??
          (sub.notaCoordenador > 0 ? coordenador?.matricula : undefined),
        avaliadorCoordenadorNome:
          sub.avaliadorCoordenadorNome ??
          (sub.notaCoordenador > 0 ? coordenador?.nome : undefined),
        dataAvaliacaoCoordenador:
          sub.dataAvaliacaoCoordenador ??
          (sub.notaCoordenador > 0 ? data : undefined),
      })),
    })),
    feedbackFinalGerenteAutorMatricula:
      original.feedbackFinalGerenteAutorMatricula ??
      (original.feedbackFinalGerente?.trim() ? gerente?.matricula : undefined),
    feedbackFinalGerenteAutorNome:
      original.feedbackFinalGerenteAutorNome ??
      (original.feedbackFinalGerente?.trim() ? gerente?.nome : undefined),
    feedbackFinalGerenteData:
      original.feedbackFinalGerenteData ??
      (original.feedbackFinalGerente?.trim() ? data : undefined),
    feedbackFinalCoordenadorAutorMatricula:
      original.feedbackFinalCoordenadorAutorMatricula ??
      (original.feedbackFinalCoordenador?.trim() ? coordenador?.matricula : undefined),
    feedbackFinalCoordenadorAutorNome:
      original.feedbackFinalCoordenadorAutorNome ??
      (original.feedbackFinalCoordenador?.trim() ? coordenador?.nome : undefined),
    feedbackFinalCoordenadorData:
      original.feedbackFinalCoordenadorData ??
      (original.feedbackFinalCoordenador?.trim() ? data : undefined),
  };
}

function mediaValores(valores: number[]): number {
  const validos = valores.filter((valor) => Number.isFinite(valor) && valor > 0);
  if (!validos.length) return 0;
  return validos.reduce((soma, valor) => soma + valor, 0) / validos.length;
}

function recalcularSubcriterio(
  sub: FeedbackSubcriterioDetalhado
): FeedbackSubcriterioDetalhado {
  const votos = sub.votosColegiado?.filter((voto) => voto.nota > 0) ?? [];
  const notaColegiado = votos.length
    ? mediaValores(votos.map((voto) => voto.nota))
    : sub.notaColegiado;
  return {
    ...sub,
    notaColegiado,
    notaFinal: mediaValores([
      sub.notaGerente,
      sub.notaCoordenador,
      notaColegiado,
    ]),
  };
}

function recalcularFeedback(feedback: Feedback): Feedback {
  const criterios = feedback.criteriosDetalhados?.map((criterio) => {
    const subcriterios = criterio.subcriterios.map(recalcularSubcriterio);
    return {
      ...criterio,
      subcriterios,
      nota: mediaValores(subcriterios.map((sub) => sub.notaFinal)),
    };
  });

  const notaMedia = criterios?.length
    ? mediaValores(criterios.map((criterio) => criterio.nota))
    : feedback.notaMedia;

  return {
    ...feedback,
    criteriosDetalhados: criterios,
    notaMedia,
    competencias: feedback.competencias.map((competencia) => {
      const criterio = criterios?.find(
        (item) => item.criterioId === competencia.competenciaId
      );
      return criterio
        ? {
            ...competencia,
            nota: criterio.nota,
            comentario: [
              criterio.observacaoGerente
                ? `Observação do Gerente: ${criterio.observacaoGerente}`
                : "",
              criterio.observacaoCoordenador
                ? `Observação do Coordenador: ${criterio.observacaoCoordenador}`
                : "",
            ]
              .filter(Boolean)
              .join("\n\n"),
          }
        : competencia;
    }),
  };
}

function mesclarVotosColegiado(
  original: VotoColegiado[] | undefined,
  recebido: VotoColegiado[] | undefined,
  usuarioAtual: Colaborador,
  podeColegiado: boolean,
  agora: string
): VotoColegiado[] {
  const mapa = new Map<number, VotoColegiado>();
  (original ?? []).forEach((voto) => mapa.set(voto.avaliadorMatricula, voto));

  if (podeColegiado) {
    const meuVoto = recebido?.find(
      (voto) => voto.avaliadorMatricula === usuarioAtual.matricula
    );
    if (meuVoto?.nota && meuVoto.nota > 0) {
      mapa.set(usuarioAtual.matricula, {
        avaliadorMatricula: usuarioAtual.matricula,
        avaliadorNome: usuarioAtual.nome,
        nota: meuVoto.nota,
        dataAtualizacao: agora,
      });
    }
  }

  return Array.from(mapa.values());
}

function mesclarCriterio(
  original: FeedbackCriterioDetalhado,
  recebido: FeedbackCriterioDetalhado,
  usuarioAtual: Colaborador,
  permissoes: ReturnType<typeof obterPermissoesAvaliacao>,
  agora: string
): FeedbackCriterioDetalhado {
  const subcriterios = original.subcriterios.map((subOriginal) => {
    const subRecebido = recebido.subcriterios.find(
      (item) => item.nome === subOriginal.nome
    ) ?? subOriginal;

    let notaGerente = subOriginal.notaGerente;
    let avaliadorGerenteMatricula = subOriginal.avaliadorGerenteMatricula;
    let avaliadorGerenteNome = subOriginal.avaliadorGerenteNome;
    let dataAvaliacaoGerente = subOriginal.dataAvaliacaoGerente;

    const gerentePodeAlterar =
      permissoes.podeAvaliarComoGerente &&
      (!avaliadorGerenteMatricula ||
        avaliadorGerenteMatricula === usuarioAtual.matricula ||
        notaGerente <= 0);
    if (gerentePodeAlterar && subRecebido.notaGerente !== notaGerente) {
      notaGerente = subRecebido.notaGerente;
      if (notaGerente > 0) {
        avaliadorGerenteMatricula = usuarioAtual.matricula;
        avaliadorGerenteNome = usuarioAtual.nome;
        dataAvaliacaoGerente = agora;
      }
    }

    let notaCoordenador = subOriginal.notaCoordenador;
    let avaliadorCoordenadorMatricula = subOriginal.avaliadorCoordenadorMatricula;
    let avaliadorCoordenadorNome = subOriginal.avaliadorCoordenadorNome;
    let dataAvaliacaoCoordenador = subOriginal.dataAvaliacaoCoordenador;

    const coordenadorPodeAlterar =
      permissoes.podeAvaliarComoCoordenador &&
      (!avaliadorCoordenadorMatricula ||
        avaliadorCoordenadorMatricula === usuarioAtual.matricula ||
        notaCoordenador <= 0);
    if (coordenadorPodeAlterar && subRecebido.notaCoordenador !== notaCoordenador) {
      notaCoordenador = subRecebido.notaCoordenador;
      if (notaCoordenador > 0) {
        avaliadorCoordenadorMatricula = usuarioAtual.matricula;
        avaliadorCoordenadorNome = usuarioAtual.nome;
        dataAvaliacaoCoordenador = agora;
      }
    }

    const votosColegiado = mesclarVotosColegiado(
      subOriginal.votosColegiado,
      subRecebido.votosColegiado,
      usuarioAtual,
      permissoes.podeAvaliarComoColegiado,
      agora
    );

    return recalcularSubcriterio({
      ...subOriginal,
      notaGerente,
      avaliadorGerenteMatricula,
      avaliadorGerenteNome,
      dataAvaliacaoGerente,
      notaCoordenador,
      avaliadorCoordenadorMatricula,
      avaliadorCoordenadorNome,
      dataAvaliacaoCoordenador,
      votosColegiado,
      notaColegiado: subRecebido.notaColegiado,
    });
  });

  let observacaoGerente = original.observacaoGerente;
  let observacaoGerenteAutorMatricula = original.observacaoGerenteAutorMatricula;
  let observacaoGerenteAutorNome = original.observacaoGerenteAutorNome;
  let observacaoGerenteData = original.observacaoGerenteData;
  if (
    permissoes.podeAvaliarComoGerente &&
    (!observacaoGerenteAutorMatricula ||
      observacaoGerenteAutorMatricula === usuarioAtual.matricula ||
      !observacaoGerente.trim()) &&
    recebido.observacaoGerente !== observacaoGerente
  ) {
    observacaoGerente = recebido.observacaoGerente;
    if (observacaoGerente.trim()) {
      observacaoGerenteAutorMatricula = usuarioAtual.matricula;
      observacaoGerenteAutorNome = usuarioAtual.nome;
      observacaoGerenteData = agora;
    }
  }

  let observacaoCoordenador = original.observacaoCoordenador;
  let observacaoCoordenadorAutorMatricula =
    original.observacaoCoordenadorAutorMatricula;
  let observacaoCoordenadorAutorNome = original.observacaoCoordenadorAutorNome;
  let observacaoCoordenadorData = original.observacaoCoordenadorData;
  if (
    permissoes.podeAvaliarComoCoordenador &&
    (!observacaoCoordenadorAutorMatricula ||
      observacaoCoordenadorAutorMatricula === usuarioAtual.matricula ||
      !observacaoCoordenador.trim()) &&
    recebido.observacaoCoordenador !== observacaoCoordenador
  ) {
    observacaoCoordenador = recebido.observacaoCoordenador;
    if (observacaoCoordenador.trim()) {
      observacaoCoordenadorAutorMatricula = usuarioAtual.matricula;
      observacaoCoordenadorAutorNome = usuarioAtual.nome;
      observacaoCoordenadorData = agora;
    }
  }

  return {
    ...original,
    subcriterios,
    nota: mediaValores(subcriterios.map((sub) => sub.notaFinal)),
    observacaoGerente,
    observacaoGerenteAutorMatricula,
    observacaoGerenteAutorNome,
    observacaoGerenteData,
    observacaoCoordenador,
    observacaoCoordenadorAutorMatricula,
    observacaoCoordenadorAutorNome,
    observacaoCoordenadorData,
  };
}

function mesclarEdicaoPorResponsabilidade(
  original: Feedback,
  recebido: Feedback,
  usuarioAtual: Colaborador
): Feedback {
  const colaboradores = getColaboradores();
  const colaborador = colaboradores.find(
    (item) => item.matricula === original.colaboradorId
  );
  const ciclo = getCiclosAvaliacao().find(
    (item) => item.ano === original.ano && item.ciclo === original.ciclo
  );
  if (!colaborador || !ciclo) return recebido;

  const base = comAutorLegado(original, colaborador, colaboradores);
  const permissoes = obterPermissoesAvaliacao(
    usuarioAtual,
    colaborador,
    colaboradores,
    ciclo
  );
  const agora = new Date().toISOString();

  const criteriosDetalhados = base.criteriosDetalhados?.map((criterio) => {
    const recebidoCriterio = recebido.criteriosDetalhados?.find(
      (item) => item.criterioId === criterio.criterioId
    );
    return recebidoCriterio
      ? mesclarCriterio(
          criterio,
          recebidoCriterio,
          usuarioAtual,
          permissoes,
          agora
        )
      : criterio;
  });

  let feedbackFinalGerente = base.feedbackFinalGerente;
  let feedbackFinalGerenteAutorMatricula = base.feedbackFinalGerenteAutorMatricula;
  let feedbackFinalGerenteAutorNome = base.feedbackFinalGerenteAutorNome;
  let feedbackFinalGerenteData = base.feedbackFinalGerenteData;
  if (
    permissoes.podeAvaliarComoGerente &&
    (!feedbackFinalGerenteAutorMatricula ||
      feedbackFinalGerenteAutorMatricula === usuarioAtual.matricula ||
      !feedbackFinalGerente?.trim()) &&
    recebido.feedbackFinalGerente !== feedbackFinalGerente
  ) {
    feedbackFinalGerente = recebido.feedbackFinalGerente;
    if (feedbackFinalGerente?.trim()) {
      feedbackFinalGerenteAutorMatricula = usuarioAtual.matricula;
      feedbackFinalGerenteAutorNome = usuarioAtual.nome;
      feedbackFinalGerenteData = agora;
    }
  }

  let feedbackFinalCoordenador = base.feedbackFinalCoordenador;
  let feedbackFinalCoordenadorAutorMatricula =
    base.feedbackFinalCoordenadorAutorMatricula;
  let feedbackFinalCoordenadorAutorNome = base.feedbackFinalCoordenadorAutorNome;
  let feedbackFinalCoordenadorData = base.feedbackFinalCoordenadorData;
  if (
    permissoes.podeAvaliarComoCoordenador &&
    (!feedbackFinalCoordenadorAutorMatricula ||
      feedbackFinalCoordenadorAutorMatricula === usuarioAtual.matricula ||
      !feedbackFinalCoordenador?.trim()) &&
    recebido.feedbackFinalCoordenador !== feedbackFinalCoordenador
  ) {
    feedbackFinalCoordenador = recebido.feedbackFinalCoordenador;
    if (feedbackFinalCoordenador?.trim()) {
      feedbackFinalCoordenadorAutorMatricula = usuarioAtual.matricula;
      feedbackFinalCoordenadorAutorNome = usuarioAtual.nome;
      feedbackFinalCoordenadorData = agora;
    }
  }

  return recalcularFeedback({
    ...recebido,
    criteriosDetalhados,
    feedbackFinalGerente,
    feedbackFinalGerenteAutorMatricula,
    feedbackFinalGerenteAutorNome,
    feedbackFinalGerenteData,
    feedbackFinalCoordenador,
    feedbackFinalCoordenadorAutorMatricula,
    feedbackFinalCoordenadorAutorNome,
    feedbackFinalCoordenadorData,
  });
}

export function saveFeedback(
  feedback: Feedback,
  usuarioAtual?: Colaborador
): void {
  const feedbacks = getFeedbacks();
  let paraSalvar = feedback;

  if (usuarioAtual) {
    // Em uma avaliação nova não existe histórico anterior a proteger, mas a
    // passagem pelo merge registra autoria de cada papel já preenchido.
    const vazio: Feedback = {
      ...feedback,
      competencias: feedback.competencias.map((item) => ({ ...item, nota: 0 })),
      notaMedia: 0,
      criteriosDetalhados: feedback.criteriosDetalhados?.map((criterio) => ({
        ...criterio,
        nota: 0,
        observacaoGerente: "",
        observacaoCoordenador: "",
        subcriterios: criterio.subcriterios.map((sub) => ({
          ...sub,
          notaGerente: 0,
          notaCoordenador: 0,
          notaColegiado: 0,
          votosColegiado: [],
          notaFinal: 0,
        })),
      })),
      feedbackFinalGerente: "",
      feedbackFinalCoordenador: "",
    };
    paraSalvar = mesclarEdicaoPorResponsabilidade(
      vazio,
      feedback,
      usuarioAtual
    );
  }

  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify([...feedbacks, paraSalvar])
  );
}

export function deleteFeedback(feedbackId: string): void {
  const updatedFeedbacks = getFeedbacks().filter(
    (feedback) => feedback.id !== feedbackId
  );
  localStorage.setItem(STORAGE_KEY, JSON.stringify(updatedFeedbacks));
}

export function updateFeedback(
  updatedFeedback: Feedback,
  usuarioAtual?: Colaborador
): void {
  const feedbacks = getFeedbacks();
  const feedbackAtual = feedbacks.find(
    (feedback) => feedback.id === updatedFeedback.id
  );

  if (usuarioAtual && feedbackAtual?.status === "CONCLUIDA") {
    throw new Error("Avaliações concluídas não podem ser alteradas.");
  }

  const updatedFeedbacks = feedbacks.map((feedback) => {
    if (feedback.id !== updatedFeedback.id) return feedback;
    return usuarioAtual
      ? mesclarEdicaoPorResponsabilidade(
          feedback,
          updatedFeedback,
          usuarioAtual
        )
      : updatedFeedback;
  });

  localStorage.setItem(STORAGE_KEY, JSON.stringify(updatedFeedbacks));
}
