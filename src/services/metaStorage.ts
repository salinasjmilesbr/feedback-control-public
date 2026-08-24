import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Meta, TipoMeta } from "../types/Meta";

const STORAGE_KEY = "feedback-control-metas";

function getTodasMetas(): Meta[] {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) return [];

  try {
    return JSON.parse(data) as Meta[];
  } catch {
    return [];
  }
}

function persistir(metas: Meta[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(metas));
}

export function getMetasDoColaboradorNoCiclo(
  colaboradorMatricula: number,
  cicloId: string,
  incluirExcluidas = false
): Meta[] {
  return getTodasMetas()
    .filter(
      (meta) =>
        meta.colaboradorMatricula === colaboradorMatricula &&
        meta.cicloId === cicloId &&
        (incluirExcluidas || !meta.excluida)
    )
    .sort(
      (a, b) =>
        new Date(a.dataCriacao).getTime() -
        new Date(b.dataCriacao).getTime()
    );
}

export function getMetasDoCiclo(
  cicloId: string,
  incluirExcluidas = false
): Meta[] {
  return getTodasMetas()
    .filter(
      (meta) =>
        meta.cicloId === cicloId &&
        (incluirExcluidas || !meta.excluida)
    )
    .sort((a, b) =>
      a.colaboradorNome.localeCompare(b.colaboradorNome, "pt-BR")
    );
}

export function contarMetasPorTipo(
  colaboradorMatricula: number,
  cicloId: string,
  tipo: TipoMeta
): number {
  return getMetasDoColaboradorNoCiclo(
    colaboradorMatricula,
    cicloId
  ).filter((meta) => meta.tipo === tipo).length;
}

function limiteDoTipo(
  ciclo: CicloAvaliacao,
  tipo: TipoMeta
): number {
  return tipo === "NEGOCIO_PROJETO"
    ? ciclo.quantidadeMetasNegocio ?? 0
    : ciclo.quantidadeMetasIndividuais ?? 0;
}

function validarCicloAtivo(ciclo: CicloAvaliacao) {
  if (ciclo.status !== "ATIVO") {
    throw new Error(
      "As metas só podem ser cadastradas ou alteradas enquanto o ciclo estiver Ativo."
    );
  }
}

export function criarMeta(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  tipo: TipoMeta,
  descricao: string,
  kpi: string,
  valorAlvo: string
): Meta {
  validarCicloAtivo(ciclo);

  const limite = limiteDoTipo(ciclo, tipo);
  const quantidadeAtual = contarMetasPorTipo(
    colaborador.matricula,
    ciclo.id,
    tipo
  );

  if (quantidadeAtual >= limite) {
    throw new Error(
      tipo === "NEGOCIO_PROJETO"
        ? "O limite de metas de Negócio/Projetos deste ciclo já foi atingido."
        : "O limite de metas Individuais deste ciclo já foi atingido."
    );
  }

  if (!descricao.trim() || !kpi.trim() || !valorAlvo.trim()) {
    throw new Error(
      "Preencha a descrição, o KPI e o valor-alvo da meta."
    );
  }

  const agora = new Date().toISOString();

  const meta: Meta = {
    id: crypto.randomUUID(),
    colaboradorMatricula: colaborador.matricula,
    colaboradorNome: colaborador.nome,
    cicloId: ciclo.id,
    ano: ciclo.ano,
    ciclo: ciclo.ciclo,
    tipo,
    descricao: descricao.trim(),
    kpi: kpi.trim(),
    valorAlvo: valorAlvo.trim(),
    status: "EM_ANDAMENTO",
    dataCriacao: agora,
    dataUltimaAtualizacao: agora,
    excluida: false,
    historico: [
      {
        id: crypto.randomUUID(),
        acao: "CRIACAO",
        data: agora,
        autorMatricula: colaborador.matricula,
        autorNome: colaborador.nome,
      },
    ],
  };

  persistir([...getTodasMetas(), meta]);

  return meta;
}

export function atualizarMeta(
  id: string,
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  descricao: string,
  kpi: string,
  valorAlvo: string
): void {
  validarCicloAtivo(ciclo);

  if (!descricao.trim() || !kpi.trim() || !valorAlvo.trim()) {
    throw new Error(
      "Preencha a descrição, o KPI e o valor-alvo da meta."
    );
  }

  const metas = getTodasMetas();
  const atual = metas.find((meta) => meta.id === id);

  if (
    !atual ||
    atual.excluida ||
    atual.colaboradorMatricula !== colaborador.matricula ||
    atual.cicloId !== ciclo.id
  ) {
    throw new Error("Meta não encontrada.");
  }

  const agora = new Date().toISOString();

  persistir(
    metas.map((meta) =>
      meta.id === id
        ? {
            ...meta,
            descricao: descricao.trim(),
            kpi: kpi.trim(),
            valorAlvo: valorAlvo.trim(),
            dataUltimaAtualizacao: agora,
            historico: [
              ...meta.historico,
              {
                id: crypto.randomUUID(),
                acao: "EDICAO",
                data: agora,
                autorMatricula: colaborador.matricula,
                autorNome: colaborador.nome,
                descricaoAnterior: meta.descricao,
                kpiAnterior: meta.kpi,
                valorAlvoAnterior: meta.valorAlvo,
              },
            ],
          }
        : meta
    )
  );
}

export function excluirMeta(
  id: string,
  colaborador: Colaborador,
  ciclo: CicloAvaliacao
): void {
  validarCicloAtivo(ciclo);

  const metas = getTodasMetas();
  const atual = metas.find((meta) => meta.id === id);

  if (
    !atual ||
    atual.excluida ||
    atual.colaboradorMatricula !== colaborador.matricula ||
    atual.cicloId !== ciclo.id
  ) {
    throw new Error("Meta não encontrada.");
  }

  const agora = new Date().toISOString();

  persistir(
    metas.map((meta) =>
      meta.id === id
        ? {
            ...meta,
            excluida: true,
            dataExclusao: agora,
            dataUltimaAtualizacao: agora,
            historico: [
              ...meta.historico,
              {
                id: crypto.randomUUID(),
                acao: "EXCLUSAO",
                data: agora,
                autorMatricula: colaborador.matricula,
                autorNome: colaborador.nome,
                descricaoAnterior: meta.descricao,
                kpiAnterior: meta.kpi,
                valorAlvoAnterior: meta.valorAlvo,
              },
            ],
          }
        : meta
    )
  );
}


export function atualizarAcompanhamentoMeta(
  id: string,
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  resultadoAtual: string,
  progressoPercentual: number
): void {
  validarCicloAtivo(ciclo);

  if (!resultadoAtual.trim()) {
    throw new Error("Informe o resultado atual da meta.");
  }

  if (
    !Number.isFinite(progressoPercentual) ||
    progressoPercentual < 0 ||
    progressoPercentual > 100
  ) {
    throw new Error("O progresso deve estar entre 0% e 100%.");
  }

  const metas = getTodasMetas();
  const atual = metas.find((meta) => meta.id === id);

  if (
    !atual ||
    atual.excluida ||
    atual.colaboradorMatricula !== colaborador.matricula ||
    atual.cicloId !== ciclo.id
  ) {
    throw new Error("Meta não encontrada.");
  }

  const agora = new Date().toISOString();

  persistir(
    metas.map((meta) =>
      meta.id === id
        ? {
            ...meta,
            resultadoAtual: resultadoAtual.trim(),
            progressoPercentual,
            dataUltimoAcompanhamento: agora,
            dataUltimaAtualizacao: agora,
            historico: [
              ...meta.historico,
              {
                id: crypto.randomUUID(),
                acao: "ATUALIZACAO_PROGRESSO",
                data: agora,
                autorMatricula: colaborador.matricula,
                autorNome: colaborador.nome,
                resultadoAtualAnterior: meta.resultadoAtual,
                progressoPercentualAnterior:
                  meta.progressoPercentual,
              },
            ],
          }
        : meta
    )
  );
}


export function finalizarMeta(
  id: string,
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  resultadoFinal: string,
  atingida: boolean
): void {
  validarCicloAtivo(ciclo);

  if (!resultadoFinal.trim()) {
    throw new Error("Informe o resultado final da meta.");
  }

  const metas = getTodasMetas();
  const atual = metas.find((meta) => meta.id === id);

  if (
    !atual ||
    atual.excluida ||
    atual.colaboradorMatricula !== colaborador.matricula ||
    atual.cicloId !== ciclo.id
  ) {
    throw new Error("Meta não encontrada.");
  }

  const agora = new Date().toISOString();

  persistir(
    metas.map((meta) =>
      meta.id === id
        ? {
            ...meta,
            resultadoFinal: resultadoFinal.trim(),
            atingida,
            status: atingida ? "ATINGIDA" : "NAO_ATINGIDA",
            dataFechamento: agora,
            dataUltimaAtualizacao: agora,
            historico: [
              ...meta.historico,
              {
                id: crypto.randomUUID(),
                acao: "FINALIZACAO",
                data: agora,
                autorMatricula: colaborador.matricula,
                autorNome: colaborador.nome,
                resultadoFinalAnterior: meta.resultadoFinal,
                atingidaAnterior: meta.atingida,
              },
            ],
          }
        : meta
    )
  );
}
