import type {
  Observacao,
  TipoObservacao,
} from "../types/Observacao";
import type { Colaborador } from "../types/Colaborador";
import {
  ordenarPorAnoECiclo,
  type OrdemPorCiclo,
} from "../utils/ordenacaoPorCiclo";
import { getCiclosAvaliacao } from "./cicloAvaliacaoStorage";

const STORAGE_KEY = "feedback-control-observacoes";

function getTodasObservacoes(): Observacao[] {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) return [];

  try {
    return JSON.parse(data) as Observacao[];
  } catch {
    return [];
  }
}

function persistir(observacoes: Observacao[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(observacoes));
}

function validarCicloAtivo(ano?: number, ciclo?: 1 | 2 | 3): void {
  const cicloPersistido = getCiclosAvaliacao().find(
    (item) => item.ano === ano && item.ciclo === ciclo
  );
  if (cicloPersistido?.status !== "ATIVO") {
    throw new Error(
      "Observações só podem ser alteradas enquanto o ciclo estiver ativo."
    );
  }
}

export function getObservacoesByColaborador(
  colaboradorMatricula: number,
  incluirExcluidas = false,
  ordem: OrdemPorCiclo = "RECENTES"
): Observacao[] {
  const observacoes = getTodasObservacoes().filter(
    (observacao) =>
      observacao.colaboradorMatricula === colaboradorMatricula &&
      (incluirExcluidas || !observacao.excluida)
  );

  return ordenarPorAnoECiclo(
    observacoes,
    ordem,
    (observacao) => observacao.dataCriacao
  );
}

export function getObservacoesComunicadasByColaborador(
  colaboradorMatricula: number
): Observacao[] {
  return getObservacoesByColaborador(colaboradorMatricula).filter(
    (observacao) => observacao.comunicado
  );
}

export function getObservacoesComunicadasByCiclo(
  colaboradorMatricula: number,
  ano: number,
  ciclo: 1 | 2 | 3
): Observacao[] {
  return getObservacoesComunicadasByColaborador(
    colaboradorMatricula
  ).filter(
    (observacao) =>
      observacao.ano === ano &&
      observacao.ciclo === ciclo
  );
}

export function getObservacoesByCiclo(
  ano: number,
  ciclo: 1 | 2 | 3,
  incluirExcluidas = false
): Observacao[] {
  return ordenarPorAnoECiclo(
    getTodasObservacoes().filter(
      (observacao) =>
        observacao.ano === ano &&
        observacao.ciclo === ciclo &&
        (incluirExcluidas || !observacao.excluida)
    ),
    "RECENTES",
    (observacao) => observacao.dataCriacao
  );
}

export function criarObservacao(
  colaboradorMatricula: number,
  tipo: TipoObservacao,
  texto: string,
  comunicado: boolean,
  ano: number,
  ciclo: 1 | 2 | 3,
  autor: Colaborador
): Observacao {
  validarCicloAtivo(ano, ciclo);
  const agora = new Date().toISOString();

  const observacao: Observacao = {
    id: crypto.randomUUID(),
    colaboradorMatricula,
    tipo,
    texto: texto.trim(),
    comunicado,
    ano,
    ciclo,
    autorMatricula: autor.matricula,
    autorNome: autor.nome,
    dataCriacao: agora,
    dataUltimaAtualizacao: agora,
    excluida: false,
    historico: [
      {
        id: crypto.randomUUID(),
        acao: "CRIACAO",
        data: agora,
        autorMatricula: autor.matricula,
        autorNome: autor.nome,
      },
    ],
  };

  persistir([...getTodasObservacoes(), observacao]);

  return observacao;
}

export function atualizarObservacao(
  id: string,
  tipo: TipoObservacao,
  texto: string,
  comunicado: boolean,
  ano: number,
  ciclo: 1 | 2 | 3,
  autor: Colaborador
): void {
  const observacoes = getTodasObservacoes();
  const atual = observacoes.find((item) => item.id === id);

  if (!atual || atual.excluida) {
    throw new Error("Observação não encontrada.");
  }
  if (atual.ano !== ano || atual.ciclo !== ciclo) {
    throw new Error("O ciclo de uma observação existente não pode ser alterado.");
  }
  validarCicloAtivo(atual.ano, atual.ciclo);

  const agora = new Date().toISOString();

  persistir(
    observacoes.map((item) =>
      item.id === id
        ? {
            ...item,
            tipo,
            texto: texto.trim(),
            comunicado,
            ano,
            ciclo,
            dataUltimaAtualizacao: agora,
            historico: [
              ...item.historico,
              {
                id: crypto.randomUUID(),
                acao: "EDICAO",
                data: agora,
                autorMatricula: autor.matricula,
                autorNome: autor.nome,
                textoAnterior: item.texto,
                tipoAnterior: item.tipo,
                comunicadoAnterior: item.comunicado,
                anoAnterior: item.ano,
                cicloAnterior: item.ciclo,
              },
            ],
          }
        : item
    )
  );
}

export function excluirObservacao(
  id: string,
  autor: Colaborador
): void {
  const observacoes = getTodasObservacoes();
  const atual = observacoes.find((item) => item.id === id);

  if (!atual || atual.excluida) {
    throw new Error("Observação não encontrada.");
  }
  validarCicloAtivo(atual.ano, atual.ciclo);

  const agora = new Date().toISOString();

  persistir(
    observacoes.map((item) =>
      item.id === id
        ? {
            ...item,
            excluida: true,
            dataExclusao: agora,
            excluidaPorMatricula: autor.matricula,
            excluidaPorNome: autor.nome,
            dataUltimaAtualizacao: agora,
            historico: [
              ...item.historico,
              {
                id: crypto.randomUUID(),
                acao: "EXCLUSAO",
                data: agora,
                autorMatricula: autor.matricula,
                autorNome: autor.nome,
                textoAnterior: item.texto,
                tipoAnterior: item.tipo,
                comunicadoAnterior: item.comunicado,
              },
            ],
          }
        : item
    )
  );
}
