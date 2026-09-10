import type { CicloAvaliacao } from "../types/CicloAvaliacao";

/**
 * F5-06 (Issue #103) — confirmação da exclusão física do ciclo.
 *
 * A partir do cutover, o acervo de avaliações é SOMENTE LEITURA: nenhuma
 * avaliação é apagada como efeito colateral da exclusão do ciclo. Registros do
 * legado com dados preenchidos continuam impedindo a exclusão (fail-closed), e
 * registros vazios do legado também a impedem — a limpeza do legado pertence à
 * atividade de importação, não ao fluxo do produto.
 */
export function confirmarExclusaoCiclo(
  ciclo: CicloAvaliacao,
  confirmar: (mensagem: string) => boolean = window.confirm
): boolean {
  return confirmar(
    `Excluir ${ciclo.ano} • Ciclo ${ciclo.ciclo}?\n\nA exclusão física do ciclo não remove avaliações já registradas. Avaliações que já possuam dados impedem a exclusão.`
  );
}
