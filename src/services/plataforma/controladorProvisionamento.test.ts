import { describe, expect, it, beforeEach } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ConflictError,
  ForbiddenError,
  TechnicalError,
  ValidationError,
} from "../../errors/applicationErrors";
import {
  criarProvisionamentoPlataforma,
  mapearErroPlataforma,
  obterProvisionamentoPlataforma,
  redefinirProvisionamentoPlataforma,
} from "./controladorProvisionamento";
import type {
  EdgePlataforma,
  ResultadoEdgePlataforma,
} from "../../infrastructure/supabase/plataforma/edgePlataforma";
import type { CodigoPublico } from "../../infrastructure/supabase/plataforma/contrato";

/**
 * F6-A03 (Issue #266) — controlador do plano de plataforma.
 *
 * Prova que o código público FECHADO vira a taxonomia F0-05 (mensagem canônica,
 * nunca a do servidor), que o resultado só é aceito na forma exata
 * `{ organization_id: <string não vazia> }`, que o self-check NUNCA lança e é
 * fail-closed, e que a identidade local do operador é fail-closed (`null`).
 */

const ORGANIZACAO = "f6a30000-0000-4000-8000-0000000000f1";
const OPERADOR = "f6a30000-0000-4000-8000-000000000003";
const OPERACAO_ID = "f6a3b000-0000-4000-8000-000000000001";

interface EdgeFalsa extends EdgePlataforma {
  readonly provisoes: unknown[];
}

function edgeFalsa(opcoes: {
  provisao?: ResultadoEdgePlataforma<unknown>;
  operador?: ResultadoEdgePlataforma<unknown> | Error;
  identidade?: string | null;
}): EdgeFalsa {
  const provisoes: unknown[] = [];
  return {
    provisoes,
    provisionarOrganizacao: async (entrada) => {
      provisoes.push(entrada);
      return opcoes.provisao ?? { ok: true, data: { organization_id: ORGANIZACAO } };
    },
    operadorAtual: async () => {
      if (opcoes.operador instanceof Error) throw opcoes.operador;
      return opcoes.operador ?? { ok: true, data: { operador: true } };
    },
  };
}

function controlador(
  edge: EdgePlataforma,
  lerUsuarioAutenticado?: () => Promise<string | null>
) {
  return criarProvisionamentoPlataforma({ edge, ...(lerUsuarioAutenticado ? { lerUsuarioAutenticado } : {}) });
}

describe("F6-A03 — controlador: código público → taxonomia F0-05", () => {
  it("mapeia cada código para o erro canônico", () => {
    const casos: readonly (readonly [CodigoPublico, unknown])[] = [
      ["NOT_AUTHORIZED", ForbiddenError],
      ["INVALID_INPUT", ValidationError],
      ["INVALID_NAME", ValidationError],
      ["INVALID_FOUNDER", ValidationError],
      ["USER_EXISTS", ConflictError],
      ["OPERATION_ALREADY_APPLIED", ConflictError],
      ["INTERNAL", TechnicalError],
      ["METHOD_NOT_ALLOWED", TechnicalError],
    ];
    for (const [codigo, classe] of casos) {
      expect(mapearErroPlataforma(codigo), codigo).toBeInstanceOf(classe);
    }
  });

  it("a mensagem apresentada é a CANÔNICA do código (nunca a do servidor)", () => {
    expect(mapearErroPlataforma("USER_EXISTS").publicMessage).toBe(
      "Não foi possível concluir a operação devido a um conflito."
    );
    expect(mapearErroPlataforma("INVALID_NAME").publicMessage).toBe(
      "Verifique os dados informados e tente novamente."
    );
  });
});

describe("F6-A03 — controlador: provisionamento", () => {
  it("devolve o organization_id soberano e transporta a intenção", async () => {
    const edge = edgeFalsa({});
    const porta = controlador(edge);

    const resultado = await porta.provisionarOrganizacao({
      operationId: OPERACAO_ID,
      organizationName: "Org Sintetica",
      founderUserId: OPERADOR,
    });

    expect(resultado).toEqual({ organizationId: ORGANIZACAO });
    expect(edge.provisoes).toEqual([
      {
        operationId: OPERACAO_ID,
        organizationName: "Org Sintetica",
        founderUserId: OPERADOR,
      },
    ]);
  });

  it("recusa é LANÇADA como ApplicationError da taxonomia", async () => {
    const edge = edgeFalsa({
      provisao: { ok: false, error: { code: "OPERATION_ALREADY_APPLIED", message: "x" } },
    });
    await expect(
      controlador(edge).provisionarOrganizacao({ operationId: OPERACAO_ID, organizationName: "Org" })
    ).rejects.toBeInstanceOf(ConflictError);
  });

  it("resultado fora da forma exata ⇒ TechnicalError (nunca sucesso presumido)", async () => {
    for (const data of [
      null,
      {},
      { organization_id: "" },
      { organization_id: "   " },
      { organization_id: 42 },
      { organizationId: ORGANIZACAO },
    ]) {
      const edge = edgeFalsa({ provisao: { ok: true, data } });
      await expect(
        controlador(edge).provisionarOrganizacao({ operationId: OPERACAO_ID, organizationName: "Org" }),
        JSON.stringify(data)
      ).rejects.toBeInstanceOf(TechnicalError);
    }
  });
});

describe("F6-A03 — controlador: self-check (D20)", () => {
  it("`true` SOMENTE com `ok: true` e `operador === true`", async () => {
    const verdadeiro = controlador(edgeFalsa({ operador: { ok: true, data: { operador: true } } }));
    expect(await verdadeiro.souOperadorDaPlataforma()).toBe(true);

    for (const resposta of [
      { ok: true, data: { operador: false } },
      { ok: true, data: { operador: "true" } },
      { ok: true, data: null },
      { ok: true, data: {} },
      { ok: false, error: { code: "NOT_AUTHORIZED", message: "x" } },
    ] as ResultadoEdgePlataforma<unknown>[]) {
      const porta = controlador(edgeFalsa({ operador: resposta }));
      expect(await porta.souOperadorDaPlataforma(), JSON.stringify(resposta)).toBe(false);
    }
  });

  it("NUNCA lança: falha de transporte resolve `false`", async () => {
    const porta = controlador(edgeFalsa({ operador: new Error("rede fora") }));
    await expect(porta.souOperadorDaPlataforma()).resolves.toBe(false);
  });
});

describe("F6-A03 — controlador: identidade do operador (fail-closed)", () => {
  it("devolve o UUID da sessão quando o leitor existe", async () => {
    const porta = controlador(edgeFalsa({}), async () => OPERADOR);
    expect(await porta.identidadeDoOperadorAutenticado()).toBe(OPERADOR);
  });

  it("sem leitor, com erro ou com `null` ⇒ `null`", async () => {
    expect(await controlador(edgeFalsa({})).identidadeDoOperadorAutenticado()).toBeNull();

    const comErro = controlador(edgeFalsa({}), async () => {
      throw new Error("sessão indisponível");
    });
    expect(await comErro.identidadeDoOperadorAutenticado()).toBeNull();

    const semSessao = controlador(edgeFalsa({}), async () => null);
    expect(await semSessao.identidadeDoOperadorAutenticado()).toBeNull();
  });
});

describe("F6-A03 — controlador: composição é fail-closed", () => {
  beforeEach(() => redefinirProvisionamentoPlataforma());

  it("sem cliente Supabase não existe caminho soberano (`null`)", () => {
    expect(obterProvisionamentoPlataforma({ cliente: null })).toBeNull();
  });

  it("injeção explícita tem precedência e não toca o ambiente", () => {
    const porta = controlador(edgeFalsa({}));
    expect(obterProvisionamentoPlataforma({ provisionamento: porta })).toBe(porta);
  });

  it("a composição de produção resolve a identidade pela sessão local", async () => {
    const cliente = {
      auth: { getSession: async () => ({ data: { session: { user: { id: OPERADOR } } }, error: null }) },
      functions: {
        invoke: async () => ({ data: { ok: true, resultado: { operador: true } }, error: null }),
      },
    } as unknown as SupabaseClient;

    const porta = obterProvisionamentoPlataforma({ cliente });
    expect(porta).not.toBeNull();
    expect(await porta?.identidadeDoOperadorAutenticado()).toBe(OPERADOR);
    expect(await porta?.souOperadorDaPlataforma()).toBe(true);
  });

  it("erro ao ler a sessão local ⇒ `null` (nenhum 'eu mesmo' presumido)", async () => {
    const cliente = {
      auth: { getSession: async () => ({ data: { session: null }, error: { message: "boom" } }) },
      functions: { invoke: async () => ({ data: null, error: null }) },
    } as unknown as SupabaseClient;

    const porta = obterProvisionamentoPlataforma({ cliente });
    expect(await porta?.identidadeDoOperadorAutenticado()).toBeNull();
  });
});
