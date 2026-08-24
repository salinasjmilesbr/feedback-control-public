import { useNavigate, useParams } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";

function MinhaAvaliacaoDetalhePage() {
  const navigate = useNavigate();
  const { feedbackId } = useParams();
  const { usuarioAtual } = useUsuarioAtual();

  if (!usuarioAtual) {
    return <div style={{ padding: "30px" }}><h1>Usuário atual não definido</h1></div>;
  }

  const feedback = getFeedbacksByColaborador(
    usuarioAtual.matricula
  ).find(
    (item) =>
      item.id === feedbackId &&
      item.status === "CONCLUIDA"
  );

  if (!feedback) {
    return (
      <div style={{ padding: "30px" }}>
        <button type="button" onClick={() => navigate("/")}>
          ← Voltar
        </button>
        <h1>Avaliação não disponível</h1>
        <p>
          Somente avaliações concluídas do próprio colaborador
          podem ser consultadas nesta área.
        </p>
      </div>
    );
  }

  const criterios = feedback.criteriosDetalhados ?? [];

  return (
    <div style={{ padding: "30px" }}>
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
          fontWeight: "bold",
        }}
      >
        ← Voltar
      </button>

      <h1 style={{ textAlign: "center" }}>Minha Avaliação</h1>

      <div style={{
        border: "1px solid #ddd",
        borderRadius: "12px",
        padding: "20px",
        backgroundColor: "#fff",
        marginTop: "20px",
        textAlign: "center",
      }}>
        <div style={{ color: "#555" }}>
          {feedback.ano} • Ciclo {feedback.ciclo}
        </div>
        <div style={{
          marginTop: "8px",
          fontSize: "36px",
          fontWeight: "bold",
          color: "#660099",
        }}>
          {feedback.notaMedia.toFixed(2)}
        </div>
        <div style={{ color: "#555" }}>Nota Final</div>
      </div>

      <div style={{ display: "grid", gap: "16px", marginTop: "20px" }}>
        {criterios.map((criterio) => (
          <div key={criterio.criterioId} style={{
            border: "1px solid #ddd",
            borderRadius: "12px",
            padding: "18px",
            backgroundColor: "#fff",
          }}>
            <div style={{
              display: "flex",
              justifyContent: "space-between",
              gap: "20px",
              alignItems: "center",
            }}>
              <h3 style={{ margin: 0, color: "#660099" }}>
                {criterio.criterioNome}
              </h3>
              <strong>{criterio.nota.toFixed(2)}</strong>
            </div>

            <div style={{ display: "grid", gap: "8px", marginTop: "14px" }}>
              {criterio.subcriterios.map((subcriterio) => (
                <div
                  key={subcriterio.nome}
                  style={{
                    padding: "12px 0",
                    borderTop: "1px solid #eee",
                  }}
                >
                  <div
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      gap: "16px",
                      alignItems: "center",
                    }}
                  >
                    <span>{subcriterio.nome}</span>
                    <strong>
                      Nota final: {subcriterio.notaFinal.toFixed(2)}
                    </strong>
                  </div>

                  <div
                    style={{
                      marginTop: "8px",
                      display: "flex",
                      gap: "14px",
                      flexWrap: "wrap",
                      color: "#555",
                      fontSize: "14px",
                    }}
                  >
                    <span>
                      Gerente:{" "}
                      <strong>
                        {subcriterio.notaGerente > 0
                          ? subcriterio.notaGerente.toFixed(2)
                          : "-"}
                      </strong>
                    </span>
                    <span>
                      Coordenador:{" "}
                      <strong>
                        {subcriterio.notaCoordenador > 0
                          ? subcriterio.notaCoordenador.toFixed(2)
                          : "-"}
                      </strong>
                    </span>
                    <span>
                      Colegiado:{" "}
                      <strong>
                        {subcriterio.notaColegiado > 0
                          ? subcriterio.notaColegiado.toFixed(2)
                          : "-"}
                      </strong>
                    </span>
                  </div>
                </div>
              ))}

              {(criterio.observacaoGerente ||
                criterio.observacaoCoordenador) && (
                <div
                  style={{
                    marginTop: "16px",
                    paddingTop: "14px",
                    borderTop: "1px solid #ddd",
                    display: "grid",
                    gap: "12px",
                  }}
                >
                  {criterio.observacaoGerente && (
                    <div>
                      <strong>Observação do Gerente</strong>
                      <div
                        style={{
                          marginTop: "6px",
                          padding: "10px",
                          borderRadius: "8px",
                          backgroundColor: "#F8F8F8",
                          whiteSpace: "pre-wrap",
                        }}
                      >
                        {criterio.observacaoGerente}
                      </div>
                    </div>
                  )}

                  {criterio.observacaoCoordenador && (
                    <div>
                      <strong>Observação do Coordenador</strong>
                      <div
                        style={{
                          marginTop: "6px",
                          padding: "10px",
                          borderRadius: "8px",
                          backgroundColor: "#F8F8F8",
                          whiteSpace: "pre-wrap",
                        }}
                      >
                        {criterio.observacaoCoordenador}
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      {(feedback.feedbackFinalGerente ||
        feedback.feedbackFinalCoordenador) && (
        <div
          style={{
            marginTop: "20px",
            border: "1px solid #ddd",
            borderRadius: "12px",
            padding: "18px",
            backgroundColor: "#fff",
          }}
        >
          <h3 style={{ marginTop: 0, color: "#660099" }}>
            Feedback Final
          </h3>

          <div style={{ display: "grid", gap: "14px" }}>
            {feedback.feedbackFinalGerente && (
              <div>
                <strong>Gerente</strong>
                <div
                  style={{
                    marginTop: "6px",
                    padding: "12px",
                    borderRadius: "8px",
                    backgroundColor: "#F8F8F8",
                    whiteSpace: "pre-wrap",
                  }}
                >
                  {feedback.feedbackFinalGerente}
                </div>
              </div>
            )}

            {feedback.feedbackFinalCoordenador && (
              <div>
                <strong>Coordenador</strong>
                <div
                  style={{
                    marginTop: "6px",
                    padding: "12px",
                    borderRadius: "8px",
                    backgroundColor: "#F8F8F8",
                    whiteSpace: "pre-wrap",
                  }}
                >
                  {feedback.feedbackFinalCoordenador}
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      <div
        style={{
          marginTop: "20px",
          padding: "14px",
          borderRadius: "10px",
          backgroundColor: "#F8F8F8",
          color: "#555",
        }}
      >
        O analista vê as notas do gerente, coordenador e a média do
        colegiado, mas não vê os votos individuais de cada integrante
        do colegiado.
      </div>

      <div style={{
        marginTop: "20px",
        textAlign: "center",
        color: "#777",
        fontSize: "13px",
      }}>
        Exportação em PDF por ciclo será adicionada em uma próxima etapa.
      </div>
    </div>
  );
}

export default MinhaAvaliacaoDetalhePage;
