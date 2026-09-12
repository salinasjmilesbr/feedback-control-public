import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { Colaborador } from "../types/Colaborador";
import type { AuthorizationContext } from "./AuthorizationContext";
import { can } from "./authorizationPolicy";
import { estadoDominioCiclo, statusCicloConhecido } from "./estadoDominioCiclo";
import autorizacaoFonte from "./authorizationPolicy.ts?raw";
import recursoFonte from "./resourceContextReal.ts?raw";

/**
 * F5-09 P6 (§8, D8, D20, D21) — MATRIZ de `domainState` das capabilities de
 * ciclo no adaptador funcional (`can`/`authorize`), com TARGET REAL (UUID) e
 * guardas estáticos de que a matriz tem uma única fonte e que nenhuma
 * capability de ciclo é decidida sobre alvo sintético.
 */

const CICLO = "55555555-5555-4555-8555-555555555555";

const STATUS = ["PLANEJADO", "ATIVO", "ENCERRADO", "CANCELADO"] as const;

/** Matriz contratada no §8 do desenho técnico (e D8 para `cycle.cancel`). */
const MATRIZ: Readonly<Record<string, readonly string[]>> = {
  "cycle.read": ["PLANEJADO", "ATIVO", "ENCERRADO", "CANCELADO"],
  "cycle.manage": ["PLANEJADO", "ATIVO"],
  "cycle.cancel": ["PLANEJADO", "ATIVO"],
  "cycle.reopen": ["ENCERRADO"],
  "cycle.period.correct": ["ATIVO"],
};

const CAPABILITIES = Object.keys(MATRIZ) as readonly (
  | "cycle.read"
  | "cycle.manage"
  | "cycle.cancel"
  | "cycle.reopen"
  | "cycle.period.correct"
)[];

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number
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

describe("F5-09 P6 — capabilities de ciclo contra o recurso REAL", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  const gestor = pessoa(1, "GERENTE");
  const coordenador = pessoa(2, "COORDENADOR", gestor.matricula);
  const analista = pessoa(4, "ANALISTA", coordenador.matricula);
  const collaborators = [gestor, coordenador, analista];

  function recursoCiclo(status: string, id: string = CICLO) {
    return { kind: "cycle" as const, cycle: { id, status }, collaborators };
  }

  it.each(
    CAPABILITIES.flatMap((capability) =>
      STATUS.map((status) => [capability, status] as const)
    )
  )("%s em ciclo %s segue a matriz do §8", (capability, status) => {
    const esperado = MATRIZ[capability].includes(status);

    expect(can(contexto(gestor), capability, recursoCiclo(status))).toBe(esperado);
  });

  it("sem a capability da ação o estado favorável NÃO autoriza", () => {
    // Alvos de DOMÍNIO (ciclo) só são alcançados pelo escopo ORGANIZATION na
    // matriz de compatibilidade: a coordenação (DIRECT_REPORTS/DESCENDANTS) NÃO
    // alcança ciclo algum — capability isolada nunca basta (fail-closed).
    expect(can(contexto(coordenador), "cycle.read", recursoCiclo("ATIVO"))).toBe(false);
    expect(can(contexto(coordenador), "cycle.manage", recursoCiclo("PLANEJADO"))).toBe(false);
    expect(can(contexto(coordenador), "cycle.cancel", recursoCiclo("PLANEJADO"))).toBe(false);

    // Fluxos próprios (SELF) não incluem nenhuma capability de ciclo.
    for (const capability of CAPABILITIES) {
      expect(can(contexto(analista), capability, recursoCiclo("ATIVO"))).toBe(false);
    }
  });

  it("status fora do domínio fechado nega TODAS as capabilities de ciclo", () => {
    for (const capability of CAPABILITIES) {
      // Caixa/espaços são NORMALIZADOS (o status válido vem do CHECK da P1);
      // qualquer outro valor é recusado.
      for (const status of ["ARQUIVADO", "", "  ", "CICLO_1"]) {
        expect(can(contexto(gestor), capability, recursoCiclo(status))).toBe(false);
      }
    }
  });

  it("o alvo autorizável é o UUID canônico do ciclo (nunca ano/numero)", () => {
    // O recurso carrega o UUID: a decisão acompanha o ID recebido.
    expect(can(contexto(gestor), "cycle.reopen", recursoCiclo("ENCERRADO"))).toBe(true);
    // Sem identidade de ciclo o probe nega (fail-closed) mesmo com status válido.
    expect(can(contexto(gestor), "cycle.read", { kind: "cycle", cycle: { id: "", status: "ATIVO" } })).toBe(
      false
    );
  });

  it("aliases legados produzem a MESMA decisão das capabilities canônicas", () => {
    const casos = [
      ["cycle.management.view", "cycle.read", "CANCELADO"],
      ["cycle.coordinator.list", "cycle.read", "ATIVO"],
      ["cycle.team.panel.view", "cycle.read", "ATIVO"],
      ["cycle.cancel.manager", "cycle.cancel", "PLANEJADO"],
      ["cycle.reopen.manager", "cycle.reopen", "ENCERRADO"],
      ["cycle.period.correct.manager", "cycle.period.correct", "ATIVO"],
    ] as const;

    for (const [alias, canonica, status] of casos) {
      expect(can(contexto(gestor), alias, recursoCiclo(status))).toBe(
        can(contexto(gestor), canonica, recursoCiclo(status))
      );
    }
  });

  it("nenhuma capability de ciclo é decidida sobre o alvo sintético global", () => {
    // O caso `global` usa alvo SINTÉTICO e não é autorização real (F5-05
    // D19/D22): sem recurso/mundo reais as cinco capabilities de ciclo respondem
    // DENY — inclusive a leitura (fail-closed, F5-08 P6).
    for (const capability of CAPABILITIES) {
      expect(can(contexto(gestor), capability, { kind: "global" })).toBe(false);
    }
  });
});

describe("F5-09 P6 — guardas estáticos da autorização de ciclo", () => {
  it("a matriz de estado tem fonte ÚNICA (`estadoDominioCiclo`) no adaptador", () => {
    expect(autorizacaoFonte).toContain("estadoDominioCiclo({ status: resource.cycle.status })");
    // A matriz inline do ramo de ciclo não pode sobreviver no adaptador.
    expect(autorizacaoFonte).not.toContain("dominioPermite(resource.cycle.status");
  });

  it("o alvo do `case \"cycle\"` é o id do recurso, e o alvo sintético é único", () => {
    expect(autorizacaoFonte).toContain('const alvo: TargetRef = { type: "cycle", id: resource.cycle.id };');

    const declaracaoSintetica = autorizacaoFonte.match(
      /const alvoCiclo: TargetRef = \{ type: "cycle", id: "global" \};/g
    ) ?? [];
    expect(declaracaoSintetica).toHaveLength(1);
    // O alvo sintético é usado UMA vez (compat de UX de `settings.manage`).
    const usos = autorizacaoFonte.match(/target: alvoCiclo/g) ?? [];
    expect(usos).toHaveLength(1);
  });

  it("o ciclo é recurso SOBERANO e meta/observação permanecem fora do limite", () => {
    expect(recursoFonte).toMatch(/TIPOS_RECURSO_SOBERANOS[\s\S]*?"cycle",\s*\] as const/);
    expect(recursoFonte).toContain('TIPOS_RECURSO_NAO_SOBERANOS = ["goal", "observation"] as const');
  });
});

describe("F5-09 P6 — probe de domínio do ciclo", () => {
  it("normaliza o status e recusa valor fora do domínio fechado", () => {
    expect(statusCicloConhecido("ativo")).toBe("ATIVO");
    expect(statusCicloConhecido(" ATIVO ")).toBe("ATIVO");
    expect(statusCicloConhecido("ARQUIVADO")).toBeNull();
    expect(statusCicloConhecido(undefined)).toBeNull();
    expect(statusCicloConhecido(1)).toBeNull();
  });

  it("capability fora da matriz de ciclo é NEGADA pelo probe", () => {
    const probe = estadoDominioCiclo({ status: "ATIVO" });
    expect(probe.allows("evaluation.read")).toBe(false);
    expect(probe.allows("cycle.read")).toBe(true);
    expect(probe.allows("cycle.period.correct")).toBe(true);
    expect(probe.allows("cycle.reopen")).toBe(false);
  });
});
