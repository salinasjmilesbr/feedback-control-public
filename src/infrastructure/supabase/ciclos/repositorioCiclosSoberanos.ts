/**
 * F5-09 P5 — LEITURA SOBERANA de ciclos (`evaluation_cycles`) por RLS.
 *
 * Caminho DECIDIDO pelo desenho técnico (§9/§13.5/§19 P5; D22):
 *
 *   navegador → PostgREST (`select`) → RLS own-tenant → linhas do tenant
 *
 * - A tabela tem policy `evaluation_cycles_select_same_tenant` (SELECT para
 *   `authenticated` com predicado `user_has_active_membership(organization_id)`)
 *   e `grant select` MINIMO (P5). A leitura **não** exige capability: a RLS é a
 *   barreira de TENANT; capability/escopo/elegibilidade continuam no Policy
 *   Engine (P6) e nas RPCs. Escrita direta do cliente é proibida e a mutação
 *   ocorre só pelas RPCs `ciclo_*` (service_role/Edge, P7).
 * - A sessão é OBRIGATÓRIA: sem JWT o PostgREST responde como `anon` e a RLS
 *   devolve conjunto vazio — uma negação SILENCIOSA que a UI leria como "não há
 *   ciclos". Por isso a sessão é verificada ANTES da consulta e a ausência
 *   recusa com `NOT_AUTHORIZED` (fail-closed, nunca vazio por negação).
 * - `organization_id` é INTENÇÃO de UX (defesa em profundidade no filtro E na
 *   projeção: linha de outro tenant é descartada/tratada como ausente); quem
 *   isola o tenant é a policy. Nada é inventado, semeado ou normalizado e o
 *   `localStorage` NÃO participa deste caminho.
 * - **UUID-first:** a identidade é `id`; `ano`/`numero` são rótulos do domínio e
 *   nunca chave de leitura/autorização.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { ehUuid, type CodigoPublico } from "../colaboradores/contrato";
import type {
  CicloSoberano,
  CycleRepository,
  NumeroCiclo,
  ResultadoCiclos,
} from "../../../application/ports/CycleRepository";

const ERRO_SEM_ORGANIZACAO = "Organização ativa ausente.";
const ERRO_SEM_SESSAO = "Sessão inválida. Entre novamente.";
const ERRO_NEGADO = "Você não tem permissão para consultar os ciclos desta organização.";
const ERRO_LEITURA = "Não foi possível consultar os ciclos agora.";
const ERRO_ID_INVALIDO = "Identificador de ciclo inválido.";

/** Colunas da projeção soberana (espinha §2.2) — nada além do necessário. */
const COLUNAS =
  "id, organization_id, ano, numero, status, data_inicio, data_fim, data_ativacao, " +
  "data_encerramento, encerrado_com_pendencias, quantidade_pendencias, version, " +
  "created_at, updated_at";

interface LinhaCiclo {
  id: string;
  organization_id: string;
  ano: number | null;
  numero: number | null;
  status: string | null;
  data_inicio: string | null;
  data_fim: string | null;
  data_ativacao: string | null;
  data_encerramento: string | null;
  encerrado_com_pendencias: boolean | null;
  quantidade_pendencias: number | null;
  version: number | null;
  created_at: string | null;
  updated_at: string | null;
}

interface ErroPostgrest {
  readonly code?: string | null;
  readonly message?: string | null;
}

interface RespostaPostgrest {
  readonly data?: unknown;
  readonly error?: ErroPostgrest | null;
}

/** 42501 = insufficient_privilege (RLS/grants); PGRST301 = JWT ausente/inválido. */
function codigoDaFalha(erro: ErroPostgrest): CodigoPublico {
  const codigo = erro.code ?? "";
  if (codigo === "42501" || codigo === "PGRST301") return "FORBIDDEN";
  if (/permission denied|not authorized|jwt/i.test(erro.message ?? "")) return "FORBIDDEN";
  return "INTERNAL";
}

function numeroDoDominio(valor: unknown): NumeroCiclo | null {
  return valor === 1 || valor === 2 || valor === 3 ? valor : null;
}

/**
 * Mapeia a linha do PostgreSQL para a projeção, sem derivar identidade de
 * `ano`/`numero` e sem inventar valores: linha fora do contrato (id ausente ou
 * número fora do domínio) é DESCARTADA (fail-closed).
 */
function mapearCiclo(linha: LinhaCiclo): CicloSoberano | null {
  const numero = numeroDoDominio(linha.numero);
  if (typeof linha.id !== "string" || linha.id.length === 0 || numero === null) return null;
  if (typeof linha.organization_id !== "string" || linha.organization_id.length === 0) return null;
  if (typeof linha.ano !== "number" || typeof linha.status !== "string") return null;
  return {
    id: linha.id,
    organizationId: linha.organization_id,
    ano: linha.ano,
    numero,
    status: linha.status as CicloSoberano["status"],
    dataInicio: linha.data_inicio,
    dataFim: linha.data_fim,
    dataAtivacao: linha.data_ativacao,
    dataEncerramento: linha.data_encerramento,
    encerradoComPendencias: linha.encerrado_com_pendencias ?? false,
    quantidadePendencias: linha.quantidade_pendencias ?? 0,
    version: linha.version ?? 0,
    criadoEm: linha.created_at ?? "",
    atualizadoEm: linha.updated_at ?? "",
  };
}

/** `null` = ausente/fora do tenant (ausência explícita, nunca erro). */
function mapearCicloOuNulo(valor: unknown): CicloSoberano | null {
  if (typeof valor !== "object" || valor === null || Array.isArray(valor)) return null;
  return mapearCiclo(valor as LinhaCiclo);
}

/**
 * Defesa em profundidade (NÃO é autorização): a linha devolvida precisa pertencer
 * ao tenant PEDIDO. A RLS é a barreira de segurança; esta checagem apenas garante
 * que uma resposta anômala/forjada do backend nunca chegue ao chamador.
 */
function mesmoTenant(ciclo: CicloSoberano, organizationId: string): boolean {
  return ciclo.organizationId === organizationId;
}

export function criarRepositorioCiclosSoberanos(cliente: SupabaseClient): CycleRepository {
  function falha<T>(codigo: CodigoPublico, mensagem: string): ResultadoCiclos<T> {
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

  /** Erro nunca é propagado cru: `FORBIDDEN` para RLS/JWT e `INTERNAL` no resto. */
  function tratarLista(
    resposta: RespostaPostgrest,
    organizationId: string
  ): ResultadoCiclos<readonly CicloSoberano[]> {
    if (resposta.error) {
      const codigo = codigoDaFalha(resposta.error);
      return falha(codigo, codigo === "FORBIDDEN" ? ERRO_NEGADO : ERRO_LEITURA);
    }
    const bruto = Array.isArray(resposta.data) ? resposta.data : [];
    const ciclos = bruto
      .map((item) => mapearCicloOuNulo(item))
      // Defesa em profundidade: a RLS isola o tenant, mas o cliente NÃO confia na
      // resposta como prova — linha de outra organização é DESCARTADA.
      .filter((ciclo): ciclo is CicloSoberano => ciclo !== null && mesmoTenant(ciclo, organizationId));
    return { ok: true, data: ciclos };
  }

  function tratarUm(
    resposta: RespostaPostgrest,
    organizationId: string
  ): ResultadoCiclos<CicloSoberano | null> {
    if (resposta.error) {
      const codigo = codigoDaFalha(resposta.error);
      return falha(codigo, codigo === "FORBIDDEN" ? ERRO_NEGADO : ERRO_LEITURA);
    }
    const ciclo = mapearCicloOuNulo(resposta.data);
    // Linha de outro tenant é tratada como AUSENTE (nunca devolvida ao chamador).
    return { ok: true, data: ciclo && mesmoTenant(ciclo, organizationId) ? ciclo : null };
  }

  function organizacaoValida(organizationId: string): boolean {
    return typeof organizationId === "string" && organizationId.length > 0;
  }

  return {
    async listarCiclos(organizationId) {
      if (!organizacaoValida(organizationId)) return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      if (!(await temSessao())) return falha("NOT_AUTHORIZED", ERRO_SEM_SESSAO);

      // Ordem determinística (UX): ano/numero decrescentes, UUID como desempate.
      const resposta = await (cliente
        .from("evaluation_cycles")
        .select(COLUNAS)
        .eq("organization_id", organizationId)
        .order("ano", { ascending: false })
        .order("numero", { ascending: false })
        .order("id", { ascending: true }) as unknown as Promise<RespostaPostgrest>);

      return tratarLista(resposta, organizationId);
    },

    async obterCiclo(organizationId, cycleId) {
      if (!organizacaoValida(organizationId)) return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      // UUID é a identidade canônica: identificador malformado é recusado ANTES
      // de qualquer consulta (fail-closed; nunca resolve por ano/numero).
      if (!ehUuid(cycleId)) return falha("INVALID_INPUT", ERRO_ID_INVALIDO);
      if (!(await temSessao())) return falha("NOT_AUTHORIZED", ERRO_SEM_SESSAO);

      const resposta = await (cliente
        .from("evaluation_cycles")
        .select(COLUNAS)
        .eq("organization_id", organizationId)
        .eq("id", cycleId)
        .maybeSingle() as unknown as Promise<RespostaPostgrest>);

      return tratarUm(resposta, organizationId);
    },

    async obterCicloAtivo(organizationId) {
      if (!organizacaoValida(organizationId)) return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      if (!(await temSessao())) return falha("NOT_AUTHORIZED", ERRO_SEM_SESSAO);

      // No máximo um ATIVO por organização (I5/D14): `maybeSingle` é o contrato.
      const resposta = await (cliente
        .from("evaluation_cycles")
        .select(COLUNAS)
        .eq("organization_id", organizationId)
        .eq("status", "ATIVO")
        .maybeSingle() as unknown as Promise<RespostaPostgrest>);

      return tratarUm(resposta, organizationId);
    },
  };
}
