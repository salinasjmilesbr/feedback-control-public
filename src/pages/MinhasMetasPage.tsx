import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getCicloAtivo } from "../services/cicloAvaliacaoStorage";
import {
  atualizarMeta,
  criarMeta,
  excluirMeta,
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
                        color: "#8A6D00",
                        fontSize: "12px",
                        fontWeight: "bold",
                      }}
                    >
                      Em andamento
                    </div>
                  </div>

                  <div
                    style={{
                      display: "flex",
                      gap: "8px",
                      flexWrap: "wrap",
                    }}
                  >
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

        {itens.length < limite && !editandoId && (
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

      {(podeAdicionar || editandoId) &&
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
