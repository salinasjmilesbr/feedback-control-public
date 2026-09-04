import { beforeEach, describe, expect, it } from "vitest";
import { AuthorizationError } from "../authorization/authorizationError";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import type { Meta } from "../types/Meta";
import type { Observacao } from "../types/Observacao";
import {
  atualizarStatusCiclo,
  encerrarCiclo,
  getCiclosAvaliacao,
} from "./cicloAvaliacaoStorage";
import { atualizarAcompanhamentoMeta } from "./metaStorage";
import {
  atualizarObservacao,
  criarObservacao,
  excluirObservacao,
} from "./observacaoStorage";
import { reabrirCiclo } from "./reaberturaCicloService";

const gerente: Colaborador = { matricula: 1, status: "ATIVO", nome: "Gerente Fictício", email: "gerente@example.com", cargo: "Gerente", area: "Área fictícia", funcao: "GERENTE", respondePara: "" };
const coordenador: Colaborador = { ...gerente, matricula: 2, nome: "Coordenador Fictício", email: "coordenador@example.com", funcao: "COORDENADOR" };
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

  it("não altera avaliações e preserva metas e observações, que voltam ao fluxo ativo", () => {
    const feedback: Feedback = {
      id: "avaliacao", colaboradorId: 3, colaboradorNome: "Pessoa Avaliada",
      status: "CONCLUIDA", data: "2026-01-01", ano: 2026, ciclo: 1,
      competencias: [], notaMedia: 3, encerradaComPendencias: true,
      pendenciasEncerramento: ["Gerente: 1 nota pendente"],
    };
    const meta: Meta = {
      id: "meta", colaboradorMatricula: 3, colaboradorNome: "Pessoa Avaliada",
      cicloId: encerrado.id, ano: 2026, ciclo: 1, tipo: "INDIVIDUAL",
      descricao: "Meta preservada", kpi: "KPI", valorAlvo: "100",
      status: "EM_ANDAMENTO", aprovacaoGerente: { matricula: 1, nome: gerente.nome, data: "2026-01-01" },
      dataCriacao: "2026-01-01", dataUltimaAtualizacao: "2026-01-01", excluida: false,
      historico: [],
    };
    const observacao: Observacao = {
      id: "observacao", colaboradorMatricula: 3, tipo: "NEUTRA", texto: "Preservada",
      comunicado: false, ano: 2026, ciclo: 1, autorMatricula: 1, autorNome: gerente.nome,
      dataCriacao: "2026-01-01", dataUltimaAtualizacao: "2026-01-01", excluida: false, historico: [],
    };
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify([feedback]));
    localStorage.setItem("feedback-control-metas", JSON.stringify([meta]));
    localStorage.setItem("feedback-control-observacoes", JSON.stringify([observacao]));

    const reaberto = reabrirCiclo(encerrado.id, "Retomar ciclo", gerente);
    expect(JSON.parse(localStorage.getItem("feedback-control-feedbacks")!)).toEqual([feedback]);
    expect(JSON.parse(localStorage.getItem("feedback-control-metas")!)).toEqual([meta]);
    expect(JSON.parse(localStorage.getItem("feedback-control-observacoes")!)).toEqual([observacao]);

    const colaborador = { ...coordenador, matricula: 3, funcao: "ANALISTA" as const };
    atualizarAcompanhamentoMeta(meta.id, colaborador, reaberto, "Em evolução", 50);
    atualizarObservacao(
      observacao.id,
      "POSITIVA",
      "Atualizada após reabertura",
      true,
      2026,
      1,
      gerente
    );
    excluirObservacao(observacao.id, gerente);
    criarObservacao(3, "POSITIVA", "Nova observação", false, 2026, 1, gerente);
    expect(JSON.parse(localStorage.getItem("feedback-control-feedbacks")!)[0]).toEqual(feedback);
    expect(JSON.parse(localStorage.getItem("feedback-control-metas")!)[0]).toMatchObject({
      status: meta.status,
      aprovacaoGerente: meta.aprovacaoGerente,
      resultadoAtual: "Em evolução",
    });
    const observacoes = JSON.parse(
      localStorage.getItem("feedback-control-observacoes")!
    ) as Observacao[];
    expect(observacoes).toHaveLength(2);
    expect(observacoes[0]).toMatchObject({
      id: observacao.id,
      texto: "Atualizada após reabertura",
      excluida: true,
      dataCriacao: observacao.dataCriacao,
    });
    expect(observacoes[0].historico.map((evento) => evento.acao)).toEqual([
      "EDICAO",
      "EXCLUSAO",
    ]);
  });

  it("mantém regressão bloqueada pela atualização genérica", () => {
    expect(() => atualizarStatusCiclo(encerrado.id, "ATIVO")).toThrow("Transição de ciclo inválida");
    expect(getCiclosAvaliacao()).toEqual([encerrado]);
  });
});
