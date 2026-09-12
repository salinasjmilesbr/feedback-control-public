/**
 * F5-09 P5 — PORTA de LEITURA soberana de ciclos (UUID-first, ASSÍNCRONA).
 *
 * ## Por que o contrato mudou
 *
 * O contrato anterior era SÍNCRONO e local (`getCiclosAvaliacao`/`getCicloAtivo`/
 * `criarCiclo`): uma abstração do `localStorage` que a auditoria read-only P5–P9
 * (`docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md` §2/§4) classificou como
 * autoridade LOCAL — resíduo a remover no cutover (P8), nunca contrato produtivo
 * final. A leitura soberana (§13.5) é
 * `navegador → PostgREST → RLS own-tenant → linhas do tenant`, logo o contrato
 * produtivo é:
 *
 * - **assíncrono**: toda operação devolve `Promise<ResultadoCiclos<T>>`;
 * - **UUID-first**: a identidade canônica é `evaluation_cycles.id`. `ano`/`numero`
 *   são RÓTULOS do domínio — NUNCA identidade, autorização ou chave de leitura;
 *   a bridge `(ano, numero)` do legado permanece apenas como INTENÇÃO para os
 *   consumidores ainda não migrados (P8);
 * - **fail-closed**: erro/indisponibilidade NUNCA resulta em fallback local,
 *   dual-read ou dado inventado. A ausência é explícita (`null`) e a falha tem
 *   código público;
 * - **sem mutação**: criar/editar/ativar/encerrar/cancelar/reabrir/corrigir são
 *   operações soberanas das RPCs (P2–P4), executadas pela fronteira autorizada
 *   (Edge `ciclos`, P7). Esta porta é estritamente de LEITURA (P5).
 */

import type { CodigoPublico } from "../../infrastructure/supabase/colaboradores/contrato";
import type { StatusCicloAvaliacao } from "../../types/CicloAvaliacao";

/** Número do ciclo no ano (domínio fechado — CHECK da F5-06). */
export type NumeroCiclo = 1 | 2 | 3;

/** Projeção soberana de `evaluation_cycles` (identidade = `id`). */
export interface CicloSoberano {
  readonly id: string;
  readonly organizationId: string;
  readonly ano: number;
  readonly numero: NumeroCiclo;
  readonly status: StatusCicloAvaliacao;
  readonly dataInicio: string | null;
  readonly dataFim: string | null;
  readonly dataAtivacao: string | null;
  readonly dataEncerramento: string | null;
  readonly encerradoComPendencias: boolean;
  readonly quantidadePendencias: number;
  /** Versão otimista da linha (base de `expected_version` das mutações do P7). */
  readonly version: number;
  readonly criadoEm: string;
  readonly atualizadoEm: string;
}

/** Erro público: código estável + mensagem sem detalhe do banco. */
export interface ErroCiclosSoberanos {
  readonly code: CodigoPublico;
  readonly message: string;
}

/** Resultado da porta: sucesso com dados ou falha com código público. */
export type ResultadoCiclos<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: ErroCiclosSoberanos };

/**
 * Porta única de LEITURA de ciclos. Sem estado, sem cache e sem autorização:
 * a organização é INTENÇÃO de UX e a RLS (P5) é quem isola o tenant.
 */
export interface CycleRepository {
  /** Ciclos da organização ativa (ordem determinística do adaptador). */
  listarCiclos(organizationId: string): Promise<ResultadoCiclos<readonly CicloSoberano[]>>;
  /** Ciclo pelo UUID canônico; `null` = ausente (ou de outro tenant). */
  obterCiclo(
    organizationId: string,
    cycleId: string
  ): Promise<ResultadoCiclos<CicloSoberano | null>>;
  /** Ciclo ATIVO da organização (no máximo um — I5/D14); `null` = nenhum. */
  obterCicloAtivo(organizationId: string): Promise<ResultadoCiclos<CicloSoberano | null>>;
}
