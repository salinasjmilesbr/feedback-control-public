/**
 * F5-06 (Issue #103) — resolução da PONTE matrícula → UUID no cliente
 * privilegiado da fronteira confiável.
 *
 * A matrícula é INTENÇÃO enviada pela tela legada; o UUID é resolvido aqui, a
 * partir da fonte estrutural (F3-01 `collaborator_identifiers`), e é ESSE valor
 * que segue para a RPC. Nada nesta resolução concede autorização: o alvo ainda
 * passa pelo Policy Engine.
 *
 * O cliente é recebido como porta mínima (apenas a operação de consulta), o que
 * mantém o módulo testável sem rede e sem tipos do SDK.
 */

import {
  codigoDeNegocioDaMatricula,
  extrairColaboradorDoIdentificador,
} from "../../../src/infrastructure/supabase/avaliacoes/ponteMatricula.ts";

export interface ResultadoConsultaIdentificador {
  readonly data: unknown;
  readonly error: unknown;
}

/** Porta mínima: consulta os identificadores de negócio do tenant. */
export interface ClienteIdentificadores {
  buscarIdentificadoresPorCodigo(entrada: {
    readonly organizationId: string;
    readonly businessCode: string;
  }): Promise<ResultadoConsultaIdentificador>;
}

export interface PonteColaborador {
  /** UUID do colaborador daquela matrícula no tenant, ou `null` (fail-closed). */
  resolver(entrada: {
    readonly organizationId: string;
    readonly matricula: unknown;
  }): Promise<string | null>;
}

export function criarPonteColaborador(cliente: ClienteIdentificadores): PonteColaborador {
  return {
    async resolver({ organizationId, matricula }) {
      if (typeof organizationId !== "string" || organizationId.trim() === "") return null;

      const businessCode = codigoDeNegocioDaMatricula(matricula);
      if (!businessCode) return null;

      const { data, error } = await cliente.buscarIdentificadoresPorCodigo({
        organizationId,
        businessCode,
      });
      if (error) return null;

      return extrairColaboradorDoIdentificador(data, organizationId);
    },
  };
}
