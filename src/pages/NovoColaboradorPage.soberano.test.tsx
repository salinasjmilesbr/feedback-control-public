/**
 * F5-07 — testes de tela do cadastro soberano de colaborador.
 *
 * Cobre: formulário restrito a dados de pessoa + matrícula + status (estrutura
 * saiu — F5-08), criação pela PORTA com `operationId` e sem qualquer escrita em
 * `localStorage`, e estados explícitos de processamento/erro/sucesso.
 */

import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  criarColaborador,
  redefinirAcessoColaboradoresSoberanos,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { ServiceColaboradores } from "../services/colaboradoresSoberanos/serviceColaboradores";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { ORGANIZACAO_TESTE, ProvedorAuthTeste } from "../test/authTeste";
import NovoColaboradorPage, {
  type EstadoCriacaoColaborador,
} from "./NovoColaboradorPage";

function operacoes(parcial: Partial<ServiceColaboradores>): ServiceColaboradores {
  return parcial as unknown as ServiceColaboradores;
}

function renderizar(estadoInicial?: EstadoCriacaoColaborador): string {
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <MemoryRouter>
        <NovoColaboradorPage estadoInicial={estadoInicial} />
      </MemoryRouter>
    </ProvedorAuthTeste>
  );
}

describe("cadastro soberano em NovoColaboradorPage", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    redefinirAcessoColaboradoresSoberanos();
  });

  it("mantém no formulário apenas pessoa, matrícula e status (estrutura é F5-08)", () => {
    const html = renderizar();

    expect(html).toContain("Matrícula *");
    expect(html).toContain("Nome *");
    expect(html).toContain("E-mail *");
    expect(html).toContain("Status inicial *");
    expect(html).toContain("Estrutura organizacional (F5-08)");
    expect(html).toContain("SEM ALOCAÇÃO");

    // Campos de estrutura que só existiam no localStorage saíram do formulário.
    expect(html).not.toContain("Cargo *");
    expect(html).not.toContain("Área *");
    expect(html).not.toContain("Função *");
    expect(html).not.toContain("Senioridade *");
    expect(html).not.toContain("Gestor direto");
    expect(html).not.toContain("Avaliadores do colegiado");
  });

  it("cria pela porta soberana com operationId e sem tocar localStorage", async () => {
    const storage = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(storage, "setItem");
    const criar = vi.fn(
      async (): Promise<ResultadoColaboradores<string>> => ({
        ok: true,
        dados: "33333333-3333-4333-8333-333333333333",
      })
    );

    const resultado = await criarColaborador(
      {
        fullName: "Nova Pessoa Fictícia",
        email: "nova@example.invalid",
        matricula: "98765",
        admissionDate: "2026-02-01",
        statusInicial: "active",
        operationId: "44444444-4444-4444-8444-444444444444",
        organizationId: ORGANIZACAO_TESTE,
      },
      { operacoes: operacoes({ criar }) }
    );

    expect(criar).toHaveBeenCalledTimes(1);
    expect(criar).toHaveBeenCalledWith({
      fullName: "Nova Pessoa Fictícia",
      email: "nova@example.invalid",
      matricula: "98765",
      admissionDate: "2026-02-01",
      statusInicial: "active",
      operationId: "44444444-4444-4444-8444-444444444444",
      organizationId: ORGANIZACAO_TESTE,
    });
    expect(resultado).toEqual({
      ok: true,
      dados: "33333333-3333-4333-8333-333333333333",
    });
    expect(escrever).not.toHaveBeenCalled();

    const html = renderizar({
      fase: "sucesso",
      collaboratorId: "33333333-3333-4333-8333-333333333333",
    });
    expect(html).toContain("Colaborador criado no cadastro soberano.");
  });

  it("mostra processamento explícito e bloqueia novo envio", () => {
    const html = renderizar({ fase: "processando" });

    expect(html).toContain("Gravando o cadastro no servidor…");
    expect(html).toContain("Salvando…");
    expect(html).toContain("disabled");
  });

  it("exibe negação e conflito do servidor sem registrar nada localmente", () => {
    const storage = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(storage, "setItem");

    const negado = renderizar({
      fase: "erro",
      codigo: "FORBIDDEN",
      mensagem: "Você não tem permissão para esta operação.",
    });
    expect(negado).toContain("Acesso restrito");
    expect(negado).toContain("Nenhum registro foi gravado localmente.");

    const conflito = renderizar({
      fase: "erro",
      codigo: "CONFLICT",
      mensagem: "Matrícula já utilizada por outro colaborador.",
    });
    expect(conflito).toContain("Conflito ao cadastrar");
    expect(conflito).toContain("Matrícula já utilizada por outro colaborador.");
    expect(escrever).not.toHaveBeenCalled();
  });
});
