import {
  InvalidCredentialsError,
  TechnicalError,
} from "../errors/applicationErrors";

/**
 * Conversão de erros de autenticação para a taxonomia F0-05.
 *
 * Nenhuma mensagem do Supabase é repassada diretamente à UI; o erro é
 * classificado por código estruturado (`invalid_credentials`) e tudo mais vira
 * falha técnica segura.
 */

function codigoEstruturado(erro: unknown): string | undefined {
  if (typeof erro === "object" && erro !== null && "code" in erro) {
    const code = (erro as { code?: unknown }).code;
    return typeof code === "string" ? code : undefined;
  }
  return undefined;
}

export function mapearErroDeLogin(erro: unknown): InvalidCredentialsError | TechnicalError {
  if (codigoEstruturado(erro) === "invalid_credentials") {
    return new InvalidCredentialsError({ cause: erro });
  }
  return new TechnicalError({ cause: erro });
}

export function mapearErroTecnico(erro: unknown): TechnicalError {
  return new TechnicalError({ cause: erro });
}
