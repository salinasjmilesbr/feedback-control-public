import type { Capability } from "../Capability";
import type { ScopeType } from "./types";

/**
 * MAPA LEGADO (F4-03, D18 = A ajustada) — artefato TEMPORÁRIO de migração e
 * regressão. NUNCA é consultado pelo policy engine em runtime e NUNCA concede
 * autorização. Documenta a regra antiga (por cargo/função) e a capability +
 * scope/relação equivalente, para testes espelhados e rastreabilidade.
 *
 * Quando todos os fluxos migrarem, este mapa pode ser removido sem alterar o
 * comportamento do engine.
 */
export interface LegacyAuthorizationMapping {
  legacyRule: string;
  capability: Capability;
  scope: ScopeType;
  note: string;
}

export const LEGACY_AUTHORIZATION_MAP: readonly LegacyAuthorizationMapping[] = [
  {
    legacyRule: "goal.create.own (perfilPossuiFluxosPropriosAtuais)",
    capability: "goal.write",
    scope: "SELF",
    note: "Fluxo-piloto migrado na F4-03 (MinhasMetas/metaStorage).",
  },
  {
    legacyRule: "goal.edit.own (perfilPossuiFluxosPropriosAtuais)",
    capability: "goal.write",
    scope: "SELF",
    note: "Fluxo-piloto migrado na F4-03.",
  },
  {
    legacyRule: "goal.delete.own (perfilPossuiFluxosPropriosAtuais)",
    capability: "goal.write",
    scope: "SELF",
    note: "Fluxo-piloto migrado na F4-03.",
  },
  {
    legacyRule: "goal.progress.own (perfilPossuiFluxosPropriosAtuais)",
    capability: "goal.write",
    scope: "SELF",
    note: "Fluxo-piloto migrado na F4-03.",
  },
  {
    legacyRule: "goal.finalize.own (perfilPossuiFluxosPropriosAtuais)",
    capability: "goal.write",
    scope: "SELF",
    note: "Fluxo-piloto migrado na F4-03.",
  },
  {
    legacyRule: "goal.approve.manager (actor.funcao === GERENTE)",
    capability: "goal.approve",
    scope: "DESCENDANTS",
    note: "Migração na F4-04 (aplicação ampla de hierarchy + assignments).",
  },
  {
    legacyRule: "goal.approve.coordinator (actor.funcao === COORDENADOR)",
    capability: "goal.approve",
    scope: "DIRECT_REPORTS",
    note: "Migração na F4-04.",
  },
];
