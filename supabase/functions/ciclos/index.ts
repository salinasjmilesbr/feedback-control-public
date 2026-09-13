import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { ciclos, type DepsCiclos, type ExecucaoCiclo } from "./core.ts";
import {
  avaliarOperacaoAutorizacao,
  type DepsContextoAutorizacao,
} from "../../../src/authorization/contextoAutorizacao.ts";
import type { AuthIdentity } from "../../../src/auth/tipos.ts";
import { capabilityCanonica } from "../../../src/authorization/catalogoCapabilities.ts";
import type { Capability } from "../../../src/authorization/Capability.ts";
import type { CapabilityComEscopos } from "../../../src/authorization/providers/reais.ts";
import type { ScopeType } from "../../../src/authorization/policyEngine/types.ts";
import type { RecursoSoberanoCarregado } from "../../../src/authorization/resourceContextReal.ts";
import { criarPonteColaborador } from "../avaliacoes/ponteColaborador.ts";

/**
 * F5-09 P7 — Edge Function `ciclos` (namespace `cycle.*`, D25).
 *
 * Fronteira confiável do domínio de CICLOS: autentica (`auth.getUser`),
 * revalida tenant, resolve o recurso SOBERANO (`evaluation_cycles`), decide pelo
 * Policy Engine (ou pelo plano administrativo D19 em `cycle.criar`) e SÓ ENTÃO
 * executa a RPC `ciclo_*` com `service_role` — que revalida tudo e é a dona das
 * invariantes transacionais/domínio (P2–P4).
 *
 * `service_role` NUNCA decide: é credencial de execução do ator verificado, e o
 * JWT do usuário não é propagado às RPCs.
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

interface LinhaCapabilityEscopo {
  capability_code: string;
  scope_type: string;
  organizational_unit_id: string | null;
}

interface LinhaAlvoEscopo {
  collaborator_id: string | null;
  position_id: string | null;
}

Deno.serve(async (req) => {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    return json(
      { error: { code: "INTERNAL", message: "Configuração do servidor indisponível." } },
      500
    );
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ---------------------------------------------------------------------------
  // Identidade soberana (F5-01/F5-03) — reaproveitada pelo engine e pela
  // revalidação de tenant do corpo (§13.1 regra 8).
  // ---------------------------------------------------------------------------
  const resolverIdentidade = async (authUserId: string): Promise<AuthIdentity | null> => {
    const { data: perfil, error: erroPerfil } = await admin
      .from("user_profiles")
      .select("id, status")
      .eq("id", authUserId)
      .maybeSingle();
    if (erroPerfil || !perfil) return null;
    if (perfil.status !== "active") {
      return {
        authUserId,
        perfil: { id: perfil.id, status: "disabled" },
        memberships: [],
        organizacoes: [],
      };
    }

    const { data: memberships, error: erroMemberships } = await admin
      .from("user_organization_memberships")
      .select("id, organization_id, status")
      .eq("user_profile_id", authUserId)
      .eq("status", "active");
    if (erroMemberships) return null;

    const linhas = (memberships ?? []) as {
      id: string;
      organization_id: string;
      status: string;
    }[];
    const ids = linhas.map((linha) => linha.organization_id);

    let organizacoes: { id: string; name: string }[] = [];
    if (ids.length > 0) {
      const { data: orgs, error: erroOrgs } = await admin
        .from("organizations")
        .select("id, name")
        .in("id", ids);
      if (erroOrgs) return null;
      organizacoes = (orgs ?? []) as { id: string; name: string }[];
    }

    return {
      authUserId,
      perfil: { id: perfil.id, status: "active" },
      memberships: linhas.map((linha) => ({
        id: linha.id,
        organizationId: linha.organization_id,
        status: linha.status === "active" ? "active" : "disabled",
      })),
      organizacoes: organizacoes.map((org) => ({ id: org.id, name: org.name })),
    };
  };

  const resolverCapabilities = async (authUserId: string, organizationId: string) => {
    const { data, error } = await admin.rpc("resolver_capabilities_escopos_efetivas", {
      p_user_profile_id: authUserId,
      p_organization_id: organizationId,
    });
    return error ? [] : ((data ?? []) as LinhaCapabilityEscopo[]);
  };

  // ---------------------------------------------------------------------------
  // Fronteira de decisão (Policy Engine) — recurso SOBERANO carregado aqui.
  // ---------------------------------------------------------------------------
  const autorizacao: DepsContextoAutorizacao = {
    agora: () => new Date(),

    resolverIdentidade,

    resolverColaboradorVinculado: async (authUserId, organizationId) => {
      const { data, error } = await admin.rpc("resolver_collaborador_vinculado", {
        p_user_profile_id: authUserId,
        p_organization_id: organizationId,
      });
      if (error) return null;
      const primeira = ((data ?? []) as { collaborator_id: string | null }[])[0];
      return primeira?.collaborator_id ?? null;
    },

    resolverCapabilitiesEscopos: async (authUserId, organizationId) => {
      const linhas = await resolverCapabilities(authUserId, organizationId);
      const porCapability = new Map<string, { scopes: Set<ScopeType>; units: Set<string> }>();
      for (const linha of linhas) {
        if (!capabilityCanonica(linha.capability_code)) continue;
        const atual = porCapability.get(linha.capability_code) ?? {
          scopes: new Set<ScopeType>(),
          units: new Set<string>(),
        };
        atual.scopes.add(linha.scope_type as ScopeType);
        if (linha.organizational_unit_id) atual.units.add(linha.organizational_unit_id);
        porCapability.set(linha.capability_code, atual);
      }
      return Array.from(porCapability.entries()).map(
        ([code, dados]): CapabilityComEscopos => ({
          capability: capabilityCanonica(code)!,
          scopes: Array.from(dados.scopes),
          ...(dados.units.size > 0 ? { unitIds: Array.from(dados.units) } : {}),
        })
      );
    },

    resolverAlvosEscopo: async ({ authUserId, organizationId, scope, unitId, data }) => {
      const { data: alvos, error } = await admin.rpc("resolver_alvos_escopo", {
        p_user_profile_id: authUserId,
        p_organization_id: organizationId,
        p_scope_type: scope,
        p_organizational_unit_id: unitId,
        p_data: data.toISOString(),
      });
      if (error) return [];
      return ((alvos ?? []) as LinhaAlvoEscopo[]).map((linha) => ({
        collaboratorId: linha.collaborator_id,
        positionId: linha.position_id,
      }));
    },

    // F5-09 P5/P6: o CICLO é recurso SOBERANO. A linha real é carregada
    // server-side — o tenant vem do recurso (nunca do caller) e o `status` real
    // alimenta o `domainState` do engine (a Edge não declara estado).
    carregarRecurso: async ({ target, organizationId }) => {
      if (target.type !== "cycle") return null;

      const { data, error } = await admin
        .from("evaluation_cycles")
        .select("id, organization_id, ano, numero, status, version")
        .eq("id", target.id)
        .eq("organization_id", organizationId)
        .maybeSingle();
      if (error || !data) return null;

      return {
        kind: "cycle",
        id: data.id,
        organizationId: data.organization_id,
        status: data.status,
      } as RecursoSoberanoCarregado;
    },
  };

  // ---------------------------------------------------------------------------
  // Execução privilegiada: RPC `ciclo_*` (SECURITY INVOKER, EXECUTE só
  // service_role) com o ator VERIFICADO. Nenhum `p_payload_hash` é enviado: os
  // RPCs derivam o hash canônico server-side (desvio declarado em P2–P4).
  // ---------------------------------------------------------------------------
  const executarRpc: DepsCiclos["executarRpc"] = async (execucao: ExecucaoCiclo) => {
    const org = execucao.organizationId;
    const ator = execucao.actorUserProfileId;
    const operacaoId = execucao.operationId;
    const ciclo = execucao.cycleId;

    switch (execucao.operacao) {
      case "cycle.criar":
        return admin.rpc("ciclo_criar", {
          p_organization_id: org,
          p_ano: execucao.ano,
          p_numero: execucao.numero,
          p_data_inicio: execucao.dataInicio,
          p_data_fim: execucao.dataFim,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "cycle.editar":
        return admin.rpc("ciclo_editar", {
          p_cycle_id: ciclo,
          p_organization_id: org,
          p_ano: execucao.ano,
          p_numero: execucao.numero,
          p_data_inicio: execucao.dataInicio,
          p_data_fim: execucao.dataFim,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "cycle.ativar":
        return admin.rpc("ciclo_ativar", {
          p_cycle_id: ciclo,
          p_organization_id: org,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "cycle.encerrar":
        return admin.rpc("ciclo_encerrar", {
          p_cycle_id: ciclo,
          p_organization_id: org,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "cycle.cancelar":
        return admin.rpc("ciclo_cancelar", {
          p_cycle_id: ciclo,
          p_organization_id: org,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "cycle.reabrir":
        return admin.rpc("ciclo_reabrir", {
          p_cycle_id: ciclo,
          p_organization_id: org,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "cycle.corrigir_periodo":
        return admin.rpc("ciclo_corrigir_periodo", {
          p_cycle_id: ciclo,
          p_organization_id: org,
          p_data_inicio: execucao.dataInicio,
          p_data_fim: execucao.dataFim,
          p_justificativa: execucao.justificativa,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "cycle.admissao.incluir":
        return admin.rpc("ciclo_incluir_admissao", {
          p_cycle_id: ciclo,
          p_organization_id: org,
          p_collaborator_id: execucao.collaboratorId,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      default:
        // Inalcançável: o contrato só expõe operações contratadas.
        return { error: { code: "INVALID_INPUT", message: "Operação não suportada." } };
    }
  };

  const deps: DepsCiclos = {
    resolveCaller: async (authHeader) => {
      const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await caller.auth.getUser();
      return error ? null : (data.user?.id ?? null);
    },

    resolverIdentidade,

    // Plano ADMINISTRATIVO (D19/D21): capabilities efetivas do ator na
    // organização, resolvidas server-side (o resolver revalida perfil,
    // membership e tenant — divergência ⇒ lista vazia ⇒ FORBIDDEN).
    resolverCapabilitiesEfetivas: async ({ actorUserProfileId, organizationId }) =>
      (await resolverCapabilities(actorUserProfileId, organizationId)).map((linha) => ({
        capability_code: linha.capability_code,
      })),

    avaliarAutorizacao: async ({ authUserId, organizationId, capability, alvo }) => {
      const canonica = capabilityCanonica(capability) as Capability | undefined;
      if (!canonica) return { permitido: false, code: "FORBIDDEN" as const };

      const decisao = await avaliarOperacaoAutorizacao(
        { authUserId, organizationId, capability: canonica, alvo },
        autorizacao
      );
      return decisao.allowed
        ? { permitido: true }
        : { permitido: false, code: decisao.denial?.publicCode ?? "FORBIDDEN" };
    },

    executarRpc,

    // Ponte matrícula → UUID (F3-01) na fronteira confiável: a matrícula é
    // INTENÇÃO; o UUID resolvido é o que segue para a RPC de admissão.
    resolverMatricula: async (matricula, organizationId) =>
      criarPonteColaborador({
        buscarIdentificadoresPorCodigo: async ({ organizationId: org, businessCode }) =>
          admin
            .from("collaborator_identifiers")
            .select("collaborator_id, organization_id, business_code, valid_to")
            .eq("organization_id", org)
            .eq("business_code", businessCode),
      }).resolver({ organizationId, matricula }),
  };

  return ciclos(req, deps);
});
