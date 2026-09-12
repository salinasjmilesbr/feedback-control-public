import type { Colaborador } from "../../types/Colaborador";
import { simulacaoDevPermitida } from "../../config/ambiente";
import { criarProvidersMundoFuncional } from "../mundoFuncional";
import type { PolicyEngineProviders, TargetRef } from "../policyEngine/types";

/**
 * Providers do mundo atual (F4-03, D7 = A): adapters sobre o domínio local
 * (localStorage/seed). Sem cargo/job_role em runtime: a decisão do fluxo-piloto
 * (metas próprias) usa somente capability `goal.write` + scope SELF + relação
 * "alvo = próprio colaborador", sem consultar `funcao`.
 *
 * ## F5-08 P6 (correção da auditoria): o mundo sintético é DEV
 *
 * §19.1: `localWorld` fica "mantido **apenas** para DEV/teste, atrás do gate de
 * modo DEV já existente; **nunca** em produção". Fora do contexto DEV do Vite a
 * fábrica abaixo devolve o mundo SOBERANO VAZIO (nenhuma capability ⇒ DENY,
 * fail-closed): o `organization_id` sintético e o `isMembershipActive: () => true`
 * não são autoridade de produção.
 *
 * Quando os domínios migrarem para Supabase (F5), os adapters soberanos passam a
 * alimentar `criarProvidersMundoFuncional` (D1) e a injeção de bindings explícitos.
 */

export const LOCAL_ORGANIZATION_ID = "organizacao-sintetica-local";

export function criarProvidersMundoLocal(
  actor: Colaborador,
  colaboradores: readonly Colaborador[]
): PolicyEngineProviders {
  if (!simulacaoDevPermitida) {
    // Produção: sem projeção soberana o mundo é VAZIO — nenhuma capability é
    // concedida por fixture/estrutura local (fail-closed).
    return criarProvidersMundoFuncional({ actor, colaboradores: [] });
  }

  return mundoLocalSintetico(actor, colaboradores);
}

/** Mundo sintético de DEV/teste (fixture) — NUNCA autoridade de produção. */
function mundoLocalSintetico(
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
      // ACHADO 1 (F5-05): scopes da CAPABILITY avaliada. Este mundo concede
      // apenas `goal.write` (fluxo próprio) — SELF; qualquer outra capability
      // não recebe alcance algum (sem herança entre capabilities).
      getActiveScopes: (_id, _org, capability) =>
        capability === "goal.write" ? ["SELF"] : [],
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
