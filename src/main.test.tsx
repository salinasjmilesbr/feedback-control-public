import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "./test/localStorageMock";

const { render, createRoot } = vi.hoisted(() => {
  const render = vi.fn();
  return { render, createRoot: vi.fn(() => ({ render })) };
});

// Isola a renderização; o bootstrap e a rotina de reset são os módulos reais.
vi.mock("react-dom/client", () => ({ createRoot }));
vi.mock("./App.tsx", () => ({ default: () => null }));

const chave = "feedback-control-colaboradores";
const marcador = "feedback-control-reset-2026-08-26-base-enxuta-v1";

describe("reset DEV no bootstrap", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();
    instalarLocalStorageEmMemoria();
    localStorage.setItem(chave, "cadastro fictício preservado");
    vi.stubGlobal("document", { getElementById: vi.fn(() => ({})) });
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    render.mockReset();
  });

  it("produção importa e renderiza sem chamar o reset nem modificar dados", async () => {
    vi.stubEnv("DEV", false);
    const reset = await import("./services/resetBaseDesenvolvimento");
    const executar = vi.spyOn(reset, "executarResetBaseDesenvolvimento");
    const remover = vi.spyOn(localStorage, "removeItem");
    const gravar = vi.spyOn(localStorage, "setItem");
    const limpar = vi.spyOn(localStorage, "clear");

    await import("./main");

    expect(executar).not.toHaveBeenCalled();
    expect(remover).not.toHaveBeenCalled();
    expect(gravar).not.toHaveBeenCalled();
    expect(limpar).not.toHaveBeenCalled();
    expect(localStorage.getItem(chave)).toBe("cadastro fictício preservado");
    expect(localStorage.getItem(marcador)).toBeNull();
    expect(createRoot).toHaveBeenCalledOnce();
    expect(render).toHaveBeenCalledOnce();
  });

  it.each([false, true])("DEV preserva a ordem reset/render e o marcador existente: %s", async (jaExecutado) => {
    vi.stubEnv("DEV", true);
    if (jaExecutado) localStorage.setItem(marcador, "ok");
    render.mockImplementation(() => {
      expect(localStorage.getItem(marcador)).toBe("ok");
      expect(localStorage.getItem(chave)).toBe(jaExecutado ? "cadastro fictício preservado" : null);
    });
    const reset = await import("./services/resetBaseDesenvolvimento");
    const executar = vi.spyOn(reset, "executarResetBaseDesenvolvimento");

    await import("./main");

    expect(executar).toHaveBeenCalledOnce();
    expect(render).toHaveBeenCalledOnce();
  });
});
