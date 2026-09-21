import { describe, expect, it } from "vitest";
import {
  codigoPublicoAposCompensacao,
  codigoPublicoQuandoNaoCompensado,
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
 * - falhas do provisionamento atômico são traduzidas com fail-closed, e o
 *   CÓDIGO SQL nunca decide apagar ou não apagar (correção da auditoria do SHA
 *   62bcd54): `23505` é `unique_violation` e pode vir do perfil, da membership
 *   ou do vínculo, inclusive para um usuário que a Edge acabou de criar.
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
  it("P0002 (colaborador inexistente no tenant) ⇒ inválido", () => {
    const decisao = decidirFalhaDoVinculo({ code: "P0002" });
    expect(decisao.codigo).toBe("INVALID_COLLABORATOR");
    expect(decisao.status).toBe(400);
  });

  it("23503 (organização inexistente) ⇒ inválido", () => {
    const decisao = decidirFalhaDoVinculo({ code: "23503" });
    expect(decisao.codigo).toBe("INVALID_ORGANIZATION");
    expect(decisao.status).toBe(400);
  });

  it("22023 (parâmetros obrigatórios) ⇒ inválido", () => {
    const decisao = decidirFalhaDoVinculo({ code: "22023" });
    expect(decisao.codigo).toBe("INVALID_INPUT");
    expect(decisao.status).toBe(400);
  });

  it("23505 ORIGINADO NO PROVISIONAMENTO não prova usuário pré-existente no Auth (auditoria 62bcd54)", () => {
    // `unique_violation` pode vir do perfil, da membership ou do vínculo. O
    // código público é de conflito, mas NÃO existe aqui — em nenhum campo —
    // uma decisão de dispensar a compensação.
    const decisao = decidirFalhaDoVinculo({ code: "23505" });
    expect(decisao.codigo).toBe("USER_EXISTS");
    expect(decisao.status).toBe(409);
    expect(Object.keys(decisao).sort()).toEqual(["codigo", "mensagem", "status"]);
  });

  it("falha do primitivo, erro desconhecido ou ausente ⇒ INTERNAL", () => {
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
    }
  });

  it("após compensação BEM-SUCEDIDA, conflito não pode ser reportado como 'já existe'", () => {
    const compensado = codigoPublicoAposCompensacao({
      codigo: "USER_EXISTS",
      mensagem: "Já existe um usuário com este e-mail.",
      status: 409,
    });
    // Nada permanece (Auth removido + RPC revertida): "já existe" seria FALSO.
    expect(compensado.codigo).toBe("INTERNAL");
    expect(compensado.status).toBe(500);

    // Falha de forma/tenant continua sendo a causa acionável do convite.
    const forma = codigoPublicoAposCompensacao({
      codigo: "INVALID_COLLABORATOR",
      mensagem: "Colaborador inválido.",
      status: 400,
    });
    expect(forma.codigo).toBe("INVALID_COLLABORATOR");
    expect(forma.status).toBe(400);
  });

  it("sem compensação, SÓ o perfil sobrevivente prova conta real (retry não destrutivo)", () => {
    const contaReal = codigoPublicoQuandoNaoCompensado(true);
    expect(contaReal.codigo).toBe("USER_EXISTS");
    expect(contaReal.status).toBe(409);

    const semProva = codigoPublicoQuandoNaoCompensado(false);
    expect(semProva.codigo).toBe("INTERNAL");
    expect(semProva.status).toBe(500);
  });
});
