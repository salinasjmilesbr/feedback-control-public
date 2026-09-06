import { describe, expect, it } from "vitest";
import { AuthorizationError as LegacyAuthorizationError } from "../authorization/authorizationError";
import { authorize } from "../authorization/authorizationPolicy";
import {
  ApplicationError,
  AuthorizationError,
  ConflictError,
  ForbiddenError,
  InvalidCredentialsError,
  NotFoundError,
  TechnicalError,
  ValidationError,
  toPublicError,
} from "./index";

describe("taxonomia comum de erros", () => {
  it.each([
    [new ValidationError(), "ValidationError", "VALIDATION_ERROR", "validation"],
    [new InvalidCredentialsError(), "InvalidCredentialsError", "INVALID_CREDENTIALS", "authentication"],
    [new AuthorizationError("settings.manage"), "AuthorizationError", "FORBIDDEN", "authorization"],
    [new ForbiddenError(), "ForbiddenError", "FORBIDDEN", "authorization"],
    [new ConflictError(), "ConflictError", "CONFLICT", "conflict"],
    [new NotFoundError(), "NotFoundError", "NOT_FOUND", "not_found"],
    [new TechnicalError(), "TechnicalError", "TECHNICAL_ERROR", "technical"],
  ] as const)("classifica %s como %s / %s / %s", (error, name, code, category) => {
    expect(error).toBeInstanceOf(Error);
    expect(error).toBeInstanceOf(ApplicationError);
    expect(error).toMatchObject({ name, code, category });
    expect(error.errorId).toBeUndefined();
    expect(toPublicError(error)).toEqual({ code, category, message: error.publicMessage });
  });

  it("mantém identidade, construtor e mensagem legados de autorização", () => {
    expect(AuthorizationError).toBe(LegacyAuthorizationError);
    const error = new LegacyAuthorizationError("settings.manage");
    expect(error).toBeInstanceOf(AuthorizationError);
    expect(error.message).toBe("Operação não permitida: settings.manage");
    expect(error.capability).toBe("settings.manage");
    expect(toPublicError(error)).toEqual({
      code: "FORBIDDEN", category: "authorization",
      message: "Você não tem permissão para realizar esta operação.",
    });
  });

  it("classifica a negação real da policy sem alterar a autorização", () => {
    expect.assertions(3);
    try {
      authorize({ actor: { matricula: 99001, funcao: "ANALISTA", status: "ATIVO" } }, "settings.manage", { kind: "global" });
    } catch (error) {
      expect(error).toBeInstanceOf(LegacyAuthorizationError);
      expect(error).toBeInstanceOf(ApplicationError);
      expect(toPublicError(error).category).toBe("authorization");
    }
  });

  it.each([ValidationError, InvalidCredentialsError, ForbiddenError, ConflictError, NotFoundError, TechnicalError])(
    "%s preserva contexto interno sem expô-lo na projeção", (ErrorClass) => {
      const cause = new Error("Detalhe interno fictício que não deve aparecer na UI");
      const error = new ErrorClass({ cause, errorId: "correlacao-ficticia-001" });
      error.message = "Mensagem interna fictícia";
      error.stack = "Stack interno fictício";

      expect(error.cause).toBe(cause);
      expect(error.errorId).toBe("correlacao-ficticia-001");
      expect(toPublicError(error)).toEqual({ code: error.code, category: error.category, message: error.publicMessage });
      expect(Object.keys(toPublicError(error)).sort()).toEqual(["category", "code", "message"]);
      expect(JSON.stringify(toPublicError(error))).not.toMatch(/fictíci|correlacao|stack|cause/);
    }
  );

  it("autorização aceita correlação opcional sem publicar capability ou causa", () => {
    const cause = new Error("Causa fictícia");
    const error = new AuthorizationError("settings.manage", { cause, errorId: "correlacao-001" });
    expect(error.cause).toBe(cause);
    expect(error.errorId).toBe("correlacao-001");
    expect(toPublicError(error)).toEqual(toPublicError(new AuthorizationError("collaborator.create")));
  });

  it.each([
    undefined, null, "conteúdo fictício", 42,
    new Error("detalhe fictício"),
    { code: "FORBIDDEN", category: "authorization", publicMessage: "conteúdo fictício" },
    { name: "ValidationError", message: "conteúdo fictício" },
  ])("trata valor desconhecido %s como falha técnica segura", (error) => {
    expect(toPublicError(error)).toEqual({
      code: "TECHNICAL_ERROR", category: "technical",
      message: "Não foi possível concluir a operação. Tente novamente mais tarde.",
    });
  });

  it("alterar uma projeção retornada não altera mensagens de outras chamadas", () => {
    const error = new TechnicalError();
    const projection = toPublicError(error);
    Object.assign(projection, { message: "mensagem substituída" });
    expect(toPublicError(error).message).toBe(error.publicMessage);
  });
});
