import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...HEADERS },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: HEADERS });
  if (req.method !== "POST") return json({ error: { code: "METHOD_NOT_ALLOWED" } }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: { code: "INTERNAL" } }, 500);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: { code: "NOT_AUTHORIZED" } }, 401);

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await caller.auth.getUser();
  const userId = authData.user?.id;
  if (authError || !userId) return json({ error: { code: "NOT_AUTHORIZED" } }, 401);

  let body: { password?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: { code: "INVALID_INPUT" } }, 400);
  }
  if (typeof body.password !== "string" || body.password.length < 6) {
    return json({ error: { code: "INVALID_PASSWORD" } }, 400);
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: perfil, error: perfilError } = await admin
    .from("user_profiles")
    .select("id, first_access_pending")
    .eq("id", userId)
    .maybeSingle();
  if (perfilError || !perfil) return json({ error: { code: "NOT_AUTHORIZED" } }, 403);
  if (perfil.first_access_pending !== true) return json({ error: { code: "ALREADY_COMPLETED" } }, 409);

  const { error: passwordError } = await admin.auth.admin.updateUserById(userId, {
    password: body.password,
  });
  if (passwordError) return json({ error: { code: "INVALID_PASSWORD" } }, 400);

  const { error: completionError } = await admin
    .from("user_profiles")
    .update({ first_access_pending: false })
    .eq("id", userId)
    .eq("first_access_pending", true);
  if (completionError) return json({ error: { code: "INTERNAL" } }, 500);

  return json({ completed: true });
});
