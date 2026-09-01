import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";

export type GlobalResource = Readonly<{
  kind: "global";
}>;

export type CollaboratorListResource = Readonly<{
  kind: "collaborator-list";
  collaborators: readonly Colaborador[];
}>;

export type EvaluationResource = Readonly<{
  kind: "evaluation";
  evaluatedCollaborator: Colaborador;
  collaborators: readonly Colaborador[];
  cycle?: CicloAvaliacao;
}>;

export type GoalResource = Readonly<{
  kind: "goal";
  owner: Colaborador;
  collaborators: readonly Colaborador[];
  cycle: CicloAvaliacao;
}>;

export type AuthorizationResource =
  | GlobalResource
  | CollaboratorListResource
  | EvaluationResource
  | GoalResource;

export type CollaboratorScopePurpose = "OPERATIONAL_TEAM" | "REPORT";

export type CollaboratorScopeInput = Readonly<{
  purpose: CollaboratorScopePurpose;
  collaborators: readonly Colaborador[];
}>;
