import type { CicloAvaliacao } from "../../types/CicloAvaliacao";

/** Recorte síncrono de consulta e cadastro; lifecycle continua nos serviços atuais. */
export interface CycleRepository {
  getCiclosAvaliacao(): CicloAvaliacao[];
  getCicloAtivo(): CicloAvaliacao | undefined;
  criarCiclo(
    ano: number,
    ciclo: 1 | 2 | 3,
    dataInicio: string,
    dataFim: string,
    quantidadeMetasNegocio: 0 | 1 | 2 | 3,
    quantidadeMetasIndividuais: 0 | 1 | 2 | 3,
    ativarAgora?: boolean
  ): CicloAvaliacao;
}
