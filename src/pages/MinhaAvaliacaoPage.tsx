import type { CSSProperties } from "react";
import { useNavigate } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import CollaboratorIdentity from "../components/CollaboratorIdentity";
import {
  getFeedbacksByColaborador,
  getFeedbacksConcluidosByColaborador,
} from "../services/feedbackStorage";
import { getCiclosAvaliacao } from "../services/cicloAvaliacaoStorage";
import {
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import {
  formatarNotaAvaliacao,
  getTextoNotaAvaliacao,
  possuiNotaAvaliacao,
} from "../services/apresentacaoNota";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Feedback } from "../types/Feedback";
import "../styles/avaliacoes.css";
import "../styles/minhas-avaliacoes.css";

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
    if (!possuiNotaAvaliacao(valor)) {
      return {
        "--score-color": "#655d69",
        "--score-bg": "#f4f1f5",
        "--score-border": "#d8d2dc",
      } as CSSProperties;
    }
    const faixa = getItemEscalaPorNota(valor, escalaAvaliacao);

    return {
      "--score-color": faixa.cor,
      "--score-bg": faixa.corFundo,
      "--score-border": `${faixa.cor}44`,
    } as CSSProperties;
  }

  function labelNota(valor: number) {
    return getTextoNotaAvaliacao(valor, escalaAvaliacao);
  }

  const ciclos = getCiclosAvaliacao();
  const ciclosCancelados = ciclos.filter(
    (ciclo) => ciclo.status === "CANCELADO"
  );
  const chavesCiclosCancelados = new Set(
    ciclosCancelados.map((ciclo) => `${ciclo.ano}-${ciclo.ciclo}`)
  );
  const feedbacksDoColaborador = getFeedbacksByColaborador(
    usuarioAtual.matricula
  );
  const avaliacoesConcluidas = getFeedbacksConcluidosByColaborador(
    usuarioAtual.matricula
  )
    .filter(
      (feedback) =>
        !chavesCiclosCancelados.has(`${feedback.ano}-${feedback.ciclo}`)
    )
    .sort((a, b) => b.ano - a.ano || b.ciclo - a.ciclo);
  const ciclosCanceladosParticipados = ciclosCancelados
    .filter((ciclo) =>
      feedbacksDoColaborador.some(
        (feedback) =>
          feedback.ano === ciclo.ano && feedback.ciclo === ciclo.ciclo
      )
    )
    .sort((a, b) => b.ano - a.ano || b.ciclo - a.ciclo);
  type ItemHistorico =
    | { tipo: "CONCLUIDA"; ano: number; ciclo: number; feedback: Feedback }
    | { tipo: "CANCELADO"; ano: number; ciclo: number; cicloCancelado: CicloAvaliacao };
  const historico: ItemHistorico[] = [
    ...avaliacoesConcluidas.map((feedback) => ({
      tipo: "CONCLUIDA" as const,
      ano: feedback.ano,
      ciclo: feedback.ciclo,
      feedback,
    })),
    ...ciclosCanceladosParticipados.map((cicloCancelado) => ({
      tipo: "CANCELADO" as const,
      ano: cicloCancelado.ano,
      ciclo: cicloCancelado.ciclo,
      cicloCancelado,
    })),
  ].sort((a, b) => b.ano - a.ano || b.ciclo - a.ciclo);

  return (
    <main className="virtus-page evaluation-page my-evaluations-page">
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

      <section className="my-evaluations-profile">
        <CollaboratorIdentity colaborador={usuarioAtual} variant="standard" />
        <div className="my-evaluations-summary">
          <strong>{avaliacoesConcluidas.length}</strong>
          <span>{avaliacoesConcluidas.length === 1 ? "avaliação concluída" : "avaliações concluídas"}</span>
        </div>
      </section>

      {historico.length === 0 ? (
        <section className="evaluation-empty">
          <h2>Nenhuma avaliação concluída disponível</h2>
          <p>
            Quando um ciclo for concluído, sua avaliação ficará disponível
            aqui para consulta.
          </p>
        </section>
      ) : (
        <section className="evaluation-history my-evaluations-history">
          <div className="evaluation-section-heading">
            <div>
              <span className="evaluation-eyebrow">Histórico</span>
              <h2>Avaliações concluídas</h2>
            </div>
          </div>

          <div className="evaluation-history-grid">
            {historico.map((item) => item.tipo === "CANCELADO" ? (
              <article className="my-evaluations-history-card" key={`ciclo-cancelado-${item.cicloCancelado.id}`}>
                <div className="my-evaluations-history-card__main">
                  <div className="my-evaluations-history-card__cycle">
                    <span className="evaluation-cycle-label">{item.ano} • Ciclo {item.ciclo}</span>
                    <span className="my-evaluations-history-card__status is-historical">Cancelado</span>
                  </div>
                  <p>Ciclo cancelado pela gerência.</p>
                </div>
              </article>
            ) : (
              <article
                className="my-evaluations-history-card score-semantic"
                style={estiloNota(item.feedback.notaMedia)}
                key={item.feedback.id}
              >
                <div className="my-evaluations-history-card__main">
                  <div className="my-evaluations-history-card__cycle">
                    <span className="evaluation-cycle-label">
                      {item.ano} • Ciclo {item.ciclo}
                    </span>
                    <span className="my-evaluations-history-card__status">
                      Concluída
                    </span>
                  </div>

                  <div className="my-evaluations-history-card__score">
                    <strong>{formatarNotaAvaliacao(item.feedback.notaMedia)}</strong>
                    <div>
                      <span>Nota final</span>
                      <small>{labelNota(item.feedback.notaMedia)}</small>
                    </div>
                  </div>
                </div>

                <button
                  type="button"
                  className="evaluation-btn evaluation-btn--primary"
                  onClick={() =>
                    navigate(`/minha-avaliacao/${item.feedback.id}`)
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
