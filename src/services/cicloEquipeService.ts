import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import { funcaoUsaEstruturaAvaliacaoAnalista } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { criteriosAvaliacao } from "../data/modeloAvaliacao";
import { getColaboradores } from "./colaboradorStorage";
import {
  avaliacaoEstaVaziaParaCleanupInterno,
  existeAvaliacaoNaoCanceladaNoCiclo,
  getFeedbacks,
  removerAvaliacaoVaziaNoCleanupInterno,
  saveFeedback,
  updateFeedback,
} from "./feedbackStorage";
import { getColaboradoresVisiveis } from "./visibilidadeColaboradores";
import { getMetasDoCiclo } from "./metaStorage";
import {
  getAplicabilidadeNoCiclo,
  getColaboradoresEfetivosNoCiclo,
  getColaboradorEfetivoNoCiclo,
} from "./historicoOrganizacionalStorage";

export type SituacaoAvaliacaoCiclo =
  | "NAO_INICIADA"
  | "EM_ANDAMENTO"
  | "PRONTA_PARA_FEEDBACK"
  | "CONCLUIDA"
  | "CANCELADA"
  | "SUSPENSA"
  | "NAO_APLICAVEL";

export type SituacaoPapelAvaliacao =
  | "NAO_APLICA"
  | "NAO_INICIADO"
  | "EM_ANDAMENTO"
  | "CONCLUIDO"
  | "PENDENTE";

export interface ProgressoPapelPainel {
  situacao: SituacaoPapelAvaliacao;
  preenchidos: number;
  total: number;
}

export interface LinhaPainelCiclo {
  colaborador: Colaborador;
  feedback?: Feedback;
  situacao: SituacaoAvaliacaoCiclo;
  gerente: ProgressoPapelPainel;
  coordenador: ProgressoPapelPainel;
  colegiado: ProgressoPapelPainel;
  possuiPendencias: boolean;
  motivoNaoAplicavel?: string;
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
  const efetivos = getColaboradoresEfetivosNoCiclo(ciclo, colaboradores);
  const feedbacks = getFeedbacks();

  const elegiveis = efetivos.filter(
    (colaborador) =>
      getAplicabilidadeNoCiclo(
        colaboradores.find((item) => item.matricula === colaborador.matricula) ?? colaborador,
        ciclo
      ).aplicavel &&
      colaborador.status === "ATIVO" &&
      colaborador.funcao !== "GERENTE" &&
      colaborador.gestorDiretoMatricula !== undefined
  );

  let criadas = 0;
  let existentes = 0;

  elegiveis.forEach((colaborador) => {
    const jaExiste = existeAvaliacaoNaoCanceladaNoCiclo(
      feedbacks,
      colaborador.matricula,
      ciclo.ano,
      ciclo.ciclo
    );

    if (jaExiste) {
      existentes += 1;
      return;
    }

    saveFeedback(criarFeedbackVazio(colaborador, ciclo));
    criadas += 1;
  });

  return { criadas, existentes, elegiveis: elegiveis.length };
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
  if (feedback.status === "CANCELADA") return "CANCELADA";
  if (feedback.status === "CONCLUIDA") return "CONCLUIDA";
  if (feedback.status === "PRONTA_PARA_FEEDBACK") {
    return "PRONTA_PARA_FEEDBACK";
  }
  return temPreenchimento(feedback) ? "EM_ANDAMENTO" : "NAO_INICIADA";
}

function progressoNaoAplicavel(): ProgressoPapelPainel {
  return { situacao: "NAO_APLICA", preenchidos: 0, total: 0 };
}

function criarProgressoPapel(
  preenchidos: number,
  total: number,
  cicloEncerrado: boolean
): ProgressoPapelPainel {
  if (total === 0) return progressoNaoAplicavel();
  if (preenchidos >= total) {
    return { situacao: "CONCLUIDO", preenchidos: total, total };
  }
  if (cicloEncerrado) {
    return { situacao: "PENDENTE", preenchidos, total };
  }
  if (preenchidos === 0) {
    return { situacao: "NAO_INICIADO", preenchidos, total };
  }
  return { situacao: "EM_ANDAMENTO", preenchidos, total };
}

function calcularProgressoPapeis(
  colaborador: Colaborador,
  feedback: Feedback | undefined,
  colaboradores: Colaborador[],
  cicloEncerrado: boolean,
  aplicavel: boolean
): {
  gerente: ProgressoPapelPainel;
  coordenador: ProgressoPapelPainel;
  colegiado: ProgressoPapelPainel;
} {
  if (!aplicavel) {
    return {
      gerente: progressoNaoAplicavel(),
      coordenador: progressoNaoAplicavel(),
      colegiado: progressoNaoAplicavel(),
    };
  }

  const subcriterios =
    feedback?.criteriosDetalhados?.flatMap((criterio) => criterio.subcriterios) ?? [];
  const totalSubcriterios =
    feedback?.criteriosDetalhados?.reduce(
      (total, criterio) => total + criterio.subcriterios.length,
      0
    ) ??
    criteriosAvaliacao.reduce(
      (total, criterio) => total + criterio.subcriterios.length,
      0
    );

  const gerenteNotas = subcriterios.filter(
    (subcriterio) => subcriterio.notaGerente > 0
  ).length;
  const gerenteFeedbackFinal =
    (feedback?.feedbackFinalGerente?.trim().length ?? 0) > 0 ? 1 : 0;
  const gerente = criarProgressoPapel(
    gerenteNotas + gerenteFeedbackFinal,
    totalSubcriterios + 1,
    cicloEncerrado
  );

  const gestorDireto = colaborador.gestorDiretoMatricula
    ? colaboradores.find(
        (item) => item.matricula === colaborador.gestorDiretoMatricula
      )
    : undefined;
  const precisaCoordenador =
    funcaoUsaEstruturaAvaliacaoAnalista(colaborador.funcao) &&
    gestorDireto?.funcao === "COORDENADOR";

  const coordenadorNotas = precisaCoordenador
    ? subcriterios.filter((subcriterio) => subcriterio.notaCoordenador > 0).length
    : 0;
  const coordenadorFeedbackFinal =
    precisaCoordenador &&
    (feedback?.feedbackFinalCoordenador?.trim().length ?? 0) > 0
      ? 1
      : 0;
  const coordenador = criarProgressoPapel(
    coordenadorNotas + coordenadorFeedbackFinal,
    precisaCoordenador ? totalSubcriterios + 1 : 0,
    cicloEncerrado
  );

  let votosRecebidos = 0;
  let votosEsperados = 0;
  if (funcaoUsaEstruturaAvaliacaoAnalista(colaborador.funcao)) {
    const atuais = new Set(colaborador.avaliadoresColegiadoMatriculas ?? []);

    if (subcriterios.length === 0) {
      // Quando a avaliação ainda não foi criada, ainda assim existe uma
      // expectativa de votos do colegiado baseada na estrutura vigente
      // do colaborador e na quantidade padrão de subcritérios do modelo.
      votosEsperados = atuais.size * totalSubcriterios;
    } else {
      subcriterios.forEach((subcriterio) => {
        const historicos = new Set(
          (subcriterio.votosColegiado ?? [])
            .filter((voto) => voto.nota > 0)
            .map((voto) => voto.avaliadorMatricula)
        );
        const uniao = new Set([...atuais, ...historicos]);
        votosEsperados += uniao.size;
        votosRecebidos += Array.from(uniao).filter((matricula) =>
          (subcriterio.votosColegiado ?? []).some(
            (voto) => voto.avaliadorMatricula === matricula && voto.nota > 0
          )
        ).length;
      });
    }
  }

  const colegiado = criarProgressoPapel(
    votosRecebidos,
    votosEsperados,
    cicloEncerrado
  );

  return { gerente, coordenador, colegiado };
}

export function getPainelCiclo(
  ciclo: CicloAvaliacao,
  usuario: Colaborador,
  options: { incluirCanceladas?: boolean } = {}
): LinhaPainelCiclo[] {
  const colaboradoresBase = getColaboradores();
  const colaboradores = getColaboradoresEfetivosNoCiclo(
    ciclo,
    colaboradoresBase
  );
  const usuarioEfetivo =
    colaboradores.find((item) => item.matricula === usuario.matricula) ?? usuario;
  const feedbacks = getFeedbacks();

  const elegiveis = getColaboradoresVisiveis(usuarioEfetivo, colaboradores)
    .filter((colaborador) => colaborador.funcao !== "GERENTE")
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  return elegiveis.flatMap((colaborador) => {
    const base =
      colaboradoresBase.find((item) => item.matricula === colaborador.matricula) ??
      colaborador;
    const aplicabilidade = getAplicabilidadeNoCiclo(base, ciclo);
    const feedback = feedbacks.find(
      (item) =>
        item.colaboradorId === colaborador.matricula &&
        item.ano === ciclo.ano &&
        item.ciclo === ciclo.ciclo
    );

    if (feedback?.status === "CANCELADA" && !options.incluirCanceladas) {
      return [];
    }

    const progressoPapeis = calcularProgressoPapeis(
      colaborador,
      feedback,
      colaboradores,
      ciclo.status === "ENCERRADO",
      aplicabilidade.aplicavel
    );

    let situacao = getSituacaoAvaliacaoCiclo(feedback);
    if (!aplicabilidade.aplicavel && feedback?.status !== "CANCELADA") {
      situacao = aplicabilidade.motivo.startsWith("Suspensa")
        ? "SUSPENSA"
        : "NAO_APLICAVEL";
    }

    const possuiPendencias =
      feedback?.status !== "CANCELADA" &&
      aplicabilidade.aplicavel &&
      ([
        progressoPapeis.gerente,
        progressoPapeis.coordenador,
        progressoPapeis.colegiado,
      ].some(
        (papel) =>
          papel.situacao !== "NAO_APLICA" && papel.situacao !== "CONCLUIDO"
      ) ||
        feedback?.encerradaComPendencias === true);

    return [{
      colaborador,
      feedback,
      situacao,
      ...progressoPapeis,
      possuiPendencias,
      motivoNaoAplicavel: aplicabilidade.aplicavel
        ? undefined
        : aplicabilidade.motivo,
    }];
  });
}

export function excluirAvaliacoesVaziasDoCiclo(
  ciclo: CicloAvaliacao
): { excluidas: number; bloqueadas: number } {
  const feedbacksDoCiclo = getFeedbacks().filter(
    (feedback) => feedback.ano === ciclo.ano && feedback.ciclo === ciclo.ciclo
  );
  const preenchidas = feedbacksDoCiclo.filter(
    (feedback) => !avaliacaoEstaVaziaParaCleanupInterno(feedback)
  );

  if (preenchidas.length > 0) {
    throw new Error(
      `Não é possível excluir este ciclo porque ${preenchidas.length} avaliação${
        preenchidas.length > 1 ? "ões já possuem" : " já possui"
      } dados preenchidos.`
    );
  }

  feedbacksDoCiclo.forEach((feedback) =>
    removerAvaliacaoVaziaNoCleanupInterno(feedback.id)
  );
  return { excluidas: feedbacksDoCiclo.length, bloqueadas: 0 };
}

export interface PendenciaAvaliacao {
  colaboradorId: number;
  colaboradorNome: string;
  papel: "Gerente" | "Coordenador" | "Colegiado" | "Metas";
  quantidade: number;
  detalhes?: string[];
}

function notasEsperadasDoSubcriterio(
  colaborador: Colaborador,
  subcriterio: NonNullable<Feedback["criteriosDetalhados"]>[number]["subcriterios"][number]
): Array<{ papel: PendenciaAvaliacao["papel"]; preenchida: boolean; quantidade?: number }> {
  const resultado: Array<{
    papel: PendenciaAvaliacao["papel"];
    preenchida: boolean;
    quantidade?: number;
  }> = [
    { papel: "Gerente", preenchida: subcriterio.notaGerente > 0 },
  ];

  if (funcaoUsaEstruturaAvaliacaoAnalista(colaborador.funcao)) {
    const gestorDiretoMatricula = colaborador.gestorDiretoMatricula;
    resultado.push({
      papel: "Coordenador",
      preenchida:
        !gestorDiretoMatricula || subcriterio.notaCoordenador > 0,
    });

    const atuais = new Set(colaborador.avaliadoresColegiadoMatriculas ?? []);
    const historicos = new Set(
      (subcriterio.votosColegiado ?? [])
        .filter((voto) => voto.nota > 0)
        .map((voto) => voto.avaliadorMatricula)
    );
    const esperados = new Set([...atuais, ...historicos]);
    const recebidos = Array.from(esperados).filter((matricula) =>
      (subcriterio.votosColegiado ?? []).some(
        (voto) => voto.avaliadorMatricula === matricula && voto.nota > 0
      )
    ).length;

    if (esperados.size > 0) {
      resultado.push({
        papel: "Colegiado",
        preenchida: recebidos >= esperados.size,
        quantidade: Math.max(0, esperados.size - recebidos),
      });
    }
  }

  return resultado;
}

export function analisarPendenciasDoCiclo(
  ciclo: CicloAvaliacao
): PendenciaAvaliacao[] {
  const colaboradoresBase = getColaboradores();
  const colaboradores = getColaboradoresEfetivosNoCiclo(ciclo, colaboradoresBase);
  const feedbacks = getFeedbacks().filter(
    (feedback) => feedback.ano === ciclo.ano && feedback.ciclo === ciclo.ciclo
  );
  const pendencias = new Map<string, PendenciaAvaliacao>();

  feedbacks.forEach((feedback) => {
    if (feedback.status === "CANCELADA") return;

    const colaborador = colaboradores.find(
      (item) => item.matricula === feedback.colaboradorId
    );
    const base = colaboradoresBase.find(
      (item) => item.matricula === feedback.colaboradorId
    );
    if (!colaborador || !base || !getAplicabilidadeNoCiclo(base, ciclo).aplicavel) {
      return;
    }

    feedback.criteriosDetalhados?.forEach((criterio) => {
      criterio.subcriterios.forEach((subcriterio) => {
        notasEsperadasDoSubcriterio(colaborador, subcriterio).forEach(
          ({ papel, preenchida, quantidade }) => {
            if (preenchida) return;
            const chave = `${colaborador.matricula}-${papel}`;
            const incremento = quantidade ?? 1;
            const atual = pendencias.get(chave);
            if (atual) {
              atual.quantidade += incremento;
            } else {
              pendencias.set(chave, {
                colaboradorId: colaborador.matricula,
                colaboradorNome: colaborador.nome,
                papel,
                quantidade: incremento,
              });
            }
          }
        );
      });
    });
  });

  getMetasDoCiclo(ciclo.id)
    .filter((meta) => {
      const base = colaboradoresBase.find(
        (item) => item.matricula === meta.colaboradorMatricula
      );
      return (
        base &&
        getAplicabilidadeNoCiclo(base, ciclo).aplicavel &&
        (meta.status === "EM_ANDAMENTO" ||
          !meta.resultadoFinal?.trim() ||
          typeof meta.atingida !== "boolean")
      );
    })
    .forEach((meta) => {
      const chave = `${meta.colaboradorMatricula}-Metas`;
      const atual = pendencias.get(chave);
      if (atual) {
        atual.quantidade += 1;
        atual.detalhes = [...(atual.detalhes ?? []), meta.descricao];
      } else {
        pendencias.set(chave, {
          colaboradorId: meta.colaboradorMatricula,
          colaboradorNome: meta.colaboradorNome,
          papel: "Metas",
          quantidade: 1,
          detalhes: [meta.descricao],
        });
      }
    });

  return Array.from(pendencias.values()).sort((a, b) =>
    a.colaboradorNome.localeCompare(b.colaboradorNome, "pt-BR")
  );
}

function mediaNotasValidas(notas: number[]): number {
  const validas = notas.filter((nota) => nota > 0);
  if (validas.length === 0) return 0;
  return validas.reduce((soma, nota) => soma + nota, 0) / validas.length;
}

function recalcularAvaliacaoParcial(
  feedback: Feedback,
  colaborador: Colaborador,
  pendencias: PendenciaAvaliacao[]
): Feedback {
  const criteriosDetalhados = (feedback.criteriosDetalhados ?? []).map(
    (criterio) => {
      const subcriterios = criterio.subcriterios.map((subcriterio) => {
        const notas = [subcriterio.notaGerente];
        if (funcaoUsaEstruturaAvaliacaoAnalista(colaborador.funcao)) {
          notas.push(subcriterio.notaCoordenador, subcriterio.notaColegiado);
        }
        return { ...subcriterio, notaFinal: mediaNotasValidas(notas) };
      });
      return {
        ...criterio,
        subcriterios,
        nota: mediaNotasValidas(subcriterios.map((sub) => sub.notaFinal)),
      };
    }
  );

  const notaMedia = mediaNotasValidas(
    criteriosDetalhados.map((criterio) => criterio.nota)
  );
  const pendenciasDesteColaborador = pendencias
    .filter(
      (item) =>
        item.colaboradorId === feedback.colaboradorId && item.papel !== "Metas"
    )
    .map(
      (item) =>
        `${item.papel}: ${item.quantidade} nota${
          item.quantidade === 1 ? "" : "s"
        } pendente${item.quantidade === 1 ? "" : "s"}`
    );
  const agora = new Date().toISOString();

  return {
    ...feedback,
    criteriosDetalhados,
    notaMedia,
    status: "CONCLUIDA",
    dataConclusao: feedback.dataConclusao ?? agora,
    dataUltimaAtualizacao: agora,
    encerradaComPendencias: pendenciasDesteColaborador.length > 0,
    pendenciasEncerramento: pendenciasDesteColaborador,
  };
}

export function concluirAvaliacoesNoEncerramentoDoCiclo(
  ciclo: CicloAvaliacao,
  pendencias: PendenciaAvaliacao[]
): void {
  const colaboradoresBase = getColaboradores();

  getFeedbacks()
    .filter(
      (feedback) =>
        feedback.ano === ciclo.ano &&
        feedback.ciclo === ciclo.ciclo &&
        feedback.status !== "CANCELADA"
    )
    .forEach((feedback) => {
      const base = colaboradoresBase.find(
        (item) => item.matricula === feedback.colaboradorId
      );
      if (!base) return;
      const colaborador = getColaboradorEfetivoNoCiclo(
        base,
        ciclo,
        colaboradoresBase
      );
      updateFeedback(recalcularAvaliacaoParcial(feedback, colaborador, pendencias));
    });
}
