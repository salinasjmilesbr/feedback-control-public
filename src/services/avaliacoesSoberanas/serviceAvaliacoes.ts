/**
 * F5-06 (Issue #103) — CASOS DE USO do caminho novo de avaliações.
 *
 * Camada entre a UI (hooks/páginas) e o repositório:
 *
 *   UI/hook → SERVICE (este módulo) → REPOSITÓRIO → Edge Function → Policy Engine → RPC
 *
 * Responsabilidades e limites:
 * - o service NÃO decide autorização (quem decide é o Policy Engine, server-side);
 * - o service NÃO calcula a nota oficial (o agregado vem materializado do banco);
 * - o service NÃO escreve em `localStorage` (sem dual-write, D12/§11);
 * - o service marca o CUTOVER quando a avaliação passa a existir exclusivamente
 *   no PostgreSQL: a partir daí o legado não é mais autoridade para ela.
 *
 * Todas as dependências são injetadas (repositório + armazenamento da marca),
 * o que mantém o módulo testável sem DOM e sem rede.
 */

import type {
  AvaliacaoSoberana,
  EntradaCriarAvaliacao,
  EntradaGravarComentario,
  EntradaGravarNotas,
  ErroRepositorioAvaliacoes,
  RepositorioAvaliacoes,
  ResultadoRepositorio,
  TransparenciaAvaliado,
} from "../../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";
import {
  avaliacaoVinculadaAoBanco,
  separarAcervoLegado,
  registrarAvaliacaoCortada,
  type ArmazenamentoCutover,
} from "../../infrastructure/supabase/avaliacoes/cutover.ts";
import { ehUuid } from "../../infrastructure/supabase/avaliacoes/contrato.ts";

/** Registro legado exposto SOMENTE para leitura (nunca autoridade). */
export interface AvaliacaoLegado<Registro = unknown> {
  readonly origem: "LEGADO_LOCAL";
  /** Sem edição: o caminho novo é o único que escreve (D12). */
  readonly editavel: false;
  readonly motivo: string;
  readonly registro: Registro;
}

/** Avaliação do caminho novo (PostgreSQL). */
export interface AvaliacaoPostgres {
  readonly origem: "POSTGRES";
  readonly editavel: boolean;
  readonly avaliacao: AvaliacaoSoberana;
}

export interface DadosAcervoAvaliacoes<Registro = unknown> {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly avaliacoes: readonly AvaliacaoPostgres[];
  readonly legado: readonly AvaliacaoLegado<Registro>[];
  /** Orientação de UI: o acervo legado não pode ser editado por este caminho. */
  readonly avisoLegado: string | null;
}

const AVISO_LEGADO =
  "Avaliações criadas antes do cutover permanecem em modo legado (somente leitura).";

export interface DependenciasServiceAvaliacoes<Registro = unknown> {
  readonly repositorio: RepositorioAvaliacoes;
  /** Fonte do acervo legado (localStorage/injeção) — somente leitura. */
  readonly lerRegistrosLegados: () => readonly Registro[];
  /** Armazenamento da marca de cutover (injetável para teste). */
  readonly armazenamento?: ArmazenamentoCutover | null;
}

export interface ResultadoCriacaoAvaliacao {
  readonly evaluationId: string;
  /** A avaliação passou a existir exclusivamente no PostgreSQL (D12). */
  readonly cutoverRegistrado: boolean;
}

export interface ServiceAvaliacoes<Registro = unknown> {
  /** Cria avaliação NOVA: escreve apenas no PostgreSQL e marca o cutover. */
  criar(
    entrada: EntradaCriarAvaliacao
  ): Promise<ResultadoRepositorio<ResultadoCriacaoAvaliacao>>;
  /** Acervo do ciclo: avaliações do banco + legado (somente leitura). */
  listarAcervo(entrada: {
    readonly organizationId: string;
    readonly cycleId: string;
    readonly evaluationIds: readonly string[];
    readonly ehEditavel: (avaliacao: AvaliacaoSoberana) => boolean;
  }): Promise<ResultadoRepositorio<DadosAcervoAvaliacoes<Registro>>>;
  ler(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<ResultadoRepositorio<AvaliacaoSoberana | null>>;
  gravarNotas(entrada: EntradaGravarNotas): Promise<ResultadoRepositorio<number | null>>;
  gravarComentario(entrada: EntradaGravarComentario): Promise<ResultadoRepositorio<null>>;
  concluir(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<ResultadoRepositorio<null>>;
  reabrir(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly motivo: string;
  }): Promise<ResultadoRepositorio<null>>;
  cancelar(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly motivo: string;
  }): Promise<ResultadoRepositorio<null>>;
  transparencia(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<ResultadoRepositorio<TransparenciaAvaliado>>;
}

export function criarServiceAvaliacoes<Registro = unknown>(
  deps: DependenciasServiceAvaliacoes<Registro>
): ServiceAvaliacoes<Registro> {
  const armazenamento = deps.armazenamento ?? null;

  return {
    async criar(entrada) {
      const resultado = await deps.repositorio.criar(entrada);
      if (!resultado.ok) return resultado;

      const evaluationId = resultado.data;
      // A partir da primeira escrita exclusiva no banco, o legado não é mais
      // autoridade para ESTA avaliação (D12/§11.3 — sem dual-write reverso).
      const cutoverRegistrado = ehUuid(evaluationId);
      if (cutoverRegistrado) registrarAvaliacaoCortada(evaluationId, armazenamento);

      return { ok: true, data: { evaluationId, cutoverRegistrado } };
    },

    async listarAcervo(entrada) {
      const avaliacoes: AvaliacaoPostgres[] = [];
      for (const evaluationId of entrada.evaluationIds) {
        const resultado = await deps.repositorio.ler({
          organizationId: entrada.organizationId,
          evaluationId,
        });
        if (!resultado.ok) return resultado;
        const avaliacao = resultado.data;
        if (!avaliacao) continue;
        // Somente o ciclo/organização pedidos entram no acervo.
        if (avaliacao.cycleId !== entrada.cycleId) continue;
        if (avaliacao.organizationId !== entrada.organizationId) continue;
        avaliacoes.push({
          origem: "POSTGRES",
          editavel: entrada.ehEditavel(avaliacao),
          avaliacao,
        });
      }

      // O acervo legado é separado por EVIDÊNCIA ESTRUTURAL (marcador do caminho
      // novo), nunca por data: registro sem marca explícita é legado local e
      // permanece somente leitura.
      const { legado } = separarAcervoLegado(deps.lerRegistrosLegados(), (registro) => {
        const id = (registro as { evaluationId?: string | null }).evaluationId;
        return avaliacaoVinculadaAoBanco(id ?? "", armazenamento)
          ? { origem: "POSTGRES" as const, evaluationId: String(id) }
          : { origem: "LEGADO_LOCAL" as const, evaluationId: id ?? null };
      });

      return {
        ok: true,
        data: {
          organizationId: entrada.organizationId,
          cycleId: entrada.cycleId,
          avaliacoes,
          legado: legado.map((registro) => ({
            origem: "LEGADO_LOCAL" as const,
            editavel: false as const,
            motivo: AVISO_LEGADO,
            registro: registro as Registro,
          })),
          avisoLegado: legado.length > 0 ? AVISO_LEGADO : null,
        },
      };
    },

    ler: (entrada) => deps.repositorio.ler(entrada),

    gravarNotas: (entrada) => deps.repositorio.gravarNotas(entrada),

    gravarComentario: (entrada) => deps.repositorio.gravarComentario(entrada),

    concluir: ({ organizationId, evaluationId }) =>
      deps.repositorio.concluir({ organizationId, evaluationId }),

    reabrir: (entrada) => deps.repositorio.reabrir(entrada),

    cancelar: (entrada) => deps.repositorio.cancelar(entrada),

    transparencia: (entrada) => deps.repositorio.transparenciaDoAvaliado(entrada),
  };
}

/** Erro público único para a UI (nunca expõe a razão interna da negação). */
export function mensagemErroAvaliacoes(erro: ErroRepositorioAvaliacoes): string {
  switch (erro.code) {
    case "FORBIDDEN":
      return "Você não tem permissão para esta operação nesta avaliação.";
    case "NOT_FOUND":
      return "Avaliação não encontrada.";
    case "CONFLICT":
      return erro.message;
    case "INVALID_INPUT":
      return erro.message;
    case "NOT_AUTHORIZED":
      return "Sessão inválida. Entre novamente.";
    default:
      return "Não foi possível concluir a operação de avaliação.";
  }
}
