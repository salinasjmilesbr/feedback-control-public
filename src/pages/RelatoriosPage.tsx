import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import CriterionIcon from "../components/CriterionIcon";
import RelatorioCriterioDetalhe from "../components/RelatorioCriterioDetalhe";
import {
  formatarPeriodoCiclo,
  getCiclosAvaliacao,
} from "../services/cicloAvaliacaoStorage";
import { getColaboradores } from "../services/colaboradorStorage";
import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import {
  getRelatorioComparacaoCiclos,
  getRelatorioDetalheCriterio,
  getRelatorioEvolucaoIndividual,
  getRelatorioVisaoGeral,
  type FiltroCargoRelatorio,
  type FiltrosRelatorio,
} from "../services/relatorioService";
import type { SituacaoAvaliacaoCiclo } from "../services/cicloEquipeService";
import "../styles/relatorios.css";

const statusLabels: Record<SituacaoAvaliacaoCiclo, string> = {
  NAO_INICIADA: "Não iniciada",
  EM_ANDAMENTO: "Em andamento",
  PRONTA_PARA_FEEDBACK: "Pronta para Feedback",
  CONCLUIDA: "Concluída",
  SUSPENSA: "Suspensa",
  NAO_APLICAVEL: "Não aplicável",
};

function labelFuncao(
  funcao: "GERENTE" | "COORDENADOR" | "CONSULTOR" | "ANALISTA" | "ESTAGIARIO" | undefined,
  senioridade: "JUNIOR" | "PLENO" | "SENIOR" | undefined
) {
  if (funcao === "ESTAGIARIO") return "Estagiário";
  if (funcao === "COORDENADOR") return "Coordenador";
  if (funcao === "CONSULTOR") return "Consultor";
  if (funcao === "ANALISTA") {
    if (senioridade === "JUNIOR") return "Analista Júnior";
    if (senioridade === "PLENO") return "Analista Pleno";
    if (senioridade === "SENIOR") return "Analista Sênior";
    return "Analista";
  }
  return "Colaborador";
}

function RelatoriosPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();

  const ciclosDisponiveis = useMemo(
    () =>
      getCiclosAvaliacao().filter(
        (ciclo) => ciclo.status === "ATIVO" || ciclo.status === "ENCERRADO"
      ),
    []
  );

  const [cicloId, setCicloId] = useState(
    ciclosDisponiveis.find((ciclo) => ciclo.status === "ATIVO")?.id ??
      ciclosDisponiveis[0]?.id ??
      ""
  );

  const [coordenadorFiltro, setCoordenadorFiltro] = useState("");
  const [cargoFiltro, setCargoFiltro] = useState("");
  const [situacaoFiltro, setSituacaoFiltro] = useState("");
  const [faixaFiltro, setFaixaFiltro] = useState("");
  const [criterioAbertoId, setCriterioAbertoId] = useState<string | null>(null);

  if (
    !usuarioAtual ||
    (usuarioAtual.funcao !== "GERENTE" &&
      usuarioAtual.funcao !== "COORDENADOR")
  ) {
    return (
      <main className="virtus-page reports-page">
        <section className="reports-empty">
          <h1>Acesso restrito</h1>
          <p>Relatórios estão disponíveis para gerentes e coordenadores.</p>
        </section>
      </main>
    );
  }

  if (!ciclosDisponiveis.length) {
    return (
      <main className="virtus-page reports-page">
        <section className="reports-page-header">
          <div>
            <h1>Relatórios</h1>
            <p>Visão consolidada de desempenho e evolução da equipe.</p>
          </div>
        </section>
        <section className="reports-empty">
          <h2>Nenhum ciclo disponível</h2>
          <p>Ative ou encerre um ciclo para habilitar a visão de relatórios.</p>
        </section>
      </main>
    );
  }

  const ciclo =
    ciclosDisponiveis.find((item) => item.id === cicloId) ??
    ciclosDisponiveis[0];

  const relatorioBase = getRelatorioVisaoGeral(ciclo, usuarioAtual);

  const filtros: FiltrosRelatorio = {
    coordenadorMatricula:
      coordenadorFiltro !== "" ? Number(coordenadorFiltro) : undefined,
    cargo:
      cargoFiltro !== "" ? (cargoFiltro as FiltroCargoRelatorio) : undefined,
    situacao:
      situacaoFiltro !== ""
        ? (situacaoFiltro as SituacaoAvaliacaoCiclo)
        : undefined,
    faixaNota: faixaFiltro !== "" ? Number(faixaFiltro) : undefined,
  };

  const relatorio = getRelatorioVisaoGeral(ciclo, usuarioAtual, filtros);

  const colaboradoresCadastro = getColaboradores();
  const coordenadoresDisponiveis = Array.from(
    new Set(
      relatorioBase.colaboradores
        .map((item) => item.gestorDiretoMatricula)
        .filter((matricula): matricula is number => matricula !== undefined)
    )
  )
    .map((matricula) =>
      colaboradoresCadastro.find((item) => item.matricula === matricula)
    )
    .filter(
      (item): item is NonNullable<typeof item> => Boolean(item)
    )
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  const escalaRelatorio = [...getEscalaAvaliacao()].sort(
    (a, b) => b.nota - a.nota
  );

  const filtrosAtivos = [
    usuarioAtual.funcao === "GERENTE" ? coordenadorFiltro : "",
    cargoFiltro,
    situacaoFiltro,
    faixaFiltro,
  ].filter(Boolean).length;

  function limparFiltros() {
    setCoordenadorFiltro("");
    setCargoFiltro("");
    setSituacaoFiltro("");
    setFaixaFiltro("");
  }

  const ciclosOrdenados = [...ciclosDisponiveis].sort(
    (a, b) => a.ano - b.ano || a.ciclo - b.ciclo
  );
  const indiceOrdenado = ciclosOrdenados.findIndex(
    (item) => item.id === ciclo.id
  );
  const cicloAnterior =
    indiceOrdenado > 0 ? ciclosOrdenados[indiceOrdenado - 1] : undefined;

  const comparacao = getRelatorioComparacaoCiclos(
    ciclo,
    cicloAnterior,
    usuarioAtual,
    filtros
  );

  const evolucaoIndividual = getRelatorioEvolucaoIndividual(
    ciclo,
    cicloAnterior,
    usuarioAtual,
    filtros
  );
  const evolucaoPorMatricula = new Map(
    evolucaoIndividual.map((item) => [item.matricula, item])
  );

  const faixaMedia =
    relatorio.mediaEquipe > 0
      ? getItemEscalaPorNota(relatorio.mediaEquipe)
      : undefined;

  const detalheCriterioAberto = criterioAbertoId
    ? getRelatorioDetalheCriterio(
        criterioAbertoId,
        ciclo,
        cicloAnterior,
        usuarioAtual,
        filtros
      )
    : undefined;

  return (
    <main className="virtus-page reports-page">
      <section className="reports-page-header">
        <div>
          <h1>Relatórios</h1>
          <p>
            Visão consolidada de desempenho da{" "}
            {usuarioAtual.funcao === "COORDENADOR"
              ? "sua equipe direta"
              : "equipe"}.
          </p>
        </div>

        <label className="reports-cycle-filter">
          <span>Ciclo</span>
          <select value={ciclo.id} onChange={(e) => setCicloId(e.target.value)}>
            {ciclosDisponiveis.map((item) => (
              <option key={item.id} value={item.id}>
                {item.ano} • Ciclo {item.ciclo}
                {item.status === "ATIVO" ? " — Ativo" : ""}
              </option>
            ))}
          </select>
        </label>
      </section>

      <section className="reports-cycle-context">
        <div>
          <strong>
            {ciclo.ano} • Ciclo {ciclo.ciclo}
          </strong>
          <span>{formatarPeriodoCiclo(ciclo.dataInicio, ciclo.dataFim)}</span>
        </div>
        <span
          className={`reports-cycle-status ${
            ciclo.status === "ATIVO" ? "is-active" : "is-closed"
          }`}
        >
          {ciclo.status === "ATIVO" ? "Ativo" : "Encerrado"}
        </span>
      </section>

      <section className="reports-filters" aria-label="Filtros do relatório">
        <div className="reports-filters__heading">
          <div>
            <strong>Filtros</strong>
            <span>
              {filtrosAtivos > 0
                ? `${filtrosAtivos} filtro${filtrosAtivos === 1 ? "" : "s"} ativo${filtrosAtivos === 1 ? "" : "s"}`
                : "Visão completa do ciclo"}
            </span>
          </div>

          {filtrosAtivos > 0 && (
            <button
              type="button"
              className="reports-filters__clear"
              onClick={limparFiltros}
            >
              Limpar filtros
            </button>
          )}
        </div>

        <div className="reports-filters__grid">
          {usuarioAtual.funcao === "GERENTE" && (
            <label className="reports-filter-control">
              <span>Coordenação</span>
              <select
                value={coordenadorFiltro}
                onChange={(event) =>
                  setCoordenadorFiltro(event.target.value)
                }
              >
                <option value="">Todas</option>
                {coordenadoresDisponiveis.map((coordenador) => (
                  <option
                    key={coordenador.matricula}
                    value={coordenador.matricula}
                  >
                    {coordenador.nome}
                  </option>
                ))}
              </select>
            </label>
          )}

          <label className="reports-filter-control">
            <span>Cargo / senioridade</span>
            <select
              value={cargoFiltro}
              onChange={(event) => setCargoFiltro(event.target.value)}
            >
              <option value="">Todos</option>
              {usuarioAtual.funcao === "GERENTE" && (
                <>
                  <option value="COORDENADOR">Coordenador</option>
                  <option value="CONSULTOR">Consultor</option>
                </>
              )}
              <option value="ANALISTA_SENIOR">Analista Sênior</option>
              <option value="ANALISTA_PLENO">Analista Pleno</option>
              <option value="ANALISTA_JUNIOR">Analista Júnior</option>
              <option value="ESTAGIARIO">Estagiário</option>
            </select>
          </label>

          <label className="reports-filter-control">
            <span>Status</span>
            <select
              value={situacaoFiltro}
              onChange={(event) => setSituacaoFiltro(event.target.value)}
            >
              <option value="">Todos</option>
              <option value="NAO_INICIADA">Não iniciada</option>
              <option value="EM_ANDAMENTO">Em andamento</option>
              <option value="PRONTA_PARA_FEEDBACK">Pronta para Feedback</option>
              <option value="CONCLUIDA">Concluída</option>
              <option value="SUSPENSA">Suspensa</option>
              <option value="NAO_APLICAVEL">Não aplicável</option>
            </select>
          </label>

          <label className="reports-filter-control">
            <span>Faixa de nota</span>
            <select
              value={faixaFiltro}
              onChange={(event) => setFaixaFiltro(event.target.value)}
            >
              <option value="">Todas</option>
              {escalaRelatorio.map((item) => (
                <option key={item.nota} value={item.nota}>
                  {item.nota} — {item.significado}
                </option>
              ))}
            </select>
          </label>
        </div>
      </section>

      <section className="reports-kpis" aria-label="Indicadores gerais">
        <article className="reports-kpi reports-kpi--featured">
          <span>Média da equipe</span>
          <strong>{relatorio.mediaEquipe > 0 ? formatarNota(relatorio.mediaEquipe) : "—"}</strong>
          <small>{faixaMedia?.significado ?? "Sem nota consolidada"}</small>
        </article>
        <article className="reports-kpi">
          <span>Colaboradores</span>
          <strong>{relatorio.totalElegiveis}</strong>
          <small>no escopo do relatório</small>
        </article>
        <article className="reports-kpi">
          <span>Com nota consolidada</span>
          <strong>{relatorio.avaliacoesComNota}</strong>
          <small>prontas ou concluídas</small>
        </article>
        <article className="reports-kpi">
          <span>Concluídas</span>
          <strong>{relatorio.concluidas}</strong>
          <small>{relatorio.prontasParaFeedback} prontas para feedback</small>
        </article>
        <article className="reports-kpi">
          <span>Em andamento</span>
          <strong>{relatorio.emAndamento}</strong>
          <small>{relatorio.naoIniciadas} não iniciadas</small>
        </article>
      </section>

      <section className="reports-card reports-evolution-card">
        <div className="reports-card__heading reports-evolution-heading">
          <div>
            <h2>Evolução entre ciclos</h2>
            <p>
              {cicloAnterior
                ? `Comparação com ${cicloAnterior.ano} • Ciclo ${cicloAnterior.ciclo}.`
                : "Não existe ciclo anterior disponível para comparação."}
            </p>
          </div>
        </div>

        {comparacao.possuiComparacao ? (
          <div className="reports-evolution-layout">
            <aside className="reports-evolution-overview">
              <div className="reports-evolution-metric">
                <span>Média atual</span>
                <strong>{comparacao.mediaAtual > 0 ? formatarNota(comparacao.mediaAtual) : "—"}</strong>
              </div>

              <div className="reports-evolution-metric">
                <span>Média anterior</span>
                <strong>{comparacao.mediaAnterior > 0 ? formatarNota(comparacao.mediaAnterior) : "—"}</strong>
              </div>

              <div className="reports-evolution-metric reports-evolution-metric--highlight">
                <span>Evolução</span>
                <strong className={
                  comparacao.variacaoMedia === undefined
                    ? ""
                    : comparacao.variacaoMedia > 0.05
                    ? "is-positive"
                    : comparacao.variacaoMedia < -0.05
                    ? "is-negative"
                    : "is-neutral"
                }>
                  {comparacao.variacaoMedia === undefined
                    ? "—"
                    : `${comparacao.variacaoMedia > 0 ? "+" : ""}${formatarNota(comparacao.variacaoMedia)}`}
                </strong>
              </div>

              <div className="reports-evolution-people">
                <strong>{comparacao.comparaveis} colaboradores comparáveis</strong>
                <span className="is-positive">↑ {comparacao.melhoraram} melhoraram</span>
                <span className="is-neutral">→ {comparacao.mantiveram} mantiveram</span>
                <span className="is-negative">↓ {comparacao.pioraram} pioraram</span>
              </div>
            </aside>

            <div className="reports-evolution-criteria">
              <div className="reports-evolution-criteria__header">
                <span>Critério</span>
                <span>Anterior</span>
                <span>Atual</span>
                <span>Evolução</span>
              </div>
              {comparacao.criterios.map((criterio, criterioIndex) => (
                <div className="reports-evolution-criteria__row" key={criterio.criterioId}>
                  <div className="reports-evolution-criterion-name">
                    <span className="reports-evolution-criterion-icon">
                      <CriterionIcon index={criterioIndex} />
                    </span>
                    <strong>{criterio.criterioNome}</strong>
                  </div>
                  <span>{criterio.anterior > 0 ? formatarNota(criterio.anterior) : "—"}</span>
                  <span className="reports-evolution-current">
                    {criterio.atual > 0 ? formatarNota(criterio.atual) : "—"}
                  </span>
                  <span className={
                    criterio.variacao === undefined
                      ? ""
                      : criterio.variacao > 0.05
                      ? "is-positive"
                      : criterio.variacao < -0.05
                      ? "is-negative"
                      : "is-neutral"
                  }>
                    {criterio.variacao === undefined
                      ? "—"
                      : `${criterio.variacao > 0 ? "+" : ""}${formatarNota(criterio.variacao)}`}
                  </span>
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="reports-evolution-empty">
            Selecione um ciclo que possua um ciclo anterior para visualizar a evolução.
          </div>
        )}
      </section>

      <div className="reports-grid">
        <section className="reports-card">
          <div className="reports-card__heading">
            <div>
              <h2>Distribuição das notas</h2>
              <p>Faixas definidas na Régua de Notas.</p>
            </div>
          </div>

          <div className="reports-distribution">
            {relatorio.distribuicao.map((faixa) => (
              <div className="reports-distribution__row" key={faixa.nota}>
                <div className="reports-distribution__label">
                  <span
                    className="reports-score-dot"
                    style={{ background: faixa.corFundo, color: faixa.cor }}
                  >
                    {faixa.nota}
                  </span>
                  <div>
                    <strong>{faixa.significado}</strong>
                    <small>{faixa.quantidade} colaborador{faixa.quantidade === 1 ? "" : "es"}</small>
                  </div>
                </div>
                <div className="reports-bar">
                  <span style={{ width: `${faixa.percentual}%` }} />
                </div>
                <strong className="reports-distribution__percent">
                  {faixa.percentual.toFixed(0)}%
                </strong>
              </div>
            ))}
          </div>
        </section>

        <section className="reports-card">
          <div className="reports-card__heading">
            <div>
              <h2>Média por critério</h2>
              <p>Os 8 critérios oficiais da avaliação.</p>
            </div>
          </div>

          <div className="reports-criteria">
            {relatorio.criterios.map((criterio, criterioIndex) => {
              const aberto = criterioAbertoId === criterio.criterioId;

              return (
                <div
                  className={`reports-criterion-group${aberto ? " is-open" : ""}`}
                  key={criterio.criterioId}
                >
                  <button
                    type="button"
                    className="reports-criterion reports-criterion--interactive"
                    aria-expanded={aberto}
                    onClick={() =>
                      setCriterioAbertoId((atual) =>
                        atual === criterio.criterioId
                          ? null
                          : criterio.criterioId
                      )
                    }
                  >
                    <div className="reports-criterion__identity">
                      <span className="reports-criterion__icon">
                        <CriterionIcon index={criterioIndex} />
                      </span>
                      <div>
                        <strong>{criterio.criterioNome}</strong>
                        <small>
                          {criterio.quantidadeAvaliacoes} avaliação
                          {criterio.quantidadeAvaliacoes === 1 ? "" : "ões"}
                        </small>
                      </div>
                    </div>

                    <div className="reports-criterion__action">
                      <span className="reports-criterion__score">
                        {criterio.media > 0
                          ? formatarNota(criterio.media)
                          : "—"}
                      </span>
                      <span className="reports-criterion__chevron">
                        {aberto ? "−" : "+"}
                      </span>
                    </div>
                  </button>

                  {aberto &&
                    detalheCriterioAberto?.criterioId ===
                      criterio.criterioId && (
                      <RelatorioCriterioDetalhe
                        detalhe={detalheCriterioAberto}
                        criterioIndex={criterioIndex}
                      />
                    )}
                </div>
              );
            })}
          </div>
        </section>
      </div>

      <section className="reports-card reports-team-card">
        <div className="reports-card__heading reports-team-heading">
          <div>
            <h2>Desempenho da equipe</h2>
            <p>
              Notas aparecem somente quando a avaliação está pronta para feedback
              ou concluída. Evolução compara com o ciclo anterior disponível.
            </p>
          </div>
          <span>{relatorio.colaboradores.length} colaboradores</span>
        </div>

        <div className="reports-table-wrap">
          <div className="reports-table">
            <div className="reports-table__row reports-table__row--header">
              <div>Colaborador</div>
              <div>Status</div>
              <div>Nota</div>
              <div>Evolução</div>
              <div>Faixa</div>
              <div>Ações</div>
            </div>

            {relatorio.colaboradores.map((colaborador) => (
              <div className="reports-table__row" key={colaborador.matricula}>
                <div className="reports-person">
                  <div className="reports-avatar">
                    {colaborador.nome
                      .split(" ")
                      .filter(Boolean)
                      .slice(0, 2)
                      .map((parte) => parte[0])
                      .join("")
                      .toUpperCase()}
                  </div>
                  <div>
                    <strong>{colaborador.nome}</strong>
                    <span>{labelFuncao(colaborador.funcao, colaborador.senioridade)}</span>
                  </div>
                </div>

                <div data-label="Status">
                  <span className={`reports-status is-${colaborador.situacao.toLowerCase().replaceAll("_", "-")}`}>
                    {statusLabels[colaborador.situacao]}
                  </span>
                </div>

                <div data-label="Nota">
                  <strong className="reports-table-score">
                    {colaborador.possuiNotaConsolidada
                      ? formatarNota(colaborador.notaMedia)
                      : "—"}
                  </strong>
                </div>

                <div data-label="Evolução">
                  {(() => {
                    const evolucao = evolucaoPorMatricula.get(
                      colaborador.matricula
                    );

                    if (!evolucao) {
                      return <span className="reports-muted">—</span>;
                    }

                    const classe =
                      evolucao.tendencia === "MELHOROU"
                        ? "is-positive"
                        : evolucao.tendencia === "PIOROU"
                        ? "is-negative"
                        : "is-neutral";

                    const seta =
                      evolucao.tendencia === "MELHOROU"
                        ? "↑"
                        : evolucao.tendencia === "PIOROU"
                        ? "↓"
                        : "→";

                    return (
                      <span
                        className={`reports-individual-evolution ${classe}`}
                        title={`Ciclo anterior: ${formatarNota(
                          evolucao.notaAnterior
                        )} • Atual: ${formatarNota(evolucao.notaAtual)}`}
                      >
                        {seta}{" "}
                        {evolucao.variacao > 0 ? "+" : ""}
                        {formatarNota(evolucao.variacao)}
                      </span>
                    );
                  })()}
                </div>

                <div data-label="Faixa">
                  {colaborador.faixa ? (
                    <span
                      className="reports-range"
                      style={{
                        color: colaborador.faixa.cor,
                        background: colaborador.faixa.corFundo,
                      }}
                    >
                      {colaborador.faixa.significado}
                    </span>
                  ) : (
                    <span className="reports-muted">—</span>
                  )}
                </div>

                <div className="reports-actions">
                  <button
                    type="button"
                    className="virtus-btn virtus-btn--outline virtus-btn--small"
                    onClick={() =>
                      navigate(`/colaborador/${colaborador.matricula}`)
                    }
                  >
                    Abrir colaborador
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>
    </main>
  );
}

export default RelatoriosPage;
