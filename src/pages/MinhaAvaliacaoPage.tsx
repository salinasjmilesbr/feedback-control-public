import { useNavigate } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";

function MinhaAvaliacaoPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();

  if (!usuarioAtual) {
    return <div style={{ padding: "30px" }}><h1>Usuário atual não definido</h1></div>;
  }

  const avaliacoesConcluidas = getFeedbacksByColaborador(
    usuarioAtual.matricula
  )
    .filter((feedback) => feedback.status === "CONCLUIDA")
    .sort((a, b) => b.ano - a.ano || b.ciclo - a.ciclo);

  return (
    <div style={{ padding: "30px" }}>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          gap: "16px",
          marginBottom: "20px",
        }}
      >
        <h1 style={{ margin: 0 }}>Minha Avaliação</h1>

        <div
          style={{
            display: "flex",
            gap: "10px",
            flexWrap: "wrap",
          }}
        >
          {usuarioAtual.funcao !== "GERENTE" && (
            <button
              type="button"
              onClick={() => navigate("/minhas-metas")}
              style={{
                padding: "10px 16px",
                borderRadius: "8px",
                border: "1px solid #660099",
                backgroundColor: "#fff",
                color: "#660099",
                cursor: "pointer",
                fontWeight: "600",
              }}
            >
              Minhas Metas
            </button>
          )}

          {usuarioAtual.funcao === "COORDENADOR" && (
          <button
            type="button"
            onClick={() => navigate("/")}
            style={{
              padding: "10px 16px",
              borderRadius: "8px",
              border: "1px solid #660099",
              backgroundColor: "#fff",
              color: "#660099",
              cursor: "pointer",
              fontWeight: "600",
            }}
          >
            Minha equipe
          </button>
          )}
        </div>
      </div>

      <div style={{
        border: "1px solid #ddd",
        borderRadius: "12px",
        padding: "20px",
        backgroundColor: "#fff",
        marginBottom: "20px",
      }}>
        <h2 style={{ marginTop: 0, color: "#660099" }}>
          {usuarioAtual.nome}
        </h2>
        <p style={{ marginBottom: 0 }}>
          Somente avaliações concluídas ficam disponíveis aqui.
        </p>
      </div>

      {avaliacoesConcluidas.length === 0 ? (
        <div style={{
          border: "1px solid #ddd",
          borderRadius: "12px",
          padding: "20px",
          backgroundColor: "#fff",
        }}>
          Nenhuma avaliação concluída disponível.
        </div>
      ) : (
        <div style={{ display: "grid", gap: "14px" }}>
          {avaliacoesConcluidas.map((feedback) => (
            <div key={feedback.id} style={{
              border: "1px solid #ddd",
              borderRadius: "12px",
              padding: "18px",
              backgroundColor: "#fff",
              display: "flex",
              justifyContent: "space-between",
              gap: "20px",
              alignItems: "center",
            }}>
              <div>
                <div style={{
                  fontWeight: "bold",
                  color: "#660099",
                  fontSize: "18px",
                }}>
                  {feedback.ano} • Ciclo {feedback.ciclo}
                </div>
                <div style={{ marginTop: "8px", color: "#555" }}>
                  Nota final: <strong>{feedback.notaMedia.toFixed(2)}</strong>
                </div>
              </div>

              <button
                type="button"
                onClick={() => navigate(`/minha-avaliacao/${feedback.id}`)}
                style={{
                  padding: "10px 16px",
                  borderRadius: "8px",
                  border: "none",
                  backgroundColor: "#660099",
                  color: "#fff",
                  cursor: "pointer",
                  fontWeight: "bold",
                }}
              >
                Ver avaliação
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default MinhaAvaliacaoPage;
