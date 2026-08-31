import type { Colaborador } from "../types/Colaborador";
import "../styles/collaborator-identity.css";

export type CollaboratorIdentityVariant = "compact" | "standard" | "profile";

interface CollaboratorIdentityProps {
  colaborador: Colaborador;
  variant?: CollaboratorIdentityVariant;
  gestorNome?: string;
  showStatus?: boolean;
  showMatricula?: boolean;
  className?: string;
}

function IconBriefcase() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M9 6V4h6v2M4 8h16v11H4V8Z" />
      <path d="M4 12h16M10 12v2h4v-2" />
    </svg>
  );
}

function IconBuilding() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M4 21V5h11v16M15 10h5v11M8 9h3M8 13h3M8 17h3" />
    </svg>
  );
}

function IconManager() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="9" cy="8" r="3" />
      <path d="M3.5 19c.6-3.4 2.5-5.2 5.5-5.2 2 0 3.5.8 4.4 2.3" />
      <path d="M16 14h5M18.5 11.5v5" />
    </svg>
  );
}

function IconBadge() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="5" y="4" width="14" height="16" rx="2" />
      <circle cx="9" cy="10" r="2" />
      <path d="M13 9h3M13 12h3M8 15h8" />
    </svg>
  );
}

function obterIniciais(nome: string) {
  return nome
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((parte) => parte[0])
    .join("")
    .toUpperCase();
}

function labelFuncao(colaborador: Colaborador) {
  if (colaborador.funcao === "GERENTE") return "Gerente";
  if (colaborador.funcao === "COORDENADOR") return "Coordenador";
  if (colaborador.funcao === "CONSULTOR") return "Consultor";
  if (colaborador.funcao === "ESTAGIARIO") return "Estagiário";
  return "Analista";
}

function labelSenioridade(colaborador: Colaborador) {
  if (colaborador.funcao !== "ANALISTA") return "";
  if (colaborador.senioridade === "JUNIOR") return "Júnior";
  if (colaborador.senioridade === "PLENO") return "Pleno";
  if (colaborador.senioridade === "SENIOR") return "Sênior";
  return "";
}

function labelStatus(colaborador: Colaborador) {
  if (colaborador.status === "ATIVO") return "Ativo";
  if (colaborador.status === "LICENCA") return "Em licença";
  return "Desligado";
}

function statusClass(colaborador: Colaborador) {
  if (colaborador.status === "ATIVO") return "is-active";
  if (colaborador.status === "LICENCA") return "is-leave";
  return "is-inactive";
}

export default function CollaboratorIdentity({
  colaborador,
  variant = "standard",
  gestorNome,
  showStatus = variant !== "compact",
  showMatricula = variant === "profile",
  className = "",
}: CollaboratorIdentityProps) {
  const senioridade = labelSenioridade(colaborador);
  const papel = `${labelFuncao(colaborador)}${senioridade ? ` • ${senioridade}` : ""}`;
  const mostrarDetalhes = variant !== "compact";
  const mostrarAdministrativo =
    variant === "profile" && (Boolean(gestorNome) || showMatricula);

  return (
    <div
      className={[
        "collaborator-identity",
        `collaborator-identity--${variant}`,
        className,
      ]
        .filter(Boolean)
        .join(" ")}
    >
      <div className="collaborator-identity__avatar" aria-hidden="true">
        {obterIniciais(colaborador.nome)}
      </div>

      <div className="collaborator-identity__body">
        <div className="collaborator-identity__title">
          <strong>{colaborador.nome}</strong>
          {showStatus && (
            <span
              className={`collaborator-identity__status ${statusClass(
                colaborador
              )}`}
            >
              {labelStatus(colaborador)}
            </span>
          )}
        </div>

        <div className="collaborator-identity__role">{papel}</div>

        {mostrarDetalhes && (
          <div className="collaborator-identity__details">
            {colaborador.cargo?.trim() && (
              <span className="collaborator-identity__detail">
                <span className="collaborator-identity__detail-icon">
                  <IconBriefcase />
                </span>
                <span>{colaborador.cargo}</span>
              </span>
            )}
            {colaborador.area?.trim() && (
              <span className="collaborator-identity__detail">
                <span className="collaborator-identity__detail-icon">
                  <IconBuilding />
                </span>
                <span>{colaborador.area}</span>
              </span>
            )}
          </div>
        )}

        {mostrarAdministrativo && (
          <div className="collaborator-identity__admin">
            {gestorNome && (
              <span className="collaborator-identity__detail">
                <span className="collaborator-identity__detail-icon">
                  <IconManager />
                </span>
                <span>
                  Gestor: <strong>{gestorNome}</strong>
                </span>
              </span>
            )}
            {showMatricula && (
              <span className="collaborator-identity__detail">
                <span className="collaborator-identity__detail-icon">
                  <IconBadge />
                </span>
                <span>Matrícula {colaborador.matricula}</span>
              </span>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
