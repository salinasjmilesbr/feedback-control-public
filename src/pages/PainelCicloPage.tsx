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
    return `Pendente (${progresso.preenchidos}/${progresso.total})`;
  }
  if (progresso.situacao === "EM_ANDAMENTO") {
    return `Em andamento (${progresso.preenchidos}/${progresso.total})`;
  }
  return `Não iniciado (0/${progresso.total})`;
}

function corPapel(progresso: ProgressoPapelPainel) {
  if (progresso.situacao === "CONCLUIDO") return "#107C41";
  if (progresso.situacao === "PENDENTE") return "#A4262C";
  if (progresso.situacao === "EM_ANDAMENTO") return "#8A6D00";
  if (progresso.situacao === "NAO_APLICA") return "#999";
  return "#555";
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
      <div style={{ padding: "30px" }}>
        <h1>Acesso restrito</h1>
        <p>
          O painel do ciclo está disponível para gerentes e coordenadores.
        </p>
      </div>
    );
  }

  const ciclo = getCiclosAvaliacao().find(
    (item) => item.id === cicloId
  );

  if (!ciclo) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Ciclo não encontrado</h1>
      </div>
    );
  }

  const linhas = getPainelCiclo(ciclo, usuarioAtual);

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

  const totalAvaliacoes = linhas.length;
  const avaliacoesComPendencias = linhas.filter(
    (linha) => linha.possuiPendencias
  ).length;

  return (
    <div
      style={{
        padding: "30px",
        maxWidth: "1100px",
        margin: "0 auto",
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          gap: "16px",
          flexWrap: "wrap",
        }}
      >
        <div>
          <h1 style={{ margin: 0 }}>
            {ciclo.ano} • Ciclo {ciclo.ciclo}
          </h1>
          <p style={{ margin: "6px 0 0 0", color: "#666" }}>
            {formatarPeriodoCiclo(ciclo.dataInicio, ciclo.dataFim)}
          </p>
        </div>

        <button
          type="button"
          onClick={() => navigate("/ciclos")}
          style={{
            padding: "10px 16px",
            borderRadius: "8px",
            border: "1px solid #660099",
            backgroundColor: "#fff",
            color: "#660099",
            cursor: "pointer",
            fontWeight: "bold",
          }}
        >
          ← Ciclos
        </button>
      </div>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))",
          gap: "12px",
          marginTop: "22px",
        }}
      >
        {[
          { label: "Total", valor: totalAvaliacoes },
          { label: "Não iniciadas", valor: totais.NAO_INICIADA },
          { label: "Em andamento", valor: totais.EM_ANDAMENTO },
          {
            label: "Prontas para Feedback",
            valor: totais.PRONTA_PARA_FEEDBACK,
          },
          { label: "Concluídas", valor: totais.CONCLUIDA },
          { label: "Com pendências", valor: avaliacoesComPendencias },
        ].map((indicador) => (
          <div
            key={indicador.label}
            style={{
              border: "1px solid #ddd",
              borderRadius: "12px",
              padding: "16px",
              backgroundColor: "#fff",
            }}
          >
            <div style={{ color: "#666", fontSize: "13px" }}>
              {indicador.label}
            </div>
            <div
              style={{
                marginTop: "6px",
                fontSize: "30px",
                fontWeight: "bold",
                color: "#660099",
              }}
            >
              {indicador.valor}
            </div>
          </div>
        ))}
      </div>

      <div
        style={{
          marginTop: "22px",
          border: "1px solid #ddd",
          borderRadius: "12px",
          backgroundColor: "#fff",
          overflowX: "auto",
        }}
      >
        {linhas.length === 0 ? (
          <div style={{ padding: "20px", color: "#666" }}>
            Nenhum colaborador elegível na sua estrutura.
          </div>
        ) : (
          <div style={{ minWidth: "980px" }}>
            <div
              style={{
                display: "grid",
                gridTemplateColumns:
                  "minmax(220px, 1.4fr) minmax(150px, 1fr) minmax(150px, 1fr) minmax(150px, 1fr) minmax(170px, 1fr) 130px",
                gap: "12px",
                padding: "12px 16px",
                backgroundColor: "#F7F7F7",
                borderBottom: "1px solid #ddd",
                fontSize: "12px",
                fontWeight: "bold",
                color: "#555",
              }}
            >
              <div>Colaborador</div>
              <div>Gerente</div>
              <div>Coordenador</div>
              <div>Colegiado</div>
              <div>Status geral</div>
              <div></div>
            </div>

            {linhas.map((linha) => (
              <div
                key={linha.colaborador.matricula}
                style={{
                  display: "grid",
                  gridTemplateColumns:
                    "minmax(220px, 1.4fr) minmax(150px, 1fr) minmax(150px, 1fr) minmax(150px, 1fr) minmax(170px, 1fr) 130px",
                  gap: "12px",
                  alignItems: "center",
                  padding: "14px 16px",
                  borderBottom: "1px solid #eee",
                }}
              >
                <div>
                  <div style={{ fontWeight: "bold" }}>
                    {linha.colaborador.nome}
                  </div>
                  <div
                    style={{
                      marginTop: "4px",
                      color: "#666",
                      fontSize: "12px",
                    }}
                  >
                    {linha.colaborador.funcao === "COORDENADOR"
                      ? "Coordenador"
                      : linha.colaborador.funcao === "CONSULTOR"
                      ? "Consultor"
                      : "Analista"}
                  </div>
                </div>

                {[linha.gerente, linha.coordenador, linha.colegiado].map(
                  (progresso, indice) => (
                    <div
                      key={indice}
                      style={{
                        color: corPapel(progresso),
                        fontWeight:
                          progresso.situacao === "PENDENTE" ||
                          progresso.situacao === "CONCLUIDO"
                            ? "bold"
                            : "normal",
                        fontSize: "13px",
                      }}
                    >
                      {labelPapel(progresso)}
                    </div>
                  )
                )}

                <div>
                  <div
                    style={{
                      fontWeight: "bold",
                      color:
                        linha.situacao === "CONCLUIDA"
                          ? "#107C41"
                          : linha.situacao === "PRONTA_PARA_FEEDBACK"
                          ? "#8A6D00"
                          : "#555",
                    }}
                  >
                    {labelsSituacao[linha.situacao]}
                  </div>
                  {linha.feedback?.encerradaComPendencias && (
                    <div
                      style={{
                        marginTop: "4px",
                        color: "#A4262C",
                        fontSize: "12px",
                        fontWeight: "bold",
                      }}
                    >
                      Encerrada com pendências
                    </div>
                  )}
                </div>

                {linha.feedback ? (
                  <button
                    type="button"
                    onClick={() =>
                      navigate(
                        `/colaborador/${linha.colaborador.matricula}/feedback/${linha.feedback!.id}/editar`
                      )
                    }
                    style={{
                      padding: "8px 12px",
                      borderRadius: "8px",
                      border: "1px solid #660099",
                      backgroundColor: "#fff",
                      color: "#660099",
                      cursor: "pointer",
                      fontWeight: "bold",
                    }}
                  >
                    Abrir
                  </button>
                ) : (
                  <span style={{ color: "#999", fontSize: "13px" }}>
                    Não criada
                  </span>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export default PainelCicloPage;
