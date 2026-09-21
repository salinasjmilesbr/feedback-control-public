// F2-06 (Issue #73) + F6-A19 (Issue #319): convite administrativo de usuário.
//
// Fronteira server-side ÚNICA para operações privilegiadas de Auth: usa o
// Supabase Auth Admin (`SUPABASE_SERVICE_ROLE_KEY`, injetada pelo runtime) e
// nunca é importada pelo frontend. O frontend apenas invoca esta função com o
// JWT do usuário logado; a autorização real acontece aqui.
//
// Autorização (F6-A19, Issue #319 — diagnóstico aprovado):
//   1. o chamador precisa de um JWT válido (resolvido via `auth.getUser`);
//   2. o chamador precisa ter `user_profiles.status = 'active'`;
//   3. o chamador precisa ser ADMINISTRADOR DO TENANT pelo predicado canônico
//      `public.usuario_eh_administrador(ator, organização)` — membership ativa +
//      atribuição ativa da role de sistema `admin` nominal (F5-04 D16/Q3,
//      reafirmado pela F5-11 P5.2 e pela F6-306). Somente `true` autoriza.
//
//      NÃO se usa `membership.manage`: é capability do plano de CONTROLE,
//      `grantable_via_role = false` (F5-04 D15) e impedida pelo trigger
//      `trg_access_role_capabilities_grantable` — nenhuma role pode carregá-la,
//      logo exigir essa capability negava TODO administrador legítimo.
//      NÃO se usa allowlist de variável de ambiente (dívida G11).
//
// VÍNCULO SOBERANO (Issue #319): o convite recebe `collaborator_id` da pessoa
// JÁ CADASTRADA e o provisionamento é UMA RPC atômica (`convidado_acesso_criar`)
// que cria perfil + membership + o vínculo da membership ao colaborador pelo
// primitivo canônico da F5-02. NENHUMA role é concedida ao convidado.
//
// Consistência: a criação no Auth é externa ao Postgres, então não há transação
// única entre Auth e banco. Estratégia: criar o usuário no Auth; provisionar
// perfil+membership+vínculo em UMA transação (RPC); em falha do provisionamento,
// compensar removendo o usuário recém-criado no Auth (não sobra estado parcial
// silencioso). A compensação é VERIFICADA: se ela própria falhar, isso é
// registrado no log da função (o retorno continua sendo erro, nunca sucesso).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  decidirFalhaDoVinculo,
  podeConvidarComoAdministradorDoTenant,
  validarEntradaDoConvite,
} from "./core.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function erro(codigo: string, mensagem: string, status: number): Response {
  return json({ error: { code: codigo, message: mensagem } }, status);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return erro("METHOD_NOT_ALLOWED", "Método não permitido.", 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return erro("INTERNAL", "Configuração do servidor indisponível.", 500);
  }

  // Cliente privilegiado (service_role) — exclusivo deste runtime server-side.
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) resolve o chamador a partir do JWT enviado (validado pelo gotrue).
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  const callerId = callerData?.user?.id;
  if (callerError || !callerId) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }

  // 2) piso mínimo: perfil interno ativo.
  const { data: perfil, error: perfilError } = await admin
    .from("user_profiles")
    .select("id, status")
    .eq("id", callerId)
    .maybeSingle();
  if (perfilError || !perfil || perfil.status !== "active") {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 403);
  }

  // 3) entradas (forma): e-mail + organização + COLABORADORA já cadastrada.
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.", 400);
  }
  const entrada = validarEntradaDoConvite(body);
  if (!entrada.ok) {
    return erro(entrada.codigo, entrada.mensagem, entrada.status);
  }

  // 4) autoridade administrativa server-side no tenant-alvo: SOMENTE o
  // predicado canônico, e SOMENTE com resposta booleana `true` (fail-closed).
  const { data: autoridade, error: autoridadeError } = await admin.rpc(
    "usuario_eh_administrador",
    {
      p_user_profile_id: callerId,
      p_organization_id: entrada.organizationId,
    }
  );
  if (!podeConvidarComoAdministradorDoTenant(autoridade, autoridadeError)) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 403);
  }

  // 5) cria o usuário no Auth (convite por e-mail).
  const { data: invited, error: inviteError } =
    await admin.auth.admin.inviteUserByEmail(entrada.email);
  if (inviteError) {
    const duplicado = inviteError.code === "email_exists" || inviteError.status === 422;
    return duplicado
      ? erro("USER_EXISTS", "Já existe um usuário com este e-mail.", 409)
      : erro("INTERNAL", "Não foi possível convidar o usuário.", 500);
  }
  const userId = invited?.user?.id;
  if (!userId) {
    return erro("INTERNAL", "Não foi possível convidar o usuário.", 500);
  }

  // 6) perfil + membership + VÍNCULO com a colaboradora, em UMA transação
  // (RPC SECURITY INVOKER, EXECUTE somente service_role). O tenant é revalidado
  // NO BANCO (cross-tenant ⇒ P0002) e NENHUMA role é concedida.
  const { error: vinculoError } = await admin.rpc("convidado_acesso_criar", {
    p_user_id: userId,
    p_organization_id: entrada.organizationId,
    p_collaborator_id: entrada.collaboratorId,
  });

  if (vinculoError) {
    const decisao = decidirFalhaDoVinculo(vinculoError);

    // Nunca apagar conta pré-existente: `23505` prova que o usuário já existia.
    if (decisao.compensar) {
      const { error: compensacaoError } = await admin.auth.admin.deleteUser(userId);
      if (compensacaoError) {
        // Estado parcial no Auth (sem perfil/membership): fica registrado para
        // limpeza operacional. Nenhum dado pessoal é logado.
        console.error(
          "convidar-usuario: compensacao do usuario Auth falhou apos falha do vinculo soberano"
        );
      }
    }

    return erro(decisao.codigo, decisao.mensagem, decisao.status);
  }

  return json({ userId, email: entrada.email }, 200);
});
