export type NotaEscala = 1 | 2 | 3 | 4 | 5;

export interface ItemEscalaAvaliacao {
  nota: NotaEscala;
  significado: string;
  descricao: string;
  cor: string;
  corFundo: string;

  /**
   * Menor média que pertence a esta faixa.
   * A faixa termina imediatamente antes do limite mínimo da nota seguinte.
   */
  limiteMinimo: number;
}

export type EscalaAvaliacao = ItemEscalaAvaliacao[];
