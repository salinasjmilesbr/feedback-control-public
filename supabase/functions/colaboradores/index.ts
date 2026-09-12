// F5-07 — Edge Function `colaboradores`: a FRONTEIRA CONFIÁVEL do domínio de
// colaboradores e histórico organizacional (§7/§8 do desenho FECHADO).
//
// Responsabilidade: resolver a identidade SOBERANA do chamador (`auth.getUser`),
// validar a FORMA da intenção, revalidar a organização contra membership ativa,
// resolver o alvo soberano (matrícula é INTENÇÃO), decidir pelo gate do plano
// correto (funcional = Policy Engine; administrativo = D19) e SÓ ENTÃO executar
// as RPC PostgreSQL com a credencial `service_role`, passando o ator VERIFICADO
// como parâmetro. O JWT do usuário NUNCA é propagado ao banco.
//
// POR QUE `service_role` NÃO permite falsificar o ator:
//   - a credencial apenas ELEVA privilégios (BYPASSRLS); NÃO define `auth.uid()`;
//   - a identidade vem do JWT validado por `auth.getUser` neste runtime;
//   - as RPC recebem `p_actor_user_profile_id` VERIFICADO e revalidam
//     perfil/membership/tenant na MESMA transação (defesa em profundidade);
//   - o JWT do usuário não é propagado (senão o PostgREST assumiria a role
//     `authenticated` e perderia o EXECUTE restrito a `service_role`).
//
// A matrícula NUNCA atravessa como identidade: o que chega ao banco é o UUID
// resolvido (`collaborators.id`).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  colaboradores,
  type ContextoAtorColaborador,
  type DepsColaboradores,
  type LinhaCapability,
  type OperacaoExecutavel,
  type ResultadoRpcColaborador,
} from "./core.ts";
import {
  avaliarOperacaoAutorizacao,
  type DepsContextoAutorizacao,
} from "../../../src/authorization/contextoAutorizacao.ts";
import type { AuthIdentity } from "../../../src/auth/tipos.ts";
import { capabilityCanonica } from "../../../src/authorization/catalogoCapabilities.ts";
import type { Capability } from "../../../src/authorization/Capability.ts";
import type { CapabilityComEscopos } from "../../../src/authorization/providers/reais.ts";
import type { ScopeType } from "../../../src/authorization/policyEngine/types.ts";
import type { RecursoSoberanoCarregado } from "../../../src/authorization/resourceContextReal.ts";
import {
  DEFINICAO_POR_OPERACAO,
  type CodigoPublico,
} from "../../../src/infrastructure/supabase/colaboradores/contrato.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

interface LinhaCapabilityEscopo {
  capability_code: string;
  scope_type: string;
  organizational_unit_id: string | null;
}

interface LinhaAlvoEscopo {
  collaborator_id: string | null;
  position_id: string | null;
}

/**
 * `colaborador_visao_obter` devolve CONJUNTO (vazio = inexistente/outro
 * tenant). A lista é normalizada para linha única (`null` quando vazia) — o
 * vazio vira `NOT_FOUND` no núcleo, nunca um erro interno.
 */
function resultadoDeArray(valor: unknown): unknown {
  if (Array.isArray(valor)) return valor.length > 0 ? valor[0] : null;
  return valor;
}

/** Normaliza o código público do Policy Engine (fail-closed para o resto). */
function codigoPublicoDaNegacao(valor: unknown): CodigoPublico {
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
      return "FORBIDDEN";
  }
}

Deno.serve(async (req) => {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    return json(
      { error: { code: "INTERNAL", message: "Configuração do servidor indisponível." } },
      500
    );
  }

  // Cliente privilegiado (`service_role`), SEM sessão e SEM o JWT do usuário.
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ---------------------------------------------------------------------------
  // Execução privilegiada: RPC `colaborador_*` / `estrutura_*` (SECURITY
  // INVOKER, EXECUTE só `service_role`) com o ator VERIFICADO. O JWT do usuário
  // NÃO é propagado; a matrícula NÃO é parâmetro (o UUID resolvido é).
  // ---------------------------------------------------------------------------
  async function executarRpc(
    execucao: OperacaoExecutavel,
    ctx: ContextoAtorColaborador
  ): Promise<ResultadoRpcColaborador> {
    const ator = ctx.actorUserProfileId;
    const org = ctx.organizationId;
    const colaborador = ctx.collaboratorId;
    const data = ctx.dataReferencia;

    switch (execucao.operacao) {
      case "collaborator.listar":
        return admin.rpc("colaborador_visao_listar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_data: data,
          p_filtros: ctx.filtrosListar,
        });

      case "collaborator.obter":
        if (!colaborador) {
          return { error: { code: "F5_07_NOT_FOUND", message: "Alvo não resolvido." } };
        }
        {
          const resultado = await admin.rpc("colaborador_visao_obter", {
            p_organization_id: org,
            p_actor_user_profile_id: ator,
            p_collaborator_id: colaborador,
            p_data: data,
          });
          if (resultado.error) return resultado;
          return { data: resultadoDeArray(resultado.data) };
        }

      case "collaborator.criar":
        return admin.rpc("colaborador_criar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_full_name: execucao.entrada.full_name,
          p_email: execucao.entrada.email,
          p_matricula: execucao.entrada.matricula,
          p_admission_date: execucao.entrada.admission_date ?? null,
          p_status_inicial: execucao.entrada.status_inicial ?? "active",
        });

      case "collaborator.editar":
        return admin.rpc("colaborador_editar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_collaborator_id: execucao.entrada.collaborator_id,
          p_full_name: execucao.entrada.full_name ?? null,
          p_email: execucao.entrada.email ?? null,
          p_admission_date: execucao.entrada.admission_date ?? null,
          p_expected_version: execucao.entrada.expected_version,
        });

      case "collaborator.identificador.definir":
        return admin.rpc("colaborador_identificador_definir", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_collaborator_id: execucao.entrada.collaborator_id,
          p_nova_matricula: execucao.entrada.nova_matricula,
          p_vigencia: execucao.entrada.vigencia,
          p_motivo: execucao.entrada.motivo,
          p_expected_version: execucao.entrada.expected_version,
        });

      case "collaborator.status.alterar":
        return admin.rpc("colaborador_status_alterar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_collaborator_id: execucao.entrada.collaborator_id,
          p_novo_status: execucao.entrada.novo_status,
          p_vigencia: execucao.entrada.vigencia,
          p_motivo: execucao.entrada.motivo,
          p_cycle_scope: execucao.entrada.cycle_scope ?? "CICLO_ATUAL_E_POSTERIORES",
          p_reference_cycle_id: execucao.entrada.reference_cycle_id ?? null,
          p_expected_version: execucao.entrada.expected_version,
        });

      case "colaborador.ocupacao.definir":
        return admin.rpc("estrutura_ocupacao_definir", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_collaborator_id: execucao.entrada.collaborator_id,
          p_position_id: execucao.entrada.position_id,
          p_vigencia: execucao.entrada.vigencia,
          p_motivo: execucao.entrada.motivo,
          p_cycle_scope: execucao.entrada.cycle_scope ?? "CICLO_ATUAL_E_POSTERIORES",
          p_reference_cycle_id: execucao.entrada.reference_cycle_id ?? null,
        });

      case "colaborador.ocupacao.encerrar":
        return admin.rpc("estrutura_ocupacao_encerrar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_collaborator_id: execucao.entrada.collaborator_id,
          p_vigencia: execucao.entrada.vigencia,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.reporting.definir":
        return admin.rpc("estrutura_reporting_definir", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_subordinate_position_id: execucao.entrada.subordinate_position_id,
          p_manager_position_id: execucao.entrada.manager_position_id,
          p_vigencia: execucao.entrada.vigencia,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.reporting.encerrar":
        return admin.rpc("estrutura_reporting_encerrar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_subordinate_position_id: execucao.entrada.subordinate_position_id,
          p_vigencia: execucao.entrada.vigencia,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.responsabilidade.definir":
        return admin.rpc("estrutura_responsabilidade_definir", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_position_id: execucao.entrada.position_id,
          p_substitute_collaborator_id: execucao.entrada.substitute_collaborator_id,
          p_responsibility_type: execucao.entrada.responsibility_type,
          p_vigencia: execucao.entrada.vigencia,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.responsabilidade.encerrar":
        return admin.rpc("estrutura_responsabilidade_encerrar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_responsibility_id: execucao.entrada.responsibility_id,
          p_vigencia: execucao.entrada.vigencia,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.sucessao.registrar":
        // RPC JÁ EXISTENTE (F3-09/F4-08) — nenhuma função nova de sucessão.
        // `p_author_user_profile_id` = ator VERIFICADO (autoria soberana).
        return admin.rpc("registrar_sucessao_avaliador", {
          p_responsibility_ids: execucao.entrada.responsibility_ids,
          p_succession_date: execucao.entrada.succession_date,
          p_motive: execucao.entrada.motivo,
          p_author_user_profile_id: ator,
        });

      case "colaborador.historico.listar":
        if (!colaborador) {
          return { error: { code: "F5_07_NOT_FOUND", message: "Alvo não resolvido." } };
        }
        // Assinatura CONGELADA da RPC (espinha §1.4): a linha do tempo é
        // integral, ordenada por vigência/created_at. A data de referência e o
        // ciclo NÃO são parâmetros desta função — enviá-los faria o PostgREST
        // responder "function not found". O escopo por ciclo é REGISTRADO no
        // evento (§11.2) e projetado na leitura; filtrar por ciclo depende da
        // entidade de ciclo soberana (F5-09).
        return admin.rpc("colaborador_historico_listar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_collaborator_id: colaborador,
        });

      case "colaborador.catalogo.bootstrap":
        return admin.rpc("colaborador_catalogo_bootstrap", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operation_id,
          p_catalogo: execucao.entrada.catalogo,
        });

      // ---------------------------------------------------------------------
      // F5-08 P3 — estrutura organizacional e catálogos (§21.1/§27).
      //
      // O dispatch apenas TRADUZ o payload público (camelCase) para os
      // parâmetros nomeados p_* e envia o ator/organização SOBERANOS
      // resolvidos nesta fronteira. Nenhuma regra de domínio é replicada aqui:
      // ciclo (I1), encerramento (I2/I3), catálogo ativo (I4), vigência (I5),
      // unicidade, cross-tenant, expected_version, idempotência e autorização
      // continuam dentro da RPC/banco.
      // ---------------------------------------------------------------------
      case "estrutura.unidade.criar":
        return admin.rpc("estrutura_unidade_criar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_nome: execucao.entrada.nome,
          p_valid_from: execucao.entrada.validFrom,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.unidade.renomear":
        return admin.rpc("estrutura_unidade_renomear", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_unidade_id: execucao.entrada.unidadeId,
          p_nome: execucao.entrada.nome,
          p_expected_version: execucao.entrada.expectedVersion,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.unidade.encerrar":
        return admin.rpc("estrutura_unidade_encerrar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_unidade_id: execucao.entrada.unidadeId,
          p_valid_to: execucao.entrada.validTo,
          p_expected_version: execucao.entrada.expectedVersion,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.unidade.parent.definir":
        return admin.rpc("estrutura_unidade_parent_definir", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_unidade_id: execucao.entrada.unidadeId,
          p_parent_unit_id: execucao.entrada.parentUnitId,
          p_valid_from: execucao.entrada.validFrom,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.unidade.parent.encerrar":
        return admin.rpc("estrutura_unidade_parent_encerrar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_unidade_id: execucao.entrada.unidadeId,
          p_valid_to: execucao.entrada.validTo,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.posicao.criar":
        return admin.rpc("estrutura_posicao_criar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_unidade_id: execucao.entrada.unidadeId,
          p_job_role_id: execucao.entrada.jobRoleId,
          p_seniority_level_id: execucao.entrada.seniorityLevelId,
          p_valid_from: execucao.entrada.validFrom,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.posicao.encerrar":
        return admin.rpc("estrutura_posicao_encerrar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_posicao_id: execucao.entrada.posicaoId,
          p_valid_to: execucao.entrada.validTo,
          p_expected_version: execucao.entrada.expectedVersion,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.colegiado.definir":
        return admin.rpc("estrutura_colegiado_definir", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_collaborator_id: execucao.entrada.collaboratorId,
          p_member_collaborator_ids: execucao.entrada.memberCollaboratorIds,
          p_valid_from: execucao.entrada.validFrom,
          p_motivo: execucao.entrada.motivo,
        });

      case "estrutura.colegiado.encerrar":
        return admin.rpc("estrutura_colegiado_encerrar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_collaborator_id: execucao.entrada.collaboratorId,
          p_valid_to: execucao.entrada.validTo,
          p_motivo: execucao.entrada.motivo,
        });

      case "catalogo.cargo.criar":
        return admin.rpc("catalogo_cargo_criar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_nome: execucao.entrada.nome,
          p_code: execucao.entrada.code,
          p_motivo: execucao.entrada.motivo,
        });

      case "catalogo.cargo.renomear":
        return admin.rpc("catalogo_cargo_renomear", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_job_role_id: execucao.entrada.jobRoleId,
          p_nome: execucao.entrada.nome,
          p_expected_version: execucao.entrada.expectedVersion,
          p_motivo: execucao.entrada.motivo,
        });

      case "catalogo.cargo.status.alterar":
        return admin.rpc("catalogo_cargo_status_alterar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_job_role_id: execucao.entrada.jobRoleId,
          p_status: execucao.entrada.status,
          p_expected_version: execucao.entrada.expectedVersion,
          p_motivo: execucao.entrada.motivo,
        });

      case "catalogo.senioridade.criar":
        return admin.rpc("catalogo_senioridade_criar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_nome: execucao.entrada.nome,
          p_motivo: execucao.entrada.motivo,
        });

      case "catalogo.senioridade.renomear":
        return admin.rpc("catalogo_senioridade_renomear", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_seniority_level_id: execucao.entrada.seniorityLevelId,
          p_nome: execucao.entrada.nome,
          p_expected_version: execucao.entrada.expectedVersion,
          p_motivo: execucao.entrada.motivo,
        });

      case "catalogo.senioridade.status.alterar":
        return admin.rpc("catalogo_senioridade_status_alterar", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_operation_id: execucao.entrada.operationId,
          p_seniority_level_id: execucao.entrada.seniorityLevelId,
          p_status: execucao.entrada.status,
          p_expected_version: execucao.entrada.expectedVersion,
          p_motivo: execucao.entrada.motivo,
        });
    }
  }

  // ---------------------------------------------------------------------------
  // Fronteira confiável: ActorContext + ResourceContext + Policy Engine (gate
  // FUNCIONAL) e capabilities efetivas (gate ADMINISTRATIVO — D19).
  // ---------------------------------------------------------------------------
  /**
   * Vínculo F5-02 do ator (auth.uid → membership → colaborador). Usado pela
   * âncora autorizável das operações funcionais sem alvo (criar/listar) e pelo
   * ActorContext do Policy Engine — MESMA implementação, uma só resolução.
   */
  const resolverColaboradorVinculado = async (
    authUserId: string,
    organizationId: string
  ): Promise<string | null> => {
    const { data, error } = await admin.rpc("resolver_collaborador_vinculado", {
      p_user_profile_id: authUserId,
      p_organization_id: organizationId,
    });
    if (error) return null;
    const primeira = ((data ?? []) as { collaborator_id: string | null }[])[0];
    return primeira?.collaborator_id ?? null;
  };

  const autorizacao: DepsContextoAutorizacao = {
    agora: () => new Date(),

    resolverIdentidade: async (authUserId): Promise<AuthIdentity | null> => {
      const { data: perfil, error: erroPerfil } = await admin
        .from("user_profiles")
        .select("id, status")
        .eq("id", authUserId)
        .maybeSingle();
      if (erroPerfil || !perfil) return null;
      if (perfil.status !== "active") {
        return {
          authUserId,
          perfil: { id: perfil.id, status: "disabled" },
          memberships: [],
          organizacoes: [],
        };
      }

      const { data: memberships, error: erroMemberships } = await admin
        .from("user_organization_memberships")
        .select("id, organization_id, status")
        .eq("user_profile_id", authUserId)
        .eq("status", "active");
      if (erroMemberships) return null;

      const linhas = (memberships ?? []) as {
        id: string;
        organization_id: string;
        status: string;
      }[];
      const ids = linhas.map((linha) => linha.organization_id);

      let organizacoes: { id: string; name: string }[] = [];
      if (ids.length > 0) {
        const { data: orgs, error: erroOrgs } = await admin
          .from("organizations")
          .select("id, name")
          .in("id", ids);
        if (erroOrgs) return null;
        organizacoes = (orgs ?? []) as { id: string; name: string }[];
      }

      return {
        authUserId,
        perfil: { id: perfil.id, status: "active" },
        memberships: linhas.map((linha) => ({
          id: linha.id,
          organizationId: linha.organization_id,
          status: linha.status === "active" ? "active" : "disabled",
        })),
        organizacoes: organizacoes.map((org) => ({ id: org.id, name: org.name })),
      };
    },

    resolverColaboradorVinculado,

    resolverCapabilitiesEscopos: async (authUserId, organizationId) => {
      const { data, error } = await admin.rpc("resolver_capabilities_escopos_efetivas", {
        p_user_profile_id: authUserId,
        p_organization_id: organizationId,
      });
      if (error) return [];

      const porCapability = new Map<string, { scopes: Set<ScopeType>; units: Set<string> }>();
      for (const linha of (data ?? []) as LinhaCapabilityEscopo[]) {
        // Fail-closed do vocabulário (F5-04 D14): código desconhecido é ignorado.
        if (!capabilityCanonica(linha.capability_code)) continue;
        const atual = porCapability.get(linha.capability_code) ?? {
          scopes: new Set<ScopeType>(),
          units: new Set<string>(),
        };
        atual.scopes.add(linha.scope_type as ScopeType);
        if (linha.organizational_unit_id) atual.units.add(linha.organizational_unit_id);
        porCapability.set(linha.capability_code, atual);
      }

      return Array.from(porCapability.entries()).map(
        ([code, dados]): CapabilityComEscopos => ({
          capability: capabilityCanonica(code)!,
          scopes: Array.from(dados.scopes),
          ...(dados.units.size > 0 ? { unitIds: Array.from(dados.units) } : {}),
        })
      );
    },

    resolverAlvosEscopo: async ({ authUserId, organizationId, scope, unitId, data }) => {
      const { data: alvos, error } = await admin.rpc("resolver_alvos_escopo", {
        p_user_profile_id: authUserId,
        p_organization_id: organizationId,
        p_scope_type: scope,
        p_organizational_unit_id: unitId,
        p_data: data.toISOString(),
      });
      if (error) return [];
      return ((alvos ?? []) as LinhaAlvoEscopo[]).map((linha) => ({
        collaboratorId: linha.collaborator_id,
        positionId: linha.position_id,
      }));
    },

    // F5-07: o RECURSO é o COLABORADOR. A linha real é carregada server-side e o
    // tenant vem do recurso (nunca do caller); a posição/unidade vigentes na
    // data alimentam a estrutura do ResourceContext (I4).
    carregarRecurso: async ({ target, organizationId }) => {
      if (target.type !== "collaborator") return null;

      const { data, error } = await admin
        .from("collaborators")
        .select("id, organization_id, status, version")
        .eq("id", target.id)
        .eq("organization_id", organizationId)
        .maybeSingle();
      if (error || !data) return null;

      const { data: ocupacoes } = await admin
        .from("occupations")
        .select("organizational_position_id, organizational_positions(unit_id)")
        .eq("collaborator_id", data.id)
        .is("valid_to", null)
        .limit(1);
      const ocupacao = ((ocupacoes ?? []) as {
        organizational_position_id: string;
        organizational_positions?: { unit_id?: string | null } | null;
      }[])[0];

      return {
        kind: "collaborator",
        id: data.id,
        organizationId: data.organization_id,
        ownerCollaboratorId: data.id,
        positionId: ocupacao?.organizational_position_id ?? null,
        unitId: ocupacao?.organizational_positions?.unit_id ?? null,
      } as RecursoSoberanoCarregado;
    },
  };

  const deps: DepsColaboradores = {
    // Âncora soberana do ator para operações funcionais sem alvo (F5-07 BLOCKER).
    resolverColaboradorVinculado,
    resolveCaller: async (authHeader) => {
      const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await caller.auth.getUser();
      return error ? null : (data.user?.id ?? null);
    },

    resolverOrganizacoesDoAtor: async (authUserId) => {
      const { data, error } = await admin
        .from("user_organization_memberships")
        .select("organization_id")
        .eq("user_profile_id", authUserId)
        .eq("status", "active");
      if (error) return [];
      return ((data ?? []) as { organization_id: string }[]).map(
        (linha) => linha.organization_id
      );
    },

    colaboradorPertenceAoAtor: async ({ organizationId, collaboratorId }) => {
      const { data, error } = await admin
        .from("collaborators")
        .select("id")
        .eq("id", collaboratorId)
        .eq("organization_id", organizationId)
        .maybeSingle();
      return !error && Boolean(data);
    },

    // Matrícula é INTENÇÃO: a resolução é feita pela RPC soberana, que devolve
    // NULL quando não há exatamente uma linha ABERTA (ambígua ⇒ não encontrado).
    resolverMatricula: async ({ actorUserProfileId, organizationId, matricula }) => {
      const { data, error } = await admin.rpc("colaborador_resolver_matricula", {
        p_organization_id: organizationId,
        p_actor_user_profile_id: actorUserProfileId,
        p_matricula: matricula,
      });
      if (error) return null;
      return typeof data === "string" && data.length > 0 ? data : null;
    },

    avaliarAutorizacao: async ({ actorUserProfileId, organizationId, operacao, alvo, dataNegocio }) => {
      const capability = capabilityCanonica(DEFINICAO_POR_OPERACAO[operacao].capability) as
        | Capability
        | undefined;
      if (!capability) return { permitido: false, code: "FORBIDDEN" as CodigoPublico };

      // MESMO caminho de decisão da Edge `avaliacoes`: ActorContext e
      // ResourceContext REAIS + Policy Engine (F4-03).
      const decisao = await avaliarOperacaoAutorizacao(
        {
          authUserId: actorUserProfileId,
          organizationId,
          capability,
          alvo,
          dataNegocio: dataNegocio ?? undefined,
        },
        autorizacao
      );

      return decisao.allowed
        ? { permitido: true }
        : {
            permitido: false,
            code: codigoPublicoDaNegacao(decisao.denial?.publicCode),
          };
    },

    // Plano ADMINISTRATIVO (D19): a MESMA fonte canônica de capabilities×escopos
    // é consultada como `service_role`; exige-se a presença do código. Nenhuma
    // allowlist funcional é usada aqui.
    resolverCapabilitiesEfetivas: async ({ actorUserProfileId, organizationId }) => {
      const { data, error } = await admin.rpc("resolver_capabilities_escopos_efetivas", {
        p_user_profile_id: actorUserProfileId,
        p_organization_id: organizationId,
      });
      if (error) return [];
      return ((data ?? []) as LinhaCapability[]).map((linha) => ({
        capability_code: linha.capability_code,
      }));
    },

    executarRpc,
  };

  return colaboradores(req, deps);
});
