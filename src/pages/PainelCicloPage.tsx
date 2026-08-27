import { useNavigate, useParams } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import {
  getCiclosAvaliacao,
  formatarPeriodoCiclo,
} from "../services/cicloAvaliacaoStorage";
import {
  getPainelCiclo,
  type ProgressoPapelPainel,
  type SituacaoAvaliacaoCiclo,
} from "../services/cicloEquipeService";
import "../styles/ciclos.css";
import "../styles/equipe-colegiado.css";

const labelsSituacao: Record<SituacaoAvaliacaoCiclo, string> = {
  NAO_INICIADA: "Não iniciada",
  EM_ANDAMENTO: "Em andamento",
  PRONTA_PARA_FEEDBACK: "Pronta para Feedback",
  CONCLUIDA: "Concluída",
};

function labelPapel(progresso: ProgressoPapelPainel) {
  if (progresso.situacao === "NAO_APLICA") return "—";
  if (progresso.situacao === "CONCLUIDO") return "Concluído";
  if (progresso.situacao === "PENDENTE") {
    return `Pendente ${progresso.preenchidos}/${progresso.total}`;
  }
  if (progresso.situacao === "EM_ANDAMENTO") {
    return `Em andamento ${progresso.preenchidos}/${progresso.total}`;
  }
  return `Não iniciado 0/${progresso.total}`;
}

function classePapel(progresso: ProgressoPapelPainel) {
  if (progresso.situacao === "CONCLUIDO") return "is-complete";
  if (progresso.situacao === "PENDENTE") return "is-pending";
  if (progresso.situacao === "EM_ANDAMENTO") return "is-progress";
  if (progresso.situacao === "NAO_APLICA") return "is-na";
  return "is-not-started";
}

function PainelCicloPage() {
  const { cicloId } = useParams();
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();

  if (
    !usuarioAtual ||
    (usuarioAtual.funcao !== "GERENTE" &&
      usuarioAtual.funcao !== "COORDENADOR")
  ) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Acesso restrito</h1>
          <p>O painel do ciclo está disponível para gerentes e coordenadores.</p>
        </section>
      </main>
    );
  }

  const ciclo = getCiclosAvaliacao().find((item) => item.id === cicloId);

  if (!ciclo) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Ciclo não encontrado</h1>
        </section>
      </main>
    );
  }

  const linhas = getPainelCiclo(ciclo, usuarioAtual);

  const separarPorVinculo = usuarioAtual.funcao === "COORDENADOR";

  const linhasEquipeDireta = separarPorVinculo
    ? linhas.filter(
        (linha) =>
          linha.colaborador.gestorDiretoMatricula === usuarioAtual.matricula
      )
    : linhas;

  const linhasColegiado = separarPorVinculo
    ? linhas.filter(
        (linha) =>
          linha.colaborador.gestorDiretoMatricula !== usuarioAtual.matricula
      )
    : [];

  const totais = linhas.reduce(
    (acc, linha) => {
      acc[linha.situacao] += 1;
      return acc;
    },
    {
      NAO_INICIADA: 0,
      EM_ANDAMENTO: 0,
      PRONTA_PARA_FEEDBACK: 0,
      CONCLUIDA: 0,
    } as Record<SituacaoAvaliacaoCiclo, number>
  );

  const indicadores = [
    { label: "Total", valor: linhas.length },
    { label: "Não iniciadas", valor: totais.NAO_INICIADA },
    { label: "Em andamento", valor: totais.EM_ANDAMENTO },
    { label: "Prontas p/ feedback", valor: totais.PRONTA_PARA_FEEDBACK },
    { label: "Concluídas", valor: totais.CONCLUIDA },
    {
      label: "Com pendências",
      valor: linhas.filter((linha) => linha.possuiPendencias).length,
    },
  ];

  function renderTabelaGrupo(
    linhasGrupo: typeof linhas,
    titulo: string,
    descricao: string,
    eyebrow: string
  ) {
    return (
      <section className="cycle-table-card cycle-team-group">
        <div className="cycle-table-heading">
          <div>
            <span className="cycle-eyebrow">{eyebrow}</span>
            <h2>{titulo}</h2>
            <p className="cycle-team-group__description">{descricao}</p>
          </div>
          <span>{linhasGrupo.length} colaboradores</span>
        </div>

        {linhasGrupo.length === 0 ? (
          <div className="cycle-empty cycle-team-group__empty">
            <p>Nenhum colaborador neste grupo.</p>
          </div>
        ) : (
          <div className="cycle-table-wrap">
            <div className="cycle-table">
              <div className="cycle-table__row cycle-table__row--header">
                <div>Colaborador</div>
                <div>Gerente</div>
                <div>Coordenador</div>
                <div>Colegiado</div>
                <div>Status geral</div>
                <div></div>
              </div>

              {linhasGrupo.map((linha) => (
                <div
                  className="cycle-table__row"
                  key={linha.colaborador.matricula}
                >
                  <div className="cycle-person">
                    <div className="cycle-person__avatar">
                      {linha.colaborador.nome
                        .split(" ")
                        .filter(Boolean)
                        .slice(0, 2)
                        .map((p) => p[0])
                        .join("")
                        .toUpperCase()}
                    </div>
                    <div>
                      <strong>{linha.colaborador.nome}</strong>
                      <span>
                        {linha.colaborador.funcao === "COORDENADOR"
                          ? "Coordenador"
                          : linha.colaborador.funcao === "CONSULTOR"
                          ? "Consultor"
                          : "Analista"}
                      </span>
                    </div>
                  </div>

                  {[linha.gerente, linha.coordenador, linha.colegiado].map(
                    (progresso, indice) => (
                      <span
                        key={indice}
                        className={`cycle-progress ${classePapel(progresso)}`}
                      >
                        {labelPapel(progresso)}
                      </span>
                    )
                  )}

                  <div>
                    <span
                      className={`cycle-general-status ${
                        linha.situacao === "CONCLUIDA"
                          ? "is-complete"
                          : linha.situacao === "PRONTA_PARA_FEEDBACK"
                          ? "is-feedback"
                          : linha.situacao === "EM_ANDAMENTO"
                          ? "is-progress"
                          : "is-not-started"
                      }`}
                    >
                      {labelsSituacao[linha.situacao]}
                    </span>
                    {linha.feedback?.encerradaComPendencias && (
                      <small className="cycle-danger-text">
                        Encerrada com pendências
                      </small>
                    )}
                  </div>

                  {linha.feedback ? (
                    <button
                      className="cycle-btn cycle-btn--small cycle-btn--secondary"
                      onClick={() =>
                        navigate(
                          `/colaborador/${linha.colaborador.matricula}/feedback/${linha.feedback!.id}/editar`
                        )
                      }
                    >
                      Abrir
                    </button>
                  ) : (
                    <span className="cycle-muted">Não criada</span>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}
      </section>
    );
  }

  return (
    <main className="virtus-page cycle-panel-page">
      <section className="cycle-page-header">
        <div>
          <button
            className="cycle-back-link"
            onClick={() =>
              navigate(
                usuarioAtual.funcao === "COORDENADOR"
                  ? "/painel-ciclos"
                  : "/ciclos"
              )
            }
          >
            ← Voltar aos ciclos
          </button>
          <h1>
            {ciclo.ano} <span>•</span> Ciclo {ciclo.ciclo}
          </h1>
          <p>{formatarPeriodoCiclo(ciclo.dataInicio, ciclo.dataFim)}</p>
        </div>

        <span
          className={`cycle-status ${
            ciclo.status === "ATIVO"
              ? "is-active"
              : ciclo.encerradoComPendencias
              ? "is-warning"
              : "is-closed"
          }`}
        >
          {ciclo.status === "ATIVO"
            ? "Ativo"
            : ciclo.encerradoComPendencias
            ? "Encerrado com pendências"
            : "Encerrado"}
        </span>
      </section>

      <section className="cycle-kpis">
        {indicadores.map((indicador) => (
          <div className="cycle-kpi" key={indicador.label}>
            <span>{indicador.label}</span>
            <strong>{indicador.valor}</strong>
          </div>
        ))}
      </section>

      {separarPorVinculo ? (
        <div className="cycle-team-groups">
          {renderTabelaGrupo(
            linhasEquipeDireta,
            "Minha equipe direta",
            "Colaboradores que respondem diretamente para você neste ciclo.",
            "Responsabilidade direta"
          )}
          {renderTabelaGrupo(
            linhasColegiado,
            "Avaliações como colegiado",
            "Colaboradores de outras equipes em que você participa como avaliador do colegiado.",
            "Participação adicional"
          )}
        </div>
      ) : (
        renderTabelaGrupo(
          linhas,
          "Equipe no ciclo",
          "Acompanhamento das avaliações elegíveis na estrutura.",
          "Acompanhamento"
        )
      )}
    </main>
  );
}

export default PainelCicloPage;

