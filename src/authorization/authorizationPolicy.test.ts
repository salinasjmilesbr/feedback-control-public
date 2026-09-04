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
  CollaboratorResource,
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
  const collaboratorResource: CollaboratorResource = {
    kind: "collaborator",
    collaborator: direto,
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
    cycle: ciclo,
  };

  it("mantém criação de avaliação e observação para colaborador ativo", () => {
    expect(
      can(contexto(gerente), "evaluation.create", evaluationResource)
    ).toBe(true);
    expect(
      can(contexto(gerente), "observation.create", observationResource)
    ).toBe(true);
  });

  it("bloqueia nova avaliação e mantém nova observação durante licença", () => {
    const colaboradorEmLicenca = { ...direto, status: "LICENCA" as const };
    const evaluationInLeave: EvaluationResource = {
      ...evaluationResource,
      evaluatedCollaborator: colaboradorEmLicenca,
    };
    const observationInLeave: ObservationResource = {
      ...observationResource,
      collaborator: colaboradorEmLicenca,
    };

    expect(
      can(contexto(gerente), "evaluation.create", evaluationInLeave)
    ).toBe(false);
    expect(
      can(contexto(gerente), "observation.create", observationInLeave)
    ).toBe(true);
  });

  it("bloqueia novas avaliações e observações após desligamento", () => {
    const colaboradorDesligado = { ...direto, status: "DESLIGADO" as const };
    const evaluationDisconnected: EvaluationResource = {
      ...evaluationResource,
      evaluatedCollaborator: colaboradorDesligado,
    };
    const observationDisconnected: ObservationResource = {
      ...observationResource,
      collaborator: colaboradorDesligado,
    };

    expect(
      can(contexto(gerente), "evaluation.create", evaluationDisconnected)
    ).toBe(false);
    expect(
      can(contexto(gerente), "observation.create", observationDisconnected)
    ).toBe(false);
  });

  it("nega handlers protegidos para colaborador desligado", () => {
    const colaboradorDesligado = { ...direto, status: "DESLIGADO" as const };

    expect(() =>
      authorize(contexto(gerente), "evaluation.create", {
        ...evaluationResource,
        evaluatedCollaborator: colaboradorDesligado,
      })
    ).toThrow(AuthorizationError);
    expect(() =>
      authorize(contexto(gerente), "observation.create", {
        ...observationResource,
        collaborator: colaboradorDesligado,
      })
    ).toThrow(AuthorizationError);
  });

  it("nega evaluation.create para recurso incompatível", () => {
    expect(
      can(contexto(gerente), "evaluation.create", { kind: "global" })
    ).toBe(false);
  });

  it("autoriza cancelamento de ciclo ativo somente para gerente", () => {
    expect(
      can(contexto(gerente), "cycle.cancel.manager", {
        kind: "cycle",
        cycle: ciclo,
      })
    ).toBe(true);
    expect(
      can(contexto(coordenador), "cycle.cancel.manager", {
        kind: "cycle",
        cycle: ciclo,
      })
    ).toBe(false);
    expect(
      can(contexto(gerente), "cycle.cancel.manager", {
        kind: "cycle",
        cycle: { ...ciclo, status: "CANCELADO" },
      })
    ).toBe(false);
  });

  it.each([
    ["ATIVO", gerente, true],
    ["ATIVO", coordenador, false],
    ["PLANEJADO", gerente, false],
    ["ENCERRADO", gerente, false],
    ["CANCELADO", gerente, false],
  ] as const)(
    "autoriza correção excepcional de período em %s para o perfil esperado",
    (status, actor, esperado) => {
      expect(
        can(contexto(actor), "cycle.period.correct.manager", {
          kind: "cycle",
          cycle: { ...ciclo, status },
        })
      ).toBe(esperado);
    }
  );

  it("nega operações relacionadas quando o ciclo está cancelado", () => {
    const cicloCancelado = { ...ciclo, status: "CANCELADO" as const };
    const avaliacaoCanceladaNoCiclo: EvaluationResource = {
      ...evaluationResource,
      cycle: cicloCancelado,
      evaluationStatus: "RASCUNHO",
    };

    expect(
      can(contexto(gerente), "evaluation.edit.manager", avaliacaoCanceladaNoCiclo)
    ).toBe(false);
    expect(
      can(contexto(gerente), "evaluation.create", avaliacaoCanceladaNoCiclo)
    ).toBe(false);
    expect(
      can(contexto(gerente), "goal.approve.manager", {
        ...goalResource,
        cycle: cicloCancelado,
      })
    ).toBe(false);
    expect(
      can(contexto(gerente), "observation.create", {
        ...observationResource,
        cycle: cicloCancelado,
      })
    ).toBe(false);
  });

  it.each([
    ["ATIVO", true],
    ["PLANEJADO", false],
    ["ENCERRADO", false],
    ["CANCELADO", false],
  ] as const)(
    "restringe capabilities de observação ao ciclo %s",
    (status, esperado) => {
      const resource: ObservationResource = {
        ...observationResource,
        cycle: { ...ciclo, status },
      };

      expect(can(contexto(gerente), "observation.create", resource)).toBe(
        esperado
      );
      expect(can(contexto(gerente), "observation.edit", resource)).toBe(
        esperado
      );
      expect(can(contexto(gerente), "observation.delete", resource)).toBe(
        esperado
      );
    }
  );

  it.each([
    ["GERENTE", gerente, true],
    ["COORDENADOR", coordenador, false],
    ["ANALISTA", direto, false],
    ["CONSULTOR", pessoa(20, "CONSULTOR"), false],
    ["ESTAGIARIO", pessoa(21, "ESTAGIARIO"), false],
  ] as const)(
    "caracteriza collaborator.create para %s",
    (_perfil, actor, esperado) => {
      expect(
        can(contexto(actor), "collaborator.create", { kind: "global" })
      ).toBe(esperado);
    }
  );

  it.each([
    ["GERENTE_RESPONSAVEL", gerente, true],
    ["COORDENADOR_DIRETO", coordenador, false],
    ["COLEGIADO", outroCoordenador, false],
    ["AVALIADO", direto, false],
  ] as const)(
    "autoriza evaluation.cancel.manager somente para %s",
    (_papel, actor, esperado) => {
      const resource: EvaluationResource = {
        ...evaluationResource,
        evaluatedCollaborator: {
          ...direto,
          avaliadoresColegiadoMatriculas: [outroCoordenador.matricula],
        },
      };

      expect(
        can(contexto(actor), "evaluation.cancel.manager", resource)
      ).toBe(esperado);
    }
  );

  it("mantém cancelada consultável e bloqueada para edição e novo cancelamento", () => {
    const resource: EvaluationResource = {
      ...evaluationResource,
      evaluationStatus: "CANCELADA",
    };

    expect(can(contexto(gerente), "evaluation.view.admin", resource)).toBe(true);
    expect(can(contexto(gerente), "evaluation.edit.manager", resource)).toBe(false);
    expect(can(contexto(gerente), "evaluation.cancel.manager", resource)).toBe(false);
  });

  it.each([
    ["GERENTE_RESPONSAVEL", gerente, true],
    ["COORDENADOR_DIRETO", coordenador, false],
    ["COLEGIADO", outroCoordenador, false],
    ["AVALIADO", direto, false],
  ] as const)(
    "autoriza evaluation.reopen.manager somente para %s em concluída",
    (_papel, actor, esperado) => {
      const resource: EvaluationResource = {
        ...evaluationResource,
        evaluatedCollaborator: {
          ...direto,
          avaliadoresColegiadoMatriculas: [outroCoordenador.matricula],
        },
        evaluationStatus: "CONCLUIDA",
      };

      expect(
        can(contexto(actor), "evaluation.reopen.manager", resource)
      ).toBe(esperado);
    }
  );

  it.each(["CANCELADA", "RASCUNHO", "PRONTA_PARA_FEEDBACK"] as const)(
    "nega evaluation.reopen.manager para status %s",
    (evaluationStatus) => {
      expect(
        can(contexto(gerente), "evaluation.reopen.manager", {
          ...evaluationResource,
          evaluationStatus,
        })
      ).toBe(false);
    }
  );

  it("nega evaluation.reopen.manager em ciclo encerrado", () => {
    expect(
      can(contexto(gerente), "evaluation.reopen.manager", {
        ...evaluationResource,
        cycle: { ...ciclo, status: "ENCERRADO" },
        evaluationStatus: "CONCLUIDA",
      })
    ).toBe(false);
  });

  it.each([
    ["GERENTE", gerente, true],
    ["COORDENADOR", coordenador, false],
    ["ANALISTA", direto, false],
    ["CONSULTOR", pessoa(22, "CONSULTOR"), false],
    ["ESTAGIARIO", pessoa(23, "ESTAGIARIO"), false],
  ] as const)(
    "caracteriza collaborator.edit para %s",
    (_perfil, actor, esperado) => {
      expect(
        can(contexto(actor), "collaborator.edit", collaboratorResource)
      ).toBe(esperado);
    }
  );

  it("nega capabilities de gestão de colaboradores para recurso incompatível", () => {
    expect(
      can(contexto(gerente), "collaborator.create", collaboratorResource)
    ).toBe(false);
    expect(
      can(contexto(gerente), "collaborator.edit", { kind: "global" })
    ).toBe(false);
  });

  it("impede coordenador de executar mutação de colaborador protegida", () => {
    expect(() =>
      authorize(contexto(coordenador), "collaborator.edit", collaboratorResource)
    ).toThrow(AuthorizationError);
  });

  it.each([
    ["GERENTE", gerente, true],
    ["COORDENADOR", coordenador, true],
    ["ANALISTA", direto, false],
    ["CONSULTOR", pessoa(24, "CONSULTOR"), false],
    ["ESTAGIARIO", pessoa(25, "ESTAGIARIO"), false],
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
    ["GERENTE_NO_ESCOPO", gerente, direto, true],
    ["COORDENADOR_DIRETO", coordenador, direto, true],
    ["COORDENADOR_COLEGIADO", coordenador, apenasColegiado, true],
    ["COORDENADOR_FORA_DO_ESCOPO", externo, direto, false],
    ["ANALISTA_PROPRIO_PERFIL", direto, direto, false],
    ["CONSULTOR_PROPRIO_PERFIL", pessoa(60, "CONSULTOR"), pessoa(60, "CONSULTOR"), false],
    ["ESTAGIARIO_PROPRIO_PERFIL", pessoa(61, "ESTAGIARIO"), pessoa(61, "ESTAGIARIO"), false],
  ] as const)(
    "combina collaborator.list e OPERATIONAL_TEAM para perfil administrativo: %s",
    (_cenario, actor, target, esperado) => {
      const equipe = [...collaborators];
      if (!equipe.some((item) => item.matricula === actor.matricula)) {
        equipe.push(actor);
      }

      const podeListar = can(
        contexto(actor),
        "collaborator.list",
        { kind: "collaborator-list", collaborators: equipe }
      );
      const podeVisualizar =
        podeListar &&
        scopeCollaborators(
          contexto(actor),
          { purpose: "OPERATIONAL_TEAM", collaborators: equipe }
        ).some((item) => item.matricula === target.matricula);

      expect(podeVisualizar).toBe(esperado);
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

  it.each([
    ["evaluation.edit.manager", gerente],
    ["evaluation.edit.coordinator", coordenador],
    ["evaluation.edit.board", outroCoordenador],
  ] as const)(
    "nega %s para avaliação concluída mesmo com responsabilidade",
    (capability, actor) => {
      const resource: EvaluationResource = {
        ...evaluationResource,
        evaluatedCollaborator: {
          ...direto,
          avaliadoresColegiadoMatriculas: [outroCoordenador.matricula],
        },
        evaluationStatus: "CONCLUIDA",
      };

      expect(can(contexto(actor), capability, resource)).toBe(false);
    }
  );

  it.each(["RASCUNHO", "PRONTA_PARA_FEEDBACK"] as const)(
    "preserva as permissões de edição para avaliação %s",
    (evaluationStatus) => {
      const resource: EvaluationResource = {
        ...evaluationResource,
        evaluatedCollaborator: {
          ...direto,
          avaliadoresColegiadoMatriculas: [outroCoordenador.matricula],
        },
        evaluationStatus,
      };

      expect(
        can(contexto(gerente), "evaluation.edit.manager", resource)
      ).toBe(true);
      expect(
        can(contexto(coordenador), "evaluation.edit.coordinator", resource)
      ).toBe(true);
      expect(
        can(contexto(outroCoordenador), "evaluation.edit.board", resource)
      ).toBe(true);
    }
  );

  it.each([
    ["GERENTE", gerente],
    ["COORDENADOR", coordenador],
    ["COLEGIADO", outroCoordenador],
  ] as const)(
    "preserva consulta administrativa de avaliação concluída para %s",
    (_papel, actor) => {
      const resource: EvaluationResource = {
        ...evaluationResource,
        evaluatedCollaborator: {
          ...direto,
          avaliadoresColegiadoMatriculas: [outroCoordenador.matricula],
        },
        evaluationStatus: "CONCLUIDA",
      };

      expect(
        can(contexto(actor), "evaluation.view.admin", resource)
      ).toBe(true);
    }
  );

  it.each([
    ["GERENTE_RESPONSAVEL", gerente, true],
    ["COORDENADOR_DIRETO", coordenador, true],
    ["MEMBRO_COLEGIADO", outroCoordenador, true],
    ["SEM_RESPONSABILIDADE", externo, false],
    ["PROPRIO_AVALIADO", direto, false],
  ] as const)(
    "autoriza evaluation.view.admin para %s conforme a responsabilidade do ciclo",
    (_perfil, actor, esperado) => {
      const resource: EvaluationResource = {
        ...evaluationResource,
        evaluatedCollaborator: {
          ...direto,
          avaliadoresColegiadoMatriculas: [outroCoordenador.matricula],
        },
      };

      expect(
        can(contexto(actor), "evaluation.view.admin", resource)
      ).toBe(esperado);
    }
  );

  it("nega evaluation.view.admin para recurso incompatível", () => {
    expect(
      can(contexto(gerente), "evaluation.view.admin", { kind: "global" })
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
    ["PROPRIO_AVALIADO", direto, false],
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
    expect(
      can(contexto(coordenadorAnterior), "evaluation.view.admin", resource)
    ).toBe(true);
    expect(
      can(contexto(coordenadorAtual), "evaluation.view.admin", resource)
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

  const capabilitiesMetasProprias = [
    "goal.create.own",
    "goal.edit.own",
    "goal.delete.own",
    "goal.progress.own",
    "goal.finalize.own",
  ] as const;

  it.each([
    ["COORDENADOR", coordenador, true],
    ["CONSULTOR", pessoa(70, "CONSULTOR"), true],
    ["ANALISTA", direto, true],
    ["ESTAGIARIO", pessoa(71, "ESTAGIARIO"), true],
    ["GERENTE", gerente, false],
  ] as const)(
    "aplica capabilities de metas próprias à configuração atual para %s",
    (_perfil, actor, esperado) => {
      const resource: GoalResource = {
        ...goalResource,
        owner: actor,
        collaborators: [...collaborators, actor],
      };

      capabilitiesMetasProprias.forEach((capability) =>
        expect(can(contexto(actor), capability, resource)).toBe(esperado)
      );
    }
  );

  it("nega todas as mutações próprias sobre meta de outro colaborador", () => {
    capabilitiesMetasProprias.forEach((capability) =>
      expect(can(contexto(coordenador), capability, goalResource)).toBe(false)
    );
  });

  it.each(["PLANEJADO", "ENCERRADO", "CANCELADO"] as const)(
    "nega mutações de metas próprias em ciclo %s",
    (status) => {
      const resource: GoalResource = {
        ...goalResource,
        owner: direto,
        cycle: { ...ciclo, status },
      };

      capabilitiesMetasProprias.forEach((capability) =>
        expect(can(contexto(direto), capability, resource)).toBe(false)
      );
    }
  );

  it("volta a permitir metas próprias quando o ciclo retorna a ativo", () => {
    const resource: GoalResource = {
      ...goalResource,
      owner: direto,
      cycle: { ...ciclo, status: "ATIVO" },
    };

    capabilitiesMetasProprias.forEach((capability) =>
      expect(can(contexto(direto), capability, resource)).toBe(true)
    );
  });

  it("nega as capabilities de aprovação de meta fora da cadeia", () => {
    expect(
      can(contexto(externo), "goal.approve.manager", goalResource)
    ).toBe(false);
    expect(
      can(contexto(externo), "goal.approve.coordinator", goalResource)
    ).toBe(false);
  });

  it("caracteriza os papéis de aprovação do gerente responsável", () => {
    expect(
      can(contexto(gerente), "goal.approve.manager", goalResource)
    ).toBe(true);
    expect(
      can(contexto(gerente), "goal.approve.coordinator", goalResource)
    ).toBe(false);
  });

  it("caracteriza os papéis de aprovação do coordenador direto", () => {
    expect(
      can(contexto(coordenador), "goal.approve.manager", goalResource)
    ).toBe(false);
    expect(
      can(contexto(coordenador), "goal.approve.coordinator", goalResource)
    ).toBe(true);
  });

  it("nega aprovação ao coordenador que participa somente do colegiado", () => {
    const resource: GoalResource = {
      ...goalResource,
      owner: apenasColegiado,
    };

    expect(
      can(contexto(coordenador), "goal.approve.manager", resource)
    ).toBe(false);
    expect(
      can(contexto(coordenador), "goal.approve.coordinator", resource)
    ).toBe(false);
  });

  it("nega aprovação ao gerente fora da cadeia", () => {
    const gerenteExterno = pessoa(30, "GERENTE");
    const resource: GoalResource = {
      ...goalResource,
      collaborators: [...collaborators, gerenteExterno],
    };

    expect(
      can(contexto(gerenteExterno), "goal.approve.manager", resource)
    ).toBe(false);
    expect(
      can(contexto(gerenteExterno), "goal.approve.coordinator", resource)
    ).toBe(false);
  });

  it.each([
    ["ANALISTA", pessoa(31, "ANALISTA")],
    ["CONSULTOR", pessoa(32, "CONSULTOR")],
    ["ESTAGIARIO", pessoa(33, "ESTAGIARIO")],
  ] as const)("nega aprovação ao perfil %s", (_perfil, actor) => {
    const resource: GoalResource = {
      ...goalResource,
      collaborators: [...collaborators, actor],
    };

    expect(can(contexto(actor), "goal.approve.manager", resource)).toBe(false);
    expect(
      can(contexto(actor), "goal.approve.coordinator", resource)
    ).toBe(false);
  });

  it("nega aprovação quando a função está ausente", () => {
    const actor = pessoa(34, undefined);
    const resource: GoalResource = {
      ...goalResource,
      collaborators: [...collaborators, actor],
    };

    expect(can(contexto(actor), "goal.approve.manager", resource)).toBe(false);
    expect(
      can(contexto(actor), "goal.approve.coordinator", resource)
    ).toBe(false);
  });

  it("nega as duas capabilities quando o ator não é resolvido", () => {
    const actorAusente = pessoa(35, "GERENTE");

    expect(
      can(contexto(actorAusente), "goal.approve.manager", goalResource)
    ).toBe(false);
    expect(
      can(contexto(actorAusente), "goal.approve.coordinator", goalResource)
    ).toBe(false);
  });

  it("preserva o responsável histórico na aprovação de metas", () => {
    const coordenadorAnterior = pessoa(50, "COORDENADOR", gerente.matricula);
    const coordenadorAtual = pessoa(51, "COORDENADOR", gerente.matricula);
    const owner = pessoa(52, "ANALISTA", coordenadorAtual.matricula);
    const movimento: MovimentacaoOrganizacional = {
      id: "movimento-meta-policy-historico",
      colaboradorMatricula: owner.matricula,
      colaboradorNome: owner.nome,
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
    const equipe = [gerente, coordenadorAnterior, coordenadorAtual, owner];
    const resource: GoalResource = {
      kind: "goal",
      owner,
      collaborators: equipe,
      cycle: ciclo,
    };

    expect(
      can(
        contexto(coordenadorAnterior),
        "goal.approve.coordinator",
        resource
      )
    ).toBe(true);
    expect(
      can(
        contexto(coordenadorAtual),
        "goal.approve.coordinator",
        resource
      )
    ).toBe(false);
  });

  it.each([
    ["GERENTE_RESPONSAVEL", gerente, true],
    ["COORDENADOR_DIRETO", coordenador, true],
    ["ATOR_EXTERNO", externo, false],
  ] as const)(
    "caracteriza o agregado OR de metas para %s",
    (_perfil, actor, esperado) => {
      const podeAprovar =
        can(contexto(actor), "goal.approve.manager", goalResource) ||
        can(contexto(actor), "goal.approve.coordinator", goalResource);

      expect(podeAprovar).toBe(esperado);
    }
  );

  it("nega as capabilities de meta para resource.kind incorreto", () => {
    expect(
      can(contexto(gerente), "goal.approve.manager", { kind: "global" })
    ).toBe(false);
    expect(
      can(contexto(coordenador), "goal.approve.coordinator", {
        kind: "global",
      })
    ).toBe(false);
  });

  it.each(["ENCERRADO", "CANCELADO"] as const)(
    "restringe aprovação em ciclo %s e preserva visualização histórica",
    (status) => {
      const resource: GoalResource = {
        ...goalResource,
        cycle: { ...ciclo, status },
      };

      expect(can(contexto(gerente), "goal.approve.manager", resource)).toBe(
        false
      );
      expect(
        can(contexto(coordenador), "goal.approve.coordinator", resource)
      ).toBe(false);
      expect(can(contexto(gerente), "goal.view.admin", resource)).toBe(true);
      expect(can(contexto(coordenador), "goal.view.admin", resource)).toBe(
        true
      );
    }
  );

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
