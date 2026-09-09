import { describe, expect, it } from "vitest";
import {
  CHAVE_ULTIMA_ORGANIZACAO,
  criarArmazenamentoUltimaOrganizacaoLocal,
  organizacaoEfetiva,
  selecaoValida,
} from "./organizacaoAtiva";
import type { IdentidadeResolvida } from "./tipos";

function identidade(...orgIds: string[]): IdentidadeResolvida {
  return {
    authUserId: "uuid-1",
    perfil: { id: "uuid-1", status: "active" },
    memberships: orgIds.map((organizationId, index) => ({
      id: `m-${index}`,
      organizationId,
      status: "active" as const,
    })),
    organizacoes: orgIds.map((id) => ({ id, name: `Org ${id}` })),
  };
}

function storageFalso(inicial: Record<string, string> = {}) {
  let bruto: string | null = JSON.stringify(inicial);
  return {
    obter() {
      return {
        getItem: () => bruto,
        setItem: (_k: string, v: string) => {
          bruto = v;
        },
        removeItem: () => {
          bruto = null;
        },
      };
    },
    valor: () => bruto,
  };
}

describe("organização ativa (F5-03)", () => {
  it("0 memberships ⇒ sem organização (null)", () => {
    expect(organizacaoEfetiva(identidade(), null)).toBeNull();
  });

  it("1 membership ⇒ organização implícita única (sem seleção)", () => {
    expect(organizacaoEfetiva(identidade("org-a"), null)).toBe("org-a");
  });

  it("N>1 sem seleção ⇒ null (exige seleção)", () => {
    expect(organizacaoEfetiva(identidade("org-a", "org-b"), null)).toBeNull();
  });

  it("N>1 com seleção válida ⇒ a selecionada", () => {
    expect(organizacaoEfetiva(identidade("org-a", "org-b"), "org-b")).toBe("org-b");
  });

  it("seleção inexistente / de outro tenant é ignorada (fail-closed)", () => {
    const identidadeA = identidade("org-a", "org-b");
    expect(selecaoValida(identidadeA, "org-c")).toBe(false);
    expect(organizacaoEfetiva(identidadeA, "org-c")).toBeNull();
    expect(selecaoValida(identidadeA, undefined)).toBe(false);
    expect(selecaoValida(undefined, "org-a")).toBe(false);
  });

  it("seleção persistida que deixou de ser válida é ignorada", () => {
    // persistido org-a, mas a membership de org-a foi revogada:
    // disponíveis = [org-b, org-c] ⇒ org-a não resolve (exige nova seleção)
    expect(organizacaoEfetiva(identidade("org-b", "org-c"), "org-a")).toBeNull();
  });

  it("spoofing via localStorage não vira organização efetiva", () => {
    const identidadeReal = identidade("org-a", "org-b");
    expect(organizacaoEfetiva(identidadeReal, "org-evil")).toBeNull();
    expect(selecaoValida(identidadeReal, "org-evil")).toBe(false);
  });

  it("marcador é persistido por usuário e removido", () => {
    const fake = storageFalso();
    const armazenamento = criarArmazenamentoUltimaOrganizacaoLocal(fake.obter);

    armazenamento.definir("uuid-1", "org-a");
    armazenamento.definir("uuid-2", "org-b");
    expect(armazenamento.ler("uuid-1")).toBe("org-a");
    expect(armazenamento.ler("uuid-2")).toBe("org-b");

    armazenamento.remover("uuid-1");
    expect(armazenamento.ler("uuid-1")).toBeNull();
    expect(armazenamento.ler("uuid-2")).toBe("org-b");

    const persistido = JSON.parse(fake.valor() ?? "{}") as Record<string, string>;
    expect(persistido["uuid-1"]).toBeUndefined();
    expect(persistido["uuid-2"]).toBe("org-b");
  });

  it("JSON corrompido não quebra a leitura (fail-closed, segue em memória)", () => {
    const fake = storageFalso();
    fake.obter().setItem(CHAVE_ULTIMA_ORGANIZACAO, "{corrompido");
    const armazenamento = criarArmazenamentoUltimaOrganizacaoLocal(fake.obter);
    expect(armazenamento.ler("uuid-1")).toBeNull();
  });
});
