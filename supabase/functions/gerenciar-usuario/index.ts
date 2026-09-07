// F2-07 (Issue #74): desativação/reativação administrativa de usuário.
//
// Fronteira server-side (mesma autorização provisória da F2-06): usa o Supabase
// Auth Admin (`SUPABASE_SERVICE_ROLE_KEY`, injetada pelo runtime) e nunca é
// importada pelo frontend. O frontend apenas invoca esta função com o JWT do
// administrador logado; a autorização real acontece aqui.
//
// Desativação (disable):
//   1. persiste `user_profiles.status = 'disabled'`;
//   2. bane o usuário no Auth (`ban_duration`) — invalida refresh, bloqueia
//      `getUser` e o sign-in; em falha, compensa revertendo o status.
//   Nenhuma linha de perfil/membership/histórico é excluída fisicamente.
//
// Reativação (enable):
//   1. desbane o usuário (`ban_duration = 'none'`);
//   2. restaura `user_profiles.status = 'active'`.
//   Sessões antigas NÃO são restauradas: o usuário deve autenticar novamente
//   (comportamento documentado).
//
// Autorização (mínima, até a Fase 4): JWT válido + allowlist
// `INVITE_ADMIN_USER_IDS` + perfil ativo do chamador (fail-closed).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

function erro(codigo: string, mensagem: string, status: number): Response {
  return json({ error: { code: codigo, message: mensagem } }, status);
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BAN_LONGO = "876000h"; // ~100 anos: desativação sem exclusão.

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return erro("METHOD_NOT_ALLOWED", "Método não permitido.", 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return erro("INTERNAL", "Configuração do servidor indisponível.", 500);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) resolve o chamador (JWT).
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  const callerId = callerData?.user?.id;
  if (callerError || !callerId) return erro("NOT_AUTHORIZED", "Não autorizado.", 401);

  // 2) allowlist (fail-closed).
  const allowlist = (Deno.env.get("INVITE_ADMIN_USER_IDS") ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  if (!allowlist.includes(callerId)) return erro("NOT_AUTHORIZED", "Não autorizado.", 403);

  // 3) piso mínimo: perfil interno ativo do chamador.
  const { data: perfilCaller, error: perfilError } = await admin
    .from("user_profiles")
    .select("id, status")
    .eq("id", callerId)
    .maybeSingle();
  if (perfilError || !perfilCaller || perfilCaller.status !== "active") {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 403);
  }

  // 4) entradas.
  let body: { action?: unknown; user_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.", 400);
  }
  const action = typeof body?.action === "string" ? body.action : "";
  const userId = typeof body?.user_id === "string" ? body.user_id : "";
  if (action !== "disable" && action !== "enable") {
    return erro("INVALID_ACTION", "Ação inválida.", 400);
  }
  if (!UUID_RE.test(userId)) {
    return erro("INVALID_USER", "Usuário inválido.", 400);
  }

  if (action === "disable") {
    const { error: statusErr } = await admin
      .from("user_profiles")
      .update({ status: "disabled" })
      .eq("id", userId);
    if (statusErr) return erro("INTERNAL", "Não foi possível desativar o usuário.", 500);

    const { error: banErr } = await admin.auth.admin.updateUserById(userId, {
      ban_duration: BAN_LONGO,
    });
    if (banErr) {
      await admin.from("user_profiles").update({ status: "active" }).eq("id", userId);
      return erro("INTERNAL", "Não foi possível desativar o usuário.", 500);
    }

    return json({ userId, status: "disabled" });
  }

  // action === "enable"
  const { error: unbanErr } = await admin.auth.admin.updateUserById(userId, {
    ban_duration: "none",
  });
  if (unbanErr) return erro("INTERNAL", "Não foi possível reativar o usuário.", 500);

  const { error: statusErr } = await admin
    .from("user_profiles")
    .update({ status: "active" })
    .eq("id", userId);
  if (statusErr) {
    await admin.auth.admin.updateUserById(userId, { ban_duration: BAN_LONGO });
    return erro("INTERNAL", "Não foi possível reativar o usuário.", 500);
  }

  return json({ userId, status: "active" });
});
