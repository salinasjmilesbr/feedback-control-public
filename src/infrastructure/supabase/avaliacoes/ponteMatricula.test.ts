import { describe, expect, it } from "vitest";
import {
  codigoDeNegocioDaMatricula,
  extrairColaboradorDoIdentificador,
  normalizarMatricula,
} from "./ponteMatricula.ts";

/**
 * F5-06 (Issue #103) — ponte matrícula → UUID: normalização estrita e leitura
 * fail-closed do identificador de negócio (F3-01). Nada aqui é autorização.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const COLABORADOR = "33333333-3333-4333-8333-333333333333";

describe("ponte matrícula → identidade técnica", () => {
  it("normaliza matrícula numérica e textual, recusando o resto", () => {
    expect(normalizarMatricula(101)).toBe(101);
    expect(normalizarMatricula("101")).toBe(101);
    expect(normalizarMatricula(" 101 ")).toBe(101);

    for (const invalida of [0, -1, 1.5, "", "abc", "10a", "1 0", null, undefined, {}, []]) {
      expect(normalizarMatricula(invalida)).toBeNull();
    }
  });

  it("gera o código de negócio canônico (sem zeros à esquerda inventados)", () => {
    expect(codigoDeNegocioDaMatricula(101)).toBe("101");
    expect(codigoDeNegocioDaMatricula("0101")).toBe("101");
    expect(codigoDeNegocioDaMatricula("abc")).toBeNull();
  });

  it("escolhe a linha ABERTA do tenant", () => {
    const linhas = [
      { collaborator_id: "antigo", organization_id: ORG, valid_to: "2025-01-01T00:00:00Z" },
      { collaborator_id: COLABORADOR, organization_id: ORG, valid_to: null },
    ];
    expect(extrairColaboradorDoIdentificador(linhas, ORG)).toBe(COLABORADOR);
  });

  it("histórico fechado, tenant divergente ou vazio ⇒ null (fail-closed)", () => {
    expect(
      extrairColaboradorDoIdentificador(
        [{ collaborator_id: COLABORADOR, organization_id: ORG, valid_to: "2025-01-01T00:00:00Z" }],
        ORG
      )
    ).toBeNull();
    expect(
      extrairColaboradorDoIdentificador(
        [{ collaborator_id: COLABORADOR, organization_id: ORG_B, valid_to: null }],
        ORG
      )
    ).toBeNull();
    expect(extrairColaboradorDoIdentificador([], ORG)).toBeNull();
    expect(extrairColaboradorDoIdentificador(null, ORG)).toBeNull();
    expect(extrairColaboradorDoIdentificador({ collaborator_id: COLABORADOR }, ORG)).toBeNull();
  });

  it("mais de uma linha aberta no tenant ⇒ null (não escolhe arbitrariamente)", () => {
    const linhas = [
      { collaborator_id: COLABORADOR, organization_id: ORG, valid_to: null },
      { collaborator_id: ORGANIZACAO_SINTETICA, organization_id: ORG, valid_to: null },
    ];
    expect(extrairColaboradorDoIdentificador(linhas, ORG)).toBeNull();
  });

  it("linha aberta sem collaborator_id válido ⇒ null", () => {
    expect(
      extrairColaboradorDoIdentificador([{ collaborator_id: "", organization_id: ORG }], ORG)
    ).toBeNull();
    expect(
      extrairColaboradorDoIdentificador([{ collaborator_id: 42, organization_id: ORG }], ORG)
    ).toBeNull();
  });
});

const ORGANIZACAO_SINTETICA = "44444444-4444-4444-8444-444444444444";
