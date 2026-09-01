import { beforeEach, describe, expect, it } from "vitest";
import { obterPermissoesAvaliacao } from "../services/permissaoAvaliacao";
import { podeAprovarMetaNoCiclo } from "../services/metaStorage";
import { aplicarEscopoRelatorio } from "../services/relatorioService";
import { getColaboradoresVisiveis } from "../services/visibilidadeColaboradores";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { AuthorizationContext } from "./AuthorizationContext";
import { AuthorizationError } from "./authorizationError";
import { authorize, can, scopeCollaborators } from "./authorizationPolicy";
import type { EvaluationResource, GoalResource } from "./ResourceContext";

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number,
  colegiado?: number[]
): Colaborador {
  return {
    matricula,
    status: "ATIVO",
    nome: `Pessoa ${matricula}`,
    email: `${matricula}@example.com`,
    cargo: funcao ?? "Sem função",
    area: "Área de teste",
    funcao,
    gestorDiretoMatricula,
    avaliadoresColegiadoMatriculas: colegiado,
    respondePara: "",
  };
}

function contexto(colaborador: Colaborador): AuthorizationContext {
  return {
    actor: {
      matricula: colaborador.matricula,
      funcao: colaborador.funcao,
      status: colaborador.status,
    },
  };
}

const ciclo: CicloAvaliacao = {
  id: "ciclo-policy",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataInicio: "2026-01-01",
  dataFim: "2026-12-31",
  dataCriacao: "2025-12-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};

describe("authorizationPolicy", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  const gerente = pessoa(1, "GERENTE");
  const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
  const outroCoordenador = pessoa(3, "COORDENADOR", gerente.matricula);
  const direto = pessoa(4, "ANALISTA", coordenador.matricula);
  const apenasColegiado = pessoa(
    5,
    "ANALISTA",
    outroCoordenador.matricula,
    [coordenador.matricula]
  );
  const externo = pessoa(9, "COORDENADOR");
  const collaborators = [
    gerente,
    coordenador,
    outroCoordenador,
    direto,
    apenasColegiado,
    externo,
  ];
  const evaluationResource: EvaluationResource = {
    kind: "evaluation",
    evaluatedCollaborator: direto,
    collaborators,
    cycle: ciclo,
  };
  const goalResource: GoalResource = {
    kind: "goal",
    owner: direto,
    collaborators,
    cycle: ciclo,
  };

  it.each([
    ["GERENTE", gerente, true],
    ["COORDENADOR", coordenador, true],
    ["ANALISTA", direto, false],
  ] as const)(
    "caracteriza collaborator.list para %s",
    (_perfil, actor, esperado) => {
      expect(
        can(
          contexto(actor),
          "collaborator.list",
          { kind: "collaborator-list", collaborators }
        )
      ).toBe(esperado);
    }
  );

  it.each([
    ["GERENTE", gerente, true],
    ["COORDENADOR", coordenador, true],
    ["ANALISTA", direto, false],
    ["CONSULTOR", pessoa(10, "CONSULTOR"), false],
    ["ESTAGIARIO", pessoa(11, "ESTAGIARIO"), false],
    ["SEM_FUNCAO", pessoa(12, undefined), false],
  ] as const)("caracteriza report.view para %s", (_perfil, actor, esperado) => {
    expect(can(contexto(actor), "report.view", { kind: "global" })).toBe(esperado);
  });

  it.each([
    ["GERENTE", gerente, true],
    ["COORDENADOR", coordenador, false],
    ["ANALISTA", direto, false],
    ["CONSULTOR", pessoa(13, "CONSULTOR"), false],
    ["ESTAGIARIO", pessoa(14, "ESTAGIARIO"), false],
    ["SEM_FUNCAO", pessoa(15, undefined), false],
  ] as const)(
    "caracteriza cycle.management.view para %s",
    (_perfil, actor, esperado) => {
      expect(
        can(contexto(actor), "cycle.management.view", { kind: "global" })
      ).toBe(esperado);
    }
  );

  it.each([
    ["evaluation.edit.manager", gerente, "podeAvaliarComoGerente"],
    [
      "evaluation.edit.coordinator",
      coordenador,
      "podeAvaliarComoCoordenador",
    ],
    ["evaluation.edit.board", coordenador, "podeAvaliarComoColegiado"],
  ] as const)(
    "mantém equivalência de %s com obterPermissoesAvaliacao",
    (capability, actor, campoLegado) => {
      const legado = obterPermissoesAvaliacao(
        actor,
        direto,
        collaborators,
        ciclo
      );

      expect(can(contexto(actor), capability, evaluationResource)).toBe(
        legado[campoLegado]
      );
    }
  );

  it("nega as capabilities de avaliação fora do escopo", () => {
    expect(
      can(contexto(externo), "evaluation.edit.manager", evaluationResource)
    ).toBe(false);
    expect(
      can(
        contexto(externo),
        "evaluation.edit.coordinator",
        evaluationResource
      )
    ).toBe(false);
    expect(
      can(contexto(externo), "evaluation.edit.board", evaluationResource)
    ).toBe(false);
  });

  it.each([
    ["goal.approve.manager", gerente],
    ["goal.approve.coordinator", coordenador],
  ] as const)(
    "mantém equivalência de %s com podeAprovarMetaNoCiclo",
    (capability, actor) => {
      expect(can(contexto(actor), capability, goalResource)).toBe(
        podeAprovarMetaNoCiclo(actor, direto, collaborators, ciclo)
      );
    }
  );

  it("nega as capabilities de aprovação de meta fora da cadeia", () => {
    expect(
      can(contexto(externo), "goal.approve.manager", goalResource)
    ).toBe(false);
    expect(
      can(contexto(externo), "goal.approve.coordinator", goalResource)
    ).toBe(false);
  });

  it("mantém OPERATIONAL_TEAM equivalente a getColaboradoresVisiveis", () => {
    expect(
      scopeCollaborators(
        contexto(coordenador),
        { purpose: "OPERATIONAL_TEAM", collaborators }
      )
    ).toEqual(getColaboradoresVisiveis(coordenador, collaborators));
  });

  it("mantém REPORT equivalente à regra pública do relatório", () => {
    const operacional = getColaboradoresVisiveis(coordenador, collaborators);
    const esperado = aplicarEscopoRelatorio(
      operacional.map((colaborador) => ({ colaborador })),
      coordenador
    ).map(({ colaborador }) => colaborador);

    expect(
      scopeCollaborators(
        contexto(coordenador),
        { purpose: "REPORT", collaborators }
      )
    ).toEqual(esperado);
  });

  it("distingue colegiado no OPERATIONAL_TEAM e no REPORT", () => {
    const operacional = scopeCollaborators(
      contexto(coordenador),
      { purpose: "OPERATIONAL_TEAM", collaborators }
    );
    const relatorio = scopeCollaborators(
      contexto(coordenador),
      { purpose: "REPORT", collaborators }
    );

    expect(operacional).toContainEqual(apenasColegiado);
    expect(relatorio).not.toContainEqual(apenasColegiado);
    expect(relatorio).toContainEqual(direto);
  });

  it("authorize não lança quando a decisão é permitida", () => {
    expect(() =>
      authorize(
        contexto(gerente),
        "evaluation.edit.manager",
        evaluationResource
      )
    ).not.toThrow();
  });

  it("authorize lança AuthorizationError tipado quando negado", () => {
    try {
      authorize(
        contexto(externo),
        "evaluation.edit.coordinator",
        evaluationResource
      );
      throw new Error("Era esperado que authorize lançasse um erro.");
    } catch (error) {
      expect(error).toBeInstanceOf(AuthorizationError);
      expect(error).toMatchObject({
        code: "FORBIDDEN",
        capability: "evaluation.edit.coordinator",
      });
    }
  });

  it("nega decisão legada quando o ator não está no resource", () => {
    const actorAusente = pessoa(99, "GERENTE");

    expect(
      can(
        contexto(actorAusente),
        "evaluation.edit.manager",
        evaluationResource
      )
    ).toBe(false);
    expect(
      can(contexto(actorAusente), "goal.approve.manager", goalResource)
    ).toBe(false);
  });

  it("nega collaborator.list quando o ator não está no resource", () => {
    const actorAusente = pessoa(99, "GERENTE");

    expect(
      can(
        contexto(actorAusente),
        "collaborator.list",
        { kind: "collaborator-list", collaborators }
      )
    ).toBe(false);
  });

  it("retorna escopo vazio quando o ator não está no input", () => {
    const actorAusente = pessoa(99, "COORDENADOR");

    expect(
      scopeCollaborators(
        contexto(actorAusente),
        { purpose: "OPERATIONAL_TEAM", collaborators }
      )
    ).toEqual([]);
    expect(
      scopeCollaborators(
        contexto(actorAusente),
        { purpose: "REPORT", collaborators }
      )
    ).toEqual([]);
  });
});
