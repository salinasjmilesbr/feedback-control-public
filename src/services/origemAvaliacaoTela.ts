/**
 * F5-06 (Issue #103) — ORIGEM da avaliação para as telas de leitura/edição.
 *
 * ## A prova de existência vem do SERVIDOR (nunca do cliente)
 *
 * Uma avaliação NOVA existe **exclusivamente no PostgreSQL**. O navegador não
 * pode ser requisito para descobri-la: `localStorage` apagado, outro navegador,
 * outro dispositivo, livro-caixa corrompido ou uma URL aberta diretamente não
 * podem fazer uma avaliação real do banco parecer inexistente.
 *
 * Por isso a resolução é SOBERANA-FIRST (`resolverLeituraAvaliacao`):
 *
 *   1. para qualquer id candidato a avaliação nova, a fronteira confiável é
 *      consultada (Edge → Policy Engine → PostgreSQL), com o tenant revalidado
 *      server-side;
 *   2. se a avaliação soberana existe e é ACESSÍVEL ⇒ `POSTGRES` (fonte única);
 *   3. somente quando o servidor responde SEM a avaliação, um registro do acervo
 *      local com o MESMO id é lido como `LEGADO_LOCAL` (somente leitura —
 *      compatibilidade com registros anteriores ao cutover);
 *   4. sem avaliação soberana e sem registro local ⇒ nada é inventado.
 *
 * O que NUNCA acontece:
 * - formato de UUID como prova de existência no banco;
 * - `localStorage` como prova de existência, de tenant ou de autorização;
 * - heurística de data;
 * - fallback autoritativo: falha de backend (autorização indeterminada, rede,
 *   configuração ausente) NÃO é convertida em leitura local silenciosa.
 *
 * Vazamento de existência cross-tenant: `NOT_FOUND` e `FORBIDDEN` permanecem
 * indistinguíveis para o cliente (contrato fail-closed já adotado) — o ator
 * nunca descobre se um id de outro tenant existe.
 *
 * ## Papel do livro-caixa local
 *
 * O registro de cutover (`CHAVE_AVALIACOES_CORTADAS`) e os índices de navegação
 * seguem existindo como CACHE/ROTEAMENTO opcionais: orientam a tela e evitam
 * tentativas redundantes. Nenhum deles estabelece existência, tenant ou
 * autorização.
 */

import {
  avaliacaoVinculadaAoBanco,
  ehIdTecnicoPostgres,
  type ArmazenamentoCutover,
} from "../infrastructure/supabase/avaliacoes/cutover.ts";
import type { PainelParticipante } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";
import {
  carregarPainelSoberano,
  type DependenciasAcessoAvaliacoes,
} from "./acessoAvaliacoesSoberanas.ts";
import { getFeedbacks } from "./feedbackStorage.ts";

export type OrigemAvaliacaoTela = "POSTGRES" | "LEGADO_LOCAL";

export type LeituraAvaliacao =
  | {
      readonly origem: "POSTGRES";
      readonly painel: PainelParticipante;
      /** O cache de cutover já conhecia este id (apenas informativo). */
      readonly cacheConhecia: boolean;
    }
  | {
      readonly origem: "LEGADO_LOCAL";
      readonly legado: unknown;
      /** O cache de cutover já conhecia este id (apenas informativo). */
      readonly cacheConhecia: boolean;
    };

function lerLegadoLocal(evaluationId: string | undefined): unknown | null {
  return getFeedbacks().find((item) => item.id === evaluationId) ?? null;
}

/**
 * O cache de cutover conhece este id como avaliação técnica do PostgreSQL?
 * É APENAS o livro-caixa local (roteamento) — nunca prova de existência.
 */
export function cacheConheciaComoTecnicaPostgres(
  evaluationId: string | undefined,
  registroCutover?: ArmazenamentoCutover | null
): boolean {
  if (typeof evaluationId !== "string") return false;
  return avaliacaoVinculadaAoBanco(evaluationId, registroCutover ?? null);
}

/**
 * O id é CANDIDATO a avaliação nova? Critério mínimo (formato técnico) e
 * exclusão de colisão com o acervo legado homônimo.
 *
 * A decisão de origem NÃO sai daqui: o servidor é quem prova a existência. Um
 * id técnico sem registro legado homônimo é consultado no banco mesmo que o
 * livro-caixa esteja ausente, corrompido ou tenha sido apagado.
 */
export function ehCandidataAvaliacaoNova(
  evaluationId: string | undefined
): boolean {
  return ehIdTecnicoPostgres(evaluationId);
}

/**
 * Classificação ADVISORY (somente cache). Não decide a origem de uma leitura:
 * use `resolverLeituraAvaliacao`. Mantida para diagnóstico e telemetria.
 */
export function classificarOrigemPorCache(
  evaluationId: string | undefined,
  registroCutover?: ArmazenamentoCutover | null
): OrigemAvaliacaoTela {
  return cacheConheciaComoTecnicaPostgres(evaluationId, registroCutover)
    ? "POSTGRES"
    : "LEGADO_LOCAL";
}

export type ResultadoLeituraAvaliacao =
  | { readonly ok: true; readonly leitura: LeituraAvaliacao | null }
  | { readonly ok: false; readonly erro: string };

/**
 * Resolve a origem E LÊ a avaliação, com a prova de existência vinda do
 * servidor (soberano-first). Ver o cabeçalho do módulo para as garantias.
 */
export async function resolverLeituraAvaliacao(
  entrada: {
    readonly organizationId: string;
    readonly evaluationId: string | undefined;
    readonly registroCutover?: ArmazenamentoCutover | null;
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoLeituraAvaliacao> {
  const id = entrada.evaluationId;
  const cacheConhecia = cacheConheciaComoTecnicaPostgres(id, entrada.registroCutover);

  // Id sem formato técnico nunca é avaliação do banco: é legado (ou inexistente).
  if (!ehCandidataAvaliacaoNova(id)) {
    const legado = lerLegadoLocal(id);
    return {
      ok: true,
      leitura: legado ? { origem: "LEGADO_LOCAL", legado, cacheConhecia } : null,
    };
  }

  // Candidato: a EXISTÊNCIA é decidida pelo servidor (tenant revalidado +
  // Policy Engine). O cache local não participa desta decisão.
  const painel = await carregarPainelSoberano(
    { organizationId: entrada.organizationId, evaluationId: id! },
    deps
  );

  if (painel.ok && painel.data) {
    return {
      ok: true,
      leitura: { origem: "POSTGRES", painel: painel.data, cacheConhecia },
    };
  }

  if (!painel.ok) {
    // `NOT_FOUND` é RESPOSTA do servidor: a avaliação não existe no tenant
    // validado (ou não é acessível — indistinguíveis por contrato, para não
    // vazar existência cross-tenant). Só nesse caso um registro local homônimo
    // pode ser lido como legado.
    if (painel.codigo === "NOT_FOUND") {
      const legado = lerLegadoLocal(id);
      return {
        ok: true,
        leitura: legado
          ? { origem: "LEGADO_LOCAL", legado, cacheConhecia }
          : null,
      };
    }

    // Qualquer outro código é INDETERMINAÇÃO (autorização não comprovada,
    // sessão, rede, configuração ausente): fail-closed, jamais legado.
    return { ok: false, erro: painel.erro ?? "Leitura recusada." };
  }

  // O servidor respondeu sem conteúdo: a avaliação não tem painel para este ator
  // (sem ocorrência vigente). Fail-closed — nunca rebaixada a legado, e o
  // registro legado homônimo não é consultado (o id é do domínio novo).
  return { ok: false, erro: "Avaliação indisponível para o seu acesso." };
}

/** Leitura para tela (nome histórico). Delega à resolução soberana. */
export async function lerAvaliacaoParaTela(
  entrada: {
    readonly organizationId: string;
    readonly evaluationId: string | undefined;
    readonly registroCutover?: ArmazenamentoCutover | null;
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoLeituraAvaliacao> {
  return resolverLeituraAvaliacao(entrada, deps);
}
