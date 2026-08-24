import { useState } from "react";
import { useNavigate } from "react-router-dom";
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
import type { StatusCicloAvaliacao } from "../types/CicloAvaliacao";

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
  const [editandoStatusId, setEditandoStatusId] = useState<string | null>(null);
  const [statusEdicao, setStatusEdicao] =
    useState<StatusCicloAvaliacao>("PLANEJADO");
  const [periodoInicioEdicao, setPeriodoInicioEdicao] = useState("");
  const [periodoFimEdicao, setPeriodoFimEdicao] = useState("");
  const [editandoMetasId, setEditandoMetasId] =
    useState<string | null>(null);
  const [metasNegocioEdicao, setMetasNegocioEdicao] =
    useState<0 | 1 | 2 | 3>(0);
  const [metasIndividuaisEdicao, setMetasIndividuaisEdicao] =
    useState<0 | 1 | 2 | 3>(0);
  const [erro, setErro] = useState("");

  void versao;

  if (!usuarioAtual || usuarioAtual.funcao !== "GERENTE") {
    return (
      <div style={{ padding: "30px" }}>
        <button type="button" onClick={() => navigate("/")}>
          ← Voltar
        </button>
        <h1>Acesso restrito</h1>
        <p>A gestão dos ciclos está disponível apenas para gerentes.</p>
      </div>
    );
  }

  const ciclos = getCiclosAvaliacao();

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
        .map(
          (pendencia) =>
            pendencia.papel === "Metas"
              ? `${pendencia.colaboradorNome} — Metas: ${
                  pendencia.quantidade
                } meta${
                  pendencia.quantidade === 1 ? "" : "s"
                } sem fechamento${
                  pendencia.detalhes?.length
                    ? ` (${pendencia.detalhes.join(", ")})`
                    : ""
                }`
              : `${pendencia.colaboradorNome} — ${pendencia.papel}: ${
                  pendencia.quantidade
                } nota${
                  pendencia.quantidade === 1 ? "" : "s"
                } pendente${
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
      setEditandoStatusId(null);
      setVersao((valor) => valor + 1);
      return;
    }

    const confirmar = window.confirm(
      "Todas as avaliações estão completas. Deseja encerrar este ciclo?"
    );

    if (!confirmar) return;

    concluirAvaliacoesNoEncerramentoDoCiclo(item, []);
    encerrarCiclo(item.id, 0);
    setEditandoStatusId(null);
    setVersao((valor) => valor + 1);
  }

  return (
    <div style={{ padding: "30px", maxWidth: "1000px", margin: "0 auto" }}>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          gap: "16px",
          alignItems: "center",
          marginBottom: "24px",
        }}
      >
        <div>
          <h1 style={{ margin: 0 }}>Ciclos de Avaliação</h1>
          <p style={{ margin: "6px 0 0 0", color: "#666" }}>
            Existe apenas um ciclo ativo por vez.
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
            fontWeight: "bold",
          }}
        >
          ← Voltar
        </button>
      </div>

      <div
        style={{
          border: "1px solid #ddd",
          borderRadius: "12px",
          padding: "18px",
          backgroundColor: "#fff",
          marginBottom: "22px",
        }}
      >
        <h3 style={{ marginTop: 0 }}>Novo ciclo</h3>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "minmax(140px, 1fr) minmax(140px, 1fr)",
            gap: "12px",
          }}
        >
          <label>
            <strong>Ano</strong>
            <input
              type="number"
              min={2020}
              max={2100}
              value={ano}
              onChange={(event) => setAno(Number(event.target.value))}
              style={{
                width: "100%",
                marginTop: "6px",
                padding: "10px",
                borderRadius: "8px",
                border: "1px solid #ccc",
                boxSizing: "border-box",
              }}
            />
          </label>

          <label>
            <strong>Ciclo</strong>
            <select
              value={ciclo}
              onChange={(event) =>
                setCiclo(Number(event.target.value) as 1 | 2 | 3)
              }
              style={{
                width: "100%",
                marginTop: "6px",
                padding: "10px",
                borderRadius: "8px",
                border: "1px solid #ccc",
                boxSizing: "border-box",
              }}
            >
              <option value={1}>Ciclo 1</option>
              <option value={2}>Ciclo 2</option>
              <option value={3}>Ciclo 3</option>
            </select>
          </label>
        </div>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "minmax(160px, 1fr) minmax(160px, 1fr)",
            gap: "12px",
            marginTop: "14px",
          }}
        >
          <label>
            <strong>Início do ciclo</strong>
            <input
              type="date"
              value={dataInicio}
              onChange={(event) => setDataInicio(event.target.value)}
              style={{
                width: "100%",
                marginTop: "6px",
                padding: "10px",
                borderRadius: "8px",
                border: "1px solid #ccc",
                boxSizing: "border-box",
              }}
            />
          </label>

          <label>
            <strong>Fim do ciclo</strong>
            <input
              type="date"
              value={dataFim}
              onChange={(event) => setDataFim(event.target.value)}
              style={{
                width: "100%",
                marginTop: "6px",
                padding: "10px",
                borderRadius: "8px",
                border: "1px solid #ccc",
                boxSizing: "border-box",
              }}
            />
          </label>
        </div>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "minmax(180px, 1fr) minmax(180px, 1fr)",
            gap: "12px",
            marginTop: "14px",
          }}
        >
          <label>
            <strong>Metas de Negócio/Projetos</strong>
            <select
              value={quantidadeMetasNegocio}
              onChange={(event) =>
                setQuantidadeMetasNegocio(
                  Number(event.target.value) as 0 | 1 | 2 | 3
                )
              }
              style={{
                width: "100%",
                marginTop: "6px",
                padding: "10px",
                borderRadius: "8px",
                border: "1px solid #ccc",
                boxSizing: "border-box",
              }}
            >
              <option value={0}>0 metas</option>
              <option value={1}>1 meta</option>
              <option value={2}>2 metas</option>
              <option value={3}>3 metas</option>
            </select>
          </label>

          <label>
            <strong>Metas Individuais</strong>
            <select
              value={quantidadeMetasIndividuais}
              onChange={(event) =>
                setQuantidadeMetasIndividuais(
                  Number(event.target.value) as 0 | 1 | 2 | 3
                )
              }
              style={{
                width: "100%",
                marginTop: "6px",
                padding: "10px",
                borderRadius: "8px",
                border: "1px solid #ccc",
                boxSizing: "border-box",
              }}
            >
              <option value={0}>0 metas</option>
              <option value={1}>1 meta</option>
              <option value={2}>2 metas</option>
              <option value={3}>3 metas</option>
            </select>
          </label>
        </div>

        <label
          style={{
            display: "flex",
            gap: "8px",
            alignItems: "center",
            marginTop: "14px",
          }}
        >
          <input
            type="checkbox"
            checked={ativarAgora}
            onChange={(event) => setAtivarAgora(event.target.checked)}
          />
          Ativar este ciclo imediatamente
        </label>

        {erro && (
          <div style={{ color: "#A4262C", marginTop: "12px" }}>
            {erro}
          </div>
        )}

        <button
          type="button"
          onClick={criar}
          style={{
            marginTop: "14px",
            padding: "10px 16px",
            borderRadius: "8px",
            border: "none",
            backgroundColor: "#660099",
            color: "#fff",
            cursor: "pointer",
            fontWeight: "bold",
          }}
        >
          Criar ciclo
        </button>
      </div>

      <div style={{ display: "grid", gap: "12px" }}>
        {ciclos.map((item) => (
          <div
            key={item.id}
            style={{
              border:
                item.status === "ATIVO"
                  ? "1px solid #660099"
                  : "1px solid #ddd",
              borderRadius: "12px",
              padding: "16px",
              backgroundColor: "#fff",
              display: "flex",
              justifyContent: "space-between",
              gap: "16px",
              alignItems: "center",
              flexWrap: "wrap",
            }}
          >
            <div>
              <div style={{ fontSize: "18px", fontWeight: "bold" }}>
                {item.ano} • Ciclo {item.ciclo}
              </div>
              <div
                style={{
                  marginTop: "6px",
                  color: "#555",
                  fontSize: "14px",
                }}
              >
                {formatarPeriodoCiclo(item.dataInicio, item.dataFim)}
              </div>

              <div
                style={{
                  marginTop: "7px",
                  color: "#555",
                  fontSize: "14px",
                }}
              >
                <strong>Metas:</strong>{" "}
                Negócio/Projetos {item.quantidadeMetasNegocio ?? 0}
                {" • "}
                Individuais {item.quantidadeMetasIndividuais ?? 0}
              </div>

              <div
                style={{
                  marginTop: "6px",
                  display: "inline-block",
                  padding: "4px 9px",
                  borderRadius: "999px",
                  fontSize: "12px",
                  fontWeight: "bold",
                  backgroundColor:
                    item.status === "ATIVO"
                      ? "#E7F6EC"
                      : item.status === "PLANEJADO"
                      ? "#FFF4CE"
                      : "#F2F2F2",
                  color:
                    item.status === "ATIVO"
                      ? "#107C41"
                      : item.status === "PLANEJADO"
                      ? "#8A6D00"
                      : "#555",
                }}
              >
                {item.status === "ATIVO"
                  ? "Ativo"
                  : item.status === "PLANEJADO"
                  ? "Planejado"
                  : item.encerradoComPendencias
                  ? "Encerrado com pendências"
                  : "Encerrado"}
              </div>
              {item.encerradoComPendencias &&
                (item.quantidadePendencias ?? 0) > 0 && (
                  <div
                    style={{
                      marginTop: "6px",
                      color: "#A4262C",
                      fontSize: "13px",
                      fontWeight: "bold",
                    }}
                  >
                    {item.quantidadePendencias} nota
                    {item.quantidadePendencias === 1 ? "" : "s"} pendente
                    {item.quantidadePendencias === 1 ? "" : "s"}
                  </div>
                )}
            </div>

            <div
              style={{
                minWidth: "280px",
                flex: "1 1 320px",
              }}
            >
              {editandoPeriodoId === item.id ? (
                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "1fr 1fr auto",
                    gap: "8px",
                    alignItems: "end",
                  }}
                >
                  <label style={{ fontSize: "12px" }}>
                    Início
                    <input
                      type="date"
                      value={periodoInicioEdicao}
                      onChange={(event) =>
                        setPeriodoInicioEdicao(event.target.value)
                      }
                      style={{
                        width: "100%",
                        marginTop: "4px",
                        padding: "8px",
                        boxSizing: "border-box",
                      }}
                    />
                  </label>

                  <label style={{ fontSize: "12px" }}>
                    Fim
                    <input
                      type="date"
                      value={periodoFimEdicao}
                      onChange={(event) =>
                        setPeriodoFimEdicao(event.target.value)
                      }
                      style={{
                        width: "100%",
                        marginTop: "4px",
                        padding: "8px",
                        boxSizing: "border-box",
                      }}
                    />
                  </label>

                  <button
                    type="button"
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
                    style={{
                      padding: "9px 12px",
                      borderRadius: "8px",
                      border: "none",
                      backgroundColor: "#660099",
                      color: "#fff",
                      cursor: "pointer",
                      fontWeight: "bold",
                    }}
                  >
                    Salvar
                  </button>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => {
                    setEditandoPeriodoId(item.id);
                    setPeriodoInicioEdicao(item.dataInicio ?? "");
                    setPeriodoFimEdicao(item.dataFim ?? "");
                    setErro("");
                  }}
                  style={{
                    padding: "9px 13px",
                    borderRadius: "8px",
                    border: "1px solid #777",
                    backgroundColor: "#fff",
                    color: "#555",
                    cursor: "pointer",
                    fontWeight: "bold",
                  }}
                >
                  Editar período
                </button>
              )}
            </div>

            <div
              style={{
                minWidth: "300px",
                flex: "1 1 340px",
              }}
            >
              {item.status === "PLANEJADO" ? (
                editandoMetasId === item.id ? (
                  <div
                    style={{
                      display: "grid",
                      gridTemplateColumns: "1fr 1fr auto",
                      gap: "8px",
                      alignItems: "end",
                    }}
                  >
                    <label style={{ fontSize: "12px" }}>
                      Metas Negócio
                      <select
                        value={metasNegocioEdicao}
                        onChange={(event) =>
                          setMetasNegocioEdicao(
                            Number(event.target.value) as 0 | 1 | 2 | 3
                          )
                        }
                        style={{
                          width: "100%",
                          marginTop: "4px",
                          padding: "8px",
                          boxSizing: "border-box",
                        }}
                      >
                        <option value={0}>0</option>
                        <option value={1}>1</option>
                        <option value={2}>2</option>
                        <option value={3}>3</option>
                      </select>
                    </label>

                    <label style={{ fontSize: "12px" }}>
                      Metas Individuais
                      <select
                        value={metasIndividuaisEdicao}
                        onChange={(event) =>
                          setMetasIndividuaisEdicao(
                            Number(event.target.value) as 0 | 1 | 2 | 3
                          )
                        }
                        style={{
                          width: "100%",
                          marginTop: "4px",
                          padding: "8px",
                          boxSizing: "border-box",
                        }}
                      >
                        <option value={0}>0</option>
                        <option value={1}>1</option>
                        <option value={2}>2</option>
                        <option value={3}>3</option>
                      </select>
                    </label>

                    <button
                      type="button"
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
                      style={{
                        padding: "9px 12px",
                        borderRadius: "8px",
                        border: "none",
                        backgroundColor: "#660099",
                        color: "#fff",
                        cursor: "pointer",
                        fontWeight: "bold",
                      }}
                    >
                      Salvar
                    </button>
                  </div>
                ) : (
                  <button
                    type="button"
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
                    style={{
                      padding: "9px 13px",
                      borderRadius: "8px",
                      border: "1px solid #777",
                      backgroundColor: "#fff",
                      color: "#555",
                      cursor: "pointer",
                      fontWeight: "bold",
                    }}
                  >
                    Editar metas
                  </button>
                )
              ) : (
                <div
                  style={{
                    fontSize: "12px",
                    color: "#777",
                    fontWeight: "600",
                  }}
                >
                  Metas bloqueadas após o início do ciclo
                </div>
              )}
            </div>

            <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
              <button
                type="button"
                onClick={() => navigate(`/ciclos/${item.id}`)}
                style={{
                  padding: "9px 13px",
                  borderRadius: "8px",
                  border: "1px solid #660099",
                  backgroundColor: "#fff",
                  color: "#660099",
                  cursor: "pointer",
                  fontWeight: "bold",
                }}
              >
                Painel da equipe
              </button>

              {editandoStatusId === item.id ? (
                <div
                  style={{
                    display: "flex",
                    gap: "8px",
                    alignItems: "center",
                    flexWrap: "wrap",
                  }}
                >
                  <select
                    value={statusEdicao}
                    onChange={(event) =>
                      setStatusEdicao(
                        event.target.value as StatusCicloAvaliacao
                      )
                    }
                    style={{
                      padding: "9px 10px",
                      borderRadius: "8px",
                      border: "1px solid #999",
                    }}
                  >
                    <option value="PLANEJADO">Planejado</option>
                    <option value="ATIVO">Ativo</option>
                    <option value="ENCERRADO">Encerrado</option>
                  </select>

                  <button
                    type="button"
                    onClick={() => {
                      try {
                        if (statusEdicao === "ENCERRADO") {
                          encerrarComValidacao(item);
                          return;
                        }

                        atualizarStatusCiclo(item.id, statusEdicao);

                        if (statusEdicao === "ATIVO") {
                          const cicloAtivado =
                            getCiclosAvaliacao().find(
                              (cicloAtual) =>
                                cicloAtual.id === item.id
                            );

                          if (cicloAtivado) {
                            criarAvaliacoesDoCicloAtivado(
                              cicloAtivado
                            );
                          }
                        }

                        setEditandoStatusId(null);
                        setErro("");
                        setVersao((valor) => valor + 1);
                      } catch (error) {
                        setErro(
                          error instanceof Error
                            ? error.message
                            : "Não foi possível atualizar o status."
                        );
                      }
                    }}
                    style={{
                      padding: "9px 12px",
                      borderRadius: "8px",
                      border: "none",
                      backgroundColor: "#660099",
                      color: "#fff",
                      cursor: "pointer",
                      fontWeight: "bold",
                    }}
                  >
                    Salvar status
                  </button>

                  <button
                    type="button"
                    onClick={() => setEditandoStatusId(null)}
                    style={{
                      padding: "9px 12px",
                      borderRadius: "8px",
                      border: "1px solid #999",
                      backgroundColor: "#fff",
                      cursor: "pointer",
                    }}
                  >
                    Cancelar
                  </button>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => {
                    setEditandoStatusId(item.id);
                    setStatusEdicao(item.status);
                    setErro("");
                  }}
                  style={{
                    padding: "9px 13px",
                    borderRadius: "8px",
                    border: "1px solid #777",
                    backgroundColor: "#fff",
                    color: "#555",
                    cursor: "pointer",
                    fontWeight: "bold",
                  }}
                >
                  Editar status
                </button>
              )}

              <button
                type="button"
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
                style={{
                  padding: "9px 13px",
                  borderRadius: "8px",
                  border: "1px solid #A4262C",
                  backgroundColor: "#fff",
                  color: "#A4262C",
                  cursor: "pointer",
                  fontWeight: "bold",
                }}
              >
                Excluir ciclo
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default CiclosAvaliacaoPage;
