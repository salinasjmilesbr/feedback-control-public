/**
 * F5-08 P6 (correção da auditoria GPT) — ADAPTADOR da estrutura soberana.
 *
 * Prova que a projeção estrutural é construída EXCLUSIVAMENTE das relações
 * soberanas já entregues pelo P4 — posições, ocupações vigentes, reporting lines
 * e colegiado — e que a identidade é o UUID canônico:
 *
 * 1. a cadeia de gestão vem de `position_reporting_lines` + ocupação vigente;
 * 2. "gerente responsável" = RAIZ da cadeia; "coordenador" = nível INTERMEDIÁRIO;
 * 3. colegiado vem da configuração VIGENTE (membros em UUID);
 * 4. vigência é meio-aberta `[from, to)` e equivale a `estaVigente` (P4/P5);
 * 5. inconsistência (posição vaga, ciclo, dado ambíguo, sem ocupação) ⇒
 *    FAIL-CLOSED: nada é adivinhado;
 * 6. nenhuma matrícula participa do modelo (nem como chave, nem como rótulo).
 */

import { describe, expect, it } from "vitest";
import { estaVigente } from "../pages/apoioEstrutura";
import type {
  ColegiadoSoberano,
  OcupacaoSoberana,
  PosicaoSoberana,
  ReportingLineSoberana,
} from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import {
  alcanceSoberano,
  colegiadoSoberano,
  gestorSoberano,
  gestorSoberanoTemSuperior,
  montarProjecaoEstrutural,
  posicaoSoberana,
  raizDaCadeiaSoberana,
  temCadeiaDeGestaoSoberana,
  temEvidenciaEstrutural,
  vigenteNaReferencia,
  vinculoEstrutural,
} from "./projecaoEstruturalSoberana";

const REF = "2026-06-15T12:00:00.000Z";
const INICIO = "2026-01-01T00:00:00.000Z";

// UUIDs canônicos (nunca matrícula).
const POS_GERENTE = "11111111-1111-4111-8111-111111111111";
const POS_COORD = "22222222-2222-4222-8222-222222222222";
const POS_ANALISTA = "33333333-3333-4333-8333-333333333333";
const POS_COLEGA = "44444444-4444-4444-8444-444444444444";
const POS_VAGA = "55555555-5555-4555-8555-555555555555";

const COL_GERENTE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const COL_COORD = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const COL_ANALISTA = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const COL_COLEGA = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

function posicao(posicaoId: string): PosicaoSoberana {
  return {
    posicaoId,
    unitId: "99999999-9999-4999-8999-999999999999",
    jobRoleId: "88888888-8888-4888-8888-888888888888",
    seniorityLevelId: null,
    validFrom: INICIO,
    validTo: null,
    version: 1,
  };
}

function ocupacao(
  ocupacaoId: string,
  collaboratorId: string,
  posicaoId: string,
  validTo: string | null = null
): OcupacaoSoberana {
  return { ocupacaoId, collaboratorId, posicaoId, validFrom: INICIO, validTo, version: 1 };
}

function reporting(
  reportingLineId: string,
  subordinatePositionId: string,
  managerPositionId: string,
  validTo: string | null = null
): ReportingLineSoberana {
  return {
    reportingLineId,
    subordinatePositionId,
    managerPositionId,
    motivo: "fixture",
    validFrom: INICIO,
    validTo,
    version: 1,
  };
}

function colegiado(
  colegiadoId: string,
  collaboratorId: string,
  membroIds: readonly string[],
  validTo: string | null = null
): ColegiadoSoberano {
  return {
    colegiadoId,
    collaboratorId,
    validFrom: INICIO,
    validTo,
    version: 1,
    membroIds,
  };
}

/** Fotografia: gerente (raiz) ← coordenação ← analista, com colegiado no analista. */
function fotografiaCompleta() {
  return {
    referencia: REF,
    posicoes: [posicao(POS_GERENTE), posicao(POS_COORD), posicao(POS_ANALISTA), posicao(POS_COLEGA)],
    ocupacoes: [
      ocupacao("o-1", COL_GERENTE, POS_GERENTE),
      ocupacao("o-2", COL_COORD, POS_COORD),
      ocupacao("o-3", COL_ANALISTA, POS_ANALISTA),
      ocupacao("o-4", COL_COLEGA, POS_COLEGA),
    ],
    reportingLines: [
      reporting("r-1", POS_COORD, POS_GERENTE),
      reporting("r-2", POS_ANALISTA, POS_COORD),
      reporting("r-3", POS_COLEGA, POS_COORD),
    ],
    colegiados: [colegiado("c-1", COL_ANALISTA, [COL_COLEGA])],
  };
}

describe("F5-08 P6 — adaptador da estrutura soberana (UUID)", () => {
  it("monta a cadeia por POSIÇÕES/reporting lines e resolve o ocupante em UUID", () => {
    const projecao = montarProjecaoEstrutural(fotografiaCompleta());

    expect(temEvidenciaEstrutural(projecao, COL_ANALISTA)).toBe(true);
    expect(posicaoSoberana(projecao, COL_ANALISTA)).toBe(POS_ANALISTA);
    expect(gestorSoberano(projecao, COL_ANALISTA)).toBe(COL_COORD);
    expect(gestorSoberano(projecao, COL_COORD)).toBe(COL_GERENTE);
    expect(gestorSoberano(projecao, COL_GERENTE)).toBeNull();

    // Cadeia em posições E em colaboradores (UUID), do gestor direto à raiz.
    expect(vinculoEstrutural(projecao, COL_ANALISTA)?.cadeiaDeGestaoPositionIds).toEqual([
      POS_COORD,
      POS_GERENTE,
    ]);
    expect(
      vinculoEstrutural(projecao, COL_ANALISTA)?.cadeiaDeGestaoCollaboratorIds
    ).toEqual([COL_COORD, COL_GERENTE]);

    // "Gerente responsável" = raiz; sem gestor, a própria pessoa é a raiz.
    expect(raizDaCadeiaSoberana(projecao, COL_ANALISTA)).toBe(COL_GERENTE);
    expect(raizDaCadeiaSoberana(projecao, COL_GERENTE)).toBe(COL_GERENTE);

    // "Coordenador" = nível INTERMEDIÁRIO (o gestor direto do analista tem
    // superior); o gerente (raiz) NÃO é intermediário.
    expect(gestorSoberanoTemSuperior(projecao, COL_ANALISTA)).toBe(true);
    expect(gestorSoberanoTemSuperior(projecao, COL_COORD)).toBe(false);
    expect(temCadeiaDeGestaoSoberana(projecao, COL_ANALISTA)).toBe(true);
    expect(temCadeiaDeGestaoSoberana(projecao, COL_GERENTE)).toBe(false);
  });

  it("colegiado vem da configuração VIGENTE, em UUID", () => {
    const projecao = montarProjecaoEstrutural(fotografiaCompleta());
    expect(colegiadoSoberano(projecao, COL_ANALISTA)).toEqual([COL_COLEGA]);
    expect(colegiadoSoberano(projecao, COL_COORD)).toEqual([]);

    const encerrado = montarProjecaoEstrutural({
      ...fotografiaCompleta(),
      colegiados: [
        colegiado("c-1", COL_ANALISTA, [COL_COLEGA], "2026-03-01T00:00:00.000Z"),
      ],
    });
    expect(colegiadoSoberano(encerrado, COL_ANALISTA)).toEqual([]);
  });

  it("alcance: raiz enxerga descendentes; gestor enxerga diretos + colegiado", () => {
    const projecao = montarProjecaoEstrutural(fotografiaCompleta());

    expect([...alcanceSoberano(projecao, COL_GERENTE)].sort()).toEqual(
      [COL_ANALISTA, COL_COLEGA, COL_COORD].sort()
    );
    expect([...alcanceSoberano(projecao, COL_COORD)].sort()).toEqual(
      [COL_ANALISTA, COL_COLEGA].sort()
    );
    expect([...alcanceSoberano(projecao, COL_COLEGA)].sort()).toEqual([COL_ANALISTA]);
  });

  it("vigência: meio-aberta, orientada pela referência, igual a `estaVigente` do P4", () => {
    const casos: Array<[string | null, string | null, string]> = [
      [INICIO, null, REF],
      [INICIO, "2026-03-01T00:00:00.000Z", REF],
      ["2026-07-01T00:00:00.000Z", null, REF],
      [INICIO, "2026-03-01T00:00:00.000Z", "2026-03-01T00:00:00.000Z"],
      [INICIO, "2026-03-01T00:00:00.000Z", "2026-02-28T23:59:59.000Z"],
      [null, null, REF],
      ["data-invalida", null, REF],
    ];

    for (const [de, ate, referencia] of casos) {
      expect(vigenteNaReferencia(de, ate, referencia), `${de} | ${ate} | ${referencia}`).toBe(
        estaVigente(de, ate, referencia)
      );
    }

    // Fim exclusivo explícito: encerrada exatamente na referência.
    expect(vigenteNaReferencia(INICIO, REF, REF)).toBe(false);
  });

  it("ocupação não vigente ⇒ nenhuma evidência estrutural (fail-closed)", () => {
    const projecao = montarProjecaoEstrutural({
      referencia: REF,
      posicoes: [posicao(POS_ANALISTA)],
      ocupacoes: [
        ocupacao("o-3", COL_ANALISTA, POS_ANALISTA, "2026-03-01T00:00:00.000Z"),
      ],
      reportingLines: [],
      colegiados: [],
    });

    expect(temEvidenciaEstrutural(projecao, COL_ANALISTA)).toBe(false);
    expect(gestorSoberano(projecao, COL_ANALISTA)).toBeNull();
    expect(temCadeiaDeGestaoSoberana(projecao, COL_ANALISTA)).toBe(false);
  });

  it("posição de gestor VAGA ⇒ cadeia não confiável (nada é adivinhado)", () => {
    const projecao = montarProjecaoEstrutural({
      referencia: REF,
      posicoes: [posicao(POS_ANALISTA), posicao(POS_VAGA)],
      ocupacoes: [ocupacao("o-3", COL_ANALISTA, POS_ANALISTA)],
      reportingLines: [reporting("r-2", POS_ANALISTA, POS_VAGA)],
      colegiados: [],
    });

    const vinculo = vinculoEstrutural(projecao, COL_ANALISTA);
    expect(vinculo?.gestorSoberanoPositionId).toBe(POS_VAGA);
    expect(vinculo?.cadeiaConfiavel).toBe(false);
    expect(gestorSoberano(projecao, COL_ANALISTA)).toBeNull();
    expect(temCadeiaDeGestaoSoberana(projecao, COL_ANALISTA)).toBe(false);
    expect(raizDaCadeiaSoberana(projecao, COL_ANALISTA)).toBeNull();
  });

  it("ciclo de reporting ⇒ cadeia não confiável (fail-closed)", () => {
    const projecao = montarProjecaoEstrutural({
      referencia: REF,
      posicoes: [posicao(POS_COORD), posicao(POS_ANALISTA)],
      ocupacoes: [
        ocupacao("o-2", COL_COORD, POS_COORD),
        ocupacao("o-3", COL_ANALISTA, POS_ANALISTA),
      ],
      reportingLines: [
        reporting("r-2", POS_ANALISTA, POS_COORD),
        reporting("r-3", POS_COORD, POS_ANALISTA),
      ],
      colegiados: [],
    });

    expect(vinculoEstrutural(projecao, COL_ANALISTA)?.cadeiaConfiavel).toBe(false);
    expect(gestorSoberano(projecao, COL_ANALISTA)).toBeNull();
  });

  it("dado ambíguo (duas ocupações/reporting/colegiado vigentes) ⇒ fail-closed", () => {
    const duasOcupacoes = montarProjecaoEstrutural({
      referencia: REF,
      posicoes: [posicao(POS_ANALISTA), posicao(POS_COLEGA)],
      ocupacoes: [
        ocupacao("o-3", COL_ANALISTA, POS_ANALISTA),
        ocupacao("o-3b", COL_ANALISTA, POS_COLEGA),
      ],
      reportingLines: [],
      colegiados: [],
    });
    expect(temEvidenciaEstrutural(duasOcupacoes, COL_ANALISTA)).toBe(true);
    expect(vinculoEstrutural(duasOcupacoes, COL_ANALISTA)?.posicaoId).toBeNull();
    expect(vinculoEstrutural(duasOcupacoes, COL_ANALISTA)?.cadeiaConfiavel).toBe(false);

    const doisColegiados = montarProjecaoEstrutural({
      referencia: REF,
      posicoes: [posicao(POS_ANALISTA)],
      ocupacoes: [ocupacao("o-3", COL_ANALISTA, POS_ANALISTA)],
      reportingLines: [],
      colegiados: [
        colegiado("c-1", COL_ANALISTA, [COL_COLEGA]),
        colegiado("c-2", COL_ANALISTA, [COL_COORD]),
      ],
    });
    expect(colegiadoSoberano(doisColegiados, COL_ANALISTA)).toEqual([]);
  });
});
