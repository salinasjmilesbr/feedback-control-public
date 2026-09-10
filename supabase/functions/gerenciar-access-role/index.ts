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
    executarRpc: async (action, membershipId, accessRoleId, actorUserId) => {
      const admin = createClient(url, serviceKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const fn =
        action === "grant"
          ? "conceder_acesso_role_rpc"
          : "revogar_acesso_role_rpc";
      const { error } = await admin.rpc(fn, {
        p_membership_id: membershipId,
        p_access_role_id: accessRoleId,
        p_actor_user_profile_id: actorUserId,
      });
      return error ? { code: error.code, message: error.message } : null;
    },
  };

  return gerenciarAcessoRole(req, deps);
});
