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
