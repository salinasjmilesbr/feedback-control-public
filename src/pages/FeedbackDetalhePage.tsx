import { type CSSProperties } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useEffect, useState } from "react";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { EvaluationResource } from "../authorization/ResourceContext";
import { can } from "../authorization/authorizationPolicy";
import AccessRestrictedState from "../components/AccessRestrictedState";
import CriterionIcon from "../components/CriterionIcon";
import CollaboratorIdentity from "../components/CollaboratorIdentity";
import RoleExpectationsCard from "../components/RoleExpectationsCard";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { useAuth } from "../auth/AuthContext";
import { cancelarAvaliacao } from "../services/cancelamentoAvaliacaoService";
import { reabrirAvaliacao } from "../services/reaberturaAvaliacaoService";
import { carregarPainelSoberano } from "../services/acessoAvaliacoesSoberanas";
import { ehAvaliacaoNova } from "../services/origemAvaliacaoTela";
import type { PainelParticipante } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import type { Colaborador } from "../types/Colaborador";
import { getCiclosAvaliacao } from "../services/cicloAvaliacaoStorage";
import {
  getColaboradorByMatricula,
  getColaboradores,
} from "../services/colaboradorStorage";
import {
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import {
  formatarNotaAvaliacao,
  getTextoNotaAvaliacao,
  possuiNotaAvaliacao,
} from "../services/apresentacaoNota";
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
  const { organizacaoAtivaId } = useAuth();
  const [versao, setVersao] = useState(0);
  const [processando, setProcessando] = useState(false);
  const [erroAcao, setErroAcao] = useState("");
  // Origem POSTGRES: a avaliação nova NÃO existe no acervo legado. Este estado
  // carrega a leitura soberana (painel do próprio participante) — sem fallback
  // local e sem depender de registro legado.
  const [painelSoberano, setPainelSoberano] = useState<PainelParticipante | null>(
    null
  );
  const [erroLeitura, setErroLeitura] = useState("");
  void versao;
  const matricula = Number(id);
  const colaborador = Number.isFinite(matricula)
    ? getColaboradorByMatricula(matricula)
    : undefined;

  // A origem é decidida pela EVIDÊNCIA de cutover (nunca pelo formato do id).
  const avaliacaoNova = ehAvaliacaoNova(feedbackId);
  // O carregamento já começa no estado correto (derivado), sem `setState` em
  // efeito: a leitura soberana termina em callback assíncrono.
  const [carregandoNova, setCarregandoNova] = useState(avaliacaoNova);

  useEffect(() => {
    if (!avaliacaoNova) return;
    let ativo = true;

    void (async () => {
      const resultado = await carregarPainelSoberano({
        organizationId: organizacaoAtivaId ?? "",
        evaluationId: feedbackId ?? "",
      });
      if (!ativo) return;

      setCarregandoNova(false);
      if (!resultado.ok || !resultado.data) {
        setErroLeitura(
          resultado.erro ?? "Avaliação não encontrada para o seu acesso."
        );
        return;
      }
      setPainelSoberano(resultado.data);
    })();

    return () => {
      ativo = false;
    };
  }, [avaliacaoNova, feedbackId, organizacaoAtivaId]);

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

  if (carregandoNova) {
    return (
      <main className="virtus-page">
        <section className="evaluation-empty" role="status" aria-live="polite">
          <h1>Carregando a avaliação…</h1>
        </section>
      </main>
    );
  }

  if (erroLeitura) {
    return (
      <main className="virtus-page">
        <section className="evaluation-empty">
          <h1>Avaliação indisponível</h1>
          <p>{erroLeitura}</p>
          <button
            className="evaluation-btn evaluation-btn--secondary"
            onClick={() => navigate(`/colaborador/${colaborador.matricula}`)}
          >
            ← Voltar
          </button>
        </section>
      </main>
    );
  }

  // Avaliação NOVA: a fonte é o PostgreSQL (nenhum registro legado é exigido).
  if (avaliacaoNova) {
    if (!painelSoberano) {
      return (
        <main className="virtus-page">
          <section className="evaluation-empty">
            <h1>Avaliação não encontrada</h1>
            <button
              className="evaluation-btn evaluation-btn--secondary"
              onClick={() => navigate(`/colaborador/${colaborador.matricula}`)}
            >
              ← Voltar
            </button>
          </section>
        </main>
      );
    }

    return (
      <VistaAvaliacaoSoberana
        painel={painelSoberano}
        colaborador={colaborador}
        processando={processando}
        erroAcao={erroAcao}
        onVoltar={() => navigate(`/colaborador/${colaborador.matricula}`)}
        onEditar={() =>
          navigate(
            `/colaborador/${colaborador.matricula}/feedback/${painelSoberano.evaluationId}/editar`
          )
        }
        onCancelar={() => {
          void executarCancelamentoSoberano();
        }}
        onReabrir={() => {
          void executarReaberturaSoberana();
        }}
      />
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
    if (!possuiNotaAvaliacao(valor)) {
      return {
        "--score-color": "#655d69",
        "--score-bg": "#f4f1f5",
        "--score-border": "#d8d2dc",
      } as CSSProperties;
    }
    const faixa = getItemEscalaPorNota(valor, escala);
    return {
      "--score-color": faixa.cor,
      "--score-bg": faixa.corFundo,
      "--score-border": `${faixa.cor}44`,
    } as CSSProperties;
  }

  function labelNota(valor: number) {
    return getTextoNotaAvaliacao(valor, escala);
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
    void executarCancelamento();
  }

  function handleReabrirAvaliacao() {
    void executarReabertura();
  }

  async function executarCancelamento() {
    const motivo = window.prompt("Informe o motivo do cancelamento:");
    if (motivo === null) return;

    setErroAcao("");
    setProcessando(true);
    try {
      // Soberano: a autorização e o efeito são decididos/executados server-side.
      const resultado = await cancelarAvaliacao(
        feedback!.id,
        motivo,
        organizacaoAtivaId ?? ""
      );
      if (!resultado.ok) {
        setErroAcao(resultado.erro ?? "Não foi possível cancelar a avaliação.");
        return;
      }
      setVersao((atual) => atual + 1);
      alert("Avaliação cancelada com sucesso.");
    } catch (error) {
      setErroAcao(
        error instanceof Error
          ? error.message
          : "Não foi possível cancelar a avaliação."
      );
    } finally {
      setProcessando(false);
    }
  }

  async function executarReabertura() {
    const motivo = window.prompt("Informe o motivo da reabertura:");
    if (motivo === null) return;

    setErroAcao("");
    setProcessando(true);
    try {
      // Soberano: a autorização e o efeito são decididos/executados server-side.
      const resultado = await reabrirAvaliacao(
        feedback!.id,
        motivo,
        organizacaoAtivaId ?? ""
      );
      if (!resultado.ok) {
        setErroAcao(resultado.erro ?? "Não foi possível reabrir a avaliação.");
        return;
      }
      setVersao((atual) => atual + 1);
      alert("Avaliação reaberta com sucesso.");
    } catch (error) {
      setErroAcao(
        error instanceof Error
          ? error.message
          : "Não foi possível reabrir a avaliação."
      );
    } finally {
      setProcessando(false);
    }
  }

  /**
   * Cancelamento/reabertura da avaliação NOVA. A origem já é soberana: o
   * serviço envia a intenção e o Policy Engine decide server-side. Nada é
   * gravado localmente e não há fallback para o acervo legado.
   */
  async function executarCancelamentoSoberano() {
    const motivo = window.prompt("Informe o motivo do cancelamento:");
    if (motivo === null) return;

    setErroAcao("");
    setProcessando(true);
    try {
      const resultado = await cancelarAvaliacao(
        painelSoberano!.evaluationId,
        motivo,
        organizacaoAtivaId ?? ""
      );
      if (!resultado.ok) {
        setErroAcao(resultado.erro ?? "Não foi possível cancelar a avaliação.");
        return;
      }
      // Recarrega o estado REAL do banco (nunca uma projeção local).
      await recarregarPainelSoberano();
      alert("Avaliação cancelada com sucesso.");
    } catch (error) {
      setErroAcao(
        error instanceof Error
          ? error.message
          : "Não foi possível cancelar a avaliação."
      );
    } finally {
      setProcessando(false);
    }
  }

  async function executarReaberturaSoberana() {
    const motivo = window.prompt("Informe o motivo da reabertura:");
    if (motivo === null) return;

    setErroAcao("");
    setProcessando(true);
    try {
      const resultado = await reabrirAvaliacao(
        painelSoberano!.evaluationId,
        motivo,
        organizacaoAtivaId ?? ""
      );
      if (!resultado.ok) {
        setErroAcao(resultado.erro ?? "Não foi possível reabrir a avaliação.");
        return;
      }
      await recarregarPainelSoberano();
      alert("Avaliação reaberta com sucesso.");
    } catch (error) {
      setErroAcao(
        error instanceof Error
          ? error.message
          : "Não foi possível reabrir a avaliação."
      );
    } finally {
      setProcessando(false);
    }
  }

  async function recarregarPainelSoberano() {
    const resultado = await carregarPainelSoberano({
      organizationId: organizacaoAtivaId ?? "",
      evaluationId: feedbackId ?? "",
    });
    if (resultado.ok && resultado.data) setPainelSoberano(resultado.data);
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
              disabled={processando}
            >
              Reabrir avaliação
            </button>
          )}
          {podeCancelarAvaliacao && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--secondary"
              onClick={handleCancelarAvaliacao}
              disabled={processando}
            >
              Cancelar avaliação
            </button>
          )}
          {podeEditarAvaliacao && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--primary"
              onClick={() => navigate(`/colaborador/${colaborador.matricula}/feedback/${feedback.id}/editar`)}
              disabled={processando}
            >
              Editar avaliação
            </button>
          )}
        </div>
      </section>

      {processando && (
        <section className="evaluation-alert" role="status" aria-live="polite">
          Processando a operação no servidor…
        </section>
      )}

      {erroAcao && (
        <section className="evaluation-alert evaluation-alert--warning" role="alert">
          <strong>Operação não concluída.</strong>
          <p>{erroAcao}</p>
        </section>
      )}

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
          <strong>{formatarNotaAvaliacao(feedback.notaMedia)}</strong>
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
                    <span>Nota final</span><strong>{formatarNotaAvaliacao(criterio.nota)}</strong><small>{labelNota(criterio.nota)}</small>
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
                        <div><span>Gerente</span><strong>{formatarNotaAvaliacao(subcriterio.notaGerente)}</strong></div>
                        {colaborador.funcao === "ANALISTA" && (
                          <>
                            <div><span>Coordenador</span><strong>{formatarNotaAvaliacao(subcriterio.notaCoordenador)}</strong></div>
                            <div>
                              <span>Colegiado</span>
                              <strong>{formatarNotaAvaliacao(subcriterio.notaColegiado)}</strong>
                              {(subcriterio.votosColegiado?.length ?? 0) > 0 && (
                                <div className="admin-evaluation-collegiate-votes">
                                  {subcriterio.votosColegiado!.map((voto) => (
                                    <small key={voto.avaliadorMatricula}>{voto.avaliadorNome}: <b>{formatarNotaAvaliacao(voto.nota)}</b></small>
                                  ))}
                                </div>
                              )}
                            </div>
                          </>
                        )}
                      </div>

                      <div className="evaluation-subcriterion-average score-semantic" style={estiloNota(subcriterio.notaFinal)}>
                        <small>Média</small><strong>{formatarNotaAvaliacao(subcriterio.notaFinal)}</strong><span>{labelNota(subcriterio.notaFinal)}</span>
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

/**
 * F5-06 (Issue #103) — VISTA SOBERANA da avaliação NOVA.
 *
 * Esta avaliação existe EXCLUSIVAMENTE no PostgreSQL: não há registro legado e
 * a tela NÃO depende de nenhum. A leitura vem do painel do próprio participante
 * (server-side) e mostra apenas o que o ator tem direito a ver: estado real,
 * papéis, catálogo congelado e as notas/comentários da PRÓPRIA ocorrência.
 * Voto ou nota individual de terceiro nunca é solicitado nem exibido (D20).
 */
function VistaAvaliacaoSoberana({
  painel,
  colaborador,
  processando,
  erroAcao,
  onVoltar,
  onEditar,
  onCancelar,
  onReabrir,
}: {
  readonly painel: PainelParticipante;
  readonly colaborador: Colaborador;
  readonly processando: boolean;
  readonly erroAcao: string;
  readonly onVoltar: () => void;
  readonly onEditar: () => void;
  readonly onCancelar: () => void;
  readonly onReabrir: () => void;
}) {
  const editavel =
    painel.status === "RASCUNHO" || painel.status === "PRONTA_PARA_FEEDBACK";
  const notaDaOcorrencia =
    painel.minhasNotas.length > 0
      ? painel.minhasNotas.reduce((soma, item) => soma + item.nota, 0) /
        painel.minhasNotas.length
      : 0;

  return (
    <main className="virtus-page evaluation-detail-page admin-evaluation-detail">
      <section className="evaluation-detail-header">
        <div>
          <button type="button" className="evaluation-back-link" onClick={onVoltar}>
            ← Voltar para o colaborador
          </button>
          <h1>Detalhes da Avaliação</h1>
          <p>
            Avaliação registrada no servidor (PostgreSQL).{" "}
            {painel.cycleAno} • Ciclo {painel.cycleNumero}
          </p>
        </div>

        <div className="evaluation-detail-actions admin-evaluation-actions">
          {painel.status === "CONCLUIDA" && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--secondary"
              onClick={onReabrir}
              disabled={processando}
            >
              Reabrir avaliação
            </button>
          )}
          {painel.status !== "CANCELADA" && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--secondary"
              onClick={onCancelar}
              disabled={processando}
            >
              Cancelar avaliação
            </button>
          )}
          {editavel && (
            <button
              type="button"
              className="evaluation-btn evaluation-btn--primary"
              onClick={onEditar}
              disabled={processando}
            >
              Editar avaliação
            </button>
          )}
        </div>
      </section>

      {processando && (
        <section className="evaluation-alert" role="status" aria-live="polite">
          Processando a operação no servidor…
        </section>
      )}

      {erroAcao && (
        <section className="evaluation-alert evaluation-alert--warning" role="alert">
          <strong>Operação não concluída.</strong>
          <p>{erroAcao}</p>
        </section>
      )}

      <section className="evaluation-detail-summary">
        <CollaboratorIdentity colaborador={colaborador} variant="standard" />
        <div className="evaluation-detail-summary__meta">
          <div>
            <span>Status (servidor)</span>
            <strong>{painel.status}</strong>
          </div>
          <div>
            <span>Seus papéis nesta avaliação</span>
            <strong>{painel.meusPapeis.join(", ") || "—"}</strong>
          </div>
          <div>
            <span>Nota média das notas registradas</span>
            <strong>
              {possuiNotaAvaliacao(notaDaOcorrencia)
                ? formatarNotaAvaliacao(notaDaOcorrencia)
                : "Sem avaliação"}
            </strong>
          </div>
        </div>
      </section>

      <section className="evaluation-detail-section">
        <div className="evaluation-section-heading">
          <div>
            <span className="evaluation-eyebrow">Sua participação</span>
            <h2>Critérios e subcritérios</h2>
          </div>
          <span className="evaluation-muted">
            {painel.minhasNotas.length} nota(s) registrada(s) por você
          </span>
        </div>

        <div className="admin-evaluation-final__grid">
          {painel.criterios.map((criterio) => {
            const subcriterios = painel.subcriterios.filter(
              (item) => item.criterionCode === criterio.code
            );
            return (
              <div key={criterio.criterionId}>
                <strong>{criterio.name}</strong>
                <ul>
                  {subcriterios.length === 0 && <li>Sem subcritérios.</li>}
                  {subcriterios.map((subcriterio) => {
                    const nota = painel.minhasNotas.find(
                      (item) => item.subcriterionId === subcriterio.subcriterionId
                    );
                    return (
                      <li key={subcriterio.subcriterionId}>
                        {subcriterio.name}:{" "}
                        {nota ? formatarNotaAvaliacao(nota.nota) : "sem nota"}
                      </li>
                    );
                  })}
                </ul>
              </div>
            );
          })}
        </div>
      </section>

      <section className="evaluation-detail-section">
        <div className="evaluation-section-heading">
          <div>
            <span className="evaluation-eyebrow">Conclusão</span>
            <h2>Seu feedback final</h2>
          </div>
        </div>
        <div className="admin-evaluation-final__grid">
          <div>
            <strong>Comentário final registrado</strong>
            <p>
              {painel.meusComentarios.find((item) => item.escopo === "FINAL")
                ?.texto || "Sem comentário final registrado."}
            </p>
          </div>
        </div>
      </section>
    </main>
  );
}

export default FeedbackDetalhePage;

