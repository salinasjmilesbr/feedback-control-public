import type { Capability } from "../Capability.ts";
import { capabilityConhecida } from "../catalogoCapabilities.ts";
import type {
  ExceptionalProvider,
  PilotFullAccessProvider,
  PolicyEngineProviders,
  ScopeType,
  TargetRef,
  TemporaryProvider,
} from "../policyEngine/types.ts";
import {
  isCollegiateAssigned,
  isEvaluationAssigned,
} from "./assigned.ts";
import type {
  CollegiateMembership,
  EvaluationResponsibility,
  EvaluationTargetResolver,
} from "./assigned.ts";

/**
 * F5-05 — providers REAIS do Policy Engine (D5, D6, D11, D16, D19, D20).
 *
 * Recebem dados SOBERANOS já resolvidos server-side, por operação:
 *   - identidade/perfil/membership (F5-01/F5-03);
 *   - capabilities × scopes dos resolvers canônicos da F5-04 (D5);
 *   - alvos de scope resolvidos pelos contratos F4-02/F3-07 (relation/target);
 *   - tenant do alvo derivado do RECURSO carregado (D6).
 *
 * Nenhuma capability/scope/tenant vem do cliente. Código de capability
 * desconhecido ⇒ `false` (DENY, fail-closed — D14 F5-04). Sem cache entre
 * requisições: os dados valem apenas para a operação corrente (D10/D17).
 *
 * As origens B (temporária), C (excepcional) e D (pilot) permanecem INDEPENDENTES
 * e são apenas repassadas quando injetadas pelo caminho server-side (D11).
 */

export interface CapabilityComEscopos {
  readonly capability: Capability;
  readonly scopes: readonly ScopeType[];
  /** Unidades-alvo quando o scope é ORGANIZATIONAL_UNIT (F4-02). */
  readonly unitIds?: readonly string[];
}

export interface AlvoEscopoResolvido {
  readonly collaboratorId: string | null;
  readonly positionId: string | null;
}

export interface EscopoResolvido {
  readonly scope: ScopeType;
  readonly unitId: string | null;
  readonly alvos: readonly AlvoEscopoResolvido[];
}

export interface DadosAssignedSoberanos {
  readonly collegiateMemberships: readonly CollegiateMembership[];
  readonly evaluationResponsibilities: readonly EvaluationResponsibility[];
  readonly resolveEvaluationTarget: EvaluationTargetResolver;
}

export interface DadosProvidersReais {
  /** `auth.uid()` — identidade soberana (nunca do cliente). */
  readonly actorId: string;
  /**
   * Colaborador vinculado (F5-02) do ator na organização — usado nas relações
   * que comparam identidade ORGANIZACIONAL (ASSIGNED / F3-08-09). `null`
   * (ADMIN sem vínculo) ⇒ ASSIGNED falha fechado.
   */
  readonly collaboratorId: string | null;
  /** Organização validada contra membership ativa (F5-03). */
  readonly organizationId: string;
  readonly perfilAtivo: boolean;
  readonly membershipAtiva: boolean;
  /** Capabilities efetivas (códigos canônicos F5-04) e seus scopes. */
  readonly capabilities: readonly CapabilityComEscopos[];
  /** Alvos por scope, resolvidos server-side (F4-02). */
  readonly escoposResolvidos: readonly EscopoResolvido[];
  /** Alvo da decisão corrente (o único cujo tenant é conhecido). */
  readonly alvo: TargetRef;
  /** Tenant do alvo, derivado do recurso carregado (D6). */
  readonly tenantDoAlvo: string | undefined;
  /** ASSIGNED: fontes soberanas F3-08/09 quando carregadas. */
  readonly assigned?: DadosAssignedSoberanos;
  /** Origens independentes (D11) — repassadas sem alteração. */
  readonly temporary?: TemporaryProvider;
  readonly exceptional?: ExceptionalProvider;
  readonly pilot?: PilotFullAccessProvider;
}

function mesmosAlvos(a: TargetRef, b: TargetRef): boolean {
  return a.type === b.type && a.id === b.id;
}

function alvoEscopoCorresponde(alvo: AlvoEscopoResolvido, target: TargetRef): boolean {
  if (target.type === "collaborator") {
    return alvo.collaboratorId !== null && alvo.collaboratorId === target.id;
  }
  if (target.type === "position") {
    return alvo.positionId !== null && alvo.positionId === target.id;
  }
  return false;
}

/**
 * Constrói os providers reais a partir de dados soberanos. Síncrono: toda a
 * leitura server-side acontece ANTES, por operação (sem I/O dentro do engine).
 */
export function criarProvidersReais(dados: DadosProvidersReais): PolicyEngineProviders {
  const { actorId, organizationId } = dados;

  const scopesAtivos: ScopeType[] = Array.from(
    new Set(dados.capabilities.flatMap((item) => item.scopes))
  );

  return {
    identity: {
      isProfileActive: (id) => id === actorId && dados.perfilAtivo,
      isMembershipActive: (id, org) =>
        id === actorId && org === organizationId && dados.membershipAtiva,
    },
    capabilities: {
      hasCapability: (id, org, capability) => {
        if (id !== actorId || org !== organizationId) return false;
        // Fail-closed do vocabulário (F5-04 D14): código fora do catálogo ⇒ DENY.
        if (!capabilityConhecida(capability)) return false;
        return dados.capabilities.some((item) => item.capability === capability);
      },
    },
    scopes: {
      getActiveScopes: (id, org) =>
        id === actorId && org === organizationId ? scopesAtivos : [],
    },
    targets: {
      resolveTargetTenant: (target) =>
        mesmosAlvos(target, dados.alvo) ? dados.tenantDoAlvo : undefined,
    },
    relations: {
      isTargetInScope: (_id, org, scope, target, _date, cycleId) => {
        if (org !== organizationId) return false;

        if (scope === "ORGANIZATION") {
          // Alcance do tenant: o engine já validou o tenant do alvo (passo 4).
          return dados.tenantDoAlvo === organizationId;
        }

        if (scope === "ASSIGNED") {
          const assigned = dados.assigned;
          // ASSIGNED compara identidade ORGANIZACIONAL: o colaborador vinculado
          // do ator (nunca auth.uid(), que não é id de colaborador). Sem vínculo
          // ou sem fonte soberana ⇒ fail-closed.
          const colaboradorDoAtor = dados.collaboratorId;
          if (!assigned || !colaboradorDoAtor) return false;
          const alvoAvaliativo = assigned.resolveEvaluationTarget(
            target,
            cycleId,
            organizationId
          );
          if (!alvoAvaliativo) return false;
          return (
            isCollegiateAssigned(
              colaboradorDoAtor,
              alvoAvaliativo,
              assigned.collegiateMemberships
            ) ||
            isEvaluationAssigned(
              colaboradorDoAtor,
              alvoAvaliativo,
              assigned.evaluationResponsibilities
            )
          );
        }

        // SELF / DIRECT_REPORTS / DESCENDANTS / ORGANIZATIONAL_UNIT: alvos
        // pré-resolvidos server-side pelos contratos F4-02/F3.
        const escopo = dados.escoposResolvidos.find((item) => item.scope === scope);
        if (!escopo) return false;
        return escopo.alvos.some((alvo) => alvoEscopoCorresponde(alvo, target));
      },
    },
    ...(dados.temporary ? { temporary: dados.temporary } : {}),
    ...(dados.exceptional ? { exceptional: dados.exceptional } : {}),
    ...(dados.pilot ? { pilot: dados.pilot } : {}),
  };
}
