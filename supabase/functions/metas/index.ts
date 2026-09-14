import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { metas, type DepsMetas, type ExecucaoMeta } from "./core.ts";
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

/**
 * F5-10 P5 (Issue #218) — Edge Function `metas` (namespace `goal.*`).
 *
 * Fronteira confiável do domínio de METAS: autentica (`auth.getUser`), revalida
 * tenant, resolve o recurso SOBERANO (`evaluation_goals` + o `status` da LINHA
 * do ciclo da meta), decide pelo Policy Engine (ou pelo plano administrativo D19
 * em `goal.listar_por_escopo`) e SÓ ENTÃO executa a RPC `meta_*` com a
 * credencial privilegiada — que revalida tudo e é a dona das invariantes
 * transacionais/domínio (P2–P4).
 *
 * Este é o ÚNICO lugar que lê `SUPABASE_SERVICE_ROLE_KEY` e cria o cliente
 * privilegiado. A credencial NUNCA decide: é credencial de execução do ator
 * verificado, e o JWT do usuário não é propagado às RPCs.
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
        // Fail-closed do vocabulário: código não canônico não entra na matriz.
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

    // F5-10 P5 (§10/D8/D9): a META é recurso SOBERANO. A linha real é carregada
    // server-side — o tenant vem do recurso (nunca do caller) — e o probe de
    // domínio recebe `status`, `excluida` e o `cicloStatus` da LINHA soberana do
    // ciclo da meta. Sem essas três leituras a autorização nega tudo
    // (fail-closed): a Edge NUNCA declara estado.
    carregarRecurso: async ({ target, organizationId }) => {
      if (target.type === "goal") {
        const { data, error } = await admin
          .from("evaluation_goals")
          .select("id, organization_id, cycle_id, collaborator_id, status, excluida")
          .eq("id", target.id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (error || !data) return null;

        // Segunda leitura OBRIGATÓRIA, com filtro de tenant (defesa em
        // profundidade): o status do ciclo alimenta `goal.write`/`goal.approve`
        // (mutação só com ciclo ATIVO).
        const { data: ciclo, error: erroCiclo } = await admin
          .from("evaluation_cycles")
          .select("id, organization_id, status")
          .eq("id", data.cycle_id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (erroCiclo || !ciclo) return null;

        return {
          kind: "goal",
          id: data.id,
          organizationId: data.organization_id,
          ownerCollaboratorId: data.collaborator_id,
          status: data.status,
          excluida: data.excluida === true,
          cicloStatus: ciclo.status,
          cycleId: data.cycle_id,
        } as RecursoSoberanoCarregado;
      }

      // `goal.criar`: a meta AINDA NÃO EXISTE — o alvo funcional é o DONO.
      if (target.type === "collaborator") {
        const { data, error } = await admin
          .from("collaborators")
          .select("id, organization_id, status")
          .eq("id", target.id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (error || !data) return null;

        return {
          kind: "collaborator",
          id: data.id,
          organizationId: data.organization_id,
          ownerCollaboratorId: data.id,
          status: data.status,
        } as RecursoSoberanoCarregado;
      }

      return null;
    },

    // F5-10 P4 (§9.1/D14/D25): aprovadores CONGELADOS da meta (avaliação
    // ORIGINAL do dono), resolvidos server-side por papel. `null` quando NENHUM
    // papel é reconhecido ⇒ o provider nega as relações de aprovação
    // (fail-closed, sem inventar aprovador).
    resolverAprovadorCongelado: async ({ organizationId, target }) => {
      if (target.type !== "goal") return null;

      const [gerente, coordenador] = await Promise.all([
        admin.rpc("f5_10_aprovador_congelado", {
          p_goal_id: target.id,
          p_organization_id: organizationId,
          p_papel: "GERENTE",
        }),
        admin.rpc("f5_10_aprovador_congelado", {
          p_goal_id: target.id,
          p_organization_id: organizationId,
          p_papel: "COORDENADOR",
        }),
      ]);

      const idGerente = gerente.error ? null : ((gerente.data as string | null) ?? null);
      const idCoordenador = coordenador.error
        ? null
        : ((coordenador.data as string | null) ?? null);
      if (!idGerente && !idCoordenador) return null;

      return {
        ...(idGerente ? { gerente: idGerente } : {}),
        ...(idCoordenador ? { coordenador: idCoordenador } : {}),
      };
    },
  };

  // ---------------------------------------------------------------------------
  // Execução privilegiada: RPC `meta_*` (SECURITY INVOKER, EXECUTE só
  // service_role) com o ator VERIFICADO. Nenhum `p_payload_hash` é enviado: as
  // RPCs derivam o hash canônico server-side (D11) — e nenhum campo de
  // identidade/autoridade é aceito do corpo.
  // ---------------------------------------------------------------------------
  const executarRpc: DepsMetas["executarRpc"] = async (execucao: ExecucaoMeta) => {
    const org = execucao.organizationId;
    const ator = execucao.actorUserProfileId;
    const operacaoId = execucao.operationId;
    const metaId = execucao.goalId;
    const ciclo = execucao.cycleId;

    switch (execucao.operacao) {
      case "goal.criar":
        return admin.rpc("meta_criar", {
          p_organization_id: org,
          p_cycle_id: ciclo,
          p_collaborator_id: execucao.collaboratorId,
          p_tipo: execucao.tipo,
          p_descricao: execucao.descricao,
          p_kpi: execucao.kpi,
          p_valor_alvo: execucao.valorAlvo,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "goal.editar":
        return admin.rpc("meta_editar", {
          p_goal_id: metaId,
          p_organization_id: org,
          p_descricao: execucao.descricao,
          p_kpi: execucao.kpi,
          p_valor_alvo: execucao.valorAlvo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "goal.atualizar_progresso":
        return admin.rpc("meta_atualizar_progresso", {
          p_goal_id: metaId,
          p_organization_id: org,
          p_resultado_atual: execucao.resultadoAtual,
          p_progresso_percentual: execucao.progressoPercentual,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "goal.finalizar":
        return admin.rpc("meta_finalizar", {
          p_goal_id: metaId,
          p_organization_id: org,
          p_resultado_final: execucao.resultadoFinal,
          p_atingida: execucao.atingida,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "goal.revisar_finalizacao":
        return admin.rpc("meta_revisar_finalizacao", {
          p_goal_id: metaId,
          p_organization_id: org,
          p_resultado_final: execucao.resultadoFinal,
          p_atingida: execucao.atingida,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "goal.excluir":
        return admin.rpc("meta_excluir", {
          p_goal_id: metaId,
          p_organization_id: org,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "goal.aprovar":
        return admin.rpc("meta_aprovar", {
          p_goal_id: metaId,
          p_organization_id: org,
          p_papel: execucao.papel,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "goal.definir_limites_do_ciclo":
        return admin.rpc("meta_definir_limites_do_ciclo", {
          p_cycle_id: ciclo,
          p_organization_id: org,
          p_tipo: execucao.tipo,
          p_quantidade: execucao.quantidade,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "goal.listar_por_escopo":
        // Leitura por escopo: a assinatura real NÃO tem `p_operation_id` (não há
        // evento de trilha) e a RPC aplica capability `goal.read`, vínculo único
        // e o ESCOPO (SELF/aprovador congelado) — fonte única da relação.
        return admin.rpc("meta_listar_por_escopo", {
          p_organization_id: org,
          p_cycle_id: ciclo,
          p_actor_user_profile_id: ator,
        });

      default:
        // Inalcançável: o contrato só expõe operações contratadas.
        return { error: { code: "INVALID_INPUT", message: "Operação não suportada." } };
    }
  };

  const deps: DepsMetas = {
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
  };

  return metas(req, deps);
});
