import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import type { Colaborador } from "../types/Colaborador";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import MinhaAvaliacaoPage from "./MinhaAvaliacaoPage";

const colaborador: Colaborador = {
  matricula: 10,
  funcao: "ANALISTA",
  status: "ATIVO",
  nome: "Pessoa Fictícia",
  email: "pessoa@example.invalid",
  cargo: "Analista",
  area: "Área",
  respondePara: "",
};

function renderizar(
  value: Partial<React.ComponentProps<typeof UsuarioAtualContext.Provider>["value"]>
) {
  return renderToStaticMarkup(
    <UsuarioAtualContext.Provider
      value={{
        usuarioAtual: colaborador,
        usuarioAtualLegado: colaborador,
        usuariosDisponiveis: [colaborador],
        selecionarUsuario: () => undefined,
        estadoResolucaoIdentidade: "resolvida-com-usuario",
        ...value,
      }}
    >
      <MemoryRouter>
        <MinhaAvaliacaoPage />
      </MemoryRouter>
    </UsuarioAtualContext.Provider>
  );
}

describe("#388 — resolução da identidade em Minha avaliação", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  it("não exibe ausência terminal durante o bootstrap", () => {
    const html = renderizar({
      usuarioAtual: undefined,
      usuarioAtualLegado: undefined,
      estadoResolucaoIdentidade: "carregando",
    });
    expect(html).toContain("Carregando identidade");
    expect(html).not.toContain("Usuário atual não definido");
  });

  it("mantém fail-closed após resolução sem usuário", () => {
    const html = renderizar({
      usuarioAtual: undefined,
      usuarioAtualLegado: undefined,
      estadoResolucaoIdentidade: "resolvida-sem-usuario",
    });
    expect(html).toContain("Usuário atual não definido");
  });

  it("carrega normalmente após resolução com usuário", () => {
    const html = renderizar({});
    expect(html).toContain("Pessoa Fictícia");
    expect(html).not.toContain("UsuÃ¡rio atual nÃ£o definido");
  });
});
