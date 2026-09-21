/**
 * F5-08 P4 — LEITURA SOBERANA da estrutura organizacional e dos catálogos.
 *
 * Caminho DECIDIDO pelo contrato #327 (P1/P2B) — leitura por VIEW SOBERANA:
 *
 *   navegador → PostgREST (`select`) → view do próprio ator → linhas autorizadas
 *
 * - `escopo: "administrativo"` (default) lê **`estrutura_administrativa`**, que
 *   exige capability EFETIVA (`org.structure.manage` para estrutura/pessoas e
 *   `org.catalog.manage` para catálogos). Membership sozinho NÃO recebe linha:
 *   a view devolve conjunto vazio e a leitura falha `FORBIDDEN` (fail-closed no
 *   servidor, nunca "estrutura vazia").
 * - `escopo: "pessoal"` lê **`estrutura_pessoal`**, o SUBGRAFO VIGENTE do próprio
 *   ator (vínculo soberano + cadeia acima/abaixo + colegiado vigente), usado
 *   pelas superfícies pessoais de ciclo/meta/avaliação.
 * - A segurança continua INTEIRA no banco (views): o cliente NÃO decide
 *   autorização e a escolha do escopo é intenção de UX.
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

/** Escopo da leitura estrutural (a segurança é da VIEW, não do cliente). */
export type EscopoLeituraEstrutural = "administrativo" | "pessoal";

export interface EntradaLerEstrutura {
  readonly organizationId?: string | null;
  /**
   * `administrativo` (default) → `estrutura_administrativa` (exige capability
   * efetiva no servidor); `pessoal` → `estrutura_pessoal` (subgrafo vigente do
   * próprio ator). Valor ausente/desconhecido ⇒ administrativo (nunca amplia).
   */
  readonly escopo?: EscopoLeituraEstrutural;
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

  return {
    async ler(entrada) {
      const organizationId =
        typeof entrada.organizationId === "string" && entrada.organizationId.length > 0
          ? entrada.organizationId
          : null;
      if (!organizationId) return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      if (!(await temSessao())) return falha("NOT_AUTHORIZED", ERRO_SEM_SESSAO);

      const escopo: EscopoLeituraEstrutural =
        entrada.escopo === "pessoal" ? "pessoal" : "administrativo";

      // UMA leitura por escopo: a view já aplica tenant (membership ativa do
      // próprio ator), capability/subgrafo e vigência. Zero linha = sem
      // autorização (fail-closed no servidor).
      const resposta = await cliente
        .from(escopo === "pessoal" ? "estrutura_pessoal" : "estrutura_administrativa")
        .select(
          "organization_id, unidades, periodos_parent, posicoes, reporting_lines, " +
            "ocupacoes, colegiados, membros_colegiado, colaboradores, cargos, senioridades"
        )
        .eq("organization_id", organizationId)
        .maybeSingle();

      if (resposta.error) {
        const codigo = codigoDaFalha(resposta.error);
        return falha(codigo, codigo === "FORBIDDEN" ? ERRO_NEGADO : ERRO_LEITURA);
      }
      // A view não devolveu linha: não há membership autorizada para a leitura.
      if (!resposta.data) return falha("FORBIDDEN", ERRO_NEGADO);

      const snapshot = resposta.data as unknown as Record<string, unknown>;
      const unidades = linhas<LinhaUnidade>(snapshot.unidades);
      const periodos = linhas<LinhaParent>(snapshot.periodos_parent);
      const posicoes = linhas<LinhaPosicao>(snapshot.posicoes);
      const reportings = linhas<LinhaReporting>(snapshot.reporting_lines);
      const ocupacoes = linhas<LinhaOcupacao>(snapshot.ocupacoes);
      const cargos = linhas<LinhaCargo>(snapshot.cargos);
      const senioridades = linhas<LinhaSenioridade>(snapshot.senioridades);
      const colegiados = linhas<LinhaColegiado>(snapshot.colegiados);
      const membros = linhas<LinhaMembroColegiado>(snapshot.membros_colegiado);
      const colaboradores = linhas<LinhaColaborador>(snapshot.colaboradores);

      const membrosPorColegiado = new Map<string, string[]>();
      for (const membro of membros) {
        const atuais = membrosPorColegiado.get(membro.configuration_id) ?? [];
        atuais.push(membro.member_collaborator_id);
        membrosPorColegiado.set(membro.configuration_id, atuais);
      }

      return {
        ok: true,
        data: {
          unidades: unidades.map((item) => ({
            unitId: texto(item.id),
            nome: texto(item.name),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          periodosParent: periodos.map((item) => ({
            periodoId: texto(item.id),
            unitId: texto(item.unit_id),
            parentUnitId: textoOuNulo(item.parent_unit_id),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          posicoes: posicoes.map((item) => ({
            posicaoId: texto(item.id),
            unitId: texto(item.unit_id),
            jobRoleId: texto(item.job_role_id),
            seniorityLevelId: textoOuNulo(item.seniority_level_id),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          reportingLines: reportings.map((item) => ({
            reportingLineId: texto(item.id),
            subordinatePositionId: texto(item.subordinate_position_id),
            managerPositionId: texto(item.manager_position_id),
            motivo: texto(item.reason),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          ocupacoes: ocupacoes.map((item) => ({
            ocupacaoId: texto(item.id),
            collaboratorId: texto(item.collaborator_id),
            posicaoId: texto(item.organizational_position_id),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
          })),
          cargos: cargos.map((item) => ({
            jobRoleId: texto(item.id),
            code: textoOuNulo(item.code),
            nome: texto(item.name),
            status: texto(item.status),
            version: versao(item.version),
          })),
          senioridades: senioridades.map((item) => ({
            seniorityLevelId: texto(item.id),
            nome: texto(item.name),
            status: texto(item.status),
            version: versao(item.version),
          })),
          colegiados: colegiados.map((item) => ({
            colegiadoId: texto(item.id),
            collaboratorId: texto(item.collaborator_id),
            validFrom: texto(item.valid_from),
            validTo: textoOuNulo(item.valid_to),
            version: versao(item.version),
            membroIds: [...(membrosPorColegiado.get(texto(item.id)) ?? [])],
          })),
          colaboradores: colaboradores.map((item) => ({
            collaboratorId: texto(item.id),
            nome: texto(item.full_name),
          })),
        },
      };
    },
  };
}
