// F5-10 P5 (Issue #218): núcleo TESTÁVEL do caminho server-side de METAS.
//
// Compartilhado entre a Edge Function (Deno) e os testes (Vitest). NÃO contém
// APIs de runtime (Deno/Node): as dependências são INJETADAS.
//
// MODELO DE PRODUÇÃO (decisão × execução SEPARADAS — §13/D19/D25):
//
//   usuário autenticado (JWT no header `Authorization`)
//   → [resolveCaller] identidade SOBERANA via `auth.getUser(JWT)`;
//   → forma da intenção validada (allowlist estrita; forma nunca é autoridade);
//   → tenant REVALIDADO contra membership ativa da identidade (o
//     `organization_id` do corpo é intenção, nunca autoridade — §13.1 regra 8);
//   → [avaliarGate] por operação: FUNCIONAL = Policy Engine com recurso REAL
//     (`{type:"goal", id: UUID}` para meta existente, `{type:"collaborator", id}`
//     em `goal.criar` — a meta ainda não existe — e `{type:"cycle", id}` em
//     `goal.definir_limites_do_ciclo`); ADMINISTRATIVO = capability efetiva do
//     ator na organização (`goal.listar_por_escopo`, cujo ESCOPO é aplicado pela
//     RPC soberana — fonte única da relação);
//   → SOMENTE com ALLOW: [executarRpc] chama a RPC `meta_*` com a credencial
//     privilegiada (SEM propagar o JWT do usuário) e com o ator VERIFICADO
//     (`auth.uid`) como parâmetro;
//   → a RPC revalida ator/tenant/capability/relação/estado/versão/idempotência e
//     grava a trilha na MESMA transação.
//
// A credencial privilegiada é de EXECUÇÃO, nunca de decisão: o cliente
// privilegiado é criado APENAS no wiring Deno (`index.ts`); este núcleo não o
// menciona, não o cria e não tem caminho alternativo. Se o gate negar, a RPC não
// é chamada. A Edge NÃO reimplementa lifecycle (`EM_ANDAMENTO`→`ATINGIDA`…),
// versão, quota do ciclo, exclusão lógica, invalidação de aprovações, hash
// canônico, transação nem autoria: essas invariantes são das RPCs PostgreSQL.

import {
  DEFINICAO_POR_OPERACAO,
  capacidadeAdministrativaDaOperacao,
  ehOperacaoFuncional,
  ehOperacaoMeta,
  validarEntradaMeta,
  type CodigoPublico,
  type EntradaMeta,
  type OperacaoMeta,
} from "../../../src/infrastructure/supabase/metas/contrato.ts";
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
  NOT_FOUND: "Meta não encontrada.",
  CONFLICT: "Operação recusada pelo estado atual da meta.",
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
export interface ErroRpcMeta {
  code?: string;
  message?: string;
}

export interface ResultadoRpcMeta {
  readonly data?: unknown;
  readonly error?: ErroRpcMeta | null;
}

/**
 * Alvo FUNCIONAL do Policy Engine (§B.5 do recon): a META existente, o
 * COLABORADOR dono (na criação, quando a meta ainda não existe) ou o CICLO (nos
 * limites de quota). Nunca alvo sintético/global (D22).
 */
export type AlvoFuncionalMeta =
  | { readonly type: "goal"; readonly id: string }
  | { readonly type: "collaborator"; readonly id: string }
  | { readonly type: "cycle"; readonly id: string };

/** Execução privilegiada JÁ autorizada, com o ator VERIFICADO. */
export interface ExecucaoMeta {
  readonly operacao: OperacaoMeta;
  readonly organizationId: string;
  /** UUID canônico da meta (`null` em `goal.criar` e nos limites do ciclo). */
  readonly goalId: string | null;
  /** UUID do ciclo (`null` fora de `goal.criar`/`goal.definir_limites_do_ciclo`). */
  readonly cycleId: string | null;
  /** UUID do colaborador DONO (intenção validada em `goal.criar`). */
  readonly collaboratorId: string | null;
  /** `auth.uid()` verificado server-side — NUNCA do corpo. */
  readonly actorUserProfileId: string;
  /** Chave de idempotência do cliente (repassada à RPC, que é idempotente). */
  readonly operationId: string;
  readonly expectedVersion: number | null;
  readonly tipo: string | null;
  readonly descricao: string | null;
  readonly kpi: string | null;
  readonly valorAlvo: string | null;
  readonly resultadoAtual: string | null;
  readonly progressoPercentual: number | null;
  readonly resultadoFinal: string | null;
  readonly atingida: boolean | null;
  readonly papel: string | null;
  readonly quantidade: number | null;
  readonly motivo: string | null;
}

export interface DepsMetas {
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
   * ResourceContext REAL — meta com `status`/`excluida` e o `cicloStatus` da
   * LINHA soberana do ciclo, ou o dono na criação). Devolve `permitido: false`
   * com o código público quando nega.
   */
  avaliarAutorizacao(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
    readonly capability: Capability;
    readonly alvo: AlvoFuncionalMeta;
  }): Promise<{ readonly permitido: boolean; readonly code?: CodigoPublico }>;
  /** Executa a RPC `meta_*` com credencial privilegiada e ator verificado. */
  executarRpc(execucao: ExecucaoMeta): Promise<ResultadoRpcMeta>;
}

/**
 * Erro da RPC → código público. As RPCs usam o prefixo `F5_10_*` (§13.2); um
 * erro SEM prefixo conhecido é `INTERNAL` (nunca um conflito de domínio
 * inventado pela fronteira).
 */
export function codigoDeErroRpc(erroRpc: ErroRpcMeta): CodigoPublico {
  const texto = `${erroRpc.message ?? ""}`;
  if (texto.includes("F5_10_FORBIDDEN")) return "FORBIDDEN";
  if (texto.includes("F5_10_NOT_FOUND")) return "NOT_FOUND";
  if (texto.includes("F5_10_CONFLICT")) return "CONFLICT";
  if (texto.includes("F5_10_INVALID_INPUT")) return "INVALID_INPUT";
  if (texto.includes("F5_10_NOT_AUTHORIZED")) return "NOT_AUTHORIZED";
  if (texto.includes("F5_10_INTERNAL")) return "INTERNAL";
  return "INTERNAL";
}

/**
 * Tenant do corpo REVALIDADO contra a identidade soberana (§13.1 regra 8):
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
 * Alvo FUNCIONAL por operação (§B.5) — mapa FECHADO, sem default permissivo:
 * - `goal.criar`: a meta AINDA NÃO EXISTE; o alvo é o DONO (colaborador) e a
 *   relação SELF é avaliada sobre ele;
 * - `goal.definir_limites_do_ciclo`: o recurso é o CICLO (quota do ciclo);
 * - demais operações funcionais: a META existente.
 * Sem o UUID exigido ⇒ `null` ⇒ a fronteira recusa (`INVALID_INPUT`).
 */
function alvoFuncionalDaOperacao(entrada: EntradaMeta): AlvoFuncionalMeta | null {
  if (entrada.operacao === "goal.criar") {
    const id = entrada.collaborator_id;
    return id ? { type: "collaborator", id } : null;
  }
  if (entrada.operacao === "goal.definir_limites_do_ciclo") {
    const id = entrada.cycle_id;
    return id ? { type: "cycle", id } : null;
  }
  const id = entrada.goal_id;
  return id ? { type: "goal", id } : null;
}

/** Gate por operação — funcional (engine) ou administrativo (D19), sem default. */
async function avaliarGate(
  callerId: string,
  entrada: EntradaMeta,
  deps: DepsMetas
): Promise<CodigoPublico | null> {
  const definicao = DEFINICAO_POR_OPERACAO[entrada.operacao];
  if (!definicao) return "FORBIDDEN";

  if (!ehOperacaoFuncional(entrada.operacao)) {
    // ADMINISTRATIVO (D19/D21): capability efetiva do ator na organização. A
    // operação de leitura de terceiros NÃO tem alvo funcional: a relação e o
    // ESCOPO são aplicados pela RPC soberana `meta_listar_por_escopo` (fonte
    // única). Operação sem definição administrativa ⇒ capacidade `null` ⇒ NEGA.
    const capacidade = capacidadeAdministrativaDaOperacao(entrada.operacao);
    const canonica = capacidade ? capabilityCanonica(capacidade) : undefined;
    if (!canonica) return "FORBIDDEN";

    const capabilities = await deps.resolverCapabilitiesEfetivas({
      actorUserProfileId: callerId,
      organizationId: entrada.organization_id,
    });
    const possui = capabilities.some((linha) => linha.capability_code === canonica);
    return possui ? null : "FORBIDDEN";
  }

  // FUNCIONAL: alvo REAL obrigatório (UUID). Nunca alvo sintético.
  const alvo = alvoFuncionalDaOperacao(entrada);
  if (!alvo) return "INVALID_INPUT";

  const canonica = capabilityCanonica(definicao.capability);
  if (!canonica) return "FORBIDDEN";

  const decisao = await deps.avaliarAutorizacao({
    authUserId: callerId,
    organizationId: entrada.organization_id,
    capability: canonica,
    alvo,
  });
  return decisao.permitido ? null : (decisao.code ?? "FORBIDDEN");
}

/**
 * Fronteira de metas. Ordem INEGOCIÁVEL: método → JWT → forma → tenant
 * revalidado → gate → execução privilegiada.
 */
export async function metas(req: Request, deps: DepsMetas): Promise<Response> {
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

  // 2) forma da intenção (nunca autoridade).
  let corpo: unknown;
  try {
    corpo = await req.json();
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.");
  }
  const validacao = validarEntradaMeta(corpo);
  if (!validacao.ok) {
    return erro("INVALID_INPUT", validacao.message);
  }
  const entrada = validacao.entrada;
  if (!ehOperacaoMeta(entrada.operacao)) return erro("INVALID_INPUT", "Operação não suportada.");

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
    goalId: entrada.goal_id ?? null,
    cycleId: entrada.cycle_id ?? null,
    collaboratorId: entrada.collaborator_id ?? null,
    actorUserProfileId: callerId,
    operationId: entrada.operation_id,
    expectedVersion: entrada.expected_version ?? null,
    tipo: entrada.tipo ?? null,
    descricao: entrada.descricao ?? null,
    kpi: entrada.kpi ?? null,
    valorAlvo: entrada.valor_alvo ?? null,
    resultadoAtual: entrada.resultado_atual ?? null,
    progressoPercentual: entrada.progresso_percentual ?? null,
    resultadoFinal: entrada.resultado_final ?? null,
    atingida: entrada.atingida ?? null,
    papel: entrada.papel ?? null,
    quantidade: entrada.quantidade ?? null,
    motivo: entrada.motivo ?? null,
  });

  if (resultado.error) {
    const codigo = codigoDeErroRpc(resultado.error);
    return erro(codigo);
  }

  return json({ ok: true, operacao: entrada.operacao, resultado: resultado.data ?? null }, 200);
}

/** Exposto para testes de contrato do mapa de operações. */
export { DEFINICAO_POR_OPERACAO, ehOperacaoFuncional, ehOperacaoMeta };
