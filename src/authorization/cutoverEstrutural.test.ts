/**
 * F5-08 P6 — TESTES DO CUTOVER ESTRUTURAL (autoridade local removida).
 *
 * Prova, em RUNTIME, que fora do contexto DEV do Vite:
 *
 * 1. a decisão de autorização do cliente NÃO resolve ator/mundo pelo cadastro
 *    legado em `localStorage` (nem pela fixture DEV de `src/data/colaboradores`):
 *    sem mundo explícito ⇒ DENY (fail-closed);
 * 2. o mundo funcional (gestão/coordenação/colegiado) NÃO deriva bindings da
 *    estrutura local: sem binding EXPLÍCITO (teste) ou vindo da projeção
 *    soberana, a capability é NEGADA — inclusive o fluxo SELF, porque o ator só
 *    existe na projeção soberana;
 * 3. o caminho SOBERANO continua funcionando: com mundo + bindings explícitos a
 *    decisão volta a ser ALLOW (o gate não é bloqueio cego);
 * 4. o contexto DEV do Vite mantém as fixtures fictícias atrás do gate
 *    explicitamente documentado, sem que elas valham em produção.
 *
 * Consequência registrada do cutover: enquanto a projeção soberana não alimentar
 * o mundo funcional do cliente, a UX gated por `can()` fica fail-closed em
 * produção (a decisão REAL é sempre server-side). Ver
 * `docs/F5-08-p6-duvida-mundo-funcional.md`.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { Colaborador } from "../types/Colaborador";
import type { AuthorizationContext } from "./AuthorizationContext";

const ORG = "organizacao-sintetica-local";

function contextoDo(colaborador: Colaborador): AuthorizationContext {
  return {
    actor: {
      matricula: colaborador.matricula,
      funcao: colaborador.funcao,
      status: colaborador.status,
    },
  };
}

/** Carrega os módulos num contexto de PRODUÇÃO (fora do gate DEV). */
async function carregarProducao() {
  vi.stubEnv("DEV", false);
  vi.stubEnv("PROD", true);
  vi.stubEnv("VITE_APP_ENV", "production");
  const politica = await import("./authorizationPolicy");
  const mundo = await import("./mundoFuncional");
  const legado = await import("../services/colaboradorStorage");
  const erros = await import("./authorizationError");
  return { politica, mundo, legado, AuthorizationError: erros.AuthorizationError };
}

/** Carrega os módulos no contexto DEV do Vite (fixtures fictícias). */
async function carregarDev() {
  vi.stubEnv("DEV", true);
  vi.stubEnv("PROD", false);
  vi.stubEnv("VITE_APP_ENV", "development");
  const politica = await import("./authorizationPolicy");
  const mundo = await import("./mundoFuncional");
  const legado = await import("../services/colaboradorStorage");
  return { politica, mundo, legado };
}

beforeEach(() => {
  vi.resetModules();
  instalarLocalStorageEmMemoria();
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

/**
 * Os casos abaixo reimportam o grafo de módulos em contexto de produção
 * (`resetModules` + `stubEnv`), o que é custoso; o limite explícito evita
 * flakiness sob carga paralela da suíte completa.
 */
describe(
  "F5-08 P6 — produção: nenhuma autoridade estrutural local",
  { timeout: 20000 },
  () => {
  it("a fixture/cadastro legado EXISTE, mas NÃO resolve o mundo (DENY com e sem mundo explícito)", async () => {
    const { politica, legado } = await carregarProducao();
    const seed = legado.getColaboradores();
    const raiz = seed.find(
      (item) => !item.gestorDiretoMatricula && item.status === "ATIVO"
    );
    expect(seed.length).toBeGreaterThan(0);
    expect(raiz).toBeDefined();
    if (!raiz) return;

    // O legado não é fallback: sem mundo explícito a decisão é DENY…
    expect(politica.can(contextoDo(raiz), "settings.manage", { kind: "global" })).toBe(
      false
    );
    expect(politica.can(contextoDo(raiz), "cycle.read", { kind: "global" })).toBe(false);

    // …e o mundo explícito, sozinho, também não concede: as CAPABILITIES do ator
    // passam a vir da projeção soberana (binding), não da estrutura local.
    expect(
      politica.can(contextoDo(raiz), "settings.manage", {
        kind: "global",
        collaborators: seed,
      })
    ).toBe(false);
  });

  it("authorize lança AuthorizationError sem mundo (fail-closed)", async () => {
    const { politica, legado, AuthorizationError } = await carregarProducao();
    const raiz = legado
      .getColaboradores()
      .find((item) => !item.gestorDiretoMatricula && item.status === "ATIVO");
    expect(raiz).toBeDefined();
    if (!raiz) return;

    expect(() =>
      politica.authorize(contextoDo(raiz), "settings.manage", { kind: "global" })
    ).toThrow(AuthorizationError);
  });

  it("o mundo funcional não deriva bindings de gestão da estrutura local", async () => {
    const { mundo, legado } = await carregarProducao();
    const seed = legado.getColaboradores();
    const raiz = seed.find(
      (item) => !item.gestorDiretoMatricula && item.status === "ATIVO"
    );
    const coordenador = seed.find((item) => item.gestorDiretoMatricula);
    expect(raiz).toBeDefined();
    if (!raiz) return;

    const providers = mundo.criarProvidersMundoFuncional({
      actor: raiz,
      colaboradores: seed,
    });

    // Gestão/coordenação/colegiado NEGADOS sem binding explícito.
    expect(providers.capabilities.hasCapability("1", ORG, "settings.manage")).toBe(false);
    expect(providers.capabilities.hasCapability("1", ORG, "cycle.manage")).toBe(false);
    expect(providers.capabilities.hasCapability("1", ORG, "evaluation.write")).toBe(false);
    if (coordenador) {
      const doCoordenador = mundo.criarProvidersMundoFuncional({
        actor: coordenador,
        colaboradores: seed,
      });
      expect(
        doCoordenador.capabilities.hasCapability("1", ORG, "evaluation.create")
      ).toBe(false);
    }
    // Nem o fluxo SELF: o próprio ator só existe na projeção soberana.
    expect(providers.capabilities.hasCapability("1", ORG, "goal.write")).toBe(false);
    // O scope isolado não concede nada — o engine exige capability E scope.
    expect(providers.scopes.getActiveScopes("1", ORG, "goal.write")).toEqual(["SELF"]);
    expect(mundo.SEM_BINDINGS_DEV.size).toBe(0);
  });

  it("com mundo + binding EXPLÍCITOS o caminho soberano volta a decidir ALLOW", async () => {
    const { mundo, legado } = await carregarProducao();
    const seed = legado.getColaboradores();
    const raiz = seed.find(
      (item) => !item.gestorDiretoMatricula && item.status === "ATIVO"
    );
    expect(raiz).toBeDefined();
    if (!raiz) return;

    const providers = mundo.criarProvidersMundoFuncional({
      actor: raiz,
      colaboradores: seed,
      bindingsDev: mundo.derivarBindingsDev(seed),
    });

    const atorId = String(raiz.matricula);
    expect(providers.capabilities.hasCapability(atorId, ORG, "settings.manage")).toBe(
      true
    );
    expect(providers.identity.isMembershipActive(atorId, ORG)).toBe(true);
    expect(
      providers.targets.resolveTargetTenant({ type: "collaborator", id: atorId })
    ).toBe(ORG);
  });
});

describe("F5-08 P6 — DEV: fixtures continuam atrás do gate explícito", () => {
  it("no contexto DEV a fixture fictícia alimenta o mundo (comportamento documentado)", async () => {
    const { politica, mundo, legado } = await carregarDev();
    const seed = legado.getColaboradores();
    const raiz = seed.find(
      (item) => !item.gestorDiretoMatricula && item.status === "ATIVO"
    );
    expect(raiz).toBeDefined();
    if (!raiz) return;

    expect(politica.can(contextoDo(raiz), "settings.manage", { kind: "global" })).toBe(
      true
    );

    const providers = mundo.criarProvidersMundoFuncional({
      actor: raiz,
      colaboradores: seed,
    });
    expect(providers.capabilities.hasCapability("1", ORG, "settings.manage")).toBe(true);
  });
});
