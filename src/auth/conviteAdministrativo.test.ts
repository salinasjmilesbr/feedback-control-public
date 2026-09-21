import { describe, expect, it } from "vitest";
import {
  ConflictError,
  ForbiddenError,
  TechnicalError,
  ValidationError,
} from "../errors/applicationErrors";
import { mapearErroConvite } from "./conviteAdministrativo";
import conviteFonte from "./conviteAdministrativo.ts?raw";
import authProviderFonte from "./AuthProvider.tsx?raw";

/**
 * F2-06 + **Issue #224** — mapeamento do erro do convite administrativo.
 *
 * DEFEITO CORRIGIDO: `FunctionsHttpError.context` é um **`Response` REAL** no
 * runtime de `@supabase/functions-js` (a lib executa
 * `throw new FunctionsHttpError(response)` em `FunctionsClient.js`; a própria
 * documentação manda `await error.context.json()`), mas o convite lia
 * `context.error.code` de forma **síncrona**, como se `context` fosse o corpo já
 * decodificado. Em produção isso devolvia `undefined` e **toda** negação da Edge
 * virava `TechnicalError`, apagando `NOT_AUTHORIZED`, `INVALID_*` e `USER_EXISTS`.
 *
 * A leitura passou a ser **assíncrona** e delegada à fonte única `corpoDeErroEdge`
 * (Issue #221). Estes testes usam `Response` REAL, provam o **fail-closed** e
 * guardam o call graph assíncrono (nenhuma `Promise` não aguardada).
 *
 * Todos os identificadores e mensagens são sintéticos.
 */

/** Envelope público da Edge, como a fronteira o devolve. */
function respostaErro(codigo: string, mensagem: string, status: number): Response {
  return new Response(JSON.stringify({ error: { code: codigo, message: mensagem } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Erro de transporte como o runtime o entrega: `context` é o `Response`. */
function erroHttp(codigo: string, mensagem: string, status: number) {
  return { context: respostaErro(codigo, mensagem, status) };
}

/** Remove comentários de linha e de bloco (visão de CÓDIGO, não de prosa). */
function semComentarios(fonte: string): string {
  return fonte.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
}

const CODIGOS_PUBLICOS: readonly { readonly codigo: string; readonly status: number }[] = [
  { codigo: "NOT_AUTHORIZED", status: 401 },
  { codigo: "INVALID_EMAIL", status: 400 },
  { codigo: "INVALID_ORGANIZATION", status: 400 },
  { codigo: "INVALID_COLLABORATOR", status: 400 },
  { codigo: "INVALID_INPUT", status: 400 },
  { codigo: "USER_EXISTS", status: 409 },
];

const CASOS_FAIL_CLOSED: readonly { readonly nome: string; readonly criar: () => unknown }[] = [
  {
    nome: "body JSON inválido",
    criar: () => ({ context: new Response("<<<nao-e-json", { status: 500 }) }),
  },
  { nome: "body vazio", criar: () => ({ context: new Response("", { status: 500 }) }) },
  { nome: "body nulo (204)", criar: () => ({ context: new Response(null, { status: 204 }) }) },
  {
    nome: "corpo válido fora do contrato",
    criar: () => ({ context: new Response('{"foo":1}', { status: 409 }) }),
  },
  {
    nome: "envelope sem `code` nem `message`",
    criar: () => ({ context: new Response('{"error":{}}', { status: 500 }) }),
  },
  { nome: "corpo que é lista JSON", criar: () => ({ context: new Response("[]", { status: 409 }) }) },
  { nome: "erro sem `context`", criar: () => ({ message: "falha de transporte" }) },
  { nome: "`context` sem corpo de erro", criar: () => ({ context: { status: 500 } }) },
  { nome: "`context` textual", criar: () => ({ context: "texto" }) },
  { nome: "erro que não é objeto", criar: () => 42 },
  { nome: "erro nulo", criar: () => null },
];

describe("mapearErroConvite (F2-06) — Response REAL (Issue #224)", () => {
  it("NOT_AUTHORIZED (401) vira erro de autorização", async () => {
    const erro = await mapearErroConvite(erroHttp("NOT_AUTHORIZED", "Não autorizado.", 401));
    expect(erro).toBeInstanceOf(ForbiddenError);
  });

  it.each(["INVALID_EMAIL", "INVALID_ORGANIZATION", "INVALID_COLLABORATOR", "INVALID_INPUT"])(
    "entrada inválida %s vira erro de validação",
    async (codigo) => {
      const erro = await mapearErroConvite(erroHttp(codigo, "Dados inválidos.", 400));
      expect(erro).toBeInstanceOf(ValidationError);
    }
  );

  it("USER_EXISTS (409) vira conflito", async () => {
    const erro = await mapearErroConvite(erroHttp("USER_EXISTS", "Usuário já existe.", 409));
    expect(erro).toBeInstanceOf(ConflictError);
  });

  it("todos os códigos públicos do convite são preservados (body JSON válido)", async () => {
    for (const { codigo, status } of CODIGOS_PUBLICOS) {
      const erro = await mapearErroConvite(erroHttp(codigo, `falha ${codigo}`, status));
      expect(erro, codigo).not.toBeInstanceOf(TechnicalError);
    }
  });

  it("o mapeamento é ASSÍNCRONO: devolve Promise e não lança o erro público", () => {
    const resultado = mapearErroConvite(erroHttp("USER_EXISTS", "Usuário já existe.", 409));
    expect(resultado).toBeInstanceOf(Promise);
    // Consome a promise para não deixar rejeição pendente no teste.
    void resultado;
  });
});

describe("mapearErroConvite (F2-06) — fail-closed (Issue #224)", () => {
  for (const caso of CASOS_FAIL_CLOSED) {
    it(`${caso.nome} ⇒ TechnicalError`, async () => {
      const erro = await mapearErroConvite(caso.criar());
      expect(erro).toBeInstanceOf(TechnicalError);
    });
  }

  it("código público DESCONHECIDO ⇒ TechnicalError", async () => {
    const erro = await mapearErroConvite(erroHttp("CODIGO_DESCONHECIDO", "x", 500));
    expect(erro).toBeInstanceOf(TechnicalError);
  });

  it("stream já consumido ⇒ TechnicalError (nunca lança)", async () => {
    const consumida = respostaErro("NOT_AUTHORIZED", "Não autorizado.", 401);
    await consumida.text();
    const erro = await mapearErroConvite({ context: consumida });
    expect(erro).toBeInstanceOf(TechnicalError);
  });
});

describe("mapearErroConvite (F2-06) — compatibilidade e projeção pública", () => {
  it("mantém compatibilidade com o corpo já decodificado (objeto simples)", async () => {
    const erro = await mapearErroConvite({
      context: { error: { code: "USER_EXISTS", message: "mensagem interna segura" } },
    });
    expect(erro).toBeInstanceOf(ConflictError);
  });

  it("não vaza a mensagem interna da fronteira na projeção pública", async () => {
    const erro = await mapearErroConvite(
      erroHttp("NOT_AUTHORIZED", "mensagem interna segura", 401)
    );
    expect(JSON.stringify(erro.publicMessage)).not.toContain("mensagem interna");
    expect(erro.publicMessage).toBe("Você não tem permissão para realizar esta operação.");
  });

  it("nenhum código público projeta a mensagem interna", async () => {
    for (const { codigo, status } of CODIGOS_PUBLICOS) {
      const erro = await mapearErroConvite(erroHttp(codigo, "segredo interno fictício", status));
      expect(JSON.stringify(erro.publicMessage), codigo).not.toContain("segredo interno");
      expect(erro.publicMessage.length, codigo).toBeGreaterThan(0);
    }
  });
});

describe("Issue #224 — guardas estáticas do call graph assíncrono", () => {
  it("o convite reutiliza a fonte única `corpoDeErroEdge` e NÃO lê `context` por conta própria", () => {
    const codigo = semComentarios(conviteFonte);
    expect(codigo).toContain("corpoDeErroEdge");
    // A leitura do `Response` vive em `errosEdge` (#221): duplicar aqui é regressão.
    expect(codigo).not.toContain("context");
  });

  it("`AuthProvider.convidarUsuario` AGUARDA o mapeamento (nenhuma Promise não aguardada)", () => {
    const codigo = semComentarios(authProviderFonte);
    expect(codigo).toContain("throw await mapearErroConvite(");
    expect(codigo).not.toContain("throw mapearErroConvite(");
    // Um único ponto de chamada — e ele é aguardado.
    expect(codigo.match(/mapearErroConvite\(/g) ?? []).toHaveLength(1);
  });

  it("o caminho de SUCESSO do convite permanece intacto", () => {
    const codigo = semComentarios(authProviderFonte);
    expect(codigo).toContain('cliente.functions.invoke("convidar-usuario"');
    expect(codigo).toContain('if (!data || typeof data.userId !== "string") throw new TechnicalError();');
    expect(codigo).toContain("return { userId: data.userId };");
  });
});
