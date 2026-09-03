import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { Colaborador } from "../types/Colaborador";
import MinhaAvaliacaoPage from "./MinhaAvaliacaoPage";

const colaborador: Colaborador = { matricula: 10, funcao: "ANALISTA", status: "ATIVO", nome: "Pessoa Avaliada", email: "pessoa@example.com", cargo: "Analista", area: "Área", respondePara: "" };

function renderizar() {
  return renderToStaticMarkup(<UsuarioAtualContext.Provider value={{ usuarioAtual: colaborador, usuariosDisponiveis: [colaborador], selecionarUsuario: () => undefined }}><MemoryRouter><MinhaAvaliacaoPage /></MemoryRouter></UsuarioAtualContext.Provider>);
}

describe("histórico pessoal de ciclo cancelado", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([
      { id: "cancelado", ano: 2026, ciclo: 1, status: "CANCELADO", cancelamento: { motivo: "Motivo administrativo secreto", autorMatricula: 1, autorNome: "Gestor", data: "2026-06-01" }, dataCriacao: "2026-01-01", dataUltimaAtualizacao: "2026-06-01" },
      { id: "normal", ano: 2025, ciclo: 2, status: "ENCERRADO", dataCriacao: "2025-01-01", dataUltimaAtualizacao: "2025-06-01" },
    ]));
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify([
      { id: "rascunho-interno", colaboradorId: 10, colaboradorNome: colaborador.nome, status: "RASCUNHO", data: "2026-01-01", ano: 2026, ciclo: 1, competencias: [], notaMedia: 4, feedbackFinalGerente: "Conteúdo interno secreto" },
      { id: "concluida", colaboradorId: 10, colaboradorNome: colaborador.nome, status: "CONCLUIDA", data: "2025-01-01", ano: 2025, ciclo: 2, competencias: [], notaMedia: 5 },
    ]));
  });

  it("mostra ciclo cancelado sanitizado sem contar nem expor avaliação interna", () => {
    const html = renderizar();
    expect(html).toContain(
      'my-evaluations-history-card__status is-historical">Cancelado'
    );
    expect(html).toContain("Ciclo cancelado pela gerência.");
    expect(html).not.toContain("rascunho-interno");
    expect(html).not.toContain("Conteúdo interno secreto");
    expect(html).not.toContain("Motivo administrativo secreto");
    expect(html).toContain("<strong>1</strong><span>avaliação concluída</span>");
    expect((html.match(/Ver avaliação/g) ?? [])).toHaveLength(1);
  });
});
