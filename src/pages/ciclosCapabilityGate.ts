import type { Capability } from "../authorization/Capability";

export function possuiCapabilityCiclos(
  capabilities: readonly Capability[]
): boolean {
  return capabilities.includes("cycle.read");
}
