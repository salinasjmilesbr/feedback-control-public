import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { avaliacoes, type DepsAvaliacoes, type ExecucaoAvaliacao } from "./core.ts";
import {
  avaliarOperacaoAutorizacao,
  type DepsContextoAutorizacao,
} from "../../../src/authorization/contextoAutorizacao.ts";
import type { AuthIdentity } from "../../../src/auth/tipos.ts";
import { capabilityCanonica } from "../../../src/authorization/catalogoCapacidades.ts";
import type { Capability } from "../../../src/authorization/Capability.ts";
import type { CapabilityComEscopos } from "../../../src/authorization/providers/reais.ts";
import type { ScopeType } from "../../../src/authorization/policyEngine/types.ts";
import type { RecursoSoberanoCarregado } from "../../../src/authorization/resourceContextReal.ts";
import { CAPABILITY_POR_OPERACAO } from "../../../src/infrastructure/supabase/avaliacoes/contrato.ts";
import { carregarAssignedDaOperacao } from "./assignedSupabase.ts";
import { criarPonteColaborador } from "./ponteColaborador.ts";

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

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ---------------------------------------------------------------------------
  // Fronteira confiável: identidade + ActorContext + ResourceContext + engine.
  // ---------------------------------------------------------------------------
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

    resolverColaboradorVinculado: async (authUserId, organizationId) => {
      const { data, error } = await admin.rpc("resolver_collaborador_vinculado", {
        p_user_profile_id: authUserId,
        p_organization_id: organizationId,
      });
      if (error) return null;
      const primeira = ((data ?? []) as { collaborator_id: string | null }[])[0];
      return primeira?.collaborator_id ?? null;
    },

    resolverCapabilitiesEscopos: async (authUserId, organizationId) => {
      const { data, error } = await admin.rpc("resolver_capabilities_escopos_efetivas", {
        p_user_profile_id: authUserId,
        p_organization_id: organizationId,
      });
      if (error) return [];

      const porCapability = new Map<string, { scopes: Set<ScopeType>; units: Set<string> }>();
      for (const linha of (data ?? []) as LinhaCapabilityEscopo[]) {
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

    // F5-06 §8.1: a AVALIAÇÃO passa a ser recurso soberano. A linha real é
    // carregada server-side; o tenant vem do recurso (nunca do caller).
    carregarRecurso: async ({ target, organizationId }) => {
      if (target.type === "evaluation") {
        const { data, error } = await admin
          .from("evaluations")
          .select("id, organization_id, cycle_id, evaluated_collaborator_id, status")
          .eq("id", target.id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (error || !data) return null;
        return {
          kind: "evaluation",
          id: data.id,
          organizationId: data.organization_id,
          ownerCollaboratorId: data.evaluated_collaborator_id,
          evaluatedCollaboratorId: data.evaluated_collaborator_id,
          cycleId: data.cycle_id,
          status: data.status,
        } as RecursoSoberanoCarregado;
      }

      if (target.type === "collaborator") {
        const { data, error } = await admin
          .from("collaborators")
          .select("id, organization_id, status")
          .eq("id", target.id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (error || !data) return null;
        return {
          kind: "collaborator",
          id: data.id,
          organizationId: data.organization_id,
          ownerCollaboratorId: data.id,
          status: data.status,
        } as RecursoSoberanoCarregado;
      }

      return null;
    },

    // ASSIGNED soberano POR OPERAÇÃO (F5-06, F3-08/F3-09): membro de colegiado
    // e responsável avaliativo alcançam a avaliação. Sem vínculo/registro
    // soberano ⇒ `null` ⇒ o Policy Engine nega o alcance (fail-closed).
    resolverAssigned: async ({ collaboratorId, organizationId, target, cycleId }) =>
      carregarAssignedDaOperacao(admin, {
        collaboratorId,
        organizationId,
        target,
        cycleId,
        agora: () => new Date(),
      }),

    // Estado de domínio derivado SERVER-SIDE (o cliente nunca declara estado).
    carregarContextoAvaliacao: async ({ target, organizationId }) => {
      if (target.type === "evaluation") {
        const { data, error } = await admin
          .from("evaluations")
          .select("status, encerrada_com_pendencias")
          .eq("id", target.id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (error || !data) return null;
        return {
          status: data.status,
          encerradaComPendencias: data.encerrada_com_pendencias === true,
        };
      }

      if (target.type !== "collaborator") return null;

      // Criação: o ciclo vigente (ATIVO/PLANEJADO, do próprio tenant) e a
      // aptidão do avaliado definem o domínio.
      const { data: ciclos, error: erroCiclos } = await admin
        .from("evaluation_cycles")
        .select("id, status")
        .eq("organization_id", organizationId)
        .in("status", ["PLANEJADO", "ATIVO"])
        .limit(1);
      if (erroCiclos) return null;

      const { data: colaborador, error: erroColaborador } = await admin
        .from("collaborators")
        .select("id, status")
        .eq("id", target.id)
        .eq("organization_id", organizationId)
        .maybeSingle();
      if (erroColaborador || !colaborador) return null;

      return {
        status: "CRIACAO",
        cicloPermiteNovaAvaliacao: (ciclos ?? []).length > 0,
        avaliadoApto: String(colaborador.status ?? "").toLowerCase() === "active",
      };
    },
  };

  // ---------------------------------------------------------------------------
  // Execução privilegiada: RPC `evaluation_*` (SECURITY INVOKER, EXECUTE só
  // service_role) com o ator VERIFICADO. O JWT do usuário NÃO é propagado.
  // ---------------------------------------------------------------------------
  const executarRpc: DepsAvaliacoes["executarRpc"] = async (execucao: ExecucaoAvaliacao) => {
    const ator = execucao.actorUserProfileId;
    const org = execucao.organizationId;
    const avaliacao = execucao.evaluationId;

    switch (execucao.operacao) {
      case "evaluation.criar": {
        // A versão de configuração é SOBERANA (do ciclo) — não é parâmetro.
        if (!execucao.cycleId) {
          return { error: { code: "INVALID_INPUT", message: "cycle_id obrigatório." } };
        }

        // PONTE matrícula → UUID (F3-01) resolvida AQUI, na fronteira
        // confiável: a tela legada envia a matrícula como INTENÇÃO e o valor
        // autoritativo é o UUID resolvido. Sem resolução ⇒ recusa (a tela não
        // pode inventar identidade, e a criação NUNCA cai para o localStorage).
        const avaliadoId = execucao.matriculaAvaliado
          ? await criarPonteColaborador({
              buscarIdentificadoresPorCodigo: async ({ organizationId, businessCode }) =>
                admin
                  .from("collaborator_identifiers")
                  .select("collaborator_id, organization_id, business_code, valid_to")
                  .eq("organization_id", organizationId)
                  .eq("business_code", businessCode),
            }).resolver({ organizationId: org, matricula: execucao.matriculaAvaliado })
          : null;

        if (!avaliadoId) {
          return {
            error: {
              code: "INVALID_INPUT",
              message: "Colaborador avaliado não resolvido para a matrícula informada.",
            },
          };
        }

        return admin.rpc("evaluation_criar", {
          p_organization_id: org,
          p_cycle_id: execucao.cycleId,
          p_evaluated_collaborator_id: avaliadoId,
          p_actor_user_profile_id: ator,
        });
      }
      case "evaluation.ler": {
        return admin
          .from("evaluations")
          .select(
            "id, organization_id, cycle_id, evaluated_collaborator_id, status, nota_media, data_conclusao, encerrada_com_pendencias"
          )
          .eq("id", avaliacao)
          .eq("organization_id", org)
          .maybeSingle();
      }
      case "evaluation.gravar_notas": {
        // CORREÇÃO DE AUDITORIA (IDOR): a ocorrência editável NÃO vem do
        // cliente. A RPC a deriva de `p_actor_user_profile_id` (auth.uid →
        // membership → vínculo F5-02 → ocorrência vigente). Nenhum
        // `participant_id` atravessa esta fronteira.
        return admin.rpc("evaluation_gravar_notas", {
          p_evaluation_id: avaliacao,
          p_notas: execucao.notas,
          p_actor_user_profile_id: ator,
        });
      }
      case "evaluation.gravar_comentario": {
        if (!execucao.escopo || !execucao.texto) {
          return { error: { code: "INVALID_INPUT", message: "Parâmetros do comentário incompletos." } };
        }
        // Idem: a ocorrência é resolvida server-side a partir do ator.
        return admin.rpc("evaluation_gravar_comentario", {
          p_evaluation_id: avaliacao,
          p_escopo: execucao.escopo,
          p_criterion_id: execucao.criterionId,
          p_texto: execucao.texto,
          p_actor_user_profile_id: ator,
        });
      }
      case "evaluation.concluir": {
        return admin.rpc("evaluation_concluir", {
          p_evaluation_id: avaliacao,
          p_actor_user_profile_id: ator,
        });
      }
      case "evaluation.reabrir": {
        if (!execucao.motivo) {
          return { error: { code: "INVALID_INPUT", message: "motivo obrigatório." } };
        }
        return admin.rpc("evaluation_reabrir", {
          p_evaluation_id: avaliacao,
          p_motivo: execucao.motivo,
          p_actor_user_profile_id: ator,
        });
      }
      case "evaluation.cancelar": {
        if (!execucao.motivo) {
          return { error: { code: "INVALID_INPUT", message: "motivo obrigatório." } };
        }
        return admin.rpc("evaluation_cancelar", {
          p_evaluation_id: avaliacao,
          p_motivo: execucao.motivo,
          p_actor_user_profile_id: ator,
        });
      }
      case "evaluation.participantes_realinhar": {
        if (!execucao.motivo) {
          return { error: { code: "INVALID_INPUT", message: "motivo obrigatório." } };
        }
        return admin.rpc("evaluation_participante_realinhar", {
          p_evaluation_id: avaliacao,
          p_motivo: execucao.motivo,
          p_actor_user_profile_id: ator,
        });
      }
      case "evaluation.resolver_ciclo": {
        // ano+ciclo (INTENÇÃO) → UUID soberano do ciclo, dentro do tenant
        // revalidado. A assinatura da RPC é EXATAMENTE
        // `(p_organization_id, p_ano, p_numero, p_actor_user_profile_id)`:
        // a matrícula NÃO é enviada aqui porque a ponte matrícula → UUID (F3-01)
        // já foi resolvida ANTES do Policy Engine, para o alvo autorizável.
        if (execucao.ano === null || execucao.numero === null) {
          return { error: { code: "INVALID_INPUT", message: "ano e numero obrigatórios." } };
        }
        return admin.rpc("evaluation_resolver_ciclo", {
          p_organization_id: org,
          p_ano: execucao.ano,
          p_numero: execucao.numero,
          p_actor_user_profile_id: ator,
        });
      }
      case "evaluation.painel_participante": {
        // LEITURA DE EDIÇÃO: a RPC resolve a ocorrência do PRÓPRIO ator pelo
        // vínculo (F5-02) + vigência; nada de participant_id do cliente.
        return admin.rpc("evaluation_painel_participante", {
          p_evaluation_id: avaliacao,
          p_actor_user_profile_id: ator,
        });
      }
      case "evaluation.transparencia": {
        // Projeção server-side do avaliado (D20): a própria RPC restringe a
        // leitura ao colaborador avaliado vinculado ao ator.
        return admin.rpc("evaluation_leitura_avaliado", {
          p_evaluation_id: avaliacao,
          p_actor_user_profile_id: ator,
        });
      }
      default:
        return { error: { code: "INVALID_INPUT", message: "Operação não suportada." } };
    }
  };

  const deps: DepsAvaliacoes = {
    resolveCaller: async (authHeader) => {
      const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await caller.auth.getUser();
      return error ? null : (data.user?.id ?? null);
    },

    avaliarAutorizacao: async ({ authUserId, organizationId, operacao, alvo }) => {
      const capability = capabilityCanonica(CAPABILITY_POR_OPERACAO[operacao]) as
        | Capability
        | undefined;
      if (!capability) return { allowed: false, code: "FORBIDDEN" as const };

      const decisao = await avaliarOperacaoAutorizacao(
        { authUserId, organizationId, capability, alvo },
        autorizacao
      );
      return decisao.allowed
        ? { allowed: true }
        : { allowed: false, code: decisao.denial?.publicCode ?? "FORBIDDEN" };
    },

    executarRpc,

    // Ponte matrícula → UUID (F3-01) na fronteira confiável: o alvo autorizável
    // de criação/resolução de ciclo é sempre o UUID resolvido server-side.
    resolverMatricula: async (matricula, organizationId) =>
      criarPonteColaborador({
        buscarIdentificadoresPorCodigo: async ({ organizationId: org, businessCode }) =>
          admin
            .from("collaborator_identifiers")
            .select("collaborator_id, organization_id, business_code, valid_to")
            .eq("organization_id", org)
            .eq("business_code", businessCode),
      }).resolver({ organizationId, matricula }),
  };

  return avaliacoes(req, deps);
});
