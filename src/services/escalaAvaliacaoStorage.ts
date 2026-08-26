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
  },
  {
    nota: 4,
    significado: "Acima do esperado",
    descricao:
      "Supera expectativas em vários aspectos. Demonstra iniciativa e consistência. Há espaço para melhorias.",
    cor: "#660099",
    corFundo: "#F4EAF8",
  },
  {
    nota: 3,
    significado: "Dentro do esperado",
    descricao:
      "Cumpre as responsabilidades de forma adequada. Há espaço para melhorias.",
    cor: "#8A6D00",
    corFundo: "#FFF4CE",
  },
  {
    nota: 2,
    significado: "Abaixo do esperado",
    descricao:
      "Performance abaixo do nível esperado pelo cargo. Apresenta dificuldades frequentes e precisa de orientação constante.",
    cor: "#C94A12",
    corFundo: "#FFF0E8",
  },
  {
    nota: 1,
    significado: "Insatisfatório",
    descricao:
      "Desempenho insatisfatório, não atende aos requisitos mínimos. Necessita mudança de atitude imediata em curto prazo.",
    cor: "#A4262C",
    corFundo: "#FDE7E9",
  },
];

function clonarPadrao(): EscalaAvaliacao {
  return escalaAvaliacaoPadrao.map((item) => ({ ...item }));
}

export function getEscalaAvaliacao(): EscalaAvaliacao {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) return clonarPadrao();

  try {
    const parsed = JSON.parse(data) as EscalaAvaliacao;

    if (!Array.isArray(parsed) || parsed.length !== 5) {
      return clonarPadrao();
    }

    return [5, 4, 3, 2, 1].map((nota) => {
      const salvo = parsed.find((item) => item.nota === nota);
      const padrao = escalaAvaliacaoPadrao.find(
        (item) => item.nota === nota
      )!;

      return {
        ...padrao,
        ...salvo,
        nota: nota as NotaEscala,
      };
    });
  } catch {
    return clonarPadrao();
  }
}

export function salvarEscalaAvaliacao(
  escala: EscalaAvaliacao
): void {
  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify(
      [...escala].sort((a, b) => b.nota - a.nota)
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
  const notaArredondada = Math.min(
    5,
    Math.max(1, Math.round(valor))
  ) as NotaEscala;

  return (
    escala.find((item) => item.nota === notaArredondada) ??
    escalaAvaliacaoPadrao.find(
      (item) => item.nota === notaArredondada
    )!
  );
}
