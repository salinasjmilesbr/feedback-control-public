import type { Capability } from "../authorization/Capability";

export function podeCriarColaboradorPorCapability(
  organizationId: string | null,
  organizationIdDasCapabilities: string | null,
  capabilities: ReadonlySet<Capability>
): boolean {
  return (
    organizationId !== null &&
    organizationId === organizationIdDasCapabilities &&
    capabilities.has("collaborator.create")
  );
}
