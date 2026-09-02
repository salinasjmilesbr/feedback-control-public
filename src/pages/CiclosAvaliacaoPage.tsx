import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import {
  criarCiclo,
  encerrarCiclo,
  excluirCiclo,
  getCiclosAvaliacao,
  atualizarConfiguracaoMetasCiclo,
  atualizarPeriodoCiclo,
  atualizarStatusCiclo,
  formatarPeriodoCiclo,
} from "../services/cicloAvaliacaoStorage";
import {
  analisarPendenciasDoCiclo,
  concluirAvaliacoesNoEncerramentoDoCiclo,
  criarAvaliacoesDoCicloAtivado,
  excluirAvaliacoesVaziasDoCiclo,
} from "../services/cicloEquipeService";
import "../styles/ciclos.css";

function CiclosAvaliacaoPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const [versao, setVersao] = useState(0);
  const [ano, setAno] = useState(new Date().getFullYear());
  const [ciclo, setCiclo] = useState<1 | 2 | 3>(1);
  const [dataInicio, setDataInicio] = useState("");
  const [dataFim, setDataFim] = useState("");
  const [quantidadeMetasNegocio, setQuantidadeMetasNegocio] =
    useState<0 | 1 | 2 | 3>(0);
  const [quantidadeMetasIndividuais, setQuantidadeMetasIndividuais] =
    useState<0 | 1 | 2 | 3>(0);
  const [ativarAgora, setAtivarAgora] = useState(false);
  const [editandoPeriodoId, setEditandoPeriodoId] = useState<string | null>(null);
  const [periodoInicioEdicao, setPeriodoInicioEdicao] = useState("");
  const [periodoFimEdicao, setPeriodoFimEdicao] = useState("");
  const [editandoMetasId, setEditandoMetasId] = useState<string | null>(null);
  const [metasNegocioEdicao, setMetasNegocioEdicao] =
    useState<0 | 1 | 2 | 3>(0);
  const [metasIndividuaisEdicao, setMetasIndividuaisEdicao] =
    useState<0 | 1 | 2 | 3>(0);
  const [erro, setErro] = useState("");
  const podeGerenciarCiclos = usuarioAtual
    ? can(
        {
          actor: {
            matricula: usuarioAtual.matricula,
            funcao: usuarioAtual.funcao,
            status: usuarioAtual.status,
          },
        },
        "cycle.management.view",
        { kind: "global" }
      )
    : false;

  void versao;

  if (!usuarioAtual || !podeGerenciarCiclos) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Acesso restrito</h1>
          <p>A gestão dos ciclos está disponível apenas para gerentes.</p>
          <button className="cycle-btn cycle-btn--secondary" onClick={() => navigate("/")}>
            Voltar ao início
          </button>
        </section>
      </main>
    );
  }

  const ciclos = getCiclosAvaliacao().sort((a, b) => {
    if (a.status !== b.status) {
      if (a.status === "ATIVO") return -1;
      if (b.status === "ATIVO") return 1;
      if (a.status === "PLANEJADO") return -1;
      if (b.status === "PLANEJADO") return 1;
    }
    if (a.ano !== b.ano) return b.ano - a.ano;
    return b.ciclo - a.ciclo;
  });

  const totalAtivos = ciclos.filter((item) => item.status === "ATIVO").length;
  const totalPlanejados = ciclos.filter((item) => item.status === "PLANEJADO").length;
  const totalEncerrados = ciclos.filter((item) => item.status === "ENCERRADO").length;

  function criar() {
    setErro("");
    try {
      const novoCiclo = criarCiclo(
        ano,
        ciclo,
        dataInicio,
        dataFim,
        quantidadeMetasNegocio,
        quantidadeMetasIndividuais,
        ativarAgora
      );

      if (ativarAgora) {
        criarAvaliacoesDoCicloAtivado(novoCiclo);
      }

      setDataInicio("");
      setDataFim("");
      setQuantidadeMetasNegocio(0);
      setQuantidadeMetasIndividuais(0);
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível criar o ciclo."
      );
    }
  }

  function encerrarComValidacao(
    item: ReturnType<typeof getCiclosAvaliacao>[number]
  ) {
    setErro("");

    const pendencias = analisarPendenciasDoCiclo(item);
    const totalPendencias = pendencias.reduce(
      (soma, pendencia) => soma + pendencia.quantidade,
      0
    );

    if (pendencias.length > 0) {
      const resumo = pendencias
        .map((pendencia) =>
          pendencia.papel === "Metas"
            ? `${pendencia.colaboradorNome} — Metas: ${pendencia.quantidade} meta${
                pendencia.quantidade === 1 ? "" : "s"
              } sem fechamento${
                pendencia.detalhes?.length
                  ? ` (${pendencia.detalhes.join(", ")})`
                  : ""
              }`
            : `${pendencia.colaboradorNome} — ${pendencia.papel}: ${
                pendencia.quantidade
              } nota${pendencia.quantidade === 1 ? "" : "s"} pendente${
                pendencia.quantidade === 1 ? "" : "s"
              }`
        )
        .join("\n");

      const confirmar = window.confirm(
        `Este ciclo possui pendências:\n\n${resumo}\n\nDeseja encerrar mesmo assim? As médias usarão somente as notas recebidas, avaliações incompletas serão marcadas como parciais e metas sem fechamento permanecerão registradas como pendências do ciclo.`
      );

      if (!confirmar) return;

      concluirAvaliacoesNoEncerramentoDoCiclo(item, pendencias);
      encerrarCiclo(item.id, totalPendencias);
      setVersao((valor) => valor + 1);
      return;
    }

    const confirmar = window.confirm(
      "Todas as avaliações estão completas. Deseja encerrar este ciclo?"
    );

    if (!confirmar) return;

    concluirAvaliacoesNoEncerramentoDoCiclo(item, []);
    encerrarCiclo(item.id, 0);
    setVersao((valor) => valor + 1);
  }

  function ativarComValidacao(
    item: ReturnType<typeof getCiclosAvaliacao>[number]
  ) {
    try {
      atualizarStatusCiclo(item.id, "ATIVO");
      const cicloAtivado = getCiclosAvaliacao().find(
        (cicloAtual) => cicloAtual.id === item.id
      );
      if (cicloAtivado) criarAvaliacoesDoCicloAtivado(cicloAtivado);

      setErro("");
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível atualizar o status."
      );
    }
  }

  return (
    <main className="virtus-page cycle-page">
      <section className="cycle-page-header">
        <div>
          <h1>Ciclos de Avaliação</h1>
          <p>
            Configure períodos, metas e acompanhe a evolução de cada ciclo.
          </p>
        </div>

        <div className="cycle-summary">
          <div>
            <strong>{ciclos.length}</strong>
            <span>Total</span>
          </div>
          <div>
            <strong>{totalAtivos}</strong>
            <span>Ativo</span>
          </div>
          <div>
            <strong>{totalPlanejados}</strong>
            <span>Planejados</span>
          </div>
          <div>
            <strong>{totalEncerrados}</strong>
            <span>Encerrados</span>
          </div>
        </div>
      </section>

      <section className="cycle-create-card">
        <div className="cycle-section-heading">
          <div>
            <span className="cycle-eyebrow">Novo ciclo</span>
            <h2>Configuração inicial</h2>
          </div>
          <span className="cycle-helper">Apenas um ciclo pode ficar ativo por vez.</span>
        </div>

        <div className="cycle-form-grid cycle-form-grid--four">
          <label className="cycle-field">
            <span>Ano</span>
            <input
              type="number"
              min={2020}
              max={2100}
              value={ano}
              onChange={(event) => setAno(Number(event.target.value))}
            />
          </label>

          <label className="cycle-field">
            <span>Ciclo</span>
            <select
              value={ciclo}
              onChange={(event) =>
                setCiclo(Number(event.target.value) as 1 | 2 | 3)
              }
            >
              <option value={1}>Ciclo 1</option>
              <option value={2}>Ciclo 2</option>
              <option value={3}>Ciclo 3</option>
            </select>
          </label>

          <label className="cycle-field">
            <span>Início</span>
            <input
              type="date"
              value={dataInicio}
              onChange={(event) => setDataInicio(event.target.value)}
            />
          </label>

          <label className="cycle-field">
            <span>Fim</span>
            <input
              type="date"
              value={dataFim}
              onChange={(event) => setDataFim(event.target.value)}
            />
          </label>
        </div>

        <div className="cycle-form-grid cycle-form-grid--two">
          <label className="cycle-field">
            <span>Metas de Negócio / Projetos</span>
            <select
              value={quantidadeMetasNegocio}
              onChange={(event) =>
                setQuantidadeMetasNegocio(
                  Number(event.target.value) as 0 | 1 | 2 | 3
                )
              }
            >
              <option value={0}>0 metas</option>
              <option value={1}>1 meta</option>
              <option value={2}>2 metas</option>
              <option value={3}>3 metas</option>
            </select>
          </label>

          <label className="cycle-field">
            <span>Metas Individuais</span>
            <select
              value={quantidadeMetasIndividuais}
              onChange={(event) =>
                setQuantidadeMetasIndividuais(
                  Number(event.target.value) as 0 | 1 | 2 | 3
                )
              }
            >
              <option value={0}>0 metas</option>
              <option value={1}>1 meta</option>
              <option value={2}>2 metas</option>
              <option value={3}>3 metas</option>
            </select>
          </label>
        </div>

        <div className="cycle-create-footer">
          <label className="cycle-checkbox">
            <input
              type="checkbox"
              checked={ativarAgora}
              onChange={(event) => setAtivarAgora(event.target.checked)}
            />
            <span>
              <strong>Ativar imediatamente</strong>
              <small>Cria as avaliações automaticamente ao salvar.</small>
            </span>
          </label>

          <button className="cycle-btn cycle-btn--primary" onClick={criar}>
            + Criar ciclo
          </button>
        </div>

        {erro && <div className="cycle-alert cycle-alert--error">{erro}</div>}
      </section>

      <section className="cycle-list">
        <div className="cycle-list-heading">
          <div>
            <span className="cycle-eyebrow">Histórico</span>
            <h2>Ciclos cadastrados</h2>
          </div>
        </div>

        {ciclos.length === 0 ? (
          <div className="cycle-empty">
            <h3>Nenhum ciclo cadastrado</h3>
            <p>Crie o primeiro ciclo usando o formulário acima.</p>
          </div>
        ) : (
          ciclos.map((item) => {
            const statusLabel =
              item.status === "ATIVO"
                ? "Ativo"
                : item.status === "PLANEJADO"
                ? "Planejado"
                : item.encerradoComPendencias
                ? "Encerrado com pendências"
                : "Encerrado";

            const statusClass =
              item.status === "ATIVO"
                ? "is-active"
                : item.status === "PLANEJADO"
                ? "is-planned"
                : item.encerradoComPendencias
                ? "is-warning"
                : "is-closed";

            return (
              <article
                key={item.id}
                className={`cycle-card ${item.status === "ATIVO" ? "cycle-card--active" : ""}`}
              >
                <div className="cycle-card__main">
                  <div className="cycle-card__identity">
                    <div className="cycle-card__title-row">
                      <h3>
                        {item.ano} <span>•</span> Ciclo {item.ciclo}
                      </h3>
                      <span className={`cycle-status ${statusClass}`}>
                        {statusLabel}
                      </span>
                    </div>

                    <div className="cycle-card__meta-grid">
                      <div>
                        <small>Período</small>
                        <strong>
                          {formatarPeriodoCiclo(item.dataInicio, item.dataFim)}
                        </strong>
                      </div>
                      <div>
                        <small>Metas de Negócio</small>
                        <strong>{item.quantidadeMetasNegocio ?? 0}</strong>
                      </div>
                      <div>
                        <small>Metas Individuais</small>
                        <strong>{item.quantidadeMetasIndividuais ?? 0}</strong>
                      </div>
                      {item.encerradoComPendencias && (
                        <div>
                          <small>Pendências</small>
                          <strong className="cycle-danger">
                            {item.quantidadePendencias ?? 0}
                          </strong>
                        </div>
                      )}
                    </div>
                  </div>

                  <button
                    className="cycle-btn cycle-btn--primary cycle-btn--panel"
                    onClick={() => navigate(`/ciclos/${item.id}`)}
                  >
                    Painel da equipe →
                  </button>
                </div>

                <div className="cycle-card__editors">
                  <div className="cycle-editor">
                    <span className="cycle-editor__label">Período</span>
                    {editandoPeriodoId === item.id ? (
                      <div className="cycle-inline-form cycle-inline-form--period">
                        <input
                          type="date"
                          value={periodoInicioEdicao}
                          onChange={(event) =>
                            setPeriodoInicioEdicao(event.target.value)
                          }
                        />
                        <input
                          type="date"
                          value={periodoFimEdicao}
                          onChange={(event) =>
                            setPeriodoFimEdicao(event.target.value)
                          }
                        />
                        <button
                          className="cycle-btn cycle-btn--small cycle-btn--primary"
                          onClick={() => {
                            try {
                              atualizarPeriodoCiclo(
                                item.id,
                                periodoInicioEdicao,
                                periodoFimEdicao
                              );
                              setEditandoPeriodoId(null);
                              setErro("");
                              setVersao((valor) => valor + 1);
                            } catch (error) {
                              setErro(
                                error instanceof Error
                                  ? error.message
                                  : "Não foi possível atualizar o período."
                              );
                            }
                          }}
                        >
                          Salvar
                        </button>
                      </div>
                    ) : (
                      <button
                        className="cycle-link-button"
                        onClick={() => {
                          setEditandoPeriodoId(item.id);
                          setPeriodoInicioEdicao(item.dataInicio ?? "");
                          setPeriodoFimEdicao(item.dataFim ?? "");
                          setErro("");
                        }}
                      >
                        Editar período
                      </button>
                    )}
                  </div>

                  <div className="cycle-editor">
                    <span className="cycle-editor__label">Metas</span>
                    {item.status === "PLANEJADO" ? (
                      editandoMetasId === item.id ? (
                        <div className="cycle-inline-form">
                          <select
                            value={metasNegocioEdicao}
                            onChange={(event) =>
                              setMetasNegocioEdicao(
                                Number(event.target.value) as 0 | 1 | 2 | 3
                              )
                            }
                          >
                            <option value={0}>Negócio: 0</option>
                            <option value={1}>Negócio: 1</option>
                            <option value={2}>Negócio: 2</option>
                            <option value={3}>Negócio: 3</option>
                          </select>

                          <select
                            value={metasIndividuaisEdicao}
                            onChange={(event) =>
                              setMetasIndividuaisEdicao(
                                Number(event.target.value) as 0 | 1 | 2 | 3
                              )
                            }
                          >
                            <option value={0}>Individual: 0</option>
                            <option value={1}>Individual: 1</option>
                            <option value={2}>Individual: 2</option>
                            <option value={3}>Individual: 3</option>
                          </select>

                          <button
                            className="cycle-btn cycle-btn--small cycle-btn--primary"
                            onClick={() => {
                              try {
                                atualizarConfiguracaoMetasCiclo(
                                  item.id,
                                  metasNegocioEdicao,
                                  metasIndividuaisEdicao
                                );
                                setEditandoMetasId(null);
                                setErro("");
                                setVersao((valor) => valor + 1);
                              } catch (error) {
                                setErro(
                                  error instanceof Error
                                    ? error.message
                                    : "Não foi possível atualizar as metas."
                                );
                              }
                            }}
                          >
                            Salvar
                          </button>
                        </div>
                      ) : (
                        <button
                          className="cycle-link-button"
                          onClick={() => {
                            setEditandoMetasId(item.id);
                            setMetasNegocioEdicao(
                              item.quantidadeMetasNegocio ?? 0
                            );
                            setMetasIndividuaisEdicao(
                              item.quantidadeMetasIndividuais ?? 0
                            );
                            setErro("");
                          }}
                        >
                          Editar metas
                        </button>
                      )
                    ) : (
                      <span className="cycle-muted">Bloqueadas após o início</span>
                    )}
                  </div>

                  <div className="cycle-editor cycle-editor--actions">
                    <span className="cycle-editor__label">Status</span>
                    {item.status === "PLANEJADO" && (
                      <button
                        className="cycle-link-button"
                        onClick={() => ativarComValidacao(item)}
                      >
                        Ativar ciclo
                      </button>
                    )}
                    {item.status === "ATIVO" && (
                      <button
                        className="cycle-link-button"
                        onClick={() => encerrarComValidacao(item)}
                      >
                        Encerrar ciclo
                      </button>
                    )}
                    {item.status === "ENCERRADO" && (
                      <span className="cycle-muted">Lifecycle encerrado</span>
                    )}
                  </div>

                  <button
                    className="cycle-link-button cycle-link-button--danger"
                    onClick={() => {
                      const confirmar = window.confirm(
                        `Excluir ${item.ano} • Ciclo ${item.ciclo}?\n\nAvaliações vazias criadas automaticamente também serão excluídas. Avaliações que já possuam dados impedem a exclusão.`
                      );
                      if (!confirmar) return;

                      try {
                        excluirAvaliacoesVaziasDoCiclo(item);
                        excluirCiclo(item.id);
                        setErro("");
                        setVersao((valor) => valor + 1);
                      } catch (error) {
                        setErro(
                          error instanceof Error
                            ? error.message
                            : "Não foi possível excluir o ciclo."
                        );
                      }
                    }}
                  >
                    Excluir ciclo
                  </button>
                </div>
              </article>
            );
          })
        )}
      </section>
    </main>
  );
}

export default CiclosAvaliacaoPage;
