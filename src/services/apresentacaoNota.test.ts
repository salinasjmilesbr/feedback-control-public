import { describe, expect, it } from "vitest";
import { escalaAvaliacaoPadrao } from "./escalaAvaliacaoStorage";
import {
  formatarNotaAvaliacao,
  getTextoNotaAvaliacao,
  possuiNotaAvaliacao,
} from "./apresentacaoNota";

describe("apresentação de notas de avaliação", () => {
  it.each([0, undefined, null, Number.NaN])(
    "trata %s como ausência de avaliação",
    (valor) => {
      expect(possuiNotaAvaliacao(valor)).toBe(false);
      expect(formatarNotaAvaliacao(valor)).toBe("—");
      expect(getTextoNotaAvaliacao(valor, escalaAvaliacaoPadrao)).toBe(
        "Sem avaliação"
      );
    }
  );

  it.each([1, 2, 3, 4, 5])("preserva a régua semântica para nota %i", (nota) => {
    expect(possuiNotaAvaliacao(nota)).toBe(true);
    expect(formatarNotaAvaliacao(nota)).toBe(`${nota}.0`);
    expect(getTextoNotaAvaliacao(nota, escalaAvaliacaoPadrao)).not.toBe(
      "Sem avaliação"
    );
  });
});
