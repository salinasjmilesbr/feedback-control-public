import { useState, type CSSProperties, type ReactNode } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";
import { exportarAvaliacaoPdf } from "../services/exportarAvaliacaoPdf";
import { getObservacoesComunicadasByCiclo } from "../services/observacaoStorage";
import {
  formatarPeriodoCiclo,
  getCiclosAvaliacao,
} from "../services/cicloAvaliacaoStorage";
import { getColaboradores } from "../services/colaboradorStorage";
import { getMetasDoColaboradorNoCiclo } from "../services/metaStorage";
import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import "../styles/avaliacoes.css";

function IconSpark() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m12 3 1.45 4.55L18 9l-4.55 1.45L12 15l-1.45-4.55L6 9l4.55-1.45L12 3Z" />
      <path d="m18 15 .85 2.15L21 18l-2.15.85L18 21l-.85-2.15L15 18l2.15-.85L18 15Z" />
    </svg>
  );
}

function IconPeople() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="9" cy="8" r="3" />
      <path d="M3.5 19c.6-3.4 2.5-5.2 5.5-5.2s4.9 1.8 5.5 5.2" />
      <circle cx="17" cy="9" r="2.2" />
      <path d="M15.7 14.2c2.9-.4 4.6 1 5 3.8" />
    </svg>
  );
}

function IconChart() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />
    </svg>
  );
}

function IconChat() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M4 5.5h16v11H9l-5 4v-15Z" />
      <path d="M8 10h8M8 13h5" />
    </svg>
  );
}

function IconTarget() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="8" />
      <circle cx="12" cy="12" r="4" />
      <circle cx="12" cy="12" r="1" />
    </svg>
  );
}

function IconBook() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M5 4.5h9.5A2.5 2.5 0 0 1 17 7v13H7.5A2.5 2.5 0 0 1 5 17.5v-13Z" />
      <path d="M17 7h2a2 2 0 0 1 2 2v11h-4M8 8h6M8 12h6" />
    </svg>
  );
}

function IconShield() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 3 20 6v5c0 5.2-2.8 8.5-8 10-5.2-1.5-8-4.8-8-10V6l8-3Z" />
      <path d="m8.5 12 2.2 2.2 4.8-5" />
    </svg>
  );
}

function IconBolt() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m13 2-7 11h6l-1 9 7-12h-6l1-8Z" />
    </svg>
  );
}

const criterioIcons: ReactNode[] = [
  <IconSpark />,
  <IconPeople />,
  <IconChart />,
  <IconChat />,
  <IconTarget />,
  <IconBook />,
  <IconShield />,
  <IconBolt />,
];

function MinhaAvaliacaoDetalhePage() {
  const navigate = useNavigate();
  const { feedbackId } = useParams();
  const { usuarioAtual } = useUsuarioAtual();
  const [mostrarRegua, setMostrarRegua] = useState(false);

  if (!usuarioAtual) {
    return (
      <main className="virtus-page">
        <section className="evaluation-empty">
          <h1>Usuário atual não definido</h1>
        </section>
      </main>
    );
  }

  const feedback = getFeedbacksByColaborador(
    usuarioAtual.matricula
  ).find(
    (item) =>
      item.id === feedbackId &&
      item.status === "CONCLUIDA"
  );

  if (!feedback) {
    return (
      <main className="virtus-page">
        <section className="evaluation-empty">
          <h1>Avaliação não disponível</h1>
          <p>
            Somente avaliações concluídas do próprio colaborador podem ser
            consultadas nesta área.
          </p>
          <button
            type="button"
            className="evaluation-btn evaluation-btn--secondary"
            onClick={() => navigate("/minha-avaliacao")}
          >
            ← Voltar
          </button>
        </section>
      </main>
    );
  }

  const criterios = feedback.criteriosDetalhados ?? [];

  const observacoesComunicadas = getObservacoesComunicadasByCiclo(
    usuarioAtual.matricula,
    feedback.ano,
    feedback.ciclo
  );

  const cicloDaAvaliacao = getCiclosAvaliacao().find(
    (ciclo) =>
      ciclo.ano === feedback.ano &&
      ciclo.ciclo === feedback.ciclo
  );

  const metasDoCiclo = cicloDaAvaliacao
    ? getMetasDoColaboradorNoCiclo(
        usuarioAtual.matricula,
        cicloDaAvaliacao.id
      )
    : [];

  const metasNegocio = metasDoCiclo.filter(
    (meta) => meta.tipo === "NEGOCIO_PROJETO"
  );

  const metasIndividuais = metasDoCiclo.filter(
    (meta) => meta.tipo === "INDIVIDUAL"
  );

  const temConclusao = Boolean(
    feedback.feedbackFinalGerente ||
      feedback.feedbackFinalCoordenador
  );

  const colaboradores = getColaboradores();

  const gestorDireto = usuarioAtual.gestorDiretoMatricula
    ? colaboradores.find(
        (item) =>
          item.matricula === usuarioAtual.gestorDiretoMatricula
      )
    : undefined;

  const coordenadorAvaliador =
    gestorDireto?.funcao === "COORDENADOR"
      ? gestorDireto
      : undefined;

  const gerenteAvaliador =
    gestorDireto?.funcao === "GERENTE"
      ? gestorDireto
      : coordenadorAvaliador?.gestorDiretoMatricula
      ? colaboradores.find(
          (item) =>
            item.matricula ===
            coordenadorAvaliador.gestorDiretoMatricula
        )
      : undefined;

  const avaliacoesHistorico = getFeedbacksByColaborador(
    usuarioAtual.matricula
  )
    .filter((item) => item.status === "CONCLUIDA")
    .sort((a, b) => b.ano - a.ano || b.ciclo - a.ciclo);

  const periodoCiclo = cicloDaAvaliacao
    ? formatarPeriodoCiclo(
        cicloDaAvaliacao.dataInicio,
        cicloDaAvaliacao.dataFim
      )
    : undefined;

  const dataConclusao =
    feedback.dataConclusao ??
    feedback.dataUltimaAtualizacao ??
    feedback.data;

  function formatarData(data?: string) {
    if (!data) return "—";

    const valor = new Date(data);
    if (Number.isNaN(valor.getTime())) return "—";

    return valor.toLocaleDateString("pt-BR");
  }

  function iniciais(nome: string) {
    return nome
      .split(" ")
      .filter(Boolean)
      .slice(0, 2)
      .map((parte) => parte[0])
      .join("")
      .toUpperCase();
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

  function labelStatusMeta(status: string) {
    if (status === "ATINGIDA") return "Atingida";
    if (status === "NAO_ATINGIDA") return "Não atingida";
    return "Pendente / Não finalizada";
  }

  return (
    <main className="virtus-page evaluation-detail-page">
      <section className="evaluation-detail-header">
        <div>
          <button
            type="button"
            className="evaluation-back-link"
            onClick={() => navigate("/minha-avaliacao")}
          >
            ← Voltar para minhas avaliações
          </button>

          <h1>Minha Avaliação</h1>
        </div>

        <div className="evaluation-detail-actions">
          <button
            type="button"
            className="evaluation-btn evaluation-btn--secondary"
            onClick={() => setMostrarRegua(true)}
          >
            Régua de notas
          </button>

          <button
            type="button"
            className="evaluation-btn evaluation-btn--primary"
            onClick={() => exportarAvaliacaoPdf(usuarioAtual, feedback)}
          >
            Exportar PDF
          </button>
        </div>
      </section>

      {feedback.encerradaComPendencias && (
        <section className="evaluation-alert evaluation-alert--warning">
          <strong>Avaliação parcialmente concluída.</strong>
          <p>
            O ciclo foi encerrado com notas pendentes. As médias consideram
            somente as avaliações efetivamente realizadas.
          </p>
          {(feedback.pendenciasEncerramento?.length ?? 0) > 0 && (
            <ul>
              {feedback.pendenciasEncerramento!.map((pendencia) => (
                <li key={pendencia}>{pendencia}</li>
              ))}
            </ul>
          )}
        </section>
      )}

      <section className="evaluation-score-card" id="resumo">
        <div
          className="evaluation-score-primary score-semantic evaluation-score-primary--semantic"
          style={estiloNota(feedback.notaMedia)}
        >
          <span>Resultado do ciclo</span>
          <strong>{formatarNota(feedback.notaMedia)}</strong>
          <small>{labelNota(feedback.notaMedia)}</small>
        </div>

        <div className="evaluation-score-divider" />

        <div className="evaluation-score-card__meta">
          <div>
            <span className="evaluation-meta-icon">▣</span>
            <small>Ano da avaliação</small>
            <strong>{feedback.ano}</strong>
            <p>{periodoCiclo ? `Período: ${periodoCiclo}` : "Período não informado"}</p>
          </div>
          <div>
            <span className="evaluation-meta-icon">◉</span>
            <small>Ciclo</small>
            <strong>{feedback.ciclo}</strong>
            <p>{feedback.ciclo === 1 ? "Primeiro ciclo do ano" : `${feedback.ciclo}º ciclo do ano`}</p>
          </div>
          <div>
            <span className="evaluation-meta-icon">◇</span>
            <small>Critérios avaliados</small>
            <strong>{criterios.length}</strong>
            <p>Critérios com avaliação</p>
          </div>
        </div>
      </section>

      <nav className="evaluation-anchor-nav" aria-label="Seções da avaliação">
        <a href="#resumo" className="is-primary">
          <span>☷</span>
          Resumo
        </a>
        <a href="#criterios">
          <span>☆</span>
          Critérios
        </a>
        {metasDoCiclo.length > 0 && (
          <a href="#metas">
            <span>◎</span>
            Metas do ciclo
          </a>
        )}
        {observacoesComunicadas.length > 0 && (
          <a href="#observacoes">
            <span>◌</span>
            Observações
          </a>
        )}
        {temConclusao && (
          <a href="#conclusao">
            <span>⚑</span>
            Conclusão
          </a>
        )}
      </nav>

      <section className="evaluation-dashboard-overview">
        <aside className="evaluation-history-panel">
          <div className="evaluation-mini-heading">
            <span className="evaluation-mini-heading__icon">↶</span>
            <strong>Histórico de avaliações</strong>
          </div>

          <div className="evaluation-history-compact-list">
            {avaliacoesHistorico.slice(0, 3).map((item) => (
              <article
                key={item.id}
                className={`evaluation-history-compact-card ${
                  item.id === feedback.id ? "is-current" : ""
                } score-semantic`}
                style={estiloNota(item.notaMedia)}
              >
                <div className="evaluation-history-compact-card__top">
                  <strong>
                    {item.ano} • Ciclo {item.ciclo}
                  </strong>
                  {item.id === feedback.id && <span>Atual</span>}
                </div>

                <div className="evaluation-history-compact-card__score">
                  {formatarNota(item.notaMedia)}
                </div>

                <div className="evaluation-history-compact-card__footer">
                  <span>Nota final</span>
                  {item.id !== feedback.id && (
                    <button
                      type="button"
                      onClick={() =>
                        navigate(`/minha-avaliacao/${item.id}`)
                      }
                    >
                      Visualizar
                    </button>
                  )}
                </div>
              </article>
            ))}
          </div>

          {avaliacoesHistorico.length > 3 && (
            <button
              type="button"
              className="evaluation-history-more"
              onClick={() => navigate("/minha-avaliacao")}
            >
              Ver todas as avaliações →
            </button>
          )}
        </aside>

        <div className="evaluation-overview-main">
          <section className="evaluation-summary-panel">
            <div className="evaluation-mini-heading">
              <span className="evaluation-mini-heading__icon">▤</span>
              <div>
                <strong>Resumo da avaliação</strong>
                <small>
                  Visão consolidada do ciclo selecionado.
                </small>
              </div>
            </div>

            <div className="evaluation-summary-metrics">
              <div
                className="score-semantic"
                style={estiloNota(feedback.notaMedia)}
              >
                <span className="evaluation-summary-metric__icon is-purple">☆</span>
                <div>
                  <small>Nota final</small>
                  <strong>{formatarNota(feedback.notaMedia)} / 5</strong>
                </div>
              </div>

              <div>
                <span className="evaluation-summary-metric__icon is-blue">▥</span>
                <div>
                  <small>Média geral</small>
                  <strong>{formatarNota(feedback.notaMedia)}</strong>
                </div>
              </div>

              <div>
                <span className="evaluation-summary-metric__icon is-green">✓</span>
                <div>
                  <small>Critérios concluídos</small>
                  <strong>{criterios.length} / {criterios.length}</strong>
                </div>
              </div>

              <div>
                <span className="evaluation-summary-metric__icon is-red">▣</span>
                <div>
                  <small>Ciclo concluído em</small>
                  <strong>{formatarData(dataConclusao)}</strong>
                </div>
              </div>
            </div>
          </section>

          <section className="evaluation-evaluators-panel">
            <div className="evaluation-mini-heading evaluation-mini-heading--evaluators">
              <span className="evaluation-mini-heading__icon">□</span>
              <div>
                <strong>Feedbacks recebidos</strong>
                <small>Avaliadores responsáveis neste ciclo.</small>
              </div>
            </div>

            <div className="evaluation-evaluator-grid">
              {gerenteAvaliador && (
                <article className="evaluation-evaluator-card is-manager">
                  <small>Avaliador (Gerente)</small>
                  <div>
                    <span>{iniciais(gerenteAvaliador.nome)}</span>
                    <strong>{gerenteAvaliador.nome}</strong>
                  </div>
                  <p>
                    {feedback.feedbackFinalGerente
                      ? "Feedback final registrado"
                      : "Avaliação concluída"}
                  </p>
                </article>
              )}

              {usuarioAtual.funcao === "ANALISTA" &&
                coordenadorAvaliador && (
                  <article className="evaluation-evaluator-card is-coordinator">
                    <small>Avaliador (Coordenador)</small>
                    <div>
                      <span>{iniciais(coordenadorAvaliador.nome)}</span>
                      <strong>{coordenadorAvaliador.nome}</strong>
                    </div>
                    <p>
                      {feedback.feedbackFinalCoordenador
                        ? "Feedback final registrado"
                        : "Avaliação concluída"}
                    </p>
                  </article>
                )}
            </div>
          </section>
        </div>
      </section>

      <section className="evaluation-criteria" id="criterios">
        <div className="evaluation-section-heading">
          <div>
            <span className="evaluation-eyebrow">Competências</span>
            <h2>Critérios avaliados</h2>
          </div>
        </div>

        <div className="evaluation-criteria-list">
          {criterios.map((criterio, criterioIndex) => {
            const criterioParcial =
              feedback.encerradaComPendencias &&
              criterio.subcriterios.some((subcriterio) =>
                usuarioAtual.funcao === "ANALISTA"
                  ? subcriterio.notaGerente <= 0 ||
                    subcriterio.notaCoordenador <= 0 ||
                    subcriterio.notaColegiado <= 0
                  : subcriterio.notaGerente <= 0
              );

            return (
              <article
                key={criterio.criterioId}
                className="evaluation-criterion-card evaluation-criterion-card--matrix"
              >
                <div className="evaluation-criterion-card__accent" />

                <div className="evaluation-criterion-card__header">
                  <div className="evaluation-criterion-heading">
                    <span className="evaluation-criterion-icon">
                      {criterioIcons[
                        criterioIndex % criterioIcons.length
                      ]}
                    </span>

                    <div>
                      <div className="evaluation-criterion-kicker">
                        Competência {criterioIndex + 1}
                      </div>
                      <h3>{criterio.criterioNome}</h3>
                      <span className="evaluation-criterion-count">
                        {criterio.subcriterios.length}{" "}
                        {criterio.subcriterios.length === 1
                          ? "subcritério"
                          : "subcritérios"}
                      </span>
                      {criterioParcial && (
                        <span className="evaluation-partial-badge">
                          Avaliação parcialmente concluída
                        </span>
                      )}
                    </div>
                  </div>

                  <div
                    className="evaluation-criterion-score evaluation-criterion-score--featured score-semantic"
                    style={estiloNota(criterio.nota)}
                  >
                    <span>Nota final</span>
                    <strong>{formatarNota(criterio.nota)}</strong>
                    <small>{labelNota(criterio.nota)}</small>
                  </div>
                </div>

                <div className="evaluation-subcriteria-matrix">
                  <div className="evaluation-subcriteria-matrix__header">
                    <span>Subcritério</span>
                    <span>Avaliações recebidas</span>
                    <span>Média do subcritério</span>
                  </div>

                  {criterio.subcriterios.map((subcriterio, subIndex) => (
                    <div
                      key={subcriterio.nome}
                      className="evaluation-subcriteria-matrix__row"
                    >
                      <div className="evaluation-subcriterion-name">
                        <span className="evaluation-subcriterion-index">
                          {subIndex + 1}
                        </span>
                        <strong>{subcriterio.nome}</strong>
                      </div>

                      <div className="evaluation-rater-group">
                        <div>
                          <span>Gerente</span>
                          <strong>
                            {subcriterio.notaGerente > 0
                              ? formatarNota(subcriterio.notaGerente)
                              : "—"}
                          </strong>
                        </div>

                        {usuarioAtual.funcao === "ANALISTA" && (
                          <>
                            <div>
                              <span>Coordenador</span>
                              <strong>
                                {subcriterio.notaCoordenador > 0
                                  ? formatarNota(subcriterio.notaCoordenador)
                                  : "—"}
                              </strong>
                            </div>

                            <div>
                              <span>Colegiado</span>
                              <strong>
                                {subcriterio.notaColegiado > 0
                                  ? formatarNota(subcriterio.notaColegiado)
                                  : "—"}
                              </strong>
                            </div>
                          </>
                        )}
                      </div>

                      <div
                        className="evaluation-subcriterion-average score-semantic"
                        style={estiloNota(subcriterio.notaFinal)}
                      >
                        <small>Média</small>
                        <strong>{formatarNota(subcriterio.notaFinal)}</strong>
                        <span>{labelNota(subcriterio.notaFinal)}</span>
                      </div>
                    </div>
                  ))}
                </div>

                {(criterio.observacaoGerente ||
                  criterio.observacaoCoordenador) && (
                  <div className="evaluation-comments">
                    {criterio.observacaoGerente && (
                      <div className="evaluation-comment">
                        <strong>Observação do Gerente</strong>
                        <p>{criterio.observacaoGerente}</p>
                      </div>
                    )}

                    {usuarioAtual.funcao === "ANALISTA" &&
                      criterio.observacaoCoordenador && (
                        <div className="evaluation-comment">
                          <strong>Observação do Coordenador</strong>
                          <p>{criterio.observacaoCoordenador}</p>
                        </div>
                      )}
                  </div>
                )}
              </article>
            );
          })}
        </div>
      </section>

      {metasDoCiclo.length > 0 && (
        <section
          className="evaluation-content-card evaluation-content-card--goals"
          id="metas"
        >
          <div className="evaluation-section-heading">
            <div>
              <span className="evaluation-eyebrow">Resultados</span>
              <h2>Metas do Ciclo</h2>
            </div>
            <span className="evaluation-section-count">
              {metasDoCiclo.length}{" "}
              {metasDoCiclo.length === 1 ? "meta" : "metas"}
            </span>
          </div>

          {[
            {
              titulo: "Metas de Negócio / Projetos",
              metas: metasNegocio,
            },
            {
              titulo: "Metas Individuais",
              metas: metasIndividuais,
            },
          ].map(
            (grupo) =>
              grupo.metas.length > 0 && (
                <div className="evaluation-goal-group" key={grupo.titulo}>
                  <h3>{grupo.titulo}</h3>

                  <div className="evaluation-goal-grid">
                    {grupo.metas.map((meta, indice) => (
                      <article className="evaluation-goal-card" key={meta.id}>
                        <div className="evaluation-goal-accent" />
                        <div className="evaluation-goal-card__header">
                          <strong>
                            {indice + 1}. {meta.descricao}
                          </strong>
                          <span
                            className={`evaluation-goal-status ${
                              meta.status === "ATINGIDA"
                                ? "is-success"
                                : meta.status === "NAO_ATINGIDA"
                                ? "is-danger"
                                : "is-warning"
                            }`}
                          >
                            {labelStatusMeta(meta.status)}
                          </span>
                        </div>

                        <dl>
                          <div>
                            <dt>KPI</dt>
                            <dd>{meta.kpi}</dd>
                          </div>
                          <div>
                            <dt>Valor-alvo</dt>
                            <dd>{meta.valorAlvo}</dd>
                          </div>
                          <div>
                            <dt>Resultado final</dt>
                            <dd>
                              {meta.resultadoFinal?.trim()
                                ? meta.resultadoFinal
                                : "Não informado"}
                            </dd>
                          </div>
                        </dl>
                      </article>
                    ))}
                  </div>
                </div>
              )
          )}
        </section>
      )}

      {observacoesComunicadas.length > 0 && (
        <section
          className="evaluation-content-card evaluation-content-card--observations"
          id="observacoes"
        >
          <div className="evaluation-section-heading">
            <div>
              <span className="evaluation-eyebrow">Histórico</span>
              <h2>Observações do Ciclo</h2>
            </div>
          </div>

          <div className="evaluation-observations">
            {observacoesComunicadas.map((observacao) => (
              <article
                className={`evaluation-observation ${
                  observacao.tipo === "POSITIVA"
                    ? "is-positive"
                    : observacao.tipo === "NEGATIVA"
                    ? "is-negative"
                    : "is-neutral"
                }`}
                key={observacao.id}
              >
                <div className="evaluation-observation__header">
                  <strong className="evaluation-observation__type">
                    <span aria-hidden="true">
                      {observacao.tipo === "POSITIVA"
                        ? "✓"
                        : observacao.tipo === "NEGATIVA"
                        ? "!"
                        : "•"}
                    </span>
                    {observacao.tipo === "POSITIVA"
                      ? "Positiva"
                      : observacao.tipo === "NEGATIVA"
                      ? "Negativa"
                      : "Neutra"}
                  </strong>

                  <span>
                    {new Date(observacao.dataCriacao).toLocaleDateString(
                      "pt-BR"
                    )}
                  </span>
                </div>

                <p>{observacao.texto}</p>
                <small>Registrada por {observacao.autorNome}</small>
              </article>
            ))}
          </div>
        </section>
      )}

      {temConclusao && (
        <section
          className="evaluation-content-card evaluation-conclusion-card"
          id="conclusao"
        >
          <div className="evaluation-conclusion-icon">
            <IconSpark />
          </div>

          <div className="evaluation-section-heading">
            <div>
              <span className="evaluation-eyebrow">Fechamento</span>
              <h2>Feedback Final</h2>
            </div>
          </div>

          <div className="evaluation-feedback-grid">
            {feedback.feedbackFinalGerente && (
              <div className="evaluation-feedback-box">
                <strong>Gerente</strong>
                <p>{feedback.feedbackFinalGerente}</p>
              </div>
            )}

            {usuarioAtual.funcao === "ANALISTA" &&
              feedback.feedbackFinalCoordenador && (
                <div className="evaluation-feedback-box">
                  <strong>Coordenador</strong>
                  <p>{feedback.feedbackFinalCoordenador}</p>
                </div>
              )}
          </div>
        </section>
      )}

      <section className="evaluation-info-note">
        {usuarioAtual.funcao === "ANALISTA"
          ? "Nesta visão aparecem as notas do gerente, coordenador e a média do colegiado, sem revelar os votos individuais."
          : "Nesta visão aparecem apenas as notas, observações e feedbacks do gerente responsável pela avaliação."}
      </section>

      {mostrarRegua && (
        <div
          className="score-scale-modal-backdrop"
          role="presentation"
          onMouseDown={() => setMostrarRegua(false)}
        >
          <section
            className="score-scale-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="score-scale-title"
            onMouseDown={(event) => event.stopPropagation()}
          >
            <div className="score-scale-modal__header">
              <div>
                <span>Modelo de avaliação</span>
                <h2 id="score-scale-title">Régua de notas</h2>
                <p>
                  Referência utilizada para interpretar notas e médias.
                </p>
              </div>

              <button
                type="button"
                onClick={() => setMostrarRegua(false)}
                aria-label="Fechar régua de notas"
              >
                ×
              </button>
            </div>

            <div className="score-scale-modal__list">
              {escalaAvaliacao.map((item) => (
                <article key={item.nota}>
                  <div
                    className="score-scale-modal__score"
                    style={{
                      color: item.cor,
                      backgroundColor: item.corFundo,
                      borderColor: `${item.cor}44`,
                    }}
                  >
                    {item.nota}
                  </div>

                  <div>
                    <strong style={{ color: item.cor }}>
                      {item.significado}
                    </strong>
                    <p>{item.descricao}</p>
                  </div>
                </article>
              ))}
            </div>

            <div className="score-scale-modal__footer">
              Médias decimais são classificadas conforme as faixas definidas
              na configuração da régua de notas.
            </div>
          </section>
        </div>
      )}
    </main>
  );
}

export default MinhaAvaliacaoDetalhePage;

