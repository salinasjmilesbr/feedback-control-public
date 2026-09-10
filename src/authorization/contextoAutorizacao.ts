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

  // 7.1) ESTADO DE DOMÍNIO derivado server-side (F5-06 §8.1): o cliente pode
  // declarar estado (uso interno/testes), mas quando a fronteira confiável
  // carrega o contexto soberano ele PREVALECE — o browser nunca declara o
  // estado do recurso. Sem contexto para um alvo de avaliação ⇒ DENY.
  const contextoAvaliacao = deps.carregarContextoAvaliacao
    ? await deps.carregarContextoAvaliacao({
        target: entrada.alvo,
        organizationId: atorComVinculo.actorContext.organizationId,
      })
    : null;

  const domainState = contextoAvaliacao
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
    alvo: recursoContexto.resourceContext.target,
    tenantDoAlvo: recursoContexto.resourceContext.organizationId,
    // F5-06: dono do recurso de avaliação (colaborador avaliado), quando houver.
    ...(recursoContexto.resourceContext.ownerCollaboratorId
      ? { avaliadoDoAlvo: recursoContexto.resourceContext.ownerCollaboratorId }
      : {}),
    ...(deps.assigned ? { assigned: deps.assigned } : {}),
    ...(deps.temporary ? { temporary: deps.temporary } : {}),
    ...(deps.exceptional ? { exceptional: deps.exceptional } : {}),
    ...(deps.pilot ? { pilot: deps.pilot } : {}),
  });

  // 10) requisição do engine (contrato F4-03 inalterado) + decisão
  const request = montarRequisicaoAutorizacao({
    actorContext: atorComVinculo.actorContext,
    resourceContext: recursoContexto.resourceContext,
    capability: entrada.capability,
    instanteSoberano,
  });
  if (!request) return negar("INDETERMINATE");

  return podeOperacao(request, providers);
}
