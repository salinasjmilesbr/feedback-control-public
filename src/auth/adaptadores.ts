import type { SupabaseClient } from "@supabase/supabase-js";
import { TechnicalError } from "../errors/applicationErrors";
import type {
  Autenticador,
  EventoMudancaSessao,
  RepositorioIdentidade,
} from "./contratos";
import type {
  MembershipAutenticada,
  OrganizacaoResolvida,
  PerfilAutenticado,
  SessaoAuth,
  UsuarioAuth,
} from "./tipos";

interface LinhaPerfil {
  id: string;
  status: string;
}

interface LinhaMembership {
  id: string;
  organization_id: string;
  status: string;
}

interface LinhaOrganizacao {
  id: string;
  name: string;
}

function paraUsuarioAuth(usuario: { id: string; email?: string | null } | null | undefined): UsuarioAuth | null {
  if (!usuario) return null;
  return { id: usuario.id, email: usuario.email ?? null };
}

/**
 * Classifica os eventos do Supabase Auth (F2-08): `INITIAL_SESSION` é uma
 * restauração (sessão pré-existente no dispositivo) e `SIGNED_IN`/
 * `PASSWORD_RECOVERY` iniciam uma sessão nova (janela da política reinicia).
 */
function mapearEventoAuth(evento: string): EventoMudancaSessao {
  switch (evento) {
    case "INITIAL_SESSION":
      return "inicial";
    case "SIGNED_IN":
    case "PASSWORD_RECOVERY":
      return "entrou";
    case "SIGNED_OUT":
      return "saiu";
    case "TOKEN_REFRESHED":
      return "tokenAtualizado";
    default:
      return "outro";
  }
}

/**
 * F5-01 (D10/G7): status só é considerado ativo quando literalmente "active".
 * Qualquer outro valor (desconhecido/corrompido) vira inativo — fail-closed em
 * defesa em profundidade (o CHECK do banco já limita o domínio; esta é a
 * segunda camada, nunca default ativo).
 */
export function normalizarStatus(status: string): "active" | "disabled" {
  return status === "active" ? "active" : "disabled";
}

export function criarAutenticador(cliente: SupabaseClient): Autenticador {
  return {
    async entrarComSenha(email, senha) {
      const { data, error } = await cliente.auth.signInWithPassword({
        email,
        password: senha,
      });
      return { data: paraUsuarioAuth(data.user), error };
    },

    async sair() {
      const { error } = await cliente.auth.signOut();
      return { data: null, error };
    },

    async obterSessao() {
      const { data, error } = await cliente.auth.getSession();
      const sessao: SessaoAuth | null = data.session
        ? { usuario: paraUsuarioAuth(data.session.user) ?? { id: data.session.user.id, email: null } }
        : null;
      return { data: sessao, error };
    },

    observarAutenticacao(aoMudar) {
      const { data } = cliente.auth.onAuthStateChange((evento, sessao) => {
        aoMudar(
          mapearEventoAuth(evento),
          sessao ? { usuario: paraUsuarioAuth(sessao.user) ?? { id: sessao.user.id, email: null } } : null
        );
      });
      return () => data.subscription.unsubscribe();
    },

    async validarSessaoAtual() {
      const { data, error } = await cliente.auth.getUser();
      return { data: paraUsuarioAuth(data.user), error };
    },

    async solicitarRecuperacaoDeSenha(email, redirectTo) {
      const { error } = await cliente.auth.resetPasswordForEmail(email, {
        redirectTo,
      });
      return { data: null, error };
    },

    async definirNovaSenha(senha) {
      const { error } = await cliente.auth.updateUser({ password: senha });
      return { data: null, error };
    },
  };
}

export function criarRepositorioIdentidade(cliente: SupabaseClient): RepositorioIdentidade {
  return {
    async buscarPerfil(authUserId) {
      const { data, error } = await cliente
        .from("user_profiles")
        .select("id, status")
        .eq("id", authUserId)
        .maybeSingle();

      if (error) throw new TechnicalError({ cause: error });
      if (!data) return null;

      const linha = data as LinhaPerfil;
      const perfil: PerfilAutenticado = {
        id: linha.id,
        status: normalizarStatus(linha.status),
      };
      return perfil;
    },

    async buscarMembershipsAtivas(authUserId) {
      const { data, error } = await cliente
        .from("user_organization_memberships")
        .select("id, organization_id, status")
        .eq("user_profile_id", authUserId)
        .eq("status", "active");

      if (error) throw new TechnicalError({ cause: error });

      const linhas = (data ?? []) as LinhaMembership[];
      const memberships: MembershipAutenticada[] = linhas.map((linha) => ({
        id: linha.id,
        organizationId: linha.organization_id,
        status: normalizarStatus(linha.status),
      }));
      return memberships;
    },

    async buscarOrganizacoes(ids) {
      if (ids.length === 0) return [];

      const { data, error } = await cliente
        .from("organizations")
        .select("id, name")
        .in("id", ids);

      if (error) throw new TechnicalError({ cause: error });

      const linhas = (data ?? []) as LinhaOrganizacao[];
      const organizacoes: OrganizacaoResolvida[] = linhas.map((linha) => ({
        id: linha.id,
        name: linha.name,
      }));
      return organizacoes;
    },
  };
}
