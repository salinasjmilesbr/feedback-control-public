// F2-06 (Issue #73): convite administrativo de usuário.
//
// Fronteira server-side ÚNICA para operações privilegiadas de Auth: usa o
// Supabase Auth Admin (`SUPABASE_SERVICE_ROLE_KEY`, injetada pelo runtime) e
// nunca é importada pelo frontend. O frontend apenas invoca esta função com o
// JWT do usuário logado; a autorização real acontece aqui.
//
// Autorização (mínima, até a Fase 4 definir capabilities):
//   1. o chamador precisa de um JWT válido (resolvido via auth.getUser);
//   2. o `auth.uid()` do chamador precisa estar no allowlist server-side
//      `INVITE_ADMIN_USER_IDS` (fail-closed: sem variável => 403);
//   3. o chamador precisa ter `user_profiles.status = 'active'`.
//
// Consistência: a criação no Auth é externa ao Postgres, então não há
// transação única. Estratégia: criar o usuário no Auth; criar perfil+membership
// atomicamente via RPC (`criar_perfil_membership`, SECURITY DEFINER); em
// qualquer falha do RPC, compensar removendo o usuário recém-criado no Auth
// (não sobra estado parcial silencioso).

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

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

  // Cliente privilegiado (service_role) — exclusivo deste runtime server-side.
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) resolve o chamador a partir do JWT enviado (validado pelo gotrue).
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  const callerId = callerData?.user?.id;
  if (callerError || !callerId) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }

  // 2) allowlist server-side (fail-closed).
  const allowlist = (Deno.env.get("INVITE_ADMIN_USER_IDS") ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  if (!allowlist.includes(callerId)) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 403);
  }

  // 3) piso mínimo: perfil interno ativo.
  const { data: perfil, error: perfilError } = await admin
    .from("user_profiles")
    .select("id, status")
    .eq("id", callerId)
    .maybeSingle();
  if (perfilError || !perfil || perfil.status !== "active") {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 403);
  }

  // 4) entradas.
  let body: { email?: unknown; organization_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.", 400);
  }
  const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
  const organizationId = typeof body?.organization_id === "string" ? body.organization_id : "";
  if (!EMAIL_RE.test(email)) {
    return erro("INVALID_EMAIL", "E-mail inválido.", 400);
  }
  if (!UUID_RE.test(organizationId)) {
    return erro("INVALID_ORGANIZATION", "Organização inválida.", 400);
  }

  // 5) cria o usuário no Auth (convite por e-mail).
  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email);
  if (inviteError) {
    const duplicado = inviteError.code === "email_exists" || inviteError.status === 422;
    return duplicado
      ? erro("USER_EXISTS", "Já existe um usuário com este e-mail.", 409)
      : erro("INTERNAL", "Não foi possível convidar o usuário.", 500);
  }
  const userId = invited?.user?.id;
  if (!userId) {
    return erro("INTERNAL", "Não foi possível convidar o usuário.", 500);
  }

  // 6) perfil + membership em uma única operação atômica (RPC SECURITY DEFINER).
  const { error: rpcError } = await admin.rpc("criar_perfil_membership", {
    p_user_id: userId,
    p_organization_id: organizationId,
  });

  if (rpcError) {
    // 23505 (unique_violation) => usuário já existia (convite duplicado) ou
    // membership duplicada: NÃO compensa (não há usuário novo para remover).
    if (rpcError.code === "23505") {
      return erro("USER_EXISTS", "Já existe um usuário com este e-mail.", 409);
    }
    // 23503 (foreign_key_violation) => organização inexistente.
    if (rpcError.code === "23503") {
      await admin.auth.admin.deleteUser(userId);
      return erro("INVALID_ORGANIZATION", "Organização inválida.", 400);
    }
    // Demais falhas: compensação remove o usuário recém-criado no Auth.
    await admin.auth.admin.deleteUser(userId);
    return erro("INTERNAL", "Não foi possível concluir o convite.", 500);
  }

  return json({ userId, email }, 200);
});
