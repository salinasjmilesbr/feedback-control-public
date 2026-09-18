import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { capabilityCanonica } from "../../../src/authorization/catalogoCapabilities.ts";

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
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: { code: "METHOD_NOT_ALLOWED" } }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: { code: "INTERNAL" } }, 500);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: { code: "NOT_AUTHORIZED" } }, 401);

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: user, error: authError } = await caller.auth.getUser();
  if (authError || !user.user?.id) return json({ error: { code: "NOT_AUTHORIZED" } }, 401);

  let body: { organization_id?: unknown };
  try {
    body = (await req.json()) as { organization_id?: unknown };
  } catch {
    return json({ error: { code: "INVALID_INPUT" } }, 400);
  }
  if (typeof body.organization_id !== "string" || body.organization_id.length === 0) {
    return json({ error: { code: "INVALID_INPUT" } }, 400);
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc("resolver_capabilities_escopos_efetivas", {
    p_user_profile_id: user.user.id,
    p_organization_id: body.organization_id,
  });
  if (error) return json({ error: { code: "FORBIDDEN" } }, 403);

  const capabilities = [...new Set(
    ((data ?? []) as { capability_code?: unknown }[])
      .map((row) => typeof row.capability_code === "string" ? capabilityCanonica(row.capability_code) : undefined)
      .filter((code): code is NonNullable<typeof code> => code !== undefined)
  )];
  return json({ capabilities });
});
