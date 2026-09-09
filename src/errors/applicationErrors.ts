const publicErrors = {
  VALIDATION_ERROR: { category: "validation", message: "Verifique os dados informados e tente novamente." },
  INVALID_CREDENTIALS: { category: "authentication", message: "E-mail ou senha inválidos." },
  ACCESS_NOT_PROVISIONED: { category: "authentication", message: "Seu acesso ainda não foi liberado. Fale com o administrador." },
  FORBIDDEN: { category: "authorization", message: "Você não tem permissão para realizar esta operação." },
  CONFLICT: { category: "conflict", message: "Não foi possível concluir a operação devido a um conflito." },
  NOT_FOUND: { category: "not_found", message: "O item solicitado não foi encontrado." },
  TECHNICAL_ERROR: { category: "technical", message: "Não foi possível concluir a operação. Tente novamente mais tarde." },
} as const;

export type ApplicationErrorCode = keyof typeof publicErrors;
export type ApplicationErrorCategory = (typeof publicErrors)[ApplicationErrorCode]["category"];

export interface ApplicationErrorOptions {
  /** Causa interna: nunca apresentar diretamente na UI. */
  cause?: unknown;
  /** Identificador opaco fornecido pelo chamador; sem geração, logging ou envio. */
  errorId?: string;
}

export interface PublicApplicationError {
  readonly code: ApplicationErrorCode;
  readonly category: ApplicationErrorCategory;
  readonly message: string;
}

export abstract class ApplicationError<Code extends ApplicationErrorCode = ApplicationErrorCode> extends Error {
  readonly code: Code;
  readonly category: ApplicationErrorCategory;
  readonly publicMessage: string;
  readonly errorId?: string;

  protected constructor(code: Code, options?: ApplicationErrorOptions, internalMessage?: string) {
    super(internalMessage ?? publicErrors[code].message, options);
    this.code = code;
    this.category = publicErrors[code].category;
    this.publicMessage = publicErrors[code].message;
    this.errorId = options?.errorId;
  }
}

export class ValidationError extends ApplicationError<"VALIDATION_ERROR"> {
  constructor(options?: ApplicationErrorOptions) {
    super("VALIDATION_ERROR", options);
    this.name = "ValidationError";
  }
}

export class InvalidCredentialsError extends ApplicationError<"INVALID_CREDENTIALS"> {
  constructor(options?: ApplicationErrorOptions) {
    super("INVALID_CREDENTIALS", options);
    this.name = "InvalidCredentialsError";
  }
}

/**
 * F5-01 (Q3 aprovada): conta autenticada sem `user_profile` — acesso ainda não
 * provisionado. Mensagem neutra/orientativa, sem expor detalhes internos.
 */
export class AccessNotProvisionedError extends ApplicationError<"ACCESS_NOT_PROVISIONED"> {
  constructor(options?: ApplicationErrorOptions) {
    super("ACCESS_NOT_PROVISIONED", options);
    this.name = "AccessNotProvisionedError";
  }
}

export class ForbiddenError extends ApplicationError<"FORBIDDEN"> {
  constructor(options?: ApplicationErrorOptions) {
    super("FORBIDDEN", options);
    this.name = "ForbiddenError";
  }
}

export class ConflictError extends ApplicationError<"CONFLICT"> {
  constructor(options?: ApplicationErrorOptions) {
    super("CONFLICT", options);
    this.name = "ConflictError";
  }
}

export class NotFoundError extends ApplicationError<"NOT_FOUND"> {
  constructor(options?: ApplicationErrorOptions) {
    super("NOT_FOUND", options);
    this.name = "NotFoundError";
  }
}

export class TechnicalError extends ApplicationError<"TECHNICAL_ERROR"> {
  constructor(options?: ApplicationErrorOptions) {
    super("TECHNICAL_ERROR", options);
    this.name = "TechnicalError";
  }
}

/** Projeta somente dados de catálogo; não confia em mensagens ou objetos externos. */
export function toPublicError(error: unknown): PublicApplicationError {
  const code: ApplicationErrorCode = error instanceof ApplicationError && Object.hasOwn(publicErrors, error.code)
    ? error.code
    : "TECHNICAL_ERROR";
  return { code, ...publicErrors[code] };
}
