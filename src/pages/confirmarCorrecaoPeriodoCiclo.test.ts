import { describe, expect, it, vi } from "vitest";
import type { ImpactoTemporalPeriodoCiclo } from "../types/CicloAvaliacao";
import { confirmarCorrecaoPeriodoComImpacto } from "./confirmarCorrecaoPeriodoCiclo";

function impacto(total: number): ImpactoTemporalPeriodoCiclo {
  return {
    avaliacoes: { quantidade: total > 0 ? 1 : 0, ids: total > 0 ? ["a"] : [] },
    metas: { quantidade: total > 1 ? 1 : 0, ids: total > 1 ? ["m"] : [] },
    observacoes: {
      quantidade: total > 2 ? 1 : 0,
      ids: total > 2 ? ["o"] : [],
    },
    total,
  };
}

describe("confirmação da correção de período", () => {
  it("permite impacto zero sem alerta extraordinário", () => {
    const confirmar = vi.fn(() => false);
    expect(confirmarCorrecaoPeriodoComImpacto(impacto(0), confirmar)).toBe(true);
    expect(confirmar).not.toHaveBeenCalled();
  });

  it("alerta quantidades e preservação quando há impacto", () => {
    const confirmar = vi.fn(() => true);
    expect(confirmarCorrecaoPeriodoComImpacto(impacto(3), confirmar)).toBe(true);
    expect(confirmar).toHaveBeenCalledWith(expect.stringContaining("3 registros"));
    expect(confirmar).toHaveBeenCalledWith(expect.stringContaining("1 avaliação"));
    expect(confirmar).toHaveBeenCalledWith(expect.stringContaining("preservados"));
    expect(confirmar).toHaveBeenCalledWith(expect.stringContaining("vinculados ao ciclo"));
  });

  it("permite cancelar o alerta sem confirmar a operação", () => {
    expect(confirmarCorrecaoPeriodoComImpacto(impacto(3), () => false)).toBe(
      false
    );
  });
});
