import type { ImpactoTemporalPeriodoCiclo } from "../types/CicloAvaliacao";

export function confirmarCorrecaoPeriodoComImpacto(
  impacto: ImpactoTemporalPeriodoCiclo,
  confirmar: (mensagem: string) => boolean = window.confirm
): boolean {
  if (impacto.total === 0) return true;

  return confirmar(
    `A correção deixará ${impacto.total} registro${
      impacto.total === 1 ? "" : "s"
    } fora das novas datas: ${impacto.avaliacoes.quantidade} avaliação(ões), ${
      impacto.metas.quantidade
    } meta(s) e ${impacto.observacoes.quantidade} observação(ões). ` +
      "Esses registros serão preservados e continuarão vinculados ao ciclo. Deseja confirmar?"
  );
}
