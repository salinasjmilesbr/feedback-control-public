import type { Capability } from "../Capability";
import type {
  ExceptionalGrant,
  ExceptionalProvider,
  ExceptionalUsageRecord,
  TargetRef,
} from "../policyEngine/types";

/**
 * Origem C — acesso excepcional auditado a conteúdo confidencial (F4-06,
 * Issue #93). Contrato fechado D1–D20 / Q1–Q8 em
 * docs/F4-06-desenho-tecnico.md.
 *
 * Somente leitura, allowlist FECHADA, sem wildcard, sem prefix matching, sem
 * cargo/job_role. A fonte real (grants excepcionais + classificação soberana
 * de confidencialidade) virá de Supabase na F5; este módulo é o contrato puro
 * e testável consumido pelo policy engine através do `ExceptionalProvider`.
 */

/**
 * Allowlist FECHADA de capabilities elegíveis à origem C (D8).
 * Piloto: somente `evaluation.read` (leitura de conteúdo confidencial de
 * avaliação/feedback de terceiros). Escrita/edição/exclusão/administração,
 * wildcard e prefix matching NÃO são permitidos.
 */
export const EXCEPTIONAL_CAPABILITIES: readonly Capability[] = [
  "evaluation.read",
];

export interface ExceptionalProviderInput {
  organizationId: string;
  grants: readonly ExceptionalGrant[];
  /**
   * Classificação soberana do recurso (D7): o domínio declara, o engine
   * consome. true = confidencial elegível; false = não confidencial;
   * undefined = indeterminado/ausente (fail-closed ⇒ DENY). O caller NUNCA
   * informa esta classificação.
   */
  isTargetConfidential: (
    target: TargetRef,
    cycleId: string | undefined,
    organizationId: string
  ) => boolean | undefined;
  /** Event sink de uso efetivo (in-memory test double / future store). */
  recordUsage?: (record: ExceptionalUsageRecord) => void;
}

/**
 * D10 (fail-closed): avaliação é recurso por ciclo. No domínio-piloto o
 * `cycleId` é OBRIGATÓRIO no grant E no pedido, e deve ser exatamente igual e
 * não vazio. `undefined` NUNCA é interpretado como "qualquer ciclo". Para
 * tipos não associados a ciclo (fora do piloto), o grant não pode declarar
 * ciclo. Sem fallback.
 */
function cicloCompativel(
  grant: ExceptionalGrant,
  cycleId: string | undefined
): boolean {
  if (grant.target.type === "evaluation") {
    if (grant.cycleId === undefined || grant.cycleId.trim() === "") return false;
    if (cycleId === undefined || cycleId.trim() === "") return false;
    return grant.cycleId === cycleId;
  }
  // Tipos não associados a ciclo: cycleId deve estar ausente no grant (D10).
  if (grant.cycleId !== undefined) return false;
  return true;
}

/** Um grant se aplica ao pedido? Correlação EXATA (D10/D11/D15/D16). */
function grantAplicavel(
  grant: ExceptionalGrant,
  beneficiaryId: string,
  organizationId: string,
  capability: Capability,
  target: TargetRef,
  date: Date,
  cycleId: string | undefined
): boolean {
  if (grant.organizationId !== organizationId) return false;
  if (grant.beneficiaryUserProfileId !== beneficiaryId) return false;
  if (grant.capability !== capability) return false;
  if (grant.target.type !== target.type) return false;
  if (grant.target.id !== target.id) return false;
  // D10 fail-closed: cycleId obrigatório e exato para recurso por ciclo.
  if (!cicloCompativel(grant, cycleId)) return false;
  if (grant.status !== "active") return false;
  // D13: janela fechada [validFrom, validTo); futuro/expirado não autoriza.
  if (date < grant.validFrom || date >= grant.validTo) return false;
  return true;
}

export function createExceptionalProvider(
  input: ExceptionalProviderInput
): ExceptionalProvider {
  return {
    isCapabilityExceptionalEligible: (capability) =>
      EXCEPTIONAL_CAPABILITIES.includes(capability),

    isTargetConfidential: (target, cycleId, organizationId) =>
      input.isTargetConfidential(target, cycleId, organizationId),

    resolveExceptionalGrants: (
      beneficiaryId,
      organizationId,
      capability,
      target,
      date,
      cycleId
    ) => {
      // tenant mismatch ⇒ vazio (fail-closed)
      if (organizationId !== input.organizationId) return [];
      return input.grants.filter((g) =>
        grantAplicavel(
          g,
          beneficiaryId,
          organizationId,
          capability,
          target,
          date,
          cycleId
        )
      );
    },

    recordUsage: input.recordUsage,
  };
}
