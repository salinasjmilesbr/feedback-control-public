import { useNavigate, useParams } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import {
  getCiclosAvaliacao,
  formatarPeriodoCiclo,
} from "../services/cicloAvaliacaoStorage";
import {
  getPainelCiclo,
  type SituacaoAvaliacaoCiclo,
} from "../services/cicloEquipeService";

const labelsSituacao: Record<SituacaoAvaliacaoCiclo, string> = {
  NAO_INICIADA: "Não iniciada",
  EM_ANDAMENTO: "Em andamento",
  PRONTA_PARA_FEEDBACK: "Pronta para Feedback",
  CONCLUIDA: "Concluída",
};

function PainelCicloPage() {
  const { cicloId } = useParams();
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();

  if (!usuarioAtual || usuarioAtual.funcao !== "GERENTE") {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Acesso restrito</h1>
        <p>O painel do ciclo está disponível apenas para gerentes.</p>
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
          gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
          gap: "12px",
          marginTop: "22px",
        }}
      >
        {(
          [
            "NAO_INICIADA",
            "EM_ANDAMENTO",
            "PRONTA_PARA_FEEDBACK",
            "CONCLUIDA",
          ] as SituacaoAvaliacaoCiclo[]
        ).map((situacao) => (
          <div
            key={situacao}
            style={{
              border: "1px solid #ddd",
              borderRadius: "12px",
              padding: "16px",
              backgroundColor: "#fff",
            }}
          >
            <div style={{ color: "#666", fontSize: "13px" }}>
              {labelsSituacao[situacao]}
            </div>
            <div
              style={{
                marginTop: "6px",
                fontSize: "30px",
                fontWeight: "bold",
                color: "#660099",
              }}
            >
              {totais[situacao]}
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
          overflow: "hidden",
        }}
      >
        {linhas.length === 0 ? (
          <div style={{ padding: "20px", color: "#666" }}>
            Nenhum colaborador elegível na sua estrutura.
          </div>
        ) : (
          linhas.map((linha, index) => (
            <div
              key={linha.colaborador.matricula}
              style={{
                display: "grid",
                gridTemplateColumns:
                  "minmax(220px, 1fr) minmax(150px, auto) auto",
                gap: "14px",
                alignItems: "center",
                padding: "14px 16px",
                borderTop: index === 0 ? "none" : "1px solid #eee",
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
                    fontSize: "13px",
                  }}
                >
                  {linha.colaborador.funcao === "COORDENADOR"
                    ? "Coordenador"
                    : linha.colaborador.funcao === "CONSULTOR"
                    ? "Consultor"
                    : "Analista"}
                </div>
              </div>

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
                  Abrir avaliação
                </button>
              ) : (
                <span style={{ color: "#999", fontSize: "13px" }}>
                  Não criada
                </span>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
}

export default PainelCicloPage;
