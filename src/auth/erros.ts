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

export type ClassificacaoErroValidacaoSessao = "sessaoInvalida" | "falhaTransitoria";

/**
 * F5-01 (Q1 aprovada/D11): classifica o erro da revalidação (`auth.getUser`).
 *
 * - status HTTP 4xx (401/403: sessão inválida, ban, usuário removido) ou
 *   `AuthSessionMissingError` ⇒ `sessaoInvalida` (encerra o acesso);
 * - sem status HTTP (rede/timeout) ou 5xx ⇒ `falhaTransitoria` (mantém a
 *   sessão local e reintenta; sem logout automático — fail-closed permanece).
 */
export function classificarErroValidacaoSessao(erro: unknown): ClassificacaoErroValidacaoSessao {
  if (typeof erro === "object" && erro !== null) {
    const status = (erro as { status?: unknown }).status;
    if (typeof status === "number" && status >= 400 && status < 500) {
      return "sessaoInvalida";
    }
    const nome = (erro as { name?: unknown }).name;
    if (nome === "AuthSessionMissingError") {
      return "sessaoInvalida";
    }
  }
  return "falhaTransitoria";
}
