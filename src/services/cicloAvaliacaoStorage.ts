import type {
  CicloAvaliacao,
  StatusCicloAvaliacao,
} from "../types/CicloAvaliacao";
import { getFeedbacks } from "./feedbackStorage";

const STORAGE_KEY = "feedback-control-ciclos";

function ordenar(ciclos: CicloAvaliacao[]) {
  return [...ciclos].sort(
    (a, b) => b.ano - a.ano || b.ciclo - a.ciclo
  );
}

function persistir(ciclos: CicloAvaliacao[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(ciclos));
}

function inicializarCiclos(): CicloAvaliacao[] {
  const agora = new Date().toISOString();
  const feedbacks = getFeedbacks();

  const pares = new Map<string, { ano: number; ciclo: 1 | 2 | 3 }>();

  feedbacks.forEach((feedback) => {
    pares.set(`${feedback.ano}-${feedback.ciclo}`, {
      ano: feedback.ano,
      ciclo: feedback.ciclo,
    });
  });

  const existentes = Array.from(pares.values()).sort(
    (a, b) => b.ano - a.ano || b.ciclo - a.ciclo
  );

  if (existentes.length === 0) {
    const inicial: CicloAvaliacao = {
      id: crypto.randomUUID(),
      ano: new Date().getFullYear(),
      ciclo: 1,
      status: "ATIVO",
      dataCriacao: agora,
      dataUltimaAtualizacao: agora,
      dataAtivacao: agora,
    };

    persistir([inicial]);
    return [inicial];
  }

  const ciclos: CicloAvaliacao[] = existentes.map(
    (item, indice) => ({
      id: crypto.randomUUID(),
      ano: item.ano,
      ciclo: item.ciclo,
      status: indice === 0 ? "ATIVO" : "ENCERRADO",
      dataCriacao: agora,
      dataUltimaAtualizacao: agora,
      dataAtivacao: indice === 0 ? agora : undefined,
      dataEncerramento: indice === 0 ? undefined : agora,
    })
  );

  persistir(ciclos);
  return ciclos;
}

export function getCiclosAvaliacao(): CicloAvaliacao[] {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) {
    return ordenar(inicializarCiclos());
  }

  try {
    return ordenar(JSON.parse(data) as CicloAvaliacao[]);
  } catch {
    return ordenar(inicializarCiclos());
  }
}

export function getCicloAtivo(): CicloAvaliacao | undefined {
  return getCiclosAvaliacao().find(
    (ciclo) => ciclo.status === "ATIVO"
  );
}

export function criarCiclo(
  ano: number,
  ciclo: 1 | 2 | 3,
  dataInicio: string,
  dataFim: string,
  ativarAgora = false
): CicloAvaliacao {
  const ciclos = getCiclosAvaliacao();

  if (
    ciclos.some(
      (item) => item.ano === ano && item.ciclo === ciclo
    )
  ) {
    throw new Error(
      `O ciclo ${ano} - Ciclo ${ciclo} já está cadastrado.`
    );
  }

  if (!dataInicio || !dataFim) {
    throw new Error("Informe as datas de início e fim do ciclo.");
  }

  if (new Date(dataInicio).getTime() > new Date(dataFim).getTime()) {
    throw new Error("A data de início não pode ser posterior à data de fim.");
  }

  const agora = new Date().toISOString();

  const novo: CicloAvaliacao = {
    id: crypto.randomUUID(),
    ano,
    ciclo,
    dataInicio,
    dataFim,
    status: ativarAgora ? "ATIVO" : "PLANEJADO",
    dataCriacao: agora,
    dataUltimaAtualizacao: agora,
    dataAtivacao: ativarAgora ? agora : undefined,
  };

  const atualizados = ativarAgora
    ? ciclos.map((item) =>
        item.status === "ATIVO"
          ? {
              ...item,
              status: "ENCERRADO" as StatusCicloAvaliacao,
              dataUltimaAtualizacao: agora,
              dataEncerramento: agora,
            }
          : item
      )
    : ciclos;

  persistir([...atualizados, novo]);
  return novo;
}

export function ativarCiclo(id: string): void {
  const ciclos = getCiclosAvaliacao();
  const alvo = ciclos.find((item) => item.id === id);

  if (!alvo) {
    throw new Error("Ciclo não encontrado.");
  }

  const agora = new Date().toISOString();

  persistir(
    ciclos.map((item) => {
      if (item.id === id) {
        return {
          ...item,
          status: "ATIVO",
          dataAtivacao: item.dataAtivacao ?? agora,
          dataEncerramento: undefined,
          dataUltimaAtualizacao: agora,
        };
      }

      if (item.status === "ATIVO") {
        return {
          ...item,
          status: "ENCERRADO",
          dataEncerramento: agora,
          dataUltimaAtualizacao: agora,
        };
      }

      return item;
    })
  );
}

export function encerrarCiclo(id: string): void {
  const ciclos = getCiclosAvaliacao();
  const alvo = ciclos.find((item) => item.id === id);

  if (!alvo) {
    throw new Error("Ciclo não encontrado.");
  }

  const agora = new Date().toISOString();

  persistir(
    ciclos.map((item) =>
      item.id === id
        ? {
            ...item,
            status: "ENCERRADO",
            dataEncerramento: agora,
            dataUltimaAtualizacao: agora,
          }
        : item
    )
  );
}


export function atualizarPeriodoCiclo(
  id: string,
  dataInicio: string,
  dataFim: string
): void {
  const ciclos = getCiclosAvaliacao();
  const alvo = ciclos.find((item) => item.id === id);

  if (!alvo) {
    throw new Error("Ciclo não encontrado.");
  }

  if (!dataInicio || !dataFim) {
    throw new Error("Informe as datas de início e fim do ciclo.");
  }

  if (new Date(dataInicio).getTime() > new Date(dataFim).getTime()) {
    throw new Error("A data de início não pode ser posterior à data de fim.");
  }

  const agora = new Date().toISOString();

  persistir(
    ciclos.map((item) =>
      item.id === id
        ? {
            ...item,
            dataInicio,
            dataFim,
            dataUltimaAtualizacao: agora,
          }
        : item
    )
  );
}

export function formatarPeriodoCiclo(
  dataInicio?: string,
  dataFim?: string
): string {
  if (!dataInicio || !dataFim) {
    return "Período não informado";
  }

  const formatar = (valor: string) =>
    new Date(`${valor}T12:00:00`).toLocaleDateString("pt-BR");

  return `${formatar(dataInicio)} a ${formatar(dataFim)}`;
}
