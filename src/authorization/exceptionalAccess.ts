import { ValidationError } from "../errors/applicationErrors";
import { authorize } from "./policyEngine/policyEngine";
import type {
  DomainStateProbe,
  ExceptionalGrant,
  ExceptionalUsageRecord,
  PolicyEngineProviders,
  TargetRef,
} from "./policyEngine/types";
import type { Capability } from "./Capability";
import { EXCEPTIONAL_CAPABILITIES } from "./providers/exceptional";

/**
 * Serviço de administração do acesso excepcional (F4-06, Issue #93).
 * Contrato fechado D1–D20 / Q1–Q8. NÃO há migration/RLS/SECURITY DEFINER;
 * este módulo é core testável (entrada pura + event sink in-memory).
 *
 * Concessão é ATO ADMINISTRATIVO autorizado pelo Policy Engine via capability
 * `exceptional_access.grant` (D3/D4): a capability de concessão NÃO concede a
 * leitura do conteúdo, e possuir leitura NÃO concede a capability de concessão.
 * Auto-concessão é PROIBIDA (D5); sem dual control (D2/Q5); sem workflow de
 * solicitação (D1). Somente leitura no piloto (`evaluation.read`), por target
 * exato + cycleId obrigatório (avaliação é recurso por ciclo).
 */

/** Eventos de auditoria da origem C (D12/Q3/Q4/D20). */
export type ExceptionalAuditEvent =
  | { kind: "granted"; grant: ExceptionalGrant; timestamp: Date }
  | {
      kind: "revoked";
      grant: ExceptionalGrant;
      revokedBy: string;
      revokedAt: Date;
      motive: string;
    }
  | { kind: "used"; record: ExceptionalUsageRecord };

/** Event sink de auditoria (in-memory test double / future store). */
export type ExceptionalAuditSink = (event: ExceptionalAuditEvent) => void;

export interface ConcessaoExceptionalInput {
  organizationId: string;
  grantedByUserProfileId: string;
  beneficiaryUserProfileId: string;
  capability: Capability;
  target: TargetRef;
  cycleId?: string;
  justification: string;
  validFrom: Date;
  validTo: Date;
  providers: PolicyEngineProviders;
  domainState: DomainStateProbe;
  date: Date;
  /** Id explícita p/ teste determinístico; ausente = gerada. */
  grantId?: string;
  audit?: ExceptionalAuditSink;
}

function justificativaValida(justification: string): boolean {
  return justification.trim() !== "";
}

export function concederAcessoExcepcional(
  input: ConcessaoExceptionalInput
): ExceptionalGrant {
  // D8: capability ∈ allowlist FECHADA de exceção (somente leitura).
  if (!EXCEPTIONAL_CAPABILITIES.includes(input.capability)) {
    throw new ValidationError();
  }

  // D11/D10: target específico (piloto = avaliação) e cycleId obrigatório.
  if (input.target.type !== "evaluation" || input.target.id.trim() === "") {
    throw new ValidationError();
  }
  if (!input.cycleId || input.cycleId.trim() === "") {
    throw new ValidationError();
  }

  // justificativa obrigatória (trim, não vazio).
  if (!justificativaValida(input.justification)) {
    throw new ValidationError();
  }

  // D13: janela fechada válida (sem grant permanente).
  if (!(input.validTo > input.validFrom)) {
    throw new ValidationError();
  }

  // D5: auto-concessão proibida.
  if (input.grantedByUserProfileId === input.beneficiaryUserProfileId) {
    throw new ValidationError();
  }

  // D3: concedente autorizado pelo Policy Engine (capability de concessão).
  // D4: esta capability NÃO concede leitura do conteúdo — é ato administrativo.
  authorize(
    {
      actor: {
        actorId: input.grantedByUserProfileId,
        organizationId: input.organizationId,
      },
      capability: "exceptional_access.grant",
      target: input.target,
      context: { date: input.date, cycleId: input.cycleId },
      domainState: input.domainState,
    },
    input.providers
  );

  const grant: ExceptionalGrant = {
    id: input.grantId ?? crypto.randomUUID(),
    organizationId: input.organizationId,
    beneficiaryUserProfileId: input.beneficiaryUserProfileId,
    grantedByUserProfileId: input.grantedByUserProfileId,
    capability: input.capability,
    target: input.target,
    cycleId: input.cycleId,
    justification: input.justification.trim(),
    validFrom: input.validFrom,
    validTo: input.validTo,
    status: "active",
  };

  input.audit?.({ kind: "granted", grant, timestamp: input.date });

  return grant;
}

export interface RevogacaoExceptionalInput {
  grant: ExceptionalGrant;
  revokedByUserProfileId: string;
  motive: string;
  providers: PolicyEngineProviders;
  domainState: DomainStateProbe;
  date: Date;
  audit?: ExceptionalAuditSink;
}

export function revogarAcessoExcepcional(
  input: RevogacaoExceptionalInput
): ExceptionalGrant {
  const { grant } = input;

  if (grant.status !== "active") {
    throw new ValidationError();
  }
  if (!justificativaValida(input.motive)) {
    throw new ValidationError();
  }

  // D14: o CONCEDENTE pode revogar; outro ator precisa da capability apropriada.
  if (input.revokedByUserProfileId !== grant.grantedByUserProfileId) {
    authorize(
      {
        actor: {
          actorId: input.revokedByUserProfileId,
          organizationId: grant.organizationId,
        },
        capability: "exceptional_access.grant",
        target: grant.target,
        context: { date: input.date, cycleId: grant.cycleId },
        domainState: input.domainState,
      },
      input.providers
    );
  }

  const revoked: ExceptionalGrant = {
    ...grant,
    status: "revoked",
    revokedAt: input.date,
    revokedBy: input.revokedByUserProfileId,
    revocationMotive: input.motive.trim(),
  };

  input.audit?.({
    kind: "revoked",
    grant: revoked,
    revokedBy: input.revokedByUserProfileId,
    revokedAt: input.date,
    motive: input.motive.trim(),
  });

  return revoked;
}
