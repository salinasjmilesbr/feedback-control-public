import type { Colaborador } from "../types/Colaborador";
import { Link } from "react-router-dom";
import { getColaboradorByMatricula } from "../services/colaboradorStorage";

function formatarNome(nome: string) {
  return nome
    .toLowerCase()
    .split(" ")
    .map(
      (palavra) =>
        palavra.charAt(0).toUpperCase() + palavra.slice(1)
    )
    .join(" ");
}

function obterIniciais(nome: string) {
  const partes = nome
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (partes.length === 0) return "?";
  if (partes.length === 1) return partes[0].slice(0, 2).toUpperCase();

  return `${partes[0][0]}${partes[partes.length - 1][0]}`.toUpperCase();
}

interface Props {
  colaborador: Colaborador;
}

function ColaboradorCard({ colaborador }: Props) {
  const gestorDireto = colaborador.gestorDiretoMatricula
    ? getColaboradorByMatricula(colaborador.gestorDiretoMatricula)
    : undefined;

  const funcaoLabel =
    colaborador.funcao === "GERENTE"
      ? "Gerente"
      : colaborador.funcao === "COORDENADOR"
      ? "Coordenador"
      : colaborador.funcao === "CONSULTOR"
      ? "Consultor"
      : "Analista";

  const senioridadeLabel =
    colaborador.senioridade === "JUNIOR"
      ? "Júnior"
      : colaborador.senioridade === "PLENO"
      ? "Pleno"
      : colaborador.senioridade === "SENIOR"
      ? "Sênior"
      : undefined;

  const statusLabel =
    colaborador.status === "ATIVO"
      ? "Ativo"
      : colaborador.status === "LICENCA"
      ? "Em licença"
      : "Desligado";

  const statusClass =
    colaborador.status === "ATIVO"
      ? "is-active"
      : colaborador.status === "LICENCA"
      ? "is-leave"
      : "is-inactive";

  return (
    <article className="collaborator-card">
      <div className="collaborator-card__top">
        <div className="collaborator-card__avatar" aria-hidden="true">
          {obterIniciais(colaborador.nome)}
        </div>

        <div className="collaborator-card__identity">
          <h3>{formatarNome(colaborador.nome)}</h3>
          <div className="collaborator-card__role">
            {funcaoLabel}
            {senioridadeLabel ? ` • ${senioridadeLabel}` : ""}
          </div>
          <div className="collaborator-card__position">
            {colaborador.cargo}
          </div>
        </div>

        <span className={`status-pill ${statusClass}`}>
          {statusLabel}
        </span>
      </div>

      <div className="collaborator-card__divider" />

      <div className="collaborator-card__details">
        {gestorDireto && (
          <div className="collaborator-card__detail">
            <span className="collaborator-card__detail-icon">↳</span>
            <div>
              <small>Gestor direto</small>
              <strong>{formatarNome(gestorDireto.nome)}</strong>
            </div>
          </div>
        )}

        {colaborador.area && (
          <div className="collaborator-card__detail">
            <span className="collaborator-card__detail-icon">▦</span>
            <div>
              <small>Área</small>
              <strong>{colaborador.area}</strong>
            </div>
          </div>
        )}
      </div>

      <div className="collaborator-card__footer">
        <div className="collaborator-card__matricula">
          <span className="collaborator-card__detail-icon" aria-hidden="true">▣</span>
          <div>
            <small>Matrícula</small>
            <strong>{colaborador.matricula}</strong>
          </div>
        </div>

        <Link
          className="collaborator-card__link"
          to={`/colaborador/${colaborador.matricula}`}
        >
          Ver histórico
          <span aria-hidden="true">→</span>
        </Link>
      </div>
    </article>
  );
}

export default ColaboradorCard;
