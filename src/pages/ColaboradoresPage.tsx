import { useState } from "react";
import { useNavigate } from "react-router-dom";
import ColaboradorCard from "../components/ColaboradorCard";
import { colaboradores } from "../data/colaboradores";
import { evaluationTeam } from "../data/evaluationTeam";
import type { StatusColaborador } from "../types/Colaborador";

type StatusFiltro = "TODOS" | StatusColaborador;

function ColaboradoresPage() {
  const navigate = useNavigate();
  const [busca, setBusca] = useState("");
  const [coordenadorFiltro, setCoordenadorFiltro] = useState("TODOS");
  const [statusFiltro, setStatusFiltro] = useState<StatusFiltro>("TODOS");

  const coordenadores = [
    "TODOS",
    ...Array.from(
      new Set(evaluationTeam.map((member) => member.coordenadorDireto))
    ).sort((a, b) => a.localeCompare(b, "pt-BR")),
  ];

  const colaboradoresAvaliaveis = colaboradores.filter((colaborador) => {
    const membroEquipe = evaluationTeam.find(
      (member) => String(member.matricula) === String(colaborador.matricula)
    );

    if (!membroEquipe) return false;

    const correspondeCoordenador =
      coordenadorFiltro === "TODOS" ||
      membroEquipe.coordenadorDireto === coordenadorFiltro;

    const correspondeStatus =
      statusFiltro === "TODOS" || colaborador.status === statusFiltro;

    return correspondeCoordenador && correspondeStatus;
  });

  const colaboradoresFiltrados = colaboradoresAvaliaveis
    .filter((colaborador) =>
      colaborador.nome.toLowerCase().includes(busca.toLowerCase())
    )
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
        <h1 style={{ margin: 0 }}>Colaboradores</h1>

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
            {coordenador === "TODOS" ? "Todas as Equipes" : coordenador}
          </option>
        ))}
      </select>

      <select
        value={statusFiltro}
        onChange={(e) => setStatusFiltro(e.target.value as StatusFiltro)}
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
