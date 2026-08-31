import type { Colaborador } from "../types/Colaborador";
import CollaboratorIdentity from "./CollaboratorIdentity";
import { Link } from "react-router-dom";


interface Props {
  colaborador: Colaborador;
}

function ColaboradorCard({ colaborador }: Props) {
  return (
    <article className="collaborator-card collaborator-card--identity">
      <CollaboratorIdentity
        colaborador={colaborador}
        variant="standard"
      />

      <div className="collaborator-card__footer collaborator-card__footer--identity">
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
