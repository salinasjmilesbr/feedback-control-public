/**
 * F5-07 — REPOSITÓRIO do caminho soberano de colaboradores.
 *
 * Fronteira única entre a aplicação (services/porta das telas) e o back-end
 * soberano:
 *
 *   UI/página → porta única → service → REPOSITÓRIO → Edge `colaboradores`
 *            → validação de forma → alvo soberano → gate (Policy Engine ou
 *              plano administrativo D19) → RPC PostgreSQL
 *
 * Regras preservadas:
 * - NENHUMA regra de autorização aqui: o cliente envia apenas INTENÇÃO
 *   (`organization_id` é intenção revalidada server-side) e traduz o código
 *   público de erro;
 * - identidade por UUID (`collaborators.id`); matrícula é INTENÇÃO;
 * - `localStorage` não participa deste caminho (sem dual-write, sem cache de
 *   decisão);
 * - nenhuma mensagem interna do banco é exposta: a Edge devolve apenas
 *   `{ ok, operacao, resultado }` ou `{ ok: false, error: { code, message } }`.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { CodigoPublico } from "./contrato.ts";

export const FUNCAO_COLABORADORES = "colaboradores";

/** Projeção soberana do colaborador (espinha §3). */
export interface ColaboradorSoberano {
  readonly collaboratorId: string;
  /** Rótulo da matrícula vigente (`collaborator_identifiers.business_code`). */
  readonly matricula: string | null;
  readonly fullName: string;
  readonly email: string;
  readonly status: string;
  readonly admissionDate: string | null;
  /** Estrutura DERIVADA da ocupação vigente na data — nunca coluna do cadastro. */
  readonly unitId: string | null;
  readonly unitName: string | null;
  readonly jobRoleCode: string | null;
  readonly jobRoleName: string | null;
  readonly seniorityName: string | null;
  readonly managerCollaboratorId: string | null;
  readonly managerFullName: string | null;
  /** Versão otimista (§13.1) — obrigatória nas mutações de linha existente. */
  readonly version: number;
}

/** Evento da linha do tempo append-only (§12). */
export interface EventoColaborador {
  readonly eventId: string;
  readonly eventType: string;
  readonly effectiveDate: string;
  readonly reason: string;
  readonly cycleScope: string;
  readonly referenceCycleId: string | null;
  readonly actorUserProfileId: string;
  readonly actorFullName: string | null;
  readonly beforeValue: unknown;
  readonly afterValue: unknown;
  readonly createdAt: string;
}

export interface ErroRepositorioColaboradores {
  readonly code: CodigoPublico;
  readonly message: string;
}

export type ResultadoRepositorioColaboradores<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: ErroRepositorioColaboradores };

// ---------------------------------------------------------------------------
// Entradas de cada operação (INTENÇÃO da tela)
// ---------------------------------------------------------------------------

export interface EntradaListarColaboradores {
  readonly organizationId?: string | null;
  readonly dataReferencia?: string;
  readonly status?: string;
  readonly unitId?: string;
  readonly busca?: string;
}

export interface EntradaObterColaborador {
  readonly organizationId?: string | null;
  /** UUID canônico. */
  readonly collaboratorId?: string;
  /**
   * Matrícula como INTENÇÃO (compatibilidade de URL/legado): resolvida no
   * servidor; ambígua ou ausente ⇒ `NOT_FOUND`.
   */
  readonly matricula?: string;
  readonly dataReferencia?: string;
}

export interface EntradaCriarColaborador {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly fullName: string;
  readonly email: string;
  readonly matricula: string;
  readonly admissionDate?: string;
  readonly statusInicial?: "active" | "leave";
}

export interface EntradaEditarColaborador {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly collaboratorId: string;
  readonly fullName?: string;
  readonly email?: string;
  readonly admissionDate?: string;
  readonly expectedVersion: number;
}

export interface EntradaDefinirIdentificador {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly collaboratorId: string;
  readonly novaMatricula: string;
  readonly vigencia: string;
  readonly motivo: string;
  readonly expectedVersion: number;
}

export interface EntradaAlterarStatus {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly collaboratorId: string;
  readonly novoStatus: "active" | "leave" | "inactive";
  readonly vigencia: string;
  readonly motivo: string;
  readonly cycleScope?: "CICLO_ATUAL_E_POSTERIORES" | "SOMENTE_CICLOS_POSTERIORES";
  readonly referenceCycleId?: string;
  readonly expectedVersion: number;
}

export interface EntradaDefinirOcupacao {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly collaboratorId: string;
  readonly positionId: string;
  readonly vigencia: string;
  readonly motivo: string;
  readonly cycleScope?: "CICLO_ATUAL_E_POSTERIORES" | "SOMENTE_CICLOS_POSTERIORES";
  readonly referenceCycleId?: string;
}

export interface EntradaEncerrarOcupacao {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly collaboratorId: string;
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaDefinirReportingLine {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly subordinatePositionId: string;
  readonly managerPositionId: string;
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaEncerrarReportingLine {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly subordinatePositionId: string;
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaDefinirResponsabilidade {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly positionId: string;
  readonly substituteCollaboratorId: string;
  readonly responsibilityType: "operational" | "evaluative" | "operational_evaluative";
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaEncerrarResponsabilidade {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly responsibilityId: string;
  readonly vigencia: string;
  readonly motivo: string;
}

export interface EntradaRegistrarSucessao {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly responsibilityIds: readonly string[];
  readonly successionDate: string;
  readonly motivo: string;
}

export interface EntradaBootstrapCatalogo {
  readonly organizationId?: string | null;
  readonly operationId: string;
  readonly catalogo: {
    readonly jobRoles: readonly { readonly code: string; readonly name: string }[];
    readonly seniorityLevels: readonly string[];
  };
}

/**
 * Resultado de LEITURA da projeção. `resultadoCru` preserva a linha como o
 * servidor a devolveu (a projeção tipada cobre o contrato da espinha; campos
 * adicionais da view não são descartados nem transformados no cliente).
 */
export interface LeituraColaboradorSoberano {
  readonly colaborador: ColaboradorSoberano;
  readonly resultadoCru: unknown;
}

export interface RepositorioColaboradores {
  listar(
    entrada: EntradaListarColaboradores
  ): Promise<ResultadoRepositorioColaboradores<readonly ColaboradorSoberano[]>>;
  obter(
    entrada: EntradaObterColaborador
  ): Promise<ResultadoRepositorioColaboradores<LeituraColaboradorSoberano>>;
  criar(entrada: EntradaCriarColaborador): Promise<ResultadoRepositorioColaboradores<string>>;
  editar(
    entrada: EntradaEditarColaborador
  ): Promise<ResultadoRepositorioColaboradores<number>>;
  definirIdentificador(
    entrada: EntradaDefinirIdentificador
  ): Promise<ResultadoRepositorioColaboradores<number>>;
  alterarStatus(entrada: EntradaAlterarStatus): Promise<ResultadoRepositorioColaboradores<number>>;
  definirOcupacao(
    entrada: EntradaDefinirOcupacao
  ): Promise<ResultadoRepositorioColaboradores<string>>;
  encerrarOcupacao(
    entrada: EntradaEncerrarOcupacao
  ): Promise<ResultadoRepositorioColaboradores<null>>;
  definirReportingLine(
    entrada: EntradaDefinirReportingLine
  ): Promise<ResultadoRepositorioColaboradores<string>>;
  encerrarReportingLine(
    entrada: EntradaEncerrarReportingLine
  ): Promise<ResultadoRepositorioColaboradores<null>>;
  definirResponsabilidade(
    entrada: EntradaDefinirResponsabilidade
  ): Promise<ResultadoRepositorioColaboradores<string>>;
  encerrarResponsabilidade(
    entrada: EntradaEncerrarResponsabilidade
  ): Promise<ResultadoRepositorioColaboradores<null>>;
  registrarSucessao(
    entrada: EntradaRegistrarSucessao
  ): Promise<ResultadoRepositorioColaboradores<null>>;
  obterHistorico(entrada: {
    readonly organizationId?: string | null;
    readonly collaboratorId: string;
    /**
     * RESERVADOS: a assinatura congelada da RPC de histórico não recebe data de
     * referência nem ciclo (o filtro por ciclo depende da F5-09). Aceitos para
     * compatibilidade da porta; não são enviados à fronteira.
     */
    readonly dataReferencia?: string;
    readonly referenceCycleId?: string;
  }): Promise<ResultadoRepositorioColaboradores<readonly EventoColaborador[]>>;
  bootstrapCatalogo(
    entrada: EntradaBootstrapCatalogo
  ): Promise<ResultadoRepositorioColaboradores<null>>;
}

// ---------------------------------------------------------------------------
// Adapter Supabase (Edge Function `colaboradores`)
// ---------------------------------------------------------------------------

interface RespostaEdge {
  ok?: unknown;
  operacao?: unknown;
  resultado?: unknown;
  error?: { code?: unknown; message?: unknown };
}

function codigoPublico(valor: unknown): CodigoPublico {
  switch (valor) {
    case "FORBIDDEN":
    case "NOT_FOUND":
    case "CONFLICT":
    case "INVALID_INPUT":
    case "INTERNAL":
    case "NOT_AUTHORIZED":
    case "METHOD_NOT_ALLOWED":
      return valor;
    default:
      return "INTERNAL";
  }
}

function comoRegistro(valor: unknown): Record<string, unknown> {
  if (typeof valor !== "object" || valor === null || Array.isArray(valor)) {
    throw new Error("Resposta inesperada do servidor.");
  }
  return valor as Record<string, unknown>;
}

function texto(valor: unknown): string {
  return typeof valor === "string" ? valor : "";
}

function textoOpcional(valor: unknown): string | null {
  return typeof valor === "string" && valor.length > 0 ? valor : null;
}

function numero(valor: unknown): number {
  return typeof valor === "number" && Number.isFinite(valor) ? valor : Number(valor ?? 0);
}

export function projetarColaborador(valor: unknown): ColaboradorSoberano {
  const registro = comoRegistro(valor);
  return {
    collaboratorId: texto(registro.collaborator_id),
    matricula: textoOpcional(registro.matricula),
    fullName: texto(registro.full_name),
    email: texto(registro.email),
    status: texto(registro.status),
    admissionDate: textoOpcional(registro.admission_date),
    unitId: textoOpcional(registro.unit_id),
    unitName: textoOpcional(registro.unit_name),
    jobRoleCode: textoOpcional(registro.job_role_code),
    jobRoleName: textoOpcional(registro.job_role_name),
    seniorityName: textoOpcional(registro.seniority_name),
    managerCollaboratorId: textoOpcional(registro.manager_collaborator_id),
    managerFullName: textoOpcional(registro.manager_full_name),
    version: numero(registro.version),
  };
}

function projetarEvento(valor: unknown): EventoColaborador {
  const registro = comoRegistro(valor);
  return {
    eventId: texto(registro.event_id),
    eventType: texto(registro.event_type),
    effectiveDate: texto(registro.effective_date),
    reason: texto(registro.reason),
    cycleScope: texto(registro.cycle_scope),
    referenceCycleId: textoOpcional(registro.reference_cycle_id),
    actorUserProfileId: texto(registro.actor_user_profile_id),
    actorFullName: textoOpcional(registro.actor_full_name),
    beforeValue: registro.before_value ?? null,
    afterValue: registro.after_value ?? null,
    createdAt: texto(registro.created_at),
  };
}

/**
 * Constrói o corpo (snake_case) do payload da Edge. `organization_id` e
 * `matricula` são INTENÇÃO; nunca `capability`, `role`, `scope` nem identidade
 * do ator. Sem organização resolvida o corpo é enviado com o valor vazio e a
 * Edge responde `INVALID_INPUT`/`FORBIDDEN` (fail-closed) — o service nunca
 * chega aqui sem organização.
 */
function montarCorpo(
  operacao: string,
  organizationId: string | null | undefined,
  extras: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    operacao,
    organization_id: typeof organizationId === "string" ? organizationId : "",
    ...extras,
  };
}

export function criarRepositorioColaboradoresSupabase(
  cliente: SupabaseClient
): RepositorioColaboradores {
  async function invocar<T>(
    corpo: Record<string, unknown>,
    projetar: (resultado: unknown) => T
  ): Promise<ResultadoRepositorioColaboradores<T>> {
    const { data, error } = await cliente.functions.invoke<RespostaEdge>(FUNCAO_COLABORADORES, {
      body: corpo,
    });

    if (error) {
      // A Edge devolve `{ error: { code, message } }`; o supabase-js expõe o
      // corpo em `error.context` quando o status não é 2xx.
      const contexto = (error as { context?: { error?: { code?: unknown; message?: unknown } } })
        .context;
      return {
        ok: false,
        error: {
          code: codigoPublico(contexto?.error?.code),
          message:
            typeof contexto?.error?.message === "string"
              ? contexto.error.message
              : "Operação de colaborador recusada.",
        },
      };
    }

    if (data?.error) {
      return {
        ok: false,
        error: {
          code: codigoPublico(data.error.code),
          message:
            typeof data.error.message === "string"
              ? data.error.message
              : "Operação de colaborador recusada.",
        },
      };
    }

    try {
      return { ok: true, data: projetar(data?.resultado ?? null) };
    } catch {
      return {
        ok: false,
        error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
      };
    }
  }

  return {
    listar: (entrada) =>
      invocar(
        montarCorpo("collaborator.listar", entrada.organizationId, {
          ...(entrada.dataReferencia ? { data_referencia: entrada.dataReferencia } : {}),
          ...(entrada.status || entrada.unitId || entrada.busca
            ? {
                filtros: {
                  ...(entrada.status ? { status: entrada.status } : {}),
                  ...(entrada.unitId ? { unit_id: entrada.unitId } : {}),
                  ...(entrada.busca ? { busca: entrada.busca } : {}),
                },
              }
            : {}),
        }),
        (resultado) => {
          const linhas = Array.isArray(resultado) ? resultado : [];
          return linhas.map(projetarColaborador);
        }
      ),

    obter: (entrada) =>
      invocar(
        montarCorpo("collaborator.obter", entrada.organizationId, {
          ...(entrada.collaboratorId ? { collaborator_id: entrada.collaboratorId } : {}),
          ...(entrada.matricula ? { matricula: entrada.matricula } : {}),
          ...(entrada.dataReferencia ? { data_referencia: entrada.dataReferencia } : {}),
        }),
        (resultado) => ({
          colaborador: projetarColaborador(resultado),
          resultadoCru: resultado,
        })
      ),

    criar: (entrada) =>
      invocar(
        montarCorpo("collaborator.criar", entrada.organizationId, {
          operation_id: entrada.operationId,
          full_name: entrada.fullName,
          email: entrada.email,
          matricula: entrada.matricula,
          ...(entrada.admissionDate ? { admission_date: entrada.admissionDate } : {}),
          ...(entrada.statusInicial ? { status_inicial: entrada.statusInicial } : {}),
        }),
        (resultado) => {
          const id = typeof resultado === "string" ? resultado : "";
          if (!id) throw new Error("id de colaborador ausente");
          return id;
        }
      ),

    editar: (entrada) =>
      invocar(
        montarCorpo("collaborator.editar", entrada.organizationId, {
          operation_id: entrada.operationId,
          collaborator_id: entrada.collaboratorId,
          ...(entrada.fullName ? { full_name: entrada.fullName } : {}),
          ...(entrada.email ? { email: entrada.email } : {}),
          ...(entrada.admissionDate ? { admission_date: entrada.admissionDate } : {}),
          expected_version: entrada.expectedVersion,
        }),
        (resultado) => numero(resultado)
      ),

    definirIdentificador: (entrada) =>
      invocar(
        montarCorpo("collaborator.identificador.definir", entrada.organizationId, {
          operation_id: entrada.operationId,
          collaborator_id: entrada.collaboratorId,
          nova_matricula: entrada.novaMatricula,
          vigencia: entrada.vigencia,
          motivo: entrada.motivo,
          expected_version: entrada.expectedVersion,
        }),
        (resultado) => numero(resultado)
      ),

    alterarStatus: (entrada) =>
      invocar(
        montarCorpo("collaborator.status.alterar", entrada.organizationId, {
          operation_id: entrada.operationId,
          collaborator_id: entrada.collaboratorId,
          novo_status: entrada.novoStatus,
          vigencia: entrada.vigencia,
          motivo: entrada.motivo,
          ...(entrada.cycleScope ? { cycle_scope: entrada.cycleScope } : {}),
          ...(entrada.referenceCycleId ? { reference_cycle_id: entrada.referenceCycleId } : {}),
          expected_version: entrada.expectedVersion,
        }),
        (resultado) => numero(resultado)
      ),

    definirOcupacao: (entrada) =>
      invocar(
        montarCorpo("colaborador.ocupacao.definir", entrada.organizationId, {
          operation_id: entrada.operationId,
          collaborator_id: entrada.collaboratorId,
          position_id: entrada.positionId,
          vigencia: entrada.vigencia,
          motivo: entrada.motivo,
          ...(entrada.cycleScope ? { cycle_scope: entrada.cycleScope } : {}),
          ...(entrada.referenceCycleId ? { reference_cycle_id: entrada.referenceCycleId } : {}),
        }),
        (resultado) => texto(resultado)
      ),

    encerrarOcupacao: (entrada) =>
      invocar(
        montarCorpo("colaborador.ocupacao.encerrar", entrada.organizationId, {
          operation_id: entrada.operationId,
          collaborator_id: entrada.collaboratorId,
          vigencia: entrada.vigencia,
          motivo: entrada.motivo,
        }),
        () => null
      ),

    definirReportingLine: (entrada) =>
      invocar(
        montarCorpo("estrutura.reporting.definir", entrada.organizationId, {
          operation_id: entrada.operationId,
          subordinate_position_id: entrada.subordinatePositionId,
          manager_position_id: entrada.managerPositionId,
          vigencia: entrada.vigencia,
          motivo: entrada.motivo,
        }),
        (resultado) => texto(resultado)
      ),

    encerrarReportingLine: (entrada) =>
      invocar(
        montarCorpo("estrutura.reporting.encerrar", entrada.organizationId, {
          operation_id: entrada.operationId,
          subordinate_position_id: entrada.subordinatePositionId,
          vigencia: entrada.vigencia,
          motivo: entrada.motivo,
        }),
        () => null
      ),

    definirResponsabilidade: (entrada) =>
      invocar(
        montarCorpo("estrutura.responsabilidade.definir", entrada.organizationId, {
          operation_id: entrada.operationId,
          position_id: entrada.positionId,
          substitute_collaborator_id: entrada.substituteCollaboratorId,
          responsibility_type: entrada.responsibilityType,
          vigencia: entrada.vigencia,
          motivo: entrada.motivo,
        }),
        (resultado) => texto(resultado)
      ),

    encerrarResponsabilidade: (entrada) =>
      invocar(
        montarCorpo("estrutura.responsabilidade.encerrar", entrada.organizationId, {
          operation_id: entrada.operationId,
          responsibility_id: entrada.responsibilityId,
          vigencia: entrada.vigencia,
          motivo: entrada.motivo,
        }),
        () => null
      ),

    registrarSucessao: (entrada) =>
      invocar(
        montarCorpo("estrutura.sucessao.registrar", entrada.organizationId, {
          operation_id: entrada.operationId,
          responsibility_ids: entrada.responsibilityIds,
          succession_date: entrada.successionDate,
          motivo: entrada.motivo,
        }),
        () => null
      ),

    obterHistorico: (entrada) =>
      invocar(
        // A assinatura CONGELADA de `colaborador_historico_listar` (espinha §1.4)
        // recebe apenas organização, ator e colaborador: a linha do tempo é
        // integral e ordenada por vigência/created_at. `dataReferencia` e
        // `referenceCycleId` NÃO são enviados (o PostgREST recusaria a chamada
        // por argumento inexistente); o escopo por ciclo é registrado no evento
        // e o filtro por ciclo depende da entidade soberana de ciclo (F5-09).
        montarCorpo("colaborador.historico.listar", entrada.organizationId, {
          collaborator_id: entrada.collaboratorId,
        }),
        (resultado) => {
          const linhas = Array.isArray(resultado) ? resultado : [];
          return linhas.map(projetarEvento);
        }
      ),

    bootstrapCatalogo: (entrada) =>
      invocar(
        montarCorpo("colaborador.catalogo.bootstrap", entrada.organizationId, {
          operation_id: entrada.operationId,
          catalogo: {
            job_roles: entrada.catalogo.jobRoles.map((item) => ({
              code: item.code,
              name: item.name,
            })),
            seniority_levels: [...entrada.catalogo.seniorityLevels],
          },
        }),
        () => null
      ),
  };
}
