import { describe, expect, it, vi } from "vitest";
import {
  criarPonteColaborador,
  type ClienteIdentificadores,
} from "../../../supabase/functions/avaliacoes/ponteColaborador.ts";

/**
 * F5-06 (Issue #103) — ponte matrícula → UUID na fronteira confiável: a
 * matrícula é intenção; a resolução usa a fonte estrutural e é fail-closed.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const COLABORADOR = "33333333-3333-4333-8333-333333333333";

function cliente(resultado: {
  readonly data?: unknown;
  readonly error?: unknown;
}): { readonly cliente: ClienteIdentificadores; readonly consultas: unknown[] } {
  const consultas: unknown[] = [];
  return {
    consultas,
    cliente: {
      buscarIdentificadoresPorCodigo: async (entrada) => {
        consultas.push(entrada);
        return { data: resultado.data ?? null, error: resultado.error ?? null };
      },
    },
  };
}

const LINHA_ABERTA = [
  { collaborator_id: COLABORADOR, organization_id: ORG, business_code: "101", valid_to: null },
];

describe("ponte de colaborador (Edge)", () => {
  it("resolve a matrícula para o UUID e consulta pelo código canônico", async () => {
    const { cliente: c, consultas } = cliente({ data: LINHA_ABERTA });
    const ponte = criarPonteColaborador(c);

    const id = await ponte.resolver({ organizationId: ORG, matricula: 101 });

    expect(id).toBe(COLABORADOR);
    expect(consultas[0]).toEqual({ organizationId: ORG, businessCode: "101" });
  });

  it("matrícula inválida NÃO consulta nada (fail-closed)", async () => {
    const buscar = vi.fn(async () => ({ data: LINHA_ABERTA, error: null }));
    const ponte = criarPonteColaborador({ buscarIdentificadoresPorCodigo: buscar });

    for (const invalida of [0, -5, 1.5, "abc", "", null, undefined, {}]) {
      expect(await ponte.resolver({ organizationId: ORG, matricula: invalida })).toBeNull();
    }
    expect(buscar).not.toHaveBeenCalled();
  });

  it("tenant ausente NÃO consulta nada", async () => {
    const buscar = vi.fn(async () => ({ data: LINHA_ABERTA, error: null }));
    const ponte = criarPonteColaborador({ buscarIdentificadoresPorCodigo: buscar });

    expect(await ponte.resolver({ organizationId: "  ", matricula: 101 })).toBeNull();
    expect(buscar).not.toHaveBeenCalled();
  });

  it("erro de consulta, histórico fechado ou tenant divergente ⇒ null", async () => {
    const comErro = criarPonteColaborador(cliente({ error: { message: "falha" } }).cliente);
    expect(await comErro.resolver({ organizationId: ORG, matricula: 101 })).toBeNull();

    const fechado = criarPonteColaborador(
      cliente({
        data: [
          {
            collaborator_id: COLABORADOR,
            organization_id: ORG,
            business_code: "101",
            valid_to: "2025-01-01T00:00:00Z",
          },
        ],
      }).cliente
    );
    expect(await fechado.resolver({ organizationId: ORG, matricula: 101 })).toBeNull();

    const outroTenant = criarPonteColaborador(
      cliente({
        data: [
          {
            collaborator_id: COLABORADOR,
            organization_id: "outra-org",
            business_code: "101",
            valid_to: null,
          },
        ],
      }).cliente
    );
    expect(await outroTenant.resolver({ organizationId: ORG, matricula: 101 })).toBeNull();
  });
});
