import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Observacao } from "../types/Observacao";
import type { StatusFeedback } from "../types/Feedback";
import type { DevCapabilityBindings } from "./mundoFuncional";
import type { DomainStateProbe } from "./policyEngine/types";

export type GlobalResource = Readonly<{
  kind: "global";
  /** Opcional (compat): quando ausente, a policy deriva o mundo do storage. */
  collaborators?: readonly Colaborador[];
}>;

export type CollaboratorListResource = Readonly<{
  kind: "collaborator-list";
  collaborators: readonly Colaborador[];
}>;

/**
 * F5-09 P6 (§8, D20/D21) — projeção MÍNIMA de ciclo para AUTORIZAÇÃO.
 *
 * Identidade canônica (`id` = UUID de `evaluation_cycles.id`, F5-09 P1) e estado
 * do domínio (`status`). `CicloSoberano` (P5) e `CicloAvaliacao` (legado) a
 * satisfazem ESTRUTURALMENTE: uma única projeção, sem duplicar entidade de ciclo
 * e sem inventar campo ausente.
 *
 * Autoridade: no caminho de ENFORCEMENT (`avaliarOperacaoAutorizacao`) o `id` e o
 * `status` vêm SEMPRE da linha soberana carregada server-side
 * (`RecursoSoberanoCarregado`), nunca deste recurso nem do corpo da requisição —
 * por isso não existe aqui nenhum campo de tenant ou de identidade do ator. A
 * compatibilidade com o ciclo legado é EXPLÍCITA e transitória (cutover no P8) e
 * NÃO pode suplantar a linha soberana: na fronteira confiável o probe do alvo
 * `cycle` é derivado do status soberano, mesmo que outro estado seja declarado.
 */
export type CicloParaAutorizacao = Readonly<{
  /** UUID canônico do ciclo (`evaluation_cycles.id`). */
  id: string;
  /** Status do domínio fechado: PLANEJADO | ATIVO | ENCERRADO | CANCELADO. */
  status: string;
}>;

export type CycleResource = Readonly<{
  kind: "cycle";
  cycle: CicloParaAutorizacao;
  /** Opcional (compat): quando ausente, a policy deriva o mundo do storage. */
  collaborators?: readonly Colaborador[];
}>;

export type CollaboratorResource = Readonly<{
  kind: "collaborator";
  collaborator: Colaborador;
  /** Opcional (compat): quando ausente, a policy deriva o mundo do storage. */
  collaborators?: readonly Colaborador[];
}>;

export type EvaluationResource = Readonly<{
  kind: "evaluation";
  evaluatedCollaborator: Colaborador;
  collaborators: readonly Colaborador[];
  cycle?: CicloAvaliacao;
  evaluationStatus?: StatusFeedback;
}>;

export type GoalResource = Readonly<{
  kind: "goal";
  owner: Colaborador;
  collaborators: readonly Colaborador[];
  cycle: CicloAvaliacao;
}>;

export type ObservationResource = Readonly<{
  kind: "observation";
  collaborator: Colaborador;
  observation?: Observacao;
  cycle?: CicloAvaliacao;
  /** Opcional (compat): quando ausente, a policy deriva o mundo do storage. */
  collaborators?: readonly Colaborador[];
}>;

export type AuthorizationResource =
  | GlobalResource
  | CycleResource
  | CollaboratorResource
  | CollaboratorListResource
  | EvaluationResource
  | GoalResource
  | ObservationResource;

export type CollaboratorScopePurpose = "OPERATIONAL_TEAM" | "REPORT";

export type CollaboratorScopeInput = Readonly<{
  purpose: CollaboratorScopePurpose;
  collaborators: readonly Colaborador[];
  /** Probe de estado do domínio para a avaliação final (default: permite). */
  domainState?: DomainStateProbe;
  cicloId?: string;
  /** Binding DEV-only explícito (testes/revogação); default derivado dos dados. */
  bindingsDev?: DevCapabilityBindings;
}>;
