import { useState } from "react";
import { useNavigate } from "react-router-dom";
import ColaboradorCard from "../components/ColaboradorCard";
import { getColaboradores } from "../services/colaboradorStorage";
import type { StatusColaborador } from "../types/Colaborador";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getColaboradoresVisiveis } from "../services/visibilidadeColaboradores";

type StatusFiltro = "TODOS" | StatusColaborador;

function ColaboradoresPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const colaboradores = getColaboradores();

  if (!usuarioAtual) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Usuário atual não definido</h1>
      </div>
    );
  }

  const colaboradoresVisiveis = getColaboradoresVisiveis(
    usuarioAtual,
    colaboradores
  );

  const [busca, setBusca] = useState("");
  const [coordenadorFiltro, setCoordenadorFiltro] = useState("TODOS");
  const [statusFiltro, setStatusFiltro] = useState<StatusFiltro>("TODOS");

  const coordenadores = [
    "TODOS",
    ...Array.from(
      new Set(
        colaboradoresVisiveis
          .map((colaborador) => colaborador.respondePara)
          .filter((coordenador) => coordenador.trim() !== "")
      )
    ).sort((a, b) => a.localeCompare(b, "pt-BR")),
  ];

  const colaboradoresFiltrados = colaboradoresVisiveis
    .filter((colaborador) => {
      const correspondeBusca = colaborador.nome
        .toLowerCase()
        .includes(busca.toLowerCase());

      const correspondeCoordenador =
        coordenadorFiltro === "TODOS" ||
        colaborador.respondePara === coordenadorFiltro;

      const correspondeStatus =
        statusFiltro === "TODOS" ||
        colaborador.status === statusFiltro;

      return (
        correspondeBusca &&
        correspondeCoordenador &&
        correspondeStatus
      );
    })
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  return (
    <div style={{ padding: "30px" }}>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          marginBottom: "20px",
        }}
      >
        <div>
          <h1 style={{ margin: 0 }}>Colaboradores</h1>
          <p style={{ margin: "6px 0 0 0", color: "#666" }}>
            {usuarioAtual.funcao === "GERENTE"
              ? "Sua estrutura hierárquica"
              : "Sua equipe e avaliações em que participa"}
          </p>
        </div>

        <div
          style={{
            display: "flex",
            gap: "10px",
            flexWrap: "wrap",
            justifyContent: "flex-end",
          }}
        >
          {usuarioAtual.funcao === "GERENTE" && (
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
                fontWeight: "600",
              }}
            >
              Ciclos de Avaliação
            </button>
          )}

          {usuarioAtual.funcao === "COORDENADOR" && (
            <button
              type="button"
              onClick={() => navigate("/painel-ciclos")}
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
              Painel de Ciclos
            </button>
          )}

          {usuarioAtual.funcao === "COORDENADOR" && (
            <button
              type="button"
              onClick={() => navigate("/minha-avaliacao")}
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
              Minha Avaliação
            </button>
          )}

          <button
            type="button"
            onClick={() => navigate("/colaboradores/novo")}
            style={{
              padding: "10px 16px",
              borderRadius: "8px",
              border: "none",
              cursor: "pointer",
              fontWeight: "600",
            }}
          >
            + Novo colaborador
          </button>
        </div>
      </div>

      <input
        type="text"
        placeholder="Buscar colaborador..."
        value={busca}
        onChange={(e) => setBusca(e.target.value)}
        style={{
          width: "100%",
          maxWidth: "500px",
          padding: "10px",
          marginBottom: "15px",
          borderRadius: "8px",
          border: "1px solid #ccc",
        }}
      />

      <select
        value={coordenadorFiltro}
        onChange={(e) => setCoordenadorFiltro(e.target.value)}
        style={{
          width: "100%",
          maxWidth: "500px",
          padding: "10px",
          marginBottom: "15px",
          borderRadius: "8px",
          border: "1px solid #ccc",
        }}
      >
        {coordenadores.map((coordenador) => (
          <option key={coordenador} value={coordenador}>
            {coordenador === "TODOS"
              ? "Todas as Equipes"
              : coordenador}
          </option>
        ))}
      </select>

      <select
        value={statusFiltro}
        onChange={(e) =>
          setStatusFiltro(e.target.value as StatusFiltro)
        }
        style={{
          width: "100%",
          maxWidth: "500px",
          padding: "10px",
          marginBottom: "25px",
          borderRadius: "8px",
          border: "1px solid #ccc",
        }}
      >
        <option value="TODOS">Todos os status</option>
        <option value="ATIVO">Ativos</option>
        <option value="LICENCA">Em licença</option>
        <option value="DESLIGADO">Desligados</option>
      </select>

      <p
        style={{
          marginBottom: "20px",
          color: "#666",
          fontWeight: "500",
        }}
      >
        {colaboradoresFiltrados.length}{" "}
        {colaboradoresFiltrados.length === 1
          ? "colaborador encontrado"
          : "colaboradores encontrados"}
      </p>

      {colaboradoresFiltrados.map((colaborador) => (
        <ColaboradorCard
          key={colaborador.matricula}
          colaborador={colaborador}
        />
      ))}
    </div>
  );
}

export default ColaboradoresPage;
