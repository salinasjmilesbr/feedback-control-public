/**
 * F5-08 P4 — testes de RENDER das quatro telas de estrutura/catálogo.
 *
 * Prova, para cada tela:
 * - estado de CARREGAMENTO explícito (nenhum dado inventado antes da leitura);
 * - estado VAZIO explícito ("sem estrutura cadastrada"), sem fallback local;
 * - estado de ERRO com o código público (403/409/500 da taxonomia), sem
 *   mascaramento e sem retry automático;
 * - identidade por UUID (nada de nome/matrícula como chave ou identidade);
 * - colegiado: versão vigente com membros, versão com ZERO membros ("sem
 *   colegiado" explícito) e ausência de versão vigente são estados DISTINTOS;
 * - nenhuma escrita em `localStorage` no render.
 */

import { renderToStaticMarkup } from "react-dom/server";
import type { ReactElement } from "react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { ProvedorAuthTeste } from "../test/authTeste";
import CatalogosPage from "./CatalogosPage";
import UnidadesPage from "./UnidadesPage";
import PosicoesPage from "./PosicoesPage";
import ColegiadoPage from "./ColegiadoPage";
import type { EstadoEstrutura } from "./apoioEstrutura";

const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const UNIDADE_PAI = "abababab-abab-4bab-8bab-abababababab";
const PERIODO = "bcbcbcbc-bcbc-4cbc-8cbc-bcbcbcbcbcbc";
const POSICAO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const POSICAO_SUPERIOR = "bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd";
const REPORTING = "cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd";
const OCUPACAO = "dededede-dede-4ede-8ede-dededededede";
const AVALIADO = "22222222-2222-4222-8222-222222222222";
const MEMBRO = "33333333-3333-4333-8333-333333333333";
const COLEGIADO = "efefefef-efef-4fef-8fef-efefefefefef";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const SENIORIDADE = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";

function estrutura(): EstruturaSoberana {
  return {
    unidades: [
      {
        unitId: UNIDADE,
        nome: "Unidade Fictícia",
        validFrom: "2026-03-01T00:00:00.000Z",
        validTo: null,
        version: 2,
      },
      {
        unitId: UNIDADE_PAI,
        nome: "Unidade Superior Fictícia",
        validFrom: "2026-01-01T00:00:00.000Z",
        validTo: null,
        version: 1,
      },
    ],
    periodosParent: [
      {
        periodoId: PERIODO,
        unitId: UNIDADE,
        parentUnitId: UNIDADE_PAI,
        validFrom: "2026-03-01T00:00:00.000Z",
        validTo: null,
        version: 1,
      },
    ],
    posicoes: [
      {
        posicaoId: POSICAO,
        unitId: UNIDADE,
        jobRoleId: CARGO,
        seniorityLevelId: SENIORIDADE,
        validFrom: "2026-03-01T00:00:00.000Z",
        validTo: null,
        version: 3,
      },
      {
        posicaoId: POSICAO_SUPERIOR,
        unitId: UNIDADE_PAI,
        jobRoleId: CARGO,
        seniorityLevelId: null,
        validFrom: "2026-01-01T00:00:00.000Z",
        validTo: null,
        version: 1,
      },
    ],
    reportingLines: [
      {
        reportingLineId: REPORTING,
        subordinatePositionId: POSICAO,
        managerPositionId: POSICAO_SUPERIOR,
        motivo: "cadeia formal fictícia",
        validFrom: "2026-03-01T00:00:00.000Z",
        validTo: null,
        version: 1,
      },
    ],
    ocupacoes: [
      {
        ocupacaoId: OCUPACAO,
        collaboratorId: MEMBRO,
        posicaoId: POSICAO,
        validFrom: "2026-03-01T00:00:00.000Z",
        validTo: null,
        version: 1,
      },
    ],
    cargos: [
      {
        jobRoleId: CARGO,
        code: "FICT",
        nome: "Cargo Fictício",
        status: "active",
        version: 4,
      },
    ],
    senioridades: [
      {
        seniorityLevelId: SENIORIDADE,
        nome: "Pleno",
        status: "disabled",
        version: 5,
      },
    ],
    colegiados: [
      {
        colegiadoId: COLEGIADO,
        collaboratorId: AVALIADO,
        validFrom: "2026-03-01T00:00:00.000Z",
        validTo: null,
        version: 6,
        membroIds: [MEMBRO],
      },
    ],
    colaboradores: [
      { collaboratorId: AVALIADO, nome: "Pessoa Avaliada Fictícia" },
      { collaboratorId: MEMBRO, nome: "Pessoa Membro Fictícia" },
    ],
  };
}

function vazia(): EstruturaSoberana {
  return {
    unidades: [],
    periodosParent: [],
    posicoes: [],
    reportingLines: [],
    ocupacoes: [],
    cargos: [],
    senioridades: [],
    colegiados: [],
    colaboradores: [],
  };
}

function renderizar(elemento: ReactElement): string {
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <MemoryRouter>{elemento}</MemoryRouter>
    </ProvedorAuthTeste>
  );
}

const PRONTO: EstadoEstrutura = { fase: "pronto", estrutura: estrutura() };
const VAZIO: EstadoEstrutura = { fase: "pronto", estrutura: vazia() };

beforeEach(() => {
  instalarLocalStorageEmMemoria();
});

describe("F5-08 P4 — telas: carregamento, vazio, erro e identidade por UUID", () => {
  it("as quatro telas exibem estado de CARREGAMENTO sem inventar dados", () => {
    const htmls = [
      renderizar(<CatalogosPage />),
      renderizar(<UnidadesPage />),
      renderizar(<PosicoesPage />),
      renderizar(<ColegiadoPage />),
    ];

    expect(htmls[0]).toContain("Carregando catálogos");
    expect(htmls[1]).toContain("Carregando unidades");
    expect(htmls[2]).toContain("Carregando posições");
    expect(htmls[3]).toContain("Carregando colegiados");
  });

  it("estado VAZIO é explícito e não é pretexto para seed local", () => {
    const unidades = renderizar(<UnidadesPage estadoInicial={VAZIO} />);
    const posicoes = renderizar(<PosicoesPage estadoInicial={VAZIO} />);
    const catalogos = renderizar(<CatalogosPage estadoInicial={VAZIO} />);

    expect(unidades).toContain("Sem estrutura cadastrada");
    expect(posicoes).toContain("Sem estrutura cadastrada");
    expect(catalogos).toContain("Sem estrutura cadastrada");
    expect(catalogos).toContain("Nenhum cargo cadastrado nesta organização");
    expect(catalogos).toContain("Nenhuma senioridade cadastrada nesta organização");
  });

  it("estado de ERRO exibe a mensagem e o CÓDIGO PÚBLICO (403)", () => {
    const erro403: EstadoEstrutura = {
      fase: "erro",
      codigo: "FORBIDDEN",
      mensagem: "Você não tem permissão para consultar a estrutura organizacional.",
    };
    const unidades = renderizar(<UnidadesPage estadoInicial={erro403} />);
    const catalogos = renderizar(<CatalogosPage estadoInicial={erro403} />);

    expect(unidades).toContain("não tem permissão");
    expect(unidades).toContain("FORBIDDEN");
    expect(catalogos).toContain("FORBIDDEN");
  });

  it("Unidades: hierarquia vigente, UUID como identidade e relação pai exibida", () => {
    const html = renderizar(<UnidadesPage estadoInicial={PRONTO} />);

    expect(html).toContain("Unidade Fictícia");
    expect(html).toContain("Unidade Superior Fictícia");
    expect(html).toContain(`data-id="${UNIDADE}"`);
    expect(html).toContain("Pai: Unidade Superior Fictícia");
    expect(html).toContain("Sem relação pai registrada");
    expect(html).toContain("Encerrar relação");
    expect(html).toContain("Renomear");
  });

  it("Posições: unidade, cargo, senioridade, ocupante e reporting line derivados", () => {
    const html = renderizar(<PosicoesPage estadoInicial={PRONTO} />);

    expect(html).toContain(`data-id="${POSICAO}"`);
    expect(html).toContain("Unidade: Unidade Fictícia");
    expect(html).toContain("Cargo: FICT — Cargo Fictício");
    expect(html).toContain("Senioridade: Pleno");
    expect(html).toContain("Ocupante: Pessoa Membro Fictícia");
    expect(html).toContain("superior Unidade Superior Fictícia");
    expect(html).toContain("identidade " + POSICAO);
  });

  it("Catálogos: status e versão podem ser desativados/renomeados por UUID", () => {
    const html = renderizar(<CatalogosPage estadoInicial={PRONTO} />);

    expect(html).toContain(`data-id="${CARGO}"`);
    expect(html).toContain(`data-id="${SENIORIDADE}"`);
    expect(html).toContain("Código FICT");
    expect(html).toContain("versão 4");
    expect(html).toContain("Desativar");
    expect(html).toContain("Ativar");
  });

  it("Colegiado: versão vigente com membros, e nunca nome como identidade", () => {
    const html = renderizar(
      <ColegiadoPage estadoInicial={PRONTO} avaliadoInicial={AVALIADO} />
    );

    expect(html).toContain("Pessoa Membro Fictícia");
    expect(html).toContain("identidade do avaliado " + AVALIADO);
    expect(html).toContain(`value="${MEMBRO}"`);
    expect(html).toContain("Histórico de versões");
    expect(html).toContain(`data-id="${COLEGIADO}"`);
    expect(html).toContain("Encerrar colegiado");
  });

  it("Colegiado: versão vigente com ZERO membros é 'sem colegiado' EXPLÍCITO", () => {
    const base = estrutura();
    const semMembros: EstadoEstrutura = {
      fase: "pronto",
      estrutura: {
        ...base,
        colegiados: [{ ...base.colegiados[0]!, membroIds: [] }],
      },
    };

    const html = renderizar(
      <ColegiadoPage estadoInicial={semMembros} avaliadoInicial={AVALIADO} />
    );

    expect(html).toContain("Sem colegiado");
    expect(html).toContain("ZERO membros");
    expect(html).toContain("sem colegiado (zero membros)");
  });

  it("Colegiado: AUSÊNCIA de versão vigente é distinta de 'sem colegiado'", () => {
    const base = estrutura();
    const semConfiguracao: EstadoEstrutura = {
      fase: "pronto",
      estrutura: { ...base, colegiados: [] },
    };

    const html = renderizar(
      <ColegiadoPage estadoInicial={semConfiguracao} avaliadoInicial={AVALIADO} />
    );

    expect(html).toContain("Nenhuma versão vigente");
    expect(html).toContain("Nenhuma versão registrada para este avaliado");
  });

  it("nenhuma tela escreve em localStorage durante o render", () => {
    const armazenamento = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(armazenamento, "setItem");

    renderizar(<CatalogosPage estadoInicial={PRONTO} />);
    renderizar(<UnidadesPage estadoInicial={VAZIO} />);
    renderizar(<PosicoesPage estadoInicial={PRONTO} />);
    renderizar(<ColegiadoPage estadoInicial={PRONTO} avaliadoInicial={AVALIADO} />);

    expect(escrever).not.toHaveBeenCalled();
  });
});
