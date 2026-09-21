/**
 * F6-A19 (Issue #319) — decisões PURAS da fronteira de convite administrativo.
 *
 * Este módulo NÃO fala com o banco nem com o Auth: só decide, para que o gate de
 * autoridade, a forma da entrada e a reação a falhas do provisionamento possam
 * ser provados por teste unitário (o runtime Deno não é testável no Vitest).
 *
 * REGRA DE AUTORIDADE (diagnóstico aprovado da #319):
 *   o gate é `public.usuario_eh_administrador(ator, organização)` — predicado
 *   canônico da autoridade administrativa do tenant (F5-04 D16/Q3, reafirmado
 *   pela F5-11 P5.2 e pela F6-306): membership ativa + atribuição ativa da role
 *   de sistema `admin` nominal.
 *
 *   `membership.manage` NÃO é gate válido e não pode voltar: é capability do
 *   plano de CONTROLE, `grantable_via_role = false` (F5-04 D15), impedida pelo
 *   trigger `trg_access_role_capabilities_grantable` — nenhuma role pode
 *   carregá-la e, portanto, nenhum ator jamais a tem como capability efetiva.
 *   Exigi-la tornava o convite impossível para TODO administrador legítimo.
 */

/** Forma do e-mail (a mesma validação que a Edge já aplicava). */
export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Identificador técnico (colaborador/organização) — nunca chave de negócio. */
export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Autoriza SOMENTE o booleano `true` devolvido pelo predicado server-side.
 * Erro, ausência, `null`, string, número ou objeto ⇒ DENY (fail-closed): a
 * autoridade nunca é inferida de valor "verdadeiro" genérico.
 */
export function podeConvidarComoAdministradorDoTenant(
  valor: unknown,
  erro: unknown
): boolean {
  if (erro) return false;
  return valor === true;
}

export type EntradaConvite =
  | {
      readonly ok: true;
      readonly email: string;
      readonly organizationId: string;
      readonly collaboratorId: string;
    }
  | {
      readonly ok: false;
      readonly codigo: string;
      readonly mensagem: string;
      readonly status: number;
    };

/**
 * Valida a FORMA do corpo do convite. `organization_id` e `collaborator_id` são
 * IDENTIFICADORES TÉCNICOS (UUID): a matrícula/e-mail nunca identificam a pessoa
 * (F5-02 D4) e o tenant é revalidado no banco. A colaboradora é OBRIGATÓRIA —
 * convite sem vínculo deixaria a conta "solta" (defeito corrigido pela #319).
 */
export function validarEntradaDoConvite(corpo: unknown): EntradaConvite {
  const bruto = (
    typeof corpo === "object" && corpo !== null ? corpo : {}
  ) as Record<string, unknown>;

  const email = typeof bruto.email === "string" ? bruto.email.trim().toLowerCase() : "";
  const organizationId =
    typeof bruto.organization_id === "string" ? bruto.organization_id.trim() : "";
  const collaboratorId =
    typeof bruto.collaborator_id === "string" ? bruto.collaborator_id.trim() : "";

  if (!EMAIL_RE.test(email)) {
    return { ok: false, codigo: "INVALID_EMAIL", mensagem: "E-mail inválido.", status: 400 };
  }
  if (!UUID_RE.test(organizationId)) {
    return {
      ok: false,
      codigo: "INVALID_ORGANIZATION",
      mensagem: "Organização inválida.",
      status: 400,
    };
  }
  if (!UUID_RE.test(collaboratorId)) {
    return {
      ok: false,
      codigo: "INVALID_COLLABORATOR",
      mensagem: "Colaborador inválido.",
      status: 400,
    };
  }

  return { ok: true, email, organizationId, collaboratorId };
}

export interface DecisaoFalhaDoVinculo {
  /** Código público estável devolvido ao cliente. */
  readonly codigo: string;
  readonly mensagem: string;
  readonly status: number;
  /**
   * `true` ⇒ o usuário recém-criado no Auth deve ser REMOVIDO (nada parcial
   * sobrevive). `false` ⇒ o erro prova que o usuário é PRÉ-EXISTENTE e removê-lo
   * seria destrutivo.
   */
  readonly compensar: boolean;
}

/**
 * Traduz a falha do provisionamento atômico (perfil + membership + vínculo) para
 * código público + decisão de compensação.
 *
 * - `P0002` (`no_data_found`): colaborador inexistente NO tenant ⇒ cross-tenant
 *   negado pelo banco;
 * - `23503` (FK): organização inexistente;
 * - `23505` (unique): o perfil/membership já existem ⇒ o usuário do Auth é
 *   PRÉ-EXISTENTE (um UUID novo não teria perfil) — NÃO compensar, para nunca
 *   apagar uma conta real (`inviteUserByEmail` devolveu usuário já existente);
 * - `22023`: parâmetros obrigatórios ausentes;
 * - qualquer outra (`P0001` do primitivo, erro de rede/indefinido) ⇒ `INTERNAL`
 *   com compensação: a transação do banco é atômica e o Auth não pode ficar órfão.
 */
export function decidirFalhaDoVinculo(erro: unknown): DecisaoFalhaDoVinculo {
  const codigo = (erro as { code?: unknown } | null | undefined)?.code;

  switch (codigo) {
    case "P0002":
      return {
        codigo: "INVALID_COLLABORATOR",
        mensagem: "Colaborador inválido.",
        status: 400,
        compensar: true,
      };
    case "23503":
      return {
        codigo: "INVALID_ORGANIZATION",
        mensagem: "Organização inválida.",
        status: 400,
        compensar: true,
      };
    case "22023":
      return {
        codigo: "INVALID_INPUT",
        mensagem: "Corpo da requisição inválido.",
        status: 400,
        compensar: true,
      };
    case "23505":
      return {
        codigo: "USER_EXISTS",
        mensagem: "Já existe um usuário com este e-mail.",
        status: 409,
        compensar: false,
      };
    default:
      return {
        codigo: "INTERNAL",
        mensagem: "Não foi possível concluir o convite.",
        status: 500,
        compensar: true,
      };
  }
}
