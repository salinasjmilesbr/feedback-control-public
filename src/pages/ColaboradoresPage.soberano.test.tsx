/**
 * F5-07 — testes de tela da listagem soberana de colaboradores.
 *
 * Cobre: listagem renderizando a projeção devolvida pelo serviço da porta única,
 * negação/erro exibido SEM escrita local, fail-closed sem organização ativa,
 * ausência explícita de alocação e remoção das heurísticas de texto
 * (`respondePara`, agrupamento por `funcao`).
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
import ColaboradoresPage, {
  type EstadoColaboradores,
} from "./ColaboradoresPage";

const ator: Colaborador = {
  matricula: 1,
  funcao: "GERENTE",
  status: "ATIVO",
  nome: "Gestor Fictício",
  email: "gestor@example.invalid",
  cargo: "Gerente",
  area: "Área fictícia",
  respondePara: "",
};

const UUID_A = "11111111-1111-4111-8111-111111111111";
const UUID_B = "22222222-2222-4222-8222-222222222222";

function soberano(parcial: Partial<ColaboradorSoberano> = {}): ColaboradorSoberano {
  return {
    collaboratorId: UUID_A,
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
    version: 1,
    ...parcial,
  };
}

function operacoes(parcial: Partial<ServiceColaboradores>): ServiceColaboradores {
  return parcial as unknown as ServiceColaboradores;
}

function renderizar(
  estadoInicial: EstadoColaboradores,
  usuario: Colaborador | undefined = ator
): string {
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <UsuarioAtualContext.Provider
        value={{
          usuarioAtual: usuario,
          usuariosDisponiveis: usuario ? [usuario] : [],
          selecionarUsuario: () => undefined,
        }}
      >
        <MemoryRouter>
          <ColaboradoresPage estadoInicial={estadoInicial} />
        </MemoryRouter>
      </UsuarioAtualContext.Provider>
    </ProvedorAuthTeste>
  );
}

/** Chaves cuja escrita a F5-07 PROÍBE no caminho de tela (I7/D14). */
const CHAVES_F507 = [
  "feedback-control-colaboradores",
  "feedback-control-historico-organizacional",
];

/** A tela escreveu alguma chave soberana de colaborador/histórico? */
function escreveuChaveF507(espiado: { mock: { calls: unknown[][] } }): boolean {
  return espiado.mock.calls.some((chamada) =>
    CHAVES_F507.includes(String(chamada[0]))
  );
}

describe("listagem soberana em ColaboradoresPage", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    redefinirAcessoColaboradoresSoberanos();
  });

  it("renderiza a projeção devolvida pelo serviço da porta, com UUID no link", async () => {
    const projecao = [
      soberano({
        collaboratorId: UUID_A,
        fullName: "Ana Fictícia",
        matricula: "12345",
        unitName: "Unidade Fictícia",
        jobRoleName: "Analista de Operações",
        seniorityName: "Pleno",
        managerFullName: "Gestor Fictício",
        version: 4,
      }),
      soberano({
        collaboratorId: UUID_B,
        fullName: "Bruno Fictício",
        matricula: "54321",
        status: "leave",
      }),
    ];
    const listar = vi.fn(
      async (): Promise<ResultadoColaboradores<readonly ColaboradorSoberano[]>> => ({
        ok: true,
        dados: projecao,
      })
    );

    const resultado = await listarColaboradores(
      { organizationId: ORGANIZACAO_TESTE },
      { operacoes: operacoes({ listar }) }
    );

    expect(listar).toHaveBeenCalledWith({ organizationId: ORGANIZACAO_TESTE });
    expect(resultado.ok).toBe(true);

    const html = renderizar({ fase: "pronto", colaboradores: projecao });

    expect(html).toContain("Ana Fictícia");
    expect(html).toContain("Bruno Fictício");
    expect(html).toContain("Matrícula 12345");
    expect(html).toContain("Ativo");
    expect(html).toContain("Em licença");
    expect(html).toContain(`/colaborador/${UUID_A}`);
    expect(html).toContain(`/colaborador/${UUID_B}`);
    expect(html).not.toContain("/colaborador/12345");
  });

  it("mostra ausência de alocação explicitamente, sem inventar estrutura", () => {
    const html = renderizar({
      fase: "pronto",
      colaboradores: [soberano({ fullName: "Sem Alocação Fictícia" })],
    });

    expect(html).toContain("Sem Alocação Fictícia");
    expect(html).toContain("Sem alocação");
    // A lista continua sendo LISTA: nada de administração estrutural aqui.
    expect(html).toContain("A alocação é definida na ficha do colaborador.");
    expect(html).not.toContain("F5-08");
    expect(html).not.toContain("Gestor:");
  });

  it("exibe negação do servidor como estado restrito, sem escrita local", () => {
    const storage = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(storage, "setItem");

    const html = renderizar({
      fase: "erro",
      codigo: "FORBIDDEN",
      mensagem: "Você não tem permissão para esta operação.",
    });

    expect(html).toContain("Acesso restrito");
    expect(html).toContain("Você não tem permissão para esta operação.");
    expect(html).toContain("Nenhum dado local é exibido como substituto");
    expect(escreveuChaveF507(escrever)).toBe(false);
  });

  it("sem organização ativa a porta recusa (fail-closed) e a tela não cai para o legado", async () => {
    const storage = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(storage, "setItem");

    // O fail-closed de organização vive no SERVICE da porta: aqui ele é exercitado
    // com o resolvedor de organização ativa injetado devolvendo `null` (nenhum
    // repositório é tocado e nenhum dado local é consultado).
    const resultado = await listarColaboradores(
      { organizationId: null },
      { deps: { organizacaoAtivaId: () => null } }
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.codigo).toBe("FORBIDDEN");

    const html = renderizar({
      fase: "erro",
      codigo: resultado.codigo,
      mensagem: resultado.mensagem,
    });

    expect(html).toContain("Acesso restrito");
    expect(html).toContain("Selecione uma organização ativa");
    expect(escreveuChaveF507(escrever)).toBe(false);
    expect(html).not.toContain("Pessoa Fictícia");
  });

  it("não usa mais filtro por texto respondePara nem agrupamento por funcao", () => {
    const html = renderizar({
      fase: "pronto",
      colaboradores: [soberano({ fullName: "Ana Fictícia" })],
    });

    expect(html).not.toContain("Equipe / Coordenador");
    expect(html).not.toContain("Minha equipe direta");
    expect(html).not.toContain("Avaliações como colegiado");
  });

  it("mantém a massa de teste explicitamente restrita e rotulada como DEV", () => {
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([
        {
          id: "ciclo-dev",
          ano: 2026,
          ciclo: 1,
          status: "ATIVO",
          dataCriacao: "2026-01-01",
          dataUltimaAtualizacao: "2026-01-01",
        },
      ])
    );

    const html = renderizar({
      fase: "pronto",
      colaboradores: [soberano()],
    });

    expect(html).toContain("Ferramenta temporária de desenvolvimento");
    expect(html).toContain("Gerar dados de teste (DEV)");
    expect(html).toContain("Restrita ao modo DEV");
  });
});
