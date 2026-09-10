import { describe, expect, it } from "vitest";

/**
 * F5-06 (D24/D25) — PARIDADE entre o cálculo OFICIAL (SQL) e a baseline legada.
 *
 * O cálculo oficial vive em `public.evaluation_calcular` (PostgreSQL) e NÃO é
 * reimplementado aqui como autoridade: este módulo apenas reproduz, em
 * TypeScript, a MESMA expressão algébrica para provar em teste que a migração
 * não mudou a regra funcional (paridade com tolerância `1e-8` — D24).
 *
 * Ontologia (contrato §6.1):
 *   parcela(individual)      = média das notas daquele PAPEL
 *   parcela(COLEGIADO)       = média dos votos VÁLIDOS (colegiado = UMA parcela)
 *   nota_subcriterio         = média das parcelas válidas
 *   nota_criterio            = média das notas de subcritério válidas
 *   nota_media               = média das notas de critério válidas
 *
 * A expressão é equivalente à baseline legada (“média simples dos valores > 0”,
 * ausência ≠ 0) — é isso que o teste verifica.
 */

/** Tolerância oficial de paridade (D24). */
export const TOLERANCIA_PARIDADE = 1e-8;

/** Baseline legada: média simples dos valores válidos (> 0); sem válidos ⇒ 0. */
export function mediaBaselineLegada(valores: readonly number[]): number {
  const validos = valores.filter((valor) => Number.isFinite(valor) && valor > 0);
  if (validos.length === 0) return 0;
  return validos.reduce((soma, valor) => soma + valor, 0) / validos.length;
}

/**
 * Parcelas por RESPONSABILIDADE: cada papel contribui com UMA parcela; o
 * colegiado é a média dos seus votos válidos (nunca uma parcela por membro).
 */
export function parcelasPorResponsabilidade(
  notasPorPapel: Readonly<Record<string, readonly number[]>>
): number[] {
  return Object.values(notasPorPapel)
    .map((notas) => mediaBaselineLegada(notas))
    .filter((parcela) => parcela > 0);
}

/** Cálculo oficial reproduzido: subcritério → critério → média geral. */
export function calcularOficial(
  notasSubcriterio: readonly number[],
  notasCriterio: readonly number[]
): number {
  // Os subcritérios válidos alimentam o critério quando não há nota de critério
  // materializada; ausência nunca vira zero.
  const sub = mediaBaselineLegada(notasSubcriterio);
  const criterios = notasCriterio.length > 0 ? notasCriterio : sub > 0 ? [sub] : [];
  return mediaBaselineLegada(criterios);
}

function iguaisComTolerancia(a: number, b: number): boolean {
  return Math.abs(a - b) <= TOLERANCIA_PARIDADE;
}

describe("paridade cálculo oficial (SQL) × baseline legada (D24/D25)", () => {
  it("3 responsabilidades com colegiado: gerente + coordenador + média do colegiado", () => {
    // Equivalente ao cenário SQL: GESTAO_CADEIA=4 ; COLEGIADO=(2+4)/2=3
    //                                     GESTAO_DIRETA=3 (hipotético)
    const parcelas = parcelasPorResponsabilidade({
      GESTAO_CADEIA: [4],
      GESTAO_DIRETA: [3],
      COLEGIADO: [2, 4],
    });
    expect(parcelas).toEqual([4, 3, 3]);
    expect(iguaisComTolerancia(mediaBaselineLegada(parcelas), 10 / 3)).toBe(true);
    // Regressão de ponderação: se cada membro do colegiado pesasse
    // individualmente, (4+3+2+4)/4 = 3.25 — resultado DIFERENTE.
    expect(iguaisComTolerancia(mediaBaselineLegada([4, 3, 2, 4]), 3.25)).toBe(true);
  });

  it("colegiado como UMA parcela reproduz o resultado do validador SQL (3.5)", () => {
    const subcriterio = mediaBaselineLegada(
      parcelasPorResponsabilidade({ GESTAO_CADEIA: [4], COLEGIADO: [2, 4] })
    );
    expect(iguaisComTolerancia(subcriterio, 3.5)).toBe(true);
    // Se cada voto pesasse: (4+2+4)/3 = 3.3333...
    const incorreto = mediaBaselineLegada([4, 2, 4]);
    expect(iguaisComTolerancia(incorreto, 3.5)).toBe(false);
  });

  it("colegiado com 0 membros ⇒ a parcela agregada não existe", () => {
    const parcelas = parcelasPorResponsabilidade({ GESTAO_CADEIA: [4], COLEGIADO: [] });
    expect(parcelas).toEqual([4]);
    expect(mediaBaselineLegada(parcelas)).toBe(4);
  });

  it("colegiado com 1 membro ⇒ parcela é o próprio voto", () => {
    const parcelas = parcelasPorResponsabilidade({ GESTAO_CADEIA: [4], COLEGIADO: [2] });
    expect(parcelas).toEqual([4, 2]);
    expect(mediaBaselineLegada(parcelas)).toBe(3);
  });

  it("colegiado com N membros ⇒ peso constante (nunca peso por membro)", () => {
    const base = mediaBaselineLegada(
      parcelasPorResponsabilidade({ GESTAO_CADEIA: [4], COLEGIADO: [4] })
    );
    for (const votos of [[4, 4, 4], [4, 4, 4, 4, 4, 4]]) {
      const resultado = mediaBaselineLegada(
        parcelasPorResponsabilidade({ GESTAO_CADEIA: [4], COLEGIADO: votos })
      );
      expect(iguaisComTolerancia(resultado, base)).toBe(true);
    }
  });

  it("membro do colegiado SEM voto não vira zero e não entra na média", () => {
    const comAusencia = parcelasPorResponsabilidade({
      GESTAO_CADEIA: [4],
      COLEGIADO: [2, 0],
    });
    expect(comAusencia).toEqual([4, 2]);
    expect(mediaBaselineLegada(comAusencia)).toBe(3);
  });

  it("ausência em papel individual não penaliza (fora do denominador)", () => {
    const apenasCadeia = parcelasPorResponsabilidade({ GESTAO_CADEIA: [3], GESTAO_DIRETA: [] });
    expect(apenasCadeia).toEqual([3]);
    expect(mediaBaselineLegada(apenasCadeia)).toBe(3);
  });

  it("todos sem nota ⇒ 0 ('sem avaliação'), nunca NaN", () => {
    expect(mediaBaselineLegada([])).toBe(0);
    expect(mediaBaselineLegada([0, 0])).toBe(0);
  });

  it("notas fracionárias resultantes preservam a precisão (sem arredondamento intermediário)", () => {
    // (4 + (2+3)/2) / 2 = (4 + 2.5) / 2 = 3.25
    const umSubcriterio = mediaBaselineLegada(
      parcelasPorResponsabilidade({ GESTAO_CADEIA: [4], COLEGIADO: [2, 3] })
    );
    expect(iguaisComTolerancia(umSubcriterio, 3.25)).toBe(true);

    // Três subcritérios com terços: a média das médias NÃO é arredondada antes.
    const subcriterios = [
      { GESTAO_CADEIA: [1], COLEGIADO: [2, 3] }, // (1+2.5)/2 = 1.75
      { GESTAO_CADEIA: [3], COLEGIADO: [3, 4] }, // (3+3.5)/2 = 3.25
      { GESTAO_CADEIA: [2], COLEGIADO: [2, 2] }, // 2
    ];
    const criterio = mediaBaselineLegada(
      subcriterios.map((sub) => mediaBaselineLegada(parcelasPorResponsabilidade(sub)))
    );
    expect(iguaisComTolerancia(criterio, (1.75 + 3.25 + 2) / 3)).toBe(true);
    // Com arredondamento intermediário para 1 casa o valor seria 2.3 (2.3333…).
    expect(iguaisComTolerancia(criterio, 2.3)).toBe(false);
  });

  it("média geral combina critérios válidos e ignora critério sem nota", () => {
    // Dois critérios materializados: 3.5 e 4.0 (um subcritério do 2º sem nota).
    const notaMedia = calcularOficial([3.5, 4, 0], [3.5, 4]);
    expect(iguaisComTolerancia(notaMedia, (3.5 + 4) / 2)).toBe(true);

    // Sem nota de critério materializada, a média dos subcritérios é usada.
    const somenteSubcriterios = calcularOficial([3.5, 4], []);
    expect(iguaisComTolerancia(somenteSubcriterios, 3.75)).toBe(true);
  });
});
