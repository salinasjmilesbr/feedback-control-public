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

  const [busca, setBusca] = useState("");
  const [coordenadorFiltro, setCoordenadorFiltro] = useState("TODOS");
  const [statusFiltro, setStatusFiltro] = useState<StatusFiltro>("TODOS");

  if (!usuarioAtual) {
    return (
      <div className="page-shell">
        <div className="empty-state">
          <h1>Usuário atual não definido</h1>
        </div>
      </div>
    );
  }

  const colaboradoresVisiveis = getColaboradoresVisiveis(
    usuarioAtual,
    colaboradores
  );

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
      const termo = busca.trim().toLowerCase();

      const correspondeBusca =
        termo === "" ||
        colaborador.nome.toLowerCase().includes(termo) ||
        colaborador.cargo.toLowerCase().includes(termo) ||
        colaborador.area.toLowerCase().includes(termo);

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

  const filtrosAtivos =
    busca.trim() !== "" ||
    coordenadorFiltro !== "TODOS" ||
    statusFiltro !== "TODOS";

  function limparFiltros() {
    setBusca("");
    setCoordenadorFiltro("TODOS");
    setStatusFiltro("TODOS");
  }

  return (
    <div className="page-shell collaborators-page">
      <section className="page-heading">
        <div>
          <h1>Colaboradores</h1>
          <p>
            {usuarioAtual.funcao === "GERENTE"
              ? "Gerencie sua estrutura, acompanhe os colaboradores e acesse o histórico de avaliações."
              : "Acompanhe sua equipe e acesse rapidamente o histórico de cada colaborador."}
          </p>
        </div>

        <button
          type="button"
          className="brand-button brand-button--primary page-heading__action"
          onClick={() => navigate("/colaboradores/novo")}
        >
          <span className="button-plus" aria-hidden="true">+</span>
          Novo colaborador
        </button>
      </section>

      <section className="filter-panel" aria-label="Filtros de colaboradores">
        <div className="filter-panel__grid">
          <label className="search-field">
            <span className="search-field__icon" aria-hidden="true">⌕</span>
            <input
              type="text"
              placeholder="Buscar por nome, cargo ou área..."
              value={busca}
              onChange={(event) => setBusca(event.target.value)}
            />
          </label>

          <label className="filter-field">
            <span>Coordenador</span>
            <select
              value={coordenadorFiltro}
              onChange={(event) =>
                setCoordenadorFiltro(event.target.value)
              }
            >
              {coordenadores.map((coordenador) => (
                <option key={coordenador} value={coordenador}>
                  {coordenador === "TODOS"
                    ? "Todos"
                    : coordenador}
                </option>
              ))}
            </select>
          </label>

          <label className="filter-field">
            <span>Status</span>
            <select
              value={statusFiltro}
              onChange={(event) =>
                setStatusFiltro(
                  event.target.value as StatusFiltro
                )
              }
            >
              <option value="TODOS">Todos</option>
              <option value="ATIVO">Ativos</option>
              <option value="LICENCA">Em licença</option>
              <option value="DESLIGADO">Desligados</option>
            </select>
          </label>

          <button
            type="button"
            className="filter-clear"
            onClick={limparFiltros}
            disabled={!filtrosAtivos}
          >
            Limpar filtros
          </button>
        </div>

        <div className="filter-panel__summary">
          <span>
            Total visível: <strong>{colaboradoresVisiveis.length}</strong>
          </span>
          <span>
            Exibindo <strong>{colaboradoresFiltrados.length}</strong>{" "}
            {colaboradoresFiltrados.length === 1
              ? "colaborador"
              : "colaboradores"}
          </span>
        </div>
      </section>

      {colaboradoresFiltrados.length > 0 ? (
        <section className="collaborators-grid">
          {colaboradoresFiltrados.map((colaborador) => (
            <ColaboradorCard
              key={colaborador.matricula}
              colaborador={colaborador}
            />
          ))}
        </section>
      ) : (
        <section className="empty-state">
          <div className="empty-state__icon" aria-hidden="true">⌕</div>
          <h2>Nenhum colaborador encontrado</h2>
          <p>
            Ajuste os filtros ou limpe a busca para visualizar outros
            colaboradores.
          </p>
          {filtrosAtivos && (
            <button
              type="button"
              className="brand-button brand-button--secondary"
              onClick={limparFiltros}
            >
              Limpar filtros
            </button>
          )}
        </section>
      )}
    </div>
  );
}

export default ColaboradoresPage;
