import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { observacoes, type DepsObservacoes, type ExecucaoObservacao } from "./core.ts";
import {
  avaliarOperacaoAutorizacao,
  type ContextoAvaliacaoSoberano,
  type DepsContextoAutorizacao,
} from "../../../src/authorization/contextoAutorizacao.ts";
import type { AuthIdentity } from "../../../src/auth/tipos.ts";
import { capabilityCanonica } from "../../../src/authorization/catalogoCapabilities.ts";
import type { Capability } from "../../../src/authorization/Capability.ts";
import type { CapabilityComEscopos } from "../../../src/authorization/providers/reais.ts";
import type { ScopeType } from "../../../src/authorization/policyEngine/types.ts";
import type { RecursoSoberanoCarregado } from "../../../src/authorization/resourceContextReal.ts";

/**
 * F5-11 P4 (Issue #248) — Edge Function `observacoes` (namespace `observacao.*`).
 *
 * Fronteira confiável do domínio de OBSERVAÇÕES: autentica (`auth.getUser`),
 * revalida o tenant, resolve o recurso SOBERANO (a LINHA de
 * `evaluation_observations` + o `status` da LINHA do ciclo da observação, ou o
 * COLABORADOR-alvo na criação), decide pelo Policy Engine e SÓ ENTÃO executa a
 * RPC `observacao_*` com a credencial privilegiada — que revalida tudo e é a dona
 * das invariantes de domínio (capability + escopo + relação + autoria D5 + estado
 * D11/D12 + versão + idempotência + trilha, na MESMA transação — P2/P3).
 *
 * Este é o ÚNICO lugar que lê `SUPABASE_SERVICE_ROLE_KEY` e cria o cliente
 * privilegiado. A credencial NUNCA decide: é credencial de execução do ator
 * verificado, e o JWT do usuário não é propagado às RPCs.
 */

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
 * Fato BOOLEANO da LINHA soberana: qualquer valor ausente/estranho é `false`
 * (fail-closed do booleano — o estado REAL é o da linha e quem aplica a
 * precondição é a RPC; nenhum fato é declarado pelo cliente).
 */
function fatoBooleano(valor: unknown): boolean {
  return valor === true;
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
  // Identidade soberana (F5-01/F5-03) — reaproveitada pelo engine e pela
  // revalidação de tenant do corpo (§8 invariante 1).
  // ---------------------------------------------------------------------------
  const resolverIdentidade = async (authUserId: string): Promise<AuthIdentity | null> => {
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
  };

  const resolverCapabilities = async (authUserId: string, organizationId: string) => {
    const { data, error } = await admin.rpc("resolver_capabilities_escopos_efetivas", {
      p_user_profile_id: authUserId,
      p_organization_id: organizationId,
    });
    return error ? [] : ((data ?? []) as LinhaCapabilityEscopo[]);
  };

  // ---------------------------------------------------------------------------
  // Estado SOBERANO da operação corrente (D11/D12) — FATOS da linha, nunca
  // decisão e nunca declarados pelo cliente. A clausura vive por REQUISIÇÃO
  // (nenhum cache entre requisições — D10) e é preenchida pela MESMA operação que
  // está sendo autorizada: o `cycle_id` é intenção JÁ VALIDADA em forma.
  // ---------------------------------------------------------------------------
  const contextoDaOperacao: { cycleId: string | null } = { cycleId: null };

  /**
   * Status VIGENTE e soberano do colaborador-alvo (D11), lido da fonte
   * `collaborator_status_periods` no intervalo meio-aberto
   * `[valid_from, valid_to)` — a MESMA semântica da fonte usada pelo gate da RPC
   * (P2/P3). O tenant é conferido ANTES (defesa em profundidade): colaborador de
   * outro tenant ou sem período vigente ⇒ `null` (fail-closed).
   */
  const resolverStatusVigenteDoColaborador = async (
    collaboratorId: string,
    organizationId: string
  ): Promise<string | null> => {
    const { data: colaborador, error: erroColaborador } = await admin
      .from("collaborators")
      .select("id, organization_id")
      .eq("id", collaboratorId)
      .eq("organization_id", organizationId)
      .maybeSingle();
    if (erroColaborador || !colaborador) return null;

    const { data: periodos, error: erroPeriodos } = await admin
      .from("collaborator_status_periods")
      .select("status, valid_from, valid_to")
      .eq("collaborator_id", colaborador.id)
      .order("valid_from", { ascending: false });
    if (erroPeriodos) return null;

    const instante = Date.now();
    const vigente = ((periodos ?? []) as {
      status: string;
      valid_from: string;
      valid_to: string | null;
    }[]).find((periodo) => {
      const inicio = Date.parse(periodo.valid_from);
      const fim = periodo.valid_to === null ? null : Date.parse(periodo.valid_to);
      return inicio <= instante && (fim === null || fim > instante);
    });

    return vigente?.status ?? null;
  };

  /**
   * Status da LINHA soberana do ciclo da operação (D12), sempre com filtro de
   * tenant. `null` ⇒ ciclo inexistente ou de outro tenant: a fronteira NÃO
   * declara estado e a RPC soberana responde `NOT_FOUND` (sem oráculo).
   */
  const resolverStatusDoCiclo = async (
    cycleId: string,
    organizationId: string
  ): Promise<string | null> => {
    const { data, error } = await admin
      .from("evaluation_cycles")
      .select("id, organization_id, status")
      .eq("id", cycleId)
      .eq("organization_id", organizationId)
      .maybeSingle();
    if (error || !data) return null;
    return data.status ?? null;
  };

  /**
   * Contexto soberano do COLABORADOR-alvo (criação) devolvido ao engine: o status
   * VIGENTE do colaborador (D11) e o status da LINHA do ciclo da operação (D12) —
   * os dois campos opcionais acrescentados ao contrato do contexto na P4, ponto
   * único pelo qual a matriz de estado da observação conhece esses FATOS. São
   * declarados como observação local para que o arquivo permaneça compilável
   * enquanto o tipo-fonte e esta Edge são escritos em paralelo; nenhuma
   * propriedade é descartada em runtime.
   */
  type ContextoObservacaoSoberano = ContextoAvaliacaoSoberano & {
    readonly colaboradorStatus: string;
    readonly cicloStatus: string;
  };

  // ---------------------------------------------------------------------------
  // Fronteira de decisão (Policy Engine) — recurso SOBERANO carregado aqui.
  // ---------------------------------------------------------------------------
  const autorizacao: DepsContextoAutorizacao = {
    agora: () => new Date(),

    resolverIdentidade,

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
      const linhas = await resolverCapabilities(authUserId, organizationId);
      const porCapability = new Map<string, { scopes: Set<ScopeType>; units: Set<string> }>();
      for (const linha of linhas) {
        // Fail-closed do vocabulário: código não canônico não entra na matriz.
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

    // F5-11 P4 (§8 linha 4; D11/D12): contexto soberano do COLABORADOR-alvo — o
    // alvo funcional da CRIAÇÃO (a observação ainda não existe). O wiring declara
    // apenas FATOS da linha: o status VIGENTE do colaborador e o status da LINHA
    // do ciclo da operação. Quem decide (aptidão/estado) é o probe do domínio no
    // Policy Engine e, em última instância, a RPC. Dado não resolvível ⇒ `null`
    // (a fronteira não inventa estado nem aceita estado declarado pelo cliente).
    carregarContextoAvaliacao: async ({
      target,
      organizationId,
    }): Promise<ContextoObservacaoSoberano | null> => {
      if (target.type !== "collaborator") return null;

      const statusVigente = await resolverStatusVigenteDoColaborador(
        target.id,
        organizationId
      );
      if (!statusVigente) return null;

      const cicloId = contextoDaOperacao.cycleId;
      if (!cicloId) return null;
      const cicloStatus = await resolverStatusDoCiclo(cicloId, organizationId);
      if (!cicloStatus) return null;

      return {
        status: statusVigente,
        colaboradorStatus: statusVigente,
        cicloStatus,
      };
    },

    // F5-11 P4 (§7.1/§8, D1/D3/D5/D7/D12): a OBSERVAÇÃO é recurso SOBERANO e a
    // linha real é carregada server-side — o tenant vem do RECURSO (nunca do
    // caller) e o bloco soberano recebe o fato comunicado, a exclusão lógica, a
    // AUTORIA derivada (`author_collaborator_id`) e o status da LINHA do ciclo.
    // Sem essas leituras a autorização nega tudo (fail-closed): a Edge NUNCA
    // declara estado nem autoria.
    carregarRecurso: async ({ target, organizationId }) => {
      if (target.type === "observation") {
        const { data, error } = await admin
          .from("evaluation_observations")
          .select(
            "id, organization_id, cycle_id, collaborator_id, comunicado, excluida, author_collaborator_id"
          )
          .eq("id", target.id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (error || !data) return null;

        // Segunda leitura OBRIGATÓRIA, com filtro de tenant (defesa em
        // profundidade): o status do ciclo alimenta o estado de domínio da
        // observação (mutação exige ciclo vigente — D12).
        const { data: ciclo, error: erroCiclo } = await admin
          .from("evaluation_cycles")
          .select("id, organization_id, status")
          .eq("id", data.cycle_id)
          .eq("organization_id", organizationId)
          .maybeSingle();
        if (erroCiclo || !ciclo) return null;

        // Fato D11 do colaborador-ALVO da observação (status VIGENTE soberano):
        // insumo do bloco soberano consumido pelo probe do domínio. Melhor
        // esforço: não resolvido ⇒ o fato é OMITIDO (a matriz do alvo observação
        // não o exige; quem nega por ausência é o gate da RPC, nunca um valor
        // declarado pelo cliente).
        const colaboradorStatus =
          (await resolverStatusVigenteDoColaborador(data.collaborator_id, organizationId)) ??
          undefined;

        return {
          kind: "observation",
          id: data.id,
          organizationId: data.organization_id,
          ownerCollaboratorId: data.collaborator_id,
          cycleId: data.cycle_id,
          comunicado: fatoBooleano(data.comunicado),
          excluida: fatoBooleano(data.excluida),
          cicloStatus: ciclo.status,
          colaboradorStatus,
          authorCollaboratorId: data.author_collaborator_id,
        } as RecursoSoberanoCarregado;
      }

      // `observacao.criar`: a observação AINDA NÃO EXISTE — o alvo funcional é o
      // COLABORADOR-alvo (a relação estrutural do ciclo é avaliada sobre ele).
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
  };

  // ---------------------------------------------------------------------------
  // Execução privilegiada: RPC `observacao_*` (SECURITY INVOKER, EXECUTE só
  // service_role) com o ator VERIFICADO. Nenhum `p_payload_hash` é enviado: as
  // RPCs derivam o hash canônico server-side (D6) — e nenhum campo de
  // identidade/autoridade é aceito do corpo.
  // ---------------------------------------------------------------------------
  const executarRpc: DepsObservacoes["executarRpc"] = async (execucao: ExecucaoObservacao) => {
    const org = execucao.organizationId;
    const ator = execucao.actorUserProfileId;
    const operacaoId = execucao.operationId;
    const observacaoId = execucao.observationId;

    switch (execucao.operacao) {
      case "observacao.criar":
        return admin.rpc("observacao_criar", {
          p_organization_id: org,
          p_cycle_id: execucao.cycleId,
          p_collaborator_id: execucao.collaboratorId,
          p_tipo: execucao.tipo,
          p_texto: execucao.texto,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "observacao.editar":
        return admin.rpc("observacao_editar", {
          p_observation_id: observacaoId,
          p_organization_id: org,
          p_tipo: execucao.tipo,
          p_texto: execucao.texto,
          p_comunicado: execucao.comunicado,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "observacao.definir_comunicado":
        return admin.rpc("observacao_definir_comunicado", {
          p_observation_id: observacaoId,
          p_organization_id: org,
          p_comunicado: execucao.comunicado,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "observacao.excluir":
        return admin.rpc("observacao_excluir", {
          p_observation_id: observacaoId,
          p_organization_id: org,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "observacao.revogar":
        return admin.rpc("observacao_revogar", {
          p_observation_id: observacaoId,
          p_organization_id: org,
          p_motivo: execucao.motivo,
          p_expected_version: execucao.expectedVersion,
          p_actor_user_profile_id: ator,
          p_operation_id: operacaoId,
        });

      case "observacao.obter":
        // Leitura de UMA observação: a assinatura real NÃO tem `p_operation_id`
        // (não há evento de trilha) e a RPC aplica `observation.read` + a
        // visibilidade soberana (autoria, relação ou SELF-comunicada).
        return admin.rpc("observacao_obter", {
          p_observation_id: observacaoId,
          p_organization_id: org,
          p_actor_user_profile_id: ator,
        });

      case "observacao.listar_por_escopo":
        // Leitura por ESCOPO: a assinatura real NÃO tem `p_operation_id` e a RPC
        // aplica `observation.read`, o vínculo do ator, o ESCOPO (allowlist
        // fechada) e a relação resolvida na data — fonte única do alcance.
        // D21: a DATA NÃO é intenção transportável; o instante da decisão é
        // SOBERANO e resolvido AQUI, no servidor (relógio da Edge).
        return admin.rpc("observacao_listar_por_escopo", {
          p_organization_id: org,
          p_actor_user_profile_id: ator,
          p_escopo: execucao.escopo,
          p_organizational_unit_id: execucao.organizationalUnitId,
          p_data: new Date().toISOString(),
        });

      case "observacao.historico":
        // Trilha append-only: a assinatura real NÃO tem `p_operation_id` e a
        // visibilidade é a MESMA da leitura (§8 linha 10).
        return admin.rpc("observacao_historico", {
          p_observation_id: observacaoId,
          p_organization_id: org,
          p_actor_user_profile_id: ator,
        });

      default:
        // Inalcançável: o contrato só expõe operações contratadas.
        return { error: { code: "INVALID_INPUT", message: "Operação não suportada." } };
    }
  };

  const deps: DepsObservacoes = {
    resolveCaller: async (authHeader) => {
      const caller = createClient(url, anonKey, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await caller.auth.getUser();
      return error ? null : (data.user?.id ?? null);
    },

    resolverIdentidade,

    // Plano ADMINISTRATIVO (D19/D21): capabilities efetivas do ator na
    // organização, resolvidas server-side (o resolver revalida perfil,
    // membership e tenant — divergência ⇒ lista vazia ⇒ FORBIDDEN).
    resolverCapabilitiesEfetivas: async ({ actorUserProfileId, organizationId }) =>
      (await resolverCapabilities(actorUserProfileId, organizationId)).map((linha) => ({
        capability_code: linha.capability_code,
      })),

    avaliarAutorizacao: async ({ authUserId, organizationId, capability, alvo, cycleId }) => {
      const canonica = capabilityCanonica(capability) as Capability | undefined;
      if (!canonica) return { permitido: false, code: "FORBIDDEN" as const };

      // Estado de domínio da MESMA operação: o ciclo é INTENÇÃO já validada em
      // forma (nunca autoridade) e o wiring lê o STATUS da linha soberana.
      contextoDaOperacao.cycleId = cycleId ?? null;

      const decisao = await avaliarOperacaoAutorizacao(
        { authUserId, organizationId, capability: canonica, alvo },
        autorizacao
      );
      return decisao.allowed
        ? { permitido: true }
        : { permitido: false, code: decisao.denial?.publicCode ?? "FORBIDDEN" };
    },

    executarRpc,
  };

  return observacoes(req, deps);
});
