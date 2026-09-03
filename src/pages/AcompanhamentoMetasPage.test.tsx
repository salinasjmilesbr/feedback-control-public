import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { Colaborador } from "../types/Colaborador";
import AcompanhamentoMetasPage from "./AcompanhamentoMetasPage";

function pessoa(matricula: number, funcao: Colaborador["funcao"], gestor?: number, colegiado?: number[]): Colaborador {
  return { matricula, funcao, gestorDiretoMatricula: gestor, avaliadoresColegiadoMatriculas: colegiado, status: "ATIVO", nome: `Pessoa ${matricula}`, email: `${matricula}@example.com`, cargo: "Cargo", area: "Área", respondePara: "" };
}

const gerente = pessoa(1, "GERENTE");
const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
const colegiado = pessoa(3, "COORDENADOR", gerente.matricula);
const avaliado = pessoa(4, "ANALISTA", coordenador.matricula, [colegiado.matricula]);
const colaboradores = [gerente, coordenador, colegiado, avaliado];

function renderizar(actor: Colaborador) {
  return renderToStaticMarkup(
    <UsuarioAtualContext.Provider value={{ usuarioAtual: actor, usuariosDisponiveis: colaboradores, selecionarUsuario: () => undefined }}>
      <MemoryRouter initialEntries={["/ciclos/cancelado/colaborador/4/metas"]}>
        <Routes><Route path="/ciclos/:cicloId/colaborador/:id/metas" element={<AcompanhamentoMetasPage />} /></Routes>
      </MemoryRouter>
    </UsuarioAtualContext.Provider>
  );
}

describe("consulta histórica de metas de ciclo cancelado", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem("feedback-control-colaboradores", JSON.stringify(colaboradores));
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([{ id: "cancelado", ano: 2026, ciclo: 1, status: "CANCELADO", dataCriacao: "2026-01-01", dataUltimaAtualizacao: "2026-01-01" }]));
    localStorage.setItem("feedback-control-metas", JSON.stringify([{ id: "meta", colaboradorMatricula: 4, colaboradorNome: avaliado.nome, cicloId: "cancelado", tipo: "INDIVIDUAL", descricao: "Meta histórica", kpi: "KPI", valorAlvo: "100", status: "EM_ANDAMENTO", historico: [] }]));
  });

  it.each([gerente, coordenador])("permite consulta somente leitura para $funcao responsável", (actor) => {
    const html = renderizar(actor);
    expect(html).toContain("Meta histórica");
    expect(html).toContain("Ciclo cancelado");
    expect(html).not.toContain("Acesso restrito");
    expect(html).not.toContain("Marque para aprovar esta meta");
    expect(html).toContain("disabled");
  });

  it("não concede acesso por vínculo apenas de colegiado", () => {
    expect(renderizar(colegiado)).toContain("Acesso restrito");
  });
});
