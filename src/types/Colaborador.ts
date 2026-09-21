export type StatusColaborador =
  | "ATIVO"
  | "LICENCA"
  | "DESLIGADO";

export type FuncaoColaborador =
  | "GERENTE"
  | "COORDENADOR"
  | "CONSULTOR"
  | "ANALISTA"
  | "ESTAGIARIO";

export type SenioridadeColaborador =
  | "JUNIOR"
  | "PLENO"
  | "SENIOR";

export interface Colaborador {
  matricula: number;
  status: StatusColaborador;

  nome: string;
  email: string;
  cargo: string;
  area: string;

  funcao?: FuncaoColaborador;
  senioridade?: SenioridadeColaborador;
  gestorDiretoMatricula?: number;
  avaliadoresColegiadoMatriculas?: number[];

  // Campos temporários para compatibilidade durante a migração.
  respondePara: string;
  gerente?: string;

  dataAdmissao?: string;
  dataInicioLicenca?: string;
  dataFimLicenca?: string;
  dataDesligamento?: string;
}


/**
 * #333 — IDENTIDADE SOBERANA do ator, reconhecida pelo VÍNCULO
 * (estrutura_autorizacao.collaborator_id) + a PRÓPRIA entrada em
 * estrutura_pessoal. Difere do `Colaborador` legado em dois pontos:
 *
 * - `collaboratorId` é a chave CANÔNICA (UUID soberano);
 * - `matricula` é RÓTULO OPCIONAL (complemento da listagem do universo, gated
 *   por `collaborator.read`): sua ausência significa "não informada" e NUNCA
 *   impede reconhecer o usuário nem inventa um número.
 *
 * Quem exige matrícula numérica continua consumindo `Colaborador` (domínio
 * legado, inalterado); as superfícies pessoais consomem esta identidade.
 */
export interface IdentidadeColaborador extends Omit<Colaborador, "matricula"> {
  /**
   * UUID soberano do vínculo. Presente em toda identidade resolvida pelo
   * provider (#333); opcional no TIPO apenas porque o contexto também recebe
   * fixtures legadas (impersonação DEV), que não conhecem UUID.
   */
  readonly collaboratorId?: string;
  readonly matricula?: number;
}

/**
 * Funções avaliadas pela estrutura com gerente, coordenador direto e colegiado.
 * Estagiário segue o mesmo fluxo operacional de avaliação do Analista,
 * mas sem senioridade.
 *
 * F5-08 P6: **não é autoridade** para decisões de papel/elegibilidade do
 * cliente. Depois do cutover, quem decide é a ESTRUTURA SOBERANA
 * (`src/services/projecaoEstruturalSoberana.ts`), por fatos relacionais:
 * "tem gestor?", "o gestor é nível intermediário?", "há colegiado vigente?".
 * Este helper permanece como vocabulário do domínio (contratos F4-09/F5-06) e
 * não deve ser consumido por caminhos produtivos — a guarda
 * `estruturaUiSeguranca.test.ts` reprova qualquer consumidor novo.
 */
export function funcaoUsaEstruturaAvaliacaoAnalista(
  funcao: FuncaoColaborador | undefined
): boolean {
  return funcao === "ANALISTA" || funcao === "ESTAGIARIO";
}
