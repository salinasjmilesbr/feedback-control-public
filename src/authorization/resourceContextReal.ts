import type { DomainStateProbe, TargetRef } from "./policyEngine/types.ts";

/**
 * F5-05 (D6, D8, D19, D22) — ResourceContext real
 * (+ F5-09 P6 para CICLO, + F5-10 P4 para META, + F5-11 P3 para OBSERVAÇÃO).
 *
 * Representa o RECURSO CARREGADO de fonte soberana server-side, com tenant
 * derivado do próprio recurso (nunca do caller) e os atributos necessários à
 * decisão de scope. Produz o `TargetRef` + `domainState` do Policy Engine.
 *
 * Limite do mundo híbrido (D19): só existem tipos de recurso SOBERANOS — os que
 * possuem persistência server-side com `organization_id`. Depois da F5-06 a
 * AVALIAÇÃO passou a ser recurso soberano (`evaluations` no PostgreSQL — D10/
 * §8.1), depois da **F5-09 P5 o CICLO** (`evaluation_cycles`: schema P1, RLS
 * own-tenant/leitura em P5), depois da **F5-10 P4 a META**
 * (`evaluation_goals`: schema P1, RPCs P2/P3) e depois da **F5-11 P3 a
 * OBSERVAÇÃO** (`evaluation_observations`: schema P1, RPCs P2): o tenant é
 * derivado da LINHA REAL carregada na fronteira confiável e o `domainState`
 * reflete o estado real do recurso. Com a F5-11 P3 **nenhum** tipo autorizável
 * permanece só em `localStorage` — a lista de tipos NÃO soberanos fica VAZIA e
 * alvos sintéticos globais seguem recusados aqui (fail-closed, D22).
 */

/**
 * Tipos de recurso com fonte soberana server-side
 * (F3 + F5-06 + F5-09 P5 + F5-10 P4 + F5-11 P3).
 */
export const TIPOS_RECURSO_SOBERANOS = [
  "collaborator",
  "position",
  "organizational_unit",
  "evaluation",
  // F5-10 P4 (D8): `goal` é soberano ANTES de `cycle` — o gate estático da
  // F5-09 P6 exige `"cycle",` imediatamente antes de `] as const`.
  "goal",
  // F5-11 P3 (§17.1): a OBSERVAÇÃO deixa de ser tipo legado não soberano e passa
  // a SOBERANA (`evaluation_observations`). A entrada é inserida ANTES do ciclo
  // para preservar o invariante da guarda estática da F5-09 P6: o ciclo continua
  // sendo o ÚLTIMO item da lista, imediatamente antes do fechamento.
  "observation",
  "cycle",
] as const;

export type TipoRecursoSoberano = (typeof TIPOS_RECURSO_SOBERANOS)[number];

/**
 * Alvos NÃO autorizáveis pelo Policy Engine (legado/transitório ou global).
 *
 * F5-11 P3 (§17.1): a OBSERVAÇÃO era o ÚLTIMO domínio mantido apenas em
 * `localStorage` e passou a recurso SOBERANO — a lista fica VAZIA. Ela é mantida
 * (vazia) como ponto único de extensão e como guarda explícita de que nenhum
 * tipo legado remanesce: qualquer reintrodução de domínio não soberano precisa
 * aparecer AQUI e ser justificada no desenho.
 */
export const TIPOS_RECURSO_NAO_SOBERANOS = [] as const;

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
  /** Owner/subject quando aplicável (avaliado/dono/colaborador-alvo). */
  readonly ownerCollaboratorId: string | null;
  readonly structure: ResourceStructure;
  readonly domainState: DomainStateProbe;
  readonly cycleId?: string;
  /**
   * F5-10 P4: bloco soberano do recurso META (dono, ciclo, estado e ids
   * CONGELADOS de aprovador). É o único caminho pelo qual os providers reais
   * conhecem as relações de aprovação da meta — nunca estrutura viva.
   */
  readonly meta?: MetaRecursoContext;
  /**
   * F5-11 P3: bloco soberano do recurso OBSERVAÇÃO (comunicado, exclusão, estado
   * do ciclo e AUTORIA derivada na fronteira — D3/D5). É o único caminho pelo
   * qual os providers reais conhecem o autor da observação; ele nunca é lido de
   * `usuarioAtual`/payload.
   */
  readonly observacao?: ObservacaoRecursoContext;
}

/**
 * F5-10 P4 (§9.1, D14/D25) — ids CONGELADOS dos aprovadores da meta.
 *
 * Derivados da avaliação **ORIGINAL** do dono (`evaluation_participants`:
 * `GESTAO_CADEIA` = GERENTE; `GESTAO_DIRETA`, quando distinta da cadeia =
 * COORDENADOR), resolvidos server-side na fronteira confiável. Nunca são lidos
 * de estrutura/hierarquia viva.
 */
export interface AprovadoresCongeladosMeta {
  readonly gerente?: string;
  readonly coordenador?: string;
}

/** F5-10 P4: materialização SOBERANA do recurso META (pré-contexto). */
export interface MetaRecursoContext {
  readonly status: string | null;
  /** Excluída (soft delete) ⇒ somente leitura histórica (§10). */
  readonly excluida: boolean;
  /** Status da LINHA soberana do ciclo da meta (mutação exige `ATIVO`). */
  readonly cicloStatus: string | null;
  readonly aprovadoresCongelados?: AprovadoresCongeladosMeta;
}

/**
 * F5-11 P3 (§7.3/§8, D3/D5/D7/D11/D12) — materialização SOBERANA do recurso
 * OBSERVAÇÃO (pré-contexto).
 *
 * Os quatro fatos vêm da LINHA SOBERANA carregada server-side
 * (`evaluation_observations`): `comunicado` (D7), `excluida` (D8), o status da
 * linha do CICLO (D12 — mutação exige `ATIVO`) e a AUTORIA derivada de
 * `auth.uid()` na fronteira (D3), que é o que sustenta a D5: **somente o autor**
 * edita, exclui, revoga a exclusão e altera o comunicado. `authorCollaboratorId`
 * é `null` quando não há vínculo de colaborador derivável na fronteira — sem
 * autoria PROVADA ninguém é autor (fail-closed).
 */
export interface ObservacaoRecursoContext {
  readonly comunicado: boolean;
  /**
   * Excluída (soft delete) ⇒ leitura histórica; a REVOGAÇÃO da exclusão é
   * `observation.edit` do autor (§8, linha 9) — o probe de estado não a nega.
   */
  readonly excluida: boolean;
  /** Status da LINHA soberana do ciclo da observação (mutação exige `ATIVO`). */
  readonly cicloStatus: string | null;
  /** AUTOR soberano (`author_collaborator_id`) ou `null` se não derivável (D3). */
  readonly authorCollaboratorId: string | null;
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
  /**
   * F5-10 P4/F5-11 P3: a META ou a OBSERVAÇÃO foi excluída (soft delete) —
   * leitura histórica apenas; na observação o autor pode REVOGAR a exclusão.
   */
  readonly excluida?: boolean;
  /** F5-10 P4/F5-11 P3: status da linha SOBERANA do ciclo (meta/observação). */
  readonly cicloStatus?: string;
  /** F5-10 P4: ids congelados dos aprovadores (§9.1/D14). */
  readonly aprovadoresCongelados?: AprovadoresCongeladosMeta;
  /** F5-11 P3: a observação está marcada como COMUNICADA (fato soberano, D7). */
  readonly comunicado?: boolean;
  /** F5-11 P3: autor SOBERANO da observação (`author_collaborator_id`, D3/D5). */
  readonly authorCollaboratorId?: string | null;
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
 * Vale igualmente para a META (F5-10 P4) e para a OBSERVAÇÃO (F5-11 P3).
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
 * Recursos de domínio com estado declaram o PRÓPRIO probe: avaliação (F5-06),
 * ciclo (F5-09 P6, `estadoDominioCiclo`), meta (F5-10 P4, `estadoDominioMeta`) e
 * observação (F5-11 P3, `estadoDominioObservacao` — consumido pelo adaptador
 * funcional). Aqui só chegam os recursos SEM predicado de estado próprio.
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
 * - id de CICLO, META ou OBSERVAÇÃO fora do formato canônico ⇒
 *   `IDENTIFICADOR_INVALIDO` (P6/D8/F5-11 P3);
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

  // F5-09 P6 + F5-10 P4 + F5-11 P3: o CICLO, a META e a OBSERVAÇÃO têm
  // identidade UUID canônica (`evaluation_cycles.id`, `evaluation_goals.id` e
  // `evaluation_observations.id`); qualquer outro rótulo (ano/numero, "global",
  // id sintético, `g-1`, `o-1`) é recusado ANTES da decisão.
  if (
    (recurso.kind === "cycle" ||
      recurso.kind === "goal" ||
      recurso.kind === "observation") &&
    !ehIdentificadorCanonico(id)
  ) {
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

  // F5-06 (§8.1) + F5-10 P4 (§10) + F5-11 P3 (§8): o dono do recurso é o
  // colaborador AVALIADO (`evaluations.evaluated_collaborator_id`), o TITULAR da
  // meta (`evaluation_goals.collaborator_id`) ou o colaborador-ALVO da observação
  // (`evaluation_observations.collaborator_id`) — nunca o caller. É esse vínculo
  // que permite ao engine resolver SELF/DIRECT_REPORTS/DESCENDANTS/ASSIGNED sobre
  // o alvo do recurso (`evaluation`/`goal`) e sobre a observação do alvo.
  const ownerCollaboratorId =
    normalizarOpcional(recurso.ownerCollaboratorId) ??
    (recurso.kind === "evaluation"
      ? normalizarOpcional(recurso.evaluatedCollaboratorId)
      : null);

  // F5-09 P6: para o recurso CICLO, o ciclo do contexto é o PRÓPRIO ciclo;
  // F5-10 P4: para a META, é o `cycle_id` da LINHA soberana da meta;
  // F5-11 P3: para a OBSERVAÇÃO, é o `cycle_id` da LINHA soberana da observação.
  const cycleId =
    normalizarOpcional(recurso.cycleId) ?? (recurso.kind === "cycle" ? id : null);

  // F5-10 P4 (§10): bloco SOBERANO da meta — estado real, exclusão e os ids
  // CONGELADOS de aprovador (D14/D25). Nada aqui é declarado pelo cliente.
  const meta: MetaRecursoContext | null =
    recurso.kind === "goal"
      ? {
          status: normalizarOpcional(recurso.status),
          excluida: recurso.excluida === true,
          cicloStatus: normalizarOpcional(recurso.cicloStatus),
          ...(recurso.aprovadoresCongelados
            ? { aprovadoresCongelados: recurso.aprovadoresCongelados }
            : {}),
        }
      : null;

  // F5-11 P3 (§7.3/§8): bloco SOBERANO da observação — comunicado e exclusão
  // (fatos da LINHA), status do CICLO e a AUTORIA derivada na fronteira (D3).
  // É o que sustenta a D5 no caminho soberano; nada aqui vem do cliente.
  const observacao: ObservacaoRecursoContext | null =
    recurso.kind === "observation"
      ? {
          comunicado: recurso.comunicado === true,
          excluida: recurso.excluida === true,
          cicloStatus: normalizarOpcional(recurso.cicloStatus),
          authorCollaboratorId: normalizarOpcional(recurso.authorCollaboratorId),
        }
      : null;

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
      ...(meta ? { meta } : {}),
      ...(observacao ? { observacao } : {}),
    },
  };
}

/**
 * Recusa alvos não autorizáveis pelo engine (global/legado/inválido). Usado pelo
 * enforcement antes de qualquer montagem
 * (D19/D22 + F5-09 P6 §8 + F5-10 P4 D8 + F5-11 P3 §8).
 */
export function motivoAlvoNaoAutorizavel(target: TargetRef): MotivoRecursoInvalido | null {
  if (ehAlvoSinteticoGlobal(target)) return "TARGET_NAO_SOBERANO";
  if (!ehTipoRecursoSoberano(target.type)) return "TARGET_NAO_SOBERANO";
  // P6/F5-10 P4/F5-11 P3: ciclo, meta e observação só são autorizáveis com o
  // UUID canônico (nunca ano/numero/rotulo nem `g-1`/`o-1`).
  if (
    (target.type === "cycle" ||
      target.type === "goal" ||
      target.type === "observation") &&
    !ehIdentificadorCanonico(target.id)
  ) {
    return "TARGET_NAO_SOBERANO";
  }
  return null;
}
