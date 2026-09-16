import type { AuthIdentity } from "../auth/tipos.ts";
import { capabilityConhecida } from "./catalogoCapabilities.ts";
import type { Capability } from "./Capability.ts";
import { ehActorContextSoberano, montarActorContext, type ActorContext } from "./actorContext.ts";
import { codigoPublicoDeNegacao } from "./policyEngine/errors.ts";
import {
  authorize as authorizeEngine,
  can as canEngine,
} from "./policyEngine/policyEngine.ts";
import {
  estadoDominioAvaliacao,
  estadoDominioCriacaoAvaliacao,
} from "./estadoDominioAvaliacao.ts";
import { estadoDominioCiclo } from "./estadoDominioCiclo.ts";
import { estadoDominioMeta } from "./estadoDominioMeta.ts";
import {
  estadoDominioObservacao,
  exigeAutoriaObservacao,
} from "./estadoDominioObservacao.ts";
import type {
  AuthorizationDecision,
  AuthorizationRequest,
  DenialReason,
  DomainStateProbe,
  ExceptionalProvider,
  PilotFullAccessProvider,
  PolicyEngineProviders,
  ScopeType,
  TargetRef,
  TemporaryProvider,
} from "./policyEngine/types.ts";
import {
  ehTipoRecursoSoberano,
  montarResourceContextSoberano,
  motivoAlvoNaoAutorizavel,
  type AprovadoresCongeladosMeta,
  type RecursoSoberanoCarregado,
  type ResourceContext,
} from "./resourceContextReal.ts";
import {
  criarProvidersReais,
  type AlvoEscopoResolvido,
  type CapabilityComEscopos,
  type DadosAssignedSoberanos,
} from "./providers/reais.ts";

/**
 * F5-05 — orquestração do contexto real e enforcement (D1–D23).
 *
 * Este módulo é a PORTA DE ENFORCEMENT da F5-05: monta `ActorContext` e
 * `ResourceContext` a partir de dados soberanos resolvidos server-side, produz o
 * `AuthorizationRequest` do engine F4-03 (sem reescrevê-lo) e decide.
 *
 * Fronteira confiável (D20): quem chama `avaliarOperacaoAutorizacao` é a Edge
 * Function / RPC / backend equivalente, com `authUserId` obtido de
 * `auth.getUser` (nunca do corpo). Nenhum `ActorRef`/contexto do browser é
 * aceito: `montarRequisicaoAutorizacao` exige a marca de soberania do
 * `ActorContext` (D20) e o tenant do recurso é conferido contra a organização
 * validada (D6/D8).
 *
 * Sem cache de ALLOW entre requisições (D10): os dados valem para a operação.
 *
 * F5-09 P6 (§8): o recurso CICLO passa a ser SOBERANO (`evaluation_cycles`, P5).
 * O `domainState` do alvo `cycle` é derivado do status da LINHA carregada
 * (`recurso.status`), nunca de estado declarado pelo chamador, e o alvo exige o
 * UUID canônico — alvo sintético (`{type:"cycle", id:"global"}`) ou rótulo
 * inválido é recusado antes de qualquer decisão (D19/D22).
 *
 * F5-10 P4 (§9.1/§10, D8/D9/D14/D25): a META também é recurso SOBERANO
 * (`evaluation_goals`). O `domainState` do alvo `goal` vem da LINHA soberana
 * (`status`, `excluida` e o status do CICLO da meta) via `estadoDominioMeta`, e
 * as relações de aprovação são **CONGELADAS** — resolvidas na fronteira
 * confiável a partir da avaliação ORIGINAL do dono e propagadas ao provider pelo
 * bloco `meta` do `ResourceContext`. Nenhuma estrutura viva participa da
 * autorização de meta.
 *
 * F5-11 P4 (§8; D3/D5/D7/D9/D11/D12): a OBSERVAÇÃO também é recurso SOBERANO
 * (`evaluation_observations`). O `domainState` do alvo `observation` é DERIVADO
 * da LINHA carregada em (7) — `comunicado`, `excluida`, status do CICLO e status
 * do colaborador-ALVO — pela fonte única `estadoDominioObservacao`, composta com
 * a AUTORIA D5 (autor da LINHA × vínculo do ator) e com a leitura
 * SELF-comunicada (D7/D9). O `domainState` declarado pelo chamador nunca é
 * autoridade nesse alvo (invariante 1 do §8) e a ausência de dado soberano é
 * fail-closed.
 */

function negar(reason: DenialReason): AuthorizationDecision {
  return {
    allowed: false,
    denial: { reason, publicCode: codigoPublicoDeNegacao(reason) },
  };
}

function dataValida(valor: unknown): valor is Date {
  return valor instanceof Date && !Number.isNaN(valor.getTime());
}

/**
 * Formato aceito para a DATA DE NEGÓCIO transportada por JSON (Edge Function):
 * ISO-8601 (`YYYY-MM-DD` ou `YYYY-MM-DDThh:mm[:ss[.sss]][Z|±hh:mm]`).
 */
const FORMATO_DATA_NEGOCIO_ISO =
  /^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:?\d{2})?)?$/;

/**
 * Valida a DATA DE NEGÓCIO (intenção funcional enviada pelo cliente — D21).
 *
 * - ausente/null ⇒ `null` (sem data de negócio);
 * - `Date` válido (chamadas internas tipadas) ⇒ `Date`;
 * - string **ISO válida** (transporte JSON da Edge Function) ⇒ normalizada
 *   server-side em `Date`;
 * - string inválida/ambígua, números, booleanos, objetos e arrays ⇒ `undefined`
 *   (o chamador trata como DENY/validação — fail-closed).
 *
 * NUNCA substitui o instante soberano da decisão (`deps.agora()`); serve apenas
 * como parâmetro funcional validado.
 */
export function validarDataNegocio(valor: unknown): Date | null | undefined {
  if (valor === undefined || valor === null) return null;

  if (valor instanceof Date) return dataValida(valor) ? valor : undefined;

  if (typeof valor === "string") {
    const texto = valor.trim();
    if (!FORMATO_DATA_NEGOCIO_ISO.test(texto)) return undefined;
    const convertida = new Date(texto);
    if (!dataValida(convertida)) return undefined;
    // Data sem hora: recusa "rollover" (ex.: 2026-02-30 ⇒ 2026-03-02).
    if (/^\d{4}-\d{2}-\d{2}$/.test(texto)) {
      return convertida.toISOString().slice(0, 10) === texto ? convertida : undefined;
    }
    return convertida;
  }

  // Números, booleanos, objetos, arrays e formatos ambíguos ⇒ DENY.
  return undefined;
}

export interface EntradaRequisicaoAutorizacao {
  readonly actorContext: ActorContext;
  readonly resourceContext: ResourceContext;
  readonly capability: Capability;
  /** Instante SOBERANO da decisão (relógio server-side — D21). */
  readonly instanteSoberano: Date;
}

/**
 * Monta o `AuthorizationRequest` do engine. Fail-closed (`null`) quando:
 * contexto de ator NÃO soberano (browser/forjado — D20); capability fora do
 * catálogo canônico (D14 F5-04); alvo não soberano (global/legado — D19/D22);
 * tenant do recurso divergente do ator (D6/D8); instante soberano inválido.
 */
export function montarRequisicaoAutorizacao(
  entrada: EntradaRequisicaoAutorizacao
): AuthorizationRequest | null {
  if (!ehActorContextSoberano(entrada.actorContext)) return null;

  const { actorContext, resourceContext, capability } = entrada;

  if (!capabilityConhecida(capability)) return null;
  if (!resourceContext || !ehTipoRecursoSoberano(String(resourceContext.kind))) return null;
  if (motivoAlvoNaoAutorizavel(resourceContext.target) !== null) return null;
  if (resourceContext.organizationId !== actorContext.organizationId) return null;
  if (!dataValida(entrada.instanteSoberano)) return null;

  return {
    actor: actorContext.toActorRef(),
    capability,
    target: resourceContext.target,
    context: {
      date: entrada.instanteSoberano,
      ...(resourceContext.cycleId ? { cycleId: resourceContext.cycleId } : {}),
    },
    domainState: resourceContext.domainState,
  };
}

/** UX/predicação (`can`) — NUNCA enforcement (D13). */
export function podeOperacao(
  request: AuthorizationRequest,
  providers: PolicyEngineProviders
): AuthorizationDecision {
  return canEngine(request, providers);
}

/** Enforcement (`authorize`) — lança erro público F0-05 quando DENY (D13). */
export function autorizarOperacao(
  request: AuthorizationRequest,
  providers: PolicyEngineProviders
): void {
  authorizeEngine(request, providers);
}

// ---------------------------------------------------------------------------
// Portas de dados SOBERANOS (implementadas na fronteira confiável — D20)
// ---------------------------------------------------------------------------

export interface EntradaResolverAlvosEscopo {
  readonly authUserId: string;
  readonly organizationId: string;
  readonly scope: ScopeType;
  readonly unitId: string | null;
  readonly data: Date;
}

export interface EntradaCarregarRecurso {
  readonly target: TargetRef;
  readonly organizationId: string;
}

/**
 * F5-06: contexto soberano necessário ao `domainState` do recurso de avaliação.
 * Para o recurso `evaluation` o estado é o status real da linha; para o alvo de
 * CRIAÇÃO (`collaborator`) o ciclo vigente e a aptidão do avaliado são
 * resolvidos server-side — nunca declarados pelo cliente.
 */
export interface ContextoAvaliacaoSoberano {
  readonly status: string;
  readonly encerradaComPendencias?: boolean;
  readonly cicloPermiteNovaAvaliacao?: boolean;
  readonly avaliadoApto?: boolean;
  /**
   * F5-11 P4 (D11): status VIGENTE do colaborador-alvo, lido da fonte soberana
   * (`collaborator_status_periods`: `active`/`leave`/`inactive`). Campo OPCIONAL
   * e retrocompatível — ausente ⇒ o probe da criação de observação trata como
   * status NÃO resolvido e NEGA (fail-closed). NUNCA é estado declarado pelo
   * cliente.
   */
  readonly colaboradorStatus?: string;
  /**
   * F5-11 P4 (D12): status da LINHA soberana do CICLO da operação (mutação de
   * observação exige `ATIVO`). Campo OPCIONAL e retrocompatível — ausente ⇒ o
   * probe NEGA a mutação (fail-closed).
   */
  readonly cicloStatus?: string;
}

export interface DepsContextoAutorizacao {
  /** Relógio server-side confiável (D21). */
  agora(): Date;
  /** Identidade soberana (F5-01) — perfil + memberships ativas + organizações. */
  resolverIdentidade(authUserId: string): Promise<AuthIdentity | null>;
  /** Vínculo F5-02 `(authUserId, organizationId) → collaborator | null`. */
  resolverColaboradorVinculado(
    authUserId: string,
    organizationId: string
  ): Promise<string | null>;
  /** Capabilities × scopes dos resolvers canônicos da F5-04 (por operação). */
  resolverCapabilitiesEscopos(
    authUserId: string,
    organizationId: string
  ): Promise<readonly CapabilityComEscopos[]>;
  /** Alvos de um scope (F4-02/F3-07), resolvidos na data de decisão. */
  resolverAlvosEscopo(
    entrada: EntradaResolverAlvosEscopo
  ): Promise<readonly AlvoEscopoResolvido[]>;
  /** Carrega o recurso de fonte SOBERANA (`null` = inexistente/inacessível). */
  carregarRecurso(
    entrada: EntradaCarregarRecurso
  ): Promise<RecursoSoberanoCarregado | null>;
  /**
   * F5-06: contexto soberano da avaliação/colaborador da operação. Usado para
   * montar o `domainState` do recurso (fronteira confiável) — o browser nunca
   * declara estado de domínio.
   */
  carregarContextoAvaliacao?(
    entrada: EntradaCarregarRecurso
  ): Promise<ContextoAvaliacaoSoberano | null>;
  /** ASSIGNED soberano (F3-08/09), quando disponível. */
  readonly assigned?: DadosAssignedSoberanos;
  /**
   * F5-06: resolve o ASSIGNED **por operação**, depois de conhecidos o vínculo
   * do ator e o tenant validados. O ator/membership nunca vêm do cliente: os
   * argumentos são derivados server-side nos passos anteriores. Ausente ⇒
   * comportamento anterior (sem ASSIGNED).
   */
  resolverAssigned?(entrada: {
    readonly authUserId: string;
    readonly collaboratorId: string | null;
    readonly organizationId: string;
    readonly target: TargetRef;
    readonly cycleId?: string;
  }): Promise<DadosAssignedSoberanos | null>;
  /**
   * F5-10 P4 (§9.1, D14/D25): resolve os **aprovadores CONGELADOS** da meta a
   * partir da avaliação **ORIGINAL** do dono (`evaluation_participants`:
   * `GESTAO_CADEIA` = gerente; `GESTAO_DIRETA`, quando distinta = coordenador).
   * Espelha `resolverAssigned`: é resolvido POR OPERAÇÃO, com o vínculo do ator,
   * o tenant validado e o alvo já conhecidos server-side — nunca do cliente.
   * `null` ⇒ nenhum papel reconhecido (o provider nega as relações de
   * aprovação — fail-closed). Estrutura VIVA nunca é consultada para a meta.
   */
  resolverAprovadorCongelado?(entrada: {
    readonly authUserId: string;
    readonly collaboratorId: string | null;
    readonly organizationId: string;
    readonly target: TargetRef;
    readonly cycleId?: string;
  }): Promise<AprovadoresCongeladosMeta | null>;
  /** Origens independentes (D11). */
  readonly temporary?: TemporaryProvider;
  readonly exceptional?: ExceptionalProvider;
  readonly pilot?: PilotFullAccessProvider;
}

export interface EntradaOperacaoAutorizacao {
  /** `auth.uid()` verificado server-side (`auth.getUser`). NUNCA do corpo. */
  readonly authUserId: string;
  /** Organização pretendida (intenção) — revalidada contra membership ativa. */
  readonly organizationId: string;
  readonly capability: Capability;
  readonly alvo: TargetRef;
  /** Data de negócio (intenção funcional validada — D21). */
  readonly dataNegocio?: unknown;
  /** Estado do domínio declarado pelo serviço (ausente ⇒ DENY). */
  readonly domainState?: DomainStateProbe;
}

/** Id soberano normalizado (`trim` + não vazio) ou `null` — comparação fail-closed. */
function identificadorSoberano(valor: unknown): string | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  return limpo.length > 0 ? limpo : null;
}

/**
 * F5-11 P4 (§8; D3/D5/D7/D9/D11/D12) — probe SOBERANO do recurso OBSERVAÇÃO.
 *
 * Composição de TRÊS fatos, todos derivados da LINHA soberana carregada em (7) —
 * nenhum deles é declarado pelo chamador:
 *
 * 1. **estado do domínio** (fonte ÚNICA `estadoDominioObservacao`): status do
 *    CICLO da observação (mutação exige `ATIVO` — D12) e status do
 *    colaborador-ALVO (D11 — `DESLIGADO` nega criação); status ausente/fora do
 *    domínio só permite o que a matriz do domínio autoriza (fail-closed);
 * 2. **AUTORIA D5** (`exigeAutoriaObservacao`): editar, definir comunicado,
 *    revogar e excluir são atos do AUTOR — e o autor autorizável é o
 *    `author_collaborator_id` da LINHA comparado ao vínculo do ator. Sem autoria
 *    PROVADA (autor ausente ou ator sem vínculo) o probe NEGA (fail-closed). A
 *    autoria NUNCA vem do chamador nem de `usuarioAtual`/payload;
 * 3. **leitura SELF-comunicada** (§8 linha 2; D7/D9): quando o PRÓPRIO
 *    colaborador-alvo é o ator, a leitura só é permitida para observação
 *    `comunicado` e NÃO excluída. Para os demais atores a leitura segue a matriz
 *    do domínio (leitura histórica em qualquer estado) e quem decide a relação é
 *    o engine/providers — o probe não amplia nem substitui aquele alcance.
 *
 * `entrada.domainState` NUNCA participa deste alvo: para recurso soberano o
 * estado declarado pelo chamador não é autoridade (invariante 1 do §8).
 */
function probeObservacaoSoberana(
  recurso: RecursoSoberanoCarregado,
  colaboradorDoAtor: string | null
): DomainStateProbe {
  const comunicado = recurso.comunicado === true;
  const excluida = recurso.excluida === true;

  const estado = estadoDominioObservacao({
    cicloStatus: recurso.cicloStatus ?? "",
    // F5-11 P5: o loader entrega o vocabulário SOBERANO (`active|leave|inactive`);
    // a conversão para o vocabulário do probe é feita AQUI, pelo normalizador
    // canônico — valor ausente/desconhecido ⇒ "" ⇒ o probe nega (fail-closed).
    colaboradorStatus: statusColaboradorDoSoberano(recurso.colaboradorStatus),
  });

  const autorDaObservacao = identificadorSoberano(recurso.authorCollaboratorId);
  const ator = identificadorSoberano(colaboradorDoAtor);
  const alvoDaObservacao = identificadorSoberano(recurso.ownerCollaboratorId);

  const autorSoberano = autorDaObservacao !== null && ator !== null && autorDaObservacao === ator;
  const atorEhOProprioAlvo =
    ator !== null && alvoDaObservacao !== null && ator === alvoDaObservacao;
  const leituraSelfPermitida = !atorEhOProprioAlvo || (comunicado && !excluida);

  return {
    allows: (capability: Capability): boolean => {
      if (!estado.allows(capability)) return false;
      if (exigeAutoriaObservacao(capability)) return autorSoberano;
      if (capability === "observation.read") return leituraSelfPermitida;
      // Demais capabilities da matriz (`observation.create`): o estado do domínio
      // (ciclo `ATIVO` + colaborador-alvo apto) já decidiu — nada é ampliado aqui.
      return true;
    },
  };
}

/**
 * F5-11 P4 (§8 linha 4; D11/D12, invariante 4) — vocabulário SOBERANO de
 * `collaborator_status_periods` (`active`/`leave`/`inactive`, CHECK da F3-01) →
 * vocabulário do probe de domínio do cliente (`ATIVO`/`LICENCA`/`DESLIGADO`).
 * O mapeamento é DOCUMENTADO no comentário da própria coluna soberana — a
 * fronteira apenas o aplica. Status ausente/desconhecido devolve `""` (NÃO
 * resolvido) e o probe da criação NEGA (fail-closed, invariante 6).
 */
const STATUS_SOBERANO_PARA_PROBE: Readonly<Record<string, string>> = {
  active: "ATIVO",
  leave: "LICENCA",
  inactive: "DESLIGADO",
  // IDEMPOTÊNCIA (F5-11 P4/P5): o vocabulário do PROBE também é aceito, porque
  // a fronteira pode ser alimentada tanto pela LINHA soberana
  // (`collaborator_status_periods` — `active`/`leave`/`inactive`) quanto por um
  // contexto que já fale o vocabulário do probe (`ATIVO`/`LICENCA`/`DESLIGADO`).
  // A normalização é, portanto, um ponto FIXO dos dois vocabulários; valor
  // ausente/desconhecido continua devolvendo `""` (NÃO resolvido ⇒ DENY).
  ativo: "ATIVO",
  licenca: "LICENCA",
  desligado: "DESLIGADO",
};

function statusColaboradorDoSoberano(valor: unknown): string {
  if (typeof valor !== "string") return "";
  return STATUS_SOBERANO_PARA_PROBE[valor.trim().toLowerCase()] ?? "";
}

/**
 * F5-11 P4 (§8 linha 4; D11/D12) — probe SOBERANO da CRIAÇÃO de observação.
 *
 * A observação AINDA NÃO EXISTE: o alvo funcional da criação é o
 * COLABORADOR-ALVO (molde `goal.criar`, cujo alvo funcional é o dono/ciclo). O
 * estado vem do contexto soberano do alvo — status do CICLO e status VIGENTE do
 * colaborador, ambos resolvidos server-side — pela fonte única
 * `estadoDominioObservacao`, composto com:
 *
 * - **SELF = DENY** (§8 invariante 4): criar/editar/excluir observação são atos
 *   EXCLUSIVOS de gestão — o próprio colaborador-alvo nunca age sobre a
 *   observação de si, ainda que o estado permita;
 * - **status NÃO resolvido ⇒ DENY** (D11/invariante 6): sem status vigente do
 *   colaborador-alvo a criação é negada, nunca "permitida por default" (o probe
 *   do cliente não distingue "ausente" de "desconhecido" porque o vocabulário
 *   soberano é fechado).
 *
 * `entrada.domainState` NUNCA é consultado neste ramo.
 */
function probeObservacaoSoberanaDeCriacao(entrada: {
  readonly cicloStatus: unknown;
  readonly colaboradorStatus: unknown;
  readonly atorEhOColaboradorAlvo: boolean;
}): DomainStateProbe {
  const statusColaborador = statusColaboradorDoSoberano(entrada.colaboradorStatus);
  const statusResolvido = statusColaborador !== "";

  const estado = estadoDominioObservacao({
    cicloStatus: typeof entrada.cicloStatus === "string" ? entrada.cicloStatus : "",
    colaboradorStatus: statusColaborador,
  });

  return {
    allows: (capability: Capability): boolean => {
      if (!estado.allows(capability)) return false;
      if (
        entrada.atorEhOColaboradorAlvo &&
        (capability === "observation.create" || exigeAutoriaObservacao(capability))
      ) {
        return false;
      }
      if (capability === "observation.create") return statusResolvido;
      // As demais capabilities da matriz (`observation.read`) não são ampliadas
      // por este ramo: quem as decide é o alcance do engine/providers.
      return true;
    },
  };
}

/**
 * Avaliação de autorização NA FRONTEIRA CONFIÁVEL (D20), por operação.
 *
 * Falha fechado em qualquer elo ausente/inconsistente — nunca ALLOW por omissão.
 * A decisão é sempre do engine F4-03 (mesma pipeline usada por `can()`).
 */
export async function avaliarOperacaoAutorizacao(
  entrada: EntradaOperacaoAutorizacao,
  deps: DepsContextoAutorizacao
): Promise<AuthorizationDecision> {
  // 0) entrada mínima
  if (!entrada.authUserId || !entrada.organizationId) return negar("NO_IDENTITY");
  if (!capabilityConhecida(entrada.capability)) return negar("CAPABILITY_MISSING");

  // 1) alvo autorizável? (global/legado ⇒ nunca autorização real — D19/D22)
  const motivoAlvo = entrada.alvo ? motivoAlvoNaoAutorizavel(entrada.alvo) : "TARGET_NAO_SOBERANO";
  if (motivoAlvo !== null) return negar("TARGET_INVALID");

  // 2) data de negócio (intenção) — inválida ⇒ fail-closed (D21)
  const dataNegocio = validarDataNegocio(entrada.dataNegocio);
  if (dataNegocio === undefined) return negar("INDETERMINATE");

  // 3) instante SOBERANO (relógio server-side) — nunca do cliente (D21)
  const instanteSoberano = deps.agora();
  if (!dataValida(instanteSoberano)) return negar("INDETERMINATE");

  // 4) identidade soberana (F5-01) + organização/membership (F5-03)
  const identidade = await deps.resolverIdentidade(entrada.authUserId);
  const ator = montarActorContext({
    identity: identidade,
    organizationId: entrada.organizationId,
    // O vínculo é resolvido apenas com a organização já validada abaixo.
    collaboratorId: null,
  });
  if (!ator.ok) {
    switch (ator.motivo) {
      case "PERFIL_INATIVO":
        return negar("PROFILE_DISABLED");
      case "SEM_IDENTIDADE":
        return negar("NO_IDENTITY");
      case "ORGANIZACAO_AUSENTE":
      case "ORGANIZACAO_NAO_DISPONIVEL":
      case "MEMBERSHIP_AUSENTE":
        return negar("MEMBERSHIP_INVALID");
    }
  }

  // 5) vínculo F5-02 (opcional) — ADMIN sem collaborator é válido (D14)
  const collaboratorId = await deps.resolverColaboradorVinculado(
    entrada.authUserId,
    ator.actorContext.organizationId
  );
  const atorComVinculo = montarActorContext({
    identity: identidade,
    organizationId: ator.actorContext.organizationId,
    collaboratorId,
  });
  if (!atorComVinculo.ok) return negar("MEMBERSHIP_INVALID");

  // 6) capabilities × scopes (F5-04, por operação)
  const capabilities = await deps.resolverCapabilitiesEscopos(
    entrada.authUserId,
    atorComVinculo.actorContext.organizationId
  );

  // 7) recurso SOBERANO (tenant derivado do recurso — D6)
  const recurso = await deps.carregarRecurso({
    target: entrada.alvo,
    organizationId: atorComVinculo.actorContext.organizationId,
  });
  if (!recurso) return negar("TARGET_INVALID");

  // 7.1) ESTADO DE DOMÍNIO derivado server-side: avaliação/criação (F5-06 §8.1),
  // CICLO (F5-09 P6 §8), META (F5-10 P4 §10) e OBSERVAÇÃO (F5-11 P4 §8).
  //
  // P6: para o alvo `cycle` o probe vem SEMPRE da LINHA SOBERANA carregada em
  // (7) — `evaluation_cycles.status`. Um estado declarado pelo chamador
  // (`entrada.domainState`) é IGNORADO nesse alvo: o browser nunca declara o
  // estado do ciclo e o ciclo legado não pode suplantar o caminho soberano.
  // F5-10 P4: o mesmo vale para o alvo `goal` — o probe vem de
  // `evaluation_goals.status`/`excluida` e do status do CICLO da meta; o
  // `domainState` declarado pelo cliente NUNCA é autoridade.
  // Ausência de status na linha ⇒ probe nega tudo (fail-closed).
  const contextoAvaliacao =
    deps.carregarContextoAvaliacao &&
    entrada.alvo.type !== "cycle" &&
    entrada.alvo.type !== "goal" &&
    // F5-11 P3: a OBSERVACAO e' recurso soberano com fonte unica propria; o loader
    // de contexto avaliativo nao se aplica a ela.
    entrada.alvo.type !== "observation"
      ? await deps.carregarContextoAvaliacao({
          target: entrada.alvo,
          organizationId: atorComVinculo.actorContext.organizationId,
        })
      : null;

  const domainState =
    entrada.alvo.type === "goal"
      ? estadoDominioMeta({
          status: recurso.status ?? "",
          excluida: recurso.excluida === true,
          cicloStatus: recurso.cicloStatus ?? "",
        })
      : entrada.alvo.type === "cycle"
        ? estadoDominioCiclo({ status: recurso.status ?? "" })
        : entrada.alvo.type === "observation"
          ? // F5-11 P4 (§8; D3/D5/D7/D9/D11/D12): a OBSERVAÇÃO é recurso SOBERANO e o
            // probe passa a ser DERIVADO da LINHA carregada em (7) — `comunicado`,
            // `excluida`, status do CICLO e status do colaborador-ALVO — pela fonte
            // única `estadoDominioObservacao`, composta com a AUTORIA D5 (autor da
            // própria LINHA × vínculo do ator) e com a leitura SELF-comunicada.
            // O estado declarado pelo chamador (`entrada.domainState`) NUNCA é
            // autoridade neste alvo (invariante 1 do §8) e nada além da regra do
            // domínio é liberado (fail-closed).
            probeObservacaoSoberana(recurso, atorComVinculo.actorContext.collaboratorId)
          : // F5-11 P4 (§8 linha 4; D11/D12): a CRIAÇÃO de observação é FUNCIONAL
            // sobre o COLABORADOR-ALVO (a observação ainda não existe — `criar` não
            // tem `observation_id`). O probe vem do contexto SOBERANO do alvo
            // (status do CICLO + status vigente do colaborador, ambos resolvidos
            // server-side) e compõe a regra SELF = DENY do invariante 4.
            // `entrada.domainState` NUNCA é consultado neste ramo.
            entrada.capability === "observation.create" &&
            entrada.alvo.type === "collaborator"
            ? probeObservacaoSoberanaDeCriacao({
                cicloStatus: contextoAvaliacao?.cicloStatus,
                colaboradorStatus: contextoAvaliacao?.colaboradorStatus,
                atorEhOColaboradorAlvo:
                  atorComVinculo.actorContext.collaboratorId !== null &&
                  atorComVinculo.actorContext.collaboratorId === entrada.alvo.id,
              })
            : contextoAvaliacao
          ? entrada.alvo.type === "evaluation"
            ? estadoDominioAvaliacao({
                status: contextoAvaliacao.status,
                ...(contextoAvaliacao.encerradaComPendencias === undefined
                  ? {}
                  : { encerradaComPendencias: contextoAvaliacao.encerradaComPendencias }),
              })
            : estadoDominioCriacaoAvaliacao({
                cicloPermiteNovaAvaliacao: contextoAvaliacao.cicloPermiteNovaAvaliacao === true,
                avaliadoApto: contextoAvaliacao.avaliadoApto === true,
              })
          : entrada.domainState;

  const recursoContexto = montarResourceContextSoberano({
    recurso,
    organizationIdEsperada: atorComVinculo.actorContext.organizationId,
    ...(domainState ? { domainState } : {}),
  });
  if (!recursoContexto.ok) {
    return recursoContexto.motivo === "TENANT_DIVERGENTE"
      ? negar("CROSS_TENANT")
      : negar("TARGET_INVALID");
  }

  // 7.1.1) aprovadores CONGELADOS da meta (F5-10 P4, §9.1/D14/D25): resolvidos
  // somente para o alvo `goal` e SOMENTE depois do identificador/tenant da linha
  // validados (mesma ordem de `resolverAssigned`). O resultado entra no
  // `ResourceContext` (bloco `meta`) — único caminho pelo qual o provider
  // conhece as relações de aprovação; ele NUNCA consulta estrutura viva.
  // `null` ⇒ sem papel reconhecido (fail-closed nas relações de aprovação).
  const aprovadoresCongelados =
    deps.resolverAprovadorCongelado && entrada.alvo.type === "goal"
      ? await deps.resolverAprovadorCongelado({
          authUserId: entrada.authUserId,
          collaboratorId: atorComVinculo.actorContext.collaboratorId,
          organizationId: atorComVinculo.actorContext.organizationId,
          target: entrada.alvo,
          ...(recursoContexto.resourceContext.cycleId
            ? { cycleId: recursoContexto.resourceContext.cycleId }
            : {}),
        })
      : null;

  const resourceContext: ResourceContext =
    aprovadoresCongelados && recursoContexto.resourceContext.meta
      ? {
          ...recursoContexto.resourceContext,
          meta: {
            ...recursoContexto.resourceContext.meta,
            aprovadoresCongelados,
          },
        }
      : recursoContexto.resourceContext;

  // 7.2) ASSIGNED soberano POR OPERAÇÃO (F5-06, F3-08/F3-09): resolvido somente
  // depois de conhecidos o vínculo do ator, o tenant validado e o CICLO do
  // recurso. `null` ⇒ sem ASSIGNED (o provider nega o alcance — fail-closed).
  const blocoAssigned = deps.resolverAssigned
    ? await deps.resolverAssigned({
        authUserId: entrada.authUserId,
        collaboratorId: atorComVinculo.actorContext.collaboratorId,
        organizationId: atorComVinculo.actorContext.organizationId,
        target: entrada.alvo,
        ...(resourceContext.cycleId ? { cycleId: resourceContext.cycleId } : {}),
      })
    : null;

  // 8) alvos por scope (F4-02/F3) para os scopes efetivos do ator.
  // ORGANIZATIONAL_UNIT é resolvido por unidade-alvo da atribuição (F4-02);
  // os demais scopes não usam unidade.
  const unidadesPorScope = new Map<ScopeType, string[]>();
  for (const item of capabilities) {
    for (const scope of item.scopes) {
      if (scope !== "ORGANIZATIONAL_UNIT") continue;
      const atuais = unidadesPorScope.get(scope) ?? [];
      for (const unitId of item.unitIds ?? []) {
        if (!atuais.includes(unitId)) atuais.push(unitId);
      }
      unidadesPorScope.set(scope, atuais);
    }
  }

  const escoposNecessarios = Array.from(
    new Set(capabilities.flatMap((item) => item.scopes))
  );
  const escoposResolvidos = [];
  for (const scope of escoposNecessarios) {
    const unidades =
      scope === "ORGANIZATIONAL_UNIT" ? (unidadesPorScope.get(scope) ?? [null]) : [null];
    for (const unitId of unidades) {
      const alvos = await deps.resolverAlvosEscopo({
        authUserId: entrada.authUserId,
        organizationId: atorComVinculo.actorContext.organizationId,
        scope,
        unitId,
        data: instanteSoberano,
      });
      escoposResolvidos.push({ scope, unitId, alvos });
    }
  }

  // 9) providers reais (dados da operação; sem cache entre requisições — D10)
  const providers = criarProvidersReais({
    actorId: atorComVinculo.actorContext.identity.authUserId,
    collaboratorId: atorComVinculo.actorContext.collaboratorId,
    organizationId: atorComVinculo.actorContext.organizationId,
    perfilAtivo: atorComVinculo.actorContext.identity.perfil.status === "active",
    membershipAtiva: atorComVinculo.actorContext.membership.status === "active",
    capabilities,
    escoposResolvidos,
    alvo: resourceContext.target,
    tenantDoAlvo: resourceContext.organizationId,
    // F5-06/F5-10 P4: DONO do recurso (colaborador avaliado na avaliação;
    // titular da meta em `evaluation_goals.collaborator_id`), quando houver.
    ...(resourceContext.ownerCollaboratorId
      ? { donoDoAlvo: resourceContext.ownerCollaboratorId }
      : {}),
    // F5-10 P4 (§9.1): bloco soberano da META — o provider conhece as relações
    // de aprovação EXCLUSIVAMENTE pelos ids congelados daqui (nunca de
    // estrutura viva).
    ...(resourceContext.meta ? { metaDoAlvo: resourceContext.meta } : {}),
    // F5-11 P5 (§8 linha 3; D5): bloco soberano da OBSERVAÇÃO — o provider passa
    // a conhecer o AUTOR pela própria LINHA (nunca de estrutura viva).
    ...(resourceContext.observacao ? { observacaoDoAlvo: resourceContext.observacao } : {}),
    ...(deps.assigned ? { assigned: deps.assigned } : {}),
    // ASSIGNED resolvido POR OPERAÇÃO (F5-06): tem precedência sobre um valor
    // estático injetado, porque reflete o ator/ciclo/alvo reais desta decisão.
    ...(blocoAssigned ? { assigned: blocoAssigned } : {}),
    ...(deps.temporary ? { temporary: deps.temporary } : {}),
    ...(deps.exceptional ? { exceptional: deps.exceptional } : {}),
    ...(deps.pilot ? { pilot: deps.pilot } : {}),
  });

  // 10) requisição do engine (contrato F4-03 inalterado) + decisão
  const request = montarRequisicaoAutorizacao({
    actorContext: atorComVinculo.actorContext,
    resourceContext,
    capability: entrada.capability,
    instanteSoberano,
  });
  if (!request) return negar("INDETERMINATE");

  return podeOperacao(request, providers);
}
