// F6-A20 (Issue #321): conclusão do primeiro acesso (onboarding de senha).
//
// A senha vive EXCLUSIVAMENTE no Supabase Auth; o estado do onboarding vive no
// Postgres (`user_profiles.first_access_pending`). Não existe transação única
// entre Auth e Postgres, então o fluxo é uma SAGA cujo PONTO DE COMMIT é o
// estado soberano:
//
//   1) gate: só conclui quem tem perfil existente com pendência `true`;
//   2) a senha é escrita no Auth (idempotente — repetir é seguro e não concede
//      autorização por si só);
//   3) o `first_access_pending` é limpo por ÚLTIMO e a linha alterada é PROVADA
//      (representação devolvida pelo UPDATE + predicado de pendência);
//   4) sem prova, o estado corrente é VERIFICADO por leitura e a conclusão só é
//      reportada se a leitura confirmar que não há mais pendência.
//
// Falha depois da senha NÃO deixa estado "meio concluído": a pendência continua
// `true` (acesso bloqueado) e o retry converge, porque o gate aceita nova
// tentativa enquanto a pendência existir. Nada aqui depende de URL,
// `localStorage` ou estado de tela — a fonte é o perfil soberano lido
// server-side. A fronteira NÃO toca roles, capabilities, memberships nem tenant.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  decidirConclusaoDoPrimeiroAcesso,
  decidirEntradaDoPrimeiroAcesso,
  linhasAfetadasDoRetorno,
  pendenciaConfirmada,
} from "./core.ts";

const HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...HEADERS },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: HEADERS });
  if (req.method !== "POST") return json({ error: { code: "METHOD_NOT_ALLOWED" } }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: { code: "INTERNAL" } }, 500);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: { code: "NOT_AUTHORIZED" } }, 401);

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await caller.auth.getUser();
  const userId = authData.user?.id;
  if (authError || !userId) return json({ error: { code: "NOT_AUTHORIZED" } }, 401);

  let body: { password?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: { code: "INVALID_INPUT" } }, 400);
  }
  if (typeof body.password !== "string" || body.password.length < 6) {
    return json({ error: { code: "INVALID_PASSWORD" } }, 400);
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // (1) Gate soberano: sem perfil ou sem pendência não há o que concluir.
  const { data: perfil, error: perfilError } = await admin
    .from("user_profiles")
    .select("id, first_access_pending")
    .eq("id", userId)
    .maybeSingle();
  const entrada = decidirEntradaDoPrimeiroAcesso(perfil, perfilError);
  if (!entrada.ok) return json({ error: { code: entrada.codigo } }, entrada.status);

  // (2) Senha no Auth: passo idempotente, repetível em retry. Falha aqui não
  // altera estado algum (a pendência continua `true`).
  const { error: passwordError } = await admin.auth.admin.updateUserById(userId, {
    password: body.password,
  });
  if (passwordError) return json({ error: { code: "INVALID_PASSWORD" } }, 400);

  // (3) PONTO DE COMMIT: limpar a pendência exige PROVA de linha alterada —
  // predicado de pendência + representação devolvida pelo UPDATE.
  const { data: atualizado, error: completionError } = await admin
    .from("user_profiles")
    .update({ first_access_pending: false })
    .eq("id", userId)
    .eq("first_access_pending", true)
    .select("id");

  const linhasAfetadas = linhasAfetadasDoRetorno(atualizado);

  // (4) Sem prova pela escrita, verificar o estado corrente por LEITURA: só a
  // pendência inexistente comprova conclusão (ex.: conclusão concorrente).
  let estadoConfirmado: boolean | null = null;
  if (completionError || linhasAfetadas !== 1) {
    const { data: verificado, error: verificacaoError } = await admin
      .from("user_profiles")
      .select("first_access_pending")
      .eq("id", userId)
      .maybeSingle();
    estadoConfirmado = pendenciaConfirmada(verificado, verificacaoError);
  }

  const conclusao = decidirConclusaoDoPrimeiroAcesso({
    erroDaAtualizacao: completionError,
    linhasAfetadas,
    estadoConfirmado,
  });
  if (conclusao.tipo !== "concluido") {
    return json({ error: { code: conclusao.codigo } }, conclusao.status);
  }

  // Só chega aqui com prova soberana (linha alterada ou estado verificado).
  return json({ completed: true });
});
