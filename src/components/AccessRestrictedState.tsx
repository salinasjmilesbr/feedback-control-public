import { Link, type To } from "react-router-dom";
import "../styles/access-restricted-state.css";

type AccessRestrictedStateProps = Readonly<{
  message: string;
  actionTo?: To;
  actionLabel?: string;
  onAction?: () => void;
}>;

function AccessRestrictedState({
  message,
  actionTo = "/",
  actionLabel = "Voltar ao início",
  onAction,
}: AccessRestrictedStateProps) {
  return (
    <main className="virtus-page access-restricted-state">
      <section className="access-restricted-state__card" role="alert">
        <span className="access-restricted-state__eyebrow">Acesso protegido</span>
        <h1>Acesso restrito</h1>
        <p>{message}</p>
        {onAction ? (
          <button
            className="access-restricted-state__action"
            type="button"
            onClick={onAction}
          >
            {actionLabel}
          </button>
        ) : (
          <Link className="access-restricted-state__action" to={actionTo}>
            {actionLabel}
          </Link>
        )}
      </section>
    </main>
  );
}

export default AccessRestrictedState;
