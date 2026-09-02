import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type {
  CicloAvaliacao,
  StatusCicloAvaliacao,
} from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import CiclosAvaliacaoPage from "./CiclosAvaliacaoPage";

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

function renderizar(status: StatusCicloAvaliacao): string {
  const ciclo: CicloAvaliacao = {
    id: "ciclo-ui",
    ano: 2026,
    ciclo: 1,
    status,
    dataCriacao: "2026-01-01T00:00:00.000Z",
    dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
  };
  localStorage.setItem("feedback-control-ciclos", JSON.stringify([ciclo]));

  return renderToStaticMarkup(
    <UsuarioAtualContext.Provider
      value={{
        usuarioAtual: gerente,
        usuariosDisponiveis: [gerente],
        selecionarUsuario: () => undefined,
      }}
    >
      <MemoryRouter>
        <CiclosAvaliacaoPage />
      </MemoryRouter>
    </UsuarioAtualContext.Provider>
  );
}

describe("ações de lifecycle em CiclosAvaliacaoPage", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("mostra somente ativação para ciclo planejado", () => {
    const html = renderizar("PLANEJADO");

    expect(html).toContain("Ativar ciclo");
    expect(html).not.toContain("Encerrar ciclo");
    expect(html).not.toContain("Editar status");
    expect(html).toContain("Editar período");
  });

  it("mostra somente encerramento para ciclo ativo", () => {
    const html = renderizar("ATIVO");

    expect(html).toContain("Encerrar ciclo");
    expect(html).not.toContain("Ativar ciclo");
    expect(html).not.toContain("Editar status");
    expect(html).not.toContain("Editar período");
  });

  it("não mostra ação de transição para ciclo encerrado", () => {
    const html = renderizar("ENCERRADO");

    expect(html).not.toContain("Ativar ciclo");
    expect(html).not.toContain("Encerrar ciclo");
    expect(html).not.toContain("Editar status");
    expect(html).toContain("Lifecycle encerrado");
    expect(html).not.toContain("Editar período");
  });
});
