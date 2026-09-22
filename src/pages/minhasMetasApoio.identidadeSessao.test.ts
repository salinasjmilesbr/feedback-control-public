import { describe, expect, it } from "vitest";
import { identidadeDaSessao } from "./minhasMetasApoio";
import pageFonte from "./MinhasMetasPage.tsx?raw";

/**
 * #333 — "Minhas Metas" reconhece o ator pelo UUID do VÍNCULO soberano; a
 * matrícula é apenas rótulo de apresentação. Sem vínculo o caminho é
 * fail-closed (mensagem explícita), nunca "lista vazia".
 */

const VINCULO = "11111111-1111-4111-8111-111111111111";

function identidadeBase(colaboradorId?: string, matricula?: number) {
  return {
    status: "ATIVO" as const,
    nome: "Carolina Mendes Rocha",
    email: "",
    cargo: "",
    area: "",
    respondePara: "",
    ...(colaboradorId === undefined ? {} : { collaboratorId: colaboradorId }),
    ...(matricula === undefined ? {} : { matricula }),
  };
}

describe("#333 — identidade da sessão em Minhas Metas", () => {
  it("funciona com collaboratorId MESMO SEM matrícula (matrícula é apresentação)", () => {
    expect(identidadeDaSessao(identidadeBase(VINCULO))).toEqual({
      collaboratorId: VINCULO,
      matriculaApresentacao: null,
    });
  });

  it("mantém a matrícula apenas como rótulo quando ela existir", () => {
    expect(identidadeDaSessao(identidadeBase(VINCULO, 4242))).toEqual({
      collaboratorId: VINCULO,
      matriculaApresentacao: "4242",
    });
  });

  it("AUSÊNCIA de collaboratorId continua fail-closed", () => {
    expect(identidadeDaSessao(identidadeBase()).collaboratorId).toBeNull();
    expect(identidadeDaSessao(identidadeBase("")).collaboratorId).toBeNull();
    expect(identidadeDaSessao(undefined).collaboratorId).toBeNull();
  });

  it("a PÁGINA gateia por collaboratorId e resolve o colaborador por UUID", () => {
    expect(pageFonte).toContain("identidadeDaSessao(usuarioAtual)");
    expect(pageFonte).toContain("if (!collaboratorId) {");
    expect(pageFonte).toContain("mensagem: SEM_ATOR");
    expect(pageFonte).not.toContain("if (!matriculaApresentacao)");
    expect(pageFonte).toMatch(
      /obterColaborador\(\s*\{\s*collaboratorId,\s*organizationId: organizacaoAtivaId\s*\}/
    );
    expect(pageFonte).not.toMatch(/obterColaborador\(\s*\{\s*matricula:/);
  });
});