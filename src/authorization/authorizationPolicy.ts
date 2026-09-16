import { simulacaoDevPermitida } from "../config/ambiente";
import { getColaboradores } from "../services/colaboradorStorage";
import { aplicarEscopoRelatorio } from "../services/relatorioService";
import { getColaboradoresVisiveis } from "../services/visibilidadeColaboradores";
import type { Colaborador } from "../types/Colaborador";
import type { AuthorizationContext } from "./AuthorizationContext";
import { alvosPermitidos } from "./autorizacaoFuncional";
import { canonicalizarCapability } from "./canonical";
import type { Capability } from "./Capability";
import { estadoDominioCiclo } from "./estadoDominioCiclo";
import {
  criarProvidersMundoFuncional,
  estaNaCadeiaDeGestao,
  LOCAL_ORGANIZATION_ID,
} from "./mundoFuncional";
import type { DomainStateProbe, TargetRef } from "./policyEngine/types";
import { can as canEngine } from "./policyEngine/policyEngine";
import type {
  AuthorizationResource,
  CollaboratorScopeInput,
} from "./ResourceContext";
import { AuthorizationError } from "./authorizationError";

/**
 * F4-09 (Issue #96): adaptador de COMPATIBILIDADE — a decisão real é do Policy
 * Engine (`policyEngine.decidir`), alimentado por providers derivados dos DADOS
 * (`mundoFuncional`, nunca `funcao`/`cargo`). Aqui NÃO existe regra soberana de
 * autorização nem derivação de papel por `funcao`: este módulo apenas traduz o
 * vocabulário legado (capability + resource) para uma requisição do engine
 * (capability canônica + target + domainState) e delega.
 */

function dominioPermite(permite: boolean): DomainStateProbe {
  return { allows: () => permite };
}

/** Status de colaborador que impede NOVA observação (D11; `inactive` do §7.9). */
const STATUS_COLABORADOR_INATIVO = "DESLIGADO";

/** Projeção mínima do estado REAL do recurso OBSERVAÇÃO consumida pelo probe. */
export interface EstadoObservacaoSoberano {
  /** Status da LINHA do ciclo da observação (`ATIVO` libera mutação — D12). */
  readonly cicloStatus?: string | null;
  /** Status do colaborador-ALVO da observação (D11). */
  readonly colaboradorStatus?: string | null;
}

function statusNormalizado(valor: unknown): string {
  return typeof valor === "string" ? valor.trim().toUpperCase() : "";
}

/**
 * F5-11 P3 (§8; D5, D11, D12) — ESTADO DE DOMÍNIO do recurso OBSERVAÇÃO.
 *
 * O Policy Engine decide **QUEM** pode agir (identidade, membership, capability,
 * escopo e relação); este helper declara **SE** a ação é possível no estado atual
 * do recurso. É a ÚNICA declaração dessa matriz para a observação, consumida
 * pelo adaptador funcional (`case "observation"` de `requisicaoEngine`), ao lado
 * do fato de AUTORIA imposto pela D5 — que NÃO é estado e por isso é composto
 * pelo chamador.
 *
 * Matriz contratada (§8; D11/D12) — fonte única:
 *
 * | capability           | exige                                                       |
 * | `observation.create` | ciclo `ATIVO` **e** colaborador-alvo ≠ `DESLIGADO` (D11)     |
 * | `observation.edit`   | ciclo `ATIVO` (editar, comunicar/descomunicar e revogar)     |
 * | `observation.delete` | ciclo `ATIVO`                                                |
 * | `observation.read`   | nada — leitura histórica em QUALQUER estado                  |
 *
 * `LICENCA` **permite** criar (paridade com `authorizationPolicy.test.ts` e com
 * §7.9). Capability fora da matriz ⇒ NEGADO (`default: false`, fail-closed).
 */
export function estadoDominioObservacao(
  entrada: EstadoObservacaoSoberano
): DomainStateProbe {
  const cicloAtivo = statusNormalizado(entrada?.cicloStatus) === "ATIVO";
  const colaboradorInativo =
    statusNormalizado(entrada?.colaboradorStatus) === STATUS_COLABORADOR_INATIVO;

  return {
    allows: (capability: Capability): boolean => {
      switch (capability) {
        case "observation.create":
          return cicloAtivo && !colaboradorInativo;
        case "observation.edit":
        case "observation.delete":
          return cicloAtivo;
        case "observation.read":
          return true;
        default:
          return false;
      }
    },
  };
}

/**
 * F5-11 P3 (§8; D5/D7) — capabilities de observação que exigem que o ATOR seja o
 * AUTOR do recurso. Editar, marcar/desmarcar comunicado e revogar a exclusão são
 * `observation.edit`; excluir é `observation.delete`. Criar e ler não exigem
 * autoria (quem cria passa a ser o autor; a leitura tem matriz própria).
 */
function exigeAutoriaObservacao(capability: Capability): boolean {
  return capability === "observation.edit" || capability === "observation.delete";
}

function resolverAtor(
  context: AuthorizationContext,
  colaboradores: readonly Colaborador[]
): Colaborador | undefined {
  const colaborador = colaboradores.find(
    (colaborador) => colaborador.matricula === context.actor.matricula
  );
  if (!colaborador) return undefined;

  return {
    ...colaborador,
    matricula: context.actor.matricula,
    funcao: context.actor.funcao,
    status: context.actor.status,
  };
}

/**
 * Mundo funcional do recurso — F5-08 P6 (cutover estrutural).
 *
 * Regra de produção: o mundo (colaboradores + cadeia de gestão) só existe quando
 * é PASSADO explicitamente pelo recurso — e o recurso o obtém da projeção
 * SOBERANA. **Não há fallback para o cadastro legado em `localStorage`**: sem
 * mundo explícito o conjunto é VAZIO, o ator não resolve e a decisão é DENY
 * (fail-closed). Dado local antigo não é autoridade estrutural.
 *
 * Exceção ÚNICA e explícita: o contexto DEV do Vite (`simulacaoDevPermitida`),
 * onde o mundo vem das fixtures fictícias — como já ocorre com o seletor de
 * impersonação (F2-09). Em HOMOLOG/PROD o gate é sempre falso.
 */
function colaboradoresDoRecurso(
  resource: AuthorizationResource
): readonly Colaborador[] {
  const colaboradores = (
    resource as { collaborators?: readonly Colaborador[] }
  ).collaborators;
  if (colaboradores && colaboradores.length > 0) return colaboradores;

  if (simulacaoDevPermitida) {
    try {
      return getColaboradores();
    } catch {
      // Fixture ilegível em DEV ⇒ mundo vazio ⇒ DENY (fail-closed).
      return [];
    }
  }

  return [];
}

interface RequisicaoEngine {
  capability: Capability;
  target: TargetRef;
  domainState: DomainStateProbe;
  cycleId?: string;
}

/**
 * Traduz capability legada + resource em uma requisição do engine. Retorna null
 * quando a combinação é incompatível (fail-closed ⇒ DENY).
 */
function requisicaoEngine(
  ator: Colaborador,
  colaboradores: readonly Colaborador[],
  capability: Capability,
  resource: AuthorizationResource
): RequisicaoEngine | null {
  const canonica = canonicalizarCapability(capability);
  const atorId = ator.matricula;

  switch (resource.kind) {
    case "evaluation": {
      const alvo: TargetRef = {
        type: "collaborator",
        id: String(resource.evaluatedCollaborator.matricula),
      };
      const status = resource.evaluationStatus;
      const cicloStatus = resource.cycle?.status;
      const cycleId = resource.cycle?.id;

      switch (canonica) {
        case "evaluation.create":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              cicloStatus !== "CANCELADO" &&
                resource.evaluatedCollaborator.status === "ATIVO"
            ),
          };
        case "evaluation.read":
          // view.admin é leitura ADMINISTRATIVA de terceiro; SELF não usa o alias.
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              atorId !== resource.evaluatedCollaborator.matricula
            ),
          };
        case "evaluation.write":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              cicloStatus !== "CANCELADO" &&
                status !== "CONCLUIDA" &&
                status !== "CANCELADA"
            ),
          };
        case "evaluation.cancel":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              cicloStatus !== "CANCELADO" && status !== "CANCELADA"
            ),
          };
        case "evaluation.reopen":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              status === "CONCLUIDA" &&
                cicloStatus !== "ENCERRADO" &&
                cicloStatus !== "CANCELADO"
            ),
          };
        default:
          return null;
      }
    }

    case "goal": {
      const alvo: TargetRef = {
        type: "collaborator",
        id: String(resource.owner.matricula),
      };
      const cycleId = resource.cycle.id;

      switch (canonica) {
        case "goal.read":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(true),
          };
        case "goal.approve":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              resource.cycle.status === "ATIVO" &&
                estaNaCadeiaDeGestao(ator, resource.owner, colaboradores)
            ),
          };
        case "goal.write":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              resource.cycle.status === "ATIVO" &&
                ator.matricula === resource.owner.matricula
            ),
          };
        default:
          return null;
      }
    }

    case "observation": {
      // F5-11 P3 (§8, §17.1; D5/D11/D12): a OBSERVAÇÃO deixa de ser tipo não
      // soberano e passa a recurso SOBERANO. O alvo do engine continua sendo o
      // COLABORADOR-alvo (relação do ciclo) e o ESTADO vem do helper de FONTE
      // ÚNICA (`estadoDominioObservacao`); o fato de AUTORIA — que não é estado e
      // nunca é derivado de `funcao`/cargo — é composto no MESMO probe, porque a
      // D5 é condição cumulativa de `observation.edit`/`observation.delete`.
      const alvo: TargetRef = {
        type: "collaborator",
        id: String(resource.collaborator.matricula),
      };
      const cycleId = resource.cycle?.id;

      const estado = estadoDominioObservacao({
        cicloStatus: resource.cycle?.status,
        colaboradorStatus: resource.collaborator.status,
      });

      // D5 — AUTORIA: somente o AUTOR da observação do recurso edita/exclui/
      // revoga/altera comunicado. O autor é o da observação CARREGADA
      // (`Observacao.autorMatricula`); sem observação não há autoria PROVADA ⇒
      // DENY (fail-closed) — autoria nunca vem do cliente.
      const autor = resource.observation
        ? String(resource.observation.autorMatricula)
        : null;
      const atorEhAutor = autor !== null && autor === String(ator.matricula);

      const domainState: DomainStateProbe = {
        allows: (capability: Capability): boolean =>
          estado.allows(capability) &&
          (!exigeAutoriaObservacao(capability) || atorEhAutor),
      };

      switch (canonica) {
        case "observation.create":
        case "observation.edit":
        case "observation.delete":
        case "observation.read":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState,
          };
        default:
          return null;
      }
    }

    case "cycle": {
      // F5-09 P6 (§8, D20/D21): o alvo autorizável é o UUID CANÔNICO do ciclo
      // (`evaluation_cycles.id`) — nunca `{type:"cycle", id:"global"}`, nunca
      // `ano`/`numero` e nunca rótulo textual. A MATRIZ de estado é única e vem
      // de `estadoDominioCiclo`, a mesma fonte consumida pela fronteira soberana
      // (`contextoAutorizacao`): o engine decide QUEM age; o domínio decide SE a
      // ação é possível no estado atual.
      const alvo: TargetRef = { type: "cycle", id: resource.cycle.id };
      const domainState = estadoDominioCiclo({ status: resource.cycle.status });

      // Sem identidade de ciclo não há recurso: fail-closed (nenhum id é
      // inventado e nenhuma decisão é tomada sobre alvo vazio).
      if (!resource.cycle.id) return null;

      switch (canonica) {
        case "cycle.read":
        case "cycle.manage":
        case "cycle.cancel":
        case "cycle.reopen":
        case "cycle.period.correct":
          return {
            capability: canonica,
            target: alvo,
            cycleId: resource.cycle.id,
            domainState,
          };
        default:
          return null;
      }
    }

    case "collaborator": {
      const alvo: TargetRef = {
        type: "collaborator",
        id: String(resource.collaborator.matricula),
      };

      switch (canonica) {
        case "collaborator.edit":
        case "collaborator.read":
          return {
            capability: canonica,
            target: alvo,
            domainState: dominioPermite(true),
          };
        default:
          return null;
      }
    }

    case "collaborator-list": {
      // Gate de "posso listar": capability sobre o próprio ator (SELF).
      const alvo: TargetRef = { type: "collaborator", id: String(atorId) };

      switch (canonica) {
        case "collaborator.read":
          return {
            capability: canonica,
            target: alvo,
            domainState: dominioPermite(true),
          };
        default:
          return null;
      }
    }

    case "global": {
      // LEGADO/TRANSITÓRIO (F5-05 D19/D22; F5-09 P6 §6): este caso usa ALVOS
      // SINTÉTICOS (`{ type: "cycle", id: "global" }` e o próprio ator) e NÃO é
      // autorização real. O enforcement real (`contextoAutorizacao`) recusa alvos
      // globais/sintéticos e exige recurso tenant-rooted com fonte soberana
      // (para CICLO: UUID canônico + estado da linha soberana).
      //
      // F5-09 P6: nenhuma capability de CICLO é decidida sobre o alvo sintético
      // de ciclo — `cycle.read` aqui é apenas o gate de NAVEGAÇÃO/lista ancorado
      // no colaborador do PRÓPRIO ator (§8 item 3); as cinco capabilities de
      // ciclo têm decisão real no `case "cycle"` acima e no Edge (P7).
      const alvoSelf: TargetRef = { type: "collaborator", id: String(atorId) };
      const alvoCiclo: TargetRef = { type: "cycle", id: "global" };

      switch (canonica) {
        case "collaborator.create":
          return {
            capability: canonica,
            target: alvoSelf,
            domainState: dominioPermite(true),
          };
        case "report.read":
        case "cycle.read":
          // Gates de navegação: report.view / cycle.management.view /
          // cycle.coordinator.list / cycle.team.panel.view.
          return {
            capability: canonica,
            target: alvoSelf,
            domainState: dominioPermite(true),
          };
        case "settings.manage":
          return {
            capability: canonica,
            target: alvoCiclo,
            domainState: dominioPermite(true),
          };
        default:
          return null;
      }
    }
  }
}

function decidir(
  context: AuthorizationContext,
  capability: Capability,
  resource: AuthorizationResource
): boolean {
  const colaboradores = colaboradoresDoRecurso(resource);
  const ator = resolverAtor(context, colaboradores);
  if (!ator) return false;

  const requisicao = requisicaoEngine(ator, colaboradores, capability, resource);
  if (!requisicao) return false;

  const decisao = canEngine(
    {
      actor: {
        actorId: String(ator.matricula),
        organizationId: LOCAL_ORGANIZATION_ID,
      },
      capability: requisicao.capability,
      target: requisicao.target,
      context: { date: new Date(), cycleId: requisicao.cycleId },
      domainState: requisicao.domainState,
    },
    criarProvidersMundoFuncional({ actor: ator, colaboradores })
  );

  return decisao.allowed;
}

export function can(
  context: AuthorizationContext,
  capability: Capability,
  resource: AuthorizationResource
): boolean {
  return decidir(context, capability, resource);
}

export function authorize(
  context: AuthorizationContext,
  capability: Capability,
  resource: AuthorizationResource
): void {
  if (!decidir(context, capability, resource)) {
    throw new AuthorizationError(capability);
  }
}

export function scopeCollaborators(
  context: AuthorizationContext,
  input: CollaboratorScopeInput
): readonly Colaborador[] {
  const actor = resolverAtor(context, input.collaborators);
  if (!actor) return [];

  // 1) Descoberta de CANDIDATOS (dados/hierarquia + UX). NÃO é autorização.
  const visiveis = getColaboradoresVisiveis(
    actor,
    [...input.collaborators]
  );
  const candidatos =
    input.purpose === "REPORT"
      ? aplicarEscopoRelatorio(
          visiveis.map((colaborador) => ({ colaborador })),
          actor
        ).map(({ colaborador }) => colaborador)
      : visiveis;

  // 2) Decisão FINAL via Policy Engine (capability + target + scope + relação +
  //    domainState). Somente ALLOW permanece (fail-closed).
  const capability: Capability =
    input.purpose === "REPORT" ? "report.read" : "collaborator.read";
  const permitidos = alvosPermitidos(
    actor,
    [...input.collaborators],
    capability,
    input.domainState ?? dominioPermite(true),
    input.cicloId,
    input.bindingsDev
  );
  const idsPermitidos = new Set(permitidos.map((c) => c.matricula));

  return candidatos.filter((c) => idsPermitidos.has(c.matricula));
}
