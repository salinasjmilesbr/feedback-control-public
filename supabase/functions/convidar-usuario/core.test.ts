import { describe, expect, it } from "vitest";
import {
  decidirFalhaDoVinculo,
  podeConvidarComoAdministradorDoTenant,
  validarEntradaDoConvite,
} from "./core";

/**
 * F6-A19 (Issue #319) — decisões puras da fronteira de convite.
 *
 * O que se prova aqui:
 * - o gate é o predicado canônico `usuario_eh_administrador` e SOMENTE `true`
 *   autoriza (não-admin, erro e valores "verdadeiros" genéricos ⇒ DENY);
 * - a colaboradora é obrigatória e identificada por UUID (a conta nunca fica
 *   "solta" e e-mail/matrícula não identificam pessoa — F5-02 D4);
 * - falhas do provisionamento atômico são traduzidas com fail-closed e com a
 *   decisão de compensação correta (nunca apagar conta pré-existente).
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const COLABORADORA = "22222222-2222-4222-8222-222222222222";

describe("F6-A19 — gate de autoridade administrativa do convite", () => {
  it("ALLOW somente com o booleano true do predicado canônico", () => {
    expect(podeConvidarComoAdministradorDoTenant(true, null)).toBe(true);
  });

  it("DENY para não-admin (false)", () => {
    expect(podeConvidarComoAdministradorDoTenant(false, null)).toBe(false);
  });

  it("DENY fail-closed para erro, ausência ou valor não booleano", () => {
    for (const valor of [undefined, null, "true", "t", 1, 0, {}, [], "TRUE"]) {
      expect(podeConvidarComoAdministradorDoTenant(valor, null)).toBe(false);
    }
    // Erro do RPC vence até um `true` inesperado.
    expect(podeConvidarComoAdministradorDoTenant(true, { code: "PGRST301" })).toBe(false);
    expect(podeConvidarComoAdministradorDoTenant(false, { message: "denied" })).toBe(false);
  });
});

describe("F6-A19 — forma da entrada do convite", () => {
  it("aceita e-mail + organização + colaboradora (UUID), normalizando o e-mail", () => {
    const entrada = validarEntradaDoConvite({
      email: "  Mariana.Pereira@Example.INVALID ",
      organization_id: ORG,
      collaborator_id: COLABORADORA,
    });

    expect(entrada.ok).toBe(true);
    if (!entrada.ok) return;
    expect(entrada).toEqual({
      ok: true,
      email: "mariana.pereira@example.invalid",
      organizationId: ORG,
      collaboratorId: COLABORADORA,
    });
  });

  it("recusa e-mail inválido", () => {
    const entrada = validarEntradaDoConvite({
      email: "sem-arroba",
      organization_id: ORG,
      collaborator_id: COLABORADORA,
    });
    expect(entrada.ok).toBe(false);
    if (entrada.ok) return;
    expect(entrada.codigo).toBe("INVALID_EMAIL");
    expect(entrada.status).toBe(400);
  });

  it("recusa organização ausente ou fora do formato UUID", () => {
    for (const organization_id of ["", "   ", "org-1", 7, null, undefined]) {
      const entrada = validarEntradaDoConvite({
        email: "pessoa@example.invalid",
        organization_id,
        collaborator_id: COLABORADORA,
      });
      expect(entrada.ok, String(organization_id)).toBe(false);
      if (entrada.ok) return;
      expect(entrada.codigo).toBe("INVALID_ORGANIZATION");
    }
  });

  it("recusa colaboradora ausente, vazia ou fora do formato UUID (#319)", () => {
    for (const collaborator_id of ["", "   ", "ACME002", "MARIA", 123, null, undefined]) {
      const entrada = validarEntradaDoConvite({
        email: "pessoa@example.invalid",
        organization_id: ORG,
        collaborator_id,
      });
      expect(entrada.ok, String(collaborator_id)).toBe(false);
      if (entrada.ok) return;
      expect(entrada.codigo).toBe("INVALID_COLLABORATOR");
      expect(entrada.status).toBe(400);
    }
  });

  it("recusa corpo que não é objeto", () => {
    for (const corpo of [null, undefined, "convite", 42, true]) {
      expect(validarEntradaDoConvite(corpo).ok).toBe(false);
    }
  });
});

describe("F6-A19 — falha do provisionamento atômico (retry/consistência)", () => {
  it("P0002 (colaborador inexistente no tenant) ⇒ inválido, com compensação", () => {
    const decisao = decidirFalhaDoVinculo({ code: "P0002" });
    expect(decisao.codigo).toBe("INVALID_COLLABORATOR");
    expect(decisao.status).toBe(400);
    expect(decisao.compensar).toBe(true);
  });

  it("23503 (organização inexistente) ⇒ inválido, com compensação", () => {
    const decisao = decidirFalhaDoVinculo({ code: "23503" });
    expect(decisao.codigo).toBe("INVALID_ORGANIZATION");
    expect(decisao.status).toBe(400);
    expect(decisao.compensar).toBe(true);
  });

  it("22023 (parâmetros obrigatórios) ⇒ inválido, com compensação", () => {
    const decisao = decidirFalhaDoVinculo({ code: "22023" });
    expect(decisao.codigo).toBe("INVALID_INPUT");
    expect(decisao.status).toBe(400);
    expect(decisao.compensar).toBe(true);
  });

  it("23505 (perfil/membership já existentes) ⇒ NUNCA compensa (conta real preservada)", () => {
    const decisao = decidirFalhaDoVinculo({ code: "23505" });
    expect(decisao.codigo).toBe("USER_EXISTS");
    expect(decisao.status).toBe(409);
    expect(decisao.compensar).toBe(false);
  });

  it("falha do primitivo, erro desconhecido ou ausente ⇒ INTERNAL com compensação (nada parcial)", () => {
    for (const erro of [
      { code: "P0001", message: "vinculo ja existente" },
      { code: "XX000" },
      { message: "network" },
      null,
      undefined,
    ]) {
      const decisao = decidirFalhaDoVinculo(erro);
      expect(decisao.codigo).toBe("INTERNAL");
      expect(decisao.status).toBe(500);
      expect(decisao.compensar).toBe(true);
    }
  });
});
