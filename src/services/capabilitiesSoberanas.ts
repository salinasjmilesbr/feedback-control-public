import type { Capability } from "../authorization/Capability";
import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";

export async function listarCapabilitiesEfetivas(
  organizationId: string
): Promise<readonly Capability[]> {
  const cliente = criarClienteSupabase();
  if (!cliente || !organizationId) return [];

  const { data, error } = await cliente.functions.invoke<{
    capabilities?: unknown;
  }>("capabilities", { body: { organization_id: organizationId } });
  if (error || !data || !Array.isArray(data.capabilities)) return [];
  return data.capabilities.filter(
    (value): value is Capability => typeof value === "string"
  );
}

export async function listarEscoposMinhaEquipe(
  organizationId: string
): Promise<readonly ("DIRECT_REPORTS" | "DESCENDANTS")[]> {
  const cliente = criarClienteSupabase();
  if (!cliente || !organizationId) return [];
  const { data, error } = await cliente.functions.invoke<{ scope_types?: unknown }>(
    "capabilities",
    { body: { organization_id: organizationId } }
  );
  if (error || !data || !Array.isArray(data.scope_types)) return [];
  return data.scope_types.filter(
    (value): value is "DIRECT_REPORTS" | "DESCENDANTS" =>
      value === "DIRECT_REPORTS" || value === "DESCENDANTS"
  );
}
