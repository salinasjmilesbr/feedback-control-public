import type { Capability } from "../Capability";
import type {
  PilotFullAccessGrant,
  PilotFullAccessProvider,
  PilotUsageRecord,
  TargetRef,
} from "../policyEngine/types";

/**
 * Origem D — Pilot Full Access (F4-07, Issue #94). Contrato fechado D1–D18 /
 * Q1–Q9 em docs/F4-07-desenho-tecnico.md.
 *
 * Development-only, tenant-scoped, perfil versionado FECHADO
 * (PILOT_PROFILE_V1), sem conteúdo confidencial, sem capabilities de
 * segurança, sem wildcard, sem cargo/job_role. A fonte real virá de Supabase na
 * F5; este módulo é o contrato puro e testável consumido pelo engine através do
 * `PilotFullAccessProvider`.
 */

/**
 * Perfil versionado FECHADO de capabilities pilot-eligible (D1/D3/D16/Q1/Q9).
 * Lista EXPLÍCITA — sem "*", sem "todas exceto", sem prefix matching. Nova
 * capability no Virtus NÃO entra aqui automaticamente (exige nova versão).
 */
export const PILOT_PROFILE_V1: readonly Capability[] = [
  "collaborator.create",
  "collaborator.edit",
  "collaborator.list",
  "cycle.coordinator.list",
  "cycle.management.view",
  "cycle.team.panel.view",
  "cycle.cancel.manager",
  "cycle.reopen.manager",
  "cycle.period.correct.manager",
  "goal.write",
  "goal.approve",
  "goal.view.admin",
  "goal.create.own",
  "goal.edit.own",
  "goal.delete.own",
  "goal.progress.own",
  "goal.finalize.own",
  "observation.create",
  "observation.edit",
  "observation.delete",
];

/** Perfis versionados suportados (referência canônica dos `profileVersion`). */
export const PILOT_PROFILES: Readonly<Record<string, readonly Capability[]>> = {
  PILOT_PROFILE_V1,
};

export type PilotEnvironment = "development" | "homologation" | "production";

export interface PilotFullAccessProviderInput {
  organizationId: string;
  grants: readonly PilotFullAccessGrant[];
  /** Ambiente injetado pela composição (config/ambiente.ts na F5); core puro. */
  environment: PilotEnvironment;
  profiles?: Readonly<Record<string, readonly Capability[]>>;
  /**
   * Classificação soberana do recurso (mesma fonte da F4-06): true =
   * confidencial; false = não confidencial; undefined = indeterminado.
   */
  isTargetConfidential: (
    target: TargetRef,
    cycleId: string | undefined,
    organizationId: string
  ) => boolean | undefined;
  recordUsage?: (record: PilotUsageRecord) => void;
}

export function createPilotFullAccessProvider(
  input: PilotFullAccessProviderInput
): PilotFullAccessProvider {
  const profiles = input.profiles ?? PILOT_PROFILES;

  return {
    // D13: D só produz ALLOW em development.
    isEnvironmentEligible: () => input.environment === "development",

    // D1/D3/D16: capability ∈ algum perfil versionado suportado (lista fechada).
    isCapabilityPilotEligible: (capability) =>
      Object.values(profiles).some((caps) => caps.includes(capability)),

    isTargetConfidential: (target, cycleId, organizationId) =>
      input.isTargetConfidential(target, cycleId, organizationId),

    resolvePilotFullAccessGrants: (beneficiaryId, organizationId, capability, date) => {
      // tenant mismatch ⇒ vazio (fail-closed)
      if (organizationId !== input.organizationId) return [];

      return input.grants.filter((g) => {
        if (g.organizationId !== organizationId) return false;
        if (g.beneficiaryUserProfileId !== beneficiaryId) return false;
        if (g.status !== "active") return false;
        // D13 janela fechada [validFrom, validTo); futuro/expirado não autoriza.
        if (date < g.validFrom || date >= g.validTo) return false;
        // D16: perfil desconhecido/inelegível ⇒ não aplicável (fail-closed).
        const profile = profiles[g.profileVersion];
        if (!profile) return false;
        return profile.includes(capability);
      });
    },

    recordUsage: input.recordUsage,
  };
}
