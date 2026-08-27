import type { CSSProperties } from "react";
import { useNavigate } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";
import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import "../styles/avaliacoes.css";

function MinhaAvaliacaoPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();

  if (!usuarioAtual) {
    return (
      <main className="virtus-page">
        <section className="evaluation-empty">
          <h1>Usuário atual não definido</h1>
        </section>
      </main>
    );
  }

  const escalaAvaliacao = getEscalaAvaliacao();

  function estiloNota(valor: number) {
    const faixa = getItemEscalaPorNota(valor, escalaAvaliacao);

    return {
      "--score-color": faixa.cor,
      "--score-bg": faixa.corFundo,
      "--score-border": `${faixa.cor}44`,
    } as CSSProperties;
  }

  function labelNota(valor: number) {
    return getItemEscalaPorNota(valor, escalaAvaliacao).significado;
  }

  const avaliacoesConcluidas = getFeedbacksByColaborador(
    usuarioAtual.matricula
  )
    .filter((feedback) => feedback.status === "CONCLUIDA")
    .sort((a, b) => b.ano - a.ano || b.ciclo - a.ciclo);

  return (
    <main className="virtus-page evaluation-page">
      <section className="evaluation-page-header">
        <div>
          <h1>Minhas Avaliações</h1>
          <p>
            Consulte seu histórico de avaliações concluídas e acompanhe sua
            evolução ao longo dos ciclos.
          </p>
        </div>

        <div className="evaluation-page-actions">
          {usuarioAtual.funcao !== "GERENTE" && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--secondary"
              onClick={() => navigate("/minhas-metas")}
            >
              Minhas Metas
            </button>
          )}

          {usuarioAtual.funcao === "COORDENADOR" && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--secondary"
              onClick={() => navigate("/")}
            >
              Minha equipe
            </button>
          )}
        </div>
      </section>

      <section className="evaluation-profile-card">
        <div className="evaluation-profile-card__avatar" aria-hidden="true">
          {usuarioAtual.nome
            .split(" ")
            .filter(Boolean)
            .slice(0, 2)
            .map((parte) => parte[0])
            .join("")
            .toUpperCase()}
        </div>

        <div>
          <strong>{usuarioAtual.nome}</strong>
          <span>
            {usuarioAtual.funcao === "COORDENADOR"
              ? "Coordenador"
              : usuarioAtual.funcao === "CONSULTOR"
              ? "Consultor"
              : usuarioAtual.funcao === "ANALISTA"
              ? "Analista"
              : "Gerente"}
          </span>
        </div>

        <div className="evaluation-profile-card__summary">
          <strong>{avaliacoesConcluidas.length}</strong>
          <span>
            {avaliacoesConcluidas.length === 1
              ? "avaliação concluída"
              : "avaliações concluídas"}
          </span>
        </div>
      </section>

      {avaliacoesConcluidas.length === 0 ? (
        <section className="evaluation-empty">
          <h2>Nenhuma avaliação concluída disponível</h2>
          <p>
            Quando um ciclo for concluído, sua avaliação ficará disponível
            aqui para consulta.
          </p>
        </section>
      ) : (
        <section className="evaluation-history">
          <div className="evaluation-section-heading">
            <div>
              <span className="evaluation-eyebrow">Histórico</span>
              <h2>Avaliações concluídas</h2>
            </div>
          </div>

          <div className="evaluation-history-grid">
            {avaliacoesConcluidas.map((feedback) => (
              <article
                className="evaluation-history-card evaluation-history-card--semantic score-semantic"
                style={estiloNota(feedback.notaMedia)}
                key={feedback.id}
              >
                <div className="evaluation-history-card__main">
                  <div className="evaluation-history-card__cycle">
                    <span className="evaluation-cycle-label">
                      {feedback.ano} • Ciclo {feedback.ciclo}
                    </span>
                    <span className="evaluation-history-card__status">
                      Concluída
                    </span>
                  </div>

                  <div className="evaluation-history-card__score">
                    <strong>{formatarNota(feedback.notaMedia)}</strong>
                    <div>
                      <span>Nota final</span>
                      <small>{labelNota(feedback.notaMedia)}</small>
                    </div>
                  </div>
                </div>

                <button
                  type="button"
                  className="evaluation-btn evaluation-btn--primary"
                  onClick={() =>
                    navigate(`/minha-avaliacao/${feedback.id}`)
                  }
                >
                  Ver avaliação →
                </button>
              </article>
            ))}
          </div>
        </section>
      )}
    </main>
  );
}

export default MinhaAvaliacaoPage;
