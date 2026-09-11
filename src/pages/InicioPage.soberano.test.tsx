/**
 * F5-07 — testes de tela do roteamento inicial por ESTADO SOBERANO.
 *
 * Cobre: `funcao` deixou de decidir o universo (um ANALISTA com leitura soberana
 * autorizada vê a lista soberana), negação do servidor como estado restrito
 * explícito com acesso ao universo pessoal, falha do caminho soberano sem queda
 * para dados locais e leitura do universo pela porta única.
 */

import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import {
  listarColaboradores,
  redefinirAcessoColaboradoresSoberanos,
  type ColaboradorSoberano,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { ServiceColaboradores } from "../services/colaboradoresSoberanos/serviceColaboradores";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { ORGANIZACAO_TESTE, ProvedorAuthTeste } from "../test/authTeste";
import type { Colaborador } from "../types/Colaborador";
import InicioPage, {
  type EstadoUniversoColaboradores,
} from "./InicioPage";

const analista: Colaborador = {
  matricula: 10,
  funcao: "ANALISTA",
  status: "ATIVO",
  nome: "Analista Fictício",
  email: "analista@example.invalid",
  cargo: "Analista",
  area: "Área fictícia",
  respondePara: "",
};

const UUID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

function soberano(): ColaboradorSoberano {
  return {
    collaboratorId: UUID,
    matricula: "12345",
    fullName: "Pessoa do Universo Soberano",
    email: "universo@example.invalid",
    status: "active",
    admissionDate: "2024-01-10",
    unitId: null,
    unitName: null,
    jobRoleCode: null,
    jobRoleName: null,
    seniorityName: null,
    managerCollaboratorId: null,
    managerFullName: null,
    version: 1,
  };
}

function operacoes(parcial: Partial<ServiceColaboradores>): ServiceColaboradores {
  return parcial as unknown as ServiceColaboradores;
}

function renderizar(
  estadoInicial: EstadoUniversoColaboradores,
  usuario: Colaborador = analista
): string {
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <UsuarioAtualContext.Provider
        value={{
          usuarioAtual: usuario,
          usuariosDisponiveis: [usuario],
          selecionarUsuario: () => undefined,
        }}
      >
        <MemoryRouter>
          <InicioPage estadoInicial={estadoInicial} />
        </MemoryRouter>
      </UsuarioAtualContext.Provider>
    </ProvedorAuthTeste>
  );
}

describe("início por estado soberano", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    redefinirAcessoColaboradoresSoberanos();
  });

  it("não decide o universo por funcao: a lista soberana é exibida", () => {
    const html = renderizar({
      fase: "pronto",
      colaboradores: [soberano()],
    });

    expect(html).toContain("Pessoa do Universo Soberano");
    expect(html).toContain("Cadastro soberano de pessoas");
    expect(html).toContain(`/colaborador/${UUID}`);
    expect(html).not.toContain("Usuário atual não definido");
  });

  it("negação do servidor vira estado restrito explícito, sem escrita local", () => {
    const storage = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(storage, "setItem");

    const html = renderizar({
      fase: "erro",
      codigo: "FORBIDDEN",
      mensagem: "Você não tem permissão para esta operação.",
    });

    expect(html).toContain("Acesso restrito ao universo de colaboradores");
    expect(html).toContain("A decisão é do servidor");
    expect(html).toContain("/minha-avaliacao");
    expect(html).not.toContain("Cadastro soberano de pessoas");
    expect(escrever).not.toHaveBeenCalled();
  });

  it("falha do caminho soberano não cai para dados locais", () => {
    const html = renderizar({
      fase: "erro",
      codigo: "INTERNAL",
      mensagem: "O caminho de colaboradores no PostgreSQL não está disponível.",
    });

    expect(html).toContain("Universo de colaboradores indisponível");
    expect(html).toContain("nenhum dado local é exibido como substituto");
    expect(html).not.toContain("Cadastro soberano de pessoas");
  });

  it("lê o universo pela porta única com a organização ativa", async () => {
    const listar = vi.fn(
      async (): Promise<ResultadoColaboradores<readonly ColaboradorSoberano[]>> => ({
        ok: true,
        dados: [soberano()],
      })
    );

    const resultado = await listarColaboradores(
      { organizationId: ORGANIZACAO_TESTE },
      { operacoes: operacoes({ listar }) }
    );

    expect(listar).toHaveBeenCalledWith({ organizationId: ORGANIZACAO_TESTE });
    expect(resultado.ok).toBe(true);

    const html = renderizar({ fase: "pronto", colaboradores: [soberano()] });
    expect(html).toContain("Pessoa do Universo Soberano");
  });
});
