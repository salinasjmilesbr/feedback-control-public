import type {
  Observacao,
  TipoObservacao,
} from "../types/Observacao";
import type { Colaborador } from "../types/Colaborador";

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

export function getObservacoesByColaborador(
  colaboradorMatricula: number,
  incluirExcluidas = false
): Observacao[] {
  return getTodasObservacoes()
    .filter(
      (observacao) =>
        observacao.colaboradorMatricula === colaboradorMatricula &&
        (incluirExcluidas || !observacao.excluida)
    )
    .sort(
      (a, b) =>
        new Date(b.dataUltimaAtualizacao).getTime() -
        new Date(a.dataUltimaAtualizacao).getTime()
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

export function criarObservacao(
  colaboradorMatricula: number,
  tipo: TipoObservacao,
  texto: string,
  comunicado: boolean,
  ano: number,
  ciclo: 1 | 2 | 3,
  autor: Colaborador
): Observacao {
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
