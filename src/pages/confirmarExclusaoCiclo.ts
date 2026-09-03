import type { CicloAvaliacao } from "../types/CicloAvaliacao";

export function confirmarExclusaoCiclo(
  ciclo: CicloAvaliacao,
  confirmar: (mensagem: string) => boolean = window.confirm
): boolean {
  return confirmar(
    `Excluir ${ciclo.ano} • Ciclo ${ciclo.ciclo}?\n\nAvaliações vazias criadas automaticamente também serão excluídas. Avaliações que já possuam dados impedem a exclusão.`
  );
}
