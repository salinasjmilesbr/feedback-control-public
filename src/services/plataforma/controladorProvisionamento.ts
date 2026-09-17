/**
 * F6-A03 (Issue #266) — controlador do PLANO DE PLATAFORMA (L1/L2 do cliente).
 *
 * Liga a porta `ProvisionamentoPlataforma` ao adapter da Edge
 * `provisionar-organizacao` e traduz o CÓDIGO PÚBLICO fechado (contrato §6.3)
 * para a taxonomia de erros F0-05 — mesmo molde de
 * `src/auth/conviteAdministrativo.ts` e `src/infrastructure/supabase/errosEdge.ts`.
 *
 * Nada aqui decide autorização, tenant ou papel:
 * - a composição do cliente é FAIL-CLOSED (`null` quando o ambiente não oferece o
 *   caminho soberano) e NÃO há fallback local, cache ou retentativa alternativa;
 * - `souOperadorDaPlataforma` é SELF-CHECK DE UX (D20) — nunca autorização — e
 *   NUNCA lança: qualquer falha resolve `false`;
 * - o `organizationId` devolvido é o UUID atribuído pelo BANCO; o cliente não
 *   fabrica identidade.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ConflictError,
  ForbiddenError,
  TechnicalError,
  ValidationError,
  type ApplicationError,
} from "../../errors/applicationErrors";
import { criarClienteSupabase } from "../../infrastructure/supabase/supabaseClient";
import {
  criarEdgePlataforma,
  type EdgePlataforma,
} from "../../infrastructure/supabase/plataforma/edgePlataforma";
import type {
  NovaOrganizacaoPlataforma,
  OrganizacaoProvisionada,
  ProvisionamentoPlataforma,
} from "../../application/ports/ProvisionamentoPlataforma";
import type { CodigoPublico } from "../../infrastructure/supabase/plataforma/contrato";

/**
 * Código público → erro da taxonomia F0-05. Código desconhecido NÃO é
 * repassado: vira `TechnicalError` (fail-closed).
 *
 * A mensagem apresentada é SEMPRE a canônica do código (critério 25 do
 * contrato): a taxonomia F0-05 é a fonte única de texto público e a mensagem do
 * servidor nunca é exibida crua.
 */
export function mapearErroPlataforma(codigo: CodigoPublico): ApplicationError {
  switch (codigo) {
    case "NOT_AUTHORIZED":
      return new ForbiddenError();
    case "INVALID_INPUT":
    case "INVALID_NAME":
    case "INVALID_FOUNDER":
      return new ValidationError();
    case "USER_EXISTS":
    case "OPERATION_ALREADY_APPLIED":
      return new ConflictError();
    default:
      return new TechnicalError();
  }
}

/** `true` somente com a forma exata `{ organization_id: <string não vazia> }`. */
function lerOrganizacaoProvisionada(resultado: unknown): OrganizacaoProvisionada {
  if (typeof resultado !== "object" || resultado === null) {
    throw new TechnicalError();
  }
  const organizationId = (resultado as { organization_id?: unknown }).organization_id;
  if (typeof organizationId !== "string" || organizationId.trim() === "") {
    throw new TechnicalError();
  }
  return { organizationId };
}

/** Dependências do controlador: o adapter da Edge e o leitor da sessão local. */
export interface DepsControladorPlataforma {
  readonly edge: EdgePlataforma;
  /**
   * Identidade autenticada do PRÓPRIO chamador (UUID da sessão local). Usada
   * somente para expressar "eu mesmo" como primeiro Admin; a Edge re-deriva o
   * ator do JWT e a autoridade continua server-side.
   */
  readonly lerUsuarioAutenticado?: () => Promise<string | null>;
}

export function criarProvisionamentoPlataforma(
  deps: DepsControladorPlataforma
): ProvisionamentoPlataforma {
  const { edge, lerUsuarioAutenticado } = deps;

  return {
    async provisionarOrganizacao(
      entrada: NovaOrganizacaoPlataforma
    ): Promise<OrganizacaoProvisionada> {
      const resposta = await edge.provisionarOrganizacao({
        operationId: entrada.operationId,
        organizationName: entrada.organizationName,
        // F6-A11/D23: identidade funcional mínima (intenção, nunca autoridade).
        founderFullName: entrada.founderFullName,
        founderMatricula: entrada.founderMatricula,
        ...(entrada.founderUserId !== undefined
          ? { founderUserId: entrada.founderUserId }
          : {}),
        ...(entrada.founderEmail !== undefined ? { founderEmail: entrada.founderEmail } : {}),
      });

      if (!resposta.ok) {
        throw mapearErroPlataforma(resposta.error.code);
      }
      return lerOrganizacaoProvisionada(resposta.data);
    },

    async souOperadorDaPlataforma(): Promise<boolean> {
      try {
        const resposta = await edge.operadorAtual();
        if (!resposta.ok) return false;
        const resultado = resposta.data;
        if (typeof resultado !== "object" || resultado === null) return false;
        return (resultado as { operador?: unknown }).operador === true;
      } catch {
        // Fail-closed: o self-check nunca derruba a página e nunca presume acesso.
        return false;
      }
    },

    async identidadeDoOperadorAutenticado(): Promise<string | null> {
      if (!lerUsuarioAutenticado) return null;
      try {
        return await lerUsuarioAutenticado();
      } catch {
        // Fail-closed: sem identidade local não há "eu mesmo" (a página informa).
        return null;
      }
    },
  };
}

/**
 * Instância resolvida uma única vez por sessão de página. `undefined` = ainda
 * não resolvido; `null` = ambiente sem caminho soberano (fail-closed).
 */
let provisionamentoMemoizado: ProvisionamentoPlataforma | null | undefined;

/** Somente para testes: descarta a memoização do caminho soberano. */
export function redefinirProvisionamentoPlataforma(): void {
  provisionamentoMemoizado = undefined;
}

export interface DependenciasAcessoPlataforma {
  /** Injeção do controlador (teste). Por padrão usa o caminho de produção. */
  readonly provisionamento?: ProvisionamentoPlataforma;
  /** Cliente Supabase explícito (teste); `null` força "sem caminho soberano". */
  readonly cliente?: SupabaseClient | null;
}

/**
 * Devolve o controlador de plataforma, ou `null` quando o ambiente não oferece o
 * caminho soberano (fail-closed — nenhum fallback local é oferecido).
 */
export function obterProvisionamentoPlataforma(
  deps: DependenciasAcessoPlataforma = {}
): ProvisionamentoPlataforma | null {
  if (deps.provisionamento) return deps.provisionamento;
  if (provisionamentoMemoizado !== undefined) return provisionamentoMemoizado;

  const cliente = deps.cliente !== undefined ? deps.cliente : criarClienteSupabase();
  provisionamentoMemoizado = cliente
    ? criarProvisionamentoPlataforma({
        edge: criarEdgePlataforma(cliente),
        // Identidade da PRÓPRIA sessão local (sem rede, sem autoridade): a Edge
        // re-deriva o ator do JWT verificado. Ausência/erro ⇒ `null` (fail-closed).
        lerUsuarioAutenticado: async () => {
          const { data, error } = await cliente.auth.getSession();
          if (error) return null;
          return data.session?.user?.id ?? null;
        },
      })
    : null;
  return provisionamentoMemoizado;
}
