// F5-04 (Issue #165): núcleo testável do caminho server-side de concessão/
// revogação de access roles (D16).
//
// Compartilhado entre a Edge Function (Deno) e os testes (Vitest). NÃO contém
// APIs de runtime (Deno/Node) — as dependências são INJETADAS.
//
// MODELO DE PRODUÇÃO (identidade × execução privilegiada SEPARADAS):
//
//   usuário autenticado (JWT no header `Authorization`)
//   → [resolveCaller] identidade SOBERANA via `auth.getUser(JWT)` (Gotrue);
//   → [executarRpc] operação privilegiada via credencial service_role, SEM o
//     JWT do usuário no `Authorization` (o PostgREST assumiria `authenticated`
//     e perderia o EXECUTE de service_role — por isso o JWT NÃO é propagado);
//   → o ator verificado (user.id) é passado como parâmetro ao RPC, derivado
//     EXCLUSIVAMENTE de identidade autenticada verificada server-side — jamais
//     de payload do cliente (actor_id no corpo é REJEITADO).
//
// O RPC revalida o ator contra o banco (perfil/membership/tenant + autoridade
// administrativa) e grava a trilha D18 com autoria soberana = user.id.

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
  /**
   * Executa o RPC administrativo com a credencial service_role. O JWT do usuário
   * NÃO é propagado (para não rebaixar a role para `authenticated`); o ator é o
   * user.id verificado por `resolveCaller`.
   */
  executarRpc(
    action: AcaoAcessoRole,
    membershipId: string,
    accessRoleId: string,
    actorUserId: string
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

  // 1) identidade soberana (auth.getUser).
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

  // 2) execução privilegiada com o ator VERIFICADO (nunca o JWT, nunca actor_id).
  const rpcError = await deps.executarRpc(
    action,
    membershipId,
    accessRoleId,
    callerId
  );
  if (rpcError) {
    // Self-escalation/cross-tenant/tenant inválido/sem autoridade administrativa
    // => 403 (fail-closed).
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
