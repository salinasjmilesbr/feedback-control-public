import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { ExibicaoAvaliacoesSoberanas } from "./ExibicaoAvaliacoesSoberanas.tsx";
import type { EstadoAvaliacoesSoberanas } from "../services/avaliacoesSoberanas/controladorAvaliacoes.ts";

/**
 * F5-06 (Issue #103) — apresentação do acervo soberano.
 *
 * O componente é PURO (recebe o estado pronto), então a renderização de todos os
 * estados é verificável sem DOM de browser, sem efeitos e sem rede. Aqui se
 * comprova o contrato visual mínimo: carregando, erro, vazio, item do banco com
 * estado real e acervo legado sempre marcado como NÃO editável.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";
const AVALIACAO = "22222222-2222-4222-8222-222222222222";
const COLABORADOR = "44444444-4444-4444-8444-444444444444";

function estado(
  parcial: Partial<EstadoAvaliacoesSoberanas> = {}
): EstadoAvaliacoesSoberanas {
  return {
    carregando: false,
    erro: null,
    acervo: null,
    avaliacaoSelecionada: null,
    ...parcial,
  };
}

function acervo(parcial: {
  readonly avaliacoes?: readonly unknown[];
  readonly legado?: readonly unknown[];
  readonly avisoLegado?: string | null;
} = {}) {
  return {
    organizationId: ORG,
    cycleId: CICLO,
    avaliacoes: (parcial.avaliacoes ?? []) as never,
    legado: (parcial.legado ?? []) as never,
    avisoLegado: parcial.avisoLegado ?? null,
  };
}

describe("exibição do acervo soberano de avaliações", () => {
  it("mostra o estado de carregamento", () => {
    const html = renderToStaticMarkup(
      <ExibicaoAvaliacoesSoberanas estado={estado({ carregando: true })} />
    );
    expect(html).toContain("Carregando avaliações");
    expect(html).toContain('aria-busy="true"');
  });

  it("mostra o erro público em região de alerta", () => {
    const html = renderToStaticMarkup(
      <ExibicaoAvaliacoesSoberanas
        estado={estado({ erro: "Você não tem permissão para esta operação nesta avaliação." })}
      />
    );
    expect(html).toContain('role="alert"');
    expect(html).toContain("não tem permissão");
  });

  it("mostra o vazio quando não há avaliação nova no ciclo", () => {
    const html = renderToStaticMarkup(
      <ExibicaoAvaliacoesSoberanas estado={estado({ acervo: acervo() as never })} />
    );
    expect(html).toContain("Nenhuma avaliação nova neste ciclo");
  });

  it("mostra a avaliação do banco com o estado real e a marca de editabilidade", () => {
    const html = renderToStaticMarkup(
      <ExibicaoAvaliacoesSoberanas
        estado={estado({
          acervo: acervo({
            avaliacoes: [
              {
                origem: "POSTGRES",
                editavel: true,
                avaliacao: {
                  id: AVALIACAO,
                  organizationId: ORG,
                  cycleId: CICLO,
                  evaluatedCollaboratorId: COLABORADOR,
                  status: "RASCUNHO",
                  notaMedia: 3.66666667,
                  dataConclusao: null,
                  encerradaComPendencias: false,
                },
              },
            ],
          }) as never,
        })}
      />
    );
    expect(html).toContain("RASCUNHO");
    expect(html).toContain("3.66666667");
    expect(html).toContain('data-editavel="sim"');
  });

  it("avaliação CONCLUIDA aparece como NÃO editável (estado real do domínio)", () => {
    const html = renderToStaticMarkup(
      <ExibicaoAvaliacoesSoberanas
        estado={estado({
          acervo: acervo({
            avaliacoes: [
              {
                origem: "POSTGRES",
                editavel: false,
                avaliacao: {
                  id: AVALIACAO,
                  organizationId: ORG,
                  cycleId: CICLO,
                  evaluatedCollaboratorId: COLABORADOR,
                  status: "CONCLUIDA",
                  notaMedia: 4.1,
                  dataConclusao: "2026-02-01T10:00:00Z",
                  encerradaComPendencias: false,
                },
              },
            ],
          }) as never,
        })}
      />
    );
    expect(html).toContain("CONCLUIDA");
    expect(html).toContain('data-editavel="nao"');
  });

  it("acervo legado é exibido SEPARADO e sempre sem edição, com o aviso", () => {
    const html = renderToStaticMarkup(
      <ExibicaoAvaliacoesSoberanas
        estado={estado({
          acervo: acervo({
            legado: [
              {
                origem: "LEGADO_LOCAL",
                editavel: false,
                motivo: "Avaliações criadas antes do cutover permanecem em modo legado (somente leitura).",
                registro: { id: "legado-1" },
              },
            ],
            avisoLegado:
              "Avaliações criadas antes do cutover permanecem em modo legado (somente leitura).",
          }) as never,
        })}
      />
    );
    expect(html).toContain("Avaliações legadas (somente leitura)");
    expect(html).toContain('data-testid="acervo-legado"');
    expect(html).toContain('data-testid="legado-item" data-editavel="nao"');
  });
});
