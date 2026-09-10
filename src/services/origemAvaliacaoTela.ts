/**
 * F5-06 (Issue #103) — ORIGEM da avaliação para as telas de leitura/edição.
 *
 * Depois do cutover existem DOIS acervos que precisam conviver na mesma tela:
 *
 * 1. **LEGADO_LOCAL** — registros anteriores ao cutover, lidos do
 *    `localStorage`, SOMENTE LEITURA (nunca voltam a ser autoridade);
 * 2. **POSTGRES** — avaliações novas, que existem exclusivamente no banco e são
 *    lidas pelo caminho soberano (`evaluation_painel_participante`).
 *
 * A classificação é ESTRUTURAL, nunca por data: um id técnico (UUID) com escrita
 * confirmada é do banco; qualquer outra coisa é legado. Nenhuma heurística de
 * data participa da decisão (D12 — correção pós-auditoria).
 *
 * Este módulo não contém autorização: a leitura do acervo novo passa pela Edge
 * Function e, portanto, pelo Policy Engine.
 */

import { ehIdTecnicoPostgres } from "../infrastructure/supabase/avaliacoes/cutover.ts";
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
 * O id informado é uma avaliação NOVA (id técnico vindo de escrita confirmada
 * no PostgreSQL)? A evidência é ESTRUTURAL, nunca uma data.
 */
export function ehAvaliacaoNova(evaluationId: string | undefined): boolean {
  return ehIdTecnicoPostgres(evaluationId);
}

/**
 * Lê uma avaliação para a tela, decidindo a origem ESTRUTURALMENTE pelo id:
 * UUID ⇒ painel soberano; caso contrário ⇒ acervo legado (somente leitura).
 *
 * Quando o id é técnico, a leitura SÓ pode vir do banco: não há fallback para o
 * acervo local (fail-closed).
 */
export async function lerAvaliacaoParaTela(
  entrada: {
    readonly organizationId: string;
    readonly evaluationId: string | undefined;
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<
  | { readonly ok: true; readonly leitura: LeituraAvaliacao | null }
  | { readonly ok: false; readonly erro: string }
> {
  const id = entrada.evaluationId;

  if (!ehIdTecnicoPostgres(id)) {
    const legado =
      getFeedbacks().find((item) => item.id === id) ?? null;
    return { ok: true, leitura: legado ? { origem: "LEGADO_LOCAL", legado } : null };
  }

  const painel = await carregarPainelSoberano(
    { organizationId: entrada.organizationId, evaluationId: id },
    deps
  );
  if (!painel.ok) return { ok: false, erro: painel.erro ?? "Leitura recusada." };
  if (!painel.data) return { ok: true, leitura: null };

  return { ok: true, leitura: { origem: "POSTGRES", painel: painel.data } };
}
