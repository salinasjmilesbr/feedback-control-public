import type { Capability } from "../Capability";
import type { TargetRef } from "../policyEngine/types";

/**
 * Contrato de compatibilidade capability × tipo de alvo (F4-04, D18 = A
 * ajustada). NÃO concede autorização, NÃO substitui capability/scope/
 * relationProvider e NÃO reimplementa regra de domínio: apenas rejeita
 * combinações semanticamente impossíveis. Incompatibilidade ⇒ DENY
 * (fail-closed).
 *
 * O contrato é deliberadamente mínimo: só bloqueia o que é impossível.
 */

function dominioDa(capability: Capability): string {
  return capability.split(".")[0];
}

// Domínio da capability → tipos de alvo PROIBIDOS.
const TIPOS_INCOMPATIVEIS: Record<string, ReadonlySet<TargetRef["type"]>> = {
  evaluation: new Set(["goal", "observation"]),
  goal: new Set(["evaluation", "observation"]),
  observation: new Set(["goal", "evaluation"]),
};

export function isCapabilityTargetCompatible(
  capability: Capability,
  target: TargetRef
): boolean {
  const proibidos = TIPOS_INCOMPATIVEIS[dominioDa(capability)];
  if (!proibidos) return true;
  return !proibidos.has(target.type);
}
