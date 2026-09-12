import type { DomainStateProbe, TargetRef } from "./policyEngine/types.ts";

/**
 * F5-05 (D6, D8, D19, D22) — ResourceContext real (+ F5-09 P6 para CICLO).
 *
 * Representa o RECURSO CARREGADO de fonte soberana server-side, com tenant
 * derivado do próprio recurso (nunca do caller) e os atributos necessários à
 * decisão de scope. Produz o `TargetRef` + `domainState` do Policy Engine.
 *
 * Limite do mundo híbrido (D19): só existem tipos de recurso SOBERANOS — os que
 * possuem persistência server-side com `organization_id`. Depois da F5-06 a
 * AVALIAÇÃO passou a ser recurso soberano (`evaluations` no PostgreSQL — D10/
 * §8.1) e depois da **F5-09 P5 o CICLO passou a ser recurso soberano**
 * (`evaluation_cycles`: schema P1, RLS own-tenant/leitura em P5): o tenant é
 * derivado da LINHA REAL carregada na fronteira confiável e o `domainState`
 * reflete o estado real do recurso. Domínios ainda mantidos apenas em
 * `localStorage` (meta/observação) NÃO produzem ResourceContext soberano e são
 * recusados aqui (fail-closed), assim como alvos sintéticos globais (D22).
 */

/** Tipos de recurso com fonte soberana server-side (F3 + F5-06 + F5-09 P5). */
export const TIPOS_RECURSO_SOBERANOS = [
  "collaborator",
  "position",
  "organizational_unit",
  "evaluation",
  "cycle",
] as const;

export type TipoRecursoSoberano = (typeof TIPOS_RECURSO_SOBERANOS)[number];

/** Alvos NÃO autorizáveis pelo Policy Engine (legado/transitório ou global). */
export const TIPOS_RECURSO_NAO_SOBERANOS = ["goal", "observation"] as const;

export interface ResourceStructure {
  readonly collaboratorId: string | null;
  readonly positionId: string | null;
  readonly unitId: string | null;
}

export interface ResourceContext {
  readonly kind: TipoRecursoSoberano;
  readonly target: TargetRef;
  /** Tenant DO RECURSO — obrigatório/não-null (D22). */
  readonly organizationId: string;
  /** Owner/subject quando aplicável (avaliado/dono/colaborador). */
  readonly ownerCollaboratorId: string | null;
  readonly structure: ResourceStructure;
  readonly domainState: DomainStateProbe;
  readonly cycleId?: string;
}

/** Recurso carregado de fonte soberana server-side (pré-contexto). */
export interface RecursoSoberanoCarregado {
  readonly kind: TipoRecursoSoberano;
  readonly id: string;
  readonly organizationId: string;
  readonly ownerCollaboratorId?: string | null;
  readonly positionId?: string | null;
  readonly unitId?: string | null;
  readonly cycleId?: string;
  /** F5-06/F5-09 P6: estado real do recurso (usado pelo probe de domínio). */
  readonly status?: string;
  /** F5-06: colaborador AVALIADO (dono do recurso de avaliação). */
  readonly evaluatedCollaboratorId?: string | null;
}

export type MotivoRecursoInvalido =
  | "TARGET_NAO_SOBERANO"
  | "IDENTIFICADOR_AUSENTE"
  | "IDENTIFICADOR_INVALIDO"
  | "TENANT_AUSENTE"
  | "TENANT_DIVERGENTE";

export type ResultadoMontagemRecurso =
  | { readonly ok: true; readonly resourceContext: ResourceContext }
  | { readonly ok: false; readonly motivo: MotivoRecursoInvalido };

export function ehTipoRecursoSoberano(tipo: string): tipo is TipoRecursoSoberano {
  return (TIPOS_RECURSO_SOBERANOS as readonly string[]).includes(tipo);
}

/**
 * Alvo sintético/global (ex.: `{ type: "cycle", id: "global" }`) — nunca é
 * autorização real (D22) e nunca satisfaz o engine.
 */
export function ehAlvoSinteticoGlobal(target: TargetRef): boolean {
  return target.id === "global";
}

/**
 * F5-09 P6 — formato do identificador CANÔNICO de ciclo (`evaluation_cycles.id`).
 *
 * Mesmo formato aceito pela coluna `uuid` do PostgreSQL e pelo contrato de
 * colaboradores (`ehUuid`): a identidade do ciclo é o UUID, nunca `ano`/`numero`
 * nem rótulo textual (`"global"`, `"ciclo-1"`). A checagem é defesa em
 * profundidade da fronteira — o id real vem da linha soberana carregada.
 */
const FORMATO_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function ehIdentificadorCanonico(valor: unknown): valor is string {
  return typeof valor === "string" && FORMATO_UUID.test(valor.trim());
}

/**
 * F5-09 P6 — o alvo é um CICLO com identificador canônico válido? Um alvo de
 * ciclo malformado/sintético nunca é autorizável (D22 + §8).
 */
export function ehAlvoCicloCanonico(target: TargetRef): boolean {
  return target.type === "cycle" && ehIdentificadorCanonico(target.id);
}

/**
 * Probe de domínio dos recursos ESTRUTURAIS: a estrutura F3 não define
 * predicado de lifecycle para leitura/edição de colaborador (matriz F4-09).
 * Recursos de domínio com estado declaram o PRÓPRIO probe: avaliação (F5-06) e
 * ciclo (F5-09 P6, `estadoDominioCiclo`); meta/observação seguem fora do limite
 * soberano (D19) e não chegam a montar contexto aqui.
 */
export const domainStateEstrutural: DomainStateProbe = { allows: () => true };

function normalizarObrigatorio(valor: unknown): string | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  return limpo.length > 0 ? limpo : null;
}

function normalizarOpcional(valor: unknown): string | null {
  return normalizarObrigatorio(valor);
}

/**
 * Monta o `ResourceContext` de um recurso soberano carregado server-side.
 *
 * Fail-closed:
 * - alvo de tipo não soberano (legado/global) ⇒ `TARGET_NAO_SOBERANO`;
 * - id ausente ⇒ `IDENTIFICADOR_AUSENTE`;
 * - id de CICLO fora do formato canônico ⇒ `IDENTIFICADOR_INVALIDO` (P6);
 * - tenant ausente ⇒ `TENANT_AUSENTE`;
 * - tenant divergente da organização validada do ator ⇒ `TENANT_DIVERGENTE`.
 */
export function montarResourceContextSoberano(entrada: {
  readonly recurso: RecursoSoberanoCarregado;
  /** Organização validada do ator (defesa em profundidade; o engine também confere). */
  readonly organizationIdEsperada: string;
  readonly domainState?: DomainStateProbe;
}): ResultadoMontagemRecurso {
  const recurso = entrada.recurso;
  if (!recurso || !ehTipoRecursoSoberano(String(recurso.kind))) {
    return { ok: false, motivo: "TARGET_NAO_SOBERANO" };
  }

  const id = normalizarObrigatorio(recurso.id);
  if (!id) {
    return { ok: false, motivo: "IDENTIFICADOR_AUSENTE" };
  }

  // F5-09 P6: o ciclo tem identidade UUID canônica; qualquer outro rótulo
  // (ano/numero, "global", id sintético) é recusado ANTES da decisão.
  if (recurso.kind === "cycle" && !ehIdentificadorCanonico(id)) {
    return { ok: false, motivo: "IDENTIFICADOR_INVALIDO" };
  }

  const organizationId = normalizarObrigatorio(recurso.organizationId);
  if (!organizationId) {
    return { ok: false, motivo: "TENANT_AUSENTE" };
  }

  const organizationIdEsperada = normalizarObrigatorio(entrada.organizationIdEsperada);
  if (!organizationIdEsperada || organizationId !== organizationIdEsperada) {
    return { ok: false, motivo: "TENANT_DIVERGENTE" };
  }

  const target: TargetRef = { type: recurso.kind, id };

  // F5-06 (§8.1): para o recurso de AVALIAÇÃO o dono é o colaborador AVALIADO
  // (`evaluations.evaluated_collaborator_id`), nunca o caller. É esse vínculo
  // que permite ao engine resolver SELF/DIRECT_REPORTS/DESCENDANTS/ASSIGNED
  // sobre o alvo `{ type: "evaluation" }`.
  const ownerCollaboratorId =
    normalizarOpcional(recurso.ownerCollaboratorId) ??
    (recurso.kind === "evaluation"
      ? normalizarOpcional(recurso.evaluatedCollaboratorId)
      : null);

  // F5-09 P6: para o recurso CICLO, o ciclo do contexto é o PRÓPRIO ciclo.
  const cycleId =
    normalizarOpcional(recurso.cycleId) ?? (recurso.kind === "cycle" ? id : null);

  return {
    ok: true,
    resourceContext: {
      kind: recurso.kind,
      target,
      organizationId,
      ownerCollaboratorId,
      structure: {
        collaboratorId: ownerCollaboratorId,
        positionId: normalizarOpcional(recurso.positionId),
        unitId: normalizarOpcional(recurso.unitId),
      },
      domainState: entrada.domainState ?? domainStateEstrutural,
      ...(cycleId ? { cycleId } : {}),
    },
  };
}

/**
 * Recusa alvos não autorizáveis pelo engine (global/legado/inválido). Usado pelo
 * enforcement antes de qualquer montagem (D19/D22 + F5-09 P6 §8).
 */
export function motivoAlvoNaoAutorizavel(target: TargetRef): MotivoRecursoInvalido | null {
  if (ehAlvoSinteticoGlobal(target)) return "TARGET_NAO_SOBERANO";
  if (!ehTipoRecursoSoberano(target.type)) return "TARGET_NAO_SOBERANO";
  // P6: ciclo só é autorizável com o UUID canônico (nunca ano/numero/rótulo).
  if (target.type === "cycle" && !ehIdentificadorCanonico(target.id)) {
    return "TARGET_NAO_SOBERANO";
  }
  return null;
}
