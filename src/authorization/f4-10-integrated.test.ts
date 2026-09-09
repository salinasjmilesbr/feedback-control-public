import { describe, expect, it } from "vitest";
import type { Colaborador } from "../types/Colaborador";
import {
  alvosPermitidos,
  autorizar,
  dominioPermite,
  pode,
} from "./autorizacaoFuncional";
import {
  criarProvidersMundoFuncional,
  derivarBindingsDev,
  LOCAL_ORGANIZATION_ID,
} from "./mundoFuncional";
import { authorize as authorizeEngine, can as canEngine } from "./policyEngine/policyEngine";

/**
 * F4-10 (Issue #97) — validação INTEGRADA e ADVERSARIAL da matriz de autorização
 * (F4-01…F4-09). Este arquivo NÃO cria regra nova: ele prova, de forma
 * transversal, que as regras já implementadas funcionam juntas e fail-closed.
 *
 * Cada teste referencia os IDs estáveis da matriz (docs/F4-10-desenho-tecnico.md)
 * que evidencia. A rastreabilidade completa está em
 * docs/F4-10-matriz-rastreabilidade.md.
 */

function colaborador(
  matricula: number,
  nome: string,
  extra: Partial<Colaborador> = {}
): Colaborador {
  return {
    matricula,
    nome,
    email: `${nome.toLowerCase()}@sintetico.invalid`,
    cargo: "Analista",
    area: "TI",
    status: "ATIVO",
    respondePara: "",
    ...extra,
  };
}

// Estrutura: GERENTE(1) -> COORDENADOR(2) -> { A(3), B(4), E(5) };
// B é colegiado de A (A.avaliadoresColegiadoMatriculas = [4]).
const gerente = colaborador(1, "Gerente", { funcao: "GERENTE" });
const coordenador = colaborador(2, "Coordenador", {
  funcao: "COORDENADOR",
  gestorDiretoMatricula: 1,
});
const analistaA = colaborador(3, "AnalistaA", {
  funcao: "ANALISTA",
  gestorDiretoMatricula: 2,
  avaliadoresColegiadoMatriculas: [4],
});
const analistaB = colaborador(4, "AnalistaB", {
  funcao: "ANALISTA",
  gestorDiretoMatricula: 2,
});
const estagiario = colaborador(5, "Estagiario", {
  funcao: "ESTAGIARIO",
  gestorDiretoMatricula: 2,
});
const todos = [gerente, coordenador, analistaA, analistaB, estagiario];

describe("F4-10 — validação integrada da matriz de autorização (gate Fase 4)", () => {
  it("PIPE-001/ATTACK-006: tenant divergente/target forjado ⇒ DENY antes de capability", () => {
    // Alvo inexistente (id forjado) ⇒ TARGET_INVALID; leitura não vaza existência.
    const decisao = pode(gerente, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: 999,
      domainState: dominioPermite(true),
    });
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("TARGET_INVALID");
  });

  it("PIPE-006/CAP-005: capability × target fora da allowlist ⇒ TARGET_INCOMPATIBLE", () => {
    // cycle.cancel com alvo collaborator (incompatível) nega antes de scope/relação.
    const providers = criarProvidersMundoFuncional({ actor: gerente, colaboradores: todos });
    const decisao = canEngine(
      {
        actor: { actorId: "1", organizationId: LOCAL_ORGANIZATION_ID },
        capability: "cycle.cancel",
        target: { type: "collaborator", id: "3" },
        context: { date: new Date() },
        domainState: dominioPermite(true),
      },
      providers
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("TARGET_INCOMPATIBLE");
  });

  it("PIPE-003/EVAL-002: SELF nunca supera estado não publicado", () => {
    const rascunho = pode(analistaA, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(false),
    });
    const concluida = pode(analistaA, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    });
    expect(rascunho.allowed).toBe(false);
    expect(concluida.allowed).toBe(true);
  });

  it("PE-006/ATTACK-007 (TOCTOU): decision antigo não é reutilizado após revogação", () => {
    // can() permite; em seguida a capability é removida; authorize() reavalia e nega.
    const providersAntes = criarProvidersMundoFuncional({ actor: coordenador, colaboradores: todos });
    const request = {
      actor: { actorId: "2", organizationId: LOCAL_ORGANIZATION_ID },
      capability: "evaluation.write" as const,
      target: { type: "collaborator" as const, id: "3" },
      context: { date: new Date() },
      domainState: dominioPermite(true),
    };
    expect(canEngine(request, providersAntes).allowed).toBe(true);

    const semCap = new Map(derivarBindingsDev(todos));
    semCap.set(2, new Set(["goal.write", "evaluation.read"])); // coordenação removida
    const providersDepois = criarProvidersMundoFuncional({
      actor: coordenador,
      colaboradores: todos,
      bindingsDev: semCap,
    });
    expect(() => authorizeEngine(request, providersDepois)).toThrow();
  });

  it("REV-003: capability removida ⇒ DENY imediato (sem logout)", () => {
    const antes = pode(coordenador, todos, {
      capability: "evaluation.write",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    });
    expect(antes.allowed).toBe(true);

    const semCap = new Map(derivarBindingsDev(todos));
    semCap.set(2, new Set(["goal.write", "evaluation.read"]));
    const depois = pode(coordenador, todos, {
      capability: "evaluation.write",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    }, semCap);
    expect(depois.allowed).toBe(false);
  });

  it("REV-009: colegiado (ASSIGNED) removido ⇒ DENY imediato, sem virar hierarquia", () => {
    const semColegiado = todos.map((c) =>
      c.matricula === analistaA.matricula
        ? { ...analistaA, avaliadoresColegiadoMatriculas: [] }
        : c
    );
    const bindings = derivarBindingsDev(semColegiado);
    const decisao = pode(analistaB, semColegiado, {
      capability: "evaluation.write",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    expect(decisao.allowed).toBe(false);
  });

  it("REV-010: mudança de gestor retira o alcance antigo imediatamente", () => {
    const antes = pode(coordenador, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    });
    expect(antes.allowed).toBe(true);

    // A passa a responder ao gerente (fora de DIRECT_REPORTS do coordenador).
    const mundoNovo = todos.map((c) =>
      c.matricula === analistaA.matricula
        ? { ...analistaA, gestorDiretoMatricula: gerente.matricula }
        : c
    );
    const depois = pode(coordenador, mundoNovo, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    }, derivarBindingsDev(mundoNovo));
    expect(depois.allowed).toBe(false);
  });

  it("CAP-003/HIER-008/ATTACK: funcao/cargo NÃO concedem autorização", () => {
    const promovido = colaborador(3, "AnalistaA", {
      funcao: "GERENTE",
      cargo: "Gerente",
      gestorDiretoMatricula: 2,
      avaliadoresColegiadoMatriculas: [4],
    });
    // Mesma estrutura (gestor=2), só cargo/funcao mudaram ⇒ continua sem acesso a B.
    const decisao = pode(promovido, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaB.matricula,
      domainState: dominioPermite(true),
    }, derivarBindingsDev(todos));
    expect(decisao.allowed).toBe(false);
  });

  it("SCOPE-011/SCOPE-012/GOAL-004: ASSIGNED não vira hierarquia nem metas de terceiro", () => {
    const colegiadoLeMeta = pode(analistaB, todos, {
      capability: "goal.approve",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    });
    expect(colegiadoLeMeta.allowed).toBe(false); // colegiado não aprova meta
  });

  it("REPORT-003/REPORT-004/DISC-002: limit-then-aggregate — sem targets autorizados ⇒ vazio", () => {
    // listAllowedTargets (via alvosPermitidos) limita o dataset ANTES de agregar.
    const visiveis = alvosPermitidos(
      coordenador,
      todos,
      "evaluation.read",
      dominioPermite(true),
      undefined,
      derivarBindingsDev(todos)
    );
    const fora = visiveis.filter((c) => c.matricula === gerente.matricula);
    expect(fora).toEqual([]); // gerente (acima) não entra no dataset do coordenador
  });

  it("PE-007/PE-011: domainState ausente ⇒ INDETERMINATE (fail-closed)", () => {
    const providers = criarProvidersMundoFuncional({ actor: gerente, colaboradores: todos });
    const decisao = canEngine(
      {
        actor: { actorId: "1", organizationId: LOCAL_ORGANIZATION_ID },
        capability: "evaluation.read",
        target: { type: "collaborator", id: "3" },
        context: { date: new Date() },
      },
      providers
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("INDETERMINATE");
  });

  it("PE-008/DISC-006: CROSS_TENANT/TARGET_INVALID ⇒ NOT_FOUND em leitura (sem vazar existência)", () => {
    const providers = criarProvidersMundoFuncional({ actor: gerente, colaboradores: todos });
    const decisao = canEngine(
      {
        actor: { actorId: "1", organizationId: LOCAL_ORGANIZATION_ID },
        capability: "evaluation.read",
        target: { type: "collaborator", id: "404" },
        context: { date: new Date() },
        domainState: dominioPermite(true),
      },
      providers
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("TARGET_INVALID");
    expect(decisao.denial?.publicCode).toBe("NOT_FOUND");
  });

  it("POS-003/POS-004: caminhos felizes correspondentes permanecem ALLOW", () => {
    const coordenadorDireto = pode(coordenador, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    });
    const colegiadoAssigned = pode(analistaB, todos, {
      capability: "evaluation.write",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    });
    expect(coordenadorDireto.allowed).toBe(true);
    expect(colegiadoAssigned.allowed).toBe(true);
  });

  it("ATTACK-010: authorize (enforcement) nega onde can() (UX) permitiria por hierarquia", () => {
    // can é predicação; authorize reavalia e é a porta soberana da mutação.
    expect(() =>
      autorizar(analistaA, todos, {
        capability: "evaluation.write",
        sujeitoMatricula: analistaB.matricula,
        domainState: dominioPermite(true),
      })
    ).toThrow();
  });
});
