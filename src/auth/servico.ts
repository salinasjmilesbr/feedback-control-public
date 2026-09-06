import { ForbiddenError, TechnicalError } from "../errors/applicationErrors";
import type { Autenticador, RepositorioIdentidade } from "./contratos";
import { mapearErroDeLogin, mapearErroTecnico } from "./erros";
import type { IdentidadeResolvida, SessaoAuth, UsuarioAuth } from "./tipos";

/**
 * Serviço de autenticação e resolução de identidade (F2-03).
 *
 * Camada pura, sem React e sem persistência própria: recebe os contratos de
 * infraestrutura e devolve dados de domínio ou erros da taxonomia F0-05. A
 * senha é usada somente na chamada de `entrarComSenha` e nunca é retida,
 * logada ou persistida.
 */

export async function entrar(
  email: string,
  senha: string,
  autenticador: Autenticador
): Promise<UsuarioAuth> {
  const { data, error } = await autenticador.entrarComSenha(email, senha);

  if (error) throw mapearErroDeLogin(error);
  if (!data) throw new TechnicalError();

  return data;
}

export async function sair(autenticador: Autenticador): Promise<void> {
  const { error } = await autenticador.sair();
  if (error) throw mapearErroTecnico(error);
}

export async function obterSessaoInicial(
  autenticador: Autenticador
): Promise<SessaoAuth | null> {
  const { data, error } = await autenticador.obterSessao();
  if (error) throw mapearErroTecnico(error);
  return data;
}

/**
 * Solicita a recuperação de senha (F2-05). Nunca revela se o e-mail possui ou
 * não conta: o resultado (inclusive erro) é ignorado e a chamada sempre
 * resolve. A UI exibe uma mensagem neutra indistinguível.
 */
export async function solicitarRecuperacaoDeSenha(
  email: string,
  redirectTo: string,
  autenticador: Autenticador
): Promise<void> {
  await autenticador.solicitarRecuperacaoDeSenha(email, redirectTo);
}

/** Define a nova senha na sessão de recuperação corrente (F2-05). */
export async function redefinirSenha(
  novaSenha: string,
  autenticador: Autenticador
): Promise<void> {
  const { error } = await autenticador.definirNovaSenha(novaSenha);
  if (error) throw mapearErroTecnico(error);
}

/** Validação mínima local da nova senha (não substitui as regras do backend). */
export function validarNovaSenha(novaSenha: string, confirmacao: string): string | null {
  if (!novaSenha || !confirmacao) {
    return "Informe e confirme a nova senha.";
  }
  if (novaSenha !== confirmacao) {
    return "As senhas informadas não coincidem.";
  }
  if (novaSenha.length < 6) {
    return "A nova senha deve ter pelo menos 6 caracteres.";
  }
  return null;
}

/**
 * Resolve perfil + memberships ativas pelo `auth.uid()`, nunca por e-mail.
 *
 * - auth user sem perfil interno, ou com perfil desabilitado, é erro de acesso
 *   seguro (`ForbiddenError`);
 * - perfil válido sem membership ativa é autenticação válida com zero
 *   organizações (sem inventar organização);
 * - múltiplas memberships são preservadas integralmente, sem seleção
 *   silenciosa de organização.
 */
export async function resolverIdentidade(
  authUserId: string,
  repositorio: RepositorioIdentidade
): Promise<IdentidadeResolvida> {
  const perfil = await repositorio.buscarPerfil(authUserId);

  if (!perfil || perfil.status !== "active") {
    throw new ForbiddenError();
  }

  const memberships = await repositorio.buscarMembershipsAtivas(authUserId);
  const idsOrganizacoes = memberships.map((membership) => membership.organizationId);
  const organizacoes = await repositorio.buscarOrganizacoes(idsOrganizacoes);

  return { authUserId, perfil, memberships, organizacoes };
}
