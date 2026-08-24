import type { Colaborador } from "../types/Colaborador";
import { Link } from "react-router-dom";
import { getColaboradorByMatricula } from "../services/colaboradorStorage";

function formatarNome(nome: string) {
  return nome
    .toLowerCase()
    .split(" ")
    .map(
      (palavra) =>
        palavra.charAt(0).toUpperCase() +
        palavra.slice(1)
    )
    .join(" ");
}

interface Props {
  colaborador: Colaborador;
}

function ColaboradorCard({ colaborador }: Props) {
  const gestorDireto = colaborador.gestorDiretoMatricula
    ? getColaboradorByMatricula(colaborador.gestorDiretoMatricula)
    : undefined;

  return (
    <div
      style={{
        border: "1px solid #ddd",
        borderRadius: "12px",
        padding: "20px",
        marginBottom: "10px",
        background: "#fff",
        boxShadow: "0 2px 8px rgba(0,0,0,0.08)",
      }}
    >
      <h3
        style={{
          textAlign: "center",
          marginBottom: "12px",
          color: "#444",
        }}
      >
        {colaborador.nome}
      </h3>

      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          gap: "20px",
        }}
      >
        <div
          style={{
            flex: 1,
            textAlign: "left",
            lineHeight: "1.4",
          }}
        >
          <p>
            <strong>Cargo:</strong>{" "}
            {colaborador.cargo}
          </p>

          {gestorDireto && (
            <p>
              <strong>Gestor direto:</strong>{" "}
              {formatarNome(gestorDireto.nome)}
            </p>
          )}
        </div>

        <div
          style={{
            minWidth: "180px",
            textAlign: "right",
          }}
        >
          <p
            style={{
              marginBottom: "10px",
            }}
          >
            <strong>Status:</strong>{" "}
            {colaborador.status === "ATIVO"
              ? "✅ Ativo"
              : colaborador.status === "LICENCA"
              ? "🟡 Em licença"
              : "❌ Desligado"}
          </p>

          <Link
            to={`/colaborador/${colaborador.matricula}`}
          >
            <button
              style={{
                padding: "8px 16px",
                cursor: "pointer",
                borderRadius: "6px",
                border: "1px solid #660099",
                background: "#660099",
                color: "#fff",
                fontWeight: "bold",
              }}
            >
              Ver Histórico
            </button>
          </Link>
        </div>
      </div>
    </div>
  );
}

export default ColaboradorCard;
