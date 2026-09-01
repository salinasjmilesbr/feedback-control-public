import { formatarNota } from "../services/escalaAvaliacaoStorage";
import type { RelatorioHistoricoCiclos } from "../services/relatorioService";
import "../styles/relatorio-historico-ciclos.css";

type Props = {
  historico: RelatorioHistoricoCiclos;
};

const VIEWBOX_WIDTH = 760;
const VIEWBOX_HEIGHT = 230;
const LEFT = 48;
const RIGHT = 22;
const TOP = 24;
const BOTTOM = 48;
const CHART_WIDTH = VIEWBOX_WIDTH - LEFT - RIGHT;
const CHART_HEIGHT = VIEWBOX_HEIGHT - TOP - BOTTOM;

function classeVariacao(valor: number | null) {
  if (valor === null) return "";
  if (valor > 0.05) return "is-positive";
  if (valor < -0.05) return "is-negative";
  return "is-neutral";
}

function textoVariacao(valor: number | null) {
  if (valor === null) return "—";
  const seta = valor > 0.05 ? "↑" : valor < -0.05 ? "↓" : "→";
  return `${seta} ${valor > 0 ? "+" : ""}${formatarNota(valor)}`;
}

export default function RelatorioHistoricoCiclos({ historico }: Props) {
  const pontos = historico.pontos;

  const x = (index: number) =>
    pontos.length <= 1
      ? LEFT + CHART_WIDTH / 2
      : LEFT + (index / (pontos.length - 1)) * CHART_WIDTH;

  const y = (media: number) =>
    TOP + ((5 - media) / 4) * CHART_HEIGHT;

  const segmentos = pontos.flatMap((ponto, index) => {
    if (index === 0) return [];

    const anterior = pontos[index - 1];
    if (ponto.media === null || anterior.media === null) return [];

    return [
      {
        x1: x(index - 1),
        y1: y(anterior.media),
        x2: x(index),
        y2: y(ponto.media),
      },
    ];
  });

  return (
    <section className="reports-card history-cycles-card">
      <div className="reports-card__heading history-cycles-card__heading">
        <div>
          <h2>Tendência da equipe</h2>
          <p>
            Evolução da média ao longo dos ciclos até o ciclo selecionado.
          </p>
        </div>
        <span>{pontos.length} ciclos no histórico</span>
      </div>

      {pontos.length === 0 ? (
        <div className="history-cycles-empty">
          Nenhum ciclo disponível para o histórico.
        </div>
      ) : (
        <>
          <div className="history-cycles-chart-wrap">
            <svg
              className="history-cycles-chart"
              viewBox={`0 0 ${VIEWBOX_WIDTH} ${VIEWBOX_HEIGHT}`}
              role="img"
              aria-label="Tendência histórica da média da equipe"
            >
              {[1, 2, 3, 4, 5].map((nota) => {
                const gridY = y(nota);

                return (
                  <g key={nota}>
                    <line
                      className="history-cycles-chart__grid"
                      x1={LEFT}
                      x2={VIEWBOX_WIDTH - RIGHT}
                      y1={gridY}
                      y2={gridY}
                    />
                    <text
                      className="history-cycles-chart__axis"
                      x={LEFT - 14}
                      y={gridY + 4}
                      textAnchor="end"
                    >
                      {nota}
                    </text>
                  </g>
                );
              })}

              {segmentos.map((segmento, index) => (
                <line
                  className="history-cycles-chart__line"
                  key={index}
                  x1={segmento.x1}
                  y1={segmento.y1}
                  x2={segmento.x2}
                  y2={segmento.y2}
                />
              ))}

              {pontos.map((ponto, index) => {
                const pointX = x(index);

                return (
                  <g key={ponto.cicloId}>
                    {ponto.media !== null && (
                      <>
                        <circle
                          className="history-cycles-chart__point"
                          cx={pointX}
                          cy={y(ponto.media)}
                          r="5"
                        />
                        <text
                          className="history-cycles-chart__value"
                          x={pointX}
                          y={y(ponto.media) - 11}
                          textAnchor="middle"
                        >
                          {formatarNota(ponto.media)}
                        </text>
                      </>
                    )}

                    <text
                      className="history-cycles-chart__label"
                      x={pointX}
                      y={VIEWBOX_HEIGHT - 17}
                      textAnchor="middle"
                    >
                      {ponto.ano} • C{ponto.ciclo}
                    </text>
                  </g>
                );
              })}
            </svg>
          </div>

          <div className="history-cycles-table">
            <div className="history-cycles-table__header" aria-hidden="true">
              <span>Ciclo</span>
              <span>Média</span>
              <span>Variação</span>
              <span>Avaliações</span>
            </div>

            {pontos.map((ponto) => (
              <div className="history-cycles-table__row" key={ponto.cicloId}>
                <div>
                  <strong>
                    {ponto.ano} • Ciclo {ponto.ciclo}
                  </strong>
                  <small>{ponto.status === "ATIVO" ? "Ativo" : "Encerrado"}</small>
                </div>

                <div data-label="Média">
                  <strong>
                    {ponto.media !== null ? formatarNota(ponto.media) : "—"}
                  </strong>
                </div>

                <div data-label="Variação">
                  <strong className={classeVariacao(ponto.variacao)}>
                    {textoVariacao(ponto.variacao)}
                  </strong>
                </div>

                <div data-label="Avaliações">
                  {ponto.quantidadeAvaliacoes}
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </section>
  );
}
