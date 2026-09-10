import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import { funcaoUsaEstruturaAvaliacaoAnalista } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { criteriosAvaliacao } from "../data/modeloAvaliacao";
import { getColaboradores } from "./colaboradorStorage";
import { getCiclosAvaliacao } from "./cicloAvaliacaoStorage";
import {
  avaliacaoEstaVaziaParaCleanupInterno,
  existeAvaliacaoNaoCanceladaNoCiclo,
  getFeedbacks,
  removerAvaliacaoVaziaNoCleanupInterno,
} from "./feedbackStorage";
import {
  criarAvaliacaoSoberana,
  lerStatusSoberano,
  concluirAvaliacaoSoberana,
  type DependenciasAcessoAvaliacoes,
} from "./acessoAvaliacoesSoberanas";
import {
  lerAvaliacoesDoCiclo,
  registrarAvaliacoesDoCiclo,
} from "../infrastructure/supabase/avaliacoes/cutover";
import { getColaboradoresVisiveis } from "./visibilidadeColaboradores";
import { getMetasDoCiclo } from "./metaStorage";
import {
  getAplicabilidadeNoCiclo,
  getColaboradoresEfetivosNoCiclo,
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

/**
 * Dependências das operações soberanas de ciclo. O `organizationId` é apenas
 * INTENÇÃO: a fronteira confiável o revalida contra a membership ativa do ator
 * (`auth.uid()`) e é ela quem decide. Sem caminho novo configurado a operação é
 * recusada — nunca cai para o `localStorage` (D12/§11.3).
 */
export interface DependenciasCicloEquipe extends DependenciasAcessoAvaliacoes {
  readonly organizationId: string;
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

/**
 * Criação AUTOMÁTICA das avaliações do ciclo ativado — SOBERANA.
 *
 * A partir do cutover, a avaliação nova existe EXCLUSIVAMENTE no PostgreSQL
 * (D12): este fluxo deixa de escrever qualquer registro em `localStorage`. O
 * ciclo é resolvido por ano+número e o colaborador pela matrícula, ambos na
 * fronteira confiável (ponte F3-01); os participantes são snapshotados
 * server-side por `evaluation_criar`.
 *
 * A resposta distingue três resultados, porque "já existe" não é erro:
 * - `criadas`: avaliação nova criada no banco;
 * - `existentes`: já havia avaliação não cancelada (legado ou banco);
 * - `bloqueadas`: o servidor recusou (ex.: ciclo ainda não existe no
 *   PostgreSQL, snapshot de ciclo ausente). Nada é criado no lugar dela.
 */
export async function criarAvaliacoesDoCicloAtivado(
  ciclo: CicloAvaliacao,
  deps: DependenciasCicloEquipe
): Promise<{ criadas: number; existentes: number; bloqueadas: number }> {
  const colaboradores = getColaboradores();
  const efetivos = getColaboradoresEfetivosNoCiclo(ciclo, colaboradores);
  const feedbacksLegados = getFeedbacks();

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
  let bloqueadas = 0;

  for (const colaborador of elegiveis) {
    // Acervo LEGADO (somente leitura): uma avaliação não cancelada já existente
    // no legado continua contando como existente — o cutover não a duplica.
    const jaExisteNoLegado = existeAvaliacaoNaoCanceladaNoCiclo(
      feedbacksLegados,
      colaborador.matricula,
      ciclo.ano,
      ciclo.ciclo
    );

    if (jaExisteNoLegado) {
      existentes += 1;
      continue;
    }

    const resultado = await criarAvaliacaoSoberana(
      {
        organizationId: deps.organizationId,
        ano: ciclo.ano,
        ciclo: ciclo.ciclo,
        matriculaAvaliado: colaborador.matricula,
      },
      deps
    );

    if (resultado.ok && resultado.data) {
      // CACHE DE NAVEGAÇÃO (não é autoridade, não é tenant): registra o id
      // soberano do ciclo E o vínculo com o colaborador, no namespace da
      // organização ativa, para que a tela localize a avaliação nova depois do
      // reload (ela nunca existe no legado).
      registrarAvaliacoesDoCiclo(
        deps.organizationId,
        ciclo.ano,
        ciclo.ciclo,
        [resultado.data.evaluationId],
        deps.armazenamento ?? null,
        colaborador.matricula
      );
      criadas += 1;
    } else {
      // Recusa do servidor (ou ausência do caminho novo): fail-closed. Não há
      // escrita local de compensação e a contagem é reportada à tela.
      bloqueadas += 1;
    }
  }

  return { criadas, existentes, bloqueadas };
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
  const cicloPersistido = getCiclosAvaliacao().find(
    (item) => item.id === ciclo.id
  );
  if (!cicloPersistido) throw new Error("Ciclo não encontrado.");
  if (cicloPersistido.status !== "PLANEJADO") {
    throw new Error(
      "Somente ciclos planejados podem ser excluídos fisicamente."
    );
  }

  const feedbacksDoCiclo = getFeedbacks().filter(
    (feedback) =>
      feedback.ano === cicloPersistido.ano &&
      feedback.ciclo === cicloPersistido.ciclo
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

/**
 * Pendências do fechamento. Lê o ACERVO (legado somente leitura + avaliações
 * novas do banco) para relatar o que falta; não decide completude oficial — a
 * completude que autoriza a conclusão normal é calculada no servidor (D18).
 */
export function analisarPendenciasDoCiclo(
  ciclo: CicloAvaliacao
): PendenciaAvaliacao[] {
  const cicloPersistido = getCiclosAvaliacao().find(
    (item) => item.id === ciclo.id
  );
  if (cicloPersistido?.status === "CANCELADO") return [];

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

/**
 * Encerramento do ciclo: CONCLUSÃO SOBERANA das avaliações NOVAS.
 *
 * A partir do cutover o frontend NÃO recalcula nota oficial (D13) e NÃO converte
 * avaliação incompleta em `CONCLUIDA` (D18). Para cada avaliação que existe
 * exclusivamente no PostgreSQL — alcançada pelo livro-caixa do ciclo, porque ela
 * nunca está no `localStorage` — o frontend pede a conclusão ao servidor: ele
 * decide a completude e materializa o agregado na mesma transação.
 *
 * A completude NÃO é presumida pela ausência de pendências locais: quem responde
 * é o banco (fail-closed). As recusas são contadas e devolvidas para a tela
 * relatar, sem inventar estado local e sem escrever em `localStorage`.
 */
export async function concluirAvaliacoesNoEncerramentoDoCiclo(
  ciclo: CicloAvaliacao,
  deps: DependenciasCicloEquipe
): Promise<{ concluidas: number; bloqueadas: number }> {
  const idsSoberanos = lerAvaliacoesDoCiclo(
    deps.organizationId,
    ciclo.ano,
    ciclo.ciclo,
    deps.armazenamento ?? null
  );

  let concluidas = 0;
  let bloqueadas = 0;

  for (const evaluationId of idsSoberanos) {
    const status = await lerStatusSoberano(
      { organizationId: deps.organizationId, evaluationId },
      deps
    );

    // Sem status real não há decisão: falha de leitura é fail-closed.
    if (!status.ok || !status.data) {
      bloqueadas += 1;
      continue;
    }

    // Já concluída ou cancelada não é recusa nem reabertura: é o estado real.
    if (status.data.status === "CONCLUIDA" || status.data.status === "CANCELADA") {
      continue;
    }

    const conclusao = await concluirAvaliacaoSoberana(
      { organizationId: deps.organizationId, evaluationId },
      deps
    );

    if (conclusao.ok) concluidas += 1;
    else bloqueadas += 1;
  }

  return { concluidas, bloqueadas };
}
