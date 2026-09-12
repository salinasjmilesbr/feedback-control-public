import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { Colaborador } from "../types/Colaborador";
import NavegacaoPrincipal from "./NavegacaoPrincipal";
import rotasFonte from "../routes/AppRoutes.tsx?raw";

/**
 * Bug #170 (Issue #170) — item "Ciclos" duplicado no menu para Gerente e
 * Coordenador.
 *
 * Causa raiz: `cycle.management.view` e `cycle.coordinator.list` são ALIASES da
 * mesma capability canônica (`cycle.read`, colapso Q1 da F4-09 em
 * `src/authorization/canonical.ts`). As duas condições do menu eram, portanto,
 * o MESMO teste — verdadeiro para todo ator com `cycle.read` (Gerente e
 * Coordenador) — e os dois itens apareciam juntos, ambos rotulados "Ciclos".
 * Antes da centralização F4 os gates eram `funcao === "GERENTE"` e
 * `funcao === "COORDENADOR"` (mutuamente exclusivos), por isso o rótulo
 * repetido nunca aparecia.
 *
 * Invariante protegida aqui: no máximo UM item "Ciclos" por contexto, apontando
 * para a listagem `/ciclos`; os demais itens do menu por perfil permanecem
 * exatamente como estavam (sem regressão). A visibilidade do menu é UX — a
 * autorização real continua no Policy Engine e nos gates das páginas.
 */

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number
): Colaborador {
  return {
    matricula,
    status: "ATIVO",
    nome: `Pessoa ${matricula}`,
    email: `${matricula}@example.com`,
    cargo: funcao ?? "Sem função",
    area: "Área fictícia",
    funcao,
    gestorDiretoMatricula,
    respondePara: "",
  };
}

/**
 * Mundo funcional fictício. Os bindings de papel são derivados da ESTRUTURA
 * (`derivarBindingsDev`: raiz = sem `gestorDiretoMatricula` ⇒ gestão; 1º nível
 * com subordinados ⇒ coordenação; demais ⇒ fluxos próprios), nunca de `funcao`.
 * Por isso a hierarquia abaixo é explícita — quem fica sem gestor vira raiz da
 * cadeia e recebe o conjunto de gestão.
 */
const gerente = pessoa(1, "GERENTE");
const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
const analista = pessoa(3, "ANALISTA", coordenador.matricula);
const consultor = pessoa(4, "CONSULTOR", coordenador.matricula);
const estagiario = pessoa(5, "ESTAGIARIO", coordenador.matricula);
const semFuncao = pessoa(6, undefined, coordenador.matricula);

const mundo = [gerente, coordenador, analista, consultor, estagiario, semFuncao];

function renderizar(usuario: Colaborador): string {
  localStorage.setItem("feedback-control-colaboradores", JSON.stringify(mundo));

  return renderToStaticMarkup(
    <UsuarioAtualContext.Provider
      value={{
        usuarioAtual: usuario,
        usuariosDisponiveis: mundo,
        selecionarUsuario: () => undefined,
      }}
    >
      <MemoryRouter>
        <NavegacaoPrincipal />
      </MemoryRouter>
    </UsuarioAtualContext.Provider>
  );
}

/** Rótulos na ordem do menu (o `<span>` do ícone tem classe e não é rótulo). */
function rotulos(html: string): string[] {
  return Array.from(html.matchAll(/<span>([^<]+)<\/span>/g), (m) => m[1]);
}

/** Destinos dos itens, na ordem do menu. */
function destinos(html: string): string[] {
  return Array.from(html.matchAll(/href="([^"]+)"/g), (m) => m[1]);
}

describe("NavegacaoPrincipal — item 'Ciclos' não pode duplicar (bug #170)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  it.each([
    ["Gerente", gerente],
    ["Coordenador", coordenador],
  ] as const)(
    "%s recebe exatamente UM item 'Ciclos', apontando para /ciclos",
    (_perfil, usuario) => {
      const html = renderizar(usuario);

      expect(rotulos(html).filter((rotulo) => rotulo === "Ciclos")).toHaveLength(
        1
      );
      expect(destinos(html)).toContain("/ciclos");
      expect(destinos(html)).not.toContain("/painel-ciclos");
    }
  );

  it.each([
    ["Analista", analista],
    ["Consultor", consultor],
    ["Estagiário", estagiario],
    ["Sem função", semFuncao],
  ] as const)("%s não recebe item 'Ciclos' (sem acesso a ciclos)", (_perfil, usuario) => {
    expect(rotulos(renderizar(usuario))).not.toContain("Ciclos");
  });

  /**
   * F5-08 P4: a administração de estrutura/catálogo entra no menu. Os itens são
   * VISÍVEIS a qualquer membro ativo porque a LEITURA é own-tenant por RLS e não
   * exige capability (D16); as mutações continuam decididas no servidor. Nenhum
   * item duplica e os demais itens permanecem exatamente como estavam.
   */
  const ITENS_ESTRUTURA = ["Unidades", "Posições", "Colegiado", "Catálogos"];

  it.each([
    ["Gerente", gerente, ["Início", "Ciclos", "Relatórios", ...ITENS_ESTRUTURA, "Configurações"]],
    [
      "Coordenador",
      coordenador,
      ["Início", "Ciclos", "Minhas avaliações", "Minhas metas", "Relatórios", ...ITENS_ESTRUTURA],
    ],
    [
      "Analista",
      analista,
      ["Início", "Minhas avaliações", "Minhas metas", ...ITENS_ESTRUTURA],
    ],
    [
      "Consultor",
      consultor,
      ["Início", "Minhas avaliações", "Minhas metas", ...ITENS_ESTRUTURA],
    ],
    [
      "Estagiário",
      estagiario,
      ["Início", "Minhas avaliações", "Minhas metas", ...ITENS_ESTRUTURA],
    ],
    ["Sem função", semFuncao, ["Início", ...ITENS_ESTRUTURA]],
  ] as const)(
    "menu de %s permanece o esperado (sem regressão nos demais itens)",
    (_perfil, usuario, esperado) => {
      expect(rotulos(renderizar(usuario))).toEqual([...esperado]);
    }
  );

  it("mantém as rotas /ciclos e /painel-ciclos declaradas (correção só de navegação)", () => {
    expect(rotasFonte).toContain('path="/ciclos"');
    expect(rotasFonte).toContain('path="/painel-ciclos"');
  });
});
