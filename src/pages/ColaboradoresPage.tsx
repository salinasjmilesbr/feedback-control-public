import { useState } from "react";
import { useNavigate } from "react-router-dom";
import ColaboradorCard from "../components/ColaboradorCard";
import { getColaboradores } from "../services/colaboradorStorage";
import type { StatusColaborador } from "../types/Colaborador";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getColaboradoresVisiveis } from "../services/visibilidadeColaboradores";
import { getCiclosAvaliacao } from "../services/cicloAvaliacaoStorage";
import { gerarDadosTesteDoCiclo } from "../services/geradorDadosTeste";
import "../styles/dados-teste.css";
import "../styles/equipe-colegiado.css";

type StatusFiltro = "TODOS" | StatusColaborador;

function ColaboradoresPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const colaboradores = getColaboradores();

  const [busca, setBusca] = useState("");
  const [coordenadorFiltro, setCoordenadorFiltro] = useState("TODOS");
  const [statusFiltro, setStatusFiltro] = useState<StatusFiltro>("TODOS");
  const ciclosDisponiveis = getCiclosAvaliacao();
  const [cicloTesteId, setCicloTesteId] = useState(
    ciclosDisponiveis[0]?.id ?? ""
  );

  if (!usuarioAtual) {
    return <div className="virtus-page">Usuário atual não definido.</div>;
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
          .filter((nome) => nome.trim() !== "")
      )
    ).sort((a, b) => a.localeCompare(b, "pt-BR")),
  ];

  const termo = busca.trim().toLowerCase();

  const colaboradoresFiltrados = colaboradoresVisiveis
    .filter((colaborador) => {
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

  const temFiltro =
    termo !== "" ||
    coordenadorFiltro !== "TODOS" ||
    statusFiltro !== "TODOS";

  const separarPorVinculo = usuarioAtual.funcao === "COORDENADOR";

  const equipeDireta = separarPorVinculo
    ? colaboradoresFiltrados.filter(
        (colaborador) =>
          colaborador.gestorDiretoMatricula === usuarioAtual.matricula
      )
    : colaboradoresFiltrados;

  const avaliacoesColegiado = separarPorVinculo
    ? colaboradoresFiltrados.filter(
        (colaborador) =>
          colaborador.gestorDiretoMatricula !== usuarioAtual.matricula
      )
    : [];

  function limparFiltros() {
    setBusca("");
    setCoordenadorFiltro("TODOS");
    setStatusFiltro("TODOS");
  }

  function gerarMassaTeste() {
    if (!usuarioAtual) {
      return;
    }

    const ciclo = ciclosDisponiveis.find(
      (item) => item.id === cicloTesteId
    );

    if (!ciclo) {
      alert("Selecione um ciclo para gerar os dados de teste.");
      return;
    }

    const confirmar = window.confirm(
      `Gerar uma nova massa de dados para ${ciclo.ano} • Ciclo ${ciclo.ciclo}?\n\n` +
        "As avaliações, metas e observações já existentes nesse ciclo serão substituídas por dados aleatórios de teste."
    );

    if (!confirmar) return;

    try {
      const resultado = gerarDadosTesteDoCiclo(ciclo, usuarioAtual);

      alert(
        `Dados de teste gerados com sucesso.\n\n` +
          `Colaboradores: ${resultado.colaboradores}\n` +
          `Avaliações: ${resultado.avaliacoes}\n` +
          `Metas: ${resultado.metas}\n` +
          `Observações: ${resultado.observacoes}`
      );

      window.location.reload();
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Não foi possível gerar os dados de teste."
      );
    }
  }

  return (
    <main className="virtus-page collaborators-v2">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Colaboradores</h1>
          <p>
            Gerencie os colaboradores, visualize avaliações e acompanhe o
            desempenho da equipe.
          </p>
        </div>

        <div className="virtus-page-actions">
          {usuarioAtual.funcao === "GERENTE" && (
            <>
              <button
                className="virtus-btn virtus-btn--outline"
                onClick={() => navigate("/configuracoes/aparencia")}
              >
                <span aria-hidden="true">◉</span>
                Identidade Visual
              </button>
              <button
                className="virtus-btn virtus-btn--outline"
                onClick={() => navigate("/ciclos")}
              >
                <span aria-hidden="true">▣</span>
                Ciclos de Avaliação
              </button>
            </>
          )}

          {usuarioAtual.funcao === "COORDENADOR" && (
            <button
              className="virtus-btn virtus-btn--outline"
              onClick={() => navigate("/painel-ciclos")}
            >
              <span aria-hidden="true">▣</span>
              Painel de Ciclos
            </button>
          )}

          <button
            className="virtus-btn virtus-btn--primary"
            onClick={() => navigate("/colaboradores/novo")}
          >
            <span className="virtus-btn__plus" aria-hidden="true">＋</span>
            Novo colaborador
          </button>
        </div>
      </section>

      {usuarioAtual.funcao === "GERENTE" && ciclosDisponiveis.length > 0 && (
        <section className="test-data-panel">
          <div className="test-data-panel__copy">
            <span className="test-data-panel__eyebrow">
              Ferramenta temporária de desenvolvimento
            </span>
            <strong>Gerar dados de teste</strong>
            <p>
              Preenche avaliações, comentários, feedbacks finais, metas e
              observações com dados variados para o ciclo selecionado.
            </p>
          </div>

          <div className="test-data-panel__actions">
            <label>
              <span>Ciclo</span>
              <select
                value={cicloTesteId}
                onChange={(event) => setCicloTesteId(event.target.value)}
              >
                {ciclosDisponiveis.map((ciclo) => (
                  <option key={ciclo.id} value={ciclo.id}>
                    {ciclo.ano} • Ciclo {ciclo.ciclo} —{" "}
                    {ciclo.status === "ATIVO"
                      ? "Ativo"
                      : ciclo.status === "PLANEJADO"
                      ? "Planejado"
                      : "Encerrado"}
                  </option>
                ))}
              </select>
            </label>

            <button
              type="button"
              className="virtus-btn virtus-btn--outline test-data-panel__button"
              onClick={gerarMassaTeste}
            >
              Gerar nova massa
            </button>
          </div>
        </section>
      )}

      <section className="virtus-filter-card">
        <div className="virtus-filter-grid">
          <label className="virtus-field virtus-field--search">
            <span>Buscar colaborador</span>
            <div className="virtus-input-wrap">
              <span className="virtus-search-icon" aria-hidden="true">⌕</span>
              <input
                value={busca}
                onChange={(event) => setBusca(event.target.value)}
                placeholder="Buscar por nome, cargo ou área..."
              />
            </div>
          </label>

          <label className="virtus-field">
            <span>Equipe / Coordenador</span>
            <select
              value={coordenadorFiltro}
              onChange={(event) => setCoordenadorFiltro(event.target.value)}
            >
              {coordenadores.map((coordenador) => (
                <option key={coordenador} value={coordenador}>
                  {coordenador === "TODOS" ? "Todas as Equipes" : coordenador}
                </option>
              ))}
            </select>
          </label>

          <label className="virtus-field">
            <span>Status</span>
            <select
              value={statusFiltro}
              onChange={(event) =>
                setStatusFiltro(event.target.value as StatusFiltro)
              }
            >
              <option value="TODOS">Todos os status</option>
              <option value="ATIVO">Ativos</option>
              <option value="LICENCA">Em licença</option>
              <option value="DESLIGADO">Desligados</option>
            </select>
          </label>

          <button
            className="virtus-btn virtus-btn--filter"
            onClick={limparFiltros}
            disabled={!temFiltro}
          >
            <span aria-hidden="true">▽</span>
            Limpar filtros
          </button>
        </div>

        <div className="virtus-filter-footer">
          <div>
            <strong>{colaboradoresFiltrados.length}</strong>{" "}
            {colaboradoresFiltrados.length === 1
              ? "colaborador encontrado"
              : "colaboradores encontrados"}
          </div>
          <div className="virtus-view-info">
            Exibindo {colaboradoresFiltrados.length} de{" "}
            {colaboradoresVisiveis.length}
            <span
              className="virtus-view-toggle is-active"
              aria-label="Visualização em grade"
              title="Visualização em grade"
            >
              ▦
            </span>
          </div>
        </div>
      </section>

      {colaboradoresFiltrados.length > 0 ? (
        separarPorVinculo ? (
          <div className="virtus-collaborator-groups">
            <section className="virtus-collaborator-group">
              <div className="virtus-collaborator-group__heading">
                <div>
                  <h2>Minha equipe direta</h2>
                  <p>Colaboradores que respondem diretamente para você.</p>
                </div>
                <span className="virtus-collaborator-group__count">
                  {equipeDireta.length}
                </span>
              </div>

              {equipeDireta.length > 0 ? (
                <div className="virtus-collaborators-grid">
                  {equipeDireta.map((colaborador) => (
                    <ColaboradorCard
                      key={colaborador.matricula}
                      colaborador={colaborador}
                    />
                  ))}
                </div>
              ) : (
                <div className="virtus-group-empty">
                  Nenhum colaborador da sua equipe direta corresponde aos filtros.
                </div>
              )}
            </section>

            <section className="virtus-collaborator-group">
              <div className="virtus-collaborator-group__heading">
                <div>
                  <h2>Avaliações como colegiado</h2>
                  <p>
                    Colaboradores de outras equipes em que você participa como
                    avaliador do colegiado.
                  </p>
                </div>
                <span className="virtus-collaborator-group__count">
                  {avaliacoesColegiado.length}
                </span>
              </div>

              {avaliacoesColegiado.length > 0 ? (
                <div className="virtus-collaborators-grid">
                  {avaliacoesColegiado.map((colaborador) => (
                    <ColaboradorCard
                      key={colaborador.matricula}
                      colaborador={colaborador}
                    />
                  ))}
                </div>
              ) : (
                <div className="virtus-group-empty">
                  Nenhuma avaliação como colegiado corresponde aos filtros.
                </div>
              )}
            </section>
          </div>
        ) : (
          <section className="virtus-collaborators-grid">
            {colaboradoresFiltrados.map((colaborador) => (
              <ColaboradorCard
                key={colaborador.matricula}
                colaborador={colaborador}
              />
            ))}
          </section>
        )
      ) : (
        <section className="virtus-empty">
          <h2>Nenhum colaborador encontrado</h2>
          <p>Altere os filtros para ampliar os resultados.</p>
        </section>
      )}
    </main>
  );
}

export default ColaboradoresPage;

