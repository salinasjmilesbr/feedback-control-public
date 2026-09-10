// F5-04 (Issue #165): Edge Function do caminho server-side de concessão/
// revogação de access roles (D16).
//
// Fronteira server-side ÚNICA para operações administrativas de access roles.
// O frontend invoca esta função com o JWT do usuário logado; a identidade
// soberana é resolvida aqui (auth.getUser) e preservada até `auth.uid()` dentro
// do RPC. Nunca é importada pelo frontend.
//
// Por que `service_role` NÃO permite falsificar o ator pelo cliente:
//   - a chave service_role (enviada como `apikey`) apenas ELEVA privilégios
//     (BYPASSRLS); ela NÃO define `request.jwt.claims`/`auth.uid()` por si só —
//     sem o JWT do usuário, `auth.uid()` é NULL e o RPC rejeita (fail-closed);
//   - a identidade do ator vem do JWT do usuário (header `Authorization`),
//     validado por `auth.getUser` no Gotrue;
//   - o RPC é chamado com o MESMO JWT preservado no header `Authorization` do
//     cliente `admin` (service_role), de modo que `auth.uid()` = usuário
//     autenticado — nunca um `actor_id` vindo do payload.

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
    // 2) executa o RPC administrativo preservando o JWT do usuário.
    executarRpc: async (authHeader, action, membershipId, accessRoleId) => {
      const admin = createClient(url, serviceKey, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const fn =
        action === "grant"
          ? "conceder_acesso_role_rpc"
          : "revogar_acesso_role_rpc";
      const { error } = await admin.rpc(fn, {
        p_membership_id: membershipId,
        p_access_role_id: accessRoleId,
      });
      return error ? { code: error.code, message: error.message } : null;
    },
  };

  return gerenciarAcessoRole(req, deps);
});
