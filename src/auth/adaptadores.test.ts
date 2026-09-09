import { describe, expect, it } from "vitest";
import { normalizarStatus } from "./adaptadores";

describe("normalização fail-closed de status (F5-01, D10/G7)", () => {
  it("somente 'active' é ativo; qualquer outro valor vira inativo", () => {
    expect(normalizarStatus("active")).toBe("active");
    expect(normalizarStatus("disabled")).toBe("disabled");
    expect(normalizarStatus("inativo")).toBe("disabled");
    expect(normalizarStatus("")).toBe("disabled");
    expect(normalizarStatus("ACTIVE")).toBe("disabled");
    expect(normalizarStatus("pending")).toBe("disabled");
  });
});
