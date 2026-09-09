import { describe, expect, it } from "vitest";
import type { Colaborador } from "../types/Colaborador";
import {
  alvosPermitidos,
  autorizar,
  dominioPermite,
  pode,
} from "./autorizacaoFuncional";
import {
  derivarBindingsDev,
  estaNaCadeiaDeGestao,
} from "./mundoFuncional";

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

describe("F4-09 — autorização funcional (Policy Engine, sem cargo)", () => {
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
  const bindings = derivarBindingsDev(todos);

  it("funcionário A não lê avaliação de B (SELF não dá acesso a terceiro)", () => {
    const decisao = pode(analistaA, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaB.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    expect(decisao.allowed).toBe(false);
    expect(() =>
      autorizar(analistaA, todos, {
        capability: "evaluation.read",
        sujeitoMatricula: analistaB.matricula,
        domainState: dominioPermite(true),
      }, bindings)
    ).toThrow();
  });

  it("SELF lê a própria avaliação somente em CONCLUIDA", () => {
    const rascunho = pode(analistaA, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(false), // RASCUNHO
    }, bindings);
    const pronta = pode(analistaA, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(false), // PRONTA_PARA_FEEDBACK
    }, bindings);
    const concluida = pode(analistaA, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true), // CONCLUIDA
    }, bindings);
    expect(rascunho.allowed).toBe(false);
    expect(pronta.allowed).toBe(false);
    expect(concluida.allowed).toBe(true);
  });

  it("coordenador acessa seu DIRECT_REPORTS e não acessa quem está fora", () => {
    const direto = pode(coordenador, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    const fora = pode(coordenador, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: gerente.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    expect(direto.allowed).toBe(true);
    expect(fora.allowed).toBe(false);
  });

  it("gerente acessa os descendentes pelo scope DESCENDANTS", () => {
    const decisao = pode(gerente, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    expect(decisao.allowed).toBe(true);
  });

  it("colegiado acessa somente o alvo ASSIGNED e não vira hierarquia", () => {
    const atribuido = pode(analistaB, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    const outro = pode(analistaB, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: estagiario.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    expect(atribuido.allowed).toBe(true);
    expect(outro.allowed).toBe(false);
  });

  it("alterar funcao/cargo sem alterar relação NÃO concede acesso", () => {
    // Promove o AnalistaA a "GERENTE" sem mudar a estrutura (gestorDireto).
    const promovido = colaborador(3, "AnalistaA", {
      funcao: "GERENTE",
      gestorDiretoMatricula: 2,
      avaliadoresColegiadoMatriculas: [4],
    });
    const decisao = pode(promovido, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: analistaB.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    expect(decisao.allowed).toBe(false);
  });

  it("capability removida do binding ⇒ DENY imediato (revogação sem logout)", () => {
    // Binding explícito sem as capabilities de coordenação.
    const semCoord = new Map(bindings);
    semCoord.set(coordenador.matricula, new Set(["goal.write", "evaluation.read"]));
    const decisao = pode(coordenador, todos, {
      capability: "evaluation.write",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    }, semCoord);
    expect(decisao.allowed).toBe(false);
  });

  it("ID/sujeito manipulado (inexistente) ⇒ DENY/TARGET_INVALID", () => {
    const decisao = pode(gerente, todos, {
      capability: "evaluation.read",
      sujeitoMatricula: 999,
      domainState: dominioPermite(true),
    }, bindings);
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("TARGET_INVALID");
  });

  it("metas: aprovação só no alcance; SELF aprovação de terceiro = DENY", () => {
    const aprovacaoCoordenador = pode(coordenador, todos, {
      capability: "goal.approve",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    const selfAprovaTerceiro = pode(analistaA, todos, {
      capability: "goal.approve",
      sujeitoMatricula: analistaB.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    expect(aprovacaoCoordenador.allowed).toBe(true);
    expect(selfAprovaTerceiro.allowed).toBe(false);
  });

  it("observação de terceiro: SELF = DENY; gestor no alcance = ALLOW", () => {
    const self = pode(analistaA, todos, {
      capability: "observation.read",
      sujeitoMatricula: analistaB.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    const gestor = pode(coordenador, todos, {
      capability: "observation.read",
      sujeitoMatricula: analistaA.matricula,
      domainState: dominioPermite(true),
    }, bindings);
    expect(self.allowed).toBe(false);
    expect(gestor.allowed).toBe(true);
  });

  it("listAllowedTargets limita o dataset (limit-then-aggregate base)", () => {
    const visiveis = alvosPermitidos(
      coordenador,
      todos,
      "evaluation.read",
      dominioPermite(true),
      undefined,
      bindings
    );
    const matriculas = visiveis.map((c) => c.matricula).sort();
    expect(matriculas).toEqual([2, 3, 4, 5].sort()); // self + diretos
  });

  it("cadeia de gestão é derivada de dados, não de funcao", () => {
    expect(estaNaCadeiaDeGestao(coordenador, analistaA, todos)).toBe(true);
    expect(estaNaCadeiaDeGestao(gerente, analistaA, todos)).toBe(true);
    expect(estaNaCadeiaDeGestao(analistaB, analistaA, todos)).toBe(false);
  });
});
