import { useState } from "react";
import type { ExpectativaCargo, CargoExpectativa } from "../types/ExpectativaCargo";
import type { ExpectativaCargoSnapshot } from "../types/Feedback";
import "../styles/role-expectations.css";

type ExpectativaExibicao = ExpectativaCargo | ExpectativaCargoSnapshot;

type Props = {
  expectativa?: ExpectativaExibicao;
  cargo?: CargoExpectativa;
  titulo?: string;
  mensagemAusente?: string;
  defaultOpen?: boolean;
};

export default function RoleExpectationsCard({
  expectativa,
  titulo = "Expectativas do cargo",
  mensagemAusente = "Expectativa do cargo não registrada nesta avaliação.",
  defaultOpen = false,
}: Props) {
  const [aberto, setAberto] = useState(defaultOpen);

  return (
    <section className={`role-expectations-card ${aberto ? "is-open" : ""}`}>
      <button
        type="button"
        className="role-expectations-card__toggle"
        onClick={() => setAberto((valor) => !valor)}
        aria-expanded={aberto}
      >
        <div>
          <strong>{titulo}</strong>
          <small>
            {expectativa
              ? `${expectativa.nome} • referência para o ciclo`
              : "Referência histórica indisponível"}
          </small>
        </div>
        <span className="role-expectations-card__chevron" aria-hidden="true">⌄</span>
      </button>

      {aberto && (
        <div className="role-expectations-card__content">
          {expectativa ? (
            <div className="role-expectations-card__grid">
              <article>
                <span>Autonomia</span>
                <p>{expectativa.autonomia}</p>
              </article>
              <article>
                <span>Tarefas</span>
                <p>{expectativa.tarefas}</p>
              </article>
              <article>
                <span>Responsabilidades</span>
                <p>{expectativa.responsabilidades}</p>
              </article>
              <article>
                <span>Foco</span>
                <p>{expectativa.foco}</p>
              </article>
            </div>
          ) : (
            <p className="role-expectations-card__empty">{mensagemAusente}</p>
          )}
        </div>
      )}
    </section>
  );
}
