import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback, StatusFeedback } from "../types/Feedback";
import FeedbackDetalhePage from "./FeedbackDetalhePage";

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number,
  colegiado?: number[]
): Colaborador {
  return {
    matricula,
    status: "ATIVO",
    nome: `Pessoa ${matricula}`,
    email: `${matricula}@example.com`,
    cargo: funcao ?? "Sem função",
    area: "Área fictícia",
    funcao,
    gestorDiretoMatricula,
    avaliadoresColegiadoMatriculas: colegiado,
    respondePara: "",
  };
}

const gerente = pessoa(1, "GERENTE");
const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
const colegiado = pessoa(3, "COORDENADOR", gerente.matricula);
const avaliado = pessoa(4, "ANALISTA", coordenador.matricula, [colegiado.matricula]);
const colaboradores = [gerente, coordenador, colegiado, avaliado];
const ciclo: CicloAvaliacao = {
  id: "ciclo-acoes-avaliacao",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};
const feedbackBase: Feedback = {
  id: "avaliacao-acoes",
  colaboradorId: avaliado.matricula,
  colaboradorNome: avaliado.nome,
  status: "CONCLUIDA",
  data: "2026-02-01T00:00:00.000Z",
  ano: 2026,
  ciclo: 1,
  competencias: [],
  criteriosDetalhados: [],
  notaMedia: 4,
};

function renderizar(actor: Colaborador, status: StatusFeedback): string {
  localStorage.setItem(
    "feedback-control-feedbacks",
    JSON.stringify([{ ...feedbackBase, status }])
  );

  return renderToStaticMarkup(
    <UsuarioAtualContext.Provider
      value={{
        usuarioAtual: actor,
        usuariosDisponiveis: colaboradores,
        selecionarUsuario: () => undefined,
      }}
    >
      <MemoryRouter
        initialEntries={[
          `/colaborador/${avaliado.matricula}/feedback/${feedbackBase.id}`,
        ]}
      >
        <Routes>
          <Route
            path="/colaborador/:id/feedback/:feedbackId"
            element={<FeedbackDetalhePage />}
          />
        </Routes>
      </MemoryRouter>
    </UsuarioAtualContext.Provider>
  );
}

describe("ações administrativas de FeedbackDetalhePage", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      "feedback-control-colaboradores",
      JSON.stringify(colaboradores)
    );
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([ciclo]));
  });

  it("oculta Editar e mostra Reabrir para gerente autorizado em concluída", () => {
    const html = renderizar(gerente, "CONCLUIDA");

    expect(html).not.toContain("Editar avaliação");
    expect(html).toContain("Reabrir avaliação");
  });

  it("oculta Editar e Reabrir para coordenador em concluída", () => {
    const html = renderizar(coordenador, "CONCLUIDA");

    expect(html).not.toContain("Editar avaliação");
    expect(html).not.toContain("Reabrir avaliação");
  });

  it("oculta Editar e Reabrir para colegiado em concluída", () => {
    const html = renderizar(colegiado, "CONCLUIDA");

    expect(html).not.toContain("Editar avaliação");
    expect(html).not.toContain("Reabrir avaliação");
  });

  it.each([gerente, coordenador, colegiado])(
    "mostra Editar em rascunho para papel autorizado $funcao/$matricula",
    (actor) => {
      expect(renderizar(actor, "RASCUNHO")).toContain("Editar avaliação");
    }
  );

  it("oculta Editar em cancelada", () => {
    expect(renderizar(gerente, "CANCELADA")).not.toContain("Editar avaliação");
  });
});
