/**
 * F5-11 P5 (Issue #250), L4 — guardas do cutover das OBSERVAÇÕES do colaborador.
 *
 * Este arquivo (que antes cobria apenas o status administrativo da avaliação)
 * passa a concentrar duas provas do L4:
 *
 * 1. **Derivação SOBERANA** usada pela tela do gestor:
 *    `observacoesDoAlvo` recorta por UUID `collaborator_id` (identidade), conta
 *    por tipo (KPI) e resolve o rótulo do AUTOR somente a partir dos
 *    colaboradores já carregados — sem inventar identidade;
 * 2. **Barreira ESTÁTICA** no fonte da página (`?raw`): a tela não pode voltar a
 *    ler o acervo local (`observacaoStorage`/`localStorage`/`sessionStorage`),
 *    não chama RPC do banco (`.rpc(`) e não carrega credencial privilegiada (a
 *    leitura passa pela porta soberana, que atravessa a Edge).
 *
 * As asserções originais do status administrativo da avaliação permanecem
 * intactas no fim do arquivo.
 */

import { describe, expect, it } from "vitest";
import type { ObservacaoSoberana } from "../application/ports/ObservationRepository";
import type { Feedback } from "../types/Feedback";
import ColaboradorDetalhePageFonte from "./ColaboradorDetalhePage.tsx?raw";
import {
  AUTOR_NAO_IDENTIFICADO,
  formatarDataDaObservacao,
  observacoesDoAlvo,
  resumoDeObservacoesPorTipo,
  rotuloDoTipo,
} from "./observacoesSoberanasDaPagina";
import { getStatusAvaliacaoAdministrativa } from "./statusAvaliacaoAdministrativa";

const ALVO = "11111111-1111-4111-8111-111111111111";
const OUTRO_ALVO = "22222222-2222-4222-8222-222222222222";
const AUTOR = "33333333-3333-4333-8333-333333333333";
const AUTOR_SEM_ROTULO = "44444444-4444-4444-8444-444444444444";

function observacaoSoberana(
  parcial: Partial<ObservacaoSoberana> = {}
): ObservacaoSoberana {
  return {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    organizationId: "55555555-5555-4555-8555-555555555555",
    collaboratorId: ALVO,
    cycleId: "66666666-6666-4666-8666-666666666666",
    tipo: "POSITIVA",
    texto: "Observação fictícia",
    comunicado: true,
    comunicadoEm: "2026-03-02T12:00:00.000Z",
    excluida: false,
    motivoExclusao: null,
    autorUserProfileId: "77777777-7777-4777-8777-777777777777",
    autorCollaboratorId: AUTOR,
    version: 2,
    criadoEm: "2026-03-01T12:00:00.000Z",
    atualizadoEm: "2026-03-02T12:00:00.000Z",
    ...parcial,
  };
}

describe("F5-11 P5 (L4) — observações do alvo na projeção soberana", () => {
  it("recorta por UUID do ALVO (identidade), nunca por matrícula/ano/ciclo", () => {
    const lista = [
      observacaoSoberana({ id: "a", texto: "Do alvo" }),
      observacaoSoberana({
        id: "b",
        collaboratorId: OUTRO_ALVO,
        texto: "De outro colaborador",
      }),
    ];

    const doAlvo = observacoesDoAlvo(lista, ALVO, {});

    expect(doAlvo.map((item) => item.id)).toEqual(["a"]);
    expect(doAlvo[0].texto).toBe("Do alvo");
  });

  it("sem alvo resolvido não apresenta observação alguma (fail-closed)", () => {
    expect(observacoesDoAlvo([observacaoSoberana()], null, {})).toEqual([]);
  });

  it("conta o KPI por tipo sobre o recorte do alvo", () => {
    const lista = [
      observacaoSoberana({ id: "a", tipo: "POSITIVA" }),
      observacaoSoberana({ id: "b", tipo: "NEUTRA" }),
      observacaoSoberana({ id: "c", tipo: "NEGATIVA" }),
      observacaoSoberana({ id: "d", tipo: "NEGATIVA" }),
      observacaoSoberana({
        id: "e",
        tipo: "NEGATIVA",
        collaboratorId: OUTRO_ALVO,
      }),
    ];

    expect(resumoDeObservacoesPorTipo(observacoesDoAlvo(lista, ALVO, {}))).toEqual({
      positivas: 1,
      neutras: 1,
      negativas: 2,
    });
  });

  it("resolve o rótulo do autor pelos colaboradores JÁ carregados", () => {
    const doAlvo = observacoesDoAlvo([observacaoSoberana()], ALVO, {
      [AUTOR]: "Gestor Fictício",
    });

    expect(doAlvo[0].autorNome).toBe("Gestor Fictício");
  });

  it("autor fora dos colaboradores carregados não vira UUID nem nome inventado", () => {
    const semRotulo = observacoesDoAlvo(
      [observacaoSoberana({ autorCollaboratorId: AUTOR_SEM_ROTULO })],
      ALVO,
      { [AUTOR]: "Gestor Fictício" }
    );
    const semAutorNaLinha = observacoesDoAlvo(
      [observacaoSoberana({ autorCollaboratorId: null })],
      ALVO,
      { [AUTOR]: "Gestor Fictício" }
    );

    expect(semRotulo[0].autorNome).toBeNull();
    expect(semRotulo[0].autorNome).not.toBe(AUTOR_SEM_ROTULO);
    expect(semAutorNaLinha[0].autorNome).toBeNull();
    expect(AUTOR_NAO_IDENTIFICADO).toContain("não identificado");
  });

  it("apresenta tipo e data soberanos sem derivar ciclo legado", () => {
    expect(rotuloDoTipo("POSITIVA")).toBe("Positiva");
    expect(rotuloDoTipo("NEUTRA")).toBe("Neutra");
    expect(rotuloDoTipo("NEGATIVA")).toBe("Negativa");
    expect(formatarDataDaObservacao("2026-03-01T12:00:00.000Z")).toBe("01/03/2026");
    expect(formatarDataDaObservacao("data-inválida")).toBe("—");
  });
});

describe("F5-11 P5 (L4) — barreira estática no fonte da página", () => {
  it("o fonte é varrido como string (prova não-vacuamente verde)", () => {
    expect(ColaboradorDetalhePageFonte).toBeTypeOf("string");
    expect(ColaboradorDetalhePageFonte).toContain("ColaboradorDetalhePageProps");
  });

  it("a tela lê as observações pela porta soberana", () => {
    expect(ColaboradorDetalhePageFonte).toContain(
      "obterRepositorioObservacoesSoberanas"
    );
    expect(ColaboradorDetalhePageFonte).toContain("listarObservacoesPorEscopo");
    // O escopo é INTENÇÃO de gestão; a decisão é server-side.
    expect(ColaboradorDetalhePageFonte).toContain('"DESCENDANTS"');
  });

  it("a tela não volta ao acervo local nem à RPC direta", () => {
    for (const proibido of [
      "observacaoStorage",
      "localStorage",
      "sessionStorage",
      ".rpc(",
      "service_role",
      "SERVICE_ROLE",
    ]) {
      expect(ColaboradorDetalhePageFonte, proibido).not.toContain(proibido);
    }
  });

  it("a tela não usa `any` na projeção soberana apresentada", () => {
    expect(ColaboradorDetalhePageFonte).not.toMatch(/:\s*any\b/);
    expect(ColaboradorDetalhePageFonte).not.toMatch(/as\s+any\b/);
  });
});

describe("status administrativo da avaliação", () => {
  it("prioriza o contexto de ciclo cancelado sem alterar o status persistido", () => {
    const feedback = { status: "RASCUNHO" } as Feedback;
    expect(getStatusAvaliacaoAdministrativa(feedback.status, "CANCELADO")).toEqual({
      label: "Cancelado",
      className: "is-historical",
    });
    expect(feedback.status).toBe("RASCUNHO");
  });

  it("apresenta rascunho de ciclo encerrado com o mesmo tratamento neutro", () => {
    const feedback = { status: "RASCUNHO" } as Feedback;
    expect(getStatusAvaliacaoAdministrativa(feedback.status, "ENCERRADO")).toEqual({
      label: "Encerrado",
      className: "is-historical",
    });
    expect(feedback.status).toBe("RASCUNHO");
  });
});
