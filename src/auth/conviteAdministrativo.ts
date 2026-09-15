import {
  ConflictError,
  ForbiddenError,
  TechnicalError,
  ValidationError,
  type ApplicationError,
} from "../errors/applicationErrors";
import { corpoDeErroEdge } from "../infrastructure/supabase/errosEdge";

/**
 * Conversão de erros do convite administrativo (F2-06) para a taxonomia F0-05.
 *
 * O frontend NÃO possui credenciais privilegiadas nem detalhes internos: apenas
 * invoca a Edge Function e mapeia o código seguro devolvido por ela para um
 * erro público.
 *
 * DEFEITO CORRIGIDO (Issue #224, continuação da #221/#223): no runtime de
 * `@supabase/functions-js`, `FunctionsHttpError.context` é o **`Response`** real
 * (a lib executa `throw new FunctionsHttpError(response)`) e o corpo NÃO vem
 * decodificado. A leitura anterior era **síncrona** (`context.error.code`) e
 * devolvia `undefined` em produção ⇒ **toda** negação do convite virava
 * `TechnicalError`, e os códigos públicos (`NOT_AUTHORIZED`, `INVALID_EMAIL`,
 * `INVALID_ORGANIZATION`, `INVALID_INPUT`, `USER_EXISTS`) nunca chegavam à
 * aplicação.
 *
 * A leitura passa a ser **assíncrona** e delegada à **fonte única** já existente
 * — `corpoDeErroEdge` (Issue #221) —, sem duplicar a regra. A taxonomia pública
 * e o fallback **fail-closed** do domínio ficam preservados: corpo inválido,
 * vazio, fora do contrato ou código desconhecido ⇒ `TechnicalError`.
 *
 * Não há regra de autorização, RPC ou RLS aqui: apenas a projeção do erro
 * público devolvido pela fronteira.
 */
export async function mapearErroConvite(erro: unknown): Promise<ApplicationError> {
  const codigo = await obterCodigoConvite(erro);

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

/**
 * Código público do corpo de erro da Edge, lido pela fonte única `errosEdge`.
 * **Fail-closed**: ausência de corpo legível, corpo fora do contrato ou `code`
 * não textual ⇒ `undefined` (o chamador aplica `TechnicalError`).
 */
async function obterCodigoConvite(erro: unknown): Promise<string | undefined> {
  const corpo = await corpoDeErroEdge(erro);
  return typeof corpo?.code === "string" ? corpo.code : undefined;
}
