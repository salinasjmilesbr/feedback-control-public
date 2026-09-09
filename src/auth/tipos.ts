/**
 * Tipos do domínio de autenticação (F2-03).
 *
 * Mantêm o estado mínimo necessário para identidade/sessão: o usuário de
 * autenticação (auth.users), o perfil interno (user_profiles) e as memberships
 * ativas (user_organization_memberships). Nenhum dado de colaborador, papel ou
 * credencial é representado aqui.
 */

export type StatusPerfil = "active" | "disabled";
export type StatusMembership = "active" | "disabled";

export interface UsuarioAuth {
  /** `auth.uid()` — identidade de autenticação. */
  id: string;
  /** Exibição opcional; nunca usado para autorização ou vínculo. */
  email?: string | null;
}

export interface SessaoAuth {
  usuario: UsuarioAuth;
}

export interface PerfilAutenticado {
  id: string;
  status: StatusPerfil;
}

export interface MembershipAutenticada {
  id: string;
  organizationId: string;
  status: StatusMembership;
}

export interface OrganizacaoResolvida {
  id: string;
  name: string;
}

export interface IdentidadeResolvida {
  authUserId: string;
  perfil: PerfilAutenticado;
  /** Somente memberships ativas; nenhuma seleção arbitrária é feita. */
  memberships: MembershipAutenticada[];
  /** Organizações alcançáveis pelas memberships ativas. */
  organizacoes: OrganizacaoResolvida[];
}

/**
 * F5-01: raiz de confiança formalizada. `AuthIdentity` é o nome de contrato da
 * identidade autenticada resolvida (`IdentidadeResolvida`), com as invariantes:
 * `authUserId === user_profile.id === auth.uid()`; perfil ativo; memberships
 * somente ativas; organizações derivadas, sem seleção. F5-02 (vínculo),
 * F5-03 (organização ativa), F5-04 (roles/capabilities) e F5-05 (ActorContext)
 * são etapas posteriores e NÃO são implementadas nesta atividade.
 */
export type AuthIdentity = IdentidadeResolvida;

/**
 * F5-02 (contrato de vínculo): colaborador vinculado a uma membership ativa do
 * usuário na organização. É o resultado da resolução `auth.uid → user_profile →
 * membership → link → colaborador`, sempre por (authUserId, organizationId) e
 * nunca por e-mail/matrícula/nome/cargo. Consumido por F5-05 (ActorContext);
 * NÃO há superfície executável pelo frontend nesta F5-02 (Q1 = A).
 */
export interface ColaboradorVinculado {
  /** Membership ativa origem do vínculo. */
  membership: MembershipAutenticada;
  /** id do link ativo (único por membership — Q6 = B). */
  linkId: string;
  /** collaborators.id (UUID técnico imutável). */
  colaboradorId: string;
  /** === membership.organizationId (tenant confirmado server-side). */
  organizationId: string;
}
