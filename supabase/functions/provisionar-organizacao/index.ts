// F6-A03 (Issue #266): fronteira server-side do PLANO DE PLATAFORMA.
//
// Este é o ÚNICO lugar da superfície de plataforma que lê
// `SUPABASE_SERVICE_ROLE_KEY` e cria o cliente privilegiado. A credencial NUNCA
// decide: ela apenas executa a RPC soberana em nome do ator VERIFICADO, e o JWT
// do usuário não é propagado à RPC (mesma doutrina de
// `supabase/functions/gerenciar-access-role/index.ts`).
//
// Autorização (contrato §5/§6, D14/D17/D20):
//   1. JWT válido resolvido por `auth.getUser` (Gotrue) — nunca pelo corpo;
//   2. `auth.uid()` ∈ allowlist server-side `INVITE_ADMIN_USER_IDS` (fail-closed:
//      variável ausente ⇒ ninguém autorizado);
//   3. piso de plataforma: perfil AUSENTE é admissível (D17 — o ambiente virgem
//      ainda não tem perfil); perfil EXISTENTE precisa estar `active`.
//
// Consistência: a criação do usuário no Auth é externa ao Postgres, então não há
// transação única. Estratégia (molde `convidar-usuario`): convidar no Auth →
// provisionar atomicamente via RPC (organização + perfis globais + membership +
// role `admin` + trilha) → em falha, COMPENSAR removendo o usuário recém-criado,
// para não sobrar estado parcial silencioso.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { plataforma, type DepsPlataforma } from "./core.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    return json(
      { error: { code: "INTERNAL", message: "Configuração do servidor indisponível." } },
      500
    );
  }

  // Cliente privilegiado (service_role) — exclusivo deste runtime server-side.
  // Sem o JWT do usuário no `Authorization`: identidade e execução SEPARADAS.
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const deps: DepsPlataforma = {
    // 1) Identidade soberana a partir do JWT (validado pelo Gotrue).
    resolveCaller: async (authHeader) => {
      if (!authHeader) return null;
      const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await caller.auth.getUser();
      return error ? null : (data.user?.id ?? null);
    },

    // 2) Autoridade de PLATAFORMA: allowlist do ambiente (não é credencial) +
    //    piso de perfil. Fail-closed em qualquer erro.
    operadorAutorizado: async (authUserId) => {
      const allowlist = (Deno.env.get("INVITE_ADMIN_USER_IDS") ?? "")
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
      if (!allowlist.includes(authUserId)) return false;

      const { data, error } = await admin
        .from("user_profiles")
        .select("id, status")
        .eq("id", authUserId)
        .maybeSingle();
      if (error) return false;
      // Perfil ausente é ADMISSÍVEL (D17): o ambiente virgem ainda não tem
      // perfil e a RPC cria a linha global na mesma transação.
      if (!data) return true;
      return data.status === "active";
    },

    // 3) Operação JÁ registrada na âncora de idempotência (D6/D7) — consultada
    //    ANTES de qualquer convite, para que o REPLAY do caminho por e-mail não
    //    esbarre no e-mail já existente.
    operacaoAplicada: async (operationId) => {
      const { data, error } = await admin
        .from("platform_provisioning_events")
        .select(
          "organization_id, organization_name, actor_user_profile_id, founder_user_profile_id"
        )
        .eq("operation_id", operationId)
        .maybeSingle();
      if (error || !data) return null;

      // E-mail da identidade do primeiro Admin da PRIMEIRA execução: lookup
      // DIRETO por id (sem listagem/enumeração de usuários). Ausente ⇒ `null`,
      // e o reconhecimento recusa o replay (fail-closed).
      const { data: usuario } = await admin.auth.admin.getUserById(
        data.founder_user_profile_id
      );
      const founderEmail = typeof usuario?.user?.email === "string" ? usuario.user.email : null;

      return {
        organizationId: data.organization_id,
        actorUserProfileId: data.actor_user_profile_id,
        organizationName: data.organization_name,
        founderUserId: data.founder_user_profile_id,
        founderEmail,
      };
    },

    // 4) Criação da identidade do primeiro Admin (Auth Admin).
    convidarFounder: async (email) => {
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email);
      if (error) {
        const existente = error.code === "email_exists" || error.status === 422;
        return existente
          ? { userId: null, existente: true, erro: null }
          : { userId: null, existente: false, erro: { code: error.code, message: error.message } };
      }
      const userId = data?.user?.id ?? null;
      return userId
        ? { userId, existente: false, erro: null }
        : {
            userId: null,
            existente: false,
            erro: { code: "INTERNAL", message: "Convite sem identidade resolvida." },
          };
    },

    // 4) Execução privilegiada da RPC soberana (transacional e idempotente).
    //    O ator é o `auth.uid()` verificado; nenhum campo de autoridade viaja.
    provisionar: async (execucao) => {
      const { data, error } = await admin.rpc("organizacao_provisionar_inicial", {
        p_operation_id: execucao.operationId,
        p_organization_name: execucao.organizationName,
        p_founder_user_profile_id: execucao.founderUserId,
        p_actor_user_profile_id: execucao.actorUserProfileId,
      });
      if (error) {
        return { organizationId: null, erro: { code: error.code, message: error.message } };
      }
      return {
        organizationId: typeof data === "string" ? data : null,
        erro: null,
      };
    },

    // 6) Compensação BEST-EFFORT: `deleteUser` devolve `{ error }` (não lança) e
    //    a chamada pode falhar por transporte — nenhuma dessas falhas pode
    //    mascarar o código público real da operação. O usuário órfão fica SEM
    //    perfil e SEM membership (inacessível — fail-closed).
    compensarFounder: async (userId) => {
      try {
        await admin.auth.admin.deleteUser(userId);
      } catch {
        // Silencioso por desenho (dívida registrada no handoff).
      }
    },
  };

  return plataforma(req, deps);
});
