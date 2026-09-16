// F5-11 P4 (Issue #248): núcleo TESTÁVEL do caminho server-side de OBSERVAÇÕES.
//
// Compartilhado entre a Edge Function (Deno) e os testes (Vitest). NÃO contém
// APIs de runtime (Deno/Node): as dependências são INJETADAS.
//
// MODELO DE PRODUÇÃO (decisão × execução SEPARADAS — §6.7/§8, molde `metas`):
//
//   usuário autenticado (JWT no header `Authorization`)
//   → [resolveCaller] identidade SOBERANA via `auth.getUser(JWT)`;
//   → forma da intenção validada (allowlist ESTRITA por operação; forma nunca é
//     autoridade);
//   → tenant REVALIDADO contra membership ativa da identidade (o
//     `organization_id` do corpo é intenção, nunca autoridade — §8 invariante 1);
//   → [avaliarGate] por operação: FUNCIONAL = Policy Engine com recurso REAL
//     (`{type:"observation", id: UUID}` — a observação é a identidade canônica,
//     D1 — ou `{type:"collaborator", id}` na CRIAÇÃO, quando a observação ainda
//     não existe); ADMINISTRATIVO = capability efetiva do ator na organização
//     (D19/D21) — é o plano da LISTAGEM por escopo, que não tem UM alvo
//     autorizável (§8 linha 1/D22) e tem o escopo/relação decididos pela RPC;
//   → SOMENTE com ALLOW: [executarRpc] chama a RPC `observacao_*` com a
//     credencial privilegiada (SEM propagar o JWT do usuário) e com o ator
//     VERIFICADO (`auth.uid`) como parâmetro;
//   → a RPC revalida ator/tenant/capability/escopo/relação/autoria/estado/versão
//     e grava a trilha na MESMA transação.
//
// O gate das RPCs (`f5_11_exigir_autorizacao_observacao` — gate FUNCIONAL ÚNICO da
// P2, reescrito na P3) aplica CUMULATIVAMENTE: capability efetiva, ESCOPO de
// gestão, RELAÇÃO estrutural, AUTORIA (D5), estado do colaborador (D11) e do ciclo
// (D12); a leitura SELF-comunicada segue a regra específica do domínio (§8 linha
// 2/D7). A fronteira NÃO reimplementa essas invariantes — ela autentica, autoriza
// pelo engine (quem/onde) e executa; a RPC é a dona do domínio (o quê/em que
// estado).
//
// A credencial privilegiada é de EXECUÇÃO, nunca de decisão: o cliente
// privilegiado é criado APENAS no wiring (`index.ts`); este núcleo não o
// menciona, não o cria e não tem caminho alternativo. Se o gate negar, a RPC não
// é chamada. A Edge NÃO reimplementa lifecycle, comunicação, exclusão lógica,
// revogação, trilha, versão, hash canônico, transação nem autoria: essas
// invariantes são das RPCs PostgreSQL (§20/§21).

import {
  DEFINICAO_POR_OPERACAO,
  RPC_POR_OPERACAO,
  capacidadeAdministrativaDaOperacao,
  ehOperacaoFuncional,
  ehOperacaoObservacao,
  validarEntradaObservacao,
  type CodigoPublico,
  type EntradaObservacao,
  type OperacaoObservacao,
} from "../../../src/infrastructure/supabase/observacoes/contrato.ts";
import { capabilityCanonica } from "../../../src/authorization/catalogoCapabilities.ts";
import type { Capability } from "../../../src/authorization/Capability.ts";
import type { AuthIdentity } from "../../../src/auth/tipos.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MENSAGENS: Readonly<Record<CodigoPublico, string>> = {
  FORBIDDEN: "Você não tem permissão para esta operação.",
  NOT_FOUND: "Observação não encontrada.",
  CONFLICT: "Operação recusada pelo estado atual da observação.",
  INVALID_INPUT: "Dados da requisição inválidos.",
  INTERNAL: "Não foi possível concluir a operação.",
  NOT_AUTHORIZED: "Não autorizado.",
  METHOD_NOT_ALLOWED: "Método não permitido.",
};

const STATUS: Readonly<Record<CodigoPublico, number>> = {
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  INVALID_INPUT: 400,
  INTERNAL: 500,
  NOT_AUTHORIZED: 401,
  METHOD_NOT_ALLOWED: 405,
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function erro(codigo: CodigoPublico, mensagem?: string): Response {
  return json({ error: { code: codigo, message: mensagem ?? MENSAGENS[codigo] } }, STATUS[codigo]);
}

/** Erro devolvido pelo executor de RPC (nunca exposto cru ao cliente). */
export interface ErroRpcObservacao {
  code?: string;
  message?: string;
}

export interface ResultadoRpcObservacao {
  readonly data?: unknown;
  readonly error?: ErroRpcObservacao | null;
}

/**
 * Alvo FUNCIONAL do Policy Engine (§8): a OBSERVAÇÃO existente (identidade
 * canônica `evaluation_observations.id` — D1) ou o COLABORADOR-alvo (na criação,
 * quando a observação ainda não existe — molde `goal.criar`). Nunca alvo
 * sintético/global (D22): o UUID é obrigatório e quem o deriva é a fronteira.
 */
export type AlvoFuncionalObservacao =
  | { readonly type: "observation"; readonly id: string }
  | { readonly type: "collaborator"; readonly id: string };

/** Execução privilegiada JÁ autorizada, com o ator VERIFICADO. */
export interface ExecucaoObservacao {
  readonly operacao: OperacaoObservacao;
  readonly organizationId: string;
  /** UUID canônico da observação (`null` em `observacao.criar` e na listagem). */
  readonly observationId: string | null;
  /** UUID do ciclo (`null` fora de `observacao.criar`). */
  readonly cycleId: string | null;
  /** UUID do colaborador-ALVO (intenção validada em `observacao.criar`). */
  readonly collaboratorId: string | null;
  /** `auth.uid()` verificado server-side — NUNCA do corpo. */
  readonly actorUserProfileId: string;
  /** Chave de idempotência do cliente (repassada às MUTAÇÕES, que a usam). */
  readonly operationId: string;
  /** Versão otimista da LINHA alvo (D10) — obrigatória em mutação existente. */
  readonly expectedVersion: number | null;
  readonly tipo: string | null;
  readonly texto: string | null;
  /** Valor PRETENDIDO do comunicado (fato da linha é revalidado na RPC — D7). */
  readonly comunicado: boolean | null;
  readonly motivo: string | null;
  /** Escopo pedido na listagem (allowlist fechada na RPC — §8 linha 1/2). */
  readonly escopo: string | null;
  /**
   * Unidade organizacional do recorte (intenção OPCIONAL, UUID validado): o
   * ESCOPO de gestão continua resolvido server-side pela RPC.
   */
  readonly organizationalUnitId: string | null;
}

export interface DepsObservacoes {
  /** Identidade soberana a partir do JWT via `auth.getUser`. */
  resolveCaller(authHeader: string): Promise<string | null>;
  /** Identidade/perfil/memberships (F5-01/F5-03) — revalida o tenant do corpo. */
  resolverIdentidade(authUserId: string): Promise<AuthIdentity | null>;
  /** Capabilities efetivas (F5-04) — plano administrativo (D19). */
  resolverCapabilitiesEfetivas(entrada: {
    readonly actorUserProfileId: string;
    readonly organizationId: string;
  }): Promise<readonly { readonly capability_code: string }[]>;
  /**
   * Gate FUNCIONAL: Policy Engine na fronteira confiável (ActorContext real +
   * ResourceContext REAL — a observação com o bloco soberano carregado
   * server-side, ou o colaborador-alvo na criação). Devolve `permitido: false`
   * com o código público quando nega.
   *
   * `cycleId` é a INTENÇÃO já validada em forma (o ciclo da CRIAÇÃO): o estado de
   * domínio do recurso é montado a partir dela pelo wiring, com o STATUS lido
   * SEMPRE da linha soberana do ciclo — nunca declarado pelo corpo.
   */
  avaliarAutorizacao(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
    readonly capability: Capability;
    readonly alvo: AlvoFuncionalObservacao;
    readonly cycleId?: string | null;
  }): Promise<{ readonly permitido: boolean; readonly code?: CodigoPublico }>;
  /** Executa a RPC `observacao_*` com credencial privilegiada e ator verificado. */
  executarRpc(execucao: ExecucaoObservacao): Promise<ResultadoRpcObservacao>;
}

/**
 * Erro da RPC → código público. As RPCs usam o prefixo `F5_11_*` (§20/§21); um
 * erro SEM prefixo conhecido é `INTERNAL` (fail-closed: a fronteira NUNCA inventa
 * conflito de domínio e nenhum prefixo de OUTRO domínio é aceito — cai no
 * fallback).
 */
export function codigoDeErroRpc(erroRpc: ErroRpcObservacao): CodigoPublico {
  const texto = `${erroRpc.message ?? ""}`;
  if (texto.includes("F5_11_FORBIDDEN")) return "FORBIDDEN";
  if (texto.includes("F5_11_NOT_FOUND")) return "NOT_FOUND";
  if (texto.includes("F5_11_CONFLICT")) return "CONFLICT";
  if (texto.includes("F5_11_INVALID_INPUT")) return "INVALID_INPUT";
  return "INTERNAL";
}

/**
 * Corpo 2xx que carrega `error` (formato `{ error: { code, message } }`): mesma
 * tradução do caminho de transporte. Corpo sem forma de erro ⇒ `null` (fail-closed:
 * um `error` vazio não é sucesso nem erro declarado — o chamador decide).
 */
function erroDoCorpoRpc(dados: unknown): ErroRpcObservacao | null {
  if (typeof dados !== "object" || dados === null || Array.isArray(dados)) return null;
  const interno = (dados as { error?: unknown }).error;
  if (typeof interno !== "object" || interno === null || Array.isArray(interno)) return null;
  const erro = interno as ErroRpcObservacao;
  if (erro.code === undefined && erro.message === undefined) return null;
  return erro;
}

/**
 * Corpo 2xx que declara `ok` DIFERENTE de `true`: nunca é sucesso presumido
 * (terceiro caminho de resposta do molde). O payload soberano das RPCs não
 * carrega `ok` — a AUSÊNCIA da chave não é inconsistência; a PRESENÇA com valor
 * diferente de `true` é (fail-closed ⇒ `INTERNAL`).
 */
function okExplicitoDiferenteDeTrue(dados: unknown): boolean {
  if (typeof dados !== "object" || dados === null || Array.isArray(dados)) return false;
  const bruto = dados as Record<string, unknown>;
  return Object.prototype.hasOwnProperty.call(bruto, "ok") && bruto.ok !== true;
}

/**
 * Tenant do corpo REVALIDADO contra a identidade soberana (§8 invariante 1):
 * sem perfil ativo, sem membership ativa naquela organização ou identidade
 * inexistente ⇒ DENY, antes de qualquer gate e sem tocar RPC privilegiada.
 */
function tenantDoAtorValido(
  identidade: AuthIdentity | null,
  organizationId: string
): CodigoPublico | null {
  if (!identidade || !identidade.authUserId) return "NOT_AUTHORIZED";
  if (identidade.perfil?.status !== "active") return "FORBIDDEN";
  const membership = (identidade.memberships ?? []).some(
    (item) => item.organizationId === organizationId && item.status === "active"
  );
  return membership ? null : "FORBIDDEN";
}

/**
 * Alvo FUNCIONAL por operação (§8) — mapa FECHADO, sem default permissivo:
 * - `observacao.criar`: a observação AINDA NÃO EXISTE; o alvo é o COLABORADOR-alvo
 *   do ciclo (a relação estrutural é avaliada sobre ele — §8 linha 4) e o próprio
 *   colaborador é revalidado na RPC (D11);
 * - demais operações funcionais: a OBSERVAÇÃO existente (identidade canônica, D1),
 *   cujo bloco soberano é carregado pelo wiring (`carregarRecurso`).
 * Sem o UUID exigido ⇒ `null` ⇒ a fronteira recusa (`INVALID_INPUT`).
 *
 * A LISTAGEM por escopo NÃO chega aqui: o contrato a declara ADMINISTRATIVA
 * (§8 linha 1 — leitura sem alvo único autorizável) e o gate a decide por
 * capability efetiva, sem alvo no engine.
 */
function alvoFuncionalDaOperacao(entrada: EntradaObservacao): AlvoFuncionalObservacao | null {
  if (entrada.operacao === "observacao.criar") {
    const id = entrada.collaborator_id;
    return id ? { type: "collaborator", id } : null;
  }
  const id = entrada.observation_id;
  return id ? { type: "observation", id } : null;
}

/**
 * Gate por operação (§8) — funcional (engine com recurso REAL) ou administrativo
 * (capability efetiva, D19/D21), SEM default permissivo e sem atalho local.
 *
 * Antes de decidir, a fronteira fecha o CONTRATO: operação fora do mapa, capability
 * não canônica/fora do namespace de observação ou operação sem RPC contratada ⇒
 * NEGA (fail-closed), sem tocar a credencial privilegiada.
 */
async function avaliarGate(
  callerId: string,
  entrada: EntradaObservacao,
  deps: DepsObservacoes
): Promise<CodigoPublico | null> {
  const definicao = DEFINICAO_POR_OPERACAO[entrada.operacao];
  if (!definicao) return "FORBIDDEN";

  // Fail-closed do vocabulário E do domínio: a capability exigida tem de existir
  // no catálogo canônico (F5-04) e pertencer a ESTE domínio.
  const canonica = capabilityCanonica(definicao.capability);
  if (!canonica || !canonica.startsWith("observation.")) return "FORBIDDEN";

  // Operação sem RPC soberana contratada não é despachável (mapa 1:1 congelado).
  if (!RPC_POR_OPERACAO[entrada.operacao]) return "FORBIDDEN";

  // ADMINISTRATIVO (D19/D21, §8 linha 1): o contrato declara administrativa a
  // operação SEM alvo único autorizável (a LISTAGEM por escopo). O plano
  // administrativo confere a CAPABILITY EFETIVA do ator na organização e a RPC
  // soberana aplica o ESCOPO pedido e a RELAÇÃO resolvida server-side (fonte única
  // do alcance) — nenhum alvo sintético vai ao engine (D22).
  if (!ehOperacaoFuncional(entrada.operacao)) {
    // Sem definição administrativa a capacidade é `null` ⇒ NEGA (sem default).
    const capacidade = capacidadeAdministrativaDaOperacao(entrada.operacao);
    const canonicaAdministrativa = capacidade ? capabilityCanonica(capacidade) : undefined;
    if (!canonicaAdministrativa) return "FORBIDDEN";

    const capabilities = await deps.resolverCapabilitiesEfetivas({
      actorUserProfileId: callerId,
      organizationId: entrada.organization_id,
    });
    const possui = capabilities.some(
      (linha) => linha.capability_code === canonicaAdministrativa
    );
    return possui ? null : "FORBIDDEN";
  }

  // FUNCIONAL: alvo REAL obrigatório (UUID). Nunca alvo sintético.
  const alvo = alvoFuncionalDaOperacao(entrada);
  if (!alvo) return "INVALID_INPUT";

  const decisao = await deps.avaliarAutorizacao({
    authUserId: callerId,
    organizationId: entrada.organization_id,
    capability: canonica,
    alvo,
    // Intenção VALIDADA em forma (não autoridade): o ciclo da CRIAÇÃO alimenta o
    // estado de domínio montado no wiring — o STATUS vem da linha soberana.
    cycleId: entrada.cycle_id ?? null,
  });
  return decisao.permitido ? null : (decisao.code ?? "FORBIDDEN");
}

/**
 * Fronteira de observações. Ordem INEGOCIÁVEL: método → JWT → forma → tenant
 * revalidado → gate → execução privilegiada.
 */
export async function observacoes(req: Request, deps: DepsObservacoes): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return erro("METHOD_NOT_ALLOWED");
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return erro("NOT_AUTHORIZED");

  // 1) identidade soberana (nunca do corpo).
  const callerId = await deps.resolveCaller(authHeader);
  if (!callerId) return erro("NOT_AUTHORIZED");

  // 2) forma da intenção (nunca autoridade) — allowlist ESTRITA por operação:
  // nenhum campo de autoria/tenant/estado/autorização entra no contrato.
  let corpo: unknown;
  try {
    corpo = await req.json();
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.");
  }
  const validacao = validarEntradaObservacao(corpo);
  if (!validacao.ok) {
    return erro("INVALID_INPUT", validacao.message);
  }
  const entrada = validacao.entrada;
  if (!ehOperacaoObservacao(entrada.operacao)) {
    return erro("INVALID_INPUT", "Operação não suportada.");
  }

  // 3) tenant do corpo REVALIDADO contra a identidade (nunca autoridade).
  const identidade = await deps.resolverIdentidade(callerId);
  const problemaTenant = tenantDoAtorValido(identidade, entrada.organization_id);
  if (problemaTenant) return erro(problemaTenant);

  // 4) GATE por operação (funcional × administrativo) — nenhum default.
  const negacao = await avaliarGate(callerId, entrada, deps);
  if (negacao) return erro(negacao);

  // 5) execução privilegiada com o ATOR VERIFICADO (JWT nunca propagado).
  const resultado = await deps.executarRpc({
    operacao: entrada.operacao,
    organizationId: entrada.organization_id,
    observationId: entrada.observation_id ?? null,
    cycleId: entrada.cycle_id ?? null,
    collaboratorId: entrada.collaborator_id ?? null,
    actorUserProfileId: callerId,
    operationId: entrada.operation_id,
    expectedVersion: entrada.expected_version ?? null,
    tipo: entrada.tipo ?? null,
    texto: entrada.texto ?? null,
    comunicado: entrada.comunicado ?? null,
    motivo: entrada.motivo ?? null,
    escopo: entrada.escopo ?? null,
    organizationalUnitId: entrada.organizational_unit_id ?? null,
  });

  // Caminho 1 — erro de EXECUÇÃO devolvido pelo executor (nunca exposto cru).
  if (resultado.error) {
    return erro(codigoDeErroRpc(resultado.error));
  }

  // Caminho 2 — corpo 2xx carregando `error`: mesma tradução fail-closed.
  const erroNoCorpo = erroDoCorpoRpc(resultado.data);
  if (erroNoCorpo) {
    return erro(codigoDeErroRpc(erroNoCorpo));
  }

  // Caminho 3 — corpo 2xx que declara `ok` diferente de `true`: nunca sucesso.
  if (okExplicitoDiferenteDeTrue(resultado.data)) {
    return erro("INTERNAL", "Resposta inesperada do servidor.");
  }

  return json({ ok: true, operacao: entrada.operacao, resultado: resultado.data ?? null }, 200);
}

/** Exposto para testes de contrato do mapa de operações. */
export { DEFINICAO_POR_OPERACAO, ehOperacaoFuncional, ehOperacaoObservacao };
