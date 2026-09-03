import { type CSSProperties } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useState } from "react";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { EvaluationResource } from "../authorization/ResourceContext";
import { can } from "../authorization/authorizationPolicy";
import AccessRestrictedState from "../components/AccessRestrictedState";
import CriterionIcon from "../components/CriterionIcon";
import CollaboratorIdentity from "../components/CollaboratorIdentity";
import RoleExpectationsCard from "../components/RoleExpectationsCard";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { cancelarAvaliacao } from "../services/cancelamentoAvaliacaoService";
import { reabrirAvaliacao } from "../services/reaberturaAvaliacaoService";
import { getCiclosAvaliacao } from "../services/cicloAvaliacaoStorage";
import {
  getColaboradorByMatricula,
  getColaboradores,
} from "../services/colaboradorStorage";
import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";
import "../styles/avaliacoes.css";
import "../styles/feedback-detalhe.css";
import { getStatusAvaliacaoAdministrativa } from "./statusAvaliacaoAdministrativa";

const criterioIcons = Array.from({ length: 8 }, (_, index) => (
  <CriterionIcon index={index} key={index} />
));

function FeedbackDetalhePage() {
  const navigate = useNavigate();
  const { id, feedbackId } = useParams();
  const { usuarioAtual } = useUsuarioAtual();
  const [versao, setVersao] = useState(0);
  void versao;
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

  const colaboradores = getColaboradores();
  const cicloDaAvaliacao = getCiclosAvaliacao().find(
    (item) => item.ano === feedback.ano && item.ciclo === feedback.ciclo
  );
  const authorizationContext: AuthorizationContext | undefined = usuarioAtual
    ? {
        actor: {
          matricula: usuarioAtual.matricula,
          funcao: usuarioAtual.funcao,
          status: usuarioAtual.status,
        },
      }
    : undefined;
  const evaluationResource: EvaluationResource = {
    kind: "evaluation",
    evaluatedCollaborator: colaborador,
    collaborators: colaboradores,
    cycle: cicloDaAvaliacao,
    evaluationStatus: feedback.status,
  };
  const podeConsultarAvaliacao = authorizationContext
    ? can(
        authorizationContext,
        "evaluation.view.admin",
        evaluationResource
      )
    : false;
  const podeCancelarAvaliacao = authorizationContext
    ? can(
        authorizationContext,
        "evaluation.cancel.manager",
        evaluationResource
      )
    : false;
  const podeReabrirAvaliacao = authorizationContext
    ? can(
        authorizationContext,
        "evaluation.reopen.manager",
        evaluationResource
      )
    : false;
  const podeEditarAvaliacao = authorizationContext
    ? can(
        authorizationContext,
        "evaluation.edit.manager",
        evaluationResource
      ) ||
      can(
        authorizationContext,
        "evaluation.edit.coordinator",
        evaluationResource
      ) ||
      can(
        authorizationContext,
        "evaluation.edit.board",
        evaluationResource
      )
    : false;

  if (!podeConsultarAvaliacao) {
    return (
      <AccessRestrictedState message="Você não possui acesso administrativo a esta avaliação." />
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

  const statusExibido = getStatusAvaliacaoAdministrativa(
    feedback.status,
    cicloDaAvaliacao?.status
  );

  function handleCancelarAvaliacao() {
    if (!usuarioAtual) return;
    const motivo = window.prompt("Informe o motivo do cancelamento:");
    if (motivo === null) return;

    try {
      cancelarAvaliacao(feedback!.id, motivo, usuarioAtual);
      setVersao((atual) => atual + 1);
      alert("Avaliação cancelada com sucesso.");
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Não foi possível cancelar a avaliação."
      );
    }
  }

  function handleReabrirAvaliacao() {
    if (!usuarioAtual) return;
    const motivo = window.prompt("Informe o motivo da reabertura:");
    if (motivo === null) return;

    try {
      reabrirAvaliacao(feedback!.id, motivo, usuarioAtual);
      setVersao((atual) => atual + 1);
      alert("Avaliação reaberta com sucesso.");
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Não foi possível reabrir a avaliação."
      );
    }
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
          {podeReabrirAvaliacao && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--secondary"
              onClick={handleReabrirAvaliacao}
            >
              Reabrir avaliação
            </button>
          )}
          {podeCancelarAvaliacao && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--secondary"
              onClick={handleCancelarAvaliacao}
            >
              Cancelar avaliação
            </button>
          )}
          {podeEditarAvaliacao && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--primary"
              onClick={() => navigate(`/colaborador/${colaborador.matricula}/feedback/${feedback.id}/editar`)}
            >
              Editar avaliação
            </button>
          )}
        </div>
      </section>

      {feedback.status === "CANCELADA" && (
        <section className="evaluation-alert evaluation-alert--warning">
          <strong>Avaliação cancelada.</strong>
          <p>{feedback.motivoCancelamento}</p>
          <small>
            Cancelada por {feedback.canceladoPorNome ?? "Autor não identificado"}
            {feedback.dataCancelamento
              ? ` em ${formatarData(feedback.dataCancelamento)}`
              : ""}
          </small>
        </section>
      )}

      {(feedback.reaberturas?.length ?? 0) > 0 && (
        <section className="evaluation-alert evaluation-alert--warning">
          <strong>Histórico de reaberturas</strong>
          <ul>
            {feedback.reaberturas!.map((evento, indice) => (
              <li key={`${evento.data}-${indice}`}>
                {evento.motivo} — {evento.autorNome} em {formatarData(evento.data)}
              </li>
            ))}
          </ul>
        </section>
      )}

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
          <span className={`admin-evaluation-status ${statusExibido.className}`}>
            {statusExibido.label}
          </span>
          <small>Avaliação em {formatarData(feedback.data)}</small>
        </div>
      </section>

      <RoleExpectationsCard
        expectativa={feedback.expectativaCargoSnapshot}
      />

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

