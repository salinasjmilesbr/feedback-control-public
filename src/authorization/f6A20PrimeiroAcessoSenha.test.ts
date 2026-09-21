/// <reference types="node" />
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * F6-A20 (Issue #321) — guardas estáticas da conclusão do primeiro acesso.
 *
 * O que estas guardas impedem de voltar (auditoria do SHA d538862):
 * 1. limpar `first_access_pending` ANTES de a senha estar escrita (concederia
 *    acesso com senha não definida e tornaria o retry impossível);
 * 2. UPDATE sem PROVA de linha alterada (responder `completed` sem prova
 *    soberana de conclusão);
 * 3. marcar a pendência como `true` na fronteira (o estado do onboarding não é
 *    restaurado por aqui);
 * 4. tocar roles, capabilities, memberships ou tenant;
 * 5. depender de URL, `localStorage` ou estado de tela para retomar o fluxo.
 *
 * A leitura é feita do disco para que a guarda valha sobre a fonte real.
 */

const RAIZ = fileURLToPath(new URL("../..", import.meta.url));

function fonte(caminho: string): string {
  return readFileSync(join(RAIZ, caminho), "utf8");
}

/** Visão de CÓDIGO do TypeScript: comentários de linha e de bloco fora. */
function semComentariosTs(conteudo: string): string {
  return conteudo
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/(^|[^:])\/\/[^\n]*/g, "$1");
}

const EDGE = "supabase/functions/concluir-primeiro-acesso/index.ts";
const CORE = "supabase/functions/concluir-primeiro-acesso/core.ts";

describe("F6-A20 — ordem e prova do ponto de commit", () => {
  const edge = semComentariosTs(fonte(EDGE));

  it("escreve a senha no Auth ANTES de limpar a pendência e só então conclui", () => {
    const posicaoSenha = edge.indexOf("updateUserById");
    const posicaoCommit = edge.indexOf("first_access_pending: false");
    const posicaoSucesso = edge.indexOf("completed: true");

    expect(posicaoSenha).toBeGreaterThan(-1);
    expect(posicaoCommit).toBeGreaterThan(-1);
    expect(posicaoSucesso).toBeGreaterThan(-1);
    expect(posicaoSenha).toBeLessThan(posicaoCommit);
    expect(posicaoCommit).toBeLessThan(posicaoSucesso);
  });

  it("o UPDATE prova a linha alterada (predicado de pendência + representação)", () => {
    expect(edge).toContain('.eq("first_access_pending", true)');
    expect(edge).toContain('.select("id")');
  });

  it("a fronteira não marca pendência como true e afirma conclusão uma única vez", () => {
    expect(edge).not.toContain("first_access_pending: true");
    expect((edge.match(/completed: true/g) ?? []).length).toBe(1);
  });

  it("decide por módulo PURO (gate, prova e verificação testáveis)", () => {
    for (const simbolo of [
      "decidirEntradaDoPrimeiroAcesso",
      "decidirConclusaoDoPrimeiroAcesso",
      "linhasAfetadasDoRetorno",
      "pendenciaConfirmada",
    ]) {
      expect(edge, simbolo).toContain(simbolo);
    }
  });

  it("não toca roles, capabilities, memberships nem tenant", () => {
    for (const proibido of ["access_role", "membership", "organization"]) {
      expect(edge, proibido).not.toContain(proibido);
    }
  });

  it("não depende de URL, localStorage ou objeto de janela", () => {
    for (const proibido of ["localStorage", "location", "window."]) {
      expect(edge, proibido).not.toContain(proibido);
    }
  });
});

describe("F6-A20 — o núcleo é puro", () => {
  const core = semComentariosTs(fonte(CORE));

  it("não fala com Auth, banco, rede nem DOM", () => {
    for (const proibido of [
      "Deno.",
      "createClient",
      ".from(",
      ".rpc(",
      "fetch(",
      "localStorage",
      "location",
      "window.",
    ]) {
      expect(core, proibido).not.toContain(proibido);
    }
  });

  it("preserva o ponto de commit como decisão explícita (1 linha = prova)", () => {
    expect(core).toContain("linhasAfetadas === 1");
    expect(core).toContain("estadoConfirmado === false");
  });
});
