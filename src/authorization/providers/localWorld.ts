import type { Colaborador } from "../../types/Colaborador";
import type { PolicyEngineProviders, TargetRef } from "../policyEngine/types";

/**
 * Providers do mundo atual (F4-03, D7 = A): adapters sobre o domínio local
 * (localStorage/seed). Sem cargo/job_role em runtime: a decisão do fluxo-piloto
 * (metas próprias) usa somente capability `goal.write` + scope SELF + relação
 * "alvo = próprio colaborador", sem consultar `funcao`.
 *
 * Quando os domínios migrarem para Supabase (F5), estes adapters são trocados
 * por adapters Supabase com a MESMA interface (D1).
 */

export const LOCAL_ORGANIZATION_ID = "organizacao-sintetica-local";

export function criarProvidersMundoLocal(
  actor: Colaborador,
  colaboradores: readonly Colaborador[]
): PolicyEngineProviders {
  const actorId = String(actor.matricula);

  return {
    identity: {
      isProfileActive: (id) => {
        // A identidade do próprio ator vem da sessão (confiável).
        if (id === actorId) return actor.status !== "DESLIGADO";
        const encontrado = colaboradores.find(
          (item) => String(item.matricula) === id
        );
        return encontrado !== undefined && encontrado.status !== "DESLIGADO";
      },
      // Mundo local: um único tenant sintético com vínculo implícito.
      isMembershipActive: () => true,
    },
    capabilities: {
      // Piloto: capability de ação sobre metas próprias (SELF) é concedida a
      // todo colaborador ativo — sem derivação de cargo.
      hasCapability: (_id, _org, capability) => capability === "goal.write",
    },
    scopes: {
      getActiveScopes: () => ["SELF"],
    },
    targets: {
      resolveTargetTenant: (target: TargetRef) => {
        if (target.type !== "collaborator") return undefined;
        // O próprio ator é um alvo conhecido (identidade da sessão).
        if (target.id === actorId) return LOCAL_ORGANIZATION_ID;
        const existe = colaboradores.some(
          (item) => String(item.matricula) === target.id
        );
        return existe ? LOCAL_ORGANIZATION_ID : undefined;
      },
    },
    relations: {
      isTargetInScope: (_id, _org, scope, target: TargetRef) => {
        if (scope !== "SELF" || target.type !== "collaborator") return false;
        return target.id === actorId;
      },
    },
  };
}
