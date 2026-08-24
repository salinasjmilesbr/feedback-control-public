import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getCicloAtivo } from "../services/cicloAvaliacaoStorage";
import {
  atualizarAcompanhamentoMeta,
  atualizarMeta,
  criarMeta,
  excluirMeta,
  finalizarMeta,
  getMetasDoColaboradorNoCiclo,
} from "../services/metaStorage";
import type { Meta, TipoMeta } from "../types/Meta";

function MinhasMetasPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();

  const [versao, setVersao] = useState(0);
  const [tipo, setTipo] = useState<TipoMeta>("NEGOCIO_PROJETO");
  const [descricao, setDescricao] = useState("");
  const [kpi, setKpi] = useState("");
  const [valorAlvo, setValorAlvo] = useState("");
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [acompanhandoId, setAcompanhandoId] =
    useState<string | null>(null);
  const [resultadoAtual, setResultadoAtual] = useState("");
  const [progressoPercentual, setProgressoPercentual] = useState(0);
  const [fechandoId, setFechandoId] = useState<string | null>(null);
  const [resultadoFinal, setResultadoFinal] = useState("");
  const [atingida, setAtingida] = useState<boolean | null>(null);
  const [erro, setErro] = useState("");

  void versao;

  if (!usuarioAtual) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Usuário atual não definido</h1>
      </div>
    );
  }

  if (usuarioAtual.funcao === "GERENTE") {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Minhas Metas</h1>
        <p>
          O cadastro de metas próprias ainda não está habilitado para o
          perfil de Gerente.
        </p>
        <button type="button" onClick={() => navigate("/")}>
          ← Voltar
        </button>
      </div>
    );
  }

  const usuario = usuarioAtual;
  const cicloEncontrado = getCicloAtivo();

  if (!cicloEncontrado) {
    return (
      <div style={{ padding: "30px" }}>
        <button
          type="button"
          onClick={() => navigate(-1)}
          style={{ marginBottom: "16px" }}
        >
          ← Voltar
        </button>
        <h1>Minhas Metas</h1>
        <p>
          Não existe um ciclo ativo para cadastro ou acompanhamento de
          metas.
        </p>
      </div>
    );
  }

  const cicloAtivo = cicloEncontrado;

  const metas = getMetasDoColaboradorNoCiclo(
    usuario.matricula,
    cicloAtivo.id
  );

  const metasNegocio = metas.filter(
    (meta) => meta.tipo === "NEGOCIO_PROJETO"
  );
  const metasIndividuais = metas.filter(
    (meta) => meta.tipo === "INDIVIDUAL"
  );

  const limiteNegocio = cicloAtivo.quantidadeMetasNegocio ?? 0;
  const limiteIndividuais =
    cicloAtivo.quantidadeMetasIndividuais ?? 0;

  const limiteAtual =
    tipo === "NEGOCIO_PROJETO"
      ? limiteNegocio
      : limiteIndividuais;

  const quantidadeAtual =
    tipo === "NEGOCIO_PROJETO"
      ? metasNegocio.length
      : metasIndividuais.length;

  const podeAdicionar =
    editandoId !== null || quantidadeAtual < limiteAtual;

  function limparFormulario() {
    setDescricao("");
    setKpi("");
    setValorAlvo("");
    setEditandoId(null);
    setErro("");
  }

  function limparAcompanhamento() {
    setAcompanhandoId(null);
    setResultadoAtual("");
    setProgressoPercentual(0);
    setErro("");
  }

  function iniciarAcompanhamento(meta: Meta) {
    setAcompanhandoId(meta.id);
    setResultadoAtual(meta.resultadoAtual ?? "");
    setProgressoPercentual(meta.progressoPercentual ?? 0);
    setErro("");
  }

  function salvarAcompanhamento() {
    if (!acompanhandoId) return;

    setErro("");

    try {
      atualizarAcompanhamentoMeta(
        acompanhandoId,
        usuario,
        cicloAtivo,
        resultadoAtual,
        progressoPercentual
      );

      limparAcompanhamento();
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível atualizar o andamento da meta."
      );
    }
  }

  function limparFechamento() {
    setFechandoId(null);
    setResultadoFinal("");
    setAtingida(null);
    setErro("");
  }

  function iniciarFechamento(meta: Meta) {
    limparFormulario();
    limparAcompanhamento();
    setFechandoId(meta.id);
    setResultadoFinal(meta.resultadoFinal ?? "");
    setAtingida(
      typeof meta.atingida === "boolean" ? meta.atingida : null
    );
    setErro("");
  }

  function salvarFechamento() {
    if (!fechandoId) return;

    if (atingida === null) {
      setErro("Informe se a meta foi atingida ou não.");
      return;
    }

    setErro("");

    try {
      finalizarMeta(
        fechandoId,
        usuario,
        cicloAtivo,
        resultadoFinal,
        atingida
      );

      limparFechamento();
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível finalizar a meta."
      );
    }
  }

  function formatarDataHora(data?: string) {
    if (!data) return "Ainda não atualizado";

    return new Date(data).toLocaleString("pt-BR", {
      dateStyle: "short",
      timeStyle: "short",
    });
  }

  function salvar() {
    setErro("");

    try {
      if (editandoId) {
        atualizarMeta(
          editandoId,
          usuario,
          cicloAtivo,
          descricao,
          kpi,
          valorAlvo
        );
      } else {
        criarMeta(
          usuario,
          cicloAtivo,
          tipo,
          descricao,
          kpi,
          valorAlvo
        );
      }

      limparFormulario();
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível salvar a meta."
      );
    }
  }

  function editar(meta: Meta) {
    limparAcompanhamento();
    limparFechamento();
    setTipo(meta.tipo);
    setDescricao(meta.descricao);
    setKpi(meta.kpi);
    setValorAlvo(meta.valorAlvo);
    setEditandoId(meta.id);
    setErro("");
  }

  function excluir(meta: Meta) {
    const confirmar = window.confirm(
      "Deseja excluir esta meta? O registro será mantido no histórico."
    );

    if (!confirmar) return;

    try {
      excluirMeta(meta.id, usuario, cicloAtivo);
      if (editandoId === meta.id) limparFormulario();
      if (acompanhandoId === meta.id) limparAcompanhamento();
      if (fechandoId === meta.id) limparFechamento();
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível excluir a meta."
      );
    }
  }

  function renderGrupo(
    titulo: string,
    tipoGrupo: TipoMeta,
    itens: Meta[],
    limite: number
  ) {
    return (
      <div
        style={{
          border: "1px solid #ddd",
          borderRadius: "12px",
          padding: "18px",
          backgroundColor: "#fff",
        }}
      >
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            gap: "12px",
            alignItems: "center",
            flexWrap: "wrap",
          }}
        >
          <h2 style={{ margin: 0, color: "#660099" }}>{titulo}</h2>
          <span
            style={{
              padding: "5px 10px",
              borderRadius: "999px",
              backgroundColor: "#F4E8FF",
              color: "#660099",
              fontSize: "12px",
              fontWeight: "bold",
            }}
          >
            {itens.length} de {limite}
          </span>
        </div>

        {limite === 0 ? (
          <div style={{ marginTop: "14px", color: "#666" }}>
            Esta categoria não foi habilitada para este ciclo.
          </div>
        ) : itens.length === 0 ? (
          <div style={{ marginTop: "14px", color: "#666" }}>
            Nenhuma meta cadastrada.
          </div>
        ) : (
          <div
            style={{
              display: "grid",
              gap: "12px",
              marginTop: "14px",
            }}
          >
            {itens.map((meta, indice) => (
              <div
                key={meta.id}
                style={{
                  border: "1px solid #eee",
                  borderRadius: "10px",
                  padding: "14px",
                  backgroundColor: "#FAFAFA",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    gap: "12px",
                    alignItems: "flex-start",
                  }}
                >
                  <div>
                    <strong>
                      {indice + 1}. {meta.descricao}
                    </strong>

                    <div style={{ marginTop: "10px" }}>
                      <span style={{ color: "#666" }}>KPI:</span>{" "}
                      <strong>{meta.kpi}</strong>
                    </div>

                    <div style={{ marginTop: "5px" }}>
                      <span style={{ color: "#666" }}>Valor-alvo:</span>{" "}
                      <strong>{meta.valorAlvo}</strong>
                    </div>

                    <div
                      style={{
                        marginTop: "8px",
                        color:
                          meta.status === "ATINGIDA"
                            ? "#107C41"
                            : meta.status === "NAO_ATINGIDA"
                            ? "#A4262C"
                            : "#8A6D00",
                        fontSize: "12px",
                        fontWeight: "bold",
                      }}
                    >
                      {meta.status === "ATINGIDA"
                        ? "Atingida"
                        : meta.status === "NAO_ATINGIDA"
                        ? "Não atingida"
                        : "Em andamento"}
                    </div>

                    <div style={{ marginTop: "12px" }}>
                      <div
                        style={{
                          display: "flex",
                          justifyContent: "space-between",
                          gap: "12px",
                          fontSize: "12px",
                          color: "#666",
                        }}
                      >
                        <span>Progresso</span>
                        <strong>
                          {meta.progressoPercentual ?? 0}%
                        </strong>
                      </div>

                      <div
                        style={{
                          height: "8px",
                          marginTop: "5px",
                          borderRadius: "999px",
                          backgroundColor: "#E6E6E6",
                          overflow: "hidden",
                        }}
                      >
                        <div
                          style={{
                            width: `${meta.progressoPercentual ?? 0}%`,
                            height: "100%",
                            backgroundColor: "#660099",
                          }}
                        />
                      </div>
                    </div>

                    <div
                      style={{
                        marginTop: "10px",
                        fontSize: "13px",
                      }}
                    >
                      <span style={{ color: "#666" }}>
                        Resultado atual:
                      </span>{" "}
                      {meta.resultadoAtual?.trim() ? (
                        <strong>{meta.resultadoAtual}</strong>
                      ) : (
                        <span style={{ color: "#999" }}>
                          Ainda não informado
                        </span>
                      )}
                    </div>

                    <div
                      style={{
                        marginTop: "6px",
                        color: "#777",
                        fontSize: "11px",
                      }}
                    >
                      Última atualização:{" "}
                      {formatarDataHora(
                        meta.dataUltimoAcompanhamento
                      )}
                    </div>

                    {meta.status !== "EM_ANDAMENTO" && (
                      <div
                        style={{
                          marginTop: "12px",
                          padding: "10px",
                          borderRadius: "8px",
                          backgroundColor:
                            meta.status === "ATINGIDA"
                              ? "#E7F6EC"
                              : "#FDE7E9",
                        }}
                      >
                        <div style={{ fontSize: "13px" }}>
                          <span style={{ color: "#666" }}>
                            Resultado final:
                          </span>{" "}
                          <strong>{meta.resultadoFinal}</strong>
                        </div>
                        <div
                          style={{
                            marginTop: "5px",
                            fontSize: "11px",
                            color: "#777",
                          }}
                        >
                          Fechada em:{" "}
                          {formatarDataHora(meta.dataFechamento)}
                        </div>
                      </div>
                    )}
                  </div>

                  <div
                    style={{
                      display: "flex",
                      gap: "8px",
                      flexWrap: "wrap",
                    }}
                  >
                    {meta.status === "EM_ANDAMENTO" && (
                      <button
                        type="button"
                        onClick={() => {
                          limparFormulario();
                          limparFechamento();
                          iniciarAcompanhamento(meta);
                        }}
                        style={{
                          border: "none",
                          backgroundColor: "transparent",
                          color: "#0078D4",
                          cursor: "pointer",
                          fontWeight: "bold",
                        }}
                      >
                        Atualizar andamento
                      </button>
                    )}

                    <button
                      type="button"
                      onClick={() => iniciarFechamento(meta)}
                      style={{
                        border: "none",
                        backgroundColor: "transparent",
                        color:
                          meta.status === "EM_ANDAMENTO"
                            ? "#107C41"
                            : "#555",
                        cursor: "pointer",
                        fontWeight: "bold",
                      }}
                    >
                      {meta.status === "EM_ANDAMENTO"
                        ? "Fechar meta"
                        : "Revisar fechamento"}
                    </button>

                    <button
                      type="button"
                      onClick={() => editar(meta)}
                      style={{
                        border: "none",
                        backgroundColor: "transparent",
                        color: "#660099",
                        cursor: "pointer",
                        fontWeight: "bold",
                      }}
                    >
                      Editar
                    </button>

                    <button
                      type="button"
                      onClick={() => excluir(meta)}
                      style={{
                        border: "none",
                        backgroundColor: "transparent",
                        color: "#A4262C",
                        cursor: "pointer",
                        fontWeight: "bold",
                      }}
                    >
                      Excluir
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        {itens.length < limite &&
          !editandoId &&
          !acompanhandoId &&
          !fechandoId && (
          <button
            type="button"
            onClick={() => {
              setTipo(tipoGrupo);
              setDescricao("");
              setKpi("");
              setValorAlvo("");
              setErro("");
            }}
            style={{
              marginTop: "14px",
              border: "none",
              backgroundColor: "transparent",
              color: "#660099",
              cursor: "pointer",
              fontWeight: "bold",
              padding: 0,
            }}
          >
            + Adicionar meta
          </button>
        )}
      </div>
    );
  }

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
          gap: "16px",
          alignItems: "center",
          flexWrap: "wrap",
        }}
      >
        <div>
          <h1 style={{ margin: 0 }}>Minhas Metas</h1>
          <p style={{ margin: "6px 0 0 0", color: "#666" }}>
            {cicloAtivo.ano} • Ciclo {cicloAtivo.ciclo}
          </p>
        </div>

        <button
          type="button"
          onClick={() => navigate(-1)}
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
          ← Voltar
        </button>
      </div>

      <div
        style={{
          marginTop: "18px",
          padding: "14px",
          borderRadius: "10px",
          backgroundColor: "#F8F8F8",
          color: "#555",
        }}
      >
        O ciclo permite até <strong>{limiteNegocio}</strong> meta
        {limiteNegocio === 1 ? "" : "s"} de Negócio/Projetos e{" "}
        <strong>{limiteIndividuais}</strong> meta
        {limiteIndividuais === 1 ? "" : "s"} individual
        {limiteIndividuais === 1 ? "" : "is"}.
      </div>

      <div
        style={{
          display: "grid",
          gap: "16px",
          marginTop: "18px",
        }}
      >
        {renderGrupo(
          "Metas de Negócio / Projetos",
          "NEGOCIO_PROJETO",
          metasNegocio,
          limiteNegocio
        )}

        {renderGrupo(
          "Metas Individuais",
          "INDIVIDUAL",
          metasIndividuais,
          limiteIndividuais
        )}
      </div>

      {fechandoId && (
        <div
          style={{
            marginTop: "18px",
            border: "1px solid #ddd",
            borderRadius: "12px",
            padding: "18px",
            backgroundColor: "#fff",
          }}
        >
          <h2 style={{ marginTop: 0 }}>Fechar meta</h2>

          <label style={{ display: "block" }}>
            <strong>Resultado final</strong>
            <textarea
              value={resultadoFinal}
              onChange={(event) =>
                setResultadoFinal(event.target.value)
              }
              placeholder="Descreva o resultado obtido de acordo com o KPI e o valor-alvo."
              style={{
                width: "100%",
                minHeight: "100px",
                marginTop: "6px",
                padding: "10px",
                borderRadius: "8px",
                border: "1px solid #ccc",
                boxSizing: "border-box",
              }}
            />
          </label>

          <div style={{ marginTop: "16px" }}>
            <strong>Meta atingida?</strong>
            <div
              style={{
                display: "flex",
                gap: "20px",
                marginTop: "10px",
              }}
            >
              <label>
                <input
                  type="radio"
                  checked={atingida === true}
                  onChange={() => setAtingida(true)}
                />{" "}
                Sim
              </label>

              <label>
                <input
                  type="radio"
                  checked={atingida === false}
                  onChange={() => setAtingida(false)}
                />{" "}
                Não
              </label>
            </div>
          </div>

          {erro && (
            <div style={{ marginTop: "12px", color: "#A4262C" }}>
              {erro}
            </div>
          )}

          <div
            style={{
              display: "flex",
              justifyContent: "flex-end",
              gap: "10px",
              marginTop: "16px",
            }}
          >
            <button
              type="button"
              onClick={limparFechamento}
              style={{
                padding: "10px 14px",
                borderRadius: "8px",
                border: "1px solid #999",
                backgroundColor: "#fff",
                cursor: "pointer",
              }}
            >
              Cancelar
            </button>
            <button
              type="button"
              onClick={salvarFechamento}
              style={{
                padding: "10px 16px",
                borderRadius: "8px",
                border: "none",
                backgroundColor: "#660099",
                color: "#fff",
                cursor: "pointer",
                fontWeight: "bold",
              }}
            >
              Salvar fechamento
            </button>
          </div>
        </div>
      )}

      {!fechandoId && acompanhandoId && (
        <div
          style={{
            marginTop: "18px",
            border: "1px solid #ddd",
            borderRadius: "12px",
            padding: "18px",
            backgroundColor: "#fff",
          }}
        >
          <h2 style={{ marginTop: 0 }}>Atualizar andamento</h2>

          <label style={{ display: "block" }}>
            <strong>Resultado atual</strong>
            <textarea
              value={resultadoAtual}
              onChange={(event) =>
                setResultadoAtual(event.target.value)
              }
              placeholder="Ex.: O tempo médio atual caiu para 5,1 horas."
              style={{
                width: "100%",
                minHeight: "90px",
                marginTop: "6px",
                padding: "10px",
                borderRadius: "8px",
                border: "1px solid #ccc",
                boxSizing: "border-box",
              }}
            />
          </label>

          <label
            style={{
              display: "block",
              marginTop: "14px",
            }}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                gap: "12px",
              }}
            >
              <strong>Progresso</strong>
              <strong>{progressoPercentual}%</strong>
            </div>

            <input
              type="range"
              min={0}
              max={100}
              step={5}
              value={progressoPercentual}
              onChange={(event) =>
                setProgressoPercentual(
                  Number(event.target.value)
                )
              }
              style={{
                width: "100%",
                marginTop: "10px",
              }}
            />

            <input
              type="number"
              min={0}
              max={100}
              value={progressoPercentual}
              onChange={(event) => {
                const valor = Number(event.target.value);
                setProgressoPercentual(
                  Math.min(100, Math.max(0, valor))
                );
              }}
              style={{
                width: "110px",
                marginTop: "8px",
                padding: "8px",
                borderRadius: "8px",
                border: "1px solid #ccc",
              }}
            />{" "}
            %
          </label>

          {erro && (
            <div
              style={{
                marginTop: "12px",
                color: "#A4262C",
              }}
            >
              {erro}
            </div>
          )}

          <div
            style={{
              display: "flex",
              justifyContent: "flex-end",
              gap: "10px",
              marginTop: "16px",
            }}
          >
            <button
              type="button"
              onClick={limparAcompanhamento}
              style={{
                padding: "10px 14px",
                borderRadius: "8px",
                border: "1px solid #999",
                backgroundColor: "#fff",
                cursor: "pointer",
              }}
            >
              Cancelar
            </button>

            <button
              type="button"
              onClick={salvarAcompanhamento}
              style={{
                padding: "10px 16px",
                borderRadius: "8px",
                border: "none",
                backgroundColor: "#660099",
                color: "#fff",
                cursor: "pointer",
                fontWeight: "bold",
              }}
            >
              Salvar andamento
            </button>
          </div>
        </div>
      )}

      {!fechandoId &&
        !acompanhandoId &&
        (podeAdicionar || editandoId) &&
        (limiteNegocio > 0 || limiteIndividuais > 0) && (
          <div
            style={{
              marginTop: "18px",
              border: "1px solid #ddd",
              borderRadius: "12px",
              padding: "18px",
              backgroundColor: "#fff",
            }}
          >
            <h2 style={{ marginTop: 0 }}>
              {editandoId ? "Editar meta" : "Nova meta"}
            </h2>

            {!editandoId && (
              <label>
                <strong>Categoria</strong>
                <select
                  value={tipo}
                  onChange={(event) => {
                    setTipo(event.target.value as TipoMeta);
                    setErro("");
                  }}
                  style={{
                    width: "100%",
                    marginTop: "6px",
                    padding: "10px",
                    borderRadius: "8px",
                    border: "1px solid #ccc",
                    boxSizing: "border-box",
                  }}
                >
                  {limiteNegocio > 0 && (
                    <option
                      value="NEGOCIO_PROJETO"
                      disabled={metasNegocio.length >= limiteNegocio}
                    >
                      Negócio / Projetos
                    </option>
                  )}

                  {limiteIndividuais > 0 && (
                    <option
                      value="INDIVIDUAL"
                      disabled={
                        metasIndividuais.length >= limiteIndividuais
                      }
                    >
                      Desenvolvimento Individual
                    </option>
                  )}
                </select>
              </label>
            )}

            <label
              style={{
                display: "block",
                marginTop: editandoId ? 0 : "14px",
              }}
            >
              <strong>Descrição da meta</strong>
              <textarea
                value={descricao}
                onChange={(event) => setDescricao(event.target.value)}
                placeholder="Ex.: Reduzir o tempo médio de publicação"
                style={{
                  width: "100%",
                  minHeight: "90px",
                  marginTop: "6px",
                  padding: "10px",
                  borderRadius: "8px",
                  border: "1px solid #ccc",
                  boxSizing: "border-box",
                }}
              />
            </label>

            <label
              style={{ display: "block", marginTop: "14px" }}
            >
              <strong>KPI mensurável</strong>
              <input
                value={kpi}
                onChange={(event) => setKpi(event.target.value)}
                placeholder="Ex.: Tempo médio entre aprovação e publicação"
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

            <label
              style={{ display: "block", marginTop: "14px" }}
            >
              <strong>Valor-alvo</strong>
              <input
                value={valorAlvo}
                onChange={(event) =>
                  setValorAlvo(event.target.value)
                }
                placeholder="Ex.: ≤ 4 horas, 95%, R$ 1 milhão, 3 projetos"
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

            {erro && (
              <div
                style={{
                  marginTop: "12px",
                  color: "#A4262C",
                }}
              >
                {erro}
              </div>
            )}

            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                gap: "10px",
                marginTop: "16px",
              }}
            >
              {editandoId && (
                <button
                  type="button"
                  onClick={limparFormulario}
                  style={{
                    padding: "10px 14px",
                    borderRadius: "8px",
                    border: "1px solid #999",
                    backgroundColor: "#fff",
                    cursor: "pointer",
                  }}
                >
                  Cancelar
                </button>
              )}

              <button
                type="button"
                onClick={salvar}
                disabled={!podeAdicionar}
                style={{
                  padding: "10px 16px",
                  borderRadius: "8px",
                  border: "none",
                  backgroundColor: "#660099",
                  color: "#fff",
                  cursor: podeAdicionar ? "pointer" : "not-allowed",
                  opacity: podeAdicionar ? 1 : 0.55,
                  fontWeight: "bold",
                }}
              >
                {editandoId ? "Salvar alterações" : "Salvar meta"}
              </button>
            </div>
          </div>
        )}
    </div>
  );
}

export default MinhasMetasPage;
