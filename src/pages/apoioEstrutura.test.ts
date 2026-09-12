/**
 * F5-08 P4 (correção do BLOCKER 1) — VIGÊNCIA TEMPORAL e VERSÃO OTIMISTA.
 *
 * O contrato temporal da F5-08 é o intervalo MEIO-ABERTO
 * `[valid_from, valid_to)`, com operações FUTURAS permitidas. Logo:
 *
 *   vigente(validFrom, validTo, referencia)
 *     = validFrom <= referencia && (validTo === null || referencia < validTo)
 *
 * Nenhum teste depende do relógio real: a referência é sempre injetada.
 */

import { describe, expect, it } from "vitest";
import {
  MENSAGEM_FOTOGRAFIA_DESATUALIZADA,
  colegiadoVigente,
  decidirVersaoOtimista,
  estaVigente,
  ocupanteDaPosicao,
  periodoParentVigente,
  profundidadeDaUnidade,
  rotuloVigencia,
  situacaoTemporal,
  superiorDaPosicao,
} from "./apoioEstrutura";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";

const REF = "2026-06-15T12:00:00.000Z";
const PASSADO = "2026-01-01T00:00:00.000Z";
const FUTURO = "2026-12-31T00:00:00.000Z";

const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const UNIDADE_PAI = "abababab-abab-4bab-8bab-abababababab";
const POSICAO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const POSICAO_SUPERIOR = "bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd";
const COLABORADOR = "22222222-2222-4222-8222-222222222222";
const MEMBRO = "33333333-3333-4333-8333-333333333333";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const COLEGIADO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

describe("F5-08 P4 — vigência meio-aberta [valid_from, valid_to)", () => {
  it.each([
    ["passado + sem término definido", PASSADO, null, true],
    ["passado + término FUTURO (continua vigente)", PASSADO, FUTURO, true],
    ["início FUTURO + sem término", FUTURO, null, false],
    ["término no PASSADO", PASSADO, "2026-03-01T00:00:00.000Z", false],
    ["referência EXATAMENTE no término (fim exclusivo)", PASSADO, REF, false],
    ["referência EXATAMENTE no início (início inclusivo)", REF, null, true],
    ["início e término futuros", FUTURO, "2027-01-01T00:00:00.000Z", false],
  ] as const)("%s", (_nome, from, to, esperado) => {
    expect(estaVigente(from, to, REF)).toBe(esperado);
  });

  it("não inventa fuso: instantes com offset são comparados por época", () => {
    // 2026-06-15T09:00:00-03:00 === 2026-06-15T12:00:00Z
    const mesmoInstante = "2026-06-15T09:00:00-03:00";

    expect(estaVigente(mesmoInstante, null, REF)).toBe(true);
    expect(estaVigente(PASSADO, mesmoInstante, REF)).toBe(false); // fim exclusivo
    expect(situacaoTemporal(mesmoInstante, null, "2026-06-15T08:59:59-03:00")).toBe(
      "futura"
    );
  });

  it("vigência inválida é FAIL-CLOSED (nunca vigente)", () => {
    expect(estaVigente(null, null, REF)).toBe(false);
    expect(estaVigente("", null, REF)).toBe(false);
    expect(estaVigente("data-invalida", null, REF)).toBe(false);
    expect(estaVigente(PASSADO, "data-invalida", REF)).toBe(false);
    // Janela degenerada (término <= início) não é vigente.
    expect(estaVigente(FUTURO, PASSADO, REF)).toBe(false);
    expect(situacaoTemporal("data-invalida", null, REF)).toBe("invalida");
  });

  it("situação temporal distingue vigente, futura e encerrada", () => {
    expect(situacaoTemporal(PASSADO, null, REF)).toBe("vigente");
    expect(situacaoTemporal(FUTURO, null, REF)).toBe("futura");
    expect(situacaoTemporal(PASSADO, "2026-03-01T00:00:00.000Z", REF)).toBe(
      "encerrada"
    );
    expect(rotuloVigencia(PASSADO, null, REF)).toBe("Vigente desde 01/01/2026");
    expect(rotuloVigencia(PASSADO, FUTURO, REF)).toBe(
      "Vigente desde 01/01/2026 até 31/12/2026"
    );
    expect(rotuloVigencia(FUTURO, null, REF)).toBe("Programada para 31/12/2026");
    expect(rotuloVigencia(PASSADO, "2026-03-01T00:00:00.000Z", REF)).toBe(
      "Encerrada em 01/03/2026"
    );
  });
});

function estrutura(parcial: Partial<EstruturaSoberana> = {}): EstruturaSoberana {
  return {
    unidades: [],
    periodosParent: [],
    posicoes: [],
    reportingLines: [],
    ocupacoes: [],
    cargos: [],
    senioridades: [],
    colegiados: [],
    colaboradores: [],
    ...parcial,
  };
}

describe("F5-08 P4 — seleção temporal da fotografia (parent/ocupação/reporting/colegiado)", () => {
  it("relação parent FUTURA não aparece como parent vigente antes da data", () => {
    const base = estrutura({
      unidades: [
        { unitId: UNIDADE, nome: "Filha", validFrom: PASSADO, validTo: null, version: 1 },
        { unitId: UNIDADE_PAI, nome: "Pai", validFrom: PASSADO, validTo: null, version: 1 },
      ],
      periodosParent: [
        {
          periodoId: POSICAO,
          unitId: UNIDADE,
          parentUnitId: UNIDADE_PAI,
          validFrom: FUTURO,
          validTo: null,
          version: 1,
        },
      ],
    });

    expect(periodoParentVigente(base, UNIDADE, REF)).toBeNull();
    expect(periodoParentVigente(base, UNIDADE, FUTURO)).toEqual({
      parentUnitId: UNIDADE_PAI,
    });
    // Árvore: a relação futura não indenta a unidade antes da data.
    expect(profundidadeDaUnidade(base, UNIDADE, REF)).toBe(0);
    expect(profundidadeDaUnidade(base, UNIDADE, FUTURO)).toBe(1);
  });

  it("relação parent com término FUTURO continua vigente (fim exclusivo)", () => {
    const base = estrutura({
      periodosParent: [
        {
          periodoId: POSICAO,
          unitId: UNIDADE,
          parentUnitId: UNIDADE_PAI,
          validFrom: PASSADO,
          validTo: FUTURO,
          version: 1,
        },
      ],
    });

    expect(periodoParentVigente(base, UNIDADE, REF)).toEqual({
      parentUnitId: UNIDADE_PAI,
    });
    expect(periodoParentVigente(base, UNIDADE, FUTURO)).toBeNull();
  });

  it("ocupação FUTURA não aparece como ocupante atual", () => {
    const base = estrutura({
      ocupacoes: [
        {
          ocupacaoId: COLEGIADO,
          collaboratorId: COLABORADOR,
          posicaoId: POSICAO,
          validFrom: FUTURO,
          validTo: null,
          version: 1,
        },
      ],
    });

    expect(ocupanteDaPosicao(base, POSICAO, REF)).toBeNull();
    expect(ocupanteDaPosicao(base, POSICAO, FUTURO)).toBe(COLABORADOR);
  });

  it("reporting line FUTURA não aparece como superior atual", () => {
    const base = estrutura({
      reportingLines: [
        {
          reportingLineId: COLEGIADO,
          subordinatePositionId: POSICAO,
          managerPositionId: POSICAO_SUPERIOR,
          motivo: "cadeia futura",
          validFrom: FUTURO,
          validTo: null,
          version: 1,
        },
      ],
    });

    expect(superiorDaPosicao(base, POSICAO, REF)).toBeNull();
    expect(superiorDaPosicao(base, POSICAO, FUTURO)).toBe(POSICAO_SUPERIOR);
  });

  it("colegiado FUTURO não aparece como versão vigente", () => {
    const base = estrutura({
      colegiados: [
        {
          colegiadoId: COLEGIADO,
          collaboratorId: COLABORADOR,
          validFrom: FUTURO,
          validTo: null,
          version: 1,
          membroIds: [MEMBRO],
        },
      ],
    });

    expect(colegiadoVigente(base, COLABORADOR, REF)).toBeNull();
    expect(colegiadoVigente(base, COLABORADOR, FUTURO)).toEqual({
      colegiadoId: COLEGIADO,
      membroIds: [MEMBRO],
    });
  });

  it("colegiado ENCERRADO não é versão vigente", () => {
    const base = estrutura({
      colegiados: [
        {
          colegiadoId: COLEGIADO,
          collaboratorId: COLABORADOR,
          validFrom: PASSADO,
          validTo: "2026-03-01T00:00:00.000Z",
          version: 2,
          membroIds: [MEMBRO],
        },
      ],
    });

    expect(colegiadoVigente(base, COLABORADOR, REF)).toBeNull();
  });
});

describe("F5-08 P4 — versão otimista NUNCA fabricada", () => {
  const CARGO_ID = CARGO;

  it("usa EXATAMENTE a versão da fotografia (inclusive 0 vindo do servidor)", () => {
    expect(decidirVersaoOtimista([{ id: CARGO_ID, version: 7 }], CARGO_ID)).toEqual({
      tipo: "enviar",
      expectedVersion: 7,
    });
    // `0` é uma versão legítima do servidor (recém-criado): o que se proíbe é
    // FABRICAR 0 quando a entidade não está na fotografia.
    expect(decidirVersaoOtimista([{ id: CARGO_ID, version: 0 }], CARGO_ID)).toEqual({
      tipo: "enviar",
      expectedVersion: 0,
    });
  });

  it("entidade ausente da fotografia ⇒ recusa local, sem versão alguma", () => {
    const decisao = decidirVersaoOtimista([{ id: MEMBRO, version: 3 }], CARGO_ID);

    expect(decisao.tipo).toBe("fotografia-desatualizada");
    if (decisao.tipo !== "fotografia-desatualizada") return;
    expect(decisao.codigo).toBe("CONFLICT");
    expect(decisao.mensagem).toBe(MENSAGEM_FOTOGRAFIA_DESATUALIZADA);
    expect(Object.keys(decisao)).not.toContain("expectedVersion");
  });

  it("versão não numérica do servidor também é fail-closed", () => {
    const decisao = decidirVersaoOtimista(
      [{ id: CARGO_ID, version: Number.NaN }],
      CARGO_ID
    );
    expect(decisao.tipo).toBe("fotografia-desatualizada");
  });
});
