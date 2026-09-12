/**
 * F5-09 P5 — PORTA ÚNICA de LEITURA soberana de ciclos (+ cache de UX).
 *
 * Nenhuma página/componente precisa importar o cliente Supabase nem o
 * `cicloAvaliacaoStorage` para ler ciclo: a composição vive aqui e em
 * `infrastructure/` (§13.5). Este módulo existe para que:
 *
 * - a **organização ativa** seja tratada como INTENÇÃO de UX (a fronteira
 *   confiável a revalida: a RLS own-tenant do P5 é quem isola o tenant);
 * - a ausência de configuração de ambiente seja **FAIL-CLOSED**: sem caminho
 *   soberano a leitura é recusada com código público — nunca cai para
 *   `localStorage` (sem dual-read, sem fallback silencioso);
 * - a negação nunca seja exceção: toda operação devolve `ResultadoCiclos`, com o
 *   código público quando falha;
 * - a **resposta assíncrona atrasada nunca vença o contexto mais recente**:
 *   o cache publica por GERAÇÃO MONOTÔNICA e só aceita o resultado se ele ainda
 *   for o da organização/versão corrente (troca rápida de organização, unmount e
 *   logout descartam respostas em voo — mesma doutrina do
 *   `estruturaSoberanaCliente.ts`, F5-08 §2.3).
 *
 * Não há autorização aqui: identidade por UUID (`evaluation_cycles.id`),
 * `organization_id` apenas como intenção e ano/numero somente como RÓTULOS
 * (jamais identidade, autorização ou chave de leitura). Nada neste módulo
 * persiste localmente nem decide tenant.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";
import { criarRepositorioCiclosSoberanos } from "../infrastructure/supabase/ciclos/repositorioCiclosSoberanos";
import type {
  CicloSoberano,
  CycleRepository,
  ResultadoCiclos,
} from "../application/ports/CycleRepository";

export type { CicloSoberano, CycleRepository, ResultadoCiclos };

export interface DependenciasAcessoCiclos {
  /** Injeção do repositório (teste). Por padrão usa o caminho de produção. */
  readonly repositorio?: CycleRepository;
  /** Cliente Supabase explícito (teste); `null` força "sem caminho soberano". */
  readonly cliente?: SupabaseClient | null;
}

const ERRO_SEM_CAMINHO =
  "Leitura soberana de ciclos indisponível neste ambiente.";
const ERRO_SEM_ORGANIZACAO = "Organização ativa ausente.";

/**
 * Instância resolvida uma única vez por sessão de página. `undefined` = ainda não
 * resolvido; `null` = ambiente sem caminho soberano (fail-closed).
 */
let repositorioMemoizado: CycleRepository | null | undefined;

/** Somente para testes: descarta a memoização do caminho soberano. */
export function redefinirAcessoCiclosSoberanos(): void {
  repositorioMemoizado = undefined;
}

/**
 * Devolve o repositório soberano, ou `null` quando o ambiente não oferece o
 * caminho novo (fail-closed — nenhum fallback local é oferecido).
 */
export function obterRepositorioCiclosSoberanos(
  deps: DependenciasAcessoCiclos = {}
): CycleRepository | null {
  if (deps.repositorio) return deps.repositorio;
  if (repositorioMemoizado !== undefined) return repositorioMemoizado;

  const cliente = deps.cliente !== undefined ? deps.cliente : criarClienteSupabase();
  repositorioMemoizado = cliente ? criarRepositorioCiclosSoberanos(cliente) : null;
  return repositorioMemoizado;
}

// ---------------------------------------------------------------------------
// Cache de UX publicada (geração monotônica) — nunca é autoridade
// ---------------------------------------------------------------------------

export type FaseCiclosSoberanos = "ocioso" | "carregando" | "pronta" | "indisponivel";

export interface EstadoCiclosSoberanos {
  readonly fase: FaseCiclosSoberanos;
  readonly organizacaoId: string | null;
  readonly ciclos: readonly CicloSoberano[];
  /** Código público quando indisponível (nunca detalhe do banco). */
  readonly codigo?: CodigoPublico;
  readonly mensagem?: string;
}

export const CICLOS_SOBERANOS_OCIOSOS: EstadoCiclosSoberanos = {
  fase: "ocioso",
  organizacaoId: null,
  ciclos: [],
};

export interface ControladorCiclosSoberanos {
  /** Estado publicado (cache de UX; nunca fonte de verdade). */
  estado(): EstadoCiclosSoberanos;
  /** Carrega a lista e publica o estado (descarta resposta obsoleta). */
  carregar(organizationId: string): Promise<ResultadoCiclos<readonly CicloSoberano[]>>;
  /** Ciclo por UUID (não altera a cache publicada). */
  obterCiclo(
    organizationId: string,
    cycleId: string
  ): Promise<ResultadoCiclos<CicloSoberano | null>>;
  /** Ciclo ATIVO (não altera a cache publicada). */
  obterCicloAtivo(organizationId: string): Promise<ResultadoCiclos<CicloSoberano | null>>;
  /** Descarta respostas em voo e volta a "ocioso" (troca de organização). */
  invalidar(): void;
  /** Descarta respostas em voo e limpa o estado (unmount/logout). */
  descartar(): void;
}

function falha<T>(codigo: CodigoPublico, mensagem: string): ResultadoCiclos<T> {
  return { ok: false, error: { code: codigo, message: mensagem } };
}

export function criarControladorCiclosSoberanos(
  deps: DependenciasAcessoCiclos = {}
): ControladorCiclosSoberanos {
  let geracao = 0;
  let estado: EstadoCiclosSoberanos = CICLOS_SOBERANOS_OCIOSOS;

  function publicar(novo: EstadoCiclosSoberanos): void {
    estado = novo;
  }

  /** `null` = sem caminho soberano (fail-closed, nunca fallback local). */
  function repositorio(): CycleRepository | null {
    return obterRepositorioCiclosSoberanos(deps);
  }

  return {
    estado: () => estado,

    async carregar(organizationId) {
      const minhaGeracao = ++geracao;

      if (typeof organizationId !== "string" || organizationId.length === 0) {
        publicar({
          fase: "indisponivel",
          organizacaoId: null,
          ciclos: [],
          codigo: "FORBIDDEN",
          mensagem: ERRO_SEM_ORGANIZACAO,
        });
        return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      }

      // Troca de organização limpa a lista imediatamente (nenhum dado do tenant
      // anterior permanece visível enquanto a nova leitura não conclui).
      publicar({
        fase: "carregando",
        organizacaoId: organizationId,
        ciclos: estado.organizacaoId === organizationId ? estado.ciclos : [],
      });

      const fonte = repositorio();
      if (!fonte) {
        if (minhaGeracao === geracao) {
          publicar({
            fase: "indisponivel",
            organizacaoId: organizationId,
            ciclos: [],
            codigo: "INTERNAL",
            mensagem: ERRO_SEM_CAMINHO,
          });
        }
        return falha("INTERNAL", ERRO_SEM_CAMINHO);
      }

      const resultado = await fonte.listarCiclos(organizationId);

      // Resposta ATRASADA de uma organização/versão anterior NUNCA publica.
      if (minhaGeracao !== geracao) return resultado;

      if (resultado.ok) {
        publicar({ fase: "pronta", organizacaoId: organizationId, ciclos: resultado.data });
      } else {
        // Erro de backend é INDISPONIBILIDADE — jamais dado local como resposta.
        publicar({
          fase: "indisponivel",
          organizacaoId: organizationId,
          ciclos: [],
          codigo: resultado.error.code,
          mensagem: resultado.error.message,
        });
      }
      return resultado;
    },

    async obterCiclo(organizationId, cycleId) {
      const fonte = repositorio();
      if (!fonte) return falha("INTERNAL", ERRO_SEM_CAMINHO);
      return fonte.obterCiclo(organizationId, cycleId);
    },

    async obterCicloAtivo(organizationId) {
      const fonte = repositorio();
      if (!fonte) return falha("INTERNAL", ERRO_SEM_CAMINHO);
      return fonte.obterCicloAtivo(organizationId);
    },

    invalidar() {
      geracao += 1;
      publicar(CICLOS_SOBERANOS_OCIOSOS);
    },

    descartar() {
      geracao += 1;
      publicar(CICLOS_SOBERANOS_OCIOSOS);
    },
  };
}
