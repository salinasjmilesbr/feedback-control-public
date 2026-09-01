import { beforeEach, describe, expect, it } from "vitest";
import { obterPermissoesAvaliacao } from "../services/permissaoAvaliacao";
import { podeAprovarMetaNoCiclo } from "../services/metaStorage";
import { aplicarEscopoRelatorio } from "../services/relatorioService";
import { getColaboradoresVisiveis } from "../services/visibilidadeColaboradores";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { MovimentacaoOrganizacional } from "../types/HistoricoOrganizacional";
import type { Observacao } from "../types/Observacao";
import type { AuthorizationContext } from "./AuthorizationContext";
import { AuthorizationError } from "./authorizationError";
import { authorize, can, scopeCollaborators } from "./authorizationPolicy";
import type {
  EvaluationResource,
  GoalResource,
  ObservationResource,
} from "./ResourceContext";

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
  const observacaoDeOutroAutor: Observacao = {
    id: "observacao-outro-autor",
    colaboradorMatricula: direto.matricula,
    tipo: "NEUTRA",
    texto: "Observação criada por outro usuário",
    comunicado: false,
    autorMatricula: outroCoordenador.matricula,
    autorNome: outroCoordenador.nome,
    dataCriacao: "2026-01-01T00:00:00.000Z",
    dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
    excluida: false,
    historico: [],
  };
  const observationResource: ObservationResource = {
    kind: "observation",
    collaborator: direto,
    observation: observacaoDeOutroAutor,
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
    ["observation.create", "GERENTE", gerente, true],
    ["observation.create", "COORDENADOR", coordenador, true],
    ["observation.create", "ANALISTA", direto, false],
    ["observation.create", "CONSULTOR", pessoa(25, "CONSULTOR"), false],
    ["observation.create", "ESTAGIARIO", pessoa(26, "ESTAGIARIO"), false],
    ["observation.create", "SEM_FUNCAO", pessoa(27, undefined), false],
    ["observation.edit", "GERENTE", gerente, true],
    ["observation.edit", "COORDENADOR", coordenador, true],
    ["observation.edit", "ANALISTA", direto, false],
    ["observation.edit", "CONSULTOR", pessoa(28, "CONSULTOR"), false],
    ["observation.edit", "ESTAGIARIO", pessoa(29, "ESTAGIARIO"), false],
    ["observation.edit", "SEM_FUNCAO", pessoa(30, undefined), false],
    ["observation.delete", "GERENTE", gerente, true],
    ["observation.delete", "COORDENADOR", coordenador, true],
    ["observation.delete", "ANALISTA", direto, false],
    ["observation.delete", "CONSULTOR", pessoa(31, "CONSULTOR"), false],
    ["observation.delete", "ESTAGIARIO", pessoa(32, "ESTAGIARIO"), false],
    ["observation.delete", "SEM_FUNCAO", pessoa(33, undefined), false],
  ] as const)(
    "caracteriza %s para %s",
    (capability, _perfil, actor, esperado) => {
      expect(can(contexto(actor), capability, observationResource)).toBe(
        esperado
      );
    }
  );

  it.each([
    ["observation.edit", "GERENTE", gerente],
    ["observation.edit", "COORDENADOR", coordenador],
    ["observation.delete", "GERENTE", gerente],
    ["observation.delete", "COORDENADOR", coordenador],
  ] as const)(
    "%s permite %s sobre observação de outro autor",
    (capability, _perfil, actor) => {
      expect(can(contexto(actor), capability, observationResource)).toBe(true);
    }
  );

  it.each([
    "observation.create",
    "observation.edit",
    "observation.delete",
  ] as const)("nega %s para resource kind incorreto", (capability) => {
    expect(can(contexto(gerente), capability, { kind: "global" })).toBe(false);
  });

  it.each([
    ["COORDENADOR", coordenador, true],
    ["GERENTE", gerente, false],
    ["ANALISTA", direto, false],
    ["CONSULTOR", pessoa(16, "CONSULTOR"), false],
    ["ESTAGIARIO", pessoa(17, "ESTAGIARIO"), false],
    ["SEM_FUNCAO", pessoa(18, undefined), false],
  ] as const)(
    "caracteriza cycle.coordinator.list para %s",
    (_perfil, actor, esperado) => {
      expect(
        can(contexto(actor), "cycle.coordinator.list", { kind: "global" })
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
    ["GERENTE", gerente, true],
    ["COORDENADOR", coordenador, false],
    ["ANALISTA", direto, false],
    ["CONSULTOR", pessoa(19, "CONSULTOR"), false],
    ["ESTAGIARIO", pessoa(20, "ESTAGIARIO"), false],
    ["SEM_FUNCAO", pessoa(21, undefined), false],
  ] as const)("caracteriza settings.manage para %s", (_perfil, actor, esperado) => {
    expect(can(contexto(actor), "settings.manage", { kind: "global" })).toBe(
      esperado
    );
  });

  it.each([
    ["GERENTE", gerente, true],
    ["COORDENADOR", coordenador, true],
    ["ANALISTA", direto, false],
    ["CONSULTOR", pessoa(22, "CONSULTOR"), false],
    ["ESTAGIARIO", pessoa(23, "ESTAGIARIO"), false],
    ["SEM_FUNCAO", pessoa(24, undefined), false],
  ] as const)(
    "caracteriza cycle.team.panel.view para %s",
    (_perfil, actor, esperado) => {
      expect(
        can(contexto(actor), "cycle.team.panel.view", { kind: "global" })
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

  it("preserva papéis simultâneos de coordenador direto e colegiado", () => {
    const avaliadoComPapeisSimultaneos = {
      ...direto,
      avaliadoresColegiadoMatriculas: [coordenador.matricula],
    };
    const resource: EvaluationResource = {
      kind: "evaluation",
      evaluatedCollaborator: avaliadoComPapeisSimultaneos,
      collaborators: [
        gerente,
        coordenador,
        avaliadoComPapeisSimultaneos,
      ],
      cycle: ciclo,
    };

    expect(
      can(contexto(coordenador), "evaluation.edit.coordinator", resource)
    ).toBe(true);
    expect(
      can(contexto(coordenador), "evaluation.edit.board", resource)
    ).toBe(true);
    expect(
      can(contexto(coordenador), "evaluation.edit.manager", resource)
    ).toBe(false);
  });

  it.each([
    ["GERENTE", gerente, true],
    ["COORDENADOR_DIRETO", coordenador, true],
    ["SOMENTE_COLEGIADO", outroCoordenador, true],
    ["EXTERNO", externo, false],
  ] as const)("caracteriza o agregado OR para %s", (_perfil, actor, esperado) => {
    const resource =
      actor === outroCoordenador
        ? {
            ...evaluationResource,
            evaluatedCollaborator: {
              ...direto,
              avaliadoresColegiadoMatriculas: [outroCoordenador.matricula],
            },
          }
        : evaluationResource;
    const podeAvaliar =
      can(contexto(actor), "evaluation.edit.manager", resource) ||
      can(contexto(actor), "evaluation.edit.coordinator", resource) ||
      can(contexto(actor), "evaluation.edit.board", resource);

    expect(podeAvaliar).toBe(esperado);
  });

  it("preserva a estrutura histórica para coordenador anterior e atual", () => {
    const coordenadorAnterior = pessoa(40, "COORDENADOR", gerente.matricula);
    const coordenadorAtual = pessoa(41, "COORDENADOR", gerente.matricula);
    const avaliado = pessoa(42, "ANALISTA", coordenadorAtual.matricula);
    const movimento: MovimentacaoOrganizacional = {
      id: "movimento-policy-historico",
      colaboradorMatricula: avaliado.matricula,
      colaboradorNome: avaliado.nome,
      tipo: "ALTERACAO_ESTRUTURA",
      dataVigencia: "2027-06-01",
      dataRegistro: "2027-06-01T12:00:00.000Z",
      escopo: "CICLO_ATUAL_E_POSTERIORES",
      anterior: {
        status: "ATIVO",
        cargo: "Analista",
        area: "Área de teste",
        funcao: "ANALISTA",
        gestorDiretoMatricula: coordenadorAnterior.matricula,
        gestorDiretoNome: coordenadorAnterior.nome,
        avaliadoresColegiadoMatriculas: [],
        avaliadoresColegiadoNomes: [],
      },
      atual: {
        status: "ATIVO",
        cargo: "Analista",
        area: "Área de teste",
        funcao: "ANALISTA",
        gestorDiretoMatricula: coordenadorAtual.matricula,
        gestorDiretoNome: coordenadorAtual.nome,
        avaliadoresColegiadoMatriculas: [],
        avaliadoresColegiadoNomes: [],
      },
    };
    localStorage.setItem(
      "feedback-control-historico-organizacional",
      JSON.stringify([movimento])
    );
    const equipe = [gerente, coordenadorAnterior, coordenadorAtual, avaliado];
    const resource: EvaluationResource = {
      kind: "evaluation",
      evaluatedCollaborator: avaliado,
      collaborators: equipe,
      cycle: ciclo,
    };

    for (const actor of [coordenadorAnterior, coordenadorAtual]) {
      const legado = obterPermissoesAvaliacao(actor, avaliado, equipe, ciclo);
      expect(
        can(contexto(actor), "evaluation.edit.coordinator", resource)
      ).toBe(legado.podeAvaliarComoCoordenador);
    }
    expect(
      can(
        contexto(coordenadorAnterior),
        "evaluation.edit.coordinator",
        resource
      )
    ).toBe(true);
    expect(
      can(contexto(coordenadorAtual), "evaluation.edit.coordinator", resource)
    ).toBe(false);
  });

  it("mantém o fallback para ciclo ativo quando cycle é undefined", () => {
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([ciclo]));
    const resource: EvaluationResource = {
      ...evaluationResource,
      cycle: undefined,
    };
    const legado = obterPermissoesAvaliacao(
      coordenador,
      direto,
      collaborators,
      undefined
    );

    expect(
      can(contexto(coordenador), "evaluation.edit.coordinator", resource)
    ).toBe(legado.podeAvaliarComoCoordenador);
  });

  it("nega os três papéis quando o ator não é resolvido", () => {
    const actorAusente = pessoa(99, "COORDENADOR");

    expect(
      can(contexto(actorAusente), "evaluation.edit.manager", evaluationResource)
    ).toBe(false);
    expect(
      can(
        contexto(actorAusente),
        "evaluation.edit.coordinator",
        evaluationResource
      )
    ).toBe(false);
    expect(
      can(contexto(actorAusente), "evaluation.edit.board", evaluationResource)
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
