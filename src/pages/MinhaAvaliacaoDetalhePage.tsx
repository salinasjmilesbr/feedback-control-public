import { useEffect, useState, type CSSProperties } from "react";
import { useNavigate, useParams } from "react-router-dom";
import CriterionIcon from "../components/CriterionIcon";
import RoleExpectationsCard from "../components/RoleExpectationsCard";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";
import { exportarAvaliacaoPdf } from "../services/exportarAvaliacaoPdf";
import {
  formatarPeriodoCiclo,
  getCiclosAvaliacao,
} from "./cicloApresentacaoLegada";
import { getColaboradores } from "../services/colaboradorStorage";
import { useAuth } from "../auth/AuthContext";
import { obterRepositorioMetasSoberanas } from "../services/acessoMetasSoberanas";
import { metasDoAvaliadoSoberanas } from "./useMetasSoberanasDaAvaliacao";
import { obterRepositorioCiclosSoberanos } from "../services/acessoCiclosSoberanos";
import type { MetaSoberana } from "../application/ports/GoalRepository";
import type { ObservacaoSoberana } from "../application/ports/ObservationRepository";

import {
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import {
  formatarNotaAvaliacao,
  getTextoNotaAvaliacao,
  possuiNotaAvaliacao,
} from "../services/apresentacaoNota";
import {
  collaboratorIdDoLegado,
  estruturaSoberanaEfetiva,
  visaoEstruturalLegada,
} from "../services/estruturaSoberanaCliente";
import "../styles/avaliacoes.css";

const criterioIcons = Array.from({ length: 8 }, (_, index) => (
  <CriterionIcon index={index} key={index} />
));

function IconSpark() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m12 3 1.45 4.55L18 9l-4.55 1.45L12 15l-1.45-4.55L6 9l4.55-1.45L12 3Z" />
      <path d="m18 15 .85 2.15L21 18l-2.15.85L18 21l-.85-2.15L15 18l2.15-.85L18 15Z" />
    </svg>
  );
}

/** Resultado de UMA leitura de metas (o que a tela consome, sem a chave). */
interface LeituraDasMetasSelf {
  readonly metas: readonly MetaSoberana[];
  readonly carregando: boolean;
  readonly erro: string;
}

/** Resultado PUBLICADO, preso à chave do contexto que o produziu. */
interface LeituraPublicadaDasMetas {
  readonly chave: string;
  readonly resultado: LeituraDasMetasSelf;
}

function MinhaAvaliacaoDetalhePage() {
  const navigate = useNavigate();
  const { feedbackId } = useParams();
  const { usuarioAtual } = useUsuarioAtual();
  const { organizacaoAtivaId } = useAuth();
  const [mostrarRegua, setMostrarRegua] = useState(false);
  /**
   * F5-10 P6 (Issue #220): as metas do ciclo vêm da superfície SOBERANA (relação
   * SELF). Loading e erro são EXPLÍCITOS — ausência de caminho soberano nunca
   * vira lista vazia silenciosa nem leitura local. O resultado é publicado com a
   * CHAVE do contexto (mesmo padrão de `MinhasMetasPage`) e o estado exibido é
   * DERIVADO: nenhum `setState` síncrono no corpo do efeito.
   */
  const [leituraMetas, setLeituraMetas] = useState<LeituraPublicadaDasMetas | null>(
    null
  );
  const [erroPdf, setErroPdf] = useState("");
  const [gerandoPdf, setGerandoPdf] = useState(false);

  const organizacaoId =
    typeof organizacaoAtivaId === "string" && organizacaoAtivaId.length > 0
      ? organizacaoAtivaId
      : null;

  /**
   * FONTE ESTÁVEL do efeito: a leitura de feedbacks é SÍNCRONA e devolve um novo
   * objeto a cada render, o que dispararia releitura infinita se a REFERÊNCIA
   * fosse dependência. Derivamos aqui a CHAVE FUNCIONAL da avaliação (matrícula +
   * ano + ciclo + id) como PRIMITIVOS estáveis: a mesma avaliação produz sempre a
   * mesma chave, e o efeito só relê quando ela muda de fato.
   */
  const matriculaDoAtor = usuarioAtual?.matricula;
  const avaliacaoDoAtor =
    matriculaDoAtor === undefined
      ? undefined
      : getFeedbacksByColaborador(matriculaDoAtor).find(
          (item) => item.id === feedbackId && item.status === "CONCLUIDA"
        );
  const anoDaAvaliacao = avaliacaoDoAtor?.ano;
  const numeroDoCicloDaAvaliacao = avaliacaoDoAtor?.ciclo;

  /** Chave funcional da leitura de metas (organização + ator + avaliação). */
  const chaveDasMetas = `${organizacaoId ?? "sem-organizacao"}|${
    matriculaDoAtor ?? "sem-ator"
  }|${anoDaAvaliacao ?? "sem-ano"}|${numeroDoCicloDaAvaliacao ?? "sem-ciclo"}`;

  const semEntradaParaMetas =
    !organizacaoId ||
    matriculaDoAtor === undefined ||
    anoDaAvaliacao === undefined ||
    numeroDoCicloDaAvaliacao === undefined;

  const resultadoDasMetas: LeituraDasMetasSelf = semEntradaParaMetas
    ? { metas: [], carregando: false, erro: "" }
    : leituraMetas?.chave === chaveDasMetas
    ? leituraMetas.resultado
    : { metas: [], carregando: true, erro: "" };

  const metasSelf = resultadoDasMetas.metas;
  const carregandoMetas = resultadoDasMetas.carregando;
  const erroMetas = resultadoDasMetas.erro;

  // Leitura SOBERANA das metas do próprio colaborador (relação SELF) no ciclo da
  // avaliação. O ciclo é resolvido pelo UUID soberano (ano/número são rótulos) e
  // o dono, pelo UUID da ponte estrutural; nada é decidido no cliente.
  useEffect(() => {
    let vigente = true;

    const publicar = (resultado: LeituraDasMetasSelf) => {
      if (vigente) setLeituraMetas({ chave: chaveDasMetas, resultado });
    };

    void (async () => {
      // Rechecagem explícita: é ela que ESTREITA os tipos dentro do fluxo.
      if (
        !organizacaoId ||
        matriculaDoAtor === undefined ||
        anoDaAvaliacao === undefined ||
        numeroDoCicloDaAvaliacao === undefined
      ) {
        publicar({ metas: [], carregando: false, erro: "" });
        return;
      }

      const repositorio = obterRepositorioMetasSoberanas();
      const portaCiclos = obterRepositorioCiclosSoberanos();
      const colaboradorUuid = collaboratorIdDoLegado(
        estruturaSoberanaEfetiva(getColaboradores()),
        matriculaDoAtor
      );

      if (!repositorio || !portaCiclos || !colaboradorUuid) {
        publicar({
          metas: [],
          carregando: false,
          erro: "As metas do ciclo não estão disponíveis pelo caminho soberano neste ambiente.",
        });
        return;
      }

      try {
        const ciclos = await portaCiclos.listarCiclos(organizacaoId);
        if (!vigente) return;

        const ciclo = ciclos.ok
          ? ciclos.data.find(
              (item) =>
                item.ano === anoDaAvaliacao &&
                item.numero === numeroDoCicloDaAvaliacao
            )
          : undefined;

        if (!ciclo) {
          publicar({
            metas: [],
            carregando: false,
            erro: "Não foi possível resolver o ciclo da avaliação pelo caminho soberano.",
          });
          return;
        }

        const metas = await repositorio.listarMetasPorEscopo(
          organizacaoId,
          ciclo.id
        );
        if (!vigente) return;

        if (!metas.ok) {
          publicar({
            metas: [],
            carregando: false,
            erro: "Não foi possível carregar as metas do ciclo.",
          });
          return;
        }

        // Metas DO PRÓPRIO ATOR: o dono é `collaboratorId`, nunca a `relacao`.
        const metasDoAtor = metasDoAvaliadoSoberanas(
          metas.data.metas,
          colaboradorUuid
        )
          .slice()
          .sort(
            (a, b) =>
              new Date(a.criadoEm).getTime() - new Date(b.criadoEm).getTime()
          );

        publicar({ metas: metasDoAtor, carregando: false, erro: "" });
      } catch {
        publicar({
          metas: [],
          carregando: false,
          erro: "Não foi possível carregar as metas do ciclo.",
        });
      }
    })();

    return () => {
      vigente = false;
    };
  }, [
    chaveDasMetas,
    organizacaoId,
    matriculaDoAtor,
    anoDaAvaliacao,
    numeroDoCicloDaAvaliacao,
  ]);

  if (!usuarioAtual) {
    return (
      <main className="virtus-page">
        <section className="evaluation-empty">
          <h1>Usuário atual não definido</h1>
        </section>
      </main>
    );
  }

  // F5-08 P6 (correção da auditoria): a estrutura vem do PRODUTOR soberano
  // (projeção publicada pelo shell autenticado). `funcao` textual e
  // `gestorDiretoMatricula` local não decidem quem avalia quem; sem evidência
  // soberana a decisão é fail-closed (nenhuma seção de papel é presumida).
  const colaboradores = getColaboradores();
  const estruturaSoberana = estruturaSoberanaEfetiva(colaboradores);
  const visaoEstrutural = visaoEstruturalLegada(
    estruturaSoberana,
    usuarioAtual.matricula
  );
  const usaEstruturaAvaliacaoAnalista = visaoEstrutural?.temCadeiaDeGestao ?? false;

  // A avaliação do ator é a MESMA identidade derivada acima (chave funcional do
  // efeito): uma única leitura, sem segunda resolução divergente.
  const feedback = avaliacaoDoAtor;

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

  /**
   * F5-11 P5 (Issue #250) — fluxo SELF **fail-closed e sem autoridade local**.
   *
   * A visão do avaliado NÃO lê mais observação do acervo do navegador: a lista
   * entregue à tela e ao PDF é VAZIA e o estado é explicitamente indisponível
   * (o bloco de observações e o atalho da navegação simplesmente não aparecem —
   * mesmo padrão de ausência já usado nesta página).
   *
   * A leitura SELF soberana depende da concessão mínima de `observation.read`
   * ao avaliado, decidida para a fase P5.1: nesta fase não há caminho autorizado
   * para o próprio avaliado ler as comunicadas, e NENHUMA capability, grant,
   * escopo ou papel é presumido aqui.
   */
  const observacoesComunicadas: readonly ObservacaoSoberana[] = [];

  const cicloDaAvaliacao = getCiclosAvaliacao().find(
    (ciclo) =>
      ciclo.ano === feedback.ano &&
      ciclo.ciclo === feedback.ciclo
  );

  const metasDoCiclo = metasSelf;

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

  const gestorDireto =
    visaoEstrutural?.gestorMatriculaLegada == null
      ? undefined
      : colaboradores.find(
          (item) => item.matricula === visaoEstrutural.gestorMatriculaLegada
        );

  // "Coordenador" = gestor direto de nível INTERMEDIÁRIO (fato relacional da
  // estrutura soberana). Gestor direto na raiz é o gerente responsável.
  const coordenadorAvaliador = visaoEstrutural?.gestorTemSuperior
    ? gestorDireto
    : undefined;

  const matriculaGerente =
    visaoEstrutural === null
      ? null
      : visaoEstrutural.gestorTemSuperior
        ? visaoEstrutural.superiorDoGestorMatriculaLegada
        : visaoEstrutural.gestorMatriculaLegada;
  const gerenteAvaliador =
    matriculaGerente === null
      ? undefined
      : colaboradores.find((item) => item.matricula === matriculaGerente);

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

  function labelStatusMeta(status: string) {
    if (status === "ATINGIDA") return "Atingida";
    if (status === "NAO_ATINGIDA") return "Não atingida";
    return "Pendente / Não finalizada";
  }

  /**
   * F5-10 P6 (Issue #220): o PDF recebe as metas JÁ LIDAS da superfície soberana.
   * Enquanto elas não estiverem disponíveis (carregando ou em erro) a exportação é
   * recusada com aviso explícito — nunca um PDF que PRESUMA metas aprovadas ou
   * leia storage local.
   */
  async function exportarPdf() {
    if (erroMetas) {
      setErroPdf(
        "Não foi possível exportar: as metas do ciclo não foram carregadas."
      );
      return;
    }

    if (carregandoMetas) {
      setErroPdf("Aguarde o carregamento das metas do ciclo para exportar.");
      return;
    }

    if (gerandoPdf) return;

    setErroPdf("");
    setGerandoPdf(true);

    // `exportarPdf` e declaracao hoisted: o estreitamento de tipo do corpo do
    // componente NAO atravessa a fronteira da função. Capturamos os valores
    // ja estreitados e recusamos explicitamente quando faltar identidade ou
    // avaliação.
    const ator = usuarioAtual;
    const avaliacao = feedback;
    if (!ator || !avaliacao) {
      setErroPdf("Não foi possível exportar: avaliação ou usuário indisponível.");
      return;
    }
    try {
      // L5: o PDF recebe a lista SOBERANA de comunicadas por parâmetro. Nesta
      // fase a visão do avaliado entrega lista VAZIA (fail-closed): nenhuma
      // observação local é arrastada para o documento (ver comentário da
      // constante `observacoesComunicadas`).
      await exportarAvaliacaoPdf(
        ator,
        avaliacao,
        metasDoCiclo,
        observacoesComunicadas
      );
    } catch {
      setErroPdf("Não foi possível gerar o PDF desta avaliação.");
    } finally {
      setGerandoPdf(false);
    }
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
            onClick={() => void exportarPdf()}
            disabled={gerandoPdf}
          >
            {gerandoPdf ? "Gerando PDF…" : "Exportar PDF"}
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

      <RoleExpectationsCard
        expectativa={feedback.expectativaCargoSnapshot}
      />

      <section className="evaluation-score-card" id="resumo">
        <div
          className="evaluation-score-primary score-semantic evaluation-score-primary--semantic"
          style={estiloNota(feedback.notaMedia)}
        >
          <span>Resultado do ciclo</span>
          <strong>{formatarNotaAvaliacao(feedback.notaMedia)}</strong>
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
                  {formatarNotaAvaliacao(item.notaMedia)}
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
                  <strong>
                    {possuiNotaAvaliacao(feedback.notaMedia)
                      ? `${formatarNotaAvaliacao(feedback.notaMedia)} / 5`
                      : "—"}
                  </strong>
                </div>
              </div>

              <div>
                <span className="evaluation-summary-metric__icon is-blue">▥</span>
                <div>
                  <small>Média geral</small>
                  <strong>{formatarNotaAvaliacao(feedback.notaMedia)}</strong>
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

              {usaEstruturaAvaliacaoAnalista &&
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

      {erroPdf && (
        <section className="evaluation-alert evaluation-alert--warning" role="alert">
          <strong>Exportação indisponível.</strong>
          <p>{erroPdf}</p>
        </section>
      )}

      {carregandoMetas && (
        <section className="evaluation-alert evaluation-alert--warning" role="status">
          <strong>Carregando metas do ciclo…</strong>
        </section>
      )}

      {erroMetas && (
        <section className="evaluation-alert evaluation-alert--warning" role="alert">
          <strong>Metas do ciclo indisponíveis.</strong>
          <p>{erroMetas}</p>
        </section>
      )}

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
                usaEstruturaAvaliacaoAnalista
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
                    <strong>{formatarNotaAvaliacao(criterio.nota)}</strong>
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
                            {formatarNotaAvaliacao(subcriterio.notaGerente)}
                          </strong>
                        </div>

                        {usaEstruturaAvaliacaoAnalista && (
                          <>
                            <div>
                              <span>Coordenador</span>
                              <strong>
                                {formatarNotaAvaliacao(subcriterio.notaCoordenador)}
                              </strong>
                            </div>

                            <div>
                              <span>Colegiado</span>
                              <strong>
                                {formatarNotaAvaliacao(subcriterio.notaColegiado)}
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
                        <strong>{formatarNotaAvaliacao(subcriterio.notaFinal)}</strong>
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

                    {usaEstruturaAvaliacaoAnalista &&
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
                            <dt>Último acompanhamento</dt>
                            <dd>
                              {formatarData(meta.dataUltimoAcompanhamento ?? undefined)}
                            </dd>
                          </div>
                          <div>
                            <dt>Resultado final</dt>
                            <dd>
                              {meta.resultadoFinal?.trim()
                                ? meta.resultadoFinal
                                : "Não informado"}
                            </dd>
                          </div>
                          <div>
                            <dt>Concluída em</dt>
                            <dd>{formatarData(meta.dataFechamento ?? undefined)}</dd>
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
                    {new Date(observacao.criadoEm).toLocaleDateString(
                      "pt-BR"
                    )}
                  </span>
                </div>

                <p>{observacao.texto}</p>
                <small>
                  {observacao.autorCollaboratorId
                    ? "Registrada por um autor identificado na estrutura carregada"
                    : "Autoria não identificada"}
                </small>
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

            {usaEstruturaAvaliacaoAnalista &&
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
        {usaEstruturaAvaliacaoAnalista
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
