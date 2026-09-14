/**
 * F5-10 P5.1 (Issue #221) — leitura do corpo de erro das Edge Functions.
 *
 * CONTEXTO DO DEFEITO (confirmado no runtime de `@supabase/functions-js`):
 * `cliente.functions.invoke()` devolve `{ data, error }` sem lançar; quando o
 * status não é 2xx, `error` é um `FunctionsHttpError` cujo **`context` é o objeto
 * `Response`** — o corpo NÃO vem decodificado. A própria documentação da lib
 * manda ler com `await error.context.json()` (ver
 * `@supabase/functions-js/dist/main/FunctionsClient.js`: o `throw new
 * FunctionsHttpError(response)` passa o `Response`).
 *
 * Os adapters liam `error.context.error.code` como se `context` fosse o corpo já
 * convertido em objeto: `undefined` em produção ⇒ TODA negação da Edge virava
 * `FORBIDDEN` genérico, e `CONFLICT`/`NOT_FOUND` (inclusive `expected_version`
 * divergente) nunca chegavam à aplicação.
 *
 * Esta função é a fonte ÚNICA da leitura, para os quatro adapters Edge do cliente
 * (metas, ciclos, colaboradores e avaliações). Ela:
 * - aceita `context` como `Response` REAL (ou qualquer objeto com `.json()`);
 * - mantém compatibilidade com o formato antigo (objeto já decodificado),
 *   usado por testes e por versões anteriores da lib;
 * - é FAIL-CLOSED: corpo vazio, JSON inválido, corpo fora do contrato
 *   (`{ error: { code, message } }`) ou ausência de `context` devolvem `null`, e o
 *   adapter aplica o código/mensagem públicos padrão;
 * - NUNCA lança: qualquer falha ao interpretar o erro vira `null` (o tratamento do
 *   erro original jamais esconde a falha de transporte com uma nova exceção).
 *
 * Não há regra de domínio, autorização, RPC ou RLS aqui: apenas a leitura do corpo
 * público devolvido pela fronteira.
 */

/** Corpo público de erro da Edge (`{ error: { code, message } }`). */
export interface CorpoErroEdge {
  readonly code?: unknown;
  readonly message?: unknown;
}

/** `{ error: { code, message } }` (contrato) ou `null` (fora do contrato). */
function extrairCorpoErro(valor: unknown): CorpoErroEdge | null {
  if (typeof valor !== "object" || valor === null) return null;
  const interno = (valor as { error?: unknown }).error;
  if (typeof interno !== "object" || interno === null) return null;
  const corpo = interno as CorpoErroEdge;
  // `{}` não é um corpo de erro útil: fail-closed (mensagem padrão do adapter).
  return corpo.code === undefined && corpo.message === undefined ? null : corpo;
}

/** `Response` (mesma realm ou não) ou qualquer objeto legível por `.json()`. */
function possuiJson(valor: unknown): valor is { json(): Promise<unknown> } {
  return (
    typeof valor === "object" &&
    valor !== null &&
    typeof (valor as { json?: unknown }).json === "function"
  );
}

/**
 * Corpo público de erro a partir do `error` de `functions.invoke` — nunca lança.
 */
export async function corpoDeErroEdge(erro: unknown): Promise<CorpoErroEdge | null> {
  if (typeof erro !== "object" || erro === null) return null;
  const contexto = (erro as { context?: unknown }).context;
  if (contexto === undefined || contexto === null) return null;

  try {
    if (possuiJson(contexto)) return extrairCorpoErro(await contexto.json());
    return extrairCorpoErro(contexto);
  } catch {
    // Corpo vazio, JSON inválido ou stream já consumido ⇒ fail-closed.
    return null;
  }
}
