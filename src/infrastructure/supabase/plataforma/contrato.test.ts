import { describe, expect, it } from "vitest";
import {
  CHAVES_POR_OPERACAO,
  CODIGOS_PUBLICOS,
  EMAIL_MINIMO,
  OPERACAO_OPERADOR_ATUAL,
  OPERACAO_PROVISIONAR_ORGANIZACAO,
  OPERACOES_PLATAFORMA,
  UUID_CANONICO,
  eCodigoPublico,
  eOperacaoPlataforma,
  validarEntradaProvisaoPlataforma,
  validarSomenteOperacao,
} from "./contrato";

/**
 * F6-A03 (Issue #266) — contrato transportável único da superfície de
 * PLATAFORMA.
 *
 * Prova que a FORMA nunca é autoridade: a allowlist de chaves é ESTRITA por
 * operação, nenhum campo de identidade/autoridade é aceito (`actor_*`,
 * `organization_id`, `capability`, `scope`, `status`, `version`, `origin`,
 * `payload_hash`), o XOR do primeiro Admin é obrigatório e a lista de códigos
 * públicos é fechada (D21: escopo com exatamente duas operações).
 *
 * F6-A11 (Issue #273): a intenção ganhou a identidade FUNCIONAL mínima do
 * primeiro Admin (`founder_full_name` e `founder_matricula`, ambas
 * obrigatórias — D23/D26/D28); a allowlist estrita passa a ter 7 chaves.
 */

const OPERACAO_ID = "66666666-6666-4666-8666-666666666666";
const FOUNDER_ID = "77777777-7777-4777-8777-777777777777";
/** Dados FICTÍCIOS da identidade funcional mínima do primeiro Admin (F6-A11). */
const NOME_ADMIN = "Admin Teste A11";
const MATRICULA_ADMIN = "A1100001";

function corpoValido(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    operacao: OPERACAO_PROVISIONAR_ORGANIZACAO,
    operation_id: OPERACAO_ID,
    organization_name: "Org Sintetica F6-A03",
    founder_user_id: FOUNDER_ID,
    founder_full_name: NOME_ADMIN,
    founder_matricula: MATRICULA_ADMIN,
    ...extra,
  };
}

describe("F6-A03 — contrato: operações fechadas (D21)", () => {
  it("expõe EXATAMENTE duas operações", () => {
    expect([...OPERACOES_PLATAFORMA].sort()).toEqual(
      [OPERACAO_OPERADOR_ATUAL, OPERACAO_PROVISIONAR_ORGANIZACAO].sort()
    );
    expect(OPERACOES_PLATAFORMA).toHaveLength(2);
  });

  it("reconhece apenas as operações contratadas (sem default permissivo)", () => {
    expect(eOperacaoPlataforma(OPERACAO_PROVISIONAR_ORGANIZACAO)).toBe(true);
    expect(eOperacaoPlataforma(OPERACAO_OPERADOR_ATUAL)).toBe(true);
    for (const invalida of [
      "observacao.criar",
      "goal.criar",
      "plataforma.listar_organizacoes",
      "plataforma.gerenciar_operador",
      "",
      null,
      42,
      {},
    ]) {
      expect(eOperacaoPlataforma(invalida), String(invalida)).toBe(false);
    }
  });

  it("a allowlist de chaves não transporta NENHUM campo de autoridade", () => {
    const proibidas = [
      "actor_user_profile_id",
      "organization_id",
      "access_role_id",
      "capability",
      "scope",
      "status",
      "version",
      "origin",
      "payload_hash",
    ];
    for (const operacao of OPERACOES_PLATAFORMA) {
      const chaves = CHAVES_POR_OPERACAO[operacao];
      expect(chaves[0]).toBe("operacao");
      for (const proibida of proibidas) {
        expect(chaves, `${operacao}:${proibida}`).not.toContain(proibida);
      }
    }
  });

  it("a allowlist da provisão tem EXATAMENTE as 7 chaves contratadas (F6-A11/D26)", () => {
    expect([...CHAVES_POR_OPERACAO[OPERACAO_PROVISIONAR_ORGANIZACAO]].sort()).toEqual(
      [
        "operacao",
        "operation_id",
        "organization_name",
        "founder_user_id",
        "founder_email",
        "founder_full_name",
        "founder_matricula",
      ].sort()
    );
    // O self-check continua transportando SOMENTE `operacao` (D20).
    expect([...CHAVES_POR_OPERACAO[OPERACAO_OPERADOR_ATUAL]]).toEqual(["operacao"]);
  });

  it("a lista de códigos públicos é fechada e não inclui código de sucesso", () => {
    expect([...CODIGOS_PUBLICOS].sort()).toEqual(
      [
        "INTERNAL",
        "INVALID_FOUNDER",
        "INVALID_INPUT",
        "INVALID_NAME",
        "METHOD_NOT_ALLOWED",
        "NOT_AUTHORIZED",
        "OPERATION_ALREADY_APPLIED",
        "USER_EXISTS",
      ].sort()
    );
    expect(eCodigoPublico("FORBIDDEN")).toBe(false);
    expect(eCodigoPublico("OK")).toBe(false);
    expect(eCodigoPublico("USER_EXISTS")).toBe(true);
  });
});

describe("F6-A03 — contrato: allowlist ESTRITA por operação", () => {
  it("aceita o corpo mínimo válido com founder_user_id", () => {
    const resultado = validarEntradaProvisaoPlataforma(corpoValido());
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada.organizationName).toBe("Org Sintetica F6-A03");
    expect(resultado.entrada.founderUserId).toBe(FOUNDER_ID);
    expect(resultado.entrada.founderEmail).toBeUndefined();
    expect(resultado.entrada.operationId).toBe(OPERACAO_ID);
    // F6-A11/D26: a identidade funcional mínima acompanha o XOR do Admin.
    expect(resultado.entrada.founderFullName).toBe(NOME_ADMIN);
    expect(resultado.entrada.founderMatricula).toBe(MATRICULA_ADMIN);
  });

  it("aceita founder_email normalizado (trim + minúsculas)", () => {
    const corpo = corpoValido();
    delete corpo.founder_user_id;
    corpo.founder_email = "  Primeiro.Admin@Example.INVALID  ";

    const resultado = validarEntradaProvisaoPlataforma(corpo);
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada.founderEmail).toBe("primeiro.admin@example.invalid");
    expect(resultado.entrada.founderUserId).toBeUndefined();
  });

  it("RECUSA qualquer chave fora da allowlist da operação", () => {
    for (const chave of [
      "actor_user_profile_id",
      "organization_id",
      "access_role_id",
      "capability",
      "scope",
      "status",
      "version",
      "origin",
      "payload_hash",
      "founder_self",
      "observacao",
      "extra",
    ]) {
      const resultado = validarEntradaProvisaoPlataforma(corpoValido({ [chave]: "x" }));
      expect(resultado.ok, chave).toBe(false);
      if (!resultado.ok) expect(resultado.codigo, chave).toBe("INVALID_INPUT");
    }
  });

  it("RECUSA corpo que não é objeto e operação desconhecida", () => {
    for (const corpo of [null, [], "texto", 7]) {
      const resultado = validarEntradaProvisaoPlataforma(corpo);
      expect(resultado.ok).toBe(false);
      if (!resultado.ok) expect(resultado.codigo).toBe("INVALID_INPUT");
    }
  });
});

describe("F6-A03 — contrato: forma do provisionamento", () => {
  it("exige operation_id em UUID canônico", () => {
    for (const invalido of ["", "abc", 123, "66666666-6666-4666-8666-66666666666"]) {
      const resultado = validarEntradaProvisaoPlataforma(corpoValido({ operation_id: invalido }));
      expect(resultado.ok, String(invalido)).toBe(false);
      if (!resultado.ok) expect(resultado.codigo).toBe("INVALID_INPUT");
    }
    expect(UUID_CANONICO.test(OPERACAO_ID)).toBe(true);
  });

  it("exige nome não vazio depois do trim", () => {
    for (const invalido of ["", "   ", "\t\n", undefined, 42]) {
      const resultado = validarEntradaProvisaoPlataforma(
        corpoValido({ organization_name: invalido })
      );
      expect(resultado.ok, String(invalido)).toBe(false);
      if (!resultado.ok) expect(resultado.codigo).toBe("INVALID_NAME");
    }
  });

  it("exige EXATAMENTE uma forma de identificação do primeiro Admin (XOR)", () => {
    const semNenhuma = corpoValido();
    delete semNenhuma.founder_user_id;
    const resultadoSem = validarEntradaProvisaoPlataforma(semNenhuma);
    expect(resultadoSem.ok).toBe(false);
    if (!resultadoSem.ok) expect(resultadoSem.codigo).toBe("INVALID_INPUT");

    const comAmbas = corpoValido({ founder_email: "outro.admin@example.invalid" });
    const resultadoAmbas = validarEntradaProvisaoPlataforma(comAmbas);
    expect(resultadoAmbas.ok).toBe(false);
    if (!resultadoAmbas.ok) expect(resultadoAmbas.codigo).toBe("INVALID_INPUT");
  });

  it("recusa identificador/e-mail inválidos do primeiro Admin", () => {
    const idInvalido = validarEntradaProvisaoPlataforma(corpoValido({ founder_user_id: "nope" }));
    expect(idInvalido.ok).toBe(false);
    if (!idInvalido.ok) expect(idInvalido.codigo).toBe("INVALID_FOUNDER");

    const corpo = corpoValido();
    delete corpo.founder_user_id;
    corpo.founder_email = "sem-arroba";
    const emailInvalido = validarEntradaProvisaoPlataforma(corpo);
    expect(emailInvalido.ok).toBe(false);
    if (!emailInvalido.ok) expect(emailInvalido.codigo).toBe("INVALID_FOUNDER");

    expect(EMAIL_MINIMO.test("a@b.invalid")).toBe(true);
    expect(EMAIL_MINIMO.test("a@b")).toBe(false);
  });
});

describe("F6-A03 — contrato: operações só de `operacao`", () => {
  it("aceita corpo com a única chave permitida", () => {
    expect(validarSomenteOperacao({ operacao: OPERACAO_OPERADOR_ATUAL }, OPERACAO_OPERADOR_ATUAL)).toEqual({
      ok: true,
    });
  });

  it("recusa chave adicional e corpo não-objeto", () => {
    const comExtra = validarSomenteOperacao(
      { operacao: OPERACAO_OPERADOR_ATUAL, organization_id: "x" },
      OPERACAO_OPERADOR_ATUAL
    );
    expect(comExtra.ok).toBe(false);
    if (!comExtra.ok) expect(comExtra.codigo).toBe("INVALID_INPUT");

    const naoObjeto = validarSomenteOperacao(null, OPERACAO_OPERADOR_ATUAL);
    expect(naoObjeto.ok).toBe(false);
  });
});

/**
 * F6-A11 (Issue #273) — identidade FUNCIONAL mínima do primeiro Admin
 * (`founder_full_name` + `founder_matricula`, D23/D26/D28).
 *
 * Prova que a ausência/vazio de cada campo novo é fail-closed com a taxonomia
 * FECHADA (nenhum código público novo), que os valores são normalizados por
 * `trim` na entrada devolvida e que a allowlist estrita continua recusando
 * qualquer chave fora das 7 contratadas.
 */
describe("F6-A11 — contrato: identidade funcional mínima do primeiro Admin", () => {
  it("corpo SEM founder_full_name ⇒ INVALID_NAME (nunca sucesso presumido)", () => {
    const ausente = corpoValido();
    delete ausente.founder_full_name;
    const semCampo = validarEntradaProvisaoPlataforma(ausente);
    expect(semCampo.ok).toBe(false);
    if (!semCampo.ok) {
      expect(semCampo.codigo).toBe("INVALID_NAME");
      expect(semCampo.message).toBe("Informe o nome do primeiro Admin.");
    }

    for (const vazio of ["", "   ", "\t\n", undefined, 42]) {
      const resultado = validarEntradaProvisaoPlataforma(
        corpoValido({ founder_full_name: vazio })
      );
      expect(resultado.ok, String(vazio)).toBe(false);
      if (!resultado.ok) expect(resultado.codigo, String(vazio)).toBe("INVALID_NAME");
    }
  });

  it("corpo SEM founder_matricula ⇒ INVALID_FOUNDER (nunca sucesso presumido)", () => {
    const ausente = corpoValido();
    delete ausente.founder_matricula;
    const semCampo = validarEntradaProvisaoPlataforma(ausente);
    expect(semCampo.ok).toBe(false);
    if (!semCampo.ok) {
      expect(semCampo.codigo).toBe("INVALID_FOUNDER");
      expect(semCampo.message).toBe("Informe a matrícula do primeiro Admin.");
    }

    for (const vazio of ["", "   ", "\t\n", undefined, 42]) {
      const resultado = validarEntradaProvisaoPlataforma(
        corpoValido({ founder_matricula: vazio })
      );
      expect(resultado.ok, String(vazio)).toBe(false);
      if (!resultado.ok) expect(resultado.codigo, String(vazio)).toBe("INVALID_FOUNDER");
    }
  });

  it("normaliza nome e matrícula do Admin com trim na entrada devolvida", () => {
    const resultado = validarEntradaProvisaoPlataforma(
      corpoValido({
        founder_full_name: `   ${NOME_ADMIN}  `,
        founder_matricula: `  ${MATRICULA_ADMIN}\t`,
      })
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada.founderFullName).toBe(NOME_ADMIN);
    expect(resultado.entrada.founderMatricula).toBe(MATRICULA_ADMIN);
  });

  it("chave desconhecida continua ⇒ INVALID_INPUT (allowlist estrita)", () => {
    for (const chave of ["founder_fullname", "founder_matriculas", "founder_admin", "nome_admin"]) {
      const resultado = validarEntradaProvisaoPlataforma(corpoValido({ [chave]: "x" }));
      expect(resultado.ok, chave).toBe(false);
      if (!resultado.ok) expect(resultado.codigo, chave).toBe("INVALID_INPUT");
    }
  });
});
