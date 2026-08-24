import { useNavigate } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import {
  formatarPeriodoCiclo,
  getCiclosAvaliacao,
} from "../services/cicloAvaliacaoStorage";

function PainelCiclosCoordenadorPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();

  if (!usuarioAtual || usuarioAtual.funcao !== "COORDENADOR") {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Acesso restrito</h1>
        <p>Esta visão está disponível apenas para coordenadores.</p>
      </div>
    );
  }

  const ciclos = getCiclosAvaliacao()
    .filter(
      (ciclo) =>
        ciclo.status === "ATIVO" || ciclo.status === "ENCERRADO"
    )
    .sort((a, b) => {
      if (a.status !== b.status) {
        return a.status === "ATIVO" ? -1 : 1;
      }

      if (a.ano !== b.ano) return b.ano - a.ano;
      return b.ciclo - a.ciclo;
    });

  return (
    <div
      style={{
        padding: "30px",
        maxWidth: "1000px",
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
          marginBottom: "24px",
        }}
      >
        <div>
          <h1 style={{ margin: 0 }}>Painel de Ciclos</h1>
          <p style={{ margin: "6px 0 0 0", color: "#666" }}>
            Acompanhe o ciclo ativo e consulte o histórico da sua equipe.
          </p>
        </div>

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
          ← Minha equipe
        </button>
      </div>

      {ciclos.length === 0 ? (
        <div
          style={{
            padding: "20px",
            border: "1px solid #ddd",
            borderRadius: "12px",
            backgroundColor: "#fff",
            color: "#666",
          }}
        >
          Nenhum ciclo ativo ou encerrado disponível.
        </div>
      ) : (
        <div style={{ display: "grid", gap: "14px" }}>
          {ciclos.map((ciclo) => (
            <div
              key={ciclo.id}
              style={{
                padding: "18px",
                border: "1px solid #ddd",
                borderRadius: "12px",
                backgroundColor: "#fff",
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                gap: "16px",
                flexWrap: "wrap",
              }}
            >
              <div>
                <div
                  style={{
                    display: "flex",
                    gap: "10px",
                    alignItems: "center",
                    flexWrap: "wrap",
                  }}
                >
                  <strong style={{ fontSize: "18px" }}>
                    {ciclo.ano} • Ciclo {ciclo.ciclo}
                  </strong>

                  <span
                    style={{
                      padding: "4px 9px",
                      borderRadius: "999px",
                      fontSize: "12px",
                      fontWeight: "bold",
                      backgroundColor:
                        ciclo.status === "ATIVO"
                          ? "#E7F6EC"
                          : ciclo.encerradoComPendencias
                          ? "#FDE7E9"
                          : "#F2F2F2",
                      color:
                        ciclo.status === "ATIVO"
                          ? "#107C41"
                          : ciclo.encerradoComPendencias
                          ? "#A4262C"
                          : "#555",
                    }}
                  >
                    {ciclo.status === "ATIVO"
                      ? "Ativo"
                      : ciclo.encerradoComPendencias
                      ? "Encerrado com pendências"
                      : "Encerrado"}
                  </span>
                </div>

                <div
                  style={{
                    marginTop: "7px",
                    color: "#666",
                    fontSize: "14px",
                  }}
                >
                  {formatarPeriodoCiclo(
                    ciclo.dataInicio,
                    ciclo.dataFim
                  )}
                </div>

                {ciclo.encerradoComPendencias &&
                  (ciclo.quantidadePendencias ?? 0) > 0 && (
                    <div
                      style={{
                        marginTop: "6px",
                        color: "#A4262C",
                        fontSize: "13px",
                      }}
                    >
                      {ciclo.quantidadePendencias} nota
                      {ciclo.quantidadePendencias === 1 ? "" : "s"}{" "}
                      pendente
                      {ciclo.quantidadePendencias === 1 ? "" : "s"} no
                      encerramento
                    </div>
                  )}
              </div>

              <button
                type="button"
                onClick={() => navigate(`/ciclos/${ciclo.id}`)}
                style={{
                  padding: "10px 14px",
                  borderRadius: "8px",
                  border: "1px solid #660099",
                  backgroundColor: "#fff",
                  color: "#660099",
                  cursor: "pointer",
                  fontWeight: "bold",
                }}
              >
                {ciclo.status === "ATIVO"
                  ? "Acompanhar ciclo"
                  : "Consultar ciclo"}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default PainelCiclosCoordenadorPage;
