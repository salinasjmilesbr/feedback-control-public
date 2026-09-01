import CriterionIcon from "./CriterionIcon";
import { formatarNota } from "../services/escalaAvaliacaoStorage";
import type {
  RelatorioDetalheCriterio,
  RelatorioHistoricoCriterio,
} from "../services/relatorioService";
import "../styles/relatorio-criterio-detalhe.css";

type Props = {
  detalhe: RelatorioDetalheCriterio;
  criterioIndex: number;
  historico: RelatorioHistoricoCriterio;
};

function labelCargo(
  funcao: RelatorioDetalheCriterio["colaboradores"][number]["funcao"],
  senioridade: RelatorioDetalheCriterio["colaboradores"][number]["senioridade"]
) {
  if (funcao === "COORDENADOR") return "Coordenador";
  if (funcao === "CONSULTOR") return "Consultor";
  if (funcao === "ESTAGIARIO") return "Estagiário";
  if (funcao === "ANALISTA" && senioridade === "SENIOR") return "Analista Sênior";
  if (funcao === "ANALISTA" && senioridade === "PLENO") return "Analista Pleno";
  if (funcao === "ANALISTA" && senioridade === "JUNIOR") return "Analista Júnior";
  return "Analista";
}

function classeVariacao(variacao: number | undefined) {
  if (variacao === undefined) return "";
  if (variacao > 0.05) return "is-positive";
  if (variacao < -0.05) return "is-negative";
  return "is-neutral";
}

function setaVariacao(variacao: number | undefined) {
  if (variacao === undefined) return "";
  if (variacao > 0.05) return "↑";
  if (variacao < -0.05) return "↓";
  return "→";
}

export default function RelatorioCriterioDetalhe({
  detalhe,
  criterioIndex,
  historico,
}: Props) {
  return (
    <div className="criterion-drilldown">
      <div className="criterion-drilldown__summary">
        <div className="criterion-drilldown__identity">
          <span className="criterion-drilldown__icon">
            <CriterionIcon index={criterioIndex} />
          </span>
          <div>
            <strong>{detalhe.criterioNome}</strong>
            <span>{detalhe.quantidadeAvaliacoes} avaliações no filtro atual</span>
          </div>
        </div>

        <div className="criterion-drilldown__metrics">
          <div>
            <span>Média atual</span>
            <strong>
              {detalhe.mediaAtual > 0 ? formatarNota(detalhe.mediaAtual) : "—"}
            </strong>
          </div>
          <div>
            <span>Média anterior</span>
            <strong>
              {detalhe.mediaAnterior !== undefined
                ? formatarNota(detalhe.mediaAnterior)
                : "—"}
            </strong>
          </div>
          <div>
            <span>Evolução</span>
            <strong className={classeVariacao(detalhe.variacaoMedia)}>
              {detalhe.variacaoMedia === undefined
                ? "—"
                : `${setaVariacao(detalhe.variacaoMedia)} ${detalhe.variacaoMedia > 0 ? "+" : ""}${formatarNota(detalhe.variacaoMedia)}`}
            </strong>
          </div>
        </div>
      </div>

      <div className="criterion-drilldown__history">
        <div className="criterion-drilldown__history-heading">
          <strong>Tendência histórica</strong>
          <span>Evolução deste critério até o ciclo selecionado.</span>
        </div>

        <div className="criterion-history-chart-wrap">
          {(() => {
            const width = 680;
            const height = 190;
            const left = 48;
            const right = 48;
            const top = 24;
            const bottom = 38;
            const chartWidth = width - left - right;
            const chartHeight = height - top - bottom;
            const pontos = historico.pontos;

            const x = (index: number) =>
              pontos.length <= 1
                ? left + chartWidth / 2
                : left + (index / (pontos.length - 1)) * chartWidth;

            const y = (media: number) =>
              top + ((5 - media) / 4) * chartHeight;

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

            const posicaoX = (index: number) =>
              `${(x(index) / width) * 100}%`;

            const posicaoY = (media: number) =>
              `${(y(media) / height) * 100}%`;

            return (
              <div
                className="criterion-history-chart-stage"
                role="img"
                aria-label={`Tendência histórica de ${historico.criterioNome}`}
              >
                <svg
                  className="criterion-history-chart"
                  viewBox={`0 0 ${width} ${height}`}
                  aria-hidden="true"
                >
                  {[1, 2, 3, 4, 5].map((nota) => {
                    const gridY = y(nota);

                    return (
                      <line
                        className="criterion-history-chart__grid"
                        key={nota}
                        x1={left}
                        x2={width - right}
                        y1={gridY}
                        y2={gridY}
                      />
                    );
                  })}

                  {segmentos.map((segmento, index) => (
                    <line
                      className="criterion-history-chart__line"
                      key={index}
                      x1={segmento.x1}
                      y1={segmento.y1}
                      x2={segmento.x2}
                      y2={segmento.y2}
                    />
                  ))}

                  {pontos.map((ponto, index) =>
                    ponto.media !== null ? (
                      <circle
                        className="criterion-history-chart__point"
                        key={ponto.cicloId}
                        cx={x(index)}
                        cy={y(ponto.media)}
                        r="4.5"
                      />
                    ) : null
                  )}
                </svg>

                <div
                  className="criterion-history-chart__y-axis"
                  aria-hidden="true"
                >
                  {[5, 4, 3, 2, 1].map((nota) => (
                    <span
                      key={nota}
                      style={{ top: `${(y(nota) / height) * 100}%` }}
                    >
                      {nota}
                    </span>
                  ))}
                </div>

                {pontos.map((ponto, index) => (
                  <div
                    className="criterion-history-chart__cycle"
                    key={`cycle-${ponto.cicloId}`}
                    style={{ left: posicaoX(index) }}
                  >
                    {ponto.ano} • C{ponto.ciclo}
                  </div>
                ))}

                {pontos.map((ponto, index) =>
                  ponto.media !== null ? (
                    <div
                      className="criterion-history-chart__value"
                      key={`value-${ponto.cicloId}`}
                      style={{
                        left: posicaoX(index),
                        top: posicaoY(ponto.media),
                      }}
                    >
                      {formatarNota(ponto.media)}
                    </div>
                  ) : null
                )}
              </div>
            );
          })()}
        </div>
      </div>

      {detalhe.colaboradores.length === 0 ? (
        <div className="criterion-drilldown__empty">
          Nenhum colaborador com nota consolidada para este critério.
        </div>
      ) : (
        <div className="criterion-drilldown__list">
          <div className="criterion-drilldown__header" aria-hidden="true">
            <span>Colaborador</span>
            <span>Cargo</span>
            <span>Nota</span>
            <span>Evolução</span>
          </div>

          {detalhe.colaboradores.map((colaborador) => (
            <div
              className="criterion-drilldown__row"
              key={colaborador.matricula}
            >
              <div className="criterion-drilldown__person">
                <strong>{colaborador.nome}</strong>
              </div>

              <div data-label="Cargo">
                {labelCargo(colaborador.funcao, colaborador.senioridade)}
              </div>

              <div data-label="Nota">
                <strong>{formatarNota(colaborador.notaAtual)}</strong>
              </div>

              <div data-label="Evolução">
                {colaborador.variacao === undefined ? (
                  <span className="criterion-drilldown__muted">—</span>
                ) : (
                  <strong
                    className={`criterion-drilldown__variation ${classeVariacao(
                      colaborador.variacao
                    )}`}
                    title={`Anterior: ${formatarNota(
                      colaborador.notaAnterior ?? 0
                    )} • Atual: ${formatarNota(colaborador.notaAtual)}`}
                  >
                    {setaVariacao(colaborador.variacao)}{" "}
                    {colaborador.variacao > 0 ? "+" : ""}
                    {formatarNota(colaborador.variacao)}
                  </strong>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
