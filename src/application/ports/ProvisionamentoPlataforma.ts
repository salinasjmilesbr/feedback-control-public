/**
 * F6-A03 (Issue #266) — PORTA da aplicação para o PLANO DE PLATAFORMA.
 *
 * Contrato de L1 (aplicação) consumido pela UI mínima de plataforma: nenhuma
 * página compõe o cliente Supabase, a Edge `provisionar-organizacao` ou o
 * adapter por conta própria (mesma doutrina de `ObservationRepository` e das
 * portas soberanas da F5-07/F5-10/F5-11).
 *
 * O que esta porta NÃO é (D18–D21):
 * - não é autorização: a decisão é sempre server-side (Edge + RPC soberana);
 * - não lista tenants, não gerencia operadores, roles, planos ou lifecycle;
 * - não gera identidade: o `organizationId` é o UUID da linha, atribuído pelo
 *   banco; o cliente apenas transporta a intenção.
 *
 * Fail-closed: as implementações LANÇAM `ApplicationError` (taxonomia F0-05) em
 * qualquer recusa; nunca devolvem sucesso presumido.
 */

/** Intenção de provisionamento — exatamente o que o contrato transporta. */
export interface NovaOrganizacaoPlataforma {
  /** Chave de idempotência gerada pelo cliente (UUID canônico). */
  readonly operationId: string;
  readonly organizationName: string;
  /**
   * F6-A11 (D22/D23): nome humano do primeiro Admin — dado a criar; é a fonte
   * canônica de `collaborators.full_name` do founder na nova organização.
   */
  readonly founderFullName: string;
  /**
   * F6-A11 (D23/D28): matrícula declarada do primeiro Admin na nova organização.
   * Código de negócio declarado — a unicidade é decidida/garantida server-side.
   */
  readonly founderMatricula: string;
  /**
   * Primeiro Admin por identidade JÁ existente (caminho de API; a UI mínima usa
   * este campo para "eu mesmo").
   */
  readonly founderUserId?: string;
  /**
   * Primeiro Admin por e-mail de identidade NOVA (convite server-side).
   */
  readonly founderEmail?: string;
}

/** Resultado soberano do provisionamento. */
export interface OrganizacaoProvisionada {
  readonly organizationId: string;
}

export interface ProvisionamentoPlataforma {
  /** Cria a organização e estabelece o primeiro Admin do tenant. */
  provisionarOrganizacao(
    entrada: NovaOrganizacaoPlataforma
  ): Promise<OrganizacaoProvisionada>;
  /**
   * Self-check de UX: informa se o usuário autenticado é operador de plataforma.
   * NUNCA é autorização (D20) e NUNCA lança: qualquer falha resolve `false`.
   */
  souOperadorDaPlataforma(): Promise<boolean>;
  /**
   * Identidade AUTENTICADA do próprio operador (UUID do `auth.uid()` da sessão
   * local), usada apenas para expressar "eu mesmo" como primeiro Admin.
   *
   * NÃO é autoridade e NÃO é identidade declarada de terceiro: a Edge re-deriva
   * o ator do JWT verificado, e este valor viaja no campo `founder_user_id` —
   * que o contrato já previa para designar o primeiro Admin. Fail-closed:
   * ausência de sessão resolve `null`.
   */
  identidadeDoOperadorAutenticado(): Promise<string | null>;
}
