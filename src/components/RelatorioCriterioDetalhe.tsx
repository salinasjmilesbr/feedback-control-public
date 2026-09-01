import CriterionIcon from "./CriterionIcon";
import { formatarNota } from "../services/escalaAvaliacaoStorage";
import type { RelatorioDetalheCriterio } from "../services/relatorioService";
import "../styles/relatorio-criterio-detalhe.css";

type Props = {
  detalhe: RelatorioDetalheCriterio;
  criterioIndex: number;
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
