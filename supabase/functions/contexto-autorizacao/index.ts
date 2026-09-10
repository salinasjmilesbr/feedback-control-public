// F5-05 — Edge Function da FRONTEIRA CONFIÁVEL server-side (D20).
//
// Responsabilidade: resolver a identidade SOBERANA do chamador (auth.getUser) e
// executar a avaliação de autorização (ActorContext + ResourceContext + engine
// F4-03) com dados lidos SERVER-SIDE. O cliente envia apenas a intenção
// (organização pretendida, capability pretendida, alvo) — nunca prova.
//
// POR QUE service_role NÃO permite falsificar o ator:
//   - a credencial service_role (apikey) apenas ELEVA privilégios (BYPASSRLS);
//     NÃO define `auth.uid()`. A identidade do ator vem do JWT do usuário,
//     validado por `auth.getUser` neste runtime;
//   - o RPC/chamada privilegiada usa o `authUserId` VERIFICADO — nunca um
//     `actor_id` do corpo (o core rejeita esse campo);
//   - o JWT do usuário NÃO é propagado ao cliente administrativo (senão o
//     PostgREST assumiria a role `authenticated` e perderia o EXECUTE de
//     service_role) — o mesmo padrão validado na F5-04 (D16).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  avaliarRequisicaoAutorizacao,
  type DepsCoreContextoAutorizacao,
} from "./core.ts";
import type { AuthIdentity } from "../../../src/auth/tipos.ts";
import { capabilityCanonica } from "../../../src/authorization/catalogoCapabilities.ts";
import type { CapabilityComEscopos } from "../../../src/authorization/providers/reais.ts";
import type { ScopeType } from "../../../src/authorization/policyEngine/types.ts";
import type { RecursoSoberanoCarregado } from "../../../src/authorization/resourceContextReal.ts";

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

  // Cliente privilegiado (service_role), SEM o JWT do usuário no Authorization:
  // apenas eleva privilégios; o ator vem do JWT verificado.
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const deps: DepsCoreContextoAutorizacao = {
    resolveCaller: async (authHeader) => {
      const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await caller.auth.getUser();
      return error ? null : (data.user?.id ?? null);
    },

    autorizacao: {
      agora: () => new Date(),

      resolverIdentidade: async (authUserId): Promise<AuthIdentity | null> => {
        const { data: perfil, error: erroPerfil } = await admin
          .from("user_profiles")
          .select("id, status")
          .eq("id", authUserId)
          .maybeSingle();
        if (erroPerfil || !perfil) return null;
        if (perfil.status !== "active") {
          // Perfil inativo: devolve snapshot com status não-ativo (o montador nega).
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

        const linhasMembership = (memberships ?? []) as {
          id: string;
          organization_id: string;
          status: string;
        }[];
        const idsOrganizacoes = linhasMembership.map((linha) => linha.organization_id);

        let organizacoes: { id: string; name: string }[] = [];
        if (idsOrganizacoes.length > 0) {
          const { data: orgs, error: erroOrgs } = await admin
            .from("organizations")
            .select("id, name")
            .in("id", idsOrganizacoes);
          if (erroOrgs) return null;
          organizacoes = (orgs ?? []) as { id: string; name: string }[];
        }

        return {
          authUserId,
          perfil: { id: perfil.id, status: "active" },
          memberships: linhasMembership.map((linha) => ({
            id: linha.id,
            organizationId: linha.organization_id,
            status: linha.status === "active" ? "active" : "disabled",
          })),
          organizacoes: organizacoes.map((org) => ({ id: org.id, name: org.name })),
        };
      },

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
        const { data, error } = await admin.rpc(
          "resolver_capabilities_escopos_efetivas",
          { p_user_profile_id: authUserId, p_organization_id: organizationId }
        );
        if (error) return [];

        const porCapability = new Map<
          string,
          { scopes: Set<ScopeType>; units: Set<string> }
        >();
        for (const linha of (data ?? []) as LinhaCapabilityEscopo[]) {
          // Fail-closed do vocabulário (F5-04 D14): código desconhecido é ignorado.
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

      carregarRecurso: async ({ target, organizationId }) => {
        // Somente recursos com persistência soberana (estrutura F3). Alvos de
        // domínios em localStorage e alvos globais/sintéticos ⇒ não carregam.
        if (target.type !== "collaborator") return null;

        const { data, error } = await admin
          .from("collaborators")
          .select("id, organization_id")
          .eq("id", target.id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (error || !data) return null;

        return {
          kind: "collaborator",
          id: data.id,
          organizationId: data.organization_id,
          ownerCollaboratorId: data.id,
        } as RecursoSoberanoCarregado;
      },
    },
  };

  return avaliarRequisicaoAutorizacao(req, deps);
});
