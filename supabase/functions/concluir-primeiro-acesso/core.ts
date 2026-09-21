/**
 * F6-A20 (Issue #321) — decisões PURAS da conclusão do primeiro acesso.
 *
 * O runtime Deno não é testável no Vitest, então a fronteira (`index.ts`) fica
 * fina e TODA a regra de consistência Auth ↔ Postgres é decidida aqui, de forma
 * determinística e provada por teste.
 *
 * ESTRATÉGIA (auditoria do SHA d538862 — sem transação única Auth ↔ Postgres):
 * uma SAGA com o ESTADO SOBERANO como ponto de commit.
 *   1. a senha é escrita no Supabase Auth PRIMEIRO: é idempotente (repetir é
 *      seguro) e não concede nada por si só;
 *   2. o estado `user_profiles.first_access_pending` é o ÚLTIMO passo e exige
 *      PROVA de que a linha foi efetivamente alterada — um UPDATE sem
 *      representação devolvida não prova nada;
 *   3. sem essa prova, o estado corrente é VERIFICADO por leitura e a conclusão
 *      só é reportada se a leitura confirmar que não há mais pendência.
 *
 * Consequências exigidas pelo contrato:
 * - NUNCA se responde `completed` sem prova soberana de conclusão;
 * - falha depois da senha NÃO deixa o onboarding meio concluído: a pendência
 *   permanece `true` (o acesso segue bloqueado) e o RETRY converge, porque o
 *   gate aceita nova tentativa enquanto a pendência existir;
 * - nada depende de URL, `localStorage` ou estado de tela: a fonte é o perfil
 *   soberano lido server-side.
 */

/** Corpo mínimo de `user_profiles` que interessa a esta fronteira. */
interface LinhaPerfil {
  readonly first_access_pending?: unknown;
}

function registro(valor: unknown): LinhaPerfil | null {
  if (typeof valor !== "object" || valor === null || Array.isArray(valor)) return null;
  return valor as LinhaPerfil;
}

export type DecisaoDeEntrada =
  | { readonly ok: true }
  | { readonly ok: false; readonly codigo: string; readonly status: number };

/**
 * Gate de entrada: só um perfil EXISTENTE e com pendência `true` pode concluir o
 * primeiro acesso. Sem perfil (ou com erro de leitura) ⇒ fail-closed; sem
 * pendência ⇒ `ALREADY_COMPLETED` (a conclusão já é um FATO soberano).
 */
export function decidirEntradaDoPrimeiroAcesso(
  perfil: unknown,
  erro: unknown
): DecisaoDeEntrada {
  if (erro) return { ok: false, codigo: "NOT_AUTHORIZED", status: 403 };

  const linha = registro(perfil);
  if (!linha) return { ok: false, codigo: "NOT_AUTHORIZED", status: 403 };

  if (linha.first_access_pending !== true) {
    return { ok: false, codigo: "ALREADY_COMPLETED", status: 409 };
  }

  return { ok: true };
}

/**
 * Quantas linhas o UPDATE efetivamente alterou, a partir do retorno do cliente
 * (PostgREST devolve a REPRESENTAÇÃO das linhas alteradas quando ela é
 * solicitada). `null` = não houve representação ⇒ **não há prova**.
 */
export function linhasAfetadasDoRetorno(retorno: unknown): number | null {
  return Array.isArray(retorno) ? retorno.length : null;
}

/**
 * Pendência confirmada por LEITURA de verificação: `true` = ainda pendente,
 * `false` = concluído (fato soberano), `null` = não foi possível provar nada
 * (erro ou formato inesperado) — sempre fail-closed.
 */
export function pendenciaConfirmada(perfil: unknown, erro: unknown): boolean | null {
  if (erro) return null;
  const linha = registro(perfil);
  if (!linha) return null;
  if (linha.first_access_pending === false) return false;
  if (linha.first_access_pending === true) return true;
  return null;
}

export type DecisaoDeConclusao =
  | {
      readonly tipo: "concluido";
      /** De onde veio a prova: linha alterada ou estado verificado por leitura. */
      readonly prova: "linha_afetada" | "estado_verificado";
    }
  | { readonly tipo: "nao_concluido"; readonly codigo: string; readonly status: number };

export interface EntradaDaConclusao {
  readonly erroDaAtualizacao: unknown;
  /** Linhas alteradas pelo UPDATE (`null` quando não houve representação). */
  readonly linhasAfetadas: number | null;
  /** Resultado da leitura de verificação (`null` = indisponível). */
  readonly estadoConfirmado: boolean | null;
}

/**
 * Decide se a conclusão pode ser REPORTADA.
 *
 * - `EXATAMENTE 1` linha alterada e sem erro ⇒ conclusão provada pela própria
 *   escrita (nenhuma leitura extra é necessária);
 * - qualquer outro desfecho (erro, 0 linhas, representação ausente) ⇒ só conclui
 *   se a leitura de verificação provar que a pendência não existe mais (caso de
 *   conclusão concorrente); se a pendência ainda existir ⇒ `INCOMPLETE` (retry
 *   converge); se nada puder ser provado ⇒ `INTERNAL`.
 *
 * Em nenhum caminho o estado é "limpo" sem prova: a pendência só desaparece pelo
 * UPDATE com predicado de pendência, e a resposta de sucesso exige uma das duas
 * provas acima.
 */
export function decidirConclusaoDoPrimeiroAcesso(
  entrada: EntradaDaConclusao
): DecisaoDeConclusao {
  if (!entrada.erroDaAtualizacao && entrada.linhasAfetadas === 1) {
    return { tipo: "concluido", prova: "linha_afetada" };
  }

  if (entrada.estadoConfirmado === false) {
    return { tipo: "concluido", prova: "estado_verificado" };
  }

  if (entrada.estadoConfirmado === true) {
    return { tipo: "nao_concluido", codigo: "INCOMPLETE", status: 500 };
  }

  return { tipo: "nao_concluido", codigo: "INTERNAL", status: 500 };
}
