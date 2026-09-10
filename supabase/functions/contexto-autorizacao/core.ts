import type { Capability } from "../../../src/authorization/Capability.ts";
import {
  avaliarOperacaoAutorizacao,
  type DepsContextoAutorizacao,
} from "../../../src/authorization/contextoAutorizacao.ts";
import type { TargetRef } from "../../../src/authorization/policyEngine/types.ts";

/**
 * F5-05 (D20) — núcleo testável da fronteira confiável server-side.
 *
 * A Edge Function recebe do CLIENTE apenas:
 *   - o JWT do usuário autenticado (header `Authorization`);
 *   - a INTENÇÃO: organização pretendida, capability pretendida, alvo (tipo+id)
 *     e, opcionalmente, a data de negócio.
 *
 * A identidade soberana é resolvida por `resolveCaller` (auth.getUser) no
 * servidor; a organização é revalidada contra membership ativa; o tenant do
 * recurso é derivado do recurso carregado; o instante da decisão vem do relógio
 * server-side. Nenhum `actor_id` é aceito do cliente.
 *
 * A resposta expõe apenas a decisão + código público F0-05 (nunca razões
 * internas do engine).
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export interface DepsCoreContextoAutorizacao {
  /** Resolve a identidade soberana a partir do JWT (auth.getUser). */
  resolveCaller(authHeader: string): Promise<string | null>;
  /** Portas de dados soberanos (server-side). */
  autorizacao: DepsContextoAutorizacao;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function erro(codigo: string, mensagem: string, status: number): Response {
  return json({ error: { code: codigo, message: mensagem } }, status);
}

interface CorpoRequisicao {
  organization_id?: unknown;
  capability?: unknown;
  target?: unknown;
  data_negocio?: unknown;
}

function alvoDoCorpo(valor: unknown): TargetRef | null {
  if (typeof valor !== "object" || valor === null || Array.isArray(valor)) return null;
  const alvo = valor as Record<string, unknown>;
  const tipo = typeof alvo.type === "string" ? alvo.type : "";
  const id = typeof alvo.id === "string" ? alvo.id : "";
  if (!tipo || !id) return null;
  return { type: tipo, id } as TargetRef;
}

export async function avaliarRequisicaoAutorizacao(
  req: Request,
  deps: DepsCoreContextoAutorizacao
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return erro("METHOD_NOT_ALLOWED", "Método não permitido.", 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }

  // Identidade SOBERANA (server-side). Falha ⇒ 401 (fail-closed).
  const authUserId = await deps.resolveCaller(authHeader);
  if (!authUserId) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }

  let corpo: CorpoRequisicao;
  try {
    corpo = (await req.json()) as CorpoRequisicao;
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.", 400);
  }
  if (typeof corpo !== "object" || corpo === null || Array.isArray(corpo)) {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.", 400);
  }
  const campos = corpo as Record<string, unknown>;

  // A identidade do ator NUNCA é aceita do cliente (D16 F5-04 / D20).
  if (
    "actor_id" in campos ||
    "actor_user_profile_id" in campos ||
    "user_profile_id" in campos ||
    "ator" in campos
  ) {
    return erro("INVALID_INPUT", "Identidade do ator nunca é informada pelo cliente.", 400);
  }

  const organizationId =
    typeof campos.organization_id === "string" ? campos.organization_id : "";
  const capability = typeof campos.capability === "string" ? campos.capability : "";
  const alvo = alvoDoCorpo(campos.target);

  if (!organizationId || !capability || !alvo) {
    return erro("INVALID_INPUT", "Parâmetros inválidos.", 400);
  }

  const decision = await avaliarOperacaoAutorizacao(
    {
      authUserId,
      organizationId,
      capability: capability as Capability,
      alvo,
      dataNegocio: campos.data_negocio,
    },
    deps.autorizacao
  );

  if (decision.allowed) {
    return json({ allowed: true, capability, target: alvo }, 200);
  }

  // Somente o código público F0-05; a razão interna nunca sai do servidor.
  return json(
    {
      allowed: false,
      code: decision.denial?.publicCode ?? "FORBIDDEN",
      capability,
      target: alvo,
    },
    200
  );
}
