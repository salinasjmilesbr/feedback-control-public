import type {
  EscalaAvaliacao,
  ItemEscalaAvaliacao,
  NotaEscala,
} from "../types/EscalaAvaliacao";

const STORAGE_KEY = "feedback-control-escala-avaliacao";

export const escalaAvaliacaoPadrao: EscalaAvaliacao = [
  {
    nota: 5,
    significado: "Excelente",
    descricao:
      "Desempenho excepcional. Serve como referência para os demais. Alta autonomia e impacto no dia a dia.",
    cor: "#107C41",
    corFundo: "#E7F6EC",
    limiteMinimo: 4.7,
  },
  {
    nota: 4,
    significado: "Acima do esperado",
    descricao:
      "Supera expectativas em vários aspectos. Demonstra iniciativa e consistência. Há espaço para melhorias.",
    cor: "#660099",
    corFundo: "#F4EAF8",
    limiteMinimo: 3.9,
  },
  {
    nota: 3,
    significado: "Dentro do esperado",
    descricao:
      "Cumpre as responsabilidades de forma adequada. Há espaço para melhorias.",
    cor: "#8A6D00",
    corFundo: "#FFF4CE",
    limiteMinimo: 2.9,
  },
  {
    nota: 2,
    significado: "Abaixo do esperado",
    descricao:
      "Performance abaixo do nível esperado pelo cargo. Apresenta dificuldades frequentes e precisa de orientação constante.",
    cor: "#C94A12",
    corFundo: "#FFF0E8",
    limiteMinimo: 2.0,
  },
  {
    nota: 1,
    significado: "Insatisfatório",
    descricao:
      "Desempenho insatisfatório, não atende aos requisitos mínimos. Necessita mudança de atitude imediata em curto prazo.",
    cor: "#A4262C",
    corFundo: "#FDE7E9",
    limiteMinimo: 1.0,
  },
];

function clonarPadrao(): EscalaAvaliacao {
  return escalaAvaliacaoPadrao.map((item) => ({ ...item }));
}

function normalizarEscala(escala: EscalaAvaliacao): EscalaAvaliacao {
  return [5, 4, 3, 2, 1].map((nota) => {
    const salvo = escala.find((item) => item.nota === nota);
    const padrao = escalaAvaliacaoPadrao.find(
      (item) => item.nota === nota
    )!;

    return {
      ...padrao,
      ...salvo,
      nota: nota as NotaEscala,
      limiteMinimo:
        typeof salvo?.limiteMinimo === "number"
          ? salvo.limiteMinimo
          : padrao.limiteMinimo,
    };
  });
}

export function getEscalaAvaliacao(): EscalaAvaliacao {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) return clonarPadrao();

  try {
    const parsed = JSON.parse(data) as EscalaAvaliacao;

    if (!Array.isArray(parsed) || parsed.length !== 5) {
      return clonarPadrao();
    }

    return normalizarEscala(parsed);
  } catch {
    return clonarPadrao();
  }
}

function validarEscala(escala: EscalaAvaliacao): void {
  const ordenada = normalizarEscala(escala).sort(
    (a, b) => a.nota - b.nota
  );

  if (ordenada[0].limiteMinimo !== 1) {
    throw new Error("A faixa da nota 1 deve começar em 1,0.");
  }

  for (const item of ordenada) {
    if (
      !Number.isFinite(item.limiteMinimo) ||
      item.limiteMinimo < 1 ||
      item.limiteMinimo > 5
    ) {
      throw new Error("Os limites da régua devem ficar entre 1,0 e 5,0.");
    }
  }

  for (let i = 1; i < ordenada.length; i += 1) {
    if (ordenada[i].limiteMinimo <= ordenada[i - 1].limiteMinimo) {
      throw new Error(
        "Os limites das faixas devem ser crescentes, sem sobreposição."
      );
    }
  }
}

export function salvarEscalaAvaliacao(
  escala: EscalaAvaliacao
): void {
  const normalizada = normalizarEscala(escala);
  validarEscala(normalizada);

  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify(
      [...normalizada].sort((a, b) => b.nota - a.nota)
    )
  );
}

export function restaurarEscalaAvaliacao(): EscalaAvaliacao {
  const padrao = clonarPadrao();
  localStorage.setItem(STORAGE_KEY, JSON.stringify(padrao));
  return padrao;
}

export function getItemEscalaPorNota(
  valor: number,
  escala = getEscalaAvaliacao()
): ItemEscalaAvaliacao {
  const valorNormalizado = Math.min(5, Math.max(1, valor));
  const ordenada = normalizarEscala(escala).sort(
    (a, b) => b.limiteMinimo - a.limiteMinimo
  );

  return (
    ordenada.find(
      (item) => valorNormalizado >= item.limiteMinimo
    ) ?? ordenada[ordenada.length - 1]
  );
}

/**
 * Padrão visual do Virtus: notas sempre com uma casa decimal.
 * Mantemos ponto como separador para consistência com os campos atuais.
 */
export function formatarNota(valor: number): string {
  if (!Number.isFinite(valor)) return "—";
  return valor.toFixed(1);
}

export function getFaixaTexto(
  item: ItemEscalaAvaliacao,
  escala = getEscalaAvaliacao()
): string {
  const ordenada = normalizarEscala(escala).sort(
    (a, b) => a.nota - b.nota
  );
  const indice = ordenada.findIndex(
    (atual) => atual.nota === item.nota
  );
  const proxima = ordenada[indice + 1];

  const inicio = item.limiteMinimo.toFixed(2);
  const fim = proxima
    ? (proxima.limiteMinimo - 0.01).toFixed(2)
    : "5.00";

  return `${inicio} a ${fim}`;
}
