/**
 * F5-07 — contrato TRANSPORTÁVEL do caminho soberano de colaboradores.
 *
 * Este módulo é compartilhado pela Edge Function `colaboradores` (Deno) e pelo
 * cliente (repositório/porta). Ele fixa:
 *
 * - as 15 operações da espinha (§2) e o payload EXATO de cada uma — snake_case,
 *   porque é o formato que atravessa a fronteira;
 * - a validação de FORMA (nunca de autoridade) das entradas;
 * - a capability exigida por operação (D10/§9.2) — nenhuma capability nova.
 *
 * Invariantes (I1–I14, §7):
 * - `organization_id` é INTENÇÃO: a Edge a REVALIDA contra a membership ativa
 *   do ator (divergência ⇒ `FORBIDDEN`);
 * - `matricula` é INTENÇÃO: resolvida server-side para `collaborators.id`;
 *   ambígua ou ausente ⇒ `NOT_FOUND` (nunca escolhe arbitrariamente);
 * - `actor_user_profile_id` NUNCA vem do corpo — a identidade vem do JWT;
 * - `capability`/`role`/`scope` do cliente não são prova de nada.
 *
 * O código público de erro (`CodigoPublico`) é o já fechado na F5-06: o mesmo
 * tipo de `src/infrastructure/supabase/avaliacoes/contrato.ts`, replicado aqui
 * para manter o módulo autocontido na Edge (bundling).
 */

/** Operações suportadas pelo caminho soberano de colaboradores (§2). */
export type OperacaoColaborador =
  | "collaborator.listar"
  | "collaborator.obter"
  | "collaborator.criar"
  | "collaborator.editar"
  | "collaborator.identificador.definir"
  | "collaborator.status.alterar"
  | "colaborador.ocupacao.definir"
  | "colaborador.ocupacao.encerrar"
  | "estrutura.reporting.definir"
  | "estrutura.reporting.encerrar"
  | "estrutura.responsabilidade.definir"
  | "estrutura.responsabilidade.encerrar"
  | "estrutura.sucessao.registrar"
  | "colaborador.historico.listar"
  | "colaborador.catalogo.bootstrap"
  // F5-08 P3 — estrutura organizacional (org.structure.manage)
  | "estrutura.unidade.criar"
  | "estrutura.unidade.renomear"
  | "estrutura.unidade.encerrar"
  | "estrutura.unidade.parent.definir"
  | "estrutura.unidade.parent.encerrar"
  | "estrutura.posicao.criar"
  | "estrutura.posicao.encerrar"
  | "estrutura.colegiado.definir"
  | "estrutura.colegiado.encerrar"
  // F5-08 P3 — catálogos (org.catalog.manage)
  | "catalogo.cargo.criar"
  | "catalogo.cargo.renomear"
  | "catalogo.cargo.status.alterar"
  | "catalogo.senioridade.criar"
  | "catalogo.senioridade.renomear"
  | "catalogo.senioridade.status.alterar";

/** Códigos públicos estáveis (F0-05) — nunca a mensagem crua do banco. */
export type CodigoPublico =
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "INVALID_INPUT"
  | "INTERNAL"
  | "NOT_AUTHORIZED"
  | "METHOD_NOT_ALLOWED";

/**
 * Gate de cada operação (§9.2, D10/D19):
 * - `funcional`: Policy Engine (`authorize()`) com ActorContext/ResourceContext
 *   reais — `collaborator.read/create/edit`;
 * - `administrativo`: plano administrativo (D19) — a capability exigida
 *   (`org.structure.manage` / `org.catalog.manage`) é verificada nas
 *   capabilities efetivas do ator resolvidas server-side. A ALLOWLIST FUNCIONAL
 *   do engine NUNCA é usada para essas operações.
 */
export type TipoGate = "funcional" | "administrativo";

export interface DefinicaoOperacao {
  readonly gate: TipoGate;
  /**
   * Capability de referência: `Capability` canônica no gate funcional;
   * exigida no plano administrativo.
   */
  readonly capability: string;
}

export const DEFINICAO_POR_OPERACAO: Readonly<Record<OperacaoColaborador, DefinicaoOperacao>> =
  {
    "collaborator.listar": { gate: "funcional", capability: "collaborator.read" },
    "collaborator.obter": { gate: "funcional", capability: "collaborator.read" },
    "collaborator.criar": { gate: "funcional", capability: "collaborator.create" },
    "collaborator.editar": { gate: "funcional", capability: "collaborator.edit" },
    "collaborator.identificador.definir": {
      gate: "funcional",
      capability: "collaborator.edit",
    },
    "collaborator.status.alterar": { gate: "funcional", capability: "collaborator.edit" },
    "colaborador.historico.listar": { gate: "funcional", capability: "collaborator.read" },
    // D19: estrutura/catálogo permanecem no plano administrativo server-side.
    "colaborador.ocupacao.definir": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "colaborador.ocupacao.encerrar": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "estrutura.reporting.definir": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "estrutura.reporting.encerrar": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "estrutura.responsabilidade.definir": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "estrutura.responsabilidade.encerrar": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "estrutura.sucessao.registrar": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "colaborador.catalogo.bootstrap": {
      gate: "administrativo",
      capability: "org.catalog.manage",
    },
    // F5-08 (D19): estrutura/colegiado no plano administrativo com
    // `org.structure.manage`; catálogos com `org.catalog.manage`.
    "estrutura.unidade.criar": { gate: "administrativo", capability: "org.structure.manage" },
    "estrutura.unidade.renomear": { gate: "administrativo", capability: "org.structure.manage" },
    "estrutura.unidade.encerrar": { gate: "administrativo", capability: "org.structure.manage" },
    "estrutura.unidade.parent.definir": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "estrutura.unidade.parent.encerrar": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "estrutura.posicao.criar": { gate: "administrativo", capability: "org.structure.manage" },
    "estrutura.posicao.encerrar": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "estrutura.colegiado.definir": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "estrutura.colegiado.encerrar": {
      gate: "administrativo",
      capability: "org.structure.manage",
    },
    "catalogo.cargo.criar": { gate: "administrativo", capability: "org.catalog.manage" },
    "catalogo.cargo.renomear": { gate: "administrativo", capability: "org.catalog.manage" },
    "catalogo.cargo.status.alterar": {
      gate: "administrativo",
      capability: "org.catalog.manage",
    },
    "catalogo.senioridade.criar": { gate: "administrativo", capability: "org.catalog.manage" },
    "catalogo.senioridade.renomear": {
      gate: "administrativo",
      capability: "org.catalog.manage",
    },
    "catalogo.senioridade.status.alterar": {
      gate: "administrativo",
      capability: "org.catalog.manage",
    },
  };

export const OPERACOES_COLABORADOR: readonly OperacaoColaborador[] = Object.keys(
  DEFINICAO_POR_OPERACAO
) as readonly OperacaoColaborador[];

export function ehOperacaoColaborador(valor: unknown): valor is OperacaoColaborador {
  return (
    typeof valor === "string" && (OPERACOES_COLABORADOR as readonly string[]).includes(valor)
  );
}

/** Gate funcional (Policy Engine) de uma operação. */
export function ehOperacaoFuncional(operacao: OperacaoColaborador): boolean {
  return DEFINICAO_POR_OPERACAO[operacao].gate === "funcional";
}

/** Subconjunto de operações que usam a allowlist funcional do Policy Engine. */
export const OPERACOES_FUNCIONAIS: readonly OperacaoColaborador[] = OPERACOES_COLABORADOR.filter(
  ehOperacaoFuncional
);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function ehUuid(valor: unknown): valor is string {
  return typeof valor === "string" && UUID.test(valor.trim());
}

/**
 * Identificador NEUTRO para alvos autorizáveis derivados server-side (o UUID
 * real é resolvido na fronteira e substitui este valor ANTES da decisão). Não é
 * identidade: um alvo neutro sem recurso carregado é NEGADO pelo engine
 * (fail-closed).
 */
export const ID_NEUTRO = "00000000-0000-0000-0000-000000000000";

export interface AlvoColaborador {
  readonly type: "collaborator";
  readonly id: string;
}

/** Filtros opcionais de `collaborator.listar` (busca é substring, não padrão). */
export interface FiltrosListarColaboradores {
  readonly status?: string;
  readonly unit_id?: string;
  readonly busca?: string;
}

export interface EntradaListar {
  readonly organization_id: string;
  readonly data_referencia?: string;
  readonly filtros?: FiltrosListarColaboradores;
}

export interface EntradaObter {
  readonly organization_id: string;
  /** UUID do colaborador (identidade canônica). */
  readonly collaborator_id?: string;
  /** Matrícula como INTENÇÃO — resolvida server-side; ambígua ⇒ NOT_FOUND. */
  readonly matricula?: string;
  readonly data_referencia?: string;
  readonly alvo: AlvoColaborador;
}

export interface EntradaCriar {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly full_name: string;
  readonly email: string;
  readonly matricula: string;
  readonly admission_date?: string;
  readonly status_inicial?: "active" | "leave";
  readonly alvo: AlvoColaborador;
}

export interface EntradaEditar {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly collaborator_id: string;
  readonly full_name?: string;
  readonly email?: string;
  readonly admission_date?: string;
  readonly expected_version: number;
  readonly alvo: AlvoColaborador;
}

export interface EntradaDefinirIdentificador {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly collaborator_id: string;
  readonly nova_matricula: string;
  readonly vigencia: string;
  readonly motivo: string;
  readonly expected_version: number;
  readonly alvo: AlvoColaborador;
}

export interface EntradaAlterarStatus {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly collaborator_id: string;
  readonly novo_status: "active" | "leave" | "inactive";
  readonly vigencia: string;
  readonly motivo: string;
  readonly cycle_scope?: "CICLO_ATUAL_E_POSTERIORES" | "SOMENTE_CICLOS_POSTERIORES";
  readonly reference_cycle_id?: string;
  readonly expected_version: number;
  readonly alvo: AlvoColaborador;
}

export interface EntradaDefinirOcupacao {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly collaborator_id: string;
  readonly position_id: string;
  readonly vigencia: string;
  readonly motivo: string;
  readonly cycle_scope?: "CICLO_ATUAL_E_POSTERIORES" | "SOMENTE_CICLOS_POSTERIORES";
  readonly reference_cycle_id?: string;
}

export interface EntradaEncerrarOcupacao {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly collaborator_id: string;
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaDefinirReporting {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly subordinate_position_id: string;
  readonly manager_position_id: string;
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaEncerrarReporting {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly subordinate_position_id: string;
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaDefinirResponsabilidade {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly position_id: string;
  readonly substitute_collaborator_id: string;
  readonly responsibility_type: "operational" | "evaluative" | "operational_evaluative";
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaEncerrarResponsabilidade {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly responsibility_id: string;
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaRegistrarSucessao {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly responsibility_ids: readonly string[];
  readonly succession_date: string;
  readonly motivo: string;
}

/** Item do catálogo mínimo (D16) — apenas job_roles e seniority_levels. */
export interface ItemCatalogoJobRole {
  readonly code: string;
  readonly name: string;
}

export interface EntradaBootstrapCatalogo {
  readonly organization_id: string;
  readonly operation_id: string;
  readonly catalogo: {
    readonly job_roles: readonly ItemCatalogoJobRole[];
    readonly seniority_levels: readonly string[];
  };
}

/** F5-08 P3 — payload público (camelCase) das operações de ESTRUTURA. */
export interface EntradaUnidadeCriar {
  readonly organization_id: string;
  readonly operationId: string;
  readonly nome: string;
  readonly validFrom: string;
  readonly motivo: string;
}

export interface EntradaUnidadeRenomear {
  readonly organization_id: string;
  readonly operationId: string;
  readonly unidadeId: string;
  readonly nome: string;
  readonly expectedVersion: number;
  readonly motivo: string;
}

export interface EntradaUnidadeEncerrar {
  readonly organization_id: string;
  readonly operationId: string;
  readonly unidadeId: string;
  readonly validTo: string;
  readonly expectedVersion: number;
  readonly motivo: string;
}

export interface EntradaUnidadeParentDefinir {
  readonly organization_id: string;
  readonly operationId: string;
  readonly unidadeId: string;
  /** `null` representa RAIZ (ausência de relação). */
  readonly parentUnitId: string | null;
  readonly validFrom: string;
  readonly motivo: string;
}

export interface EntradaUnidadeParentEncerrar {
  readonly organization_id: string;
  readonly operationId: string;
  readonly unidadeId: string;
  readonly validTo: string;
  readonly motivo: string;
}

export interface EntradaPosicaoCriar {
  readonly organization_id: string;
  readonly operationId: string;
  readonly unidadeId: string;
  readonly jobRoleId: string;
  /** Senioridade é opcional no contrato da posição. */
  readonly seniorityLevelId: string | null;
  readonly validFrom: string;
  readonly motivo: string;
}

export interface EntradaPosicaoEncerrar {
  readonly organization_id: string;
  readonly operationId: string;
  readonly posicaoId: string;
  readonly validTo: string;
  readonly expectedVersion: number;
  readonly motivo: string;
}

export interface EntradaColegiadoDefinir {
  readonly organization_id: string;
  readonly operationId: string;
  /** Colaborador AVALIADO ao qual a configuração se aplica. */
  readonly collaboratorId: string;
  /** 0..N membros EXPLÍCITOS; lista vazia = "sem colegiado" explícito. */
  readonly memberCollaboratorIds: readonly string[];
  readonly validFrom: string;
  readonly motivo: string;
}

export interface EntradaColegiadoEncerrar {
  readonly organization_id: string;
  readonly operationId: string;
  readonly collaboratorId: string;
  readonly validTo: string;
  readonly motivo: string;
}

/** F5-08 P3 — payload público (camelCase) dos CATÁLOGOS. */
export interface EntradaCargoCriar {
  readonly organization_id: string;
  readonly operationId: string;
  readonly nome: string;
  /** Rótulo estável opcional (D5); nunca autoridade. */
  readonly code: string | null;
  readonly motivo: string;
}

export interface EntradaCargoRenomear {
  readonly organization_id: string;
  readonly operationId: string;
  readonly jobRoleId: string;
  readonly nome: string;
  readonly expectedVersion: number;
  readonly motivo: string;
}

export interface EntradaCatalogoStatusAlterar {
  readonly organization_id: string;
  readonly operationId: string;
  readonly expectedVersion: number;
  readonly status: (typeof STATUS_CATALOGO)[number];
  readonly motivo: string;
}

export interface EntradaCargoStatusAlterar extends EntradaCatalogoStatusAlterar {
  readonly jobRoleId: string;
}

export interface EntradaSenioridadeCriar {
  readonly organization_id: string;
  readonly operationId: string;
  readonly nome: string;
  readonly motivo: string;
}

export interface EntradaSenioridadeRenomear {
  readonly organization_id: string;
  readonly operationId: string;
  readonly seniorityLevelId: string;
  readonly nome: string;
  readonly expectedVersion: number;
  readonly motivo: string;
}

export interface EntradaSenioridadeStatusAlterar extends EntradaCatalogoStatusAlterar {
  readonly seniorityLevelId: string;
}

export interface EntradaHistorico {
  readonly organization_id: string;
  readonly collaborator_id: string;
  readonly data_referencia?: string;
  readonly reference_cycle_id?: string;
  readonly alvo: AlvoColaborador;
}

/** Intenção validada por forma, específica de cada operação. */
export type EntradaColaborador =
  | EntradaListar
  | EntradaObter
  | EntradaCriar
  | EntradaEditar
  | EntradaDefinirIdentificador
  | EntradaAlterarStatus
  | EntradaDefinirOcupacao
  | EntradaEncerrarOcupacao
  | EntradaDefinirReporting
  | EntradaEncerrarReporting
  | EntradaDefinirResponsabilidade
  | EntradaEncerrarResponsabilidade
  | EntradaRegistrarSucessao
  | EntradaHistorico
  | EntradaBootstrapCatalogo
  | EntradaUnidadeCriar
  | EntradaUnidadeRenomear
  | EntradaUnidadeEncerrar
  | EntradaUnidadeParentDefinir
  | EntradaUnidadeParentEncerrar
  | EntradaPosicaoCriar
  | EntradaPosicaoEncerrar
  | EntradaColegiadoDefinir
  | EntradaColegiadoEncerrar
  | EntradaCargoCriar
  | EntradaCargoRenomear
  | EntradaCargoStatusAlterar
  | EntradaSenioridadeCriar
  | EntradaSenioridadeRenomear
  | EntradaSenioridadeStatusAlterar;

export type ResultadoValidacaoColaborador =
  | { readonly ok: true; readonly entrada: EntradaColaborador }
  | { readonly ok: false; readonly code: CodigoPublico; readonly message: string };

/**
 * Campos de identidade que o cliente NUNCA informa: a fronteira os deriva do
 * JWT verificado (mesma regra da F5-05/F5-06).
 */
const CAMPOS_PROIBIDOS = [
  "actor_id",
  "actor_user_profile_id",
  "user_profile_id",
  "ator",
  "capability",
  "role",
  "scope",
] as const;

const STATUS_INICIAIS = ["active", "leave"] as const;
const STATUS_COLABORADOR = ["active", "leave", "inactive"] as const;
const RESPONSABILIDADES = ["operational", "evaluative", "operational_evaluative"] as const;
const CICLO_ESCOPOS = ["CICLO_ATUAL_E_POSTERIORES", "SOMENTE_CICLOS_POSTERIORES"] as const;
/** Status dos catálogos (D17): inativação no lugar, nunca DELETE. */
const STATUS_CATALOGO = ["active", "disabled"] as const;

type StatusColaborador = (typeof STATUS_COLABORADOR)[number];
type StatusInicial = (typeof STATUS_INICIAIS)[number];
type ResponsabilidadeTipo = (typeof RESPONSABILIDADES)[number];
type CicloEscopo = (typeof CICLO_ESCOPOS)[number];

function registro(valor: unknown): Record<string, unknown> | null {
  if (typeof valor !== "object" || valor === null || Array.isArray(valor)) return null;
  return valor as Record<string, unknown>;
}

/** Texto obrigatório, com `trim`, sem vazio e com limite de tamanho. */
function texto(valor: unknown, max: number): string | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  if (limpo.length === 0 || limpo.length > max) return null;
  return limpo;
}

/**
 * Matrícula como INTENÇÃO: inteiro positivo, aceita em número ou texto.
 * Devolve a forma canônica em texto (o banco compara `business_code` textual).
 */
function matricula(valor: unknown): string | null {
  if (typeof valor === "number") {
    return Number.isInteger(valor) && valor > 0 ? String(valor) : null;
  }
  if (typeof valor === "string") {
    const limpo = valor.trim();
    return /^\d+$/.test(limpo) && Number(limpo) > 0 ? limpo : null;
  }
  return null;
}

/** Formato literal estrito: a interpretação/rotação de data é do banco. */
const FORMATO_DATA = /^\d{4}-\d{2}-\d{2}$/;
const FORMATO_INSTANTE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/;

function dataOuInstante(valor: unknown): string | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  if (FORMATO_DATA.test(limpo) || FORMATO_INSTANTE.test(limpo)) return limpo;
  return null;
}

/**
 * UUID OPCIONAL (nullable do contrato): ausente/null ⇒ `null`; presente e
 * inválido ⇒ `ok: false` (fail-closed). Nunca concede autoridade.
 */
function uuidOpcional(
  valor: unknown
): { readonly ok: true; readonly valor: string | null } | { readonly ok: false } {
  if (valor === undefined || valor === null) return { ok: true, valor: null };
  return ehUuid(valor) ? { ok: true, valor: valor as string } : { ok: false };
}

/**
 * Lista de UUIDs que ACEITA VAZIO: o colegiado é 0..N no contrato e lista
 * vazia é "sem colegiado" EXPLÍCITO (F3-08 D8), distinto de ausência de
 * configuração. A fronteira valida SOMENTE forma (array + UUIDs):
 * duplicidade, self-member, tenant e qualquer cardinalidade de domínio
 * continuam na RPC/banco — nenhum teto arbitrário é imposto aqui.
 */
function listaUuidPermitindoVazio(valor: unknown): readonly string[] | null {
  if (!Array.isArray(valor)) return null;
  const itens: string[] = [];
  for (const item of valor) {
    if (!ehUuid(item)) return null;
    itens.push(item as string);
  }
  return itens;
}

/**
 * `code` do cargo (D5 — rótulo estável, NUNCA autoridade): OPCIONAL.
 * Normalizado para caixa alta e sem espaços nas bordas, exatamente como o
 * CHECK `ck_job_roles_code` e o bootstrap D16. `ok: false` ⇒ forma inválida.
 */
function codeCargo(
  valor: unknown
): { readonly ok: true; readonly valor: string | null } | { readonly ok: false } {
  if (valor === undefined || valor === null) return { ok: true, valor: null };
  const limpo = texto(valor, 40);
  if (!limpo) return { ok: false };
  return { ok: true, valor: limpo.toUpperCase() };
}

function listaUuid(valor: unknown, max: number): readonly string[] | null {
  if (!Array.isArray(valor) || valor.length === 0 || valor.length > max) return null;
  const itens: string[] = [];
  for (const item of valor) {
    if (!ehUuid(item)) return null;
    itens.push(item);
  }
  return itens;
}

/**
 * `filtros` é INTENÇÃO de UX: chaves desconhecidas são recusadas (nada de
 * "ignora o que não entende"), e `busca` é SUBSTRING — os curingas de ILIKE são
 * escapados no executor (a tela não declara padrão de banco).
 */
function validarFiltros(valor: unknown): FiltrosListarColaboradores | null | undefined {
  if (valor === undefined || valor === null) return undefined;
  const cru = registro(valor);
  if (!cru) return null;

  for (const chave of Object.keys(cru)) {
    if (chave !== "status" && chave !== "unit_id" && chave !== "busca") return null;
  }

  const filtros: {
    status?: string;
    unit_id?: string;
    busca?: string;
  } = {};

  if (cru.status !== undefined && cru.status !== null) {
    const status = texto(cru.status, 32);
    if (!status) return null;
    filtros.status = status;
  }
  if (cru.unit_id !== undefined && cru.unit_id !== null) {
    if (!ehUuid(cru.unit_id)) return null;
    filtros.unit_id = cru.unit_id;
  }
  if (cru.busca !== undefined && cru.busca !== null) {
    const busca = texto(cru.busca, 120);
    if (!busca) return null;
    filtros.busca = busca;
  }

  return filtros;
}

/** Catálogo do bootstrap: apenas `job_roles` (code+name) e `seniority_levels`. */
function validarCatalogo(valor: unknown): EntradaBootstrapCatalogo["catalogo"] | null {
  const cru = registro(valor);
  if (!cru) return null;
  for (const chave of Object.keys(cru)) {
    if (chave !== "job_roles" && chave !== "seniority_levels") return null;
  }
  if (!Array.isArray(cru.job_roles) || cru.job_roles.length === 0 || cru.job_roles.length > 200) {
    return null;
  }
  if (
    !Array.isArray(cru.seniority_levels) ||
    cru.seniority_levels.length === 0 ||
    cru.seniority_levels.length > 200
  ) {
    return null;
  }

  const jobRoles: ItemCatalogoJobRole[] = [];
  for (const item of cru.job_roles) {
    const linha = registro(item);
    if (!linha) return null;
    for (const chave of Object.keys(linha)) {
      if (chave !== "code" && chave !== "name") return null;
    }
    const name = texto(linha.name, 120);
    // D5: o código estável é canônico em MAIÚSCULAS (o banco reforça o check).
    const code = typeof linha.code === "string" ? linha.code.trim().toUpperCase() : "";
    if (!name || !/^[A-Z0-9_]{2,40}$/.test(code)) return null;
    jobRoles.push({ code, name });
  }

  const senioridades: string[] = [];
  for (const item of cru.seniority_levels) {
    const name = texto(item, 120);
    if (!name) return null;
    senioridades.push(name);
  }

  return { job_roles: jobRoles, seniority_levels: senioridades };
}

/**
 * Valida a FORMA da intenção (nunca a autoridade). Qualquer desvio é
 * `INVALID_INPUT` — fail-closed. O alvo autorizável de criação é o colaborador
 * A CRIAR: o identificador neutro é substituído na fronteira pelo UUID
 * devolvido pela RPC, nunca por um valor enviado pela tela.
 */
export function validarEntradaColaborador(corpo: unknown): ResultadoValidacaoColaborador {
  const cru = registro(corpo);
  if (!cru) {
    return { ok: false, code: "INVALID_INPUT", message: "Corpo da requisição inválido." };
  }

  for (const proibido of CAMPOS_PROIBIDOS) {
    if (cru[proibido] !== undefined) {
      return {
        ok: false,
        code: "INVALID_INPUT",
        message: "O corpo não pode declarar identidade, capability, role nem escopo.",
      };
    }
  }

  if (!ehOperacaoColaborador(cru.operacao)) {
    return { ok: false, code: "INVALID_INPUT", message: "Operação desconhecida." };
  }
  if (!ehUuid(cru.organization_id)) {
    return { ok: false, code: "INVALID_INPUT", message: "organization_id inválido." };
  }

  const organization_id = cru.organization_id;

  // `data_referencia` é parâmetro de LEITURA (nunca "hoje" implícito).
  let data_referencia: string | undefined;
  if (cru.data_referencia !== undefined && cru.data_referencia !== null) {
    const normalizada = dataOuInstante(cru.data_referencia);
    if (!normalizada) {
      return { ok: false, code: "INVALID_INPUT", message: "data_referencia inválida." };
    }
    data_referencia = normalizada;
  }

  // `operation_id` (idempotência) — obrigatório em toda MUTAÇÃO.
  let operation_id: string | undefined;
  if (cru.operation_id !== undefined && cru.operation_id !== null) {
    if (!ehUuid(cru.operation_id)) {
      return { ok: false, code: "INVALID_INPUT", message: "operation_id inválido." };
    }
    operation_id = cru.operation_id;
  }

  // `expected_version` (concorrência otimista §13.1) — obrigatório quando
  // informado em operação que altera linha existente.
  let expected_version: number | undefined;
  if (cru.expected_version !== undefined && cru.expected_version !== null) {
    if (
      typeof cru.expected_version !== "number" ||
      !Number.isInteger(cru.expected_version) ||
      cru.expected_version < 0
    ) {
      return { ok: false, code: "INVALID_INPUT", message: "expected_version inválido." };
    }
    expected_version = cru.expected_version;
  }

  let cycle_scope: CicloEscopo | undefined;
  if (cru.cycle_scope !== undefined && cru.cycle_scope !== null) {
    if (typeof cru.cycle_scope !== "string" || !criaEscopoValido(cru.cycle_scope)) {
      return { ok: false, code: "INVALID_INPUT", message: "cycle_scope inválido." };
    }
    cycle_scope = cru.cycle_scope as CicloEscopo;
  }

  let reference_cycle_id: string | undefined;
  if (cru.reference_cycle_id !== undefined && cru.reference_cycle_id !== null) {
    if (!ehUuid(cru.reference_cycle_id)) {
      return { ok: false, code: "INVALID_INPUT", message: "reference_cycle_id inválido." };
    }
    reference_cycle_id = cru.reference_cycle_id;
  }

  const exigirOperacao = (): { ok: false; code: CodigoPublico; message: string } | null =>
    operation_id ? null : { ok: false, code: "INVALID_INPUT", message: "operation_id obrigatório." };

  const exigirVersao = (): { ok: false; code: CodigoPublico; message: string } | null =>
    expected_version === undefined
      ? { ok: false, code: "INVALID_INPUT", message: "expected_version obrigatório." }
      : null;

  const exigirMotivo = (): string | { ok: false; code: CodigoPublico; message: string } =>
    texto(cru.motivo, 500) ?? {
      ok: false,
      code: "INVALID_INPUT",
      message: "motivo obrigatório.",
    };

  // F5-08 P3: as operações de estrutura/catálogo têm payload público em
  // camelCase (`operationId`/`expectedVersion`). A leitura é PARALELA à do
  // legado — nenhuma operação F5-07 passa a aceitar a outra convenção — e as
  // mensagens públicas permanecem as canônicas do contrato.
  let operationIdCamel: string | undefined;
  if (cru.operationId !== undefined && cru.operationId !== null) {
    if (!ehUuid(cru.operationId)) {
      return { ok: false, code: "INVALID_INPUT", message: "operation_id inválido." };
    }
    operationIdCamel = cru.operationId;
  }

  let expectedVersionCamel: number | undefined;
  if (cru.expectedVersion !== undefined && cru.expectedVersion !== null) {
    if (
      typeof cru.expectedVersion !== "number" ||
      !Number.isInteger(cru.expectedVersion) ||
      cru.expectedVersion < 0
    ) {
      return { ok: false, code: "INVALID_INPUT", message: "expected_version inválido." };
    }
    expectedVersionCamel = cru.expectedVersion;
  }

  const exigirOperacaoNova = (): { ok: false; code: CodigoPublico; message: string } | null =>
    operationIdCamel
      ? null
      : { ok: false, code: "INVALID_INPUT", message: "operation_id obrigatório." };

  const exigirVersaoNova = (): { ok: false; code: CodigoPublico; message: string } | null =>
    expectedVersionCamel === undefined
      ? { ok: false, code: "INVALID_INPUT", message: "expected_version obrigatório." }
      : null;

  const exigirVigencia = (): string | { ok: false; code: CodigoPublico; message: string } => {
    const vigencia = cru.vigencia === undefined ? null : dataOuInstante(cru.vigencia);
    return (
      vigencia ?? {
        ok: false,
        code: "INVALID_INPUT",
        message: "vigencia inválida.",
      }
    );
  };

  switch (cru.operacao) {
    case "collaborator.listar": {
      const filtros = validarFiltros(cru.filtros);
      if (filtros === null) {
        return { ok: false, code: "INVALID_INPUT", message: "filtros inválidos." };
      }
      return {
        ok: true,
        entrada: {
          organization_id,
          ...(data_referencia ? { data_referencia } : {}),
          ...(filtros ? { filtros } : {}),
        },
      };
    }

    case "collaborator.obter": {
      const temId = cru.collaborator_id !== undefined && cru.collaborator_id !== null;
      const temMatricula = cru.matricula !== undefined && cru.matricula !== null;

      if (temId && temMatricula) {
        return {
          ok: false,
          code: "INVALID_INPUT",
          message: "Informe collaborator_id OU matricula, nunca os dois.",
        };
      }
      if (temId) {
        if (!ehUuid(cru.collaborator_id)) {
          return { ok: false, code: "INVALID_INPUT", message: "collaborator_id inválido." };
        }
        return {
          ok: true,
          entrada: {
            organization_id,
            collaborator_id: cru.collaborator_id,
            ...(data_referencia ? { data_referencia } : {}),
            alvo: { type: "collaborator", id: cru.collaborator_id },
          },
        };
      }
      if (temMatricula) {
        const normalizada = matricula(cru.matricula);
        if (!normalizada) {
          return { ok: false, code: "INVALID_INPUT", message: "matricula inválida." };
        }
        return {
          ok: true,
          entrada: {
            organization_id,
            matricula: normalizada,
            ...(data_referencia ? { data_referencia } : {}),
            // Alvo resolvido server-side (a UUID real substitui `ID_NEUTRO`).
            alvo: { type: "collaborator", id: ID_NEUTRO },
          },
        };
      }
      return {
        ok: false,
        code: "INVALID_INPUT",
        message: "collaborator_id ou matricula é obrigatório.",
      };
    }

    case "collaborator.criar": {
      const falta = exigirOperacao();
      if (falta) return falta;
      const full_name = texto(cru.full_name, 200);
      const email = texto(cru.email, 320);
      const matriculaNormalizada = matricula(cru.matricula);
      if (!full_name) {
        return { ok: false, code: "INVALID_INPUT", message: "full_name inválido." };
      }
      if (!email || !email.includes("@") || email.indexOf("@") === 0) {
        return { ok: false, code: "INVALID_INPUT", message: "email inválido." };
      }
      if (!matriculaNormalizada) {
        return { ok: false, code: "INVALID_INPUT", message: "matricula inválida." };
      }

      let admission_date: string | undefined;
      if (cru.admission_date !== undefined && cru.admission_date !== null) {
        const normalizada = dataOuInstante(cru.admission_date);
        if (!normalizada) {
          return { ok: false, code: "INVALID_INPUT", message: "admission_date inválida." };
        }
        admission_date = normalizada;
      }

      let status_inicial: StatusInicial | undefined;
      if (cru.status_inicial !== undefined && cru.status_inicial !== null) {
        if (
          typeof cru.status_inicial !== "string" ||
          !(STATUS_INICIAIS as readonly string[]).includes(cru.status_inicial)
        ) {
          return { ok: false, code: "INVALID_INPUT", message: "status_inicial inválido." };
        }
        status_inicial = cru.status_inicial as StatusInicial;
      }

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          full_name,
          email,
          matricula: matriculaNormalizada,
          ...(admission_date ? { admission_date } : {}),
          ...(status_inicial ? { status_inicial } : {}),
          alvo: { type: "collaborator", id: ID_NEUTRO },
        },
      };
    }

    case "collaborator.editar": {
      const falta = exigirOperacao() ?? exigirVersao();
      if (falta) return falta;
      if (!ehUuid(cru.collaborator_id)) {
        return { ok: false, code: "INVALID_INPUT", message: "collaborator_id inválido." };
      }

      let full_name: string | undefined;
      if (cru.full_name !== undefined && cru.full_name !== null) {
        const normalizado = texto(cru.full_name, 200);
        if (!normalizado) {
          return { ok: false, code: "INVALID_INPUT", message: "full_name inválido." };
        }
        full_name = normalizado;
      }

      let email: string | undefined;
      if (cru.email !== undefined && cru.email !== null) {
        const normalizado = texto(cru.email, 320);
        if (!normalizado || !normalizado.includes("@") || normalizado.indexOf("@") === 0) {
          return { ok: false, code: "INVALID_INPUT", message: "email inválido." };
        }
        email = normalizado;
      }

      let admission_date: string | undefined;
      if (cru.admission_date !== undefined && cru.admission_date !== null) {
        const normalizada = dataOuInstante(cru.admission_date);
        if (!normalizada) {
          return { ok: false, code: "INVALID_INPUT", message: "admission_date inválida." };
        }
        admission_date = normalizada;
      }

      // A operação edita SOMENTE dados de pessoa: sem campo, não há intenção.
      if (full_name === undefined && email === undefined && admission_date === undefined) {
        return {
          ok: false,
          code: "INVALID_INPUT",
          message: "Informe ao menos um dado de pessoa (full_name, email, admission_date).",
        };
      }

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          collaborator_id: cru.collaborator_id,
          ...(full_name ? { full_name } : {}),
          ...(email ? { email } : {}),
          ...(admission_date ? { admission_date } : {}),
          expected_version: expected_version!,
          alvo: { type: "collaborator", id: cru.collaborator_id },
        },
      };
    }

    case "collaborator.identificador.definir": {
      const falta = exigirOperacao() ?? exigirVersao();
      if (falta) return falta;
      if (!ehUuid(cru.collaborator_id)) {
        return { ok: false, code: "INVALID_INPUT", message: "collaborator_id inválido." };
      }
      const nova_matricula = matricula(cru.nova_matricula);
      if (!nova_matricula) {
        return { ok: false, code: "INVALID_INPUT", message: "nova_matricula inválida." };
      }
      const vigencia = exigirVigencia();
      if (typeof vigencia !== "string") return vigencia;
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          collaborator_id: cru.collaborator_id,
          nova_matricula,
          vigencia,
          motivo,
          expected_version: expected_version!,
          alvo: { type: "collaborator", id: cru.collaborator_id },
        },
      };
    }

    case "collaborator.status.alterar": {
      const falta = exigirOperacao() ?? exigirVersao();
      if (falta) return falta;
      if (!ehUuid(cru.collaborator_id)) {
        return { ok: false, code: "INVALID_INPUT", message: "collaborator_id inválido." };
      }
      if (
        typeof cru.novo_status !== "string" ||
        !(STATUS_COLABORADOR as readonly string[]).includes(cru.novo_status)
      ) {
        return { ok: false, code: "INVALID_INPUT", message: "novo_status inválido." };
      }
      const vigencia = exigirVigencia();
      if (typeof vigencia !== "string") return vigencia;
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          collaborator_id: cru.collaborator_id,
          novo_status: cru.novo_status as StatusColaborador,
          vigencia,
          motivo,
          ...(cycle_scope ? { cycle_scope } : {}),
          ...(reference_cycle_id ? { reference_cycle_id } : {}),
          expected_version: expected_version!,
          alvo: { type: "collaborator", id: cru.collaborator_id },
        },
      };
    }

    case "colaborador.ocupacao.definir": {
      const falta = exigirOperacao();
      if (falta) return falta;
      if (!ehUuid(cru.collaborator_id) || !ehUuid(cru.position_id)) {
        return {
          ok: false,
          code: "INVALID_INPUT",
          message: "collaborator_id ou position_id inválido.",
        };
      }
      const vigencia = exigirVigencia();
      if (typeof vigencia !== "string") return vigencia;
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          collaborator_id: cru.collaborator_id,
          position_id: cru.position_id,
          vigencia,
          motivo,
          ...(cycle_scope ? { cycle_scope } : {}),
          ...(reference_cycle_id ? { reference_cycle_id } : {}),
        },
      };
    }

    case "colaborador.ocupacao.encerrar": {
      const falta = exigirOperacao();
      if (falta) return falta;
      if (!ehUuid(cru.collaborator_id)) {
        return { ok: false, code: "INVALID_INPUT", message: "collaborator_id inválido." };
      }
      const vigencia = exigirVigencia();
      if (typeof vigencia !== "string") return vigencia;
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          collaborator_id: cru.collaborator_id,
          vigencia,
          motivo,
        },
      };
    }

    case "estrutura.reporting.definir": {
      const falta = exigirOperacao();
      if (falta) return falta;
      if (!ehUuid(cru.subordinate_position_id) || !ehUuid(cru.manager_position_id)) {
        return {
          ok: false,
          code: "INVALID_INPUT",
          message: "subordinate_position_id ou manager_position_id inválido.",
        };
      }
      if (cru.subordinate_position_id === cru.manager_position_id) {
        return { ok: false, code: "INVALID_INPUT", message: "Auto-reporting é inválido." };
      }
      const vigencia = exigirVigencia();
      if (typeof vigencia !== "string") return vigencia;
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          subordinate_position_id: cru.subordinate_position_id,
          manager_position_id: cru.manager_position_id,
          vigencia,
          motivo,
        },
      };
    }

    case "estrutura.reporting.encerrar": {
      const falta = exigirOperacao();
      if (falta) return falta;
      if (!ehUuid(cru.subordinate_position_id)) {
        return {
          ok: false,
          code: "INVALID_INPUT",
          message: "subordinate_position_id inválido.",
        };
      }
      const vigencia = exigirVigencia();
      if (typeof vigencia !== "string") return vigencia;
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          subordinate_position_id: cru.subordinate_position_id,
          vigencia,
          motivo,
        },
      };
    }

    case "estrutura.responsabilidade.definir": {
      const falta = exigirOperacao();
      if (falta) return falta;
      if (!ehUuid(cru.position_id) || !ehUuid(cru.substitute_collaborator_id)) {
        return {
          ok: false,
          code: "INVALID_INPUT",
          message: "position_id ou substitute_collaborator_id inválido.",
        };
      }
      if (
        typeof cru.responsibility_type !== "string" ||
        !(RESPONSABILIDADES as readonly string[]).includes(cru.responsibility_type)
      ) {
        return { ok: false, code: "INVALID_INPUT", message: "responsibility_type inválido." };
      }
      const vigencia = exigirVigencia();
      if (typeof vigencia !== "string") return vigencia;
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          position_id: cru.position_id,
          substitute_collaborator_id: cru.substitute_collaborator_id,
          responsibility_type: cru.responsibility_type as ResponsabilidadeTipo,
          vigencia,
          motivo,
        },
      };
    }

    case "estrutura.responsabilidade.encerrar": {
      const falta = exigirOperacao();
      if (falta) return falta;
      if (!ehUuid(cru.responsibility_id)) {
        return { ok: false, code: "INVALID_INPUT", message: "responsibility_id inválido." };
      }
      const vigencia = exigirVigencia();
      if (typeof vigencia !== "string") return vigencia;
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          responsibility_id: cru.responsibility_id,
          vigencia,
          motivo,
        },
      };
    }

    case "estrutura.sucessao.registrar": {
      const falta = exigirOperacao();
      if (falta) return falta;
      const responsibility_ids = listaUuid(cru.responsibility_ids, 200);
      if (!responsibility_ids) {
        return { ok: false, code: "INVALID_INPUT", message: "responsibility_ids inválido." };
      }
      const succession_date =
        cru.succession_date === undefined ? null : dataOuInstante(cru.succession_date);
      if (!succession_date) {
        return { ok: false, code: "INVALID_INPUT", message: "succession_date inválida." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;

      return {
        ok: true,
        entrada: {
          organization_id,
          operation_id: operation_id!,
          responsibility_ids,
          succession_date,
          motivo,
        },
      };
    }

    case "colaborador.historico.listar": {
      if (!ehUuid(cru.collaborator_id)) {
        return { ok: false, code: "INVALID_INPUT", message: "collaborator_id inválido." };
      }
      return {
        ok: true,
        entrada: {
          organization_id,
          collaborator_id: cru.collaborator_id,
          ...(data_referencia ? { data_referencia } : {}),
          ...(reference_cycle_id ? { reference_cycle_id } : {}),
          alvo: { type: "collaborator", id: cru.collaborator_id },
        },
      };
    }

    case "colaborador.catalogo.bootstrap": {
      const falta = exigirOperacao();
      if (falta) return falta;
      const catalogo = validarCatalogo(cru.catalogo);
      if (!catalogo) {
        return { ok: false, code: "INVALID_INPUT", message: "catalogo inválido." };
      }
      return {
        ok: true,
        entrada: { organization_id, operation_id: operation_id!, catalogo },
      };
    }

    // -----------------------------------------------------------------------
    // F5-08 P3 — estrutura organizacional e catálogos (§21.1)
    //
    // A fronteira valida SOMENTE forma/tipo (nunca autoridade): os 15 payloads
    // são INTENÇÃO. Regras de domínio (ciclo, vigência, I1–I5, unicidade,
    // cross-tenant, expected_version e idempotência) pertencem à RPC/banco.
    // -----------------------------------------------------------------------
    case "estrutura.unidade.criar": {
      const falta = exigirOperacaoNova();
      if (falta) return falta;
      const nome = texto(cru.nome, 200);
      if (!nome) {
        return { ok: false, code: "INVALID_INPUT", message: "nome inválido." };
      }
      const validFrom = cru.validFrom === undefined ? null : dataOuInstante(cru.validFrom);
      if (!validFrom) {
        return { ok: false, code: "INVALID_INPUT", message: "validFrom inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: { organization_id, operationId: operationIdCamel!, nome, validFrom, motivo },
      };
    }

    case "estrutura.unidade.renomear": {
      const falta = exigirOperacaoNova() ?? exigirVersaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.unidadeId)) {
        return { ok: false, code: "INVALID_INPUT", message: "unidadeId inválido." };
      }
      const nome = texto(cru.nome, 200);
      if (!nome) {
        return { ok: false, code: "INVALID_INPUT", message: "nome inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          unidadeId: cru.unidadeId,
          nome,
          expectedVersion: expectedVersionCamel!,
          motivo,
        },
      };
    }

    case "estrutura.unidade.encerrar": {
      const falta = exigirOperacaoNova() ?? exigirVersaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.unidadeId)) {
        return { ok: false, code: "INVALID_INPUT", message: "unidadeId inválido." };
      }
      const validTo = cru.validTo === undefined ? null : dataOuInstante(cru.validTo);
      if (!validTo) {
        return { ok: false, code: "INVALID_INPUT", message: "validTo inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          unidadeId: cru.unidadeId,
          validTo,
          expectedVersion: expectedVersionCamel!,
          motivo,
        },
      };
    }

    case "estrutura.unidade.parent.definir": {
      const falta = exigirOperacaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.unidadeId)) {
        return { ok: false, code: "INVALID_INPUT", message: "unidadeId inválido." };
      }
      const parent = uuidOpcional(cru.parentUnitId);
      if (!parent.ok) {
        return { ok: false, code: "INVALID_INPUT", message: "parentUnitId inválido." };
      }
      const validFrom = cru.validFrom === undefined ? null : dataOuInstante(cru.validFrom);
      if (!validFrom) {
        return { ok: false, code: "INVALID_INPUT", message: "validFrom inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          unidadeId: cru.unidadeId,
          parentUnitId: parent.valor,
          validFrom,
          motivo,
        },
      };
    }

    case "estrutura.unidade.parent.encerrar": {
      const falta = exigirOperacaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.unidadeId)) {
        return { ok: false, code: "INVALID_INPUT", message: "unidadeId inválido." };
      }
      const validTo = cru.validTo === undefined ? null : dataOuInstante(cru.validTo);
      if (!validTo) {
        return { ok: false, code: "INVALID_INPUT", message: "validTo inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          unidadeId: cru.unidadeId,
          validTo,
          motivo,
        },
      };
    }

    case "estrutura.posicao.criar": {
      const falta = exigirOperacaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.unidadeId)) {
        return { ok: false, code: "INVALID_INPUT", message: "unidadeId inválido." };
      }
      if (!ehUuid(cru.jobRoleId)) {
        return { ok: false, code: "INVALID_INPUT", message: "jobRoleId inválido." };
      }
      const senioridade = uuidOpcional(cru.seniorityLevelId);
      if (!senioridade.ok) {
        return { ok: false, code: "INVALID_INPUT", message: "seniorityLevelId inválido." };
      }
      const validFrom = cru.validFrom === undefined ? null : dataOuInstante(cru.validFrom);
      if (!validFrom) {
        return { ok: false, code: "INVALID_INPUT", message: "validFrom inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          unidadeId: cru.unidadeId,
          jobRoleId: cru.jobRoleId,
          seniorityLevelId: senioridade.valor,
          validFrom,
          motivo,
        },
      };
    }

    case "estrutura.posicao.encerrar": {
      const falta = exigirOperacaoNova() ?? exigirVersaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.posicaoId)) {
        return { ok: false, code: "INVALID_INPUT", message: "posicaoId inválido." };
      }
      const validTo = cru.validTo === undefined ? null : dataOuInstante(cru.validTo);
      if (!validTo) {
        return { ok: false, code: "INVALID_INPUT", message: "validTo inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          posicaoId: cru.posicaoId,
          validTo,
          expectedVersion: expectedVersionCamel!,
          motivo,
        },
      };
    }

    case "estrutura.colegiado.definir": {
      const falta = exigirOperacaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.collaboratorId)) {
        return { ok: false, code: "INVALID_INPUT", message: "collaboratorId inválido." };
      }
      const membros = listaUuidPermitindoVazio(cru.memberCollaboratorIds);
      if (!membros) {
        return { ok: false, code: "INVALID_INPUT", message: "memberCollaboratorIds inválido." };
      }
      const validFrom = cru.validFrom === undefined ? null : dataOuInstante(cru.validFrom);
      if (!validFrom) {
        return { ok: false, code: "INVALID_INPUT", message: "validFrom inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          collaboratorId: cru.collaboratorId,
          memberCollaboratorIds: membros,
          validFrom,
          motivo,
        },
      };
    }

    case "estrutura.colegiado.encerrar": {
      const falta = exigirOperacaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.collaboratorId)) {
        return { ok: false, code: "INVALID_INPUT", message: "collaboratorId inválido." };
      }
      const validTo = cru.validTo === undefined ? null : dataOuInstante(cru.validTo);
      if (!validTo) {
        return { ok: false, code: "INVALID_INPUT", message: "validTo inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          collaboratorId: cru.collaboratorId,
          validTo,
          motivo,
        },
      };
    }

    case "catalogo.cargo.criar": {
      const falta = exigirOperacaoNova();
      if (falta) return falta;
      const nome = texto(cru.nome, 120);
      if (!nome) {
        return { ok: false, code: "INVALID_INPUT", message: "nome inválido." };
      }
      const code = codeCargo(cru.code);
      if (!code.ok) {
        return { ok: false, code: "INVALID_INPUT", message: "code inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          nome,
          code: code.valor,
          motivo,
        },
      };
    }

    case "catalogo.cargo.renomear": {
      const falta = exigirOperacaoNova() ?? exigirVersaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.jobRoleId)) {
        return { ok: false, code: "INVALID_INPUT", message: "jobRoleId inválido." };
      }
      const nome = texto(cru.nome, 120);
      if (!nome) {
        return { ok: false, code: "INVALID_INPUT", message: "nome inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          jobRoleId: cru.jobRoleId,
          nome,
          expectedVersion: expectedVersionCamel!,
          motivo,
        },
      };
    }

    case "catalogo.cargo.status.alterar": {
      const falta = exigirOperacaoNova() ?? exigirVersaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.jobRoleId)) {
        return { ok: false, code: "INVALID_INPUT", message: "jobRoleId inválido." };
      }
      const status = typeof cru.status === "string" ? cru.status.trim() : "";
      if (!(STATUS_CATALOGO as readonly string[]).includes(status)) {
        return { ok: false, code: "INVALID_INPUT", message: "status inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          jobRoleId: cru.jobRoleId,
          status: status as (typeof STATUS_CATALOGO)[number],
          expectedVersion: expectedVersionCamel!,
          motivo,
        },
      };
    }

    case "catalogo.senioridade.criar": {
      const falta = exigirOperacaoNova();
      if (falta) return falta;
      const nome = texto(cru.nome, 120);
      if (!nome) {
        return { ok: false, code: "INVALID_INPUT", message: "nome inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: { organization_id, operationId: operationIdCamel!, nome, motivo },
      };
    }

    case "catalogo.senioridade.renomear": {
      const falta = exigirOperacaoNova() ?? exigirVersaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.seniorityLevelId)) {
        return { ok: false, code: "INVALID_INPUT", message: "seniorityLevelId inválido." };
      }
      const nome = texto(cru.nome, 120);
      if (!nome) {
        return { ok: false, code: "INVALID_INPUT", message: "nome inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          seniorityLevelId: cru.seniorityLevelId,
          nome,
          expectedVersion: expectedVersionCamel!,
          motivo,
        },
      };
    }

    case "catalogo.senioridade.status.alterar": {
      const falta = exigirOperacaoNova() ?? exigirVersaoNova();
      if (falta) return falta;
      if (!ehUuid(cru.seniorityLevelId)) {
        return { ok: false, code: "INVALID_INPUT", message: "seniorityLevelId inválido." };
      }
      const status = typeof cru.status === "string" ? cru.status.trim() : "";
      if (!(STATUS_CATALOGO as readonly string[]).includes(status)) {
        return { ok: false, code: "INVALID_INPUT", message: "status inválido." };
      }
      const motivo = exigirMotivo();
      if (typeof motivo !== "string") return motivo;
      return {
        ok: true,
        entrada: {
          organization_id,
          operationId: operationIdCamel!,
          seniorityLevelId: cru.seniorityLevelId,
          status: status as (typeof STATUS_CATALOGO)[number],
          expectedVersion: expectedVersionCamel!,
          motivo,
        },
      };
    }
  }
}

function criaEscopoValido(valor: string): boolean {
  return (CICLO_ESCOPOS as readonly string[]).includes(valor);
}
