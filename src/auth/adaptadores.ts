import type { SupabaseClient } from "@supabase/supabase-js";
import { TechnicalError } from "../errors/applicationErrors";
import type { Autenticador, RepositorioIdentidade } from "./contratos";
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
      const { data } = cliente.auth.onAuthStateChange((_evento, sessao) => {
        aoMudar(sessao ? { usuario: paraUsuarioAuth(sessao.user) ?? { id: sessao.user.id, email: null } } : null);
      });
      return () => data.subscription.unsubscribe();
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
        status: linha.status === "disabled" ? "disabled" : "active",
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
        status: linha.status === "disabled" ? "disabled" : "active",
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
