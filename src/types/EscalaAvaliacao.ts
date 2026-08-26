export type NotaEscala = 1 | 2 | 3 | 4 | 5;

export interface ItemEscalaAvaliacao {
  nota: NotaEscala;
  significado: string;
  descricao: string;
  cor: string;
  corFundo: string;
}

export type EscalaAvaliacao = ItemEscalaAvaliacao[];
