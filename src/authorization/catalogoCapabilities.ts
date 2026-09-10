import type { Capability } from "./Capability";

/**
 * Espelho literal do catálogo canônico de capabilities (F5-04, D14/D6).
 *
 * O BANCO (`public.capabilities`, não-deprecado) é a fonte canônica dos códigos
 * concedíveis; este array é o espelho TS literal usado para o TESTE DE PARIDADE
 * DB↔TS (`.ai/architecture-rules.md` / docs/F5-04 §14). Nenhum mapper fuzzy/
 * permissivo em runtime: código desconhecido ⇒ DENY.
 *
 * Catálogo canônico (29) — espelho de docs/F4-09 §6.3 + F5-04 D14:
 *   colaborador/ciclo/avaliação/meta/observação (ações granulares),
 *   report.read, settings.manage, membership.read/manage, access_role.manage,
 *   org.structure.manage, org.catalog.manage, exceptional_access.grant,
 *   pilot_full_access.grant.
 */
export const CAPABILIDADES_CANONICAS: readonly Capability[] = [
  "collaborator.create",
  "collaborator.edit",
  "collaborator.read",
  "cycle.read",
  "cycle.manage",
  "cycle.cancel",
  "cycle.reopen",
  "cycle.period.correct",
  "evaluation.create",
  "evaluation.read",
  "evaluation.write",
  "evaluation.cancel",
  "evaluation.reopen",
  "goal.read",
  "goal.write",
  "goal.approve",
  "observation.read",
  "observation.create",
  "observation.edit",
  "observation.delete",
  "report.read",
  "settings.manage",
  "membership.read",
  "membership.manage",
  "access_role.manage",
  "org.structure.manage",
  "org.catalog.manage",
  "exceptional_access.grant",
  "pilot_full_access.grant",
];

/**
 * Plano ADMINISTRATIVO de controle (F5-04, D15): capabilities que administram o
 * próprio mecanismo (membership.manage, access_role.manage) e as de C/D
 * (exceptional_access.grant, pilot_full_access.grant). Fora do catálogo
 * concedível por role — nunca transitam por access_role.
 */
export const CAPABILIDADES_NAO_CONCEDIVEIS_VIA_ROLE: readonly Capability[] = [
  "membership.manage",
  "access_role.manage",
  "exceptional_access.grant",
  "pilot_full_access.grant",
];

/**
 * Códigos coarse DEPRECADOS (F5-04, D14): reconciliados às ações granulares
 * canônicas, mantidos fisicamente no banco (sem remoção), nunca concedidos por
 * role nova. Não pertencem ao tipo `Capability` (são códigos legados de banco).
 */
export const CAPABILIDADES_DEPRECIADAS: readonly string[] = [
  "collaborator.manage",
  "observation.write",
];

const SET_CANONICAS: ReadonlySet<string> = new Set(CAPABILIDADES_CANONICAS);

/**
 * Fronteira DB→engine (F5-04, D14): resolve um código de capability vindo do
 * banco para a capability canônica do engine. Sem tradução fuzzy/permissiva:
 * código desconhecido, deprecado ou fora do catálogo canônico ⇒ `undefined`
 * (DENY, fail-closed).
 */
export function capabilityCanonica(code: string): Capability | undefined {
  return SET_CANONICAS.has(code) ? (code as Capability) : undefined;
}

/**
 * Verdadeiro se o código pertence ao catálogo canônico (não-deprecado) — usado
 * como guard fail-closed para capability desconhecida.
 */
export function capabilityConhecida(code: string): boolean {
  return SET_CANONICAS.has(code);
}
