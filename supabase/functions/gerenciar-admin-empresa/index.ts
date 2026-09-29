import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const HEADERS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...HEADERS, "Content-Type": "application/json" } });
const error = (code: string, message: string, status: number) => json({ error: { code, message } }, status);

async function hash(value: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: HEADERS });
  if (req.method !== "POST") return error("METHOD_NOT_ALLOWED", "Método não permitido.", 405);
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return error("INTERNAL", "Configuração indisponível.", 500);
  const authorization = req.headers.get("Authorization");
  if (!authorization) return error("NOT_AUTHORIZED", "Não autorizado.", 401);
  const caller = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await caller.auth.getUser();
  if (authError || !authData.user?.id) return error("NOT_AUTHORIZED", "Não autorizado.", 401);
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return error("INVALID_INPUT", "Corpo inválido.", 400); }
  const action = typeof body.action === "string" ? body.action : "";
  const organizationId = typeof body.organization_id === "string" ? body.organization_id : "";
  if (!UUID.test(organizationId)) return error("INVALID_INPUT", "Organização inválida.", 400);
  const { data: actor } = await admin.from("user_profiles").select("id").eq("id", authData.user.id).eq("status", "active").maybeSingle();
  if (!actor) return error("NOT_AUTHORIZED", "Não autorizado.", 403);
  const { data: allowed, error: authorityError } = await admin.rpc("usuario_eh_administrador", { p_user_profile_id: actor.id, p_organization_id: organizationId });
  if (authorityError || allowed !== true) return error("NOT_AUTHORIZED", "Não autorizado.", 403);

  if (action === "list") {
    const { data, error: listError } = await admin.from("user_organization_memberships").select("id,user_profile_id,status,user_profiles!inner(id,status,first_access_pending)").eq("organization_id", organizationId).order("created_at");
    if (listError) return error("INTERNAL", "Não foi possível listar administradores.", 500);
    const { data: role } = await admin.from("access_roles").select("id").eq("name", "admin").eq("is_system", true).maybeSingle();
    const rows = [];
    for (const item of data ?? []) {
      const { data: assignments } = role ? await admin.from("membership_access_role_assignments").select("status,updated_at").eq("membership_id", item.id).eq("access_role_id", role.id).order("updated_at", { ascending: false }).limit(1) : { data: [] };
      const assignment = assignments?.[0];
      if (assignment) {
        const { data: links } = await admin.from("membership_collaborator_links").select("collaborator_id,collaborators(full_name,email)").eq("membership_id", item.id).eq("organization_id", organizationId).eq("status", "active").order("updated_at", { ascending: false }).limit(1);
        const link = links?.[0] as { collaborator_id?: string; collaborators?: { full_name?: string | null; email?: string | null } | null } | undefined;
        const authTarget = await admin.auth.admin.getUserById(item.user_profile_id);
        const collaborator = link?.collaborators;
        rows.push({
          ...item,
          admin_status: assignment.status,
          display_name: collaborator?.full_name?.trim() || authTarget.data.user?.user_metadata?.full_name || authTarget.data.user?.user_metadata?.name || null,
          email: collaborator?.email || authTarget.data.user?.email || null,
        });
      }
    }
    return json({ administrators: rows });
  }

  if (action !== "invite" && action !== "revoke" && action !== "reactivate") return error("INVALID_ACTION", "Ação inválida.", 400);
  const operationId = typeof body.operation_id === "string" ? body.operation_id : crypto.randomUUID();
  if (!UUID.test(operationId)) return error("INVALID_INPUT", "Operação inválida.", 400);
  if (action === "invite") {
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    if (!email || !email.includes("@")) return error("INVALID_INPUT", "E-mail inválido.", 400);
    if (typeof body.operation_id === "string") {
      const { data: replay } = await admin.from("company_admin_operations").select("result_membership_id,target_user_profile_id,payload_hash").eq("organization_id", organizationId).eq("operation_id", operationId).maybeSingle();
      if (replay) {
        const { data: existingAuth } = await admin.auth.admin.getUserById(replay.target_user_profile_id);
        const replayHash = await hash({ action, organization_id: organizationId, email, target_user_id: replay.target_user_profile_id });
        if (!existingAuth.user || existingAuth.user.email?.toLowerCase() !== email || replay.payload_hash !== replayHash) return error("OPERATION_CONFLICT", "Operação já usada com outro payload.", 409);
        return json({ operation_id: operationId, user_id: replay.target_user_profile_id, membership_id: replay.result_membership_id, replay: true });
      }
    }
    const { data: existingUsers, error: existingUsersError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (existingUsersError) return error("INVITE_FAILED", "Convite nÃ£o enviado.", 502);
    if (existingUsers.users.some((user) => user.email?.toLowerCase() === email)) return error("INVITE_FAILED", "Convite nÃ£o enviado.", 502);
    const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email);
    if (inviteError || !invited.user?.id) return error("INVITE_FAILED", "Convite não enviado.", 502);
    const payload = { action, organization_id: organizationId, email, target_user_id: invited.user.id };
    const payloadHash = await hash(payload);
    const { data: profile } = await admin.from("user_profiles").select("id").eq("id", invited.user.id).maybeSingle();
    if (!profile) {
      const { error: profileError } = await admin.from("user_profiles").upsert({ id: invited.user.id, status: "active", first_access_pending: true }, { onConflict: "id", ignoreDuplicates: true });
      if (profileError) return error("PROFILE_CREATE_FAILED", profileError.message, 500);
    }
    const { data: membership, error: grantError } = await admin.rpc("company_admin_invite_grant", { p_operation_id: operationId, p_organization_id: organizationId, p_target_user_profile_id: invited.user.id, p_actor_user_profile_id: actor.id, p_payload_hash: payloadHash });
    if (grantError) { await admin.auth.admin.deleteUser(invited.user.id); return error(grantError.code ?? "ADMIN_OPERATION_FAILED", grantError.message, 409); }
    return json({ operation_id: operationId, user_id: invited.user.id, membership_id: membership });
  }
  const membershipId = typeof body.membership_id === "string" ? body.membership_id : "";
  if (!UUID.test(membershipId)) return error("INVALID_INPUT", "Membership inválida.", 400);
  const payloadHash = await hash({ action, organization_id: organizationId, membership_id: membershipId });
  const rpc = action === "revoke" ? "company_admin_revoke" : "company_admin_reactivate";
  const { error: operationError } = await admin.rpc(rpc, { p_operation_id: operationId, p_organization_id: organizationId, p_membership_id: membershipId, p_actor_user_profile_id: actor.id, p_payload_hash: payloadHash });
  if (operationError) return error(operationError.code ?? "ADMIN_OPERATION_FAILED", operationError.message, 409);
  return json({ operation_id: operationId, membership_id: membershipId });
});
