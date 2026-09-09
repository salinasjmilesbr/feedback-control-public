import { ForbiddenError, ValidationError } from "../errors/applicationErrors";
import { authorize } from "./policyEngine/policyEngine";
import type {
  DomainStateProbe,
  PilotFullAccessGrant,
  PolicyEngineProviders,
  TargetRef,
} from "./policyEngine/types";
import { PILOT_PROFILES } from "./providers/pilot";

/**
 * Serviço de administração do Pilot Full Access (F4-07, Issue #94). Contrato
 * fechado D1–D18 / Q1–Q9. Sem migration/RLS/SECURITY DEFINER: core testável
 * com event sink in-memory.
 *
 * Concessão/revogação são ATOS ADMINISTRATIVOS autorizados pelo Policy Engine
 * via capability `pilot_full_access.grant` (D10): não pertence ao ADMIN
 * automaticamente, não deriva de cargo/job_role/allowlist DEV, auto-concessão
 * é PROIBIDA, justificativa obrigatória, janela fechada (máx. 30 dias), sem
 * retroatividade e sem extensão in-place.
 */

/** Duração máxima de um grant D (D9/Q2): 30 dias. */
export const PILOT_MAX_DURATION_DAYS = 30;

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Eventos de auditoria da origem D (D14): granted/revoked/relinquished. */
export type PilotAuditEvent =
  | { kind: "granted"; grant: PilotFullAccessGrant; timestamp: Date }
  | {
      kind: "revoked";
      grant: PilotFullAccessGrant;
      revokedBy: string;
      revokedAt: Date;
      motive: string;
    }
  | {
      kind: "relinquished";
      grant: PilotFullAccessGrant;
      relinquishedBy: string;
      at: Date;
    };

/** Event sink de auditoria (in-memory test double / future store). */
export type PilotAuditSink = (event: PilotAuditEvent) => void;

export interface ConcessaoPilotInput {
  organizationId: string;
  grantedByUserProfileId: string;
  beneficiaryUserProfileId: string;
  justification: string;
  validFrom: Date;
  validTo: Date;
  profileVersion: string;
  providers: PolicyEngineProviders;
  domainState: DomainStateProbe;
  /** Data de contexto/concessão (usada no authorize e como createdAt). */
  date: Date;
  /** Âncora concreta no tenant para o authorize administrativo (tipo pilot-eligible). */
  authorizationTarget: TargetRef;
  grantId?: string;
  audit?: PilotAuditSink;
}

function justificativaValida(justification: string): boolean {
  return justification.trim() !== "";
}

export function concederPilotFullAccess(
  input: ConcessaoPilotInput
): PilotFullAccessGrant {
  // justificativa obrigatória
  if (!justificativaValida(input.justification)) throw new ValidationError();
  // D14/D5: auto-concessão proibida
  if (input.grantedByUserProfileId === input.beneficiaryUserProfileId) {
    throw new ValidationError();
  }
  // D9/D12: janela fechada válida
  if (!(input.validTo > input.validFrom)) throw new ValidationError();
  // D9/Q2: duração máxima 30 dias
  if (
    input.validTo.getTime() - input.validFrom.getTime() >
    PILOT_MAX_DURATION_DAYS * MS_PER_DAY
  ) {
    throw new ValidationError();
  }
  // D10: retroativo proibido (validFrom não pode ser anterior à concessão)
  if (input.validFrom.getTime() < input.date.getTime()) {
    throw new ValidationError();
  }
  // D1/D16: profileVersion suportado (fechado)
  if (!Object.prototype.hasOwnProperty.call(PILOT_PROFILES, input.profileVersion)) {
    throw new ValidationError();
  }

  // D10: concessão autorizada pelo Policy Engine (capability de concessão).
  authorize(
    {
      actor: {
        actorId: input.grantedByUserProfileId,
        organizationId: input.organizationId,
      },
      capability: "pilot_full_access.grant",
      target: input.authorizationTarget,
      context: { date: input.date },
      domainState: input.domainState,
    },
    input.providers
  );

  const grant: PilotFullAccessGrant = {
    id: input.grantId ?? crypto.randomUUID(),
    organizationId: input.organizationId,
    beneficiaryUserProfileId: input.beneficiaryUserProfileId,
    grantedByUserProfileId: input.grantedByUserProfileId,
    justification: input.justification.trim(),
    validFrom: input.validFrom,
    validTo: input.validTo,
    status: "active",
    profileVersion: input.profileVersion,
    createdAt: input.date,
    version: 0,
  };

  input.audit?.({ kind: "granted", grant, timestamp: input.date });

  return grant;
}

export interface RevogacaoPilotInput {
  grant: PilotFullAccessGrant;
  revokedByUserProfileId: string;
  motive: string;
  providers: PolicyEngineProviders;
  domainState: DomainStateProbe;
  date: Date;
  authorizationTarget: TargetRef;
  audit?: PilotAuditSink;
}

export function revogarPilotFullAccess(
  input: RevogacaoPilotInput
): PilotFullAccessGrant {
  const { grant } = input;

  if (grant.status !== "active") throw new ValidationError();
  if (!justificativaValida(input.motive)) throw new ValidationError();

  // D12: o CONCEDENTE pode revogar; outro ator precisa da capability apropriada.
  if (input.revokedByUserProfileId !== grant.grantedByUserProfileId) {
    authorize(
      {
        actor: {
          actorId: input.revokedByUserProfileId,
          organizationId: grant.organizationId,
        },
        capability: "pilot_full_access.grant",
        target: input.authorizationTarget,
        context: { date: input.date },
        domainState: input.domainState,
      },
      input.providers
    );
  }

  const revoked: PilotFullAccessGrant = {
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

export interface RenunciaPilotInput {
  grant: PilotFullAccessGrant;
  beneficiaryUserProfileId: string;
  date: Date;
  audit?: PilotAuditSink;
}

/** Renúncia voluntária (D12): somente o próprio beneficiário; efeito imediato. */
export function renunciarPilotFullAccess(
  input: RenunciaPilotInput
): PilotFullAccessGrant {
  const { grant } = input;

  if (grant.status !== "active") throw new ValidationError();
  if (input.beneficiaryUserProfileId !== grant.beneficiaryUserProfileId) {
    throw new ForbiddenError();
  }

  const relinquished: PilotFullAccessGrant = {
    ...grant,
    status: "revoked",
    revokedAt: input.date,
    revokedBy: input.beneficiaryUserProfileId,
    revocationMotive: "renúncia voluntária",
  };

  input.audit?.({
    kind: "relinquished",
    grant: relinquished,
    relinquishedBy: input.beneficiaryUserProfileId,
    at: input.date,
  });

  return relinquished;
}
