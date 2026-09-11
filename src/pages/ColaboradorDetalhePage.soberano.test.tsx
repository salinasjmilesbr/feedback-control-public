/**
 * F5-07 — testes de tela do detalhe soberano do colaborador.
 *
 * Cobre: identidade/estado pela projeção soberana, histórico organizacional vindo
 * da trilha append-only (`obterHistoricoColaborador`), ausência explícita de
 * alocação, estado restrito em negação, acervo legado apenas ROTULADO como legado
 * e ausência de leitura do `colaboradorStorage` no render.
 */

import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import {
  getColaboradorByMatricula,
  getColaboradores,
} from "../services/colaboradorStorage";
import {
  obterHistoricoColaborador,
  redefinirAcessoColaboradoresSoberanos,
  type ColaboradorSoberano,
  type EventoColaborador,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { ServiceColaboradores } from "../services/colaboradoresSoberanos/serviceColaboradores";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { ORGANIZACAO_TESTE, ProvedorAuthTeste } from "../test/authTeste";
import ColaboradorDetalhePage, {
  type EstadoDetalheColaborador,
} from "./ColaboradorDetalhePage";

/**
 * Barreira do teste: nenhuma tela migrada pode voltar a ler o cadastro legado
 * durante o render (I7). O mock registra a chamada para a asserção.
 */
vi.mock("../services/colaboradorStorage", async (importOriginal) => {
  const real =
    await importOriginal<typeof import("../services/colaboradorStorage")>();
  return {
    ...real,
    getColaboradores: vi.fn(() => []),
    getColaboradorByMatricula: vi.fn(() => undefined),
  };
});

const UUID = "99999999-9999-4999-8999-999999999999";

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
    version: 3,
    ...parcial,
  };
}

function evento(parcial: Partial<EventoColaborador> = {}): EventoColaborador {
  return {
    eventId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    eventType: "IDENTIFICADOR_DEFINIDO",
    effectiveDate: "2026-03-01T00:00:00.000Z",
    reason: "Correção de matrícula",
    cycleScope: "CICLO_ATUAL_E_POSTERIORES",
    referenceCycleId: null,
    actorUserProfileId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    actorFullName: "Gestor Fictício",
    beforeValue: { matricula: "12345" },
    afterValue: { matricula: "54321" },
    createdAt: "2026-03-01T12:00:00.000Z",
    ...parcial,
  };
}

function operacoes(parcial: Partial<ServiceColaboradores>): ServiceColaboradores {
  return parcial as unknown as ServiceColaboradores;
}

function renderizar(
  estadoInicial: EstadoDetalheColaborador,
  identificador: string = UUID
): string {
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <UsuarioAtualContext.Provider
        value={{
          usuarioAtual: undefined,
          usuariosDisponiveis: [],
          selecionarUsuario: () => undefined,
        }}
      >
        <MemoryRouter initialEntries={[`/colaborador/${identificador}`]}>
          <Routes>
            <Route
              path="/colaborador/:collaboratorId"
              element={<ColaboradorDetalhePage estadoInicial={estadoInicial} />}
            />
          </Routes>
        </MemoryRouter>
      </UsuarioAtualContext.Provider>
    </ProvedorAuthTeste>
  );
}

describe("detalhe soberano em ColaboradorDetalhePage", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    vi.mocked(getColaboradores).mockClear();
    vi.mocked(getColaboradorByMatricula).mockClear();
    redefinirAcessoColaboradoresSoberanos();
  });

  it("mostra 'sem alocação' e não lê o cadastro legado no render", () => {
    const html = renderizar({
      fase: "pronto",
      colaborador: soberano(),
      historico: [],
      erroHistorico: null,
    });

    expect(html).toContain("Pessoa Fictícia");
    expect(html).toContain("Sem alocação");
    expect(html).toContain("F5-08");
    expect(html).not.toContain("Gestor:");
    expect(getColaboradores).not.toHaveBeenCalled();
    expect(getColaboradorByMatricula).not.toHaveBeenCalled();
  });

  it("renderiza o histórico organizacional soberano com autor e vigência", () => {
    const html = renderizar({
      fase: "pronto",
      colaborador: soberano(),
      historico: [evento()],
      erroHistorico: null,
    });

    expect(html).toContain("Matrícula definida");
    expect(html).toContain("Correção de matrícula");
    expect(html).toContain("Registrado por: Gestor Fictício");
    expect(html).toContain("Matrícula: 12345 → 54321");
    expect(html).toContain("Trilha soberana append-only");
    expect(getColaboradores).not.toHaveBeenCalled();
  });

  it("exibe negação do servidor como acesso restrito, sem fallback local", () => {
    const html = renderizar({
      fase: "erro",
      codigo: "FORBIDDEN",
      mensagem: "Você não tem permissão para esta operação.",
    });

    expect(html).toContain("Acesso restrito");
    expect(html).toContain("Você não tem permissão para esta operação.");
    expect(html).toContain("Nenhum cadastro local é exibido como substituto");
    expect(getColaboradores).not.toHaveBeenCalled();
  });

  it("mantém o acervo local claramente rotulado como legado", () => {
    const html = renderizar({
      fase: "pronto",
      colaborador: soberano(),
      historico: [],
      erroHistorico: null,
    });

    expect(html).toContain("Acervo legado local (avaliações)");
    expect(html).toContain(
      "Avaliações ainda persistidas no armazenamento local"
    );
    expect(html).toContain("Observações (legado local)");
  });

  it("explicita quando não há matrícula numérica para o acervo legado", () => {
    const html = renderizar({
      fase: "pronto",
      colaborador: soberano({ matricula: null }),
      historico: [],
      erroHistorico: null,
    });

    expect(html).toContain("não possui matrícula numérica vigente");
    expect(html).toContain("O histórico soberano acima permanece íntegro.");
  });

  it("busca o histórico pela porta soberana com o UUID do colaborador", async () => {
    const obterHistorico = vi.fn(
      async (): Promise<ResultadoColaboradores<readonly EventoColaborador[]>> => ({
        ok: true,
        dados: [evento()],
      })
    );

    const resultado = await obterHistoricoColaborador(
      { collaboratorId: UUID, organizationId: ORGANIZACAO_TESTE },
      { operacoes: operacoes({ obterHistorico }) }
    );

    expect(obterHistorico).toHaveBeenCalledWith({
      collaboratorId: UUID,
      organizationId: ORGANIZACAO_TESTE,
    });
    expect(resultado.ok).toBe(true);
  });
});
