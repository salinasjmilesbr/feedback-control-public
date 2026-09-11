/**
 * F5-07 — CASOS DE USO do caminho soberano de colaboradores.
 *
 * Camada entre a porta única das telas e o repositório:
 *
 *   página → PORTA (`acessoColaboradoresSoberanos`) → SERVICE (este módulo)
 *          → REPOSITÓRIO → Edge `colaboradores` → gate → RPC PostgreSQL
 *
 * Responsabilidades e limites:
 * - resolve a ORGANIZAÇÃO ATIVA como INTENÇÃO de UX (nunca autoridade: a Edge a
 *   revalida contra a membership ativa do ator);
 * - NÃO decide autorização (quem decide é o Policy Engine / plano administrativo,
 *   server-side);
 * - NÃO escreve em `localStorage` (sem dual-write) e NÃO mantém cache de decisão
 *   entre chamadas;
 * - normaliza o resultado e o erro público; sem organização ativa ⇒ recusa
 *   explícita (fail-closed), jamais fallback.
 *
 * Todas as dependências são injetadas (repositório + resolvedor da organização),
 * o que mantém o módulo testável sem DOM e sem rede.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { criarClienteSupabase } from "../../infrastructure/supabase/supabaseClient";
import {
  criarRepositorioColaboradoresSupabase,
  type ColaboradorSoberano,
  type EntradaAlterarStatus,
  type EntradaBootstrapCatalogo,
  type EntradaCriarColaborador,
  type EntradaDefinirIdentificador,
  type EntradaDefinirOcupacao,
  type EntradaDefinirReportingLine,
  type EntradaDefinirResponsabilidade,
  type EntradaEditarColaborador,
  type EntradaEncerrarOcupacao,
  type EntradaEncerrarReportingLine,
  type EntradaEncerrarResponsabilidade,
  type EntradaListarColaboradores,
  type EntradaObterColaborador,
  type EntradaRegistrarSucessao,
  type ErroRepositorioColaboradores,
  type EventoColaborador,
  type RepositorioColaboradores,
} from "../../infrastructure/supabase/colaboradores/repositorioColaboradores";
import type { CodigoPublico } from "../../infrastructure/supabase/colaboradores/contrato";

/** Resultado da porta única: sucesso com dados ou falha com código público. */
export type ResultadoColaboradores<T> =
  | { readonly ok: true; readonly dados: T }
  | { readonly ok: false; readonly codigo: CodigoPublico; readonly mensagem: string };

/** Projeção soberana do colaborador (espinha §3). */
export type ColaboradorSoberanoProjetado = ColaboradorSoberano;
/** Evento da linha do tempo append-only (§12). */
export type EventoColaboradorProjetado = EventoColaborador;

export interface DependenciasServiceColaboradores {
  /** Organização ATIVA do contexto de UX (intenção). Injetável para teste. */
  readonly organizacaoAtivaId?: () => string | null | undefined;
  /** Repositório do caminho soberano (injetável para teste). */
  readonly repositorio?: RepositorioColaboradores;
  /** Cliente Supabase já construído (injetável para teste). */
  readonly cliente?: SupabaseClient | null;
}

/**
 * Mensagem pública por código (F0-05). A mensagem do servidor só é aproveitada
 * em `INVALID_INPUT`/`CONFLICT`, que descrevem a INTENÇÃO do próprio usuário;
 * negação e inexistência permanecem genéricas e indistinguíveis.
 */
export function mensagemColaboradores(erro: ErroRepositorioColaboradores): string {
  switch (erro.code) {
    case "FORBIDDEN":
      return "Você não tem permissão para esta operação.";
    case "NOT_FOUND":
      return "Colaborador não encontrado.";
    case "CONFLICT":
      return erro.message;
    case "INVALID_INPUT":
      return erro.message;
    case "NOT_AUTHORIZED":
      return "Sessão inválida. Entre novamente.";
    case "METHOD_NOT_ALLOWED":
      return "Operação indisponível neste ambiente.";
    default:
      return "Não foi possível concluir a operação.";
  }
}

export interface ServiceColaboradores {
  listar(
    entrada: EntradaListarColaboradores
  ): Promise<ResultadoColaboradores<readonly ColaboradorSoberanoProjetado[]>>;
  obter(
    entrada: EntradaObterColaborador
  ): Promise<ResultadoColaboradores<ColaboradorSoberanoProjetado>>;
  criar(entrada: EntradaCriarColaborador): Promise<ResultadoColaboradores<string>>;
  editar(entrada: EntradaEditarColaborador): Promise<ResultadoColaboradores<number>>;
  definirIdentificador(
    entrada: EntradaDefinirIdentificador
  ): Promise<ResultadoColaboradores<number>>;
  alterarStatus(entrada: EntradaAlterarStatus): Promise<ResultadoColaboradores<number>>;
  definirOcupacao(
    entrada: EntradaDefinirOcupacao
  ): Promise<ResultadoColaboradores<string>>;
  encerrarOcupacao(
    entrada: EntradaEncerrarOcupacao
  ): Promise<ResultadoColaboradores<null>>;
  definirReportingLine(
    entrada: EntradaDefinirReportingLine
  ): Promise<ResultadoColaboradores<string>>;
  encerrarReportingLine(
    entrada: EntradaEncerrarReportingLine
  ): Promise<ResultadoColaboradores<null>>;
  definirResponsabilidade(
    entrada: EntradaDefinirResponsabilidade
  ): Promise<ResultadoColaboradores<string>>;
  encerrarResponsabilidade(
    entrada: EntradaEncerrarResponsabilidade
  ): Promise<ResultadoColaboradores<null>>;
  registrarSucessao(entrada: EntradaRegistrarSucessao): Promise<ResultadoColaboradores<null>>;
  obterHistorico(entrada: {
    readonly organizationId?: string | null;
    readonly collaboratorId: string;
    readonly dataReferencia?: string;
    readonly referenceCycleId?: string;
  }): Promise<ResultadoColaboradores<readonly EventoColaboradorProjetado[]>>;
  bootstrapCatalogo(entrada: EntradaBootstrapCatalogo): Promise<ResultadoColaboradores<null>>;
}

const ERRO_SEM_ORGANIZACAO = "Selecione uma organização ativa para operar colaboradores.";
const ERRO_SEM_CAMINHO =
  "O caminho de colaboradores no PostgreSQL não está disponível neste ambiente.";

function falha<T>(erro: ErroRepositorioColaboradores): ResultadoColaboradores<T> {
  return { ok: false, codigo: erro.code, mensagem: mensagemColaboradores(erro) };
}

function falhaSimples<T>(codigo: CodigoPublico, mensagem: string): ResultadoColaboradores<T> {
  return { ok: false, codigo, mensagem };
}

/** Constrói o repositório de produção; `null` sem configuração (fail-closed). */
export function criarRepositorioColaboradoresProducao(
  cliente?: SupabaseClient | null
): RepositorioColaboradores | null {
  const resolvido = cliente ?? criarClienteSupabase();
  if (!resolvido) return null;
  return criarRepositorioColaboradoresSupabase(resolvido);
}

export function criarServiceColaboradores(
  deps: DependenciasServiceColaboradores = {}
): ServiceColaboradores {
  let memoizado: RepositorioColaboradores | null | undefined;

  function repositorio(): RepositorioColaboradores | null {
    if (deps.repositorio) return deps.repositorio;
    if (memoizado !== undefined) return memoizado;
    memoizado = criarRepositorioColaboradoresProducao(deps.cliente ?? null);
    return memoizado;
  }

  /**
   * Organização alvo: a informada pela tela (intenção) ou a ATIVA do contexto
   * de UX. Sem uma delas a operação é recusada — nada cai para autoridade local.
   */
  function organizacaoAlvo(informada?: string | null): string | null {
    if (typeof informada === "string" && informada.length > 0) return informada;
    const ativa = deps.organizacaoAtivaId?.();
    return typeof ativa === "string" && ativa.length > 0 ? ativa : null;
  }

  interface Contexto {
    readonly organização: string;
    readonly repo: RepositorioColaboradores;
  }

  /** Resolve as dependências comuns (fail-closed sem organização ou caminho). */
  async function comContexto<T>(
    informada: string | null | undefined,
    executar: (contexto: Contexto) => Promise<ResultadoColaboradores<T>>
  ): Promise<ResultadoColaboradores<T>> {
    const organização = organizacaoAlvo(informada);
    if (!organização) return falhaSimples("FORBIDDEN", ERRO_SEM_ORGANIZACAO);

    const repo = repositorio();
    if (!repo) return falhaSimples("INTERNAL", ERRO_SEM_CAMINHO);

    return executar({ organização, repo });
  }

  async function propagar<T>(
    resultado: Promise<
      | { readonly ok: true; readonly data: T }
      | { readonly ok: false; readonly error: ErroRepositorioColaboradores }
    >
  ): Promise<ResultadoColaboradores<T>> {
    const resolvido = await resultado;
    if (!resolvido.ok) return falha(resolvido.error);
    return { ok: true, dados: resolvido.data };
  }

  return {
    listar: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(
          repo.listar({
            organizationId: organização,
            ...(entrada.dataReferencia ? { dataReferencia: entrada.dataReferencia } : {}),
            ...(entrada.status ? { status: entrada.status } : {}),
            ...(entrada.unitId ? { unitId: entrada.unitId } : {}),
            ...(entrada.busca ? { busca: entrada.busca } : {}),
          })
        )
      ),

    obter: (entrada) =>
      comContexto(entrada.organizationId, async ({ organização, repo }) => {
        const resultado = await propagar(
          repo.obter({
            organizationId: organização,
            ...(entrada.collaboratorId ? { collaboratorId: entrada.collaboratorId } : {}),
            ...(entrada.matricula ? { matricula: entrada.matricula } : {}),
            ...(entrada.dataReferencia ? { dataReferencia: entrada.dataReferencia } : {}),
          })
        );
        // A porta expõe a PROJEÇÃO; o payload cru permanece no repositório.
        return resultado.ok ? { ok: true, dados: resultado.dados.colaborador } : resultado;
      }),

    criar: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.criar({ ...entrada, organizationId: organização }))
      ),

    editar: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.editar({ ...entrada, organizationId: organização }))
      ),

    definirIdentificador: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.definirIdentificador({ ...entrada, organizationId: organização }))
      ),

    alterarStatus: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.alterarStatus({ ...entrada, organizationId: organização }))
      ),

    definirOcupacao: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.definirOcupacao({ ...entrada, organizationId: organização }))
      ),

    encerrarOcupacao: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.encerrarOcupacao({ ...entrada, organizationId: organização }))
      ),

    definirReportingLine: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.definirReportingLine({ ...entrada, organizationId: organização }))
      ),

    encerrarReportingLine: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.encerrarReportingLine({ ...entrada, organizationId: organização }))
      ),

    definirResponsabilidade: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.definirResponsabilidade({ ...entrada, organizationId: organização }))
      ),

    encerrarResponsabilidade: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.encerrarResponsabilidade({ ...entrada, organizationId: organização }))
      ),

    registrarSucessao: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.registrarSucessao({ ...entrada, organizationId: organização }))
      ),

    obterHistorico: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(
          repo.obterHistorico({
            organizationId: organização,
            collaboratorId: entrada.collaboratorId,
            ...(entrada.dataReferencia ? { dataReferencia: entrada.dataReferencia } : {}),
            ...(entrada.referenceCycleId ? { referenceCycleId: entrada.referenceCycleId } : {}),
          })
        )
      ),

    bootstrapCatalogo: (entrada) =>
      comContexto(entrada.organizationId, ({ organização, repo }) =>
        propagar(repo.bootstrapCatalogo({ ...entrada, organizationId: organização }))
      ),
  };
}
