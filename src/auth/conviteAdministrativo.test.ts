import { describe, expect, it } from "vitest";
import {
  ConflictError,
  ForbiddenError,
  TechnicalError,
  ValidationError,
} from "../errors/applicationErrors";
import { mapearErroConvite } from "./conviteAdministrativo";

function erroDaFuncao(codigo: string | undefined) {
  return { context: { error: { code: codigo, message: "mensagem interna segura" } } };
}

describe("mapearErroConvite (F2-06)", () => {
  it("não autorizado vira erro de autorização", () => {
    expect(mapearErroConvite(erroDaFuncao("NOT_AUTHORIZED"))).toBeInstanceOf(ForbiddenError);
  });

  it.each(["INVALID_EMAIL", "INVALID_ORGANIZATION", "INVALID_INPUT"])(
    "entrada inválida %s vira erro de validação",
    (codigo) => {
      expect(mapearErroConvite(erroDaFuncao(codigo))).toBeInstanceOf(ValidationError);
    }
  );

  it("usuário já existente vira conflito", () => {
    expect(mapearErroConvite(erroDaFuncao("USER_EXISTS"))).toBeInstanceOf(ConflictError);
  });

  it.each([
    undefined,
    "CODIGO_DESCONHECIDO",
    null,
    new Error("detalhe interno fictício"),
    {},
  ])("erro desconhecido ou sem contexto vira falha técnica segura: %s", (erro) => {
    expect(mapearErroConvite(erro)).toBeInstanceOf(TechnicalError);
  });

  it("não vaza a mensagem interna na projeção pública", () => {
    const erro = mapearErroConvite(erroDaFuncao("NOT_AUTHORIZED"));
    expect(JSON.stringify(erro.publicMessage)).not.toContain("mensagem interna");
    expect(erro.publicMessage).toBe("Você não tem permissão para realizar esta operação.");
  });
});
