import {
  ConflictError,
  ForbiddenError,
  TechnicalError,
  ValidationError,
  type ApplicationError,
} from "../errors/applicationErrors";

/**
 * Conversão de erros do convite administrativo (F2-06) para a taxonomia F0-05.
 *
 * O frontend NÃO possui credenciais privilegiadas nem detalhes internos: apenas
 * invoca a Edge Function e mapeia o código seguro devolvido por ela para um
 * erro público.
 */
export function mapearErroConvite(erro: unknown): ApplicationError {
  const codigo = obterCodigoConvite(erro);

  switch (codigo) {
    case "NOT_AUTHORIZED":
      return new ForbiddenError({ cause: erro });
    case "INVALID_EMAIL":
    case "INVALID_ORGANIZATION":
    case "INVALID_INPUT":
      return new ValidationError({ cause: erro });
    case "USER_EXISTS":
      return new ConflictError({ cause: erro });
    default:
      return new TechnicalError({ cause: erro });
  }
}

function obterCodigoConvite(erro: unknown): string | undefined {
  if (typeof erro !== "object" || erro === null || !("context" in erro)) {
    return undefined;
  }
  const contexto = (erro as { context?: unknown }).context;
  if (typeof contexto !== "object" || contexto === null || !("error" in contexto)) {
    return undefined;
  }
  const interno = (contexto as { error?: unknown }).error;
  if (typeof interno !== "object" || interno === null || !("code" in interno)) {
    return undefined;
  }
  const codigo = (interno as { code?: unknown }).code;
  return typeof codigo === "string" ? codigo : undefined;
}
