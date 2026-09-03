import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "./escalaAvaliacaoStorage";
import type { EscalaAvaliacao } from "../types/EscalaAvaliacao";

export function possuiNotaAvaliacao(valor?: number | null): valor is number {
  return (
    typeof valor === "number" &&
    Number.isFinite(valor) &&
    valor >= 1 &&
    valor <= 5
  );
}

export function formatarNotaAvaliacao(valor?: number | null): string {
  return possuiNotaAvaliacao(valor) ? formatarNota(valor) : "—";
}

export function getTextoNotaAvaliacao(
  valor?: number | null,
  escala: EscalaAvaliacao = getEscalaAvaliacao()
): string {
  return possuiNotaAvaliacao(valor)
    ? getItemEscalaPorNota(valor, escala).significado
    : "Sem avaliação";
}
