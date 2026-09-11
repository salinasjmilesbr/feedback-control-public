/**
 * F5-07 — testes de tela da edição soberana.
 *
 * Cobre: leitura por UUID, intenção de matrícula resolvida NO SERVIDOR (fail-closed
 * quando ausente/ambígua), `expectedVersion` em toda mutação, conflito de versão
 * explícito, ausência de alocação (F5-08) e ausência de escrita local.
 */

import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  alterarStatusColaborador,
  definirIdentificadorColaborador,
  editarColaborador,
  obterColaborador,
  redefinirAcessoColaboradoresSoberanos,
  type ColaboradorSoberano,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { ServiceColaboradores } from "../services/colaboradoresSoberanos/serviceColaboradores";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { ORGANIZACAO_TESTE, ProvedorAuthTeste } from "../test/authTeste";
import EditarColaboradorPage, {
  type EstadoEdicaoColaborador,
} from "./EditarColaboradorPage";

const UUID = "55555555-5555-4555-8555-555555555555";

function soberano(parcial: Partial<ColaboradorSoberano> = {}): ColaboradorSoberano {
  return {
    collaboratorId: UUID,
    matricula: "12345",
    fullName: "Pessoa Fictícia",
    email: "pessoa@example.invalid",
    status: "active",
    admissionDate: "2024-01-10",
    unitId: null,
    unitName: null,
    jobRoleCode: null,
    jobRoleName: null,
    seniorityName: null,
    managerCollaboratorId: null,
    managerFullName: null,
    version: 7,
    ...parcial,
  };
}

function operacoes(parcial: Partial<ServiceColaboradores>): ServiceColaboradores {
  return parcial as unknown as ServiceColaboradores;
}

function renderizar(
  estadoInicial: EstadoEdicaoColaborador,
  identificador: string = UUID
): string {
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <MemoryRouter initialEntries={[`/colaborador/${identificador}/editar`]}>
        <Routes>
          <Route
            path="/colaborador/:collaboratorId/editar"
            element={<EditarColaboradorPage estadoInicial={estadoInicial} />}
          />
        </Routes>
      </MemoryRouter>
    </ProvedorAuthTeste>
  );
}

describe("edição soberana em EditarColaboradorPage", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    redefinirAcessoColaboradoresSoberanos();
  });

  it("carrega a projeção por UUID com versão e operações separadas", () => {
    const html = renderizar({ fase: "pronto", colaborador: soberano() });

    expect(html).toContain("Pessoa Fictícia");
    expect(html).toContain("Versão da projeção: 7");
    expect(html).toContain("Dados de pessoa");
    expect(html).toContain("Nova matrícula *");
    expect(html).toContain("Status, licença e inativação");
    expect(html).toContain("Estrutura organizacional (F5-08)");
  });

  it("exibe 'sem alocação' quando não há estrutura soberana", () => {
    const html = renderizar({ fase: "pronto", colaborador: soberano() });

    expect(html).toContain("Sem alocação");
    expect(html).toContain("F5-08");
  });

  it("mostra conflito de versão explícito, sem reescrever dado local", () => {
    const storage = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(storage, "setItem");

    const html = renderizar({
      fase: "conflito",
      mensagem: "O colaborador foi alterado por outra pessoa.",
    });

    expect(html).toContain("Conflito de versão");
    expect(html).toContain("O colaborador foi alterado por outra pessoa.");
    expect(html).toContain("Recarregar dados");
    expect(escrever).not.toHaveBeenCalled();
  });

  it("envia expectedVersion nas mutações e propaga CONFLICT como resultado", async () => {
    const storage = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(storage, "setItem");

    const editar = vi.fn(
      async (): Promise<ResultadoColaboradores<number>> => ({
        ok: false,
        codigo: "CONFLICT",
        mensagem: "Versão divergente.",
      })
    );
    const definirIdentificador = vi.fn(
      async (): Promise<ResultadoColaboradores<number>> => ({ ok: true, dados: 8 })
    );
    const alterarStatus = vi.fn(
      async (): Promise<ResultadoColaboradores<number>> => ({ ok: true, dados: 9 })
    );

    const conflito = await editarColaborador(
      {
        collaboratorId: UUID,
        operationId: "66666666-6666-4666-8666-666666666666",
        expectedVersion: 7,
        fullName: "Pessoa Fictícia Editada",
        organizationId: ORGANIZACAO_TESTE,
      },
      { operacoes: operacoes({ editar }) }
    );

    expect(editar).toHaveBeenCalledWith({
      collaboratorId: UUID,
      operationId: "66666666-6666-4666-8666-666666666666",
      expectedVersion: 7,
      fullName: "Pessoa Fictícia Editada",
      organizationId: ORGANIZACAO_TESTE,
    });
    expect(conflito.ok).toBe(false);
    if (!conflito.ok) expect(conflito.codigo).toBe("CONFLICT");

    await definirIdentificadorColaborador(
      {
        collaboratorId: UUID,
        operationId: "77777777-7777-4777-8777-777777777777",
        novaMatricula: "54321",
        vigencia: "2026-03-01",
        motivo: "Correção de matrícula",
        expectedVersion: 7,
        organizationId: ORGANIZACAO_TESTE,
      },
      { operacoes: operacoes({ definirIdentificador }) }
    );
    expect(definirIdentificador).toHaveBeenCalledWith(
      expect.objectContaining({
        collaboratorId: UUID,
        novaMatricula: "54321",
        vigencia: "2026-03-01",
        motivo: "Correção de matrícula",
        expectedVersion: 7,
      })
    );

    await alterarStatusColaborador(
      {
        collaboratorId: UUID,
        operationId: "88888888-8888-4888-8888-888888888888",
        novoStatus: "inactive",
        vigencia: "2026-03-02",
        motivo: "Desligamento",
        expectedVersion: 7,
        organizationId: ORGANIZACAO_TESTE,
      },
      { operacoes: operacoes({ alterarStatus }) }
    );
    expect(alterarStatus).toHaveBeenCalledWith(
      expect.objectContaining({
        collaboratorId: UUID,
        novoStatus: "inactive",
        expectedVersion: 7,
      })
    );

    expect(escrever).not.toHaveBeenCalled();
  });

  it("mantém o UUID como identidade e a matrícula apenas como intenção de servidor", async () => {
    const obter = vi.fn(
      async (): Promise<ResultadoColaboradores<ColaboradorSoberano>> => ({
        ok: true,
        dados: soberano(),
      })
    );
    const dependencias = { operacoes: operacoes({ obter }) };

    await obterColaborador(
      { collaboratorId: UUID, organizationId: ORGANIZACAO_TESTE },
      dependencias
    );
    expect(obter).toHaveBeenLastCalledWith({
      collaboratorId: UUID,
      organizationId: ORGANIZACAO_TESTE,
    });

    await obterColaborador(
      { matricula: "12345", organizationId: ORGANIZACAO_TESTE },
      dependencias
    );
    expect(obter).toHaveBeenLastCalledWith({
      matricula: "12345",
      organizationId: ORGANIZACAO_TESTE,
    });

    const html = renderizar(
      {
        fase: "erro",
        codigo: "NOT_FOUND",
        mensagem: "Colaborador não encontrado.",
      },
      "12345"
    );

    expect(html).toContain("Colaborador não encontrado");
    expect(html).toContain("resolvida no servidor");
  });
});
