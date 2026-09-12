/**
 * F5-07 — PORTA ÚNICA das telas para o domínio soberano de colaboradores.
 *
 * Nenhuma página/componente importa o cliente Supabase nem conhece a Edge
 * Function: a construção do repositório e a orquestração vivem em
 * `infrastructure/` e neste módulo. Esta porta existe para que:
 *
 * - a organização ativa seja sempre tratada como INTENÇÃO de UX (a fronteira
 *   confiável a revalida contra a membership ativa do ator);
 * - a ausência de configuração de ambiente seja FAIL-CLOSED: sem caminho
 *   soberano as operações são recusadas com código público — nunca caem para o
 *   `localStorage` (sem dual-write, sem fallback silencioso);
 * - NEGAÇÃO nunca seja uma exceção: toda operação devolve
 *   `ResultadoColaboradores`, com o código público quando falha.
 *
 * Não há autorização aqui: identidade por UUID (`collaborators.id`), matrícula
 * como INTENÇÃO e `organization_id` apenas como intenção. Nada neste módulo
 * concede autoridade nem persiste localmente.
 */

import {
  criarServiceColaboradores,
  type ColaboradorSoberanoProjetado,
  type DependenciasServiceColaboradores,
  type EventoColaboradorProjetado,
  type ResultadoColaboradores,
  type ServiceColaboradores,
} from "./serviceColaboradores";
import type { EstruturaSoberana } from "../../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";

/** Projeção soberana do colaborador (espinha §3). */
export type ColaboradorSoberano = ColaboradorSoberanoProjetado;
/** Evento da linha do tempo append-only (§12). */
export type EventoColaborador = EventoColaboradorProjetado;
/** Resultado da porta: sucesso com dados ou falha com código público. */
export type { ResultadoColaboradores };

export interface DependenciasAcessoColaboradores {
  /** Injeção das operações (teste). Por padrão usa o caminho de produção. */
  readonly operacoes?: ServiceColaboradores;
  /** Injeção das dependências do service (teste). */
  readonly deps?: DependenciasServiceColaboradores;
}

/**
 * Instância resolvida uma única vez por sessão de página: a construção do
 * cliente Supabase é custosa e o caminho soberano é idempotente. `undefined` =
 * ainda não resolvido; `null` = ambiente sem caminho soberano (fail-closed).
 */
let operacoesMemoizadas: ServiceColaboradores | null | undefined;

/** Somente para testes: descarta a memoização do caminho soberano. */
export function redefinirAcessoColaboradoresSoberanos(): void {
  operacoesMemoizadas = undefined;
}

/**
 * Devolve as operações soberanas, ou `null` quando o ambiente não oferece o
 * caminho novo (fail-closed — nenhum fallback local é oferecido).
 */
export function obterOperacoesColaboradoresSoberanos(
  deps: DependenciasAcessoColaboradores = {}
): ServiceColaboradores | null {
  if (deps.operacoes) return deps.operacoes;
  if (operacoesMemoizadas !== undefined) return operacoesMemoizadas;

  operacoesMemoizadas = criarServiceColaboradores(deps.deps ?? {});
  return operacoesMemoizadas;
}

const ERRO_SEM_CAMINHO =
  "O caminho de colaboradores no PostgreSQL não está disponível neste ambiente.";

/**
 * Executa uma operação da porta. Nenhuma exceção escapa por negação: falha de
 * autorização/existência vem como `{ ok: false, codigo, mensagem }`. Falhas
 * inesperadas (rede/ambiente) viram `INTERNAL` — nunca leitura local silenciosa.
 */
async function executar<T>(
  deps: DependenciasAcessoColaboradores,
  operacao: (servico: ServiceColaboradores) => Promise<ResultadoColaboradores<T>>
): Promise<ResultadoColaboradores<T>> {
  const servico = obterOperacoesColaboradoresSoberanos(deps);
  if (!servico) {
    return { ok: false, codigo: "INTERNAL", mensagem: ERRO_SEM_CAMINHO };
  }
  try {
    return await operacao(servico);
  } catch {
    return {
      ok: false,
      codigo: "INTERNAL",
      mensagem: "Não foi possível concluir a operação de colaborador.",
    };
  }
}

// ---------------------------------------------------------------------------
// Leitura
// ---------------------------------------------------------------------------

export function listarColaboradores(
  entrada: {
    readonly organizationId?: string | null;
    readonly dataReferencia?: string;
    readonly status?: string;
    readonly unitId?: string;
    readonly busca?: string;
  } = {},
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<readonly ColaboradorSoberano[]>> {
  return executar(deps, (servico) => servico.listar(entrada));
}

/** Leitura por UUID canônico OU por matrícula (INTENÇÃO resolvida no servidor). */
export function obterColaborador(
  entrada: {
    readonly collaboratorId?: string;
    readonly matricula?: string;
    readonly organizationId?: string | null;
    readonly dataReferencia?: string;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<ColaboradorSoberano>> {
  return executar(deps, (servico) => servico.obter(entrada));
}

export function obterHistoricoColaborador(
  entrada: {
    readonly collaboratorId: string;
    readonly organizationId?: string | null;
    readonly dataReferencia?: string;
    readonly referenceCycleId?: string;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<readonly EventoColaborador[]>> {
  return executar(deps, (servico) => servico.obterHistorico(entrada));
}

// ---------------------------------------------------------------------------
// Colaborador (dados de pessoa, identificador e status)
// ---------------------------------------------------------------------------

export function criarColaborador(
  entrada: {
    readonly fullName: string;
    readonly email: string;
    readonly matricula: string;
    /** Idempotência (§13.5): gerado pelo chamador, único por organização. */
    readonly operationId: string;
    readonly admissionDate?: string;
    readonly statusInicial?: "active" | "leave";
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.criar(entrada));
}

export function editarColaborador(
  entrada: {
    readonly collaboratorId: string;
    readonly operationId: string;
    /** Versão lida na projeção: divergência ⇒ `CONFLICT` (§13.1). */
    readonly expectedVersion: number;
    readonly fullName?: string;
    readonly email?: string;
    readonly admissionDate?: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.editar(entrada));
}

export function definirIdentificadorColaborador(
  entrada: {
    readonly collaboratorId: string;
    readonly operationId: string;
    readonly novaMatricula: string;
    readonly vigencia: string;
    readonly motivo: string;
    readonly expectedVersion: number;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.definirIdentificador(entrada));
}

export function alterarStatusColaborador(
  entrada: {
    readonly collaboratorId: string;
    readonly operationId: string;
    readonly novoStatus: "active" | "leave" | "inactive";
    readonly vigencia: string;
    readonly motivo: string;
    readonly expectedVersion: number;
    readonly cycleScope?: "CICLO_ATUAL_E_POSTERIORES" | "SOMENTE_CICLOS_POSTERIORES";
    readonly referenceCycleId?: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.alterarStatus(entrada));
}

// ---------------------------------------------------------------------------
// Estrutura (plano administrativo — D19)
// ---------------------------------------------------------------------------

export function definirOcupacao(
  entrada: {
    readonly collaboratorId: string;
    readonly operationId: string;
    readonly positionId: string;
    readonly vigencia: string;
    readonly motivo: string;
    readonly cycleScope?: "CICLO_ATUAL_E_POSTERIORES" | "SOMENTE_CICLOS_POSTERIORES";
    readonly referenceCycleId?: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.definirOcupacao(entrada));
}

export function encerrarOcupacao(
  entrada: {
    readonly collaboratorId: string;
    readonly operationId: string;
    readonly vigencia: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<null>> {
  return executar(deps, (servico) => servico.encerrarOcupacao(entrada));
}

export function definirReportingLine(
  entrada: {
    readonly subordinatePositionId: string;
    readonly managerPositionId: string;
    readonly operationId: string;
    readonly vigencia: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.definirReportingLine(entrada));
}

export function encerrarReportingLine(
  entrada: {
    readonly subordinatePositionId: string;
    readonly operationId: string;
    readonly vigencia: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<null>> {
  return executar(deps, (servico) => servico.encerrarReportingLine(entrada));
}

export function definirResponsabilidadeTemporaria(
  entrada: {
    readonly positionId: string;
    readonly substituteCollaboratorId: string;
    readonly responsibilityType: "operational" | "evaluative" | "operational_evaluative";
    readonly operationId: string;
    readonly vigencia: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.definirResponsabilidade(entrada));
}

export function encerrarResponsabilidadeTemporaria(
  entrada: {
    readonly responsibilityId: string;
    readonly operationId: string;
    readonly vigencia: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<null>> {
  return executar(deps, (servico) => servico.encerrarResponsabilidade(entrada));
}

/** Sucessão avaliativa: reuso da RPC já existente (F3-09/F4-08). */
export function registrarSucessao(
  entrada: {
    readonly responsibilityIds: readonly string[];
    readonly successionDate: string;
    readonly operationId: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<null>> {
  return executar(deps, (servico) => servico.registrarSucessao(entrada));
}

// ---------------------------------------------------------------------------
// Catálogo (bootstrap mínimo — D16)
// ---------------------------------------------------------------------------

/** Bootstrap MÍNIMO e idempotente: apenas job_roles e seniority_levels (D16). */
export function bootstrapCatalogo(
  entrada: {
    readonly operationId: string;
    readonly jobRoles: readonly { readonly code: string; readonly name: string }[];
    readonly seniorityLevels: readonly string[];
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<null>> {
  return executar(deps, (servico) =>
    servico.bootstrapCatalogo({
      operationId: entrada.operationId,
      catalogo: {
        jobRoles: entrada.jobRoles,
        seniorityLevels: entrada.seniorityLevels,
      },
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    })
  );
}

// ---------------------------------------------------------------------------
// F5-08 P4 — ESTRUTURA ORGANIZACIONAL E CATÁLOGOS
//
// Leitura soberana (D16): `select` sob RLS own-tenant, sem capability e sem
// RPC de listagem. Escrita (D19): as 15 operações administrativas do P3 pela
// Edge `colaboradores`, que revalida capability efetiva e ator no servidor.
//
// Esta porta NÃO decide autorização nem tenant: envia `operationId`
// (idempotência), `expectedVersion` (concorrência otimista — sempre o valor
// lido do servidor), vigência e `motivo` obrigatório. Nada é gravado
// localmente e nenhuma identidade/tenant é fabricada.
// ---------------------------------------------------------------------------

/** Fotografia soberana da estrutura/catálogo do tenant (RLS F4-08). */
export type EstruturaSoberanaProjetada = EstruturaSoberana;

export function lerEstrutura(
  entrada: { readonly organizationId?: string | null } = {},
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<EstruturaSoberanaProjetada>> {
  return executar(deps, (servico) => servico.lerEstrutura(entrada));
}

export function criarUnidade(
  entrada: {
    readonly operationId: string;
    readonly nome: string;
    readonly validFrom: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.criarUnidade(entrada));
}

export function renomearUnidade(
  entrada: {
    readonly operationId: string;
    readonly unidadeId: string;
    readonly nome: string;
    readonly expectedVersion: number;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.renomearUnidade(entrada));
}

export function encerrarUnidade(
  entrada: {
    readonly operationId: string;
    readonly unidadeId: string;
    readonly validTo: string;
    readonly expectedVersion: number;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.encerrarUnidade(entrada));
}

/** `parentUnitId: null` define a unidade como RAIZ no novo período. */
export function definirParentUnidade(
  entrada: {
    readonly operationId: string;
    readonly unidadeId: string;
    readonly parentUnitId: string | null;
    readonly validFrom: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.definirParentUnidade(entrada));
}

/** Encerra o período pai/filho vigente: a unidade volta a ser raiz. */
export function encerrarParentUnidade(
  entrada: {
    readonly operationId: string;
    readonly unidadeId: string;
    readonly validTo: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.encerrarParentUnidade(entrada));
}

export function criarPosicao(
  entrada: {
    readonly operationId: string;
    readonly unidadeId: string;
    readonly jobRoleId: string;
    readonly seniorityLevelId: string | null;
    readonly validFrom: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.criarPosicao(entrada));
}

export function encerrarPosicao(
  entrada: {
    readonly operationId: string;
    readonly posicaoId: string;
    readonly validTo: string;
    readonly expectedVersion: number;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.encerrarPosicao(entrada));
}

/**
 * Define a versão vigente do colegiado do avaliado. Lista vazia é "sem
 * colegiado" EXPLÍCITO (0..N membros — nenhum teto no cliente).
 */
export function definirColegiado(
  entrada: {
    readonly operationId: string;
    readonly collaboratorId: string;
    readonly memberCollaboratorIds: readonly string[];
    readonly validFrom: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.definirColegiado(entrada));
}

export function encerrarColegiado(
  entrada: {
    readonly operationId: string;
    readonly collaboratorId: string;
    readonly validTo: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.encerrarColegiado(entrada));
}

export function criarCargo(
  entrada: {
    readonly operationId: string;
    readonly nome: string;
    readonly code: string | null;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.criarCargo(entrada));
}

export function renomearCargo(
  entrada: {
    readonly operationId: string;
    readonly jobRoleId: string;
    readonly nome: string;
    readonly expectedVersion: number;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.renomearCargo(entrada));
}

export function alterarStatusCargo(
  entrada: {
    readonly operationId: string;
    readonly jobRoleId: string;
    readonly status: "active" | "disabled";
    readonly expectedVersion: number;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.alterarStatusCargo(entrada));
}

export function criarSenioridade(
  entrada: {
    readonly operationId: string;
    readonly nome: string;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<string>> {
  return executar(deps, (servico) => servico.criarSenioridade(entrada));
}

export function renomearSenioridade(
  entrada: {
    readonly operationId: string;
    readonly seniorityLevelId: string;
    readonly nome: string;
    readonly expectedVersion: number;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.renomearSenioridade(entrada));
}

export function alterarStatusSenioridade(
  entrada: {
    readonly operationId: string;
    readonly seniorityLevelId: string;
    readonly status: "active" | "disabled";
    readonly expectedVersion: number;
    readonly motivo: string;
    readonly organizationId?: string | null;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<ResultadoColaboradores<number>> {
  return executar(deps, (servico) => servico.alterarStatusSenioridade(entrada));
}
