import { describe, expect, it } from "vitest";

import fonteFluxo from "./fluxoMutacaoObservacao.ts?raw";
import type { ResultadoObservacoesUi, ControladorObservacoes } from "./controladorObservacoes";
import {
  criarObservacaoSoberana,
  editarObservacaoSoberana,
  excluirObservacaoSoberana,
  mensagemDaFalha,
} from "./fluxoMutacaoObservacao";

/**
 * F5-11 P5 (Issue #250), L3 — FLUXO de mutação do painel: a tela só delega ao
 * controlador soberano. Discriminantes:
 * - SEM ciclo soberano a criação é recusada ANTES da fronteira (nunca se inventa
 *   `cycle_id` — D2);
 * - SEM motivo a exclusão é recusada ANTES da fronteira (D8/D16);
 * - a negação do servidor atravessa como código público + mensagem, sem estado
 *   otimista e sem fallback local;
 * - a EDIÇÃO usa a definição COMPLETA (tipo/texto/comunicado) e o alvo por UUID.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "22222222-2222-4222-8222-222222222222";
const OBS = "33333333-3333-4333-8333-333333333333";
const ALVO = "44444444-4444-4444-8444-444444444444";

interface Chamada {
  readonly metodo: string;
  readonly corpo: Record<string, unknown>;
}

function controladorEspiao(
  chamadas: Chamada[],
  resposta: ResultadoObservacoesUi<unknown>
): ControladorObservacoes {
  const registrar =
    (metodo: string) =>
    (entrada: object): Promise<ResultadoObservacoesUi<unknown>> => {
      chamadas.push({ metodo, corpo: { ...entrada } as Record<string, unknown> });
      return Promise.resolve(resposta);
    };

  return {
    listarPorEscopo: registrar("listarPorEscopo"),
    obter: registrar("obter"),
    historico: registrar("historico"),
    criar: registrar("criar"),
    editar: registrar("editar"),
    definirComunicado: registrar("definirComunicado"),
    excluir: registrar("excluir"),
    revogar: registrar("revogar"),
  } as unknown as ControladorObservacoes;
}

// Tipos REAIS do controlador: `error.code` é a união FECHADA `CodigoPublico`
// (`FalhaObservacoesUi`) — a anotação explícita evita `string` genérico, sem
// `any` e sem cast permissivo.
const SUCESSO: ResultadoObservacoesUi<unknown> = {
  ok: true,
  data: { observacaoId: OBS, version: 4 },
};
const NEGADO: ResultadoObservacoesUi<unknown> = {
  ok: false,
  error: { code: "FORBIDDEN", mensagem: "Você não tem permissão para esta operação." },
};

describe("F5-11 P5 L3 — fluxo de mutação soberano do painel", () => {
  it("criar transporta SOMENTE intenção (org, ciclo, alvo, tipo, texto)", async () => {
    const chamadas: Chamada[] = [];
    const resultado = await criarObservacaoSoberana(
      { controlador: controladorEspiao(chamadas, SUCESSO), organizationId: ORG, collaboratorId: ALVO, cycleId: CICLO },
      { tipo: "POSITIVA", texto: "observacao ficticia" }
    );

    expect(resultado.ok).toBe(true);
    expect(chamadas.map((c) => c.metodo)).toEqual(["criar"]);
    expect(Object.keys(chamadas[0].corpo).sort()).toEqual([
      "collaboratorId",
      "cycleId",
      "organizationId",
      "texto",
      "tipo",
    ]);
    for (const proibida of ["expectedVersion", "autor", "status", "comunicado", "data"]) {
      expect(chamadas[0].corpo).not.toHaveProperty(proibida);
    }
  });

  it("SEM ciclo soberano a criação é recusada ANTES da fronteira (nada de ciclo inventado)", async () => {
    const chamadas: Chamada[] = [];
    const resultado = await criarObservacaoSoberana(
      { controlador: controladorEspiao(chamadas, SUCESSO), organizationId: ORG, collaboratorId: ALVO },
      { tipo: "POSITIVA", texto: "observacao ficticia" }
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) throw new Error("esperado recusa");
    expect(resultado.error.code).toBe("INVALID_INPUT");
    expect(resultado.error.mensagem).toBe("Selecione o ciclo da observação.");
    expect(chamadas).toEqual([]);
  });

  it("editar usa a definição COMPLETA e o alvo por UUID", async () => {
    const chamadas: Chamada[] = [];
    const resultado = await editarObservacaoSoberana(
      { controlador: controladorEspiao(chamadas, SUCESSO), organizationId: ORG, collaboratorId: ALVO },
      { id: OBS },
      { tipo: "NEGATIVA", texto: "texto novo ficticio", comunicado: true }
    );

    expect(resultado.ok).toBe(true);
    expect(chamadas.map((c) => c.metodo)).toEqual(["editar"]);
    expect(chamadas[0].corpo).toEqual({
      organizationId: ORG,
      observationId: OBS,
      tipo: "NEGATIVA",
      texto: "texto novo ficticio",
      comunicado: true,
    });
    // A versão esperada NÃO é transportada pelo painel: ela vem da LEITURA
    // soberana dentro do controlador (D10).
    expect(chamadas[0].corpo).not.toHaveProperty("expectedVersion");
  });

  it("SEM motivo a exclusão é recusada ANTES da fronteira (D8/D16)", async () => {
    const chamadas: Chamada[] = [];
    const resultado = await excluirObservacaoSoberana(
      { controlador: controladorEspiao(chamadas, SUCESSO), organizationId: ORG, collaboratorId: ALVO },
      { id: OBS },
      "   "
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) throw new Error("esperado recusa");
    expect(resultado.error.code).toBe("INVALID_INPUT");
    expect(chamadas).toEqual([]);
  });

  it("excluir envia o motivo normalizado e o alvo, sem versão do browser", async () => {
    const chamadas: Chamada[] = [];
    const resultado = await excluirObservacaoSoberana(
      { controlador: controladorEspiao(chamadas, SUCESSO), organizationId: ORG, collaboratorId: ALVO },
      { id: OBS },
      "  motivo ficticio  "
    );

    expect(resultado.ok).toBe(true);
    expect(chamadas[0].corpo).toEqual({
      organizationId: ORG,
      observationId: OBS,
      motivo: "motivo ficticio",
    });
  });

  it("negação do servidor atravessa como falha pública (fail-closed, sem fallback)", async () => {
    const chamadas: Chamada[] = [];
    const resultado = await criarObservacaoSoberana(
      {
        controlador: controladorEspiao(chamadas, NEGADO),
        organizationId: ORG,
        collaboratorId: ALVO,
        cycleId: CICLO,
      },
      { tipo: "POSITIVA", texto: "tentativa ficticia negada" }
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) throw new Error("esperado negativa");
    expect(mensagemDaFalha(resultado.error)).toBe(
      "FORBIDDEN: Você não tem permissão para esta operação."
    );
  });

  it("o FONTE do fluxo não decide autorização nem fala storage/RPC", () => {
    expect(fonteFluxo).not.toMatch(/localStorage|sessionStorage/);
    expect(fonteFluxo).not.toMatch(/observacaoStorage/);
    expect(fonteFluxo).not.toMatch(/\.rpc\s*\(/);
    expect(fonteFluxo).not.toMatch(/SERVICE_ROLE_KEY|serviceRoleKey/);
    expect(fonteFluxo).not.toMatch(/authorizationPolicy|\bcan\s*\(|\bauthorize\s*\(/);
  });
});
