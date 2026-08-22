import { useState } from "react";
import ColaboradorCard from "../components/ColaboradorCard";
import { colaboradores } from "../data/colaboradores";
import { evaluationTeam } from "../data/evaluationTeam";

function ColaboradoresPage() {
  const [busca, setBusca] = useState("");
  const [coordenadorFiltro, setCoordenadorFiltro] = useState("TODOS");

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
    if (coordenadorFiltro === "TODOS") return true;

    return membroEquipe.coordenadorDireto === coordenadorFiltro;
  });

  const colaboradoresFiltrados = colaboradoresAvaliaveis
    .filter((colaborador) =>
      colaborador.nome.toLowerCase().includes(busca.toLowerCase())
    )
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  return (
    <div style={{ padding: "30px" }}>
      <h1>Colaboradores</h1>

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
          marginBottom: "25px",
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
