import { describe, expect, it } from "vitest";
import type { AuthIdentity } from "../auth/tipos.ts";
import type { Capability } from "./Capability.ts";
import {
  avaliarOperacaoAutorizacao,
  type DepsContextoAutorizacao,
} from "./contextoAutorizacao.ts";
import type { DomainStateProbe, TargetRef } from "./policyEngine/types.ts";
import type { RecursoSoberanoCarregado } from "./resourceContextReal.ts";

/**
 * F5-09 P6 (§8, D8, D20, D21) — CICLO na FRONTEIRA SOBERANA.
 *
 * Prova, com o Policy Engine REAL (não mockado) e dependências soberanas
 * sintéticas, que a autorização de ciclo:
 *   - usa o TARGET REAL (`{type:"cycle", id: UUID}` de `evaluation_cycles.id`);
 *   - deriva o `domainState` da LINHA SOBERANA carregada, nunca de estado
 *     declarado pelo chamador;
 *   - nega alvo sintético (`{type:"cycle", id:"global"}`) e rótulo inválido;
 *   - nega tenant divergente, membership ausente/revogada, perfil inativo, ator
 *     inexistente, capability ausente/revogada e scope insuficiente;
 *   - não é afetada por cargo/função textual.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const USER = "33333333-3333-4333-8333-333333333333";
const COLABORADOR = "44444444-4444-4444-8444-444444444444";
const CICLO = "55555555-5555-4555-8555-555555555555";

interface Cenario {
  /** Capability da OPERAÇÃO avaliada. */
  readonly capability?: Capability;
  /** Capabilities efetivas do ator (resolver da F5-04) — revogada = ausente. */
  readonly capabilitiesAtor?: readonly Capability[];
  readonly scopes?: readonly string[];
  /** Status SOBERANO da linha `evaluation_cycles`. */
  readonly status?: string;
  readonly recurso?: RecursoSoberanoCarregado | null;
  readonly membership?: "active" | "revoked";
  readonly perfil?: "active" | "disabled";
  readonly identidadeNula?: boolean;
  readonly alvo?: TargetRef;
  /** Estado DECLARADO pelo chamador (o browser nunca declara estado soberano). */
  readonly domainStateDeclarado?: DomainStateProbe;
}

function identidade(cenario: Cenario): AuthIdentity | null {
  if (cenario.identidadeNula) return null;
  return {
    authUserId: USER,
    perfil: { id: USER, status: cenario.perfil ?? "active" },
    memberships: [
      { id: "m-1", organizationId: ORG, status: cenario.membership ?? "active" },
    ],
    organizacoes: [{ id: ORG, name: "Org sintetica" }],
  } as unknown as AuthIdentity;
}

function fronteira(
  cenario: Cenario,
  alvosCarregados: TargetRef[]
): DepsContextoAutorizacao {
  const recurso =
    cenario.recurso === undefined
      ? ({
          kind: "cycle",
          id: CICLO,
          organizationId: ORG,
          status: cenario.status ?? "ATIVO",
        } as RecursoSoberanoCarregado)
      : cenario.recurso;

  return {
    agora: () => new Date("2026-03-01T12:00:00Z"),
    resolverIdentidade: async () => identidade(cenario),
    resolverColaboradorVinculado: async () => COLABORADOR,
    resolverCapabilitiesEscopos: async () =>
      (cenario.capabilitiesAtor ?? ["cycle.read"]).map((capability) => ({
        capability,
        scopes: (cenario.scopes ?? ["ORGANIZATION"]) as never,
      })),
    resolverAlvosEscopo: async () => [],
    carregarRecurso: async ({ target }) => {
      alvosCarregados.push(target);
      return recurso;
    },
  };
}

async function decidir(cenario: Cenario = {}) {
  const alvosCarregados: TargetRef[] = [];
  const decisao = await avaliarOperacaoAutorizacao(
    {
      authUserId: USER,
      organizationId: ORG,
      capability: cenario.capability ?? "cycle.read",
      alvo: cenario.alvo ?? { type: "cycle", id: CICLO },
      ...(cenario.domainStateDeclarado
        ? { domainState: cenario.domainStateDeclarado }
        : {}),
    },
    fronteira(cenario, alvosCarregados)
  );
  return { decisao, alvosCarregados };
}

const DECLARA_TUDO_PERMITIDO: DomainStateProbe = { allows: () => true };

describe("F5-09 P6 — ciclo na fronteira soberana (target real + estado da linha)", () => {
  it("cycle.read usa o UUID canônico como alvo REAL e permite ciclo do tenant", async () => {
    const { decisao, alvosCarregados } = await decidir({ capability: "cycle.read" });

    expect(decisao.allowed).toBe(true);
    // O recurso é carregado pelo alvo REAL: UUID canônico do ciclo.
    expect(alvosCarregados).toEqual([{ type: "cycle", id: CICLO }]);
  });

  it("cycle.read permanece permitido em ciclo CANCELADO (transparência, sem mutação)", async () => {
    const { decisao } = await decidir({ capability: "cycle.read", status: "CANCELADO" });
    expect(decisao.allowed).toBe(true);
  });

  it("cycle.manage: PLANEJADO/ATIVO permitem; ENCERRADO/CANCELADO negam pelo domínio", async () => {
    const planejado = await decidir({
      capability: "cycle.manage",
      capabilitiesAtor: ["cycle.manage"],
      status: "PLANEJADO",
    });
    expect(planejado.decisao.allowed).toBe(true);

    const ativo = await decidir({
      capability: "cycle.manage",
      capabilitiesAtor: ["cycle.manage"],
      status: "ATIVO",
    });
    expect(ativo.decisao.allowed).toBe(true);

    for (const status of ["ENCERRADO", "CANCELADO"]) {
      const { decisao } = await decidir({
        capability: "cycle.manage",
        capabilitiesAtor: ["cycle.manage"],
        status,
      });
      expect(decisao.allowed).toBe(false);
      expect(decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    }
  });

  it("cycle.cancel: PLANEJADO e ATIVO permitem (D8); ENCERRADO e CANCELADO negam", async () => {
    for (const status of ["PLANEJADO", "ATIVO"]) {
      const { decisao } = await decidir({
        capability: "cycle.cancel",
        capabilitiesAtor: ["cycle.cancel"],
        status,
      });
      expect(decisao.allowed).toBe(true);
    }

    for (const status of ["ENCERRADO", "CANCELADO"]) {
      const { decisao } = await decidir({
        capability: "cycle.cancel",
        capabilitiesAtor: ["cycle.cancel"],
        status,
      });
      expect(decisao.allowed).toBe(false);
      expect(decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    }
  });

  it("cycle.reopen: somente ENCERRADO permite", async () => {
    for (const status of ["PLANEJADO", "ATIVO", "ENCERRADO", "CANCELADO"]) {
      const { decisao } = await decidir({
        capability: "cycle.reopen",
        capabilitiesAtor: ["cycle.reopen"],
        status,
      });
      expect(decisao.allowed).toBe(status === "ENCERRADO");
    }
  });

  it("cycle.period.correct: somente ATIVO permite", async () => {
    for (const status of ["PLANEJADO", "ATIVO", "ENCERRADO", "CANCELADO"]) {
      const { decisao } = await decidir({
        capability: "cycle.period.correct",
        capabilitiesAtor: ["cycle.period.correct"],
        status,
      });
      expect(decisao.allowed).toBe(status === "ATIVO");
    }
  });

  it("o status SOBERANO prevalece: estado declarado pelo chamador não autoriza", async () => {
    const { decisao } = await decidir({
      capability: "cycle.period.correct",
      capabilitiesAtor: ["cycle.period.correct"],
      status: "ENCERRADO",
      // Chamador declara "domínio permite tudo" — deve ser IGNORADO no alvo ciclo.
      domainStateDeclarado: DECLARA_TUDO_PERMITIDO,
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });

  it("linha sem status real ⇒ DENY mesmo para leitura (fail-closed)", async () => {
    const { decisao } = await decidir({ capability: "cycle.read", status: "" });
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });

  it("tenant divergente do recurso ⇒ CROSS_TENANT", async () => {
    const { decisao } = await decidir({
      capability: "cycle.read",
      recurso: { kind: "cycle", id: CICLO, organizationId: ORG_B, status: "ATIVO" },
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("CROSS_TENANT");
  });

  it("membership revogada ⇒ MEMBERSHIP_INVALID (autorização obsoleta negada)", async () => {
    const { decisao, alvosCarregados } = await decidir({
      capability: "cycle.read",
      membership: "revoked",
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("MEMBERSHIP_INVALID");
    expect(alvosCarregados).toEqual([]);
  });

  it("perfil inativo ⇒ PROFILE_DISABLED", async () => {
    const { decisao } = await decidir({ capability: "cycle.read", perfil: "disabled" });
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("PROFILE_DISABLED");
  });

  it("ator inexistente ⇒ NO_IDENTITY", async () => {
    const { decisao } = await decidir({ capability: "cycle.read", identidadeNula: true });
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("NO_IDENTITY");
  });

  it("capability ausente/revogada ⇒ CAPABILITY_MISSING", async () => {
    const { decisao } = await decidir({
      capability: "cycle.manage",
      capabilitiesAtor: ["cycle.read"],
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("capability sem scope ⇒ SCOPE_INSUFFICIENT", async () => {
    const { decisao } = await decidir({
      capability: "cycle.read",
      capabilitiesAtor: ["cycle.read"],
      scopes: [],
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("alvo sintético global e rótulo inválido são recusados SEM carregar recurso", async () => {
    const global = await decidir({
      capability: "cycle.manage",
      capabilitiesAtor: ["cycle.manage"],
      alvo: { type: "cycle", id: "global" },
    });
    expect(global.decisao.allowed).toBe(false);
    expect(global.decisao.denial?.reason).toBe("TARGET_INVALID");
    expect(global.alvosCarregados).toEqual([]);

    // `ano`/`numero` NUNCA são identidade de ciclo.
    const rotulo = await decidir({
      capability: "cycle.read",
      alvo: { type: "cycle", id: "2035-1" },
    });
    expect(rotulo.decisao.allowed).toBe(false);
    expect(rotulo.decisao.denial?.reason).toBe("TARGET_INVALID");
    expect(rotulo.alvosCarregados).toEqual([]);

    const idNeutro = await decidir({
      capability: "cycle.read",
      alvo: { type: "cycle", id: "00000000-0000-0000-0000-000000000000" },
      recurso: null,
    });
    expect(idNeutro.decisao.allowed).toBe(false);
    expect(idNeutro.decisao.denial?.reason).toBe("TARGET_INVALID");
  });

  it("cargo/função textual adulterados não concedem nada", async () => {
    // A linha traz rótulos organizacionais; o ator NÃO tem a capability.
    const comRotulos = await decidir({
      capability: "cycle.cancel",
      capabilitiesAtor: [],
      recurso: {
        kind: "cycle",
        id: CICLO,
        organizationId: ORG,
        status: "ATIVO",
        ...({ funcao: "GERENTE", cargo: "Diretor", papel: "admin" } as object),
      } as RecursoSoberanoCarregado,
    });

    expect(comRotulos.decisao.allowed).toBe(false);
    expect(comRotulos.decisao.denial?.reason).toBe("CAPABILITY_MISSING");
  });
});
