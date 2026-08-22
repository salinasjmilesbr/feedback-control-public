import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { colaboradores } from "../data/colaboradores";
import {
  deleteFeedback,
  getFeedbacksByColaborador,
} from "../services/feedbackStorage";

function FeedbackDetalhePage() {
  const navigate = useNavigate();
  const { id, feedbackId } = useParams();
  const [criterioAberto, setCriterioAberto] = useState<string>("");
  const [feedbackFinalAberto, setFeedbackFinalAberto] = useState(false);

  const colaborador = colaboradores.find(
    (item) => item.matricula.toString() === id
  );

  if (!colaborador) {
    return (
      <div style={{ padding: "30px" }}>
        <button
          onClick={() => navigate(-1)}
          style={{
            marginBottom: "20px",
            padding: "10px 16px",
            borderRadius: "8px",
            border: "1px solid #660099",
            backgroundColor: "#fff",
            color: "#660099",
            cursor: "pointer",
            fontWeight: "bold",
          }}
        >
          ← Voltar
        </button>

        <h1>Colaborador não encontrado</h1>
      </div>
    );
  }

  const feedbacks = getFeedbacksByColaborador(colaborador.matricula);
  const feedback = feedbacks.find((item) => item.id === feedbackId);

  if (!feedback) {
    return (
      <div style={{ padding: "30px" }}>
        <button
          onClick={() => navigate(`/colaborador/${colaborador.matricula}`)}
          style={{
            marginBottom: "20px",
            padding: "10px 16px",
            borderRadius: "8px",
            border: "1px solid #660099",
            backgroundColor: "#fff",
            color: "#660099",
            cursor: "pointer",
            fontWeight: "bold",
          }}
        >
          ← Voltar
        </button>

        <h1>Feedback não encontrado</h1>
      </div>
    );
  }

  const criteriosDetalhados = feedback.criteriosDetalhados ?? [];
  const feedbackFinalGerente = feedback.feedbackFinalGerente ?? "";
  const feedbackFinalCoordenador = feedback.feedbackFinalCoordenador ?? "";

  const totalFeedbacksFinaisPreenchidos = [
    feedbackFinalGerente,
    feedbackFinalCoordenador,
  ].filter((texto) => texto.trim().length > 0).length;

  const statusFeedbackFinal =
    totalFeedbacksFinaisPreenchidos === 0
      ? "Pendente"
      : `${totalFeedbacksFinaisPreenchidos} comentário${
          totalFeedbacksFinaisPreenchidos > 1 ? "s" : ""
        } preenchido${totalFeedbacksFinaisPreenchidos > 1 ? "s" : ""}`;

  function handleExcluirFeedback() {
    const confirmar = window.confirm("Deseja realmente excluir este feedback?");

    if (!confirmar) {
      return;
    }

    deleteFeedback(feedback!.id);
    alert("Feedback excluído com sucesso.");
    navigate(`/colaborador/${colaborador!.matricula}`);
  }

  return (
    <div style={{ padding: "30px" }}>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          marginBottom: "30px",
        }}
      >
        <button
          onClick={() => navigate(`/colaborador/${colaborador.matricula}`)}
          style={{
            padding: "10px 16px",
            borderRadius: "8px",
            border: "1px solid #660099",
            backgroundColor: "#fff",
            color: "#660099",
            cursor: "pointer",
            fontWeight: "bold",
            marginTop: "3px",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          ← Voltar
        </button>

        <h1
          style={{
            flex: 1,
            margin: 0,
            textAlign: "center",
            fontSize: "36px",
          }}
        >
          Detalhes da Avaliação
        </h1>

        <div style={{ width: "100px" }}></div>
      </div>

      <div
        style={{
          border: "1px solid #ddd",
          borderRadius: "10px",
          padding: "20px",
          marginBottom: "20px",
          backgroundColor: "#fff",
        }}
      >
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            gap: "20px",
          }}
        >
          <div style={{ flex: 1, textAlign: "left" }}>
            <h2
              style={{
                margin: 0,
                marginBottom: "12px",
                color: "#660099",
                textAlign: "left",
              }}
            >
              {colaborador.nome}
            </h2>
            <p style={{ margin: "0 0 8px 0", textAlign: "left" }}>
              <strong>Matrícula:</strong> {colaborador.matricula}
            </p>
            <p style={{ margin: "0 0 8px 0", textAlign: "left" }}>
              <strong>Área:</strong> {colaborador.area}
            </p>
            <p style={{ margin: 0, textAlign: "left" }}>
              <strong>Data da avaliação:</strong>{" "}
              {new Date(feedback.data).toLocaleDateString("pt-BR")}
            </p>
            <div
              style={{
                marginTop: "12px",
                display: "inline-flex",
                alignItems: "center",
                gap: "6px",
                padding: "4px 10px",
                borderRadius: "999px",
                backgroundColor:
                  feedback.status === "CONCLUIDA"
                    ? "#E7F6EC"
                    : feedback.status === "PRONTA_PARA_FEEDBACK"
                    ? "#FFF4CE"
                    : "#F4E8FF",
                color:
                  feedback.status === "CONCLUIDA"
                    ? "#107C41"
                    : feedback.status === "PRONTA_PARA_FEEDBACK"
                    ? "#8A6D00"
                    : "#660099",
                fontSize: "12px",
                fontWeight: "bold",
              }}
            >
              {feedback.status === "RASCUNHO" && "📝 Rascunho"}
              {feedback.status === "PRONTA_PARA_FEEDBACK" &&
                "🎯 Pronta para Feedback"}
              {feedback.status === "CONCLUIDA" && "✅ Concluída"}
            </div>
          </div>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              justifyContent: "center",
              alignItems: "flex-end",
              gap: "12px",
            }}
          >
            <span style={{ fontWeight: "bold" }}>
              {colaborador.ativo ? "✅ Ativo" : "❌ Inativo"}
            </span>

            <button
              type="button"
              onClick={() =>
                navigate(
                  `/colaborador/${colaborador.matricula}/feedback/${feedback.id}/editar`
                )
              }
              style={{
                padding: "10px 18px",
                borderRadius: "10px",
                border: "none",
                cursor: "pointer",
                backgroundColor: "#660099",
                color: "#fff",
                fontWeight: "bold",
              }}
            >
              ✏️ Editar Avaliação
            </button>

            <button
              type="button"
              onClick={handleExcluirFeedback}
              style={{
                padding: "10px 18px",
                borderRadius: "10px",
                border: "1px solid #A80000",
                cursor: "pointer",
                backgroundColor: "#fff",
                color: "#A80000",
                fontWeight: "bold",
              }}
            >
              🗑 Excluir Avaliação
            </button>
          </div>
        </div>
      </div>

      <div
        style={{
          marginTop: "20px",
          border: "1px solid #660099",
          borderRadius: "12px",
          padding: "20px",
          backgroundColor: "#fff",
          textAlign: "center",
        }}
      >
        <h3 style={{ marginTop: 0 }}>Resumo da Avaliação</h3>

        {criteriosDetalhados.length > 0 ? (
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
              gap: "16px",
              marginTop: "20px",
            }}
          >
            {criteriosDetalhados.map((criterio) => (
              <div
                key={criterio.criterioId}
                style={{
                  border: "1px solid #eee",
                  borderRadius: "12px",
                  padding: "16px",
                  backgroundColor: "#F8FBFF",
                }}
              >
                <div style={{ fontSize: "14px", color: "#555" }}>
                  {criterio.criterioNome}
                </div>
                <div
                  style={{
                    marginTop: "8px",
                    fontSize: "28px",
                    fontWeight: "bold",
                    color: "#0078D4",
                  }}
                >
                  {criterio.nota.toFixed(2)}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p style={{ color: "#555" }}>
            Esta avaliação foi salva em um modelo anterior e não possui detalhes por critério.
          </p>
        )}

        <div
          style={{
            marginTop: "24px",
            paddingTop: "20px",
            borderTop: "1px solid #ddd",
          }}
        >
          <div style={{ fontSize: "16px", color: "#555" }}>Nota Final</div>
          <div
            style={{
              marginTop: "8px",
              fontSize: "36px",
              fontWeight: "bold",
              color: "#660099",
            }}
          >
            {feedback.notaMedia.toFixed(2)}
          </div>
        </div>
      </div>

      {criteriosDetalhados.map((criterio) => {
        const estaAberto = criterioAberto === criterio.criterioId;
        const subcriteriosAvaliadosDoCriterio = criterio.subcriterios.filter(
          (subcriterio) =>
            subcriterio.notaGerente > 0 &&
            subcriterio.notaCoordenador > 0 &&
            subcriterio.notaColegiado > 0
        ).length;
        const criterioConcluido =
          subcriteriosAvaliadosDoCriterio === criterio.subcriterios.length;

        return (
          <div
            key={criterio.criterioId}
            style={{
              marginTop: "20px",
              border: estaAberto ? "1px solid #660099" : "1px solid #ddd",
              borderRadius: "12px",
              backgroundColor: "#fff",
              overflow: "hidden",
            }}
          >
            <button
              type="button"
              onClick={() =>
                setCriterioAberto((criterioAtual) =>
                  criterioAtual === criterio.criterioId ? "" : criterio.criterioId
                )
              }
              style={{
                width: "100%",
                padding: "18px 20px",
                border: "none",
                backgroundColor: estaAberto ? "#F8F1FF" : "#fff",
                cursor: "pointer",
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                gap: "16px",
                textAlign: "left",
              }}
            >
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "12px",
                  flex: 1,
                }}
              >
                <span
                  style={{
                    fontSize: "18px",
                    color: "#660099",
                    fontWeight: "bold",
                    width: "20px",
                  }}
                >
                  {estaAberto ? "▼" : "▶"}
                </span>

                <div>
                  <h3
                    style={{
                      margin: 0,
                      color: "#660099",
                    }}
                  >
                    {criterio.criterioNome}
                  </h3>
                  <p
                    style={{
                      margin: "6px 0 0 0",
                      color: "#555",
                      fontSize: "14px",
                    }}
                  >
                    {subcriteriosAvaliadosDoCriterio} de {criterio.subcriterios.length} subcritérios avaliados
                  </p>
                </div>
              </div>

              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "10px",
                  flexWrap: "wrap",
                  justifyContent: "flex-end",
                }}
              >
                {criterioConcluido && (
                  <span
                    style={{
                      padding: "6px 10px",
                      borderRadius: "999px",
                      backgroundColor: "#E7F6EC",
                      color: "#107C10",
                      fontWeight: "bold",
                      fontSize: "13px",
                      whiteSpace: "nowrap",
                    }}
                  >
                    Concluído
                  </span>
                )}

                <span
                  style={{
                    padding: "8px 14px",
                    borderRadius: "12px",
                    backgroundColor: "#E8F4FF",
                    color: "#0078D4",
                    fontWeight: "bold",
                    whiteSpace: "nowrap",
                  }}
                >
                  Nota {criterio.nota.toFixed(2)}
                </span>
              </div>
            </button>

            {estaAberto && (
              <div
                style={{
                  padding: "20px",
                  borderTop: "1px solid #eee",
                }}
              >
                <div style={{ display: "grid", gap: "18px" }}>
                  {criterio.subcriterios.map((subcriterio) => (
                    <div
                      key={subcriterio.nome}
                      style={{
                        border: "1px solid #eee",
                        borderRadius: "10px",
                        padding: "16px",
                        backgroundColor: "#FAFAFA",
                      }}
                    >
                      <div
                        style={{
                          display: "flex",
                          justifyContent: "space-between",
                          alignItems: "center",
                          gap: "16px",
                          marginBottom: "14px",
                        }}
                      >
                        <div style={{ fontWeight: "bold", color: "#333" }}>
                          {subcriterio.nome}
                        </div>
                        <div
                          style={{
                            padding: "6px 12px",
                            borderRadius: "10px",
                            backgroundColor: "#F4E8FF",
                            color: "#660099",
                            fontWeight: "bold",
                            whiteSpace: "nowrap",
                          }}
                        >
                          Média {subcriterio.notaFinal.toFixed(2)}
                        </div>
                      </div>

                      <div
                        style={{
                          display: "grid",
                          gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
                          gap: "14px",
                          textAlign: "center",
                        }}
                      >
                        <div>
                          <strong>Gerente</strong>
                          <div style={{ marginTop: "8px" }}>
                            {subcriterio.notaGerente || "Não informado"}
                          </div>
                        </div>
                        <div>
                          <strong>Coordenador</strong>
                          <div style={{ marginTop: "8px" }}>
                            {subcriterio.notaCoordenador || "Não informado"}
                          </div>
                        </div>
                        <div>
                          <strong>Colegiado</strong>
                          <div style={{ marginTop: "8px" }}>
                            {subcriterio.notaColegiado || "Não informado"}
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>

                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
                    gap: "16px",
                    marginTop: "20px",
                  }}
                >
                  <div>
                    <h4 style={{ margin: "0 0 8px 0", color: "#333" }}>
                      Observação do Gerente
                    </h4>
                    <div
                      style={{
                        minHeight: "70px",
                        padding: "12px",
                        borderRadius: "8px",
                        border: "1px solid #ddd",
                        backgroundColor: "#FAFAFA",
                        whiteSpace: "pre-wrap",
                      }}
                    >
                      {criterio.observacaoGerente || "Sem observação registrada."}
                    </div>
                  </div>

                  <div>
                    <h4 style={{ margin: "0 0 8px 0", color: "#333" }}>
                      Observação do Coordenador
                    </h4>
                    <div
                      style={{
                        minHeight: "70px",
                        padding: "12px",
                        borderRadius: "8px",
                        border: "1px solid #ddd",
                        backgroundColor: "#FAFAFA",
                        whiteSpace: "pre-wrap",
                      }}
                    >
                      {criterio.observacaoCoordenador || "Sem observação registrada."}
                    </div>
                  </div>
                </div>
              </div>
            )}
          </div>
        );
      })}

      <div
        style={{
          marginTop: "20px",
          border: feedbackFinalAberto ? "1px solid #660099" : "1px solid #ddd",
          borderRadius: "12px",
          backgroundColor: "#fff",
          overflow: "hidden",
        }}
      >
        <button
          type="button"
          onClick={() => setFeedbackFinalAberto((estadoAtual) => !estadoAtual)}
          style={{
            width: "100%",
            padding: "18px 20px",
            border: "none",
            backgroundColor: feedbackFinalAberto ? "#F8F1FF" : "#fff",
            cursor: "pointer",
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            gap: "16px",
            textAlign: "left",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: "12px",
              flex: 1,
            }}
          >
            <span
              style={{
                fontSize: "18px",
                color: "#660099",
                fontWeight: "bold",
                width: "20px",
              }}
            >
              {feedbackFinalAberto ? "▼" : "▶"}
            </span>

            <div>
              <h3
                style={{
                  margin: 0,
                  color: "#660099",
                }}
              >
                Feedback Final
              </h3>
              <p
                style={{
                  margin: "6px 0 0 0",
                  color: "#555",
                  fontSize: "14px",
                }}
              >
                Consolidado final da avaliação
              </p>
            </div>
          </div>

          <span
            style={{
              padding: "8px 14px",
              borderRadius: "12px",
              backgroundColor:
                totalFeedbacksFinaisPreenchidos > 0 ? "#E7F6EC" : "#FFF4CE",
              color: totalFeedbacksFinaisPreenchidos > 0 ? "#107C10" : "#8A6D00",
              fontWeight: "bold",
              whiteSpace: "nowrap",
            }}
          >
            {statusFeedbackFinal}
          </span>
        </button>

        {feedbackFinalAberto && (
          <div
            style={{
              padding: "20px",
              borderTop: "1px solid #eee",
            }}
          >
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
                gap: "16px",
              }}
            >
              <div>
                <h4 style={{ margin: "0 0 8px 0", color: "#333" }}>
                  Feedback Final do Gerente
                </h4>
                <div
                  style={{
                    minHeight: "120px",
                    padding: "12px",
                    borderRadius: "8px",
                    border: "1px solid #ddd",
                    backgroundColor: "#FAFAFA",
                    whiteSpace: "pre-wrap",
                  }}
                >
                  {feedbackFinalGerente || "Sem feedback final registrado."}
                </div>
              </div>

              <div>
                <h4 style={{ margin: "0 0 8px 0", color: "#333" }}>
                  Feedback Final do Coordenador
                </h4>
                <div
                  style={{
                    minHeight: "120px",
                    padding: "12px",
                    borderRadius: "8px",
                    border: "1px solid #ddd",
                    backgroundColor: "#FAFAFA",
                    whiteSpace: "pre-wrap",
                  }}
                >
                  {feedbackFinalCoordenador || "Sem feedback final registrado."}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default FeedbackDetalhePage;
