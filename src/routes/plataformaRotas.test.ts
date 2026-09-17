import { describe, expect, it } from "vitest";
import type { EstadoSessao } from "../auth/controladorSessao";
import {
  ROTA_PLATAFORMA_NOVA_ORGANIZACAO,
  decidirAcessoARotaDePlataforma,
  type DecisaoRotaPlataforma,
} from "./plataformaRotas";

/**
 * F6-A03 (Issue #266) — guard da rota de plataforma (D19).
 *
 * Prova a decisão para os NOVE estados de sessão, com destaque para a exceção
 * DELIBERADA de `acessoNegado` (o plano de plataforma não depende da resolução
 * de identidade de TENANT — §3 B5) e para o bloqueio fail-closed de
 * `sessaoIndisponivel`/`indisponivel`.
 */

const sessao = { usuario: { id: "uuid-operador", email: "operador@example.invalid" } };
const identidade = {
  authUserId: "uuid-operador",
  perfil: { id: "uuid-operador", status: "active" as const },
  memberships: [],
  organizacoes: [],
};

const ESTADOS: readonly (readonly [EstadoSessao, DecisaoRotaPlataforma["tipo"]])[] = [
  [{ status: "verificando" }, "carregando"],
  [{ status: "autenticado", sessao, identidade }, "permitir"],
  [{ status: "semOrganizacao", sessao, identidade }, "permitir"],
  [{ status: "aguardandoSelecao", sessao, identidade }, "permitir"],
  [
    { status: "acessoNegado", erro: { code: "ACCESS_NOT_PROVISIONED", category: "authentication", message: "x" } },
    "permitir",
  ],
  [{ status: "naoAutenticado" }, "redirecionarLogin"],
  [{ status: "sessaoExpirada", motivo: "inatividade" }, "redirecionarLogin"],
  [{ status: "sessaoExpirada", motivo: "duracaoMaxima" }, "redirecionarLogin"],
  [{ status: "sessaoIndisponivel" }, "bloquear"],
  [{ status: "indisponivel" }, "bloquear"],
];

describe("F6-A03 — guard de plataforma: decisão por estado", () => {
  it("decide os nove estados de sessão", () => {
    expect(ESTADOS).toHaveLength(10);
    for (const [estado, esperado] of ESTADOS) {
      expect(decidirAcessoARotaDePlataforma(estado).tipo, estado.status).toBe(esperado);
    }
  });

  it("admite `semOrganizacao` e `acessoNegado` (alcançabilidade no ambiente virgem)", () => {
    for (const estado of ESTADOS.filter(
      ([, esperado]) => esperado === "permitir"
    ).map(([estado]) => estado)) {
      expect(decidirAcessoARotaDePlataforma(estado).tipo).toBe("permitir");
    }
    // Os quatro estados de sessão VIVA são exatamente os admitidos.
    expect(
      ESTADOS.filter(([, esperado]) => esperado === "permitir").map(([estado]) => estado.status)
    ).toEqual(["autenticado", "semOrganizacao", "aguardandoSelecao", "acessoNegado"]);
  });

  it("bloqueia fail-closed quando a sessão não é confirmável", () => {
    expect(decidirAcessoARotaDePlataforma({ status: "sessaoIndisponivel" }).tipo).toBe("bloquear");
    expect(decidirAcessoARotaDePlataforma({ status: "indisponivel" }).tipo).toBe("bloquear");
  });

  it("não redireciona para login quem tem sessão viva", () => {
    const redireciona = ESTADOS.filter(([, esperado]) => esperado === "redirecionarLogin").map(
      ([estado]) => estado.status
    );
    expect(redireciona).toEqual(["naoAutenticado", "sessaoExpirada", "sessaoExpirada"]);
  });
});

describe("F6-A03 — guard de plataforma: rota", () => {
  it("a rota é a única superfície da UI mínima de plataforma (D21)", () => {
    expect(ROTA_PLATAFORMA_NOVA_ORGANIZACAO).toBe("/plataforma/nova-organizacao");
  });
});
