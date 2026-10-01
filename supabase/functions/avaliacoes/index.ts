import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { avaliacoes, type DepsAvaliacoes, type ExecucaoAvaliacao } from "./core.ts";
import type { ResultadoRelatorioSoberano } from "./core.ts";
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
  CAPABILITY_POR_OPERACAO,
  SCOPE_LEITURA_LEITURA_COLETIVA,
  resolverDescobertaAvaliacao,
  resolverLeituraColetiva,
  type PainelParticipantesAvaliacao,
} from "../../../src/infrastructure/supabase/avaliacoes/contrato.ts";
import {
  carregarAssignedDaOperacao,
  carregarAssignedWriteColegiadoMaterializado,
} from "./assignedSupabase.ts";
import { criarPonteColaborador } from "./ponteColaborador.ts";
import {
  carregarEstadoDescoberta,
  type EstadoDescoberta,
} from "./descobertaSupabase.ts";

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

    resolverAlvosEscopo: async ({ authUserId, organizationId, scope, unitId, data, capability, alvo, cycleId }) => {
      // CREATE usa a fotografia do ciclo; WRITE de avaliação usa as ocorrências
      // materializadas. Ambos permanecem atrás do mesmo resolver do Policy Engine.
      if (alvo?.type === "evaluation" && cycleId &&
          (capability === "evaluation.write" || capability === "evaluation.create") &&
          (scope === "DIRECT_REPORTS" || scope === "DESCENDANTS")) {
        const { data: avaliacao, error: erroAvaliacao } = await admin
          .from("evaluations")
          .select("evaluated_collaborator_id")
          .eq("id", alvo.id)
          .eq("organization_id", organizationId)
          .eq("cycle_id", cycleId)
          .maybeSingle();
        if (erroAvaliacao || !avaliacao) return [];

        const roleType = scope === "DIRECT_REPORTS" ? "GESTAO_DIRETA" : "GESTAO_CADEIA";
        const { data: vinculo, error: erroVinculo } = await admin.rpc("resolver_collaborador_vinculado", {
          p_user_profile_id: authUserId,
          p_organization_id: organizationId,
        });
        const actorCollaboratorId = (vinculo as { collaborator_id?: string }[] | null)?.[0]?.collaborator_id;
        if (erroVinculo || !actorCollaboratorId) return [];
        const { data: participante, error: erroParticipante } = await admin
          .from("evaluation_participants")
          .select("id")
          .eq("organization_id", organizationId)
          .eq("evaluation_id", alvo.id)
          .eq("role_type", roleType)
          .eq("collaborator_id", actorCollaboratorId)
          .lte("valid_from", data.toISOString())
          .or(`valid_to.is.null,valid_to.gt.${data.toISOString()}`)
          .eq("status", "active")
          .limit(1);
        if (erroParticipante || !participante?.length) return [];
        return [{ collaboratorId: avaliacao.evaluated_collaborator_id, positionId: null }];
      }

      let dataResolucao = data;
      if (capability === "evaluation.create" && cycleId && alvo?.type === "collaborator") {
        const { data: ciclo, error: erroCiclo } = await admin
          .from("evaluation_cycles")
          .select("ano, numero")
          .eq("id", cycleId)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (erroCiclo || !ciclo) return [];
        const { data: snapshot, error: erroSnapshot } = await admin
          .from("collegiate_cycle_snapshots")
          .select("reference_date")
          .eq("organization_id", organizationId)
          .eq("ano", ciclo.ano)
          .eq("ciclo", ciclo.numero)
          .eq("collaborator_id", alvo.id)
          .maybeSingle();
        if (erroSnapshot || !snapshot?.reference_date) return [];
        dataResolucao = new Date(snapshot.reference_date);
      }
      const { data: alvos, error } = await admin.rpc("resolver_alvos_escopo", {
        p_user_profile_id: authUserId,
        p_organization_id: organizationId,
        p_scope_type: scope,
        p_organizational_unit_id: unitId,
        p_data: dataResolucao.toISOString(),
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
          .select("id, organization_id")
          .eq("id", target.id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (error || !data) return null;
        return {
          kind: "collaborator",
          id: data.id,
          organizationId: data.organization_id,
          ownerCollaboratorId: data.id,
        } as RecursoSoberanoCarregado;
      }

      return null;
    },

    // ASSIGNED soberano POR OPERAÇÃO (F5-06, F3-08/F3-09): membro de colegiado
    // e responsável avaliativo alcançam a avaliação. Sem vínculo/registro
    // soberano ⇒ `null` ⇒ o Policy Engine nega o alcance (fail-closed).
    resolverAssigned: async ({ collaboratorId, organizationId, target, cycleId, capability }) => {
      const entradaAssigned = {
        collaboratorId,
        organizationId,
        target,
        cycleId,
        agora: () => new Date(),
      } as const;
      if (capability === "evaluation.write") {
        return carregarAssignedWriteColegiadoMaterializado(admin, entradaAssigned);
      }
      return carregarAssignedDaOperacao(admin, entradaAssigned);
    },

    // Estado de domínio derivado SERVER-SIDE (o cliente nunca declara estado).
    carregarContextoAvaliacao: async ({ target, organizationId, cycleId, authUserId }) => {
      if (target.type === "evaluation") {
        const { data, error } = await admin
          .from("evaluations")
          .select("status, encerrada_com_pendencias")
          .eq("id", target.id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (error || !data) return null;

        // F6 Incremento 1 (R2/R3): participação MATERIALIZADA e VIGENTE do ator,
        // resolvida pelo MESMO helper soberano do caminho de escrita (o cliente
        // nunca informa ocorrência). Ausência ⇒ vazio (não é erro ⇒ `false`);
        // erro/ambiguidade ⇒ `null` (indeterminação ⇒ fail-closed).
        let atorEhParticipanteVigente = false;
        if (authUserId) {
          const { data: ocorrencias, error: erroOcorrencia } = await admin.rpc(
            "evaluation_ocorrencia_do_ator",
            {
              p_organization_id: organizationId,
              p_evaluation_id: target.id,
              p_actor_user_profile_id: authUserId,
            }
          );
          if (erroOcorrencia) return null;
          atorEhParticipanteVigente = Array.isArray(ocorrencias) && ocorrencias.length > 0;
        }

        return {
          status: data.status,
          encerradaComPendencias: data.encerrada_com_pendencias === true,
          atorEhParticipanteVigente,
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
        .eq("id", cycleId ?? "00000000-0000-0000-0000-000000000000")
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

  const resolverAlvosRelatorio = async (authUserId: string, organizationId: string) => {
    const { data, error } = await admin.rpc("resolver_alvos_escopo", {
      p_user_profile_id: authUserId,
      p_organization_id: organizationId,
      p_scope_type: "DESCENDANTS",
      p_organizational_unit_id: null,
      p_data: new Date().toISOString(),
    });
    if (error) {
      return [] as { collaboratorId: string; positionId: string }[];
    }
    return ((data ?? []) as LinhaAlvoEscopo[])
      .filter((linha): linha is { collaborator_id: string; position_id: string } =>
        typeof linha.collaborator_id === "string" && typeof linha.position_id === "string"
      )
      .map((linha) => ({ collaboratorId: linha.collaborator_id, positionId: linha.position_id }));
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
          : execucao.evaluatedCollaboratorId;

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

  const executarRelatorio: DepsAvaliacoes["executarRelatorio"] = async ({
    authUserId,
    organizationId,
    cycleId,
  }) => {
    const { data: ciclo, error: erroCiclo } = await admin
      .from("evaluation_cycles")
      .select("id, organization_id")
      .eq("id", cycleId)
      .eq("organization_id", organizationId)
      .maybeSingle();
    if (erroCiclo || !ciclo) {
      return { error: { code: "NOT_FOUND" } };
    }

    const alvos = await resolverAlvosRelatorio(authUserId, organizationId);
    const ids = alvos.map((alvo) => alvo.collaboratorId);
    if (ids.length === 0) {
      const vazio: ResultadoRelatorioSoberano = {
        organizationId,
        cycleId,
        scope: "DESCENDANTS",
        colaboradores: [],
      };
      return { data: vazio };
    }

    const [colaboradores, status, avaliacoesDoCiclo] = await Promise.all([
      admin.from("collaborators").select("id, organization_id, full_name").eq("organization_id", organizationId).in("id", ids),
      admin.from("collaborator_status_periods").select("collaborator_id, status, valid_from, valid_to").in("collaborator_id", ids).lte("valid_from", new Date().toISOString()),
      admin.from("evaluations").select("id, evaluated_collaborator_id, status, nota_media, data_conclusao").eq("organization_id", organizationId).eq("cycle_id", cycleId).in("evaluated_collaborator_id", ids),
    ]);
    if (colaboradores.error || status.error || avaliacoesDoCiclo.error) {
      return { error: { code: "INTERNAL" } };
    }

    const agora = Date.now();
    const statusPorColaborador = new Map<string, string>();
    for (const linha of (status.data ?? []) as { collaborator_id: string; status: string; valid_from: string; valid_to: string | null }[]) {
      const inicio = Date.parse(linha.valid_from);
      const fim = linha.valid_to === null ? Number.POSITIVE_INFINITY : Date.parse(linha.valid_to);
      if (inicio <= agora && agora < fim) statusPorColaborador.set(linha.collaborator_id, linha.status);
    }
    const avaliacaoPorColaborador = new Map<string, { id: string; status: string; nota_media: number | null; data_conclusao: string | null }>();
    for (const linha of (avaliacoesDoCiclo.data ?? []) as { id: string; evaluated_collaborator_id: string; status: string; nota_media: number | null; data_conclusao: string | null }[]) {
      avaliacaoPorColaborador.set(linha.evaluated_collaborator_id, linha);
    }
    const nomes = new Map((colaboradores.data ?? []).map((linha) => [linha.id, linha.full_name]));
    const resultado: ResultadoRelatorioSoberano = {
      organizationId,
      cycleId,
      scope: "DESCENDANTS",
      colaboradores: alvos
        .filter((alvo) => nomes.has(alvo.collaboratorId))
        .map((alvo) => {
          const avaliacao = avaliacaoPorColaborador.get(alvo.collaboratorId);
          return {
            collaboratorId: alvo.collaboratorId,
            nome: nomes.get(alvo.collaboratorId)!,
            positionId: alvo.positionId,
            status: statusPorColaborador.get(alvo.collaboratorId) ?? null,
            evaluationId: avaliacao?.id ?? null,
            evaluationStatus: avaliacao?.status ?? null,
            notaMedia: avaliacao?.nota_media ?? null,
            dataConclusao: avaliacao?.data_conclusao ?? null,
          };
        }),
    };
    return { data: resultado };
  };

  // ---------------------------------------------------------------------------
  // Descoberta soberana da avaliação do colaborador no ciclo.
  //
  // LEITURA: um ÚNICO carregamento serve à decisão (os três ramos — create ∨
  // write ∨ read) e ao payload mínimo. Memoizado POR ATOR dentro da requisição
  // (as deps são criadas a cada requisição) — nunca entre requisições/atores.
  // ---------------------------------------------------------------------------
  let descobertaMemo: { chave: string; promessa: Promise<EstadoDescoberta> } | null = null;

  const carregarDescoberta = (
    authUserId: string,
    organizationId: string,
    cycleId: string,
    collaboratorId: string
  ): Promise<EstadoDescoberta> => {
    const chave = `${authUserId}|${organizationId}|${cycleId}|${collaboratorId}`;
    if (descobertaMemo?.chave === chave) return descobertaMemo.promessa;

    const promessa = carregarEstadoDescoberta(
      {
        // Tenant revalidado server-side: ciclo de OUTRO tenant é inexistente.
        cicloDoTenant: async () => {
          const { data, error } = await admin
            .from("evaluation_cycles")
            .select("id")
            .eq("id", cycleId)
            .eq("organization_id", organizationId)
            .maybeSingle();
          return !error && Boolean(data);
        },
        // Unicidade: no máximo UMA avaliação NÃO CANCELADA por
        // (organização, ciclo, colaborador) — índice parcial
        // `uq_evaluations_org_cycle_collaborator_nao_cancelada`.
        avaliacaoNaoCancelada: async () => {
          const { data, error } = await admin
            .from("evaluations")
            .select("id, status")
            .eq("organization_id", organizationId)
            .eq("cycle_id", cycleId)
            .eq("evaluated_collaborator_id", collaboratorId)
            .neq("status", "CANCELADA")
            .maybeSingle();
          if (error) throw new Error("avaliacao indisponivel");
          return data && typeof data.id === "string" && typeof data.status === "string"
            ? { id: data.id, status: data.status }
            : null;
        },
        autorizar: async (capability, alvo) => {
          const decisao = await avaliarOperacaoAutorizacao(
            { authUserId, organizationId, capability, alvo, cycleId },
            autorizacao
          );
          return decisao.allowed === true;
        },
      },
      collaboratorId
    );

    descobertaMemo = { chave, promessa };
    return promessa;
  };

  const autorizacaoDescoberta = (estado: EstadoDescoberta) => {
    if (!estado.cicloOk) return { allowed: false as const, code: "NOT_FOUND" as const };
    const decisao = resolverDescobertaAvaliacao({
      avaliacao: estado.encontrada,
      autorizaCriar: estado.autorizaCriar,
      autorizaEscrever: estado.autorizaEscrever,
      autorizaLer: estado.autorizaLer,
    });
    return decisao.allowed
      ? { allowed: true as const, resultado: decisao.resultado }
      : { allowed: false as const, code: "FORBIDDEN" as const };
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

    avaliarAutorizacao: async ({ authUserId, organizationId, operacao, alvo, cycleId }) => {
      const capability = capabilityCanonica(CAPABILITY_POR_OPERACAO[operacao]) as
        | Capability
        | undefined;
      if (!capability) return { allowed: false, code: "FORBIDDEN" as const };

      const decisao = await avaliarOperacaoAutorizacao(
        { authUserId, organizationId, capability, alvo, ...(cycleId ? { cycleId } : {}) },
        autorizacao
      );
      return decisao.allowed
        ? { allowed: true }
        : { allowed: false, code: decisao.denial?.publicCode ?? "FORBIDDEN" };
    },

    avaliarRelatorio: async ({ authUserId, organizationId }) => {
      const capabilities = await autorizacao.resolverCapabilitiesEscopos(authUserId, organizationId);
      const report = capabilities.find((item) => item.capability === "report.read");
      if (!report?.scopes.includes("DESCENDANTS")) {
        return { allowed: false, code: "FORBIDDEN" as const };
      }
      const alvos = await resolverAlvosRelatorio(authUserId, organizationId);
      const primeiro = alvos[0];
      if (!primeiro) {
        return { allowed: false, code: "FORBIDDEN" as const };
      }
      const decisao = await avaliarOperacaoAutorizacao(
        {
          authUserId,
          organizationId,
          capability: "report.read",
          alvo: { type: "collaborator", id: primeiro.collaboratorId },
        },
        autorizacao
      );
      return decisao.allowed
        ? { allowed: true }
        : { allowed: false, code: decisao.denial?.publicCode ?? "FORBIDDEN" };
    },

    avaliarDescoberta: async ({ authUserId, organizationId, cycleId, alvo }) => {
      const estado = await carregarDescoberta(authUserId, organizationId, cycleId, alvo.id);
      const decisao = autorizacaoDescoberta(estado);
      return decisao.allowed ? { allowed: true } : { allowed: false, code: decisao.code };
    },

    executarDescoberta: async ({
      authUserId,
      organizationId,
      cycleId,
      evaluatedCollaboratorId,
    }) => {
      const estado = await carregarDescoberta(
        authUserId,
        organizationId,
        cycleId,
        evaluatedCollaboratorId
      );
      const decisao = autorizacaoDescoberta(estado);
      if (!decisao.allowed) return { error: { code: decisao.code } };
      return { data: decisao.resultado };
    },

    // F6 Incremento 1 (R2) — LEITURA COLETIVA dos participantes.
    //
    // M1: o probe de domínio próprio (`probeLeituraColetiva`) é determinado
    // EXCLUSIVAMENTE por ESTA operação confiável da Edge — nunca por input do
    // cliente (o corpo só admite operacao/organization_id/alvo e o flag não
    // existe no payload). A concessão exige ocorrência MATERIALIZADA e VIGENTE
    // do ator E um dos dois caminhos de entitlement: `evaluation.write` (scope
    // do papel) OU `evaluation.read` SOMENTE com `ASSIGNED` (#306). Este caminho
    // concede LEITURA apenas: nenhuma escrita é liberada (o gate de mutação, que
    // nega `evaluation.write` em CONCLUIDA, permanece intacto).
    avaliarPainelParticipantes: async ({ authUserId, organizationId, evaluationId }) => {
      const { data: ocorrencias, error: erroOcorrencia } = await admin.rpc(
        "evaluation_ocorrencia_do_ator",
        {
          p_organization_id: organizationId,
          p_evaluation_id: evaluationId,
          p_actor_user_profile_id: authUserId,
        }
      );
      if (erroOcorrencia) return { allowed: false, code: "INTERNAL" as const };
      const participanteVigente = Array.isArray(ocorrencias) && ocorrencias.length > 0;

      let autorizaEscrita = false;
      let autorizaLeituraAssigned = false;
      if (participanteVigente) {
        const alvo = { type: "evaluation" as const, id: evaluationId };
        const escrita = await avaliarOperacaoAutorizacao(
          {
            authUserId,
            organizationId,
            capability: "evaluation.write",
            alvo,
            probeLeituraColetiva: true,
          },
          autorizacao
        );
        autorizaEscrita = escrita.allowed === true;

        if (!autorizaEscrita) {
          const leitura = await avaliarOperacaoAutorizacao(
            {
              authUserId,
              organizationId,
              capability: "evaluation.read",
              alvo,
              probeLeituraColetiva: true,
            },
            autorizacao
          );
          if (leitura.allowed === true) {
            const capabilities = await autorizacao.resolverCapabilitiesEscopos(
              authUserId,
              organizationId
            );
            autorizaLeituraAssigned = capabilities.some(
              (item) =>
                item.capability === "evaluation.read" &&
                item.scopes.includes(SCOPE_LEITURA_LEITURA_COLETIVA)
            );
          }
        }
      }

      const decisao = resolverLeituraColetiva({
        participanteVigente,
        autorizaEscrita,
        autorizaLeituraAssigned,
      });
      return decisao.allowed ? { allowed: true } : { allowed: false, code: "FORBIDDEN" as const };
    },

    executarPainelParticipantes: async ({ authUserId, evaluationId }) => {
      const { data, error } = await admin.rpc("evaluation_painel_participantes", {
        p_evaluation_id: evaluationId,
        p_actor_user_profile_id: authUserId,
      });
      if (error) return { error: { code: "INTERNAL" as const } };
      return { data: (data ?? null) as PainelParticipantesAvaliacao | null };
    },

    executarRpc,
    executarRelatorio,

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
