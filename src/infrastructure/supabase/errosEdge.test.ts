import { describe, expect, it } from "vitest";
import { corpoDeErroEdge } from "./errosEdge";

/**
 * F5-10 P5.1 (Issue #221) — leitura do corpo de erro de Edge Functions.
 *
 * O defeito confirmado: `FunctionsHttpError.context` é um **`Response`** no
 * runtime de `@supabase/functions-js` (a doc da lib manda `await
 * error.context.json()`), mas os adapters liam `error.context.error.code` como se
 * `context` fosse o corpo já decodificado — em produção `undefined`, e TODA
 * negação da Edge virava `FORBIDDEN` genérico.
 *
 * Estes testes usam `Response` REAL (não objeto simples) e provam o fail-closed.
 */

/** Envelope público da Edge, como a fronteira o devolve. */
function respostaErro(codigo: string, mensagem: string, status: number): Response {
  return new Response(JSON.stringify({ error: { code: codigo, message: mensagem } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("corpoDeErroEdge — leitura do corpo a partir de `Response` REAL", () => {
  it("lê CONFLICT (409) do corpo real", async () => {
    const erro = { context: respostaErro("CONFLICT", "expected_version divergente", 409) };
    await expect(corpoDeErroEdge(erro)).resolves.toEqual({
      code: "CONFLICT",
      message: "expected_version divergente",
    });
  });

  it("lê NOT_FOUND (404) e FORBIDDEN (403) do corpo real", async () => {
    await expect(
      corpoDeErroEdge({ context: respostaErro("NOT_FOUND", "Meta não encontrada.", 404) })
    ).resolves.toEqual({ code: "NOT_FOUND", message: "Meta não encontrada." });

    await expect(
      corpoDeErroEdge({ context: respostaErro("FORBIDDEN", "Sem permissão.", 403) })
    ).resolves.toEqual({ code: "FORBIDDEN", message: "Sem permissão." });
  });

  it("preserva os demais códigos públicos suportados", async () => {
    for (const [status, codigo] of [
      [400, "INVALID_INPUT"],
      [401, "NOT_AUTHORIZED"],
      [405, "METHOD_NOT_ALLOWED"],
      [500, "INTERNAL"],
    ] as const) {
      await expect(
        corpoDeErroEdge({ context: respostaErro(codigo, `falha ${codigo}`, status) })
      ).resolves.toEqual({ code: codigo, message: `falha ${codigo}` });
    }
  });

  it("JSON inválido ⇒ null (fail-closed, sem lançar)", async () => {
    await expect(corpoDeErroEdge({ context: new Response("<<<nao-e-json", { status: 500 }) })).resolves.toBeNull();
  });

  it("body vazio ⇒ null (fail-closed, sem lançar)", async () => {
    await expect(corpoDeErroEdge({ context: new Response("", { status: 500 }) })).resolves.toBeNull();
    await expect(
      corpoDeErroEdge({ context: new Response(null, { status: 204 }) })
    ).resolves.toBeNull();
  });

  it("body válido FORA do contrato ⇒ null (fail-closed)", async () => {
    for (const corpo of ['{"foo":1}', '{"code":"CONFLICT"}', '{"error":"texto"}', "[]", "42"]) {
      await expect(
        corpoDeErroEdge({ context: new Response(corpo, { status: 409 }) }),
        corpo
      ).resolves.toBeNull();
    }
    // Envelope presente mas sem `code`/`message` não é corpo de erro útil.
    await expect(
      corpoDeErroEdge({ context: new Response('{"error":{}}', { status: 500 }) })
    ).resolves.toBeNull();
  });

  it("mantém compatibilidade com o corpo já decodificado (objeto simples)", async () => {
    await expect(
      corpoDeErroEdge({ context: { error: { code: "CONFLICT", message: "versão divergente" } } })
    ).resolves.toEqual({ code: "CONFLICT", message: "versão divergente" });
  });

  it("erro sem `context` ou que não é objeto ⇒ null (fail-closed)", async () => {
    for (const erro of [
      undefined,
      null,
      42,
      "erro",
      {},
      { context: null },
      { context: undefined },
      { context: "texto" },
    ]) {
      await expect(corpoDeErroEdge(erro), JSON.stringify(erro)).resolves.toBeNull();
    }
  });

  it("NUNCA lança quando a leitura do corpo falha (stream consumido/json que rejeita)", async () => {
    const respostaConsumida = new Response('{"error":{"code":"CONFLICT"}}', { status: 409 });
    await respostaConsumida.text(); // consome o corpo: o próximo json() rejeita
    await expect(corpoDeErroEdge({ context: respostaConsumida })).resolves.toBeNull();

    const jsonQueRejeita = { json: async () => Promise.reject(new Error("falha de leitura")) };
    await expect(corpoDeErroEdge({ context: jsonQueRejeita })).resolves.toBeNull();
  });
});
