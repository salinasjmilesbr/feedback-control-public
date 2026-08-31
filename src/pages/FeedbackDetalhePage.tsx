import { type CSSProperties, type ReactNode } from "react";
import { useNavigate, useParams } from "react-router-dom";
import CollaboratorIdentity from "../components/CollaboratorIdentity";
import { getColaboradorByMatricula } from "../services/colaboradorStorage";
import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import {
  deleteFeedback,
  getFeedbacksByColaborador,
} from "../services/feedbackStorage";
import "../styles/avaliacoes.css";
import "../styles/feedback-detalhe.css";

function IconSpark() { return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3 1.45 4.55L18 9l-4.55 1.45L12 15l-1.45-4.55L6 9l4.55-1.45L12 3Z" /><path d="m18 15 .85 2.15L21 18l-2.15.85L18 21l-.85-2.15L15 18l2.15-.85L18 15Z" /></svg>; }
function IconPeople() { return <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="9" cy="8" r="3" /><path d="M3.5 19c.6-3.4 2.5-5.2 5.5-5.2s4.9 1.8 5.5 5.2" /><circle cx="17" cy="9" r="2.2" /><path d="M15.7 14.2c2.9-.4 4.6 1 5 3.8" /></svg>; }
function IconChart() { return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2" /></svg>; }
function IconChat() { return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5.5h16v11H9l-5 4v-15Z" /><path d="M8 10h8M8 13h5" /></svg>; }
function IconTarget() { return <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8" /><circle cx="12" cy="12" r="4" /><circle cx="12" cy="12" r="1" /></svg>; }
function IconBook() { return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4.5h9.5A2.5 2.5 0 0 1 17 7v13H7.5A2.5 2.5 0 0 1 5 17.5v-13Z" /><path d="M17 7h2a2 2 0 0 1 2 2v11h-4M8 8h6M8 12h6" /></svg>; }
function IconShield() { return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 20 6v5c0 5.2-2.8 8.5-8 10-5.2-1.5-8-4.8-8-10V6l8-3Z" /><path d="m8.5 12 2.2 2.2 4.8-5" /></svg>; }
function IconBolt() { return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m13 2-7 11h6l-1 9 7-12h-6l1-8Z" /></svg>; }

const criterioIcons: ReactNode[] = [
  <IconSpark />, <IconPeople />, <IconChart />, <IconChat />,
  <IconTarget />, <IconBook />, <IconShield />, <IconBolt />,
];

function FeedbackDetalhePage() {
  const navigate = useNavigate();
  const { id, feedbackId } = useParams();
  const matricula = Number(id);
  const colaborador = Number.isFinite(matricula)
    ? getColaboradorByMatricula(matricula)
    : undefined;

  if (!colaborador) {
    return (
      <main className="virtus-page">
        <section className="evaluation-empty">
          <h1>Colaborador não encontrado</h1>
          <button className="evaluation-btn evaluation-btn--secondary" onClick={() => navigate(-1)}>← Voltar</button>
        </section>
      </main>
    );
  }

  const feedback = getFeedbacksByColaborador(colaborador.matricula)
    .find((item) => item.id === feedbackId);

  if (!feedback) {
    return (
      <main className="virtus-page">
        <section className="evaluation-empty">
          <h1>Avaliação não encontrada</h1>
          <button className="evaluation-btn evaluation-btn--secondary" onClick={() => navigate(`/colaborador/${colaborador.matricula}`)}>← Voltar</button>
        </section>
      </main>
    );
  }

  const criterios = feedback.criteriosDetalhados ?? [];
  const escala = getEscalaAvaliacao();

  function estiloNota(valor: number) {
    const faixa = getItemEscalaPorNota(valor, escala);
    return {
      "--score-color": faixa.cor,
      "--score-bg": faixa.corFundo,
      "--score-border": `${faixa.cor}44`,
    } as CSSProperties;
  }

  function labelNota(valor: number) {
    return getItemEscalaPorNota(valor, escala).significado;
  }


  function formatarData(data?: string) {
    if (!data) return "—";
    const valor = new Date(data);
    return Number.isNaN(valor.getTime()) ? "—" : valor.toLocaleDateString("pt-BR");
  }

  function statusLabel() {
    if (feedback!.status === "CONCLUIDA") return "Concluída";
    if (feedback!.status === "PRONTA_PARA_FEEDBACK") return "Pronta para Feedback";
    return "Rascunho";
  }

  function handleExcluirFeedback() {
    if (!window.confirm("Deseja realmente excluir este feedback?")) return;
    deleteFeedback(feedback!.id);
    alert("Feedback excluído com sucesso.");
    navigate(`/colaborador/${colaborador!.matricula}`);
  }

  const feedbackFinalGerente = feedback.feedbackFinalGerente ?? "";
  const feedbackFinalCoordenador = feedback.feedbackFinalCoordenador ?? "";
  const temFeedbackFinal = Boolean(feedbackFinalGerente || feedbackFinalCoordenador);

  return (
    <main className="virtus-page evaluation-detail-page admin-evaluation-detail">
      <section className="evaluation-detail-header">
        <div>
          <button type="button" className="evaluation-back-link" onClick={() => navigate(`/colaborador/${colaborador.matricula}`)}>
            ← Voltar para o colaborador
          </button>
          <h1>Detalhes da Avaliação</h1>
          <p>Consulta administrativa do resultado e dos registros do ciclo.</p>
        </div>

        <div className="evaluation-detail-actions admin-evaluation-actions">
          <button
            type="button"
            className="evaluation-btn evaluation-btn--secondary admin-evaluation-delete"
            onClick={handleExcluirFeedback}
          >
            Excluir avaliação
          </button>
          <button
            type="button"
            className="evaluation-btn evaluation-btn--primary"
            onClick={() => navigate(`/colaborador/${colaborador.matricula}/feedback/${feedback.id}/editar`)}
          >
            Editar avaliação
          </button>
        </div>
      </section>

      {feedback.encerradaComPendencias && (
        <section className="evaluation-alert evaluation-alert--warning">
          <strong>Avaliação parcialmente concluída.</strong>
          <p>O ciclo foi encerrado com pendências. As médias consideram somente as avaliações efetivamente realizadas.</p>
          {(feedback.pendenciasEncerramento?.length ?? 0) > 0 && (
            <ul>{feedback.pendenciasEncerramento!.map((pendencia) => <li key={pendencia}>{pendencia}</li>)}</ul>
          )}
        </section>
      )}

      <section className="admin-evaluation-profile admin-evaluation-profile--identity">
        <CollaboratorIdentity colaborador={colaborador} variant="standard" />
        <div className="admin-evaluation-profile__context">
          <span className={`admin-evaluation-status is-${feedback.status.toLowerCase()}`}>{statusLabel()}</span>
          <small>Avaliação em {formatarData(feedback.data)}</small>
        </div>
      </section>

      <section className="evaluation-score-card" id="resumo">
        <div className="evaluation-score-primary score-semantic evaluation-score-primary--semantic" style={estiloNota(feedback.notaMedia)}>
          <span>Resultado do ciclo</span>
          <strong>{formatarNota(feedback.notaMedia)}</strong>
          <small>{labelNota(feedback.notaMedia)}</small>
        </div>
        <div className="evaluation-score-divider" />
        <div className="evaluation-score-card__meta">
          <div><small>Ano da avaliação</small><strong>{feedback.ano}</strong><p>Referência anual</p></div>
          <div><small>Ciclo</small><strong>{feedback.ciclo}</strong><p>{feedback.ciclo === 1 ? "Primeiro ciclo do ano" : `${feedback.ciclo}º ciclo do ano`}</p></div>
          <div><small>Critérios avaliados</small><strong>{criterios.length}</strong><p>Competências no ciclo</p></div>
        </div>
      </section>

      <nav className="evaluation-anchor-nav" aria-label="Seções da avaliação">
        <a href="#resumo" className="is-primary">Resumo</a>
        <a href="#criterios">Critérios</a>
        {temFeedbackFinal && <a href="#conclusao">Feedback final</a>}
      </nav>

      <section className="evaluation-criteria" id="criterios">
        <div className="evaluation-section-heading">
          <div><span className="evaluation-eyebrow">Competências</span><h2>Critérios avaliados</h2></div>
        </div>

        {criterios.length === 0 ? (
          <section className="evaluation-empty">
            <p>Esta avaliação foi salva em um modelo anterior e não possui detalhes por critério.</p>
          </section>
        ) : (
          <div className="evaluation-criteria-list">
            {criterios.map((criterio, criterioIndex) => (
              <article key={criterio.criterioId} className="evaluation-criterion-card evaluation-criterion-card--matrix">
                <div className="evaluation-criterion-card__accent" />
                <div className="evaluation-criterion-card__header">
                  <div className="evaluation-criterion-heading">
                    <span className="evaluation-criterion-icon">{criterioIcons[criterioIndex % criterioIcons.length]}</span>
                    <div>
                      <div className="evaluation-criterion-kicker">Competência {criterioIndex + 1}</div>
                      <h3>{criterio.criterioNome}</h3>
                      <span className="evaluation-criterion-count">
                        {criterio.subcriterios.length} {criterio.subcriterios.length === 1 ? "subcritério" : "subcritérios"}
                      </span>
                    </div>
                  </div>
                  <div className="evaluation-criterion-score evaluation-criterion-score--featured score-semantic" style={estiloNota(criterio.nota)}>
                    <span>Nota final</span><strong>{formatarNota(criterio.nota)}</strong><small>{labelNota(criterio.nota)}</small>
                  </div>
                </div>

                <div className="evaluation-subcriteria-matrix">
                  <div className="evaluation-subcriteria-matrix__header">
                    <span>Subcritério</span><span>Avaliações recebidas</span><span>Média do subcritério</span>
                  </div>

                  {criterio.subcriterios.map((subcriterio, subIndex) => (
                    <div key={subcriterio.nome} className="evaluation-subcriteria-matrix__row">
                      <div className="evaluation-subcriterion-name">
                        <span className="evaluation-subcriterion-index">{subIndex + 1}</span>
                        <strong>{subcriterio.nome}</strong>
                      </div>

                      <div className="evaluation-rater-group">
                        <div><span>Gerente</span><strong>{subcriterio.notaGerente > 0 ? formatarNota(subcriterio.notaGerente) : "—"}</strong></div>
                        {colaborador.funcao === "ANALISTA" && (
                          <>
                            <div><span>Coordenador</span><strong>{subcriterio.notaCoordenador > 0 ? formatarNota(subcriterio.notaCoordenador) : "—"}</strong></div>
                            <div>
                              <span>Colegiado</span>
                              <strong>{subcriterio.notaColegiado > 0 ? formatarNota(subcriterio.notaColegiado) : "—"}</strong>
                              {(subcriterio.votosColegiado?.length ?? 0) > 0 && (
                                <div className="admin-evaluation-collegiate-votes">
                                  {subcriterio.votosColegiado!.map((voto) => (
                                    <small key={voto.avaliadorMatricula}>{voto.avaliadorNome}: <b>{formatarNota(voto.nota)}</b></small>
                                  ))}
                                </div>
                              )}
                            </div>
                          </>
                        )}
                      </div>

                      <div className="evaluation-subcriterion-average score-semantic" style={estiloNota(subcriterio.notaFinal)}>
                        <small>Média</small><strong>{formatarNota(subcriterio.notaFinal)}</strong><span>{labelNota(subcriterio.notaFinal)}</span>
                      </div>
                    </div>
                  ))}
                </div>

                {(criterio.observacaoGerente || criterio.observacaoCoordenador) && (
                  <div className="evaluation-comments">
                    {criterio.observacaoGerente && <div className="evaluation-comment"><strong>Observação do Gerente</strong><p>{criterio.observacaoGerente}</p></div>}
                    {colaborador.funcao === "ANALISTA" && criterio.observacaoCoordenador && <div className="evaluation-comment"><strong>Observação do Coordenador</strong><p>{criterio.observacaoCoordenador}</p></div>}
                  </div>
                )}
              </article>
            ))}
          </div>
        )}
      </section>

      <section className="evaluation-content-card admin-evaluation-final" id="conclusao">
        <div className="evaluation-section-heading">
          <div><span className="evaluation-eyebrow">Conclusão</span><h2>Feedback Final</h2></div>
          <span className={`admin-evaluation-final__status ${temFeedbackFinal ? "is-complete" : "is-pending"}`}>
            {temFeedbackFinal ? "Registrado" : "Pendente"}
          </span>
        </div>

        <div className="admin-evaluation-final__grid">
          <div>
            <strong>Feedback Final do Gerente</strong>
            <p>{feedbackFinalGerente || "Sem feedback final registrado."}</p>
          </div>
          {colaborador.funcao === "ANALISTA" && (
            <div>
              <strong>Feedback Final do Coordenador</strong>
              <p>{feedbackFinalCoordenador || "Sem feedback final registrado."}</p>
            </div>
          )}
        </div>
      </section>
    </main>
  );
}

export default FeedbackDetalhePage;

