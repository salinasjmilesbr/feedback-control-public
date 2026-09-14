import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { criarEdgeMetas } from "./metas/edgeMetas";
import { criarEdgeCiclos } from "./ciclos/edgeCiclos";
import { criarRepositorioColaboradoresSupabase } from "./colaboradores/repositorioColaboradores";
import { criarRepositorioAvaliacoesSupabase } from "./avaliacoes/repositorioAvaliacoes";

/**
 * F5-10 P5.1 (Issue #221) — propagação de erro das Edge Functions nos adapters.
 *
 * DEFEITO CORRIGIDO: `FunctionsHttpError.context` é um **`Response`** no runtime
 * de `@supabase/functions-js` (a lib manda `await error.context.json()`), mas os
 * quatro adapters liam `error.context.error.code` como se `context` fosse o corpo
 * já decodificado ⇒ `undefined` em produção ⇒ **toda negação da Edge virava
 * `FORBIDDEN`** e `CONFLICT`/`NOT_FOUND` nunca chegavam à aplicação.
 *
 * Este arquivo prova, para CADA adapter, com `Response` REAL (não objeto
 * simples), que os códigos públicos são preservados e que corpo vazio, JSON
 * inválido ou corpo fora do contrato continuam **fail-closed**.
 *
 * Todos os identificadores são sintéticos.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";
const OPERACAO = "66666666-6666-4666-8666-666666666666";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";

interface ErroPublico {
  readonly code: string;
  readonly message: string;
}
interface Resultado {
  readonly ok: boolean;
  readonly error?: ErroPublico;
  readonly data?: unknown;
}
interface RespostaFalsa {
  readonly data?: unknown;
  readonly error?: unknown;
}

/** Cliente falso: `functions.invoke` devolve exatamente a resposta pedida. */
function clienteFalso(resposta: RespostaFalsa): SupabaseClient {
  return {
    functions: {
      invoke: async () => ({ data: resposta.data ?? null, error: resposta.error ?? null }),
    },
  } as unknown as SupabaseClient;
}

/** Corpo de erro REAL, como a Edge o devolve (status + `{ error: {...} }`). */
function corpoErroHttp(codigo: string, mensagem: string, status: number): Response {
  return new Response(JSON.stringify({ error: { code: codigo, message: mensagem } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface Adaptador {
  readonly nome: string;
  /** Mensagem pública padrão quando o corpo não é legível. */
  readonly mensagemPadrao: string;
  /** Código de fallback PRÓPRIO do adapter (fail-closed pré-existente). */
  readonly codigoPadrao: string;
  /** Chamada cujo caminho é o tratamento de erro/2xx de `invoke`. */
  readonly chamar: (resposta: RespostaFalsa) => Promise<Resultado>;
}

const ADAPTADORES: readonly Adaptador[] = [
  {
    nome: "metas (edgeMetas)",
    mensagemPadrao: "Operação de meta recusada.",
    codigoPadrao: "FORBIDDEN",
    chamar: (resposta) =>
      criarEdgeMetas(clienteFalso(resposta)).criar({
        organizationId: ORG,
        cycleId: CICLO,
        collaboratorId: COLABORADOR,
        tipo: "INDIVIDUAL",
        descricao: "Meta sintetica",
        kpi: "KPI sintetico",
        valorAlvo: "100",
        operationId: OPERACAO,
      }),
  },
  {
    nome: "ciclos (edgeCiclos)",
    mensagemPadrao: "Operação de ciclo recusada.",
    codigoPadrao: "FORBIDDEN",
    chamar: (resposta) =>
      criarEdgeCiclos(clienteFalso(resposta)).criar({
        organizationId: ORG,
        ano: 2035,
        numero: 2,
        dataInicio: "2035-04-01",
        dataFim: "2035-06-30",
        operationId: OPERACAO,
      }),
  },
  {
    nome: "colaboradores (repositorioColaboradores)",
    mensagemPadrao: "Operação de colaborador recusada.",
    codigoPadrao: "INTERNAL",
    chamar: (resposta) =>
      criarRepositorioColaboradoresSupabase(clienteFalso(resposta)).criar({
        organizationId: ORG,
        operationId: OPERACAO,
        fullName: "Pessoa Sintetica",
        email: "pessoa.sintetica@example.test",
        matricula: "0001",
      }),
  },
  {
    nome: "avaliações (repositorioAvaliacoes)",
    mensagemPadrao: "Operação de avaliação recusada.",
    codigoPadrao: "INTERNAL",
    chamar: (resposta) =>
      criarRepositorioAvaliacoesSupabase(clienteFalso(resposta)).criar({
        organizationId: ORG,
        cycleId: CICLO,
        evaluatedCollaboratorId: COLABORADOR,
      }),
  },
];

/** Erro de transporte como o runtime o entrega: com `context` (Response). */
function erroCom(contexto: unknown): RespostaFalsa {
  return {
    error: { message: "Edge Function returned a non-2xx status code", context: contexto },
  };
}

const CASOS_DE_CODIGO: readonly {
  readonly nome: string;
  readonly codigo: string;
  readonly mensagem: string;
  readonly status: number;
}[] = [
  { nome: "CONFLICT (409)", codigo: "CONFLICT", mensagem: "expected_version divergente", status: 409 },
  { nome: "NOT_FOUND (404)", codigo: "NOT_FOUND", mensagem: "Registro não encontrado.", status: 404 },
  { nome: "FORBIDDEN (403)", codigo: "FORBIDDEN", mensagem: "Sem permissão.", status: 403 },
  { nome: "INVALID_INPUT (400)", codigo: "INVALID_INPUT", mensagem: "Dados inválidos.", status: 400 },
  { nome: "NOT_AUTHORIZED (401)", codigo: "NOT_AUTHORIZED", mensagem: "Não autorizado.", status: 401 },
];

const CASOS_FAIL_CLOSED: readonly { readonly nome: string; readonly resposta: RespostaFalsa }[] = [
  { nome: "JSON inválido", resposta: erroCom(new Response("<<<nao-e-json", { status: 500 })) },
  { nome: "body vazio", resposta: erroCom(new Response("", { status: 500 })) },
  {
    nome: "corpo válido fora do contrato",
    resposta: erroCom(new Response('{"foo":1}', { status: 409 })),
  },
  {
    nome: "envelope sem código nem mensagem",
    resposta: erroCom(new Response('{"error":{}}', { status: 500 })),
  },
  { nome: "erro sem `context`", resposta: { error: { message: "falha de transporte" } } },
  { nome: "`context` sem corpo de erro", resposta: erroCom({ status: 500 }) },
];

describe("F5-10 P5.1 (Issue #221) — códigos públicos preservados (Response REAL)", () => {
  for (const adaptador of ADAPTADORES) {
    for (const caso of CASOS_DE_CODIGO) {
      it(`${adaptador.nome}: ${caso.nome} chega ao chamador`, async () => {
        const resultado = await adaptador.chamar(
          erroCom(corpoErroHttp(caso.codigo, caso.mensagem, caso.status))
        );
        expect(resultado.ok).toBe(false);
        expect(resultado.error).toEqual({ code: caso.codigo, message: caso.mensagem });
      });
    }
  }
});

describe("F5-10 P5.1 (Issue #221) — fail-closed quando o corpo não é legível", () => {
  for (const adaptador of ADAPTADORES) {
    for (const caso of CASOS_FAIL_CLOSED) {
      it(`${adaptador.nome}: ${caso.nome} ⇒ código de fallback do adapter com a mensagem padrão`, async () => {
        const resultado = await adaptador.chamar(caso.resposta);
        expect(resultado.ok).toBe(false);
        expect(resultado.error).toEqual({
          code: adaptador.codigoPadrao,
          message: adaptador.mensagemPadrao,
        });
      });
    }
  }
});

describe("F5-10 P5.1 (Issue #221) — o caminho 2xx não regride", () => {
  it("metas: 2xx dentro do contrato continua sucesso", async () => {
    const resultado = await ADAPTADORES[0]!.chamar({
      data: { ok: true, resultado: { goal_id: COLABORADOR, version: 1, status: "EM_ANDAMENTO" } },
    });
    expect(resultado).toEqual({
      ok: true,
      data: { goal_id: COLABORADOR, version: 1, status: "EM_ANDAMENTO" },
    });
  });

  it("ciclos: 2xx dentro do contrato continua sucesso", async () => {
    const resultado = await ADAPTADORES[1]!.chamar({ data: { ok: true, resultado: { version: 0 } } });
    expect(resultado).toEqual({ ok: true, data: { version: 0 } });
  });

  it("colaboradores: 2xx dentro do contrato continua sucesso", async () => {
    const resultado = await ADAPTADORES[2]!.chamar({
      data: { ok: true, resultado: "colaborador-sintetico" },
    });
    expect(resultado).toEqual({ ok: true, data: "colaborador-sintetico" });
  });

  it("avaliações: 2xx dentro do contrato continua sucesso", async () => {
    const resultado = await ADAPTADORES[3]!.chamar({ data: { ok: true, resultado: CICLO } });
    expect(resultado).toEqual({ ok: true, data: CICLO });
  });

  it("2xx com `error` no corpo (fora do contrato) NÃO é sucesso presumido", async () => {
    for (const adaptador of ADAPTADORES) {
      const resultado = await adaptador.chamar({
        data: { error: { code: "CONFLICT", message: "conflito no corpo 2xx" } },
      });
      expect(resultado.ok, adaptador.nome).toBe(false);
      expect(resultado.error, adaptador.nome).toEqual({
        code: "CONFLICT",
        message: "conflito no corpo 2xx",
      });
    }
  });
});
