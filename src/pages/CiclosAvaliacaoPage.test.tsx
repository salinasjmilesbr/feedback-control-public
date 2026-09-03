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
import { confirmarExclusaoCiclo } from "./confirmarExclusaoCiclo";

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

function renderizar(
  status: StatusCicloAvaliacao,
  mostrarCanceladosInicial = false
): string {
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
        <CiclosAvaliacaoPage
          mostrarCanceladosInicial={mostrarCanceladosInicial}
        />
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
    expect(html).toContain("Excluir ciclo");
    expect(html).not.toContain("Cancelar ciclo");
  });

  it("mostra somente encerramento para ciclo ativo", () => {
    const html = renderizar("ATIVO");

    expect(html).toContain("Encerrar ciclo");
    expect(html).not.toContain("Ativar ciclo");
    expect(html).not.toContain("Editar status");
    expect(html).not.toContain("Editar período");
    expect(html).not.toContain("Excluir ciclo");
    expect(html).toContain("Cancelar ciclo");
  });

  it("não mostra ação de transição para ciclo encerrado", () => {
    const html = renderizar("ENCERRADO");

    expect(html).not.toContain("Ativar ciclo");
    expect(html).not.toContain("Encerrar ciclo");
    expect(html).not.toContain("Editar status");
    expect(html).toContain("Lifecycle encerrado");
    expect(html).not.toContain("Editar período");
    expect(html).not.toContain("Excluir ciclo");
    expect(html).not.toContain("Cancelar ciclo");
  });

  it("oculta cancelados por padrão e oferece controle explícito", () => {
    const html = renderizar("CANCELADO");

    expect(html).toContain("Mostrar cancelados");
    expect(html).not.toContain("Lifecycle cancelado");
  });

  it("identifica cancelado quando exibido e oculta todas as ações normais", () => {
    const html = renderizar("CANCELADO", true);

    expect(html).toContain("Cancelado");
    expect(html).toContain("Lifecycle cancelado");
    expect(html).not.toContain("Ativar ciclo");
    expect(html).not.toContain("Encerrar ciclo");
    expect(html).not.toContain("Editar período");
    expect(html).not.toContain("Excluir ciclo");
    expect(html).not.toContain("Cancelar ciclo");
  });

  it("exige confirmação explícita antes da exclusão", () => {
    const ciclo: CicloAvaliacao = {
      id: "ciclo-confirmacao",
      ano: 2026,
      ciclo: 2,
      status: "PLANEJADO",
      dataCriacao: "2026-01-01T00:00:00.000Z",
      dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
    };
    let mensagem = "";

    const confirmado = confirmarExclusaoCiclo(ciclo, (texto) => {
      mensagem = texto;
      return false;
    });

    expect(confirmado).toBe(false);
    expect(mensagem).toContain("Excluir 2026 • Ciclo 2?");
    expect(mensagem).toContain("Avaliações vazias");
  });
});
