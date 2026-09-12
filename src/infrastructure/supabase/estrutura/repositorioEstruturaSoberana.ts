/**
 * F5-08 P4 — LEITURA SOBERANA da estrutura organizacional e dos catálogos.
 *
 * Caminho DECIDIDO pelo desenho técnico (D16 / §13.1 / §12.1):
 *
 *   navegador → PostgREST (`select`) → RLS F4-08 own-tenant → linhas do tenant
 *
 * - NÃO existe RPC de listagem administrativa e a F5-08 **não** cria uma
 *   (§21.3): as tabelas de estrutura/catálogo já têm policy
 *   `*_select_same_tenant` + `grant select` a `authenticated` (F4-08). A leitura
 *   NÃO exige capability — qualquer membro ativo lê a estrutura da PRÓPRIA
 *   organização; a escrita continua bloqueada (sem policy de DML) e ocorre
 *   somente pelas RPCs, via Edge.
 * - A sessão do usuário é OBRIGATÓRIA: sem JWT o PostgREST responde como `anon`
 *   e a RLS devolve conjunto vazio — uma negação SILENCIOSA que a UI exibiria
 *   como "sem estrutura cadastrada". Por isso toda leitura verifica a sessão
 *   ANTES da consulta e recusa com `NOT_AUTHORIZED` quando ela não existe
 *   (fail-closed, nunca vazio por negação).
 * - NENHUMA regra de autorização, de tenant ou de ciclo é decidida aqui: o
 *   `organization_id` é INTENÇÃO de UX; a RLS é quem isola o tenant. Nenhum
 *   dado é inventado, normalizado ou semeado (I7) e nada é escrito
 *   (`localStorage` não participa deste caminho).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { CodigoPublico } from "../colaboradores/contrato.ts";

export interface ErroLeituraEstrutura {
  readonly code: CodigoPublico;
  readonly message: string;
}

export type ResultadoLeituraEstrutura<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: ErroLeituraEstrutura };

/** Unidade formal (rótulo + vigência; o UUID é a identidade). */
export interface UnidadeSoberana {
  readonly unitId: string;
  readonly nome: string;
  readonly validFrom: string;
  readonly validTo: string | null;
  readonly version: number;
}

/** Período pai/filho entre unidades (`parentUnitId: null` = raiz no período). */
export interface PeriodoParentSoberano {
  readonly periodoId: string;
  readonly unitId: string;
  readonly parentUnitId: string | null;
  readonly validFrom: string;
  readonly validTo: string | null;
  readonly version: number;
}

/** Posição formal (unidade + cargo + senioridade opcional). */
export interface PosicaoSoberana {
  readonly posicaoId: string;
  readonly unitId: string;
  readonly jobRoleId: string;
  readonly seniorityLevelId: string | null;
  readonly validFrom: string;
  readonly validTo: string | null;
  readonly version: number;
}

/** Reporting line formal entre posições. */
export interface ReportingLineSoberana {
  readonly reportingLineId: string;
  readonly subordinatePositionId: string;
  readonly managerPositionId: string;
  readonly motivo: string;
  readonly validFrom: string;
  readonly validTo: string | null;
  readonly version: number;
}

/** Ocupação (quem ocupa qual posição e desde quando). */
export interface OcupacaoSoberana {
  readonly ocupacaoId: string;
  readonly collaboratorId: string;
  readonly posicaoId: string;
  readonly validFrom: string;
  readonly validTo: string | null;
  readonly version: number;
}

export interface CargoSoberano {
  readonly jobRoleId: string;
  /** Rótulo estável (nunca autoridade) — pode ser nulo (D5). */
  readonly code: string | null;
  readonly nome: string;
  readonly status: string;
  readonly version: number;
}

export interface SenioridadeSoberana {
  readonly seniorityLevelId: string;
  readonly nome: string;
  readonly status: string;
  readonly version: number;
}

/** Versão da configuração de colegiado de um avaliado (0..N membros). */
export interface ColegiadoSoberano {
  readonly colegiadoId: string;
  readonly collaboratorId: string;
  readonly validFrom: string;
  readonly validTo: string | null;
  readonly version: number;
  /** IDs canônicos dos membros desta versão (vazio = "sem colegiado"). */
  readonly membroIds: readonly string[];
}

/**
 * Colaborador do tenant reduzido ao necessário para EXIBIR/selecionar na
 * estrutura (nome é rótulo; o UUID é a identidade). Lido pela MESMA via RLS
 * own-tenant (`collaborators_select_same_tenant`) — a tela de estrutura não
 * depende da porta de colaboradores para mostrar ocupante/membros.
 */
export interface ColaboradorResumidoSoberano {
  readonly collaboratorId: string;
  readonly nome: string;
}

/** Fotografia da estrutura do tenant, como o servidor a devolveu. */
export interface EstruturaSoberana {
  readonly unidades: readonly UnidadeSoberana[];
  readonly periodosParent: readonly PeriodoParentSoberano[];
  readonly posicoes: readonly PosicaoSoberana[];
  readonly reportingLines: readonly ReportingLineSoberana[];
  readonly ocupacoes: readonly OcupacaoSoberana[];
  readonly cargos: readonly CargoSoberano[];
  readonly senioridades: readonly SenioridadeSoberana[];
  readonly colegiados: readonly ColegiadoSoberano[];
  readonly colaboradores: readonly ColaboradorResumidoSoberano[];
}

export interface EntradaLerEstrutura {
  readonly organizationId?: string | null;
}

export interface LeituraEstrutura {
  ler(entrada: EntradaLerEstrutura): Promise<ResultadoLeituraEstrutura<EstruturaSoberana>>;
}

const ERRO_SEM_SESSAO = "Sessão inválida. Entre novamente.";
const ERRO_SEM_ORGANIZACAO = "Selecione uma organização ativa para consultar a estrutura.";
const ERRO_LEITURA = "Não foi possível carregar a estrutura organizacional.";
const ERRO_NEGADO = "Você não tem permissão para consultar a estrutura organizacional.";

interface LinhaUnidade {
  id: string;
  name: string | null;
  valid_from: string;
  valid_to: string | null;
  version: number | null;
}

interface LinhaParent {
  id: string;
  unit_id: string;
  parent_unit_id: string | null;
  valid_from: string;
  valid_to: string | null;
  version: number | null;
}

interface LinhaPosicao {
  id: string;
  unit_id: string;
  job_role_id: string;
  seniority_level_id: string | null;
  valid_from: string;
  valid_to: string | null;
  version: number | null;
}

interface LinhaReporting {
  id: string;
  subordinate_position_id: string;
  manager_position_id: string;
  reason: string | null;
  valid_from: string;
  valid_to: string | null;
  version: number | null;
}

interface LinhaOcupacao {
  id: string;
  collaborator_id: string;
  organizational_position_id: string;
  valid_from: string;
  valid_to: string | null;
  version: number | null;
}

interface LinhaCargo {
  id: string;
  code: string | null;
  name: string | null;
  status: string | null;
  version: number | null;
}

interface LinhaSenioridade {
  id: string;
  name: string | null;
  status: string | null;
  version: number | null;
}

interface LinhaColegiado {
  id: string;
  collaborator_id: string;
  valid_from: string;
  valid_to: string | null;
  version: number | null;
}

interface LinhaMembroColegiado {
  configuration_id: string;
  member_collaborator_id: string;
}

interface LinhaColaborador {
  id: string;
  full_name: string | null;
}

interface RespostaPostgrest {
  readonly data: unknown;
  readonly error: { readonly code?: string | null; readonly message?: string | null } | null;
}

function textoOuNulo(valor: unknown): string | null {
  return typeof valor === "string" && valor.length > 0 ? valor : null;
}

function texto(valor: unknown): string {
  return typeof valor === "string" ? valor : "";
}

function versao(valor: unknown): number {
  return typeof valor === "number" && Number.isFinite(valor) ? valor : 0;
}

/** Código público da falha de leitura, sem vazar SQL nem detalhe do banco. */
function codigoDaFalha(erro: {
  readonly code?: string | null;
  readonly message?: string | null;
}): CodigoPublico {
  const codigo = erro.code ?? "";
  // 42501 = insufficient_privilege (RLS/grants); PGRST301 = JWT ausente/inválido.
  if (codigo === "42501" || codigo === "PGRST301") return "FORBIDDEN";
  if (/permission denied|not authorized|jwt/i.test(erro.message ?? "")) return "FORBIDDEN";
  return "INTERNAL";
}

function linhas<T>(valor: unknown): T[] {
  if (!Array.isArray(valor)) return [];
  return valor.filter(
    (item): item is T => typeof item === "object" && item !== null && !Array.isArray(item)
  );
}

export function criarLeituraEstrutura(cliente: SupabaseClient): LeituraEstrutura {
  function falha<T>(codigo: CodigoPublico, mensagem: string): ResultadoLeituraEstrutura<T> {
    return { ok: false, error: { code: codigo, message: mensagem } };
  }

  /** A sessão é pré-condição da leitura RLS (ver cabeçalho). */
  async function temSessao(): Promise<boolean> {
    try {
      const { data } = await cliente.auth.getSession();
      return Boolean(data.session?.access_token);
    } catch {
      return false;
    }
  }

  /**
   * Traduz a resposta do PostgREST em resultado público. Erro nunca é propagado
   * cru: `FORBIDDEN` para negação de RLS/JWT e `INTERNAL` para o resto.
   */
  function tratar<T>(resposta: RespostaPostgrest): ResultadoLeituraEstrutura<T[]> {
    if (resposta.error) {
      const codigo = codigoDaFalha(resposta.error);
      return falha(codigo, codigo === "FORBIDDEN" ? ERRO_NEGADO : ERRO_LEITURA);
    }
    return { ok: true, data: linhas<T>(resposta.data) };
  }

  return {
    async ler(entrada) {
      const organizationId =
        typeof entrada.organizationId === "string" && entrada.organizationId.length > 0
          ? entrada.organizationId
          : null;
      if (!organizationId) return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      if (!(await temSessao())) return falha("NOT_AUTHORIZED", ERRO_SEM_SESSAO);

      // Filtro por `organization_id` é defesa em profundidade: a RLS já isola o
      // tenant. Ordenação determinística é UX (o contrato não define ordem).
      const [
        unidades,
        periodos,
        posicoes,
        reportings,
        ocupacoes,
        cargos,
        senioridades,
        colegiados,
        membros,
        colaboradores,
      ] = await Promise.all([
        cliente
          .from("organizational_units")
          .select("id, name, valid_from, valid_to, version")
          .eq("organization_id", organizationId)
          .order("name", { ascending: true })
          .then(tratar<LinhaUnidade>),
        cliente
          .from("organizational_unit_parent_periods")
          .select("id, unit_id, parent_unit_id, valid_from, valid_to, version")
          .eq("organization_id", organizationId)
          .order("valid_from", { ascending: false })
          .order("id", { ascending: true })
          .then(tratar<LinhaParent>),
        cliente
          .from("organizational_positions")
          .select("id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to, version")
          .eq("organization_id", organizationId)
          .order("valid_from", { ascending: false })
          .order("id", { ascending: true })
          .then(tratar<LinhaPosicao>),
        cliente
          .from("position_reporting_lines")
          .select(
            "id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to, version"
          )
          .eq("organization_id", organizationId)
          .order("valid_from", { ascending: false })
          .order("id", { ascending: true })
          .then(tratar<LinhaReporting>),
        cliente
          .from("occupations")
          .select("id, collaborator_id, organizational_position_id, valid_from, valid_to, version")
          .eq("organization_id", organizationId)
          .order("valid_from", { ascending: false })
          .order("id", { ascending: true })
          .then(tratar<LinhaOcupacao>),
        cliente
          .from("job_roles")
          .select("id, code, name, status, version")
          .eq("organization_id", organizationId)
          .order("name", { ascending: true })
          .then(tratar<LinhaCargo>),
        cliente
          .from("seniority_levels")
          .select("id, name, status, version")
          .eq("organization_id", organizationId)
          .order("name", { ascending: true })
          .then(tratar<LinhaSenioridade>),
        cliente
          .from("collegiate_configurations")
          .select("id, collaborator_id, valid_from, valid_to, version")
          .eq("organization_id", organizationId)
          .order("valid_from", { ascending: false })
          .order("id", { ascending: true })
          .then(tratar<LinhaColegiado>),
        cliente
          .from("collegiate_configuration_members")
          .select("configuration_id, member_collaborator_id")
          .eq("organization_id", organizationId)
          .order("configuration_id", { ascending: true })
          .then(tratar<LinhaMembroColegiado>),
        cliente
          .from("collaborators")
          .select("id, full_name")
          .eq("organization_id", organizationId)
          .order("full_name", { ascending: true })
          .then(tratar<LinhaColaborador>),
      ]);

      // Fail-closed: qualquer consulta negada/falha interrompe a leitura inteira
      // (a tela nunca mostra uma fotografia parcial como se fosse completa).
      if (!unidades.ok) return unidades;
      if (!periodos.ok) return periodos;
      if (!posicoes.ok) return posicoes;
      if (!reportings.ok) return reportings;
      if (!ocupacoes.ok) return ocupacoes;
      if (!cargos.ok) return cargos;
      if (!senioridades.ok) return senioridades;
      if (!colegiados.ok) return colegiados;
      if (!membros.ok) return membros;
      if (!colaboradores.ok) return colaboradores;

      const membrosPorColegiado = new Map<string, string[]>();
      for (const membro of membros.data) {
        const atuais = membrosPorColegiado.get(membro.configuration_id) ?? [];
        atuais.push(membro.member_collaborator_id);
        membrosPorColegiado.set(membro.configuration_id, atuais);
      }

      return {
        ok: true,
        data: {
          unidades: unidades.data.map((item) => ({
            unitId: texto(item.id),
            nome: texto(item.name),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          periodosParent: periodos.data.map((item) => ({
            periodoId: texto(item.id),
            unitId: texto(item.unit_id),
            parentUnitId: textoOuNulo(item.parent_unit_id),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          posicoes: posicoes.data.map((item) => ({
            posicaoId: texto(item.id),
            unitId: texto(item.unit_id),
            jobRoleId: texto(item.job_role_id),
            seniorityLevelId: textoOuNulo(item.seniority_level_id),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          reportingLines: reportings.data.map((item) => ({
            reportingLineId: texto(item.id),
            subordinatePositionId: texto(item.subordinate_position_id),
            managerPositionId: texto(item.manager_position_id),
            motivo: texto(item.reason),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          ocupacoes: ocupacoes.data.map((item) => ({
            ocupacaoId: texto(item.id),
            collaboratorId: texto(item.collaborator_id),
            posicaoId: texto(item.organizational_position_id),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          cargos: cargos.data.map((item) => ({
            jobRoleId: texto(item.id),
            code: textoOuNulo(item.code),
            nome: texto(item.name),
            status: texto(item.status),
            version: versao(item.version),
          })),
          senioridades: senioridades.data.map((item) => ({
            seniorityLevelId: texto(item.id),
            nome: texto(item.name),
            status: texto(item.status),
            version: versao(item.version),
          })),
          colegiados: colegiados.data.map((item) => ({
            colegiadoId: texto(item.id),
            collaboratorId: texto(item.collaborator_id),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
            membroIds: [...(membrosPorColegiado.get(texto(item.id)) ?? [])],
          })),
          colaboradores: colaboradores.data.map((item) => ({
            collaboratorId: texto(item.id),
            nome: texto(item.full_name),
          })),
        },
      };
    },
  };
}
