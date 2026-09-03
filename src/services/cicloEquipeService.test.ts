import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import {
  analisarPendenciasDoCiclo,
  concluirAvaliacoesNoEncerramentoDoCiclo,
  criarAvaliacoesDoCicloAtivado,
  excluirAvaliacoesVaziasDoCiclo,
  getPainelCiclo,
} from "./cicloEquipeService";

const gerente: Colaborador = {
  matricula: 1,
  status: "ATIVO",
  nome: "Gerente Fictício",
  email: "gerente@example.com",
  cargo: "Gerente",
  area: "Área fictícia",
  funcao: "GERENTE",
  respondePara: "",
};
const avaliado: Colaborador = {
  matricula: 2,
  status: "ATIVO",
  nome: "Pessoa Avaliada",
  email: "avaliado@example.com",
  cargo: "Consultor",
  area: "Área fictícia",
  funcao: "CONSULTOR",
  gestorDiretoMatricula: gerente.matricula,
  respondePara: gerente.nome,
};
const ciclo: CicloAvaliacao = {
  id: "ciclo-cancelada",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};
const cancelada: Feedback = {
  id: "avaliacao-cancelada",
  colaboradorId: avaliado.matricula,
  colaboradorNome: avaliado.nome,
  status: "CANCELADA",
  data: "2026-01-10T00:00:00.000Z",
  ano: 2026,
  ciclo: 1,
  notaMedia: 0,
  competencias: [],
  criteriosDetalhados: [
    {
      criterioId: "criterio",
      criterioNome: "Critério",
      nota: 0,
      observacaoGerente: "",
      observacaoCoordenador: "",
      subcriterios: [
        {
          nome: "Subcritério",
          notaGerente: 0,
          notaCoordenador: 0,
          notaColegiado: 0,
          notaFinal: 0,
        },
      ],
    },
  ],
};

describe("cicloEquipeService com avaliação cancelada", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      "feedback-control-colaboradores",
      JSON.stringify([gerente, avaliado])
    );
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([ciclo]));
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify([cancelada]));
  });

  it("oculta no painel por padrão e inclui com status explícito", () => {
    expect(getPainelCiclo(ciclo, gerente)).toEqual([]);

    const linhas = getPainelCiclo(ciclo, gerente, { incluirCanceladas: true });
    expect(linhas).toHaveLength(1);
    expect(linhas[0].situacao).toBe("CANCELADA");
    expect(linhas[0].possuiPendencias).toBe(false);
  });

  it("não gera pendência de encerramento", () => {
    expect(analisarPendenciasDoCiclo(ciclo)).toEqual([]);

    concluirAvaliacoesNoEncerramentoDoCiclo(ciclo, []);

    expect(
      JSON.parse(localStorage.getItem("feedback-control-feedbacks") ?? "[]")[0]
        .status
    ).toBe("CANCELADA");
  });

  it("não gera pendências para ciclo cancelado", () => {
    const cicloCancelado = { ...ciclo, status: "CANCELADO" as const };
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([cicloCancelado])
    );

    expect(analisarPendenciasDoCiclo(cicloCancelado)).toEqual([]);
  });

  it("gera avaliação automática nova e vazia quando só existe cancelada", () => {
    const resultado = criarAvaliacoesDoCicloAtivado(ciclo);

    expect(resultado.criadas).toBeGreaterThan(0);
    expect(resultado.existentes).toBe(0);
    const persistidas = JSON.parse(
      localStorage.getItem("feedback-control-feedbacks") ?? "[]"
    ) as Feedback[];
    const doAvaliado = persistidas.filter(
      (feedback) => feedback.colaboradorId === avaliado.matricula
    );
    expect(doAvaliado).toHaveLength(2);
    expect(doAvaliado[0]).toEqual(cancelada);
    expect(doAvaliado[1].id).not.toBe(cancelada.id);
    expect(doAvaliado[1].status).toBe("RASCUNHO");
    expect(doAvaliado[1].notaMedia).toBe(0);
    expect(doAvaliado[1].feedbackFinalGerente).toBe("");
    expect(doAvaliado[1].feedbackFinalCoordenador).toBe("");
    expect(doAvaliado[1]).not.toHaveProperty("motivoCancelamento");
  });

  it("mantém a avaliação não cancelada como existente na geração automática", () => {
    localStorage.setItem(
      "feedback-control-feedbacks",
      JSON.stringify([{ ...cancelada, id: "avaliacao-ativa", status: "RASCUNHO" }])
    );

    const resultado = criarAvaliacoesDoCicloAtivado(ciclo);
    expect(resultado.existentes).toBe(1);
    const persistidas = JSON.parse(
      localStorage.getItem("feedback-control-feedbacks") ?? "[]"
    ) as Feedback[];
    expect(
      persistidas.filter((feedback) => feedback.colaboradorId === avaliado.matricula)
    ).toHaveLength(1);
  });
});

describe("cleanup seguro na exclusão de ciclo", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      "feedback-control-colaboradores",
      JSON.stringify([gerente, avaliado])
    );
  });

  it.each(["ATIVO", "ENCERRADO"] as const)(
    "rejeita ciclo %s antes de remover avaliações relacionadas",
    (status) => {
      const cicloProtegido = { ...ciclo, status };
      const feedbackRelacionado = { ...cancelada, status: "RASCUNHO" as const };
      localStorage.setItem(
        "feedback-control-ciclos",
        JSON.stringify([cicloProtegido])
      );
      localStorage.setItem(
        "feedback-control-feedbacks",
        JSON.stringify([feedbackRelacionado])
      );

      expect(() => excluirAvaliacoesVaziasDoCiclo(cicloProtegido)).toThrow(
        "Somente ciclos planejados podem ser excluídos fisicamente."
      );
      expect(
        JSON.parse(localStorage.getItem("feedback-control-ciclos") ?? "[]")
      ).toEqual([cicloProtegido]);
      expect(
        JSON.parse(localStorage.getItem("feedback-control-feedbacks") ?? "[]")
      ).toEqual([feedbackRelacionado]);
    }
  );

  it("rejeita ciclo planejado com avaliação preenchida e preserva tudo", () => {
    const cicloPlanejado = { ...ciclo, status: "PLANEJADO" as const };
    const preenchida = {
      ...cancelada,
      status: "RASCUNHO" as const,
      feedbackFinalGerente: "Conteúdo operacional",
    };
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([cicloPlanejado]));
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify([preenchida]));

    expect(() => excluirAvaliacoesVaziasDoCiclo(cicloPlanejado)).toThrow(
      "dados preenchidos"
    );
    expect(
      JSON.parse(localStorage.getItem("feedback-control-ciclos") ?? "[]")
    ).toEqual([cicloPlanejado]);
    expect(
      JSON.parse(localStorage.getItem("feedback-control-feedbacks") ?? "[]")
    ).toEqual([preenchida]);
  });

  it("remove somente avaliação realmente vazia de ciclo planejado", () => {
    const cicloPlanejado = { ...ciclo, status: "PLANEJADO" as const };
    const vazia = { ...cancelada, status: "RASCUNHO" as const };
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([cicloPlanejado]));
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify([vazia]));

    expect(excluirAvaliacoesVaziasDoCiclo(cicloPlanejado)).toEqual({
      excluidas: 1,
      bloqueadas: 0,
    });
    expect(
      JSON.parse(localStorage.getItem("feedback-control-feedbacks") ?? "[]")
    ).toEqual([]);
  });
});
