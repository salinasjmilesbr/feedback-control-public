import { useEffect, useState } from "react";
import type { Colaborador } from "../types/Colaborador";
import type {
  Observacao,
  TipoObservacao,
} from "../types/Observacao";
import {
  atualizarObservacao,
  criarObservacao,
  excluirObservacao,
  getObservacoesByColaborador,
} from "../services/observacaoStorage";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import "../styles/observacoes.css";
import {
  getCicloAtivo,
  getCiclosAvaliacao,
  formatarPeriodoCiclo,
} from "../services/cicloAvaliacaoStorage";

type Props = {
  colaborador: Colaborador;
  abrirNovaObservacaoToken?: number;
};

const labelsTipo: Record<TipoObservacao, string> = {
  POSITIVA: "Positiva",
  NEUTRA: "Neutra",
  NEGATIVA: "Negativa",
};

const estiloTipo: Record<
  TipoObservacao,
  { backgroundColor: string; color: string }
> = {
  POSITIVA: {
    backgroundColor: "#E7F6EC",
    color: "#107C41",
  },
  NEUTRA: {
    backgroundColor: "#F2F2F2",
    color: "#555",
  },
  NEGATIVA: {
    backgroundColor: "#FDE7E9",
    color: "#A4262C",
  },
};

function formatarData(data: string) {
  return new Date(data).toLocaleString("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  });
}

function ObservacoesColaborador({
  colaborador,
  abrirNovaObservacaoToken,
}: Props) {
  const { usuarioAtual } = useUsuarioAtual();
  const cicloAtivo = getCicloAtivo();
  const ciclosDisponiveis = getCiclosAvaliacao();

  const [versao, setVersao] = useState(0);
  const [formAberto, setFormAberto] = useState(false);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [tipo, setTipo] = useState<TipoObservacao>("NEUTRA");
  const [texto, setTexto] = useState("");
  const [comunicado, setComunicado] = useState(false);
  const [ano, setAno] = useState(
    cicloAtivo?.ano ?? new Date().getFullYear()
  );
  const [ciclo, setCiclo] = useState<1 | 2 | 3>(
    cicloAtivo?.ciclo ?? 1
  );
  const [mostrarExcluidas, setMostrarExcluidas] = useState(false);
  const [historicoAberto, setHistoricoAberto] = useState<string | null>(
    null
  );
  const [erro, setErro] = useState("");

  useEffect(() => {
    if (!abrirNovaObservacaoToken) return;

    setEditandoId(null);
    setTipo("NEUTRA");
    setTexto("");
    setComunicado(false);
    setAno(cicloAtivo?.ano ?? new Date().getFullYear());
    setCiclo(cicloAtivo?.ciclo ?? 1);
    setErro("");
    setFormAberto(true);
  }, [abrirNovaObservacaoToken, cicloAtivo?.ano, cicloAtivo?.ciclo]);

  void versao;

  const observacoes = getObservacoesByColaborador(
    colaborador.matricula,
    mostrarExcluidas
  );

  const podeGerenciar =
    usuarioAtual?.funcao === "GERENTE" ||
    usuarioAtual?.funcao === "COORDENADOR";

  function limparFormulario() {
    setEditandoId(null);
    setTipo("NEUTRA");
    setTexto("");
    setComunicado(false);
    setAno(cicloAtivo?.ano ?? new Date().getFullYear());
    setCiclo(cicloAtivo?.ciclo ?? 1);
    setErro("");
    setFormAberto(false);
  }

  function iniciarEdicao(observacao: Observacao) {
    setEditandoId(observacao.id);
    setTipo(observacao.tipo);
    setTexto(observacao.texto);
    setComunicado(observacao.comunicado);
    setAno(observacao.ano ?? new Date().getFullYear());
    setCiclo(observacao.ciclo ?? 1);
    setErro("");
    setFormAberto(true);
  }

  function salvar() {
    if (!usuarioAtual || !podeGerenciar) return;

    if (!texto.trim()) {
      setErro("Digite o texto da observação.");
      return;
    }

    try {
      if (editandoId) {
        atualizarObservacao(
          editandoId,
          tipo,
          texto,
          comunicado,
          ano,
          ciclo,
          usuarioAtual
        );
      } else {
        criarObservacao(
          colaborador.matricula,
          tipo,
          texto,
          comunicado,
          ano,
          ciclo,
          usuarioAtual
        );
      }

      limparFormulario();
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível salvar a observação."
      );
    }
  }

  function excluir(observacao: Observacao) {
    if (!usuarioAtual || !podeGerenciar) return;

    const confirmar = window.confirm(
      "Deseja realmente excluir esta observação? Ela permanecerá no histórico."
    );

    if (!confirmar) return;

    excluirObservacao(observacao.id, usuarioAtual);
    setVersao((valor) => valor + 1);
  }

  return (
    <div className="observation-panel">
      <div className="observation-panel__header">
        <div>
          <h3 className="observation-panel__title">Observações</h3>
          <p className="observation-panel__description">
            Registros positivos, neutros ou negativos do colaborador.
          </p>
        </div>

        {podeGerenciar && (
          <div className="observation-panel__actions">
            <label className="observation-toggle">
              <input
                type="checkbox"
                checked={mostrarExcluidas}
                onChange={(event) =>
                  setMostrarExcluidas(event.target.checked)
                }
              />
              Mostrar excluídas
            </label>

            <button
              type="button"
              onClick={() => {
                if (formAberto && !editandoId) {
                  limparFormulario();
                } else {
                  setEditandoId(null);
                  setTipo("NEUTRA");
                  setTexto("");
                  setComunicado(false);
                  setAno(cicloAtivo?.ano ?? new Date().getFullYear());
                  setCiclo(cicloAtivo?.ciclo ?? 1);
                  setErro("");
                  setFormAberto(true);
                }
              }}
              className="virtus-btn virtus-btn--primary"
            >
              + Nova observação
            </button>
          </div>
        )}
      </div>

      {formAberto && podeGerenciar && (
        <div className="observation-form">
          <div className="observation-form__grid">
            <label>
              <strong>Tipo</strong>
              <select
                value={tipo}
                onChange={(event) =>
                  setTipo(event.target.value as TipoObservacao)
                }
                className="observation-control"
              >
                <option value="POSITIVA">Positiva</option>
                <option value="NEUTRA">Neutra</option>
                <option value="NEGATIVA">Negativa</option>
              </select>
            </label>

            <label>
              <strong>Ciclo da observação</strong>
              <select
                value={`${ano}-${ciclo}`}
                onChange={(event) => {
                  const [anoSelecionado, cicloSelecionado] =
                    event.target.value.split("-");

                  setAno(Number(anoSelecionado));
                  setCiclo(Number(cicloSelecionado) as 1 | 2 | 3);
                }}
                className="observation-control"
              >
                {ciclosDisponiveis.map((item) => (
                  <option
                    key={item.id}
                    value={`${item.ano}-${item.ciclo}`}
                  >
                    {item.ano} • Ciclo {item.ciclo} —{" "}
                    {formatarPeriodoCiclo(
                      item.dataInicio,
                      item.dataFim
                    )}
                    {item.status === "ATIVO" ? " (Ativo)" : ""}
                  </option>
                ))}
              </select>
            </label>

            <label>
              <strong>Observação</strong>
              <textarea
                value={texto}
                onChange={(event) => setTexto(event.target.value)}
                className="observation-control observation-control--textarea"
              />
            </label>

            <label className="observation-checkbox">
              <input
                type="checkbox"
                checked={comunicado}
                onChange={(event) =>
                  setComunicado(event.target.checked)
                }
              />
              <strong>Comunicado ao colaborador</strong>
            </label>

            {erro && (
              <div className="observation-form__error">{erro}</div>
            )}

            <div className="observation-form__actions">
              <button
                type="button"
                onClick={limparFormulario}
                className="virtus-btn virtus-btn--outline"
              >
                Cancelar
              </button>

              <button
                type="button"
                onClick={salvar}
                className="virtus-btn virtus-btn--primary"
              >
                {editandoId ? "Salvar alterações" : "Salvar observação"}
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="observation-list">
        {observacoes.length === 0 ? (
          <div className="observation-empty">Nenhuma observação registrada.</div>
        ) : (
          observacoes.map((observacao) => (
            <div
              key={observacao.id}
              className={`observation-card ${
                observacao.tipo === "POSITIVA"
                  ? "is-positive"
                  : observacao.tipo === "NEGATIVA"
                  ? "is-negative"
                  : "is-neutral"
              } ${observacao.excluida ? "is-deleted" : ""}`}
            >
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  gap: "12px",
                  flexWrap: "wrap",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    gap: "8px",
                    flexWrap: "wrap",
                    alignItems: "center",
                  }}
                >
                  <span
                    style={{
                      ...estiloTipo[observacao.tipo],
                      padding: "4px 9px",
                      borderRadius: "999px",
                      fontSize: "12px",
                      fontWeight: "bold",
                    }}
                  >
                    <span aria-hidden="true">
                      {observacao.tipo === "POSITIVA"
                        ? "✓ "
                        : observacao.tipo === "NEGATIVA"
                        ? "! "
                        : "• "}
                    </span>
                    {labelsTipo[observacao.tipo]}
                  </span>

                  <span
                    style={{
                      padding: "4px 9px",
                      borderRadius: "999px",
                      fontSize: "12px",
                      fontWeight: "bold",
                      backgroundColor: "#E8F4FF",
                      color: "#0078D4",
                    }}
                  >
                    {observacao.ano && observacao.ciclo
                      ? `${observacao.ano} • Ciclo ${observacao.ciclo}`
                      : "Sem ciclo"}
                  </span>

                  <span
                    style={{
                      padding: "4px 9px",
                      borderRadius: "999px",
                      fontSize: "12px",
                      fontWeight: "bold",
                      backgroundColor: observacao.comunicado
                        ? "#E7F6EC"
                        : "#FFF4CE",
                      color: observacao.comunicado
                        ? "#107C41"
                        : "#8A6D00",
                    }}
                  >
                    {observacao.comunicado
                      ? "Comunicado"
                      : "Não comunicado"}
                  </span>

                  {observacao.excluida && (
                    <span
                      style={{
                        padding: "4px 9px",
                        borderRadius: "999px",
                        fontSize: "12px",
                        fontWeight: "bold",
                        backgroundColor: "#FDE7E9",
                        color: "#A4262C",
                      }}
                    >
                      Excluída
                    </span>
                  )}
                </div>

                {!observacao.excluida && podeGerenciar && (
                  <div
                    style={{
                      display: "flex",
                      gap: "8px",
                    }}
                  >
                    <button
                      type="button"
                      onClick={() => iniciarEdicao(observacao)}
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
                      onClick={() => excluir(observacao)}
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
                )}
              </div>

<div className="observation-card__text">
                {observacao.texto}
              </div>

<div className="observation-card__meta">
                Registrada por <strong>{observacao.autorNome}</strong>{" "}
                em {formatarData(observacao.dataCriacao)}
                {observacao.dataUltimaAtualizacao !==
                  observacao.dataCriacao && (
                  <>
                    {" "}
                    • Atualizada em{" "}
                    {formatarData(
                      observacao.dataUltimaAtualizacao
                    )}
                  </>
                )}
              </div>

              <button
                type="button"
                onClick={() =>
                  setHistoricoAberto((atual) =>
                    atual === observacao.id ? null : observacao.id
                  )
                }
                className="observation-history-toggle"
              >
                {historicoAberto === observacao.id
                  ? "Ocultar histórico"
                  : `Ver histórico (${observacao.historico.length})`}
              </button>

              {historicoAberto === observacao.id && (
<div className="observation-history">
                  {[...observacao.historico]
                    .reverse()
                    .map((evento) => (
                      <div
                        key={evento.id}
                        style={{
                          fontSize: "12px",
                          color: "#555",
                        }}
                      >
                        <strong>
                          {evento.acao === "CRIACAO"
                            ? "Criação"
                            : evento.acao === "EDICAO"
                            ? "Edição"
                            : "Exclusão"}
                        </strong>
                        {" • "}
                        {formatarData(evento.data)}
                        {" • "}
                        {evento.autorNome}

                        {evento.acao === "EDICAO" &&
                          evento.textoAnterior && (
                            <div
                              style={{
                                marginTop: "4px",
                                padding: "6px 8px",
                                backgroundColor: "#F8F8F8",
                                borderRadius: "6px",
                              }}
                            >
                              Texto anterior: {evento.textoAnterior}
                            </div>
                          )}
                      </div>
                    ))}
                </div>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
}

export default ObservacoesColaborador;
