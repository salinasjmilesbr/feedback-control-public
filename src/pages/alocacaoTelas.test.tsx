/**
 * F5-08 P5 — testes de RENDER dos pontos de alocação que o P5 adiciona:
 * seletor soberano por POSIÇÃO no Novo colaborador, ações de reporting line na
 * tela de Posições e remoção dos avisos obsoletos "F5-08".
 *
 * Tudo determinístico: a fotografia soberana é semeada (`estruturaInicial`) e o
 * render é estático — nenhuma rede, nenhum relógio real, nenhum localStorage.
 */

import { renderToStaticMarkup } from "react-dom/server";
import type { ReactElement } from "react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { ProvedorAuthTeste } from "../test/authTeste";
import NovoColaboradorPage from "./NovoColaboradorPage";
import PosicoesPage from "./PosicoesPage";
import type { EstadoEstrutura } from "./apoioEstrutura";

const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const POSICAO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const POSICAO_FUTURA = "bfbfbfbf-bfbf-4fbf-8fbf-bfbfbfbfbfbf";
const GESTOR = "bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd";
const REPORTING = "cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd";

/** Posição vigente hoje (`valid_from` no passado, sem término). */
function posicaoVigente(posicaoId: string) {
  return {
    posicaoId,
    unitId: UNIDADE,
    jobRoleId: CARGO,
    seniorityLevelId: null,
    validFrom: "2026-01-01T00:00:00.000Z",
    validTo: null,
    version: 1,
  };
}

function estrutura(parcial: Partial<EstruturaSoberana> = {}): EstruturaSoberana {
  return {
    unidades: [
      {
        unitId: UNIDADE,
        nome: "Unidade Fictícia",
        validFrom: "2026-01-01T00:00:00.000Z",
        validTo: null,
        version: 1,
      },
    ],
    periodosParent: [],
    posicoes: [posicaoVigente(POSICAO), posicaoVigente(GESTOR)],
    reportingLines: [],
    ocupacoes: [],
    cargos: [
      { jobRoleId: CARGO, code: "FICT", nome: "Cargo Fictício", status: "active", version: 1 },
    ],
    senioridades: [],
    colegiados: [],
    colaboradores: [],
    ...parcial,
  };
}

function renderizar(elemento: ReactElement): string {
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <MemoryRouter>{elemento}</MemoryRouter>
    </ProvedorAuthTeste>
  );
}

beforeEach(() => {
  instalarLocalStorageEmMemoria();
});

describe("F5-08 P5 — Novo colaborador: alocação por POSIÇÃO soberana", () => {
  it("oferece o seletor soberano com rótulo unidade • cargo e campos de vigência/motivo", () => {
    const html = renderizar(
      <NovoColaboradorPage
        estruturaInicial={{ fase: "pronto", estrutura: estrutura() }}
        alocacaoInicial
      />
    );

    expect(html).toContain("Alocação (opcional)");
    expect(html).toContain("Alocar este colaborador agora");
    expect(html).toContain("Posição (unidade • cargo • senioridade) *");
    expect(html).toContain("Unidade Fictícia • FICT — Cargo Fictício");
    expect(html).toContain("Vigência da ocupação *");
    expect(html).toContain("Motivo da alocação *");
    expect(html).toContain("Definir também o gestor (reporting line)");
    // O UUID da posição é o valor enviado (identidade), nunca o rótulo.
    expect(html).toContain(`value="${POSICAO}"`);
  });

  it("sem posição VIGENTE a alocação fica indisponível (nada é criado automaticamente)", () => {
    const apenasFutura: EstadoEstrutura = {
      fase: "pronto",
      estrutura: estrutura({
        posicoes: [
          {
            ...posicaoVigente(POSICAO_FUTURA),
            validFrom: "2099-01-01T00:00:00.000Z",
          },
        ],
      }),
    };

    const html = renderizar(<NovoColaboradorPage estruturaInicial={apenasFutura} />);

    expect(html).toContain("Nenhuma posição vigente disponível");
    expect(html).toContain("Nada é criado automaticamente");
    // O checkbox de alocação existe, porém desabilitado (fail-closed de UX).
    expect(html).toContain("Alocar este colaborador agora");
    expect(html).not.toContain(`value="${POSICAO_FUTURA}"`);
  });

  it("quando a fotografia falha, o cadastro continua disponível e a alocação não", () => {
    const html = renderizar(
      <NovoColaboradorPage
        estruturaInicial={{
          fase: "erro",
          codigo: "FORBIDDEN",
          mensagem: "Você não tem permissão para consultar a estrutura organizacional.",
        }}
      />
    );

    expect(html).toContain("Não foi possível carregar as posições");
    expect(html).toContain("FORBIDDEN");
    expect(html).toContain("O cadastro do colaborador continua disponível");
    expect(html).toContain("Salvar colaborador");
  });
});

describe("F5-08 P5 — Posições: reporting line (posição → posição)", () => {
  it("posição vigente oferece Definir/Alterar gestor; a futura não é oferecida", () => {
    const comFutura: EstadoEstrutura = {
      fase: "pronto",
      estrutura: estrutura({
        posicoes: [
          posicaoVigente(POSICAO),
          {
            ...posicaoVigente(POSICAO_FUTURA),
            validFrom: "2099-01-01T00:00:00.000Z",
          },
        ],
      }),
    };

    const html = renderizar(<PosicoesPage estadoInicial={comFutura} />);

    // Apenas a posição VIGENTE oferece a ação de reporting line.
    expect(html.split('data-testid="posicao-gestor-abrir"').length - 1).toBe(1);
    expect(html).toContain("Definir gestor");
    expect(html).toContain("Programada para 01/01/2099");
    expect(html).toContain("sem linha de reporting registrada");
  });

  it("com reporting line vigente mostra o superior e oferece alterar/encerrar", () => {
    const comLinha: EstadoEstrutura = {
      fase: "pronto",
      estrutura: estrutura({
        reportingLines: [
          {
            reportingLineId: REPORTING,
            subordinatePositionId: POSICAO,
            managerPositionId: GESTOR,
            motivo: "cadeia formal fictícia",
            validFrom: "2026-01-01T00:00:00.000Z",
            validTo: null,
            version: 1,
          },
        ],
      }),
    };

    const html = renderizar(<PosicoesPage estadoInicial={comLinha} />);

    expect(html).toContain("superior Unidade Fictícia • FICT — Cargo Fictício");
    expect(html).toContain("Alterar gestor");
  });

  it("a tela não decide ciclo: nenhum texto de validação local de ciclo é emitido", () => {
    const html = renderizar(
      <PosicoesPage estadoInicial={{ fase: "pronto", estrutura: estrutura() }} />
    );

    expect(html).not.toContain("ciclo");
    expect(html).not.toContain("recursão");
  });
});

describe("F5-08 P5 — avisos obsoletos 'F5-08' removidos das telas de alocação", () => {
  it("Novo e Posições não exibem aviso pendente da F5-08", () => {
    const novo = renderizar(
      <NovoColaboradorPage
        estruturaInicial={{ fase: "pronto", estrutura: estrutura() }}
      />
    );
    const posicoes = renderizar(
      <PosicoesPage estadoInicial={{ fase: "pronto", estrutura: estrutura() }} />
    );

    expect(novo).not.toContain("F5-08");
    expect(posicoes).not.toContain("F5-08");
  });
});

describe("F5-08 P5 — depois da criação, a UI não oferece nova criação de pessoa", () => {
  const CRIADO = "22222222-2222-4222-8222-222222222222";

  it("'Salvar colaborador' desaparece; restam apenas ações de estado", () => {
    const html = renderizar(
      <NovoColaboradorPage
        estadoInicial={{ fase: "sucesso", collaboratorId: CRIADO }}
        estruturaInicial={{ fase: "pronto", estrutura: estrutura() }}
        alocacaoInicial
      />
    );

    expect(html).toContain("Colaborador criado no cadastro soberano.");
    expect(html).not.toContain("Salvar colaborador");
    expect(html).toContain("Abrir a ficha do colaborador");
    expect(html).toContain("Ver colaboradores");
    // Os campos de pessoa ficam encerrados (não há nova submissão).
    expect(html).toContain('disabled=""');
  });

  it("estado parcial 'sem-gestor' oferece SOMENTE o retry do gestor", () => {
    const html = renderizar(
      <NovoColaboradorPage
        estadoInicial={{ fase: "sucesso", collaboratorId: CRIADO }}
        estruturaInicial={{ fase: "pronto", estrutura: estrutura() }}
        alocacaoInicial
        alocacaoEstadoInicial={{
          fase: "erro",
          codigo: "FORBIDDEN",
          mensagem: "sem permissão para definir gestor",
          parcial: "sem-gestor",
        }}
      />
    );

    expect(html).toContain("Ocupação criada, gestor NÃO definido");
    expect(html).toContain('data-testid="alocacao-retry-gestor"');
    expect(html).not.toContain('data-testid="alocacao-retry-ocupacao"');
    expect(html).not.toContain("Salvar colaborador");
    expect(html).toContain("Abrir a ficha do colaborador");
  });

  it("estado parcial 'sem-ocupacao' oferece SOMENTE o retry da ocupação", () => {
    const html = renderizar(
      <NovoColaboradorPage
        estadoInicial={{ fase: "sucesso", collaboratorId: CRIADO }}
        estruturaInicial={{ fase: "pronto", estrutura: estrutura() }}
        alocacaoInicial
        alocacaoEstadoInicial={{
          fase: "erro",
          codigo: "FORBIDDEN",
          mensagem: "sem permissão para alocar",
          parcial: "sem-ocupacao",
        }}
      />
    );

    expect(html).toContain("Colaborador criado SEM ALOCAÇÃO");
    expect(html).toContain('data-testid="alocacao-retry-ocupacao"');
    expect(html).not.toContain('data-testid="alocacao-retry-gestor"');
    expect(html).not.toContain("Salvar colaborador");
  });
});
