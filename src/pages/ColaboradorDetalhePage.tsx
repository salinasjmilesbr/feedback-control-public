import { useLayoutEffect, useState, type CSSProperties, type ReactNode } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { can, scopeCollaborators } from "../authorization/authorizationPolicy";
import CollaboratorIdentity from "../components/CollaboratorIdentity";
import CriterionIcon from "../components/CriterionIcon";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";

import ObservacoesColaborador from "../components/ObservacoesColaborador";
import { getColaboradorByMatricula, getColaboradores } from "../services/colaboradorStorage";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";
import { getObservacoesByColaborador } from "../services/observacaoStorage";
import { getHistoricoOrganizacional } from "../services/historicoOrganizacionalStorage";
import type { MovimentacaoOrganizacional } from "../types/HistoricoOrganizacional";
import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import type { Feedback } from "../types/Feedback";
import "../styles/colaborador-detalhe.css";

function Icon({
  children,
  size = 18,
}: {
  children: ReactNode;
  size?: number;
}) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

function IconEdit() {
  return (
    <Icon>
      <path d="M4 20h4l11-11-4-4L4 16v4Z" />
      <path d="m13.5 6.5 4 4" />
    </Icon>
  );
}

function IconPlus() {
  return (
    <Icon>
      <path d="M12 5v14M5 12h14" />
    </Icon>
  );
}

function IconChart() {
  return (
    <Icon>
      <path d="M4 20V11M10 20V6M16 20v-4M22 20H2" />
    </Icon>
  );
}

function IconStar() {
  return (
    <Icon>
      <path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3l-5.6 2.9 1.1-6.2L3 9.6l6.2-.9L12 3Z" />
    </Icon>
  );
}

function IconTrend() {
  return (
    <Icon>
      <path d="m4 17 6-6 4 4 6-8" />
      <path d="M15 7h5v5" />
    </Icon>
  );
}

function IconCheck() {
  return (
    <Icon>
      <circle cx="12" cy="12" r="9" />
      <path d="m8 12 2.7 2.7L16.5 9" />
    </Icon>
  );
}

function IconCalendar() {
  return (
    <Icon>
      <rect x="3" y="5" width="18" height="16" rx="2" />
      <path d="M8 3v4M16 3v4M3 10h18" />
    </Icon>
  );
}

function IconPositive() {
  return (
    <Icon size={20}>
      <path d="M7 10v10H4V10h3ZM7 18h9.5a2 2 0 0 0 1.9-1.4l1.3-4A2 2 0 0 0 17.8 10H14l.7-3.3A2.2 2.2 0 0 0 10.5 5L7 10Z" />
    </Icon>
  );
}

function IconNeutral() {
  return (
    <Icon size={20}>
      <circle cx="12" cy="12" r="9" />
      <path d="M9 10h.01M15 10h.01M9 15h6" />
    </Icon>
  );
}

function IconNegative() {
  return (
    <Icon size={20}>
      <path d="M7 14V4H4v10h3ZM7 6h9.5a2 2 0 0 1 1.9 1.4l1.3 4A2 2 0 0 1 17.8 14H14l.7 3.3a2.2 2.2 0 0 1-4.2 1.7L7 14Z" />
    </Icon>
  );
}

function IconChevron({ aberto }: { aberto: boolean }) {
  return (
    <Icon size={17}>
      <path d={aberto ? "m6 14 6-6 6 6" : "m6 10 6 6 6-6"} />
    </Icon>
  );
}

const criterioSiglas = [
  "DT",
  "PR",
  "CO",
  "TE",
  "PI",
  "AF",
  "CR",
  "DP",
] as const;

const criterioNomePorSigla: Record<(typeof criterioSiglas)[number], string> = {
  DT: "Desempenho técnico",
  PR: "Produtividade",
  CO: "Comunicação",
  TE: "Trabalho em equipe",
  PI: "Proatividade e iniciativa",
  AF: "Adaptação e flexibilidade",
  CR: "Comprometimento e responsabilidade",
  DP: "Desenvolvimento profissional",
};

const criterioIconPorSigla: Record<(typeof criterioSiglas)[number], ReactNode> = {
  DT: <CriterionIcon index={0} />,
  PR: <CriterionIcon index={1} />,
  CO: <CriterionIcon index={2} />,
  TE: <CriterionIcon index={3} />,
  PI: <CriterionIcon index={4} />,
  AF: <CriterionIcon index={5} />,
  CR: <CriterionIcon index={6} />,
  DP: <CriterionIcon index={7} />,
};

function normalizarTexto(valor: string) {
  return valor
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function calcularPercentual(parte: number, total: number) {
  if (total === 0) return 0;
  return Math.round((parte / total) * 100);
}

function calcularPreenchimentoFeedback(feedback: Feedback) {
  const subcriterios =
    feedback.criteriosDetalhados?.flatMap((criterio) => criterio.subcriterios) ?? [];

  const totalSubcriterios = subcriterios.length;
  const gerente = subcriterios.filter((item) => item.notaGerente > 0).length;
  const coordenador = subcriterios.filter(
    (item) => item.notaCoordenador > 0
  ).length;
  const colegiado = subcriterios.filter((item) => item.notaColegiado > 0).length;

  return {
    geral: calcularPercentual(
      gerente + coordenador + colegiado,
      totalSubcriterios * 3
    ),
    gerente: calcularPercentual(gerente, totalSubcriterios),
    coordenador: calcularPercentual(coordenador, totalSubcriterios),
    colegiado: calcularPercentual(colegiado, totalSubcriterios),
  };
}

function labelStatusFeedback(status: Feedback["status"]) {
  if (status === "CONCLUIDA") return "Concluída";
  if (status === "PRONTA_PARA_FEEDBACK") return "Pronta para feedback";
  return "Em andamento";
}

function classeStatusFeedback(status: Feedback["status"]) {
  if (status === "CONCLUIDA") return "is-complete";
  if (status === "PRONTA_PARA_FEEDBACK") return "is-ready";
  return "is-progress";
}

function formatarData(valor?: string) {
  if (!valor) return undefined;
  const normalizada = valor.length === 10 ? `${valor}T12:00:00` : valor;
  return new Date(normalizada).toLocaleDateString("pt-BR");
}

function labelTipoMovimentacao(tipo: MovimentacaoOrganizacional["tipo"]) {
  if (tipo === "ADMISSAO") return "Admissão";
  if (tipo === "LICENCA") return "Início de licença";
  if (tipo === "RETORNO_LICENCA") return "Retorno de licença";
  if (tipo === "DESLIGAMENTO") return "Desligamento";
  return "Alteração organizacional";
}

function labelStatusOrganizacional(status?: string) {
  if (status === "ATIVO") return "Ativo";
  if (status === "LICENCA") return "Em licença";
  if (status === "DESLIGADO") return "Desligado";
  return status ?? "—";
}

function labelFuncaoOrganizacional(funcao?: string) {
  if (funcao === "GERENTE") return "Gerente";
  if (funcao === "COORDENADOR") return "Coordenador";
  if (funcao === "CONSULTOR") return "Consultor";
  if (funcao === "ANALISTA") return "Analista";
  return funcao ?? "—";
}

function labelSenioridadeOrganizacional(senioridade?: string) {
  if (senioridade === "JUNIOR") return "Júnior";
  if (senioridade === "PLENO") return "Pleno";
  if (senioridade === "SENIOR") return "Sênior";
  return senioridade ?? "—";
}

function mudancasDaMovimentacao(movimento: MovimentacaoOrganizacional) {
  const anterior = movimento.anterior;
  const atual = movimento.atual;
  const mudancas: string[] = [];

  if (!anterior) {
    mudancas.push(`${labelFuncaoOrganizacional(atual.funcao)} · ${atual.cargo}`);
    if (atual.gestorDiretoNome) mudancas.push(`Gestor: ${atual.gestorDiretoNome}`);
    return mudancas;
  }

  if (anterior.status !== atual.status) {
    mudancas.push(
      `Status: ${labelStatusOrganizacional(anterior.status)} → ${labelStatusOrganizacional(atual.status)}`
    );
  }
  if (anterior.gestorDiretoMatricula !== atual.gestorDiretoMatricula) {
    mudancas.push(
      `Gestor: ${anterior.gestorDiretoNome ?? "Sem gestor"} → ${atual.gestorDiretoNome ?? "Sem gestor"}`
    );
  }
  if (anterior.cargo !== atual.cargo) {
    mudancas.push(`Cargo: ${anterior.cargo} → ${atual.cargo}`);
  }
  if (anterior.funcao !== atual.funcao) {
    mudancas.push(
      `Função: ${labelFuncaoOrganizacional(anterior.funcao)} → ${labelFuncaoOrganizacional(atual.funcao)}`
    );
  }
  if (anterior.senioridade !== atual.senioridade) {
    mudancas.push(
      `Senioridade: ${labelSenioridadeOrganizacional(anterior.senioridade)} → ${labelSenioridadeOrganizacional(atual.senioridade)}`
    );
  }
  if (anterior.area !== atual.area) {
    mudancas.push(`Área: ${anterior.area} → ${atual.area}`);
  }

  const colegiadoAnterior = [...(anterior.avaliadoresColegiadoNomes ?? [])].sort();
  const colegiadoAtual = [...(atual.avaliadoresColegiadoNomes ?? [])].sort();
  if (JSON.stringify(colegiadoAnterior) !== JSON.stringify(colegiadoAtual)) {
    mudancas.push(
      `Colegiado: ${colegiadoAnterior.join(", ") || "Sem avaliadores"} → ${colegiadoAtual.join(", ") || "Sem avaliadores"}`
    );
  }

  return mudancas;
}

function ColaboradorDetalhePage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();

  useLayoutEffect(() => {
    window.scrollTo(0, 0);
  }, [id]);
  const [mostrarObservacoes, setMostrarObservacoes] = useState(false);
  const [novaObservacaoToken, setNovaObservacaoToken] = useState(0);
  const [ordenacao, setOrdenacao] = useState<"RECENTES" | "ANTIGAS">("RECENTES");
  const [avaliacoesAbertas, setAvaliacoesAbertas] = useState<Set<string>>(
    () => new Set()
  );

  const matricula = Number(id);
  const colaborador = Number.isFinite(matricula)
    ? getColaboradorByMatricula(matricula)
    : undefined;

  if (!colaborador) {
    return (
      <main className="virtus-page">
        <section className="virtus-empty">
          <h2>Colaborador não encontrado</h2>
          <button
            className="virtus-btn virtus-btn--outline"
            type="button"
            onClick={() => navigate("/")}
          >
            Voltar
          </button>
        </section>
      </main>
    );
  }

  const todosColaboradores = getColaboradores();
  const authorizationContext = usuarioAtual
    ? {
        actor: {
          matricula: usuarioAtual.matricula,
          funcao: usuarioAtual.funcao,
          status: usuarioAtual.status,
        },
      }
    : undefined;
  const podeListarColaboradores = authorizationContext
    ? can(
        authorizationContext,
        "collaborator.list",
        { kind: "collaborator-list", collaborators: todosColaboradores }
      )
    : false;
  const podeVisualizarColaborador =
    authorizationContext && podeListarColaboradores
      ? scopeCollaborators(
          authorizationContext,
          {
            purpose: "OPERATIONAL_TEAM",
            collaborators: todosColaboradores,
          }
        ).some((item) => item.matricula === colaborador.matricula)
      : false;

  if (!podeVisualizarColaborador) {
    return (
      <main className="virtus-page">
        <section className="virtus-empty">
          <h2>Acesso restrito</h2>
          <p>Você não possui acesso administrativo a este colaborador.</p>
          <button
            className="virtus-btn virtus-btn--outline"
            type="button"
            onClick={() => navigate("/")}
          >
            Voltar
          </button>
        </section>
      </main>
    );
  }

  const podeEditarColaborador = authorizationContext
    ? can(
        authorizationContext,
        "collaborator.edit",
        { kind: "collaborator", collaborator: colaborador }
      )
    : false;
  const podeCriarObservacao = authorizationContext
    ? can(
        authorizationContext,
        "observation.create",
        { kind: "observation", collaborator: colaborador }
      )
    : false;
  const podeCriarAvaliacao = authorizationContext
    ? can(
        authorizationContext,
        "evaluation.create",
        {
          kind: "evaluation",
          evaluatedCollaborator: colaborador,
          collaborators: todosColaboradores,
        }
      )
    : false;
  const gestorDireto = colaborador.gestorDiretoMatricula
    ? todosColaboradores.find(
        (item) => item.matricula === colaborador.gestorDiretoMatricula
      )
    : undefined;

  const historicoOrganizacional = getHistoricoOrganizacional(
    colaborador.matricula
  );
  const feedbacksBase = getFeedbacksByColaborador(colaborador.matricula);
  const feedbacksOrdenados = [...feedbacksBase].sort((a, b) => {
    const dataA = new Date(a.dataCriacao ?? a.data).getTime();
    const dataB = new Date(b.dataCriacao ?? b.data).getTime();
    return ordenacao === "RECENTES" ? dataB - dataA : dataA - dataB;
  });

  const feedbacksConcluidos = feedbacksBase.filter(
    (feedback) => feedback.status === "CONCLUIDA"
  );
  const ultimaAvaliacao = [...feedbacksBase].sort(
    (a, b) =>
      new Date(b.dataCriacao ?? b.data).getTime() -
      new Date(a.dataCriacao ?? a.data).getTime()
  )[0];

  const notasValidas = feedbacksConcluidos
    .map((feedback) => feedback.notaMedia)
    .filter((nota) => nota > 0);

  const ultimaNota = ultimaAvaliacao?.notaMedia ?? 0;
  const melhorNota = notasValidas.length > 0 ? Math.max(...notasValidas) : 0;
  const escala = getEscalaAvaliacao();

  const observacoes = getObservacoesByColaborador(colaborador.matricula);
  const observacoesPositivas = observacoes.filter(
    (observacao) => observacao.tipo === "POSITIVA"
  ).length;
  const observacoesNeutras = observacoes.filter(
    (observacao) => observacao.tipo === "NEUTRA"
  ).length;
  const observacoesNegativas = observacoes.filter(
    (observacao) => observacao.tipo === "NEGATIVA"
  ).length;

  const idMaisRecente = [...feedbacksBase].sort(
    (a, b) =>
      new Date(b.dataCriacao ?? b.data).getTime() -
      new Date(a.dataCriacao ?? a.data).getTime()
  )[0]?.id;

  function estaAberta(feedbackId: string) {
    return avaliacoesAbertas.size === 0
      ? feedbackId === idMaisRecente
      : avaliacoesAbertas.has(feedbackId);
  }

  function abrirNovaObservacao() {
    setMostrarObservacoes(true);
    setNovaObservacaoToken((valor) => valor + 1);

    window.setTimeout(() => {
      document
        .getElementById("observacoes-detalhe")
        ?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 80);
  }

  function alternarAvaliacao(feedbackId: string) {
    setAvaliacoesAbertas((atual) => {
      const proximo = new Set(atual);

      if (proximo.size === 0 && idMaisRecente) {
        proximo.add(idMaisRecente);
      }

      if (proximo.has(feedbackId)) {
        proximo.delete(feedbackId);
      } else {
        proximo.add(feedbackId);
      }

      return proximo;
    });
  }

  function estiloNota(valor: number) {
    if (valor <= 0) {
      return {
        "--score-color": "var(--brand-primary)",
        "--score-bg": "#f7f3f9",
        "--score-border": "#e7dbea",
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
    if (valor <= 0) return "Sem nota";
    return getItemEscalaPorNota(valor, escala).significado;
  }

  return (
    <main className="virtus-page collaborator-detail-v3">
      <button
        type="button"
        className="collaborator-detail-back"
        onClick={() => navigate("/")}
      >
        ← Voltar para colaboradores
      </button>

      <section className="collaborator-profile-card collaborator-profile-card--identity">
        <CollaboratorIdentity
          colaborador={colaborador}
          variant="profile"
          gestorNome={gestorDireto?.nome}
        />

        <div className="virtus-page-actions collaborator-profile-actions">
          {podeEditarColaborador && (
            <Link
              to={`/colaborador/${colaborador.matricula}/editar`}
              className="virtus-btn virtus-btn--outline collaborator-link-button"
            >
              <IconEdit />
              Editar cadastro
            </Link>
          )}

          {podeCriarObservacao && (
            <button
              type="button"
              className="virtus-btn virtus-btn--outline collaborator-link-button"
              onClick={abrirNovaObservacao}
            >
              <IconPlus />
              Nova observação
            </button>
          )}

          {podeCriarAvaliacao && (
            <Link
              to={`/colaborador/${colaborador.matricula}/novo-feedback`}
              className="virtus-btn virtus-btn--primary collaborator-link-button"
            >
              <IconPlus />
              Nova avaliação
            </Link>
          )}
        </div>
      </section>

      <section className="collaborator-kpis">
        <article className="collaborator-kpi">
          <span className="collaborator-kpi__icon">
            <IconChart />
          </span>
          <div>
            <small>Avaliações</small>
            <strong>{feedbacksBase.length}</strong>
            <span>Total realizadas</span>
          </div>
        </article>

        <article
          className="collaborator-kpi score-semantic"
          style={estiloNota(ultimaNota)}
        >
          <span className="collaborator-kpi__icon">
            <IconStar />
          </span>
          <div>
            <small>Última nota</small>
            <strong className="is-score">
              {ultimaNota > 0 ? formatarNota(ultimaNota) : "—"}
            </strong>
            <span className="collaborator-kpi__score-label">
              {labelNota(ultimaNota)}
            </span>
          </div>
        </article>

        <article
          className="collaborator-kpi score-semantic"
          style={estiloNota(melhorNota)}
        >
          <span className="collaborator-kpi__icon">
            <IconTrend />
          </span>
          <div>
            <small>Melhor nota</small>
            <strong className="is-score">
              {melhorNota > 0 ? formatarNota(melhorNota) : "—"}
            </strong>
            <span className="collaborator-kpi__score-label">
              {labelNota(melhorNota)}
            </span>
          </div>
        </article>

        <article className="collaborator-kpi">
          <span className="collaborator-kpi__icon">
            <IconCheck />
          </span>
          <div>
            <small>Concluídas</small>
            <strong>{feedbacksConcluidos.length}</strong>
            <span>
              Das {feedbacksBase.length}{" "}
              {feedbacksBase.length === 1 ? "avaliação" : "avaliações"}
            </span>
          </div>
        </article>
      </section>

      <section className="collaborator-section">
        <div className="collaborator-section-heading">
          <h2>Observações</h2>
        </div>

        <div className="collaborator-observation-summary">
          <button
            type="button"
            className="collaborator-observation-kpi is-positive"
            onClick={() => setMostrarObservacoes(true)}
          >
            <span className="collaborator-observation-kpi__icon">
              <IconPositive />
            </span>
            <span className="collaborator-observation-kpi__copy">
              <small>Positivas</small>
              <strong>{observacoesPositivas}</strong>
              <em>Ver todas →</em>
            </span>
          </button>

          <button
            type="button"
            className="collaborator-observation-kpi is-neutral"
            onClick={() => setMostrarObservacoes(true)}
          >
            <span className="collaborator-observation-kpi__icon">
              <IconNeutral />
            </span>
            <span className="collaborator-observation-kpi__copy">
              <small>Neutras</small>
              <strong>{observacoesNeutras}</strong>
              <em>Ver todas →</em>
            </span>
          </button>

          <button
            type="button"
            className="collaborator-observation-kpi is-negative"
            onClick={() => setMostrarObservacoes(true)}
          >
            <span className="collaborator-observation-kpi__icon">
              <IconNegative />
            </span>
            <span className="collaborator-observation-kpi__copy">
              <small>Negativas</small>
              <strong>{observacoesNegativas}</strong>
              <em>Ver todas →</em>
            </span>
          </button>
        </div>

        {mostrarObservacoes && (
          <div className="collaborator-observations-detail" id="observacoes-detalhe">
            <div className="collaborator-observations-detail__top">
              <strong>Todas as observações</strong>
              <button
                type="button"
                className="virtus-btn virtus-btn--outline"
                onClick={() => setMostrarObservacoes(false)}
              >
                Fechar
              </button>
            </div>
            <ObservacoesColaborador
              colaborador={colaborador}
              abrirNovaObservacaoToken={novaObservacaoToken}
            />
          </div>
        )}
      </section>

      <section className="collaborator-section">
        <div className="collaborator-section-heading collaborator-section-heading--history">
          <div>
            <h2>Histórico de avaliações</h2>
          </div>

          <label className="collaborator-sort">
            <span>Ordenar por:</span>
            <select
              value={ordenacao}
              onChange={(event) =>
                setOrdenacao(event.target.value as "RECENTES" | "ANTIGAS")
              }
            >
              <option value="RECENTES">Mais recentes</option>
              <option value="ANTIGAS">Mais antigas</option>
            </select>
          </label>
        </div>

        {feedbacksOrdenados.length === 0 ? (
          <div className="collaborator-history-empty">
            Nenhuma avaliação registrada para este colaborador.
          </div>
        ) : (
          <div className="collaborator-history">
            {feedbacksOrdenados.map((feedback) => {
              const preenchimento = calcularPreenchimentoFeedback(feedback);
              const dataInicio = formatarData(feedback.dataCriacao ?? feedback.data);
              const dataFim = formatarData(feedback.dataConclusao);
              const temNota = feedback.notaMedia > 0;
              const aberta = estaAberta(feedback.id);

              return (
                <article
                  className={`collaborator-evaluation-card score-semantic ${
                    aberta ? "is-open" : "is-closed"
                  }`}
                  style={estiloNota(feedback.notaMedia)}
                  key={feedback.id}
                >
                  <header className="collaborator-evaluation-card__header">
                    <button
                      type="button"
                      className="collaborator-evaluation-card__toggle"
                      onClick={() => alternarAvaliacao(feedback.id)}
                      aria-expanded={aberta}
                    >
                      <span className="collaborator-evaluation-card__calendar">
                        <IconCalendar />
                      </span>
                      <span className="collaborator-evaluation-card__cycle-copy">
                        <span className="collaborator-evaluation-card__title">
                          <strong>
                            {feedback.ano} • Ciclo {feedback.ciclo}
                          </strong>
                          <span
                            className={`collaborator-evaluation-status ${classeStatusFeedback(
                              feedback.status
                            )}`}
                          >
                            {labelStatusFeedback(feedback.status)}
                          </span>
                        </span>
                        <small>
                          {dataInicio ? `Início: ${dataInicio}` : ""}
                          {dataFim ? ` • Conclusão: ${dataFim}` : ""}
                        </small>
                      </span>
                    </button>

                    <div className="collaborator-evaluation-card__actions">
                      <Link
                        className="virtus-btn virtus-btn--outline collaborator-link-button collaborator-link-button--compact"
                        to={`/colaborador/${colaborador.matricula}/feedback/${feedback.id}`}
                      >
                        {feedback.status === "CONCLUIDA"
                          ? "Ver avaliação"
                          : "Abrir avaliação"}{" "}
                        →
                      </Link>

                      <button
                        type="button"
                        className="collaborator-chevron"
                        onClick={() => alternarAvaliacao(feedback.id)}
                        aria-label={aberta ? "Recolher avaliação" : "Expandir avaliação"}
                      >
                        <IconChevron aberto={aberta} />
                      </button>
                    </div>
                  </header>

                  {aberta && (
                    <>
                      <div className="collaborator-evaluation-summary">
                        <div className="collaborator-evaluation-score">
                          <small>
                            {feedback.status === "CONCLUIDA"
                              ? "Nota final"
                              : "Nota atual / final"}
                          </small>
                          <strong>
                            {temNota ? formatarNota(feedback.notaMedia) : "—"}
                          </strong>
                          <span>{labelNota(feedback.notaMedia)}</span>
                        </div>

                        <div className="collaborator-evaluation-progress">
                          <small>Progresso geral</small>
                          <strong>{preenchimento.geral}%</strong>
                          <span>Preenchimento total</span>
                        </div>

                        <div className="collaborator-evaluation-raters">
                          <small>Progresso por avaliador</small>
                          {[
                            ["Gerente", preenchimento.gerente],
                            ["Coordenador", preenchimento.coordenador],
                            ["Colegiado", preenchimento.colegiado],
                          ].map(([label, percentual]) => (
                            <div className="collaborator-rater-progress" key={label}>
                              <div>
                                <span>{label}</span>
                                <strong>{percentual}%</strong>
                              </div>
                              <div className="collaborator-progress-track">
                                <i style={{ width: `${percentual}%` }} />
                              </div>
                            </div>
                          ))}
                        </div>
                      </div>

                      <div className="collaborator-competencies">
                        <small>Competências avaliadas</small>
                        <div className="collaborator-competencies__grid">
                          {criterioSiglas.map((sigla) => {
                            const criterio = feedback.criteriosDetalhados?.find(
                              (item) =>
                                normalizarTexto(item.criterioNome) ===
                                normalizarTexto(criterioNomePorSigla[sigla])
                            );
                            const nota = criterio?.nota ?? 0;

                            return (
                              <div
                                className={`collaborator-competency ${
                                  nota > 0 ? "score-semantic has-score" : ""
                                }`}
                                key={sigla}
                                style={nota > 0 ? estiloNota(nota) : undefined}
                              >
                                <span className="collaborator-competency__icon">
                                  {criterioIconPorSigla[sigla]}
                                </span>
                                <span className="collaborator-competency__name">
                                  {criterioNomePorSigla[sigla]}
                                </span>
                                <strong>
                                  {nota > 0 ? formatarNota(nota) : "—"}
                                </strong>
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    </>
                  )}
                </article>
              );
            })}
          </div>
        )}
      </section>

      <section className="collaborator-section collaborator-org-history-section">
        <div className="collaborator-section-heading">
          <div>
            <h2>Histórico organizacional</h2>
            <p className="collaborator-section-subtitle">
              Movimentações registradas com data de vigência e contexto do ciclo.
            </p>
          </div>
        </div>

        {historicoOrganizacional.length === 0 ? (
          <div className="collaborator-history-empty">
            Nenhuma movimentação organizacional registrada ainda.
          </div>
        ) : (
          <div className="collaborator-org-timeline">
            {historicoOrganizacional.map((movimento) => {
              const mudancas = mudancasDaMovimentacao(movimento);
              return (
                <article className="collaborator-org-event" key={movimento.id}>
                  <div className="collaborator-org-event__rail" aria-hidden="true">
                    <span />
                  </div>
                  <div className="collaborator-org-event__content">
                    <header>
                      <div>
                        <strong>{labelTipoMovimentacao(movimento.tipo)}</strong>
                        <span>{formatarData(movimento.dataVigencia)}</span>
                      </div>
                      <span className="collaborator-org-event__scope">
                        {movimento.escopo === "SOMENTE_CICLOS_POSTERIORES"
                          ? "Ciclos posteriores"
                          : "Ciclo atual e posteriores"}
                      </span>
                    </header>

                    {mudancas.length > 0 && (
                      <div className="collaborator-org-event__changes">
                        {mudancas.map((mudanca) => (
                          <span key={mudanca}>{mudanca}</span>
                        ))}
                      </div>
                    )}

                    {(movimento.motivo ||
                      movimento.cicloReferenciaLabel ||
                      movimento.autorNome) && (
                      <footer>
                        {movimento.motivo && <span>Motivo: {movimento.motivo}</span>}
                        {movimento.cicloReferenciaLabel && (
                          <span>Ciclo de referência: {movimento.cicloReferenciaLabel}</span>
                        )}
                        {movimento.autorNome && (
                          <span>Alterado por: {movimento.autorNome}</span>
                        )}
                      </footer>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>

    </main>
  );
}

export default ColaboradorDetalhePage;

