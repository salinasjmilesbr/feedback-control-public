/**
 * F5-06 (Issue #103) — ORIGEM da avaliação para as telas de leitura/edição.
 *
 * Depois do cutover existem DOIS acervos que convivem na mesma tela:
 *
 * 1. **LEGADO_LOCAL** — registros anteriores ao cutover, lidos do
 *    `localStorage`, SOMENTE LEITURA (nunca voltam a ser autoridade);
 * 2. **POSTGRES** — avaliações novas, que existem exclusivamente no banco e são
 *    lidas pelo caminho soberano (`evaluation_painel_participante`).
 *
 * ## Decisão de origem — fonte ÚNICA (`classificarOrigem`)
 *
 * A origem NÃO é inferida por formato de id nem por data. Ela exige EVIDÊNCIA
 * ESTRUTURAL de cutover: o id precisa constar do registro explícito de escritas
 * server-side CONFIRMADAS (`avaliacaoVinculadaAoBanco`). Assim:
 *
 * - id legado numérico/textual ⇒ `LEGADO_LOCAL`;
 * - id com FORMATO de UUID mas sem registro de cutover ⇒ `LEGADO_LOCAL`
 *   (formato não é evidência — fail-closed);
 * - registro de cutover ausente/corrompido ⇒ `LEGADO_LOCAL` (nada é promovido
 *   por omissão);
 * - id com evidência registrada ⇒ `POSTGRES`, e aí a leitura SÓ pode vir do
 *   banco: falha de leitura é fail-closed, sem fallback para o legado.
 *
 * O registro de cutover é livro-caixa de ROTEAMENTO do cliente: não é
 * autorização, não é tenancy e não prova existência (quem prova é o PostgreSQL,
 * via Edge + Policy Engine).
 */

import {
  avaliacaoVinculadaAoBanco,
  type ArmazenamentoCutover,
} from "../infrastructure/supabase/avaliacoes/cutover.ts";
import type { PainelParticipante } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";
import {
  carregarPainelSoberano,
  type DependenciasAcessoAvaliacoes,
} from "./acessoAvaliacoesSoberanas.ts";
import { getFeedbacks } from "./feedbackStorage.ts";

export type OrigemAvaliacaoTela = "POSTGRES" | "LEGADO_LOCAL";

export interface LeituraAvaliacao {
  readonly origem: OrigemAvaliacaoTela;
  /** Presente somente quando a origem é o PostgreSQL. */
  readonly painel?: PainelParticipante;
  /** Presente somente quando a origem é o legado local. */
  readonly legado?: unknown;
}

/**
 * FONTE ÚNICA da decisão de origem para as telas. Usa SEMPRE a mesma evidência
 * do caminho soberano (`avaliacaoVinculadaAoBanco`): id técnico **e** registro
 * explícito de escrita confirmada. Formato de UUID, isoladamente, NÃO promove.
 *
 * `registroCutover`:
 * - omitido ⇒ usa o registro do ambiente (produção);
 * - `null` explícito ⇒ evidência INDISPONÍVEL ⇒ `LEGADO_LOCAL` (fail-closed).
 */
export function classificarOrigem(
  evaluationId: string | undefined,
  registroCutover?: ArmazenamentoCutover | null
): OrigemAvaliacaoTela {
  if (typeof evaluationId !== "string") return "LEGADO_LOCAL";
  if (registroCutover === null) return "LEGADO_LOCAL";
  return avaliacaoVinculadaAoBanco(evaluationId, registroCutover)
    ? "POSTGRES"
    : "LEGADO_LOCAL";
}

/** A avaliação é NOVA (existe exclusivamente no PostgreSQL), por EVIDÊNCIA? */
export function ehAvaliacaoNova(
  evaluationId: string | undefined,
  registroCutover?: ArmazenamentoCutover | null
): boolean {
  return classificarOrigem(evaluationId, registroCutover) === "POSTGRES";
}

/**
 * Lê uma avaliação para a tela, decidindo a origem pela fonte única
 * (`classificarOrigem`, baseada em evidência de cutover — nunca no formato do
 * id nem em data):
 *
 * - `POSTGRES` ⇒ painel soberano; falha de leitura é fail-closed (sem fallback);
 * - `LEGADO_LOCAL` ⇒ registro do acervo local (somente leitura), se existir.
 */
export async function lerAvaliacaoParaTela(
  entrada: {
    readonly organizationId: string;
    readonly evaluationId: string | undefined;
    readonly registroCutover?: ArmazenamentoCutover | null;
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<
  | { readonly ok: true; readonly leitura: LeituraAvaliacao | null }
  | { readonly ok: false; readonly erro: string }
> {
  const id = entrada.evaluationId;

  if (classificarOrigem(id, entrada.registroCutover) === "LEGADO_LOCAL") {
    const legado = getFeedbacks().find((item) => item.id === id) ?? null;
    return { ok: true, leitura: legado ? { origem: "LEGADO_LOCAL", legado } : null };
  }

  // Origem POSTGRES: a leitura é SOBERANA. Ausência/corrupção da evidência já
  // foi tratada acima como legado; aqui a evidência existe e a única fonte
  // possível é o banco — sem fallback local (fail-closed).
  const painel = await carregarPainelSoberano(
    { organizationId: entrada.organizationId, evaluationId: id! },
    deps
  );
  if (!painel.ok) return { ok: false, erro: painel.erro ?? "Leitura recusada." };
  if (!painel.data) return { ok: false, erro: "Avaliação não encontrada para o seu acesso." };

  return { ok: true, leitura: { origem: "POSTGRES", painel: painel.data } };
}
