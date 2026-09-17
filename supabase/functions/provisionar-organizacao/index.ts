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

    // 3) Criação da identidade do primeiro Admin (Auth Admin).
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

    // 5) Compensação: nenhum usuário parcial fica no Auth.
    compensarFounder: async (userId) => {
      await admin.auth.admin.deleteUser(userId);
    },
  };

  return plataforma(req, deps);
});
