// F5-09 P7 (Issue #202): núcleo TESTÁVEL do caminho server-side de CICLOS.
//
// Compartilhado entre a Edge Function (Deno) e os testes (Vitest). NÃO contém
// APIs de runtime (Deno/Node): as dependências são INJETADAS.
//
// MODELO DE PRODUÇÃO (decisão × execução SEPARADAS — §2/D25):
//
//   usuário autenticado (JWT no header `Authorization`)
//   → [resolveCaller] identidade SOBERANA via `auth.getUser(JWT)`;
//   → forma da intenção validada (allowlist estrita; forma nunca é autoridade);
//   → tenant REVALIDADO contra membership ativa da identidade (o
//     `organization_id` do corpo é intenção, nunca autoridade — §13.1 regra 8);
//   → [avaliarGate] por operação: FUNCIONAL = Policy Engine com recurso REAL
//     (`{type:"cycle", id: UUID}` carregado server-side, com o status da linha
//     soberana — P5/P6); ADMINISTRATIVO = capability efetiva do ator na
//     organização (D19/D21, `cycle.criar` sem alvo sintético);
//   → SOMENTE com ALLOW: [executarRpc] chama a RPC `ciclo_*` com a credencial
//     service_role (SEM propagar o JWT do usuário) e com o ator VERIFICADO
//     (`auth.uid`) como parâmetro;
//   → a RPC revalida ator/tenant/capability/estado/versão/idempotência e grava a
//     trilha na MESMA transação.
//
// `service_role` é credencial de EXECUÇÃO, nunca de decisão: se o gate negar, a
// RPC não é chamada e não existe caminho alternativo. A Edge NÃO reimplementa
// lifecycle (PLANEJADO→ATIVO etc.), versão, sobreposição, unicidade de ATIVO,
// transação, materialização, admissão ou autoria: essas invariantes são das RPCs
// PostgreSQL (§13.3).

import {
  DEFINICAO_POR_OPERACAO,
  capacidadeAdministrativaDaOperacao,
  ehOperacaoFuncional,
  ehOperacaoCiclo,
  validarEntradaCiclo,
  type CodigoPublico,
  type EntradaCiclo,
  type OperacaoCiclo,
} from "../../../src/infrastructure/supabase/ciclos/contrato.ts";
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
  NOT_FOUND: "Ciclo não encontrado.",
  CONFLICT: "Operação recusada pelo estado atual do ciclo.",
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
export interface ErroRpcCiclo {
  code?: string;
  message?: string;
}

export interface ResultadoRpcCiclo {
  readonly data?: unknown;
  readonly error?: ErroRpcCiclo | null;
}

/** Execução privilegiada JÁ autorizada, com o ator VERIFICADO. */
export interface ExecucaoCiclo {
  readonly operacao: OperacaoCiclo;
  readonly organizationId: string;
  /** UUID canônico do ciclo (`null` apenas em `cycle.criar`). */
  readonly cycleId: string | null;
  /** `auth.uid()` verificado server-side — NUNCA do corpo. */
  readonly actorUserProfileId: string;
  /** Chave de idempotência do cliente (repassada à RPC, que é idempotente). */
  readonly operationId: string;
  readonly expectedVersion: number | null;
  readonly ano: number | null;
  readonly numero: number | null;
  readonly dataInicio: string | null;
  readonly dataFim: string | null;
  readonly motivo: string | null;
  readonly justificativa: string | null;
  /** UUID do colaborador (admissão): resolvido da intenção na fronteira. */
  readonly collaboratorId: string | null;
}

export interface DepsCiclos {
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
   * ResourceContext REAL do ciclo + capabilities×scopes + domainState do status
   * soberano). Devolve `permitido: false` com o código público quando nega.
   */
  avaliarAutorizacao(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
    readonly capability: Capability;
    readonly alvo: { readonly type: "cycle"; readonly id: string };
  }): Promise<{ readonly permitido: boolean; readonly code?: CodigoPublico }>;
  /** Ponte matrícula → UUID (F3-01) para `cycle.admissao.incluir`. */
  resolverMatricula?(
    matricula: number | string,
    organizationId: string
  ): Promise<string | null>;
  /** Executa a RPC `ciclo_*` com credencial privilegiada e ator verificado. */
  executarRpc(execucao: ExecucaoCiclo): Promise<ResultadoRpcCiclo>;
}

/**
 * Erro da RPC → código público. Os RPCs usam o prefixo `F5_09_*` (§13.2); um
 * erro SEM prefixo conhecido é `INTERNAL` (nunca um conflito de domínio
 * inventado pela fronteira).
 */
export function codigoDeErroRpc(erroRpc: ErroRpcCiclo): CodigoPublico {
  const texto = `${erroRpc.message ?? ""}`;
  if (texto.includes("F5_09_FORBIDDEN")) return "FORBIDDEN";
  if (texto.includes("F5_09_NOT_FOUND")) return "NOT_FOUND";
  if (texto.includes("F5_09_CONFLICT")) return "CONFLICT";
  if (texto.includes("F5_09_INVALID_INPUT")) return "INVALID_INPUT";
  if (texto.includes("F5_09_NOT_AUTHORIZED")) return "NOT_AUTHORIZED";
  if (texto.includes("F5_09_INTERNAL")) return "INTERNAL";
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

/** Gate por operação — funcional (engine) ou administrativo (D19), sem default. */
async function avaliarGate(
  callerId: string,
  entrada: EntradaCiclo,
  deps: DepsCiclos
): Promise<CodigoPublico | null> {
  const definicao = DEFINICAO_POR_OPERACAO[entrada.operacao];
  if (!definicao) return "FORBIDDEN";

  if (!ehOperacaoFuncional(entrada.operacao)) {
    // ADMINISTRATIVO (D21): capability efetiva do ator na organização. Operação
    // sem definição administrativa ⇒ capacidade `null` ⇒ NEGA (sem default).
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

  // FUNCIONAL: alvo REAL obrigatório (UUID do ciclo). Nunca alvo sintético.
  const cycleId = entrada.cycle_id;
  if (!cycleId) return "INVALID_INPUT";

  const canonica = capabilityCanonica(definicao.capability);
  if (!canonica) return "FORBIDDEN";

  const decisao = await deps.avaliarAutorizacao({
    authUserId: callerId,
    organizationId: entrada.organization_id,
    capability: canonica,
    alvo: { type: "cycle", id: cycleId },
  });
  return decisao.permitido ? null : (decisao.code ?? "FORBIDDEN");
}

/**
 * Fronteira de ciclos. Ordem INEGOCIÁVEL: método → JWT → forma → tenant
 * revalidado → gate → execução privilegiada.
 */
export async function ciclos(req: Request, deps: DepsCiclos): Promise<Response> {
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
  const validacao = validarEntradaCiclo(corpo);
  if (!validacao.ok) {
    return erro("INVALID_INPUT", validacao.message);
  }
  const entrada = validacao.entrada;
  if (!ehOperacaoCiclo(entrada.operacao)) return erro("INVALID_INPUT", "Operação não suportada.");

  // 3) tenant do corpo REVALIDADO contra a identidade (nunca autoridade).
  const identidade = await deps.resolverIdentidade(callerId);
  const problemaTenant = tenantDoAtorValido(identidade, entrada.organization_id);
  if (problemaTenant) return erro(problemaTenant);

  // 3.1) Admissão: a matrícula é INTENÇÃO; o UUID do colaborador é resolvido
  // AQUI na fronteira confiável (F3-01). Sem resolução ⇒ recusa, sem RPC.
  let collaboratorId: string | null = entrada.collaborator_id ?? null;
  if (entrada.operacao === "cycle.admissao.incluir" && !collaboratorId) {
    const matricula = entrada.matricula;
    if (matricula === undefined || !deps.resolverMatricula) {
      return erro("INVALID_INPUT", "Colaborador da admissão não resolvido.");
    }
    const resolvido = await deps.resolverMatricula(matricula, entrada.organization_id);
    if (!resolvido) {
      return erro("INVALID_INPUT", "Colaborador da admissão não resolvido.");
    }
    collaboratorId = resolvido;
  }

  // 4) GATE por operação (funcional × administrativo) — nenhum default.
  const negacao = await avaliarGate(callerId, entrada, deps);
  if (negacao) return erro(negacao);

  // 5) execução privilegiada com o ATOR VERIFICADO (JWT nunca propagado).
  const resultado = await deps.executarRpc({
    operacao: entrada.operacao,
    organizationId: entrada.organization_id,
    cycleId: entrada.cycle_id ?? null,
    actorUserProfileId: callerId,
    operationId: entrada.operation_id,
    expectedVersion: entrada.expected_version ?? null,
    ano: entrada.ano ?? null,
    numero: entrada.numero ?? null,
    dataInicio: entrada.data_inicio ?? null,
    dataFim: entrada.data_fim ?? null,
    motivo: entrada.motivo ?? null,
    justificativa: entrada.justificativa ?? null,
    collaboratorId,
  });

  if (resultado.error) {
    const codigo = codigoDeErroRpc(resultado.error);
    return erro(codigo);
  }

  return json({ ok: true, operacao: entrada.operacao, resultado: resultado.data ?? null }, 200);
}

/** Exposto para testes de contrato do mapa de operações. */
export { DEFINICAO_POR_OPERACAO, ehOperacaoFuncional, ehOperacaoCiclo };
