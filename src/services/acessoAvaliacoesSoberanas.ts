/**
 * F5-06 (Issue #103) — ACESSO das telas ao caminho soberano de avaliações.
 *
 * Este módulo é a ÚNICA porta pela qual páginas/componentes alcançam o domínio
 * de avaliações novo. Ele existe para que:
 *
 * - nenhuma página/componente conheça o cliente Supabase nem a Edge Function
 *   (a construção do repositório vive em `infrastructure/`);
 * - a marca de cutover usada na tela seja SEMPRE a mesma do caminho soberano;
 * - a ausência de configuração de ambiente seja FAIL-CLOSED: sem caminho novo
 *   as operações são recusadas com erro público — nunca caem para o
 *   `localStorage` (D12/§11.3).
 *
 * Não há autorização aqui: o tenant é apenas INTENÇÃO enviada à fronteira
 * confiável, que o revalida contra a membership ativa do ator. Nada neste módulo
 * concede autoridade, calcula nota oficial ou persiste em `localStorage`.
 */

import { criarRepositorioAvaliacoesProducao } from "../infrastructure/supabase/avaliacoes/repositorioProducao.ts";
import {
  avaliacaoVinculadaAoBanco,
  lerAvaliacoesCortadas,
  type ArmazenamentoCutover,
} from "../infrastructure/supabase/avaliacoes/cutover.ts";
import type { AvaliacaoSoberana } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";
import {
  criarCutoverAvaliacoes,
  type AvaliacaoNovaCriada,
  type CutoverAvaliacoes,
  type ObservacaoDoPainel,
  type NotaDoPainelPorNome,
  type ResultadoCutover,
} from "./avaliacoesSoberanas/cutoverAvaliacoesService.ts";
import type { PainelParticipante } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";

/** Operações soberanas oferecidas às telas (mesmo contrato do cutover). */
export type OperacoesAvaliacaoSoberanas = CutoverAvaliacoes;

export interface DependenciasAcessoAvaliacoes {
  /** Injeção da criação do repositório (teste). Por padrão usa o ambiente. */
  readonly criarCutover?: () => CutoverAvaliacoes | null;
  readonly armazenamento?: ArmazenamentoCutover | null;
}

/**
 * Instância resolvida uma única vez por sessão de página: a construção do
 * cliente Supabase é custosa e o caminho novo é idempotente. `undefined` =
 * ainda não resolvido; `null` = ambiente sem caminho novo (fail-closed).
 */
let operacoesMemoizadas: CutoverAvaliacoes | null | undefined;

/** Somente para testes: descarta a memoização do caminho novo. */
export function redefinirAcessoAvaliacoesSoberanas(): void {
  operacoesMemoizadas = undefined;
}

/**
 * Devolve as operações soberanas, ou `null` quando o ambiente não oferece o
 * caminho novo (fail-closed — nenhum fallback local é oferecido).
 */
export function obterOperacoesAvaliacaoSoberanas(
  deps: DependenciasAcessoAvaliacoes = {}
): OperacoesAvaliacaoSoberanas | null {
  if (deps.criarCutover) return deps.criarCutover();
  if (operacoesMemoizadas !== undefined) return operacoesMemoizadas;

  const repositorio = criarRepositorioAvaliacoesProducao();
  operacoesMemoizadas = repositorio
    ? criarCutoverAvaliacoes({
        repositorio,
        ...(deps.armazenamento ? { armazenamento: deps.armazenamento } : {}),
      })
    : null;

  return operacoesMemoizadas;
}

const ERRO_SEM_CAMINHO =
  "O caminho de avaliações no PostgreSQL não está disponível neste ambiente.";

/**
 * A avaliação é nova (existe EXCLUSIVAMENTE no PostgreSQL)? A evidência é
 * ESTRUTURAL (id técnico registrado na escrita confirmada), nunca uma data.
 */
export function avaliacaoNovaNoBanco(
  evaluationId: string,
  armazenamento?: ArmazenamentoCutover | null
): boolean {
  return avaliacaoVinculadaAoBanco(evaluationId, armazenamento ?? null);
}

/** Ids das avaliações já confirmadas exclusivamente no PostgreSQL. */
export function idsDeAvaliacoesNovas(
  armazenamento?: ArmazenamentoCutover | null
): ReadonlySet<string> {
  return lerAvaliacoesCortadas(armazenamento ?? null);
}

/**
 * Cria uma avaliação NOVA no PostgreSQL. Sem caminho configurado ⇒ recusa
 * explícita (sem escrita local, sem fallback).
 */
export async function criarAvaliacaoSoberana(
  entrada: {
    readonly organizationId: string;
    readonly ano: number;
    readonly ciclo: number;
    readonly matriculaAvaliado: number;
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCutover<AvaliacaoNovaCriada>> {
  const operacoes = obterOperacoesAvaliacaoSoberanas(deps);
  if (!operacoes) return { ok: false, erro: ERRO_SEM_CAMINHO };
  return operacoes.criarNova(entrada);
}

/** Painel de EDIÇÃO da própria ocorrência do ator autenticado. */
export async function carregarPainelSoberano(
  entrada: { readonly organizationId: string; readonly evaluationId: string },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCutover<PainelParticipante>> {
  const operacoes = obterOperacoesAvaliacaoSoberanas(deps);
  if (!operacoes) return { ok: false, erro: ERRO_SEM_CAMINHO };
  return operacoes.carregarPainel(entrada);
}

/** Notas da própria ocorrência, por NOME de subcritério do catálogo congelado. */
export async function gravarNotasSoberanas(
  entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly painel: PainelParticipante;
    readonly notas: readonly NotaDoPainelPorNome[];
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCutover<number | null>> {
  const operacoes = obterOperacoesAvaliacaoSoberanas(deps);
  if (!operacoes) return { ok: false, erro: ERRO_SEM_CAMINHO };
  return operacoes.gravarNotasDoPainel(entrada);
}

/** Observações de critério da própria ocorrência. */
export async function gravarObservacoesSoberanas(
  entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly painel: PainelParticipante;
    readonly observacoes: readonly ObservacaoDoPainel[];
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCutover<number>> {
  const operacoes = obterOperacoesAvaliacaoSoberanas(deps);
  if (!operacoes) return { ok: false, erro: ERRO_SEM_CAMINHO };
  return operacoes.gravarObservacoesDoPainel(entrada);
}

/** Comentário final da própria ocorrência. */
export async function gravarComentarioFinalSoberano(
  entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly painel: PainelParticipante;
    readonly texto: string;
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCutover<null>> {
  const operacoes = obterOperacoesAvaliacaoSoberanas(deps);
  if (!operacoes) return { ok: false, erro: ERRO_SEM_CAMINHO };
  return operacoes.gravarComentarioFinalDoPainel(entrada);
}

/** Status REAL da avaliação no banco (nunca projeção do legado). */
export async function lerStatusSoberano(
  entrada: { readonly organizationId: string; readonly evaluationId: string },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCutover<AvaliacaoSoberana | null>> {
  const operacoes = obterOperacoesAvaliacaoSoberanas(deps);
  if (!operacoes) return { ok: false, erro: ERRO_SEM_CAMINHO };
  return operacoes.lerStatus(entrada);
}

/** Conclusão: completude e cálculo são oficiais no SQL (D13/D18). */
export async function concluirAvaliacaoSoberana(
  entrada: { readonly organizationId: string; readonly evaluationId: string },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCutover<null>> {
  const operacoes = obterOperacoesAvaliacaoSoberanas(deps);
  if (!operacoes) return { ok: false, erro: ERRO_SEM_CAMINHO };
  return operacoes.concluir(entrada);
}

/** Cancelamento soberano com motivo (auditado server-side). */
export async function cancelarAvaliacaoSoberana(
  entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly motivo: string;
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCutover<null>> {
  const operacoes = obterOperacoesAvaliacaoSoberanas(deps);
  if (!operacoes) return { ok: false, erro: ERRO_SEM_CAMINHO };
  return operacoes.cancelar(entrada);
}

/** Reabertura soberana com motivo (auditada server-side). */
export async function reabrirAvaliacaoSoberana(
  entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly motivo: string;
  },
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCutover<null>> {
  const operacoes = obterOperacoesAvaliacaoSoberanas(deps);
  if (!operacoes) return { ok: false, erro: ERRO_SEM_CAMINHO };
  return operacoes.reabrir(entrada);
}
