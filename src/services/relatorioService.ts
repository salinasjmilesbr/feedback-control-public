import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { ItemEscalaAvaliacao } from "../types/EscalaAvaliacao";
import { criteriosAvaliacao } from "../data/modeloAvaliacao";
import { getPainelCiclo, type SituacaoAvaliacaoCiclo } from "./cicloEquipeService";
import { getEscalaAvaliacao, getItemEscalaPorNota } from "./escalaAvaliacaoStorage";

export interface RelatorioFaixaNota {
  nota: number;
  significado: string;
  quantidade: number;
  percentual: number;
  cor: string;
  corFundo: string;
}

export interface RelatorioCriterio {
  criterioId: string;
  criterioNome: string;
  media: number;
  quantidadeAvaliacoes: number;
}

export interface RelatorioColaborador {
  matricula: number;
  nome: string;
  funcao: Colaborador["funcao"];
  senioridade: Colaborador["senioridade"];
  gestorDiretoMatricula?: number;
  situacao: SituacaoAvaliacaoCiclo;
  notaMedia: number;
  possuiNotaConsolidada: boolean;
  faixa?: ItemEscalaAvaliacao;
}



export type FiltroCargoRelatorio =
  | "COORDENADOR"
  | "CONSULTOR"
  | "ANALISTA_SENIOR"
  | "ANALISTA_PLENO"
  | "ANALISTA_JUNIOR"
  | "ESTAGIARIO";

export interface FiltrosRelatorio {
  coordenadorMatricula?: number;
  cargo?: FiltroCargoRelatorio;
  situacao?: SituacaoAvaliacaoCiclo;
  faixaNota?: number;
}

function atendeFiltroCargo(
  colaborador: Colaborador,
  cargo: FiltroCargoRelatorio | undefined
): boolean {
  if (!cargo) return true;
  if (cargo === "COORDENADOR") return colaborador.funcao === "COORDENADOR";
  if (cargo === "CONSULTOR") return colaborador.funcao === "CONSULTOR";
  if (cargo === "ESTAGIARIO") return colaborador.funcao === "ESTAGIARIO";
  if (cargo === "ANALISTA_SENIOR") {
    return colaborador.funcao === "ANALISTA" && colaborador.senioridade === "SENIOR";
  }
  if (cargo === "ANALISTA_PLENO") {
    return colaborador.funcao === "ANALISTA" && colaborador.senioridade === "PLENO";
  }
  if (cargo === "ANALISTA_JUNIOR") {
    return colaborador.funcao === "ANALISTA" && colaborador.senioridade === "JUNIOR";
  }
  return true;
}

function aplicarFiltrosRelatorio(
  linhas: ReturnType<typeof getPainelCiclo>,
  filtros: FiltrosRelatorio | undefined,
  escala: ItemEscalaAvaliacao[]
) {
  if (!filtros) return linhas;

  return linhas.filter((linha) => {
    if (
      filtros.coordenadorMatricula !== undefined &&
      linha.colaborador.gestorDiretoMatricula !== filtros.coordenadorMatricula
    ) {
      return false;
    }

    if (!atendeFiltroCargo(linha.colaborador, filtros.cargo)) {
      return false;
    }

    if (filtros.situacao && linha.situacao !== filtros.situacao) {
      return false;
    }

    if (filtros.faixaNota !== undefined) {
      const notaMedia = linha.feedback?.notaMedia ?? 0;
      if (!possuiNotaConsolidada(linha.situacao, notaMedia)) {
        return false;
      }

      if (getItemEscalaPorNota(notaMedia, escala).nota !== filtros.faixaNota) {
        return false;
      }
    }

    return true;
  });
}

export interface RelatorioVisaoGeral {
  totalElegiveis: number;
  concluidas: number;
  prontasParaFeedback: number;
  emAndamento: number;
  naoIniciadas: number;
  suspensasOuNaoAplicaveis: number;
  avaliacoesComNota: number;
  mediaEquipe: number;
  distribuicao: RelatorioFaixaNota[];
  criterios: RelatorioCriterio[];
  colaboradores: RelatorioColaborador[];
}

function media(valores: number[]): number {
  const validos = valores.filter((valor) => Number.isFinite(valor) && valor > 0);
  if (!validos.length) return 0;
  return validos.reduce((soma, valor) => soma + valor, 0) / validos.length;
}

function possuiNotaConsolidada(
  situacao: SituacaoAvaliacaoCiclo,
  notaMedia: number
): boolean {
  return (
    notaMedia > 0 &&
    (situacao === "PRONTA_PARA_FEEDBACK" || situacao === "CONCLUIDA")
  );
}

/**
 * Relatórios do coordenador consideram somente sua equipe direta.
 * Participações como colegiado pertencem ao painel operacional, mas não entram
 * na consolidação de desempenho da equipe do coordenador.
 */
function linhasDoEscopo(
  ciclo: CicloAvaliacao,
  usuario: Colaborador
) {
  const linhas = getPainelCiclo(ciclo, usuario);

  if (usuario.funcao === "COORDENADOR") {
    return linhas.filter(
      (linha) =>
        linha.colaborador.gestorDiretoMatricula === usuario.matricula
    );
  }

  return linhas;
}

export function getRelatorioVisaoGeral(
  ciclo: CicloAvaliacao,
  usuario: Colaborador,
  filtros?: FiltrosRelatorio
): RelatorioVisaoGeral {
  const escala = getEscalaAvaliacao();
  const linhas = aplicarFiltrosRelatorio(
    linhasDoEscopo(ciclo, usuario),
    filtros,
    escala
  );

  const colaboradores: RelatorioColaborador[] = linhas
    .map((linha) => {
      const notaMedia = linha.feedback?.notaMedia ?? 0;
      const consolidada = possuiNotaConsolidada(linha.situacao, notaMedia);

      return {
        matricula: linha.colaborador.matricula,
        nome: linha.colaborador.nome,
        funcao: linha.colaborador.funcao,
        senioridade: linha.colaborador.senioridade,
        gestorDiretoMatricula: linha.colaborador.gestorDiretoMatricula,
        situacao: linha.situacao,
        notaMedia,
        possuiNotaConsolidada: consolidada,
        faixa: consolidada
          ? getItemEscalaPorNota(notaMedia, escala)
          : undefined,
      };
    })
    .sort((a, b) => {
      const ordemFuncao = (item: RelatorioColaborador): number => {
        if (item.funcao === "COORDENADOR") return 1;
        if (item.funcao === "CONSULTOR") return 2;
        if (item.funcao === "ANALISTA" && item.senioridade === "SENIOR") return 3;
        if (item.funcao === "ANALISTA" && item.senioridade === "PLENO") return 4;
        if (item.funcao === "ANALISTA" && item.senioridade === "JUNIOR") return 5;
        if (item.funcao === "ANALISTA") return 6;
        if (item.funcao === "ESTAGIARIO") return 7;
        return 8;
      };

      const diferencaFuncao = ordemFuncao(a) - ordemFuncao(b);
      if (diferencaFuncao !== 0) return diferencaFuncao;

      return a.nome.localeCompare(b.nome, "pt-BR");
    });

  const linhasComNota = linhas.filter((linha) =>
    possuiNotaConsolidada(linha.situacao, linha.feedback?.notaMedia ?? 0)
  );

  const mediaEquipe = media(
    linhasComNota.map((linha) => linha.feedback?.notaMedia ?? 0)
  );

  const distribuicao = [...escala]
    .sort((a, b) => b.nota - a.nota)
    .map((item) => {
      const quantidade = linhasComNota.filter(
        (linha) =>
          getItemEscalaPorNota(linha.feedback?.notaMedia ?? 0, escala).nota ===
          item.nota
      ).length;

      return {
        nota: item.nota,
        significado: item.significado,
        quantidade,
        percentual: linhasComNota.length
          ? (quantidade / linhasComNota.length) * 100
          : 0,
        cor: item.cor,
        corFundo: item.corFundo,
      };
    });

  const criterios = criteriosAvaliacao.map((criterioModelo) => {
    const notas = linhasComNota
      .map((linha) =>
        linha.feedback?.criteriosDetalhados?.find(
          (criterio) => criterio.criterioId === criterioModelo.id
        )?.nota ?? 0
      )
      .filter((nota) => nota > 0);

    return {
      criterioId: criterioModelo.id,
      criterioNome: criterioModelo.nome,
      media: media(notas),
      quantidadeAvaliacoes: notas.length,
    };
  });

  const contar = (situacao: SituacaoAvaliacaoCiclo) =>
    linhas.filter((linha) => linha.situacao === situacao).length;

  return {
    totalElegiveis: linhas.length,
    concluidas: contar("CONCLUIDA"),
    prontasParaFeedback: contar("PRONTA_PARA_FEEDBACK"),
    emAndamento: contar("EM_ANDAMENTO"),
    naoIniciadas: contar("NAO_INICIADA"),
    suspensasOuNaoAplicaveis:
      contar("SUSPENSA") + contar("NAO_APLICAVEL"),
    avaliacoesComNota: linhasComNota.length,
    mediaEquipe,
    distribuicao,
    criterios,
    colaboradores,
  };
}


export interface RelatorioComparacaoCriterio {
  criterioId: string;
  criterioNome: string;
  atual: number;
  anterior: number;
  variacao?: number;
}

export interface RelatorioComparacaoCiclos {
  possuiComparacao: boolean;
  mediaAtual: number;
  mediaAnterior: number;
  variacaoMedia?: number;
  melhoraram: number;
  mantiveram: number;
  pioraram: number;
  comparaveis: number;
  criterios: RelatorioComparacaoCriterio[];
}

export function getRelatorioComparacaoCiclos(
  cicloAtual: CicloAvaliacao,
  cicloAnterior: CicloAvaliacao | undefined,
  usuario: Colaborador,
  filtros?: FiltrosRelatorio
): RelatorioComparacaoCiclos {
  const atual = getRelatorioVisaoGeral(cicloAtual, usuario, filtros);

  if (!cicloAnterior) {
    return {
      possuiComparacao: false,
      mediaAtual: atual.mediaEquipe,
      mediaAnterior: 0,
      melhoraram: 0,
      mantiveram: 0,
      pioraram: 0,
      comparaveis: 0,
      criterios: atual.criterios.map((criterio) => ({
        criterioId: criterio.criterioId,
        criterioNome: criterio.criterioNome,
        atual: criterio.media,
        anterior: 0,
      })),
    };
  }

  const anterior = getRelatorioVisaoGeral(cicloAnterior, usuario, filtros);
  const anterioresPorMatricula = new Map(
    anterior.colaboradores
      .filter((item) => item.possuiNotaConsolidada)
      .map((item) => [item.matricula, item])
  );

  let melhoraram = 0;
  let mantiveram = 0;
  let pioraram = 0;

  atual.colaboradores
    .filter((item) => item.possuiNotaConsolidada)
    .forEach((item) => {
      const itemAnterior = anterioresPorMatricula.get(item.matricula);
      if (!itemAnterior) return;

      const variacao = item.notaMedia - itemAnterior.notaMedia;
      if (variacao > 0.05) melhoraram += 1;
      else if (variacao < -0.05) pioraram += 1;
      else mantiveram += 1;
    });

  const criteriosAnteriores = new Map(
    anterior.criterios.map((criterio) => [criterio.criterioId, criterio])
  );

  return {
    possuiComparacao: true,
    mediaAtual: atual.mediaEquipe,
    mediaAnterior: anterior.mediaEquipe,
    variacaoMedia:
      atual.mediaEquipe > 0 && anterior.mediaEquipe > 0
        ? atual.mediaEquipe - anterior.mediaEquipe
        : undefined,
    melhoraram,
    mantiveram,
    pioraram,
    comparaveis: melhoraram + mantiveram + pioraram,
    criterios: atual.criterios.map((criterio) => {
      const criterioAnterior = criteriosAnteriores.get(criterio.criterioId);
      const valorAnterior = criterioAnterior?.media ?? 0;

      return {
        criterioId: criterio.criterioId,
        criterioNome: criterio.criterioNome,
        atual: criterio.media,
        anterior: valorAnterior,
        variacao:
          criterio.media > 0 && valorAnterior > 0
            ? criterio.media - valorAnterior
            : undefined,
      };
    }),
  };
}


export type TendenciaEvolucaoIndividual =
  | "MELHOROU"
  | "MANTEVE"
  | "PIOROU";

export interface RelatorioEvolucaoIndividual {
  matricula: number;
  notaAtual: number;
  notaAnterior: number;
  variacao: number;
  tendencia: TendenciaEvolucaoIndividual;
}

export function getRelatorioEvolucaoIndividual(
  cicloAtual: CicloAvaliacao,
  cicloAnterior: CicloAvaliacao | undefined,
  usuario: Colaborador,
  filtros?: FiltrosRelatorio
): RelatorioEvolucaoIndividual[] {
  if (!cicloAnterior) return [];

  const atual = getRelatorioVisaoGeral(cicloAtual, usuario, filtros);
  const anterior = getRelatorioVisaoGeral(cicloAnterior, usuario, filtros);

  const anterioresPorMatricula = new Map(
    anterior.colaboradores
      .filter((item) => item.possuiNotaConsolidada)
      .map((item) => [item.matricula, item])
  );

  return atual.colaboradores
    .filter((item) => item.possuiNotaConsolidada)
    .flatMap((item) => {
      const itemAnterior = anterioresPorMatricula.get(item.matricula);
      if (!itemAnterior) return [];

      const variacao = item.notaMedia - itemAnterior.notaMedia;
      const tendencia: TendenciaEvolucaoIndividual =
        variacao > 0.05
          ? "MELHOROU"
          : variacao < -0.05
          ? "PIOROU"
          : "MANTEVE";

      return [
        {
          matricula: item.matricula,
          notaAtual: item.notaMedia,
          notaAnterior: itemAnterior.notaMedia,
          variacao,
          tendencia,
        },
      ];
    });
}


export interface RelatorioDetalheCriterioColaborador {
  matricula: number;
  nome: string;
  funcao: Colaborador["funcao"];
  senioridade: Colaborador["senioridade"];
  notaAtual: number;
  notaAnterior?: number;
  variacao?: number;
}

export interface RelatorioDetalheCriterio {
  criterioId: string;
  criterioNome: string;
  mediaAtual: number;
  mediaAnterior?: number;
  variacaoMedia?: number;
  quantidadeAvaliacoes: number;
  colaboradores: RelatorioDetalheCriterioColaborador[];
}

export function getRelatorioDetalheCriterio(
  criterioId: string,
  cicloAtual: CicloAvaliacao,
  cicloAnterior: CicloAvaliacao | undefined,
  usuario: Colaborador,
  filtros?: FiltrosRelatorio
): RelatorioDetalheCriterio | undefined {
  const criterioModelo = criteriosAvaliacao.find(
    (criterio) => criterio.id === criterioId
  );

  if (!criterioModelo) return undefined;

  const escala = getEscalaAvaliacao();

  const linhasAtuais = aplicarFiltrosRelatorio(
    linhasDoEscopo(cicloAtual, usuario),
    filtros,
    escala
  ).filter((linha) =>
    possuiNotaConsolidada(linha.situacao, linha.feedback?.notaMedia ?? 0)
  );

  const linhasAnteriores = cicloAnterior
    ? aplicarFiltrosRelatorio(
        linhasDoEscopo(cicloAnterior, usuario),
        filtros,
        escala
      ).filter((linha) =>
        possuiNotaConsolidada(linha.situacao, linha.feedback?.notaMedia ?? 0)
      )
    : [];

  const notaCriterio = (
    linha: (typeof linhasAtuais)[number]
  ): number =>
    linha.feedback?.criteriosDetalhados?.find(
      (criterio) => criterio.criterioId === criterioId
    )?.nota ?? 0;

  const notasAnterioresPorMatricula = new Map(
    linhasAnteriores
      .map((linha) => [linha.colaborador.matricula, notaCriterio(linha)] as const)
      .filter(([, nota]) => nota > 0)
  );

  const colaboradores: RelatorioDetalheCriterioColaborador[] =
    linhasAtuais
      .flatMap((linha): RelatorioDetalheCriterioColaborador[] => {
        const notaAtual = notaCriterio(linha);
        if (notaAtual <= 0) return [];

        const notaAnterior = notasAnterioresPorMatricula.get(
          linha.colaborador.matricula
        );

        const item: RelatorioDetalheCriterioColaborador = {
          matricula: linha.colaborador.matricula,
          nome: linha.colaborador.nome,
          funcao: linha.colaborador.funcao,
          senioridade: linha.colaborador.senioridade,
          notaAtual,
        };

        if (notaAnterior !== undefined) {
          item.notaAnterior = notaAnterior;
          item.variacao = notaAtual - notaAnterior;
        }

        return [item];
      })
      .sort((a, b) => {
        const ordem = (item: RelatorioDetalheCriterioColaborador) => {
          if (item.funcao === "COORDENADOR") return 1;
          if (item.funcao === "CONSULTOR") return 2;
          if (item.funcao === "ANALISTA" && item.senioridade === "SENIOR") return 3;
          if (item.funcao === "ANALISTA" && item.senioridade === "PLENO") return 4;
          if (item.funcao === "ANALISTA" && item.senioridade === "JUNIOR") return 5;
          if (item.funcao === "ESTAGIARIO") return 6;
          return 7;
        };

        const diferenca = ordem(a) - ordem(b);
        return diferenca !== 0
          ? diferenca
          : a.nome.localeCompare(b.nome, "pt-BR");
      });

  const notasAtuais = colaboradores.map((item) => item.notaAtual);
  const notasAnteriores = colaboradores
    .map((item) => item.notaAnterior)
    .filter((nota): nota is number => nota !== undefined && nota > 0);

  const mediaAtual = media(notasAtuais);
  const mediaAnterior = notasAnteriores.length
    ? media(notasAnteriores)
    : undefined;

  return {
    criterioId,
    criterioNome: criterioModelo.nome,
    mediaAtual,
    mediaAnterior,
    variacaoMedia:
      mediaAnterior !== undefined ? mediaAtual - mediaAnterior : undefined,
    quantidadeAvaliacoes: colaboradores.length,
    colaboradores,
  };
}
