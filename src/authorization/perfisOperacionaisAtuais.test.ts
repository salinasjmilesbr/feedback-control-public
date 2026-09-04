import { describe, expect, it } from "vitest";
import { perfilPossuiFluxosPropriosAtuais } from "./perfisOperacionaisAtuais";

describe("perfis operacionais atuais", () => {
  it.each(["COORDENADOR", "CONSULTOR", "ANALISTA", "ESTAGIARIO"] as const)(
    "inclui %s nos fluxos de Minhas avaliações e Minhas metas",
    (perfil) => expect(perfilPossuiFluxosPropriosAtuais(perfil)).toBe(true)
  );

  it("não concede fluxos próprios nem permissões administrativas ao gerente", () => {
    expect(perfilPossuiFluxosPropriosAtuais("GERENTE")).toBe(false);
    expect(perfilPossuiFluxosPropriosAtuais(undefined)).toBe(false);
  });
});
