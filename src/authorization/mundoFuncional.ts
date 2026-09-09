import type { Colaborador } from "../types/Colaborador";
import type { Capability } from "./Capability";
import { canonicalizarCapability } from "./canonical";
import type {
  PolicyEngineProviders,
  ScopeType,
  TargetRef,
} from "./policyEngine/types";

/**
 * Mundo funcional local pré-F5 (F4-09, D3/Q2): providers do Policy Engine
 * derivados dos DADOS (cadeia `gestorDiretoMatricula` + colegiado), NUNCA de
 * cargo/`funcao`. Capabilities vêm de um binding DEV-only EXPLÍCITO (transitório;
 * a F5 substitui por membership → access_role → capability).
 *
 * Não simula RLS: a fronteira de aplicação é o engine; o RLS real das tabelas
 * funcionais virá na F5.
 */

export const LOCAL_ORGANIZATION_ID = "organizacao-sintetica-local";

export type DevCapabilityBindings = ReadonlyMap<number, ReadonlySet<Capability>>;

/** Capabilities de AÇÃO concedidas a todo colaborador ativo (fluxos próprios). */
const CAPABILIDADES_SELF: readonly Capability[] = ["goal.write", "evaluation.read"];

/** Ações de gestão de cadeia (gerente/raiz) — scope DESCENDANTS. */
const CAPABILIDADES_GESTAO: readonly Capability[] = [
  "collaborator.create",
  "collaborator.edit",
  "collaborator.read",
  "cycle.read",
  "cycle.manage",
  "cycle.cancel",
  "cycle.reopen",
  "cycle.period.correct",
  "evaluation.read",
  "evaluation.create",
  "evaluation.write",
  "evaluation.cancel",
  "evaluation.reopen",
  "goal.read",
  "goal.approve",
  "observation.read",
  "observation.create",
  "observation.edit",
  "observation.delete",
  "report.read",
  "settings.manage",
];

/** Ações de coordenação (gestor de 1º nível) — scope DIRECT_REPORTS. */
const CAPABILIDADES_COORDENACAO: readonly Capability[] = [
  "collaborator.read",
  "cycle.read",
  "evaluation.read",
  "evaluation.create",
  "evaluation.write",
  "goal.read",
  "goal.approve",
  "observation.read",
  "observation.create",
  "observation.edit",
  "observation.delete",
  "report.read",
];

/** Ações de colegiado — scope ASSIGNED (somente o avaliado atribuído). */
const CAPABILIDADES_COLEGIADO: readonly Capability[] = [
  "evaluation.read",
  "evaluation.write",
];

function subordinadosDiretos(
  gestor: Colaborador,
  colaboradores: readonly Colaborador[]
): Colaborador[] {
  return colaboradores.filter(
    (item) => item.gestorDiretoMatricula === gestor.matricula
  );
}

function descendentes(
  gestor: Colaborador,
  colaboradores: readonly Colaborador[]
): Set<number> {
  const resultado = new Set<number>();
  const fila: number[] = [gestor.matricula];
  const visitados = new Set<number>();
  while (fila.length > 0) {
    const atual = fila.shift();
    if (atual === undefined || visitados.has(atual)) continue;
    visitados.add(atual);
    for (const item of colaboradores) {
      if (item.gestorDiretoMatricula === atual && !resultado.has(item.matricula)) {
        resultado.add(item.matricula);
        fila.push(item.matricula);
      }
    }
  }
  return resultado;
}

/** O ator está na cadeia de gestão ACIMA do alvo (ancestral via gestorDireto)? */
export function estaNaCadeiaDeGestao(
  ator: Colaborador,
  alvo: Colaborador,
  colaboradores: readonly Colaborador[]
): boolean {
  const porMatricula = new Map(colaboradores.map((c) => [c.matricula, c]));
  let atual: Colaborador | undefined = alvo;
  const visitados = new Set<number>();
  while (atual?.gestorDiretoMatricula) {
    const gestor = atual.gestorDiretoMatricula;
    if (visitados.has(gestor)) return false;
    visitados.add(gestor);
    if (gestor === ator.matricula) return true;
    atual = porMatricula.get(gestor);
  }
  return false;
}

/**
 * Binding DEV-only EXPLÍCITO derivado da ESTRUTURA (nunca de `funcao`):
 *   - raiz (sem gestor) → conjunto de gestão;
 *   - gestor de 1º nível com superior → conjunto de coordenação;
 *   - demais ativos → fluxos próprios (SELF).
 */
export function derivarBindingsDev(
  colaboradores: readonly Colaborador[]
): DevCapabilityBindings {
  const bindings = new Map<number, Set<Capability>>();
  const raiz = colaboradores.filter((c) => !c.gestorDiretoMatricula);

  for (const colaborador of colaboradores) {
    if (colaborador.status === "DESLIGADO") continue;
    const caps = new Set<Capability>(CAPABILIDADES_SELF);

    const ehRaiz = raiz.some((r) => r.matricula === colaborador.matricula);
    const temSubordinados = colaboradores.some(
      (item) => item.gestorDiretoMatricula === colaborador.matricula
    );
    const ehColegiado = colaboradores.some((item) =>
      item.avaliadoresColegiadoMatriculas?.includes(colaborador.matricula)
    );

    if (ehRaiz) {
      CAPABILIDADES_GESTAO.forEach((c) => caps.add(c));
    } else if (temSubordinados) {
      CAPABILIDADES_COORDENACAO.forEach((c) => caps.add(c));
    }
    if (ehColegiado) {
      CAPABILIDADES_COLEGIADO.forEach((c) => caps.add(c));
    }

    bindings.set(colaborador.matricula, caps);
  }
  return bindings;
}

export interface MundoFuncionalInput {
  actor: Colaborador;
  colaboradores: readonly Colaborador[];
  bindingsDev?: DevCapabilityBindings;
}

export function criarProvidersMundoFuncional(
  input: MundoFuncionalInput
): PolicyEngineProviders {
  const { actor, colaboradores } = input;
  const actorId = String(actor.matricula);
  const porMatricula = new Map(colaboradores.map((c) => [c.matricula, c]));
  const bindings = input.bindingsDev ?? derivarBindingsDev(colaboradores);

  const meusSubordinados = subordinadosDiretos(actor, colaboradores);
  const meusDescendentes = descendentes(actor, colaboradores);
  const ehColegiadoDeAlguem = colaboradores.some((c) =>
    c.avaliadoresColegiadoMatriculas?.includes(actor.matricula)
  );

  function colaboradorAlvo(id: string): Colaborador | undefined {
    const matricula = Number(id);
    if (!Number.isInteger(matricula)) return undefined;
    return porMatricula.get(matricula);
  }

  const ehRaiz = !actor.gestorDiretoMatricula;
  const scopes: ScopeType[] = ["SELF"];
  if (meusSubordinados.length > 0) scopes.push("DIRECT_REPORTS");
  if (meusDescendentes.size > 0) scopes.push("DESCENDANTS");
  if (ehColegiadoDeAlguem) scopes.push("ASSIGNED");
  if (ehRaiz) scopes.push("ORGANIZATION");

  return {
    identity: {
      isProfileActive: (id) => {
        if (id === actorId) return actor.status !== "DESLIGADO";
        const alvo = colaboradorAlvo(id);
        return alvo !== undefined && alvo.status !== "DESLIGADO";
      },
      isMembershipActive: () => true, // tenant sintético único (pré-F5)
    },
    capabilities: {
      hasCapability: (_id, _org, capability) => {
        const canonica = canonicalizarCapability(capability);
        const caps = bindings.get(actor.matricula);
        if (!caps) return false;
        // Fluxos próprios (SELF) sempre disponíveis a ativo.
        if (CAPABILIDADES_SELF.includes(canonica)) return true;
        return caps.has(canonica);
      },
    },
    scopes: {
      getActiveScopes: () => scopes,
    },
    targets: {
      resolveTargetTenant: (target: TargetRef) => {
        if (target.type === "collaborator") {
          if (target.id === actorId) return LOCAL_ORGANIZATION_ID;
          return colaboradorAlvo(target.id) ? LOCAL_ORGANIZATION_ID : undefined;
        }
        // Alvos de domínio (ciclo) pertencem ao tenant sintético único (pré-F5).
        if (target.type === "cycle") return LOCAL_ORGANIZATION_ID;
        return undefined;
      },
    },
    relations: {
      isTargetInScope: (_id, _org, scope, target) => {
        // ORGANIZATION cobre SOMENTE alvos de domínio (ciclo), nunca
        // colaboradores: evita que a gestão de cadeia (raiz) vaze para relações
        // de avaliação/meta/observação (D6/D10).
        if (scope === "ORGANIZATION") return target.type !== "collaborator";
        if (target.type !== "collaborator") return false;
        if (target.id === actorId && scope === "SELF") return true;

        const alvo = colaboradorAlvo(target.id);
        if (!alvo) return false;

        if (scope === "DIRECT_REPORTS") {
          return alvo.gestorDiretoMatricula === actor.matricula;
        }
        if (scope === "DESCENDANTS") {
          return meusDescendentes.has(alvo.matricula);
        }
        if (scope === "ASSIGNED") {
          return (
            alvo.avaliadoresColegiadoMatriculas?.includes(actor.matricula) ?? false
          );
        }
        return false;
      },
    },
  };
}
