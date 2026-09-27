// F5-04 (Issue #165): Edge Function do caminho server-side de concessão/
// revogação de access roles (D16).
//
// Fronteira server-side ÚNICA para operações administrativas de access roles.
// O frontend invoca esta função com o JWT do usuário logado; a identidade
// soberana é resolvida aqui (auth.getUser) e o RPC é executado com a credencial
// service_role (SEM o JWT do usuário no Authorization). Nunca é importada pelo
// frontend.
//
// POR QUE service_role NÃO permite falsificar o ator e POR QUE o JWT NÃO é
// propagado ao RPC:
//   - se o JWT do usuário fosse mantido no header `Authorization`, o PostgREST
//     assumiria a role `authenticated` (o JWT define a role efetiva) e a chamada
//     ao RPC falharia por permissão (EXECUTE só service_role);
//   - por isso a IDENTIDADE e a EXECUÇÃO são separadas: a identidade vem de
//     `auth.getUser(JWT)` (Gotrue) e o RPC roda com service_role (apikey), que
//     apenas eleva privilégios (BYPASSRLS) e NÃO define o ator;
//   - o ator verificado (user.id) é passado como `p_actor_user_profile_id`,
//     derivado exclusivamente de identidade autenticada verificada server-side;
//   - o cliente nunca envia actor_id (o core rejeita esse campo).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  gerenciarAcessoRole,
  type DepsGerenciarAcessoRole,
} from "./core.ts";

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

  const deps: DepsGerenciarAcessoRole = {
    // 1) identidade soberana a partir do JWT (validado pelo Gotrue).
    resolveCaller: async (authHeader) => {
      const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await caller.auth.getUser();
      return error ? null : (data.user?.id ?? null);
    },
    // 2) executa o RPC com service_role SEM o JWT do usuário; o ator é o
    //    user.id verificado (jamais do corpo).
    executarRpc: async (action, membershipId, accessRoleId, actorUserId, organizationId, targetEmail, scopeType, operationId, reason) => {
      const admin = createClient(url, serviceKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const evaluator = action === "grant-evaluator" || action === "revoke-evaluator";
      const functional = action === "grant-functional" || action === "revoke-functional";
      const fn = evaluator
        ? (action === "grant-evaluator" ? "f6_306_conceder_evaluator" : "f6_306_revogar_evaluator")
        : functional
        ? "gerenciar_acesso_funcional_rpc"
        : (action === "grant" ? "conceder_acesso_role_rpc" : "revogar_acesso_role_rpc");
      if (evaluator) {
        const users = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
        const target = users.data.users.find((user) => user.email?.toLowerCase() === targetEmail);
        if (!target) return { code: "F6_306_TARGET_NOT_FOUND", message: "Usuário não encontrado." };
        const { error } = await admin.rpc(fn, {
          p_target_user_profile_id: target.id,
          p_organization_id: organizationId,
          p_actor_user_profile_id: actorUserId,
        });
        return error ? { code: error.code, message: error.message } : null;
      }
      const { error } = await admin.rpc(fn, functional ? {
        p_operation_id: operationId,
        p_action: action === "grant-functional" ? "grant" : "revoke",
        p_membership_id: membershipId,
        p_access_role_id: accessRoleId,
        p_scope_type: scopeType,
        p_reason: reason,
        p_actor_user_profile_id: actorUserId,
      } : {
        p_membership_id: membershipId,
        p_access_role_id: accessRoleId,
        p_actor_user_profile_id: actorUserId,
      });
      return error ? { code: error.code, message: error.message } : null;
    },
  };

  // Lista administrativa somente para montar a jornada de negocio. A
  // autorizacao continua server-side e nenhum identificador retornado pelo
  // cliente e aceito como prova de autoridade.
  if (req.method === "POST") {
    try {
      const body = await req.clone().json();
      if (body?.action === "list-functional" && typeof body.organization_id === "string") {
        const authHeader = req.headers.get("Authorization");
        const callerId = authHeader ? await deps.resolveCaller(authHeader) : null;
        if (!callerId) return json({ error: { code: "NOT_AUTHORIZED", message: "NÃ£o autorizado." } }, 401);
        const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
        const authority = await admin.rpc("usuario_eh_administrador", {
          p_user_profile_id: callerId, p_organization_id: body.organization_id,
        });
        if (authority.error || authority.data !== true) return json({ error: { code: "FORBIDDEN", message: "OperaÃ§Ã£o negada." } }, 403);
        const [roles, memberships] = await Promise.all([
          admin.from("access_roles").select("id,name,organization_id").eq("status", "active")
            .or(`organization_id.is.null,organization_id.eq.${body.organization_id}`),
          admin.from("user_organization_memberships").select("id,user_profile_id").eq("organization_id", body.organization_id).eq("status", "active"),
        ]);
        if (roles.error || memberships.error) return json({ error: { code: "INTERNAL", message: "Dados administrativos indisponÃ­veis." } }, 500);
        const links = memberships.data?.length ? await admin.from("membership_collaborator_links").select("membership_id,collaborator_id").in("membership_id", (memberships.data ?? []).map((m) => m.id)).eq("status", "active") : { data: [], error: null };
        const collaboratorIds = (links.data ?? []).map((l) => l.collaborator_id);
        const collaborators = collaboratorIds.length ? await admin.from("collaborators").select("id,full_name").in("id", collaboratorIds) : { data: [], error: null };
        if (links.error || collaborators.error) return json({ error: { code: "INTERNAL", message: "VÃ­nculos administrativos indisponÃ­veis." } }, 500);
        const names = new Map((collaborators.data ?? []).map((c) => [c.id, c.full_name]));
        return json({ ok: true, people: (links.data ?? []).map((l) => ({ membership_id: l.membership_id, collaborator_id: l.collaborator_id, name: names.get(l.collaborator_id) ?? "Pessoa sem nome" })), roles: (roles.data ?? []).filter((r) => r.name !== "admin") });
      }
    } catch { /* segue para o contrato normal, que devolve INVALID_INPUT */ }
  }

  return gerenciarAcessoRole(req, deps);
});
