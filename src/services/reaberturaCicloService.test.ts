import { beforeEach, describe, expect, it, vi } from "vitest";
import { AuthorizationError } from "../authorization/authorizationError";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import type { Observacao } from "../types/Observacao";
import {
  atualizarStatusCiclo,
  encerrarCiclo,
  getCiclosAvaliacao,
} from "./cicloAvaliacaoStorage";
import {
  ERRO_ESCRITA_LOCAL_OBSERVACOES,
  atualizarObservacao,
  criarObservacao,
  excluirObservacao,
} from "./observacaoStorage";
import { reabrirCiclo } from "./reaberturaCicloService";

/**
 * F5-10 P6: o módulo legado de metas foi eliminado do caminho funcional. A
 * chave só sobrevive aqui como MARCADOR PROIBIDO: serve para provar que o fluxo
 * de reabertura não lê nem grava o registro local legado de metas.
 */
const CHAVE_METAS_LEGADA = "feedback-control-metas";

const gerente: Colaborador = { matricula: 1, status: "ATIVO", nome: "Gerente Fictício", email: "gerente@example.com", cargo: "Gerente", area: "Área fictícia", funcao: "GERENTE", respondePara: "" };
const coordenador: Colaborador = { ...gerente, matricula: 2, nome: "Coordenador Fictício", email: "coordenador@example.com", funcao: "COORDENADOR", gestorDiretoMatricula: gerente.matricula };
const encerrado: CicloAvaliacao = {
  id: "ciclo-encerrado", ano: 2026, ciclo: 1, status: "ENCERRADO",
  dataInicio: "2026-01-01", dataFim: "2026-06-30",
  quantidadeMetasNegocio: 1, quantidadeMetasIndividuais: 1,
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-06-30T10:00:00.000Z",
  dataAtivacao: "2026-01-01T10:00:00.000Z",
  dataEncerramento: "2026-06-30T10:00:00.000Z",
  encerradoComPendencias: true,
  quantidadePendencias: 2,
};

function persistirCiclos(...ciclos: CicloAvaliacao[]) {
  localStorage.setItem("feedback-control-ciclos", JSON.stringify(ciclos));
}

describe("reabrirCiclo", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    persistirCiclos(encerrado);
  });

  it("permite gerente reabrir encerrado com auditoria e preserva o encerramento", () => {
    const reaberto = reabrirCiclo(encerrado.id, "  Ajuste excepcional  ", gerente);
    expect(reaberto).toMatchObject({
      status: "ATIVO",
      dataEncerramento: encerrado.dataEncerramento,
      encerradoComPendencias: true,
      quantidadePendencias: 2,
      encerramentos: [{
        data: encerrado.dataEncerramento,
        encerradoComPendencias: true,
        quantidadePendencias: 2,
      }],
      reaberturas: [{
        motivo: "Ajuste excepcional",
        autorMatricula: gerente.matricula,
        autorNome: gerente.nome,
        data: expect.any(String),
      }],
    });
    expect(Number.isNaN(Date.parse(reaberto.reaberturas![0].data))).toBe(false);
  });

  it("rejeita não gerente, motivo vazio e estados inelegíveis sem alteração", () => {
    expect(() => reabrirCiclo(encerrado.id, "Motivo", coordenador)).toThrow(AuthorizationError);
    expect(() => reabrirCiclo(encerrado.id, "   ", gerente)).toThrow("Informe o motivo da reabertura do ciclo.");
    expect(getCiclosAvaliacao()).toEqual([encerrado]);

    for (const status of ["PLANEJADO", "ATIVO", "CANCELADO"] as const) {
      const ciclo = { ...encerrado, status };
      persistirCiclos(ciclo);
      expect(() => reabrirCiclo(ciclo.id, "Motivo", gerente)).toThrow(AuthorizationError);
      expect(getCiclosAvaliacao()).toEqual([ciclo]);
    }
  });

  it("rejeita quando há outro ciclo ativo antes de modificar qualquer dado", () => {
    const ativo = { ...encerrado, id: "outro-ativo", ciclo: 2 as const, status: "ATIVO" as const };
    persistirCiclos(encerrado, ativo);
    const antes = localStorage.getItem("feedback-control-ciclos");
    expect(() => reabrirCiclo(encerrado.id, "Motivo", gerente)).toThrow("Já existe um ciclo ativo");
    expect(localStorage.getItem("feedback-control-ciclos")).toBe(antes);
  });

  it("preserva múltiplos encerramentos e reaberturas", () => {
    reabrirCiclo(encerrado.id, "Primeira reabertura", gerente);
    encerrarCiclo(encerrado.id, 0);
    reabrirCiclo(encerrado.id, "Segunda reabertura", gerente);
    const ciclo = getCiclosAvaliacao()[0];
    expect(ciclo.reaberturas?.map((evento) => evento.motivo)).toEqual([
      "Primeira reabertura", "Segunda reabertura",
    ]);
    expect(ciclo.encerramentos).toHaveLength(2);
    expect(ciclo.encerramentos?.[0]).toMatchObject({
      data: encerrado.dataEncerramento,
      encerradoComPendencias: true,
      quantidadePendencias: 2,
    });
  });

  it("não altera avaliações, preserva observações e nunca toca o registro legado de metas", () => {
    const feedback: Feedback = {
      id: "avaliacao", colaboradorId: 3, colaboradorNome: "Pessoa Avaliada",
      status: "CONCLUIDA", data: "2026-01-01", ano: 2026, ciclo: 1,
      competencias: [], notaMedia: 3, encerradaComPendencias: true,
      pendenciasEncerramento: ["Gerente: 1 nota pendente"],
    };
    const observacao: Observacao = {
      id: "observacao", colaboradorMatricula: 3, tipo: "NEUTRA", texto: "Preservada",
      comunicado: false, ano: 2026, ciclo: 1, autorMatricula: 1, autorNome: gerente.nome,
      dataCriacao: "2026-01-01", dataUltimaAtualizacao: "2026-01-01", excluida: false, historico: [],
    };
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify([feedback]));
    localStorage.setItem("feedback-control-observacoes", JSON.stringify([observacao]));

    const gravar = vi.spyOn(localStorage, "setItem");
    const ler = vi.spyOn(localStorage, "getItem");

    const reaberto = reabrirCiclo(encerrado.id, "Retomar ciclo", gerente);
    expect(reaberto.status).toBe("ATIVO");
    expect(JSON.parse(localStorage.getItem("feedback-control-feedbacks")!)).toEqual([feedback]);
    expect(JSON.parse(localStorage.getItem("feedback-control-observacoes")!)).toEqual([observacao]);

    // Prova metas-free: a reabertura não LÊ nem GRAVA o registro local legado.
    const gravouRegistroLegado = gravar.mock.calls.some(
      ([chave]) => chave === CHAVE_METAS_LEGADA
    );
    const leuRegistroLegado = ler.mock.calls.some(
      ([chave]) => chave === CHAVE_METAS_LEGADA
    );
    expect(gravouRegistroLegado).toBe(false);
    expect(leuRegistroLegado).toBe(false);

    // F5-11 P5 (Issue #250): o acervo local de observações está sob barreira D13
    // — a escrita local é PROIBIDA e a reabertura não muda isso (a autoridade é a
    // porta soberana). Nenhuma das três mutações grava: o acervo fica intacto.
    expect(() =>
      atualizarObservacao(
        observacao.id,
        "POSITIVA",
        "Atualizada após reabertura",
        true,
        2026,
        1,
        gerente
      )
    ).toThrow(ERRO_ESCRITA_LOCAL_OBSERVACOES);
    expect(() => excluirObservacao(observacao.id, gerente)).toThrow(
      ERRO_ESCRITA_LOCAL_OBSERVACOES
    );
    expect(() =>
      criarObservacao(3, "POSITIVA", "Nova observação", false, 2026, 1, gerente)
    ).toThrow(ERRO_ESCRITA_LOCAL_OBSERVACOES);
    expect(JSON.parse(localStorage.getItem("feedback-control-feedbacks")!)[0]).toEqual(feedback);
    expect(localStorage.getItem(CHAVE_METAS_LEGADA)).toBeNull();
    expect(
      JSON.parse(localStorage.getItem("feedback-control-observacoes")!)
    ).toEqual([observacao]);
  });

  it("mantém regressão bloqueada pela atualização genérica", () => {
    expect(() => atualizarStatusCiclo(encerrado.id, "ATIVO")).toThrow("Transição de ciclo inválida");
    expect(getCiclosAvaliacao()).toEqual([encerrado]);
  });
});
