// F5-04 (Issue #165): núcleo testável do caminho server-side de concessão/
// revogação de access roles (D16).
//
// Compartilhado entre a Edge Function (Deno) e os testes (Vitest). NÃO contém
// APIs de runtime (Deno/Node) — as dependências (resolver o chamador e executar
// o RPC) são INJETADAS, o que permite testar o fluxo de produção sem simulação
// privilegiada de `request.jwt.claim.sub`.
//
// Fluxo de produção (D16):
//   usuário autenticado (JWT no header `Authorization`)
//   → componente server-side (Edge Function): service_role SOMENTE para elevar
//     privilégios/BYPASSRLS — nunca para definir o ator;
//   → identidade soberana resolvida via `auth.getUser(JWT)`  [resolveCaller];
//   → RPC administrativo invocado com o MESMO JWT preservado no header
//     `Authorization` → `auth.uid()` resolve para o usuário autenticado;
//   → validação de tenant (membership ativa do ator na organização alvo);
//   → grant/revoke + trilha append-only (D18).
//
// Nenhum `actor_id`/`actor_user_profile_id` é aceito do cliente: a presença
// desses campos no corpo é REJEITADA — a identidade vem do JWT, nunca do payload.

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export type AcaoAcessoRole = "grant" | "revoke";

export interface ErroRpc {
  code?: string;
  message?: string;
}

export interface DepsGerenciarAcessoRole {
  /** Resolve a identidade soberana a partir do JWT (Authorization) via auth.getUser. */
  resolveCaller(authHeader: string): Promise<string | null>;
  /** Executa o RPC administrativo preservando o JWT do usuário (auth.uid()). */
  executarRpc(
    authHeader: string,
    action: AcaoAcessoRole,
    membershipId: string,
    accessRoleId: string
  ): Promise<ErroRpc | null>;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function erro(codigo: string, mensagem: string, status: number): Response {
  return json({ error: { code: codigo, message: mensagem } }, status);
}

export async function gerenciarAcessoRole(
  req: Request,
  deps: DepsGerenciarAcessoRole
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

  const callerId = await deps.resolveCaller(authHeader);
  if (!callerId) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.", 400);
  }

  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.", 400);
  }
  const campos = body as Record<string, unknown>;

  // Nenhum actor_id é confiado ao cliente (D16): rejeita explicitamente.
  if (
    "actor_id" in campos ||
    "actor_user_profile_id" in campos ||
    "ator" in campos
  ) {
    return erro(
      "INVALID_INPUT",
      "Identidade do ator nunca é informada pelo cliente.",
      400
    );
  }

  const membershipId =
    typeof campos.membership_id === "string" ? campos.membership_id : "";
  const accessRoleId =
    typeof campos.access_role_id === "string" ? campos.access_role_id : "";
  const actionRaw = campos.action;
  const action: AcaoAcessoRole | "" =
    actionRaw === "grant" || actionRaw === "revoke" ? actionRaw : "";

  if (!UUID_RE.test(membershipId) || !UUID_RE.test(accessRoleId) || !action) {
    return erro("INVALID_INPUT", "Parâmetros inválidos.", 400);
  }

  const rpcError = await deps.executarRpc(
    authHeader,
    action,
    membershipId,
    accessRoleId
  );
  if (rpcError) {
    // Self-escalation/cross-tenant/tenant inválido => 403 (fail-closed).
    return erro(
      rpcError.code ?? "FORBIDDEN",
      rpcError.message ?? "Operação negada.",
      403
    );
  }

  return json(
    {
      ok: true,
      action,
      membership_id: membershipId,
      access_role_id: accessRoleId,
      caller_id: callerId,
    },
    200
  );
}
