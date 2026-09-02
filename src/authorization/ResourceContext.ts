import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Observacao } from "../types/Observacao";
import type { StatusFeedback } from "../types/Feedback";

export type GlobalResource = Readonly<{
  kind: "global";
}>;

export type CollaboratorListResource = Readonly<{
  kind: "collaborator-list";
  collaborators: readonly Colaborador[];
}>;

export type CollaboratorResource = Readonly<{
  kind: "collaborator";
  collaborator: Colaborador;
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
}>;

export type AuthorizationResource =
  | GlobalResource
  | CollaboratorResource
  | CollaboratorListResource
  | EvaluationResource
  | GoalResource
  | ObservationResource;

export type CollaboratorScopePurpose = "OPERATIONAL_TEAM" | "REPORT";

export type CollaboratorScopeInput = Readonly<{
  purpose: CollaboratorScopePurpose;
  collaborators: readonly Colaborador[];
}>;
