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
import type { MetaRecursoContext } from "../resourceContextReal.ts";
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
 *
 * F5-10 P4 (§9.1/§10, D8/D9/D14/D25): o alvo `goal` tem relações PRÓPRIAS —
 * SELF pelo **dono** da meta e DESCENDANTS/DIRECT_REPORTS pelos **aprovadores
 * CONGELADOS** da avaliação original do dono (recebidos em `metaDoAlvo`).
 * Estrutura/hierarquia viva NUNCA é consultada para meta, e `goal.approve` não
 * implica `goal.write` (capabilities distintas ⇒ alcances distintos).
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
  /**
   * F5-06/F5-10 P4: colaborador DONO do recurso alvo — o AVALIADO quando o alvo
   * é uma avaliação (`evaluations.evaluated_collaborator_id`) e o TITULAR quando
   * o alvo é uma meta (`evaluation_goals.collaborator_id`).
   * `null`/ausente ⇒ a relação SELF do dono NÃO é satisfeita.
   */
  readonly donoDoAlvo?: string | null;
  /**
   * F5-10 P4 (§9.1, D14/D25): bloco SOBERANO da meta — aprovadores CONGELADOS
   * da avaliação ORIGINAL do dono. Ausente ⇒ nenhuma relação de aprovação é
   * satisfeita (fail-closed). NUNCA se lê estrutura viva para o alvo meta.
   */
  readonly metaDoAlvo?: MetaRecursoContext;
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
 * F5-06 (§8.1): o recurso AVALIAÇÃO é autorizável, mas o alvo é
 * `{ type: "evaluation", id }`. A relação (SELF/DIRECT_REPORTS/DESCENDANTS/
 * ORGANIZATIONAL_UNIT) é definida sobre o COLABORADOR AVALIADO — dono derivado
 * da linha real da avaliação —, nunca sobre o id da avaliação. Este predicado
 * traduz o alvo de avaliação para o colaborador avaliado já em escopo.
 */
function alvoAvaliacaoCorresponde(
  alvo: AlvoEscopoResolvido,
  target: TargetRef,
  donoDoAlvo: string | null
): boolean {
  if (target.type !== "evaluation") return false;
  return (
    donoDoAlvo !== null &&
    alvo.collaboratorId !== null &&
    alvo.collaboratorId === donoDoAlvo
  );
}

/**
 * F5-10 P4 (§10, D8/D9): a META é autorizável pelo alvo `{ type: "goal", id }`,
 * mas a relação SELF é definida sobre o TITULAR da meta
 * (`evaluation_goals.collaborator_id`, dono derivado da linha real) — o id da
 * meta nunca define relação. Mesmo padrão de `alvoAvaliacaoCorresponde`.
 */
function alvoMetaCorresponde(
  alvo: AlvoEscopoResolvido,
  target: TargetRef,
  donoDoAlvo: string | null
): boolean {
  if (target.type !== "goal") return false;
  return (
    donoDoAlvo !== null &&
    alvo.collaboratorId !== null &&
    alvo.collaboratorId === donoDoAlvo
  );
}

/** Alvos pré-resolvidos de um scope (vazio ⇒ relação não satisfeita). */
function alvosDoEscopo(
  dados: DadosProvidersReais,
  scope: ScopeType
): readonly AlvoEscopoResolvido[] {
  return dados.escoposResolvidos.find((item) => item.scope === scope)?.alvos ?? [];
}

/** Id de colaborador congelado válido (não vazio) — fail-closed no resto. */
function idCongeladoValido(valor: string | undefined): valor is string {
  return typeof valor === "string" && valor.trim().length > 0;
}

/**
 * F5-10 P4 (§9.1, D14/D25) — relações do alvo META, TODAS sobre a
 * materialização **CONGELADA** da avaliação do dono (nunca hierarquia viva):
 *   - `SELF` ⇒ o colaborador vinculado ao ator é o **DONO** da meta;
 *   - `DESCENDANTS` ⇒ é o **GERENTE** congelado (`GESTAO_CADEIA` da ocorrência
 *     original da avaliação do dono);
 *   - `DIRECT_REPORTS` ⇒ é o **COORDENADOR** congelado (`GESTAO_DIRETA`
 *     original e distinta da cadeia);
 *   - `ASSIGNED` e os demais escopos ⇒ `false` (fail-closed): aprovar meta não
 *     decorre de delegação avaliativa, de alcance de unidade nem de tenant.
 */
function metaNoEscopoDoAtor(
  scope: ScopeType,
  target: TargetRef,
  dados: DadosProvidersReais
): boolean {
  if (scope === "SELF") {
    const dono = dados.donoDoAlvo ?? null;
    if (dono === null) return false;
    return alvosDoEscopo(dados, scope).some((alvo) =>
      alvoMetaCorresponde(alvo, target, dono)
    );
  }

  if (scope === "DESCENDANTS" || scope === "DIRECT_REPORTS") {
    const colaboradorDoAtor = dados.collaboratorId;
    if (!colaboradorDoAtor) return false;
    const congelados = dados.metaDoAlvo?.aprovadoresCongelados;
    if (!congelados) return false;
    const aprovadorCongelado =
      scope === "DESCENDANTS" ? congelados.gerente : congelados.coordenador;
    return (
      idCongeladoValido(aprovadorCongelado) &&
      aprovadorCongelado === colaboradorDoAtor
    );
  }

  return false;
}

/**
 * Constrói os providers reais a partir de dados soberanos. Síncrono: toda a
 * leitura server-side acontece ANTES, por operação (sem I/O dentro do engine).
 */
export function criarProvidersReais(dados: DadosProvidersReais): PolicyEngineProviders {
  const { actorId, organizationId } = dados;

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
      /**
       * ACHADO 1 (F5-05): devolve os scopes EXCLUSIVAMENTE da capability
       * avaliada (F4-02: scope pertence à atribuição da capability). Nunca
       * devolve a união de scopes das demais capabilities do ator — uma
       * capability não herda alcance de outra.
       */
      getActiveScopes: (id, org, capability) => {
        if (id !== actorId || org !== organizationId) return [];
        const item = dados.capabilities.find((c) => c.capability === capability);
        if (!item) return [];
        return Array.from(new Set(item.scopes));
      },
    },
    targets: {
      resolveTargetTenant: (target) =>
        mesmosAlvos(target, dados.alvo) ? dados.tenantDoAlvo : undefined,
    },
    relations: {
      isTargetInScope: (_id, org, scope, target, _date, cycleId) => {
        if (org !== organizationId) return false;

        // F5-10 P4 (§9.1/D14/D25): o alvo META tem relações PRÓPRIAS,
        // materializadas de forma CONGELADA na avaliação original do dono.
        // Estrutura viva NUNCA é consultada — inclusive `ORGANIZATION` e
        // `ASSIGNED` são negados para meta (fail-closed).
        if (target.type === "goal") {
          return metaNoEscopoDoAtor(scope, target, dados);
        }

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
        // F5-06: para o alvo AVALIAÇÃO a relação é lida sobre o COLABORADOR
        // AVALIADO (dono do recurso) — o id da avaliação não define relação.
        const escopo = dados.escoposResolvidos.find((item) => item.scope === scope);
        if (!escopo) return false;
        return escopo.alvos.some(
          (alvo) =>
            alvoEscopoCorresponde(alvo, target) ||
            alvoAvaliacaoCorresponde(alvo, target, dados.donoDoAlvo ?? null)
        );
      },
    },
    ...(dados.temporary ? { temporary: dados.temporary } : {}),
    ...(dados.exceptional ? { exceptional: dados.exceptional } : {}),
    ...(dados.pilot ? { pilot: dados.pilot } : {}),
  };
}
