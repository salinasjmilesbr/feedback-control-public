/**
 * F6-A03 (Issue #266) — conversão PURA do formulário da UI mínima de plataforma
 * em INTENÇÃO transportável.
 *
 * Vive fora do arquivo da página por dois motivos:
 * - é lógica pura, testável sem React (nada de estado, nada de DOM);
 * - mantém o módulo React exportando SOMENTE componentes (regra
 *   `react-refresh/only-export-components` do projeto).
 *
 * FAIL-CLOSED: entrada incompleta nunca vira requisição. A conversão NÃO decide
 * autorização e NÃO gera identidade — o `operationId` chega pronto (UUID do
 * cliente) e o primeiro Admin é apenas o ALVO designado (a Edge re-deriva o ator
 * do JWT verificado).
 */

import type { NovaOrganizacaoPlataforma } from "../../application/ports/ProvisionamentoPlataforma";

/** Forma escolhida para o primeiro Admin no formulário mínimo (§6.5.2). */
export type FormaPrimeiroAdmin = "eu" | "outra";

/** Motivo da recusa de montagem — nunca exposto cru; vira erro da taxonomia. */
export type MotivoMontagem = "nome" | "identidade" | "email";

export type ResultadoMontagem =
  | { readonly ok: true; readonly entrada: NovaOrganizacaoPlataforma }
  | { readonly ok: false; readonly motivo: MotivoMontagem };

export interface EntradaMontagem {
  readonly operacaoId: string;
  readonly nome: string;
  readonly forma: FormaPrimeiroAdmin;
  readonly email: string;
  /**
   * UUID da sessão autenticada (para "eu mesmo"). `null` ⇒ fail-closed: a
   * montagem recusa e nenhuma chamada é feita.
   */
  readonly usuarioAutenticadoId: string | null;
}

export function montarEntradaProvisao(entrada: EntradaMontagem): ResultadoMontagem {
  const nome = entrada.nome.trim();
  if (nome === "") return { ok: false, motivo: "nome" };

  if (entrada.forma === "eu") {
    const id = entrada.usuarioAutenticadoId?.trim() ?? "";
    if (id === "") return { ok: false, motivo: "identidade" };
    return {
      ok: true,
      entrada: { operationId: entrada.operacaoId, organizationName: nome, founderUserId: id },
    };
  }

  const email = entrada.email.trim().toLowerCase();
  if (email === "") return { ok: false, motivo: "email" };
  return {
    ok: true,
    entrada: { operationId: entrada.operacaoId, organizationName: nome, founderEmail: email },
  };
}
