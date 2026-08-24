import { useState } from "react";
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

type Props = {
  colaborador: Colaborador;
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

function ObservacoesColaborador({ colaborador }: Props) {
  const { usuarioAtual } = useUsuarioAtual();

  const [versao, setVersao] = useState(0);
  const [formAberto, setFormAberto] = useState(false);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [tipo, setTipo] = useState<TipoObservacao>("NEUTRA");
  const [texto, setTexto] = useState("");
  const [comunicado, setComunicado] = useState(false);
  const [ano, setAno] = useState(new Date().getFullYear());
  const [ciclo, setCiclo] = useState<1 | 2 | 3>(1);
  const [mostrarExcluidas, setMostrarExcluidas] = useState(false);
  const [historicoAberto, setHistoricoAberto] = useState<string | null>(
    null
  );
  const [erro, setErro] = useState("");

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
    setAno(new Date().getFullYear());
    setCiclo(1);
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
    <div
      style={{
        marginTop: "30px",
        border: "1px solid #ddd",
        borderRadius: "10px",
        padding: "20px",
        backgroundColor: "#fff",
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          gap: "16px",
          flexWrap: "wrap",
        }}
      >
        <div>
          <h3 style={{ margin: 0 }}>Observações</h3>
          <p
            style={{
              margin: "6px 0 0 0",
              color: "#666",
              fontSize: "14px",
            }}
          >
            Registros positivos, neutros ou negativos do colaborador.
          </p>
        </div>

        {podeGerenciar && (
          <div
            style={{
              display: "flex",
              gap: "10px",
              flexWrap: "wrap",
            }}
          >
            <label
              style={{
                display: "flex",
                gap: "6px",
                alignItems: "center",
                fontSize: "13px",
                color: "#555",
              }}
            >
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
                  setAno(new Date().getFullYear());
                  setCiclo(1);
                  setErro("");
                  setFormAberto(true);
                }
              }}
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
              + Nova observação
            </button>
          </div>
        )}
      </div>

      {formAberto && podeGerenciar && (
        <div
          style={{
            marginTop: "18px",
            padding: "16px",
            borderRadius: "10px",
            border: "1px solid #ddd",
            backgroundColor: "#FAFAFA",
          }}
        >
          <div
            style={{
              display: "grid",
              gap: "12px",
            }}
          >
            <label>
              <strong>Tipo</strong>
              <select
                value={tipo}
                onChange={(event) =>
                  setTipo(event.target.value as TipoObservacao)
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
                <option value="POSITIVA">Positiva</option>
                <option value="NEUTRA">Neutra</option>
                <option value="NEGATIVA">Negativa</option>
              </select>
            </label>

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
                  onChange={(event) =>
                    setAno(Number(event.target.value))
                  }
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

            <label>
              <strong>Observação</strong>
              <textarea
                value={texto}
                onChange={(event) => setTexto(event.target.value)}
                style={{
                  width: "100%",
                  minHeight: "110px",
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
                display: "flex",
                gap: "8px",
                alignItems: "center",
              }}
            >
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
              <div style={{ color: "#A4262C" }}>{erro}</div>
            )}

            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                gap: "10px",
              }}
            >
              <button
                type="button"
                onClick={limparFormulario}
                style={{
                  padding: "9px 14px",
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
                onClick={salvar}
                style={{
                  padding: "9px 14px",
                  borderRadius: "8px",
                  border: "none",
                  backgroundColor: "#660099",
                  color: "#fff",
                  cursor: "pointer",
                  fontWeight: "bold",
                }}
              >
                {editandoId ? "Salvar alterações" : "Salvar observação"}
              </button>
            </div>
          </div>
        </div>
      )}

      <div
        style={{
          display: "grid",
          gap: "12px",
          marginTop: "18px",
        }}
      >
        {observacoes.length === 0 ? (
          <div style={{ color: "#666" }}>
            Nenhuma observação registrada.
          </div>
        ) : (
          observacoes.map((observacao) => (
            <div
              key={observacao.id}
              style={{
                border: "1px solid #eee",
                borderRadius: "10px",
                padding: "14px",
                backgroundColor: observacao.excluida
                  ? "#F5F5F5"
                  : "#fff",
                opacity: observacao.excluida ? 0.75 : 1,
              }}
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

              <div
                style={{
                  marginTop: "12px",
                  whiteSpace: "pre-wrap",
                  color: "#333",
                }}
              >
                {observacao.texto}
              </div>

              <div
                style={{
                  marginTop: "10px",
                  color: "#666",
                  fontSize: "12px",
                }}
              >
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
                style={{
                  marginTop: "10px",
                  border: "none",
                  padding: 0,
                  backgroundColor: "transparent",
                  color: "#660099",
                  cursor: "pointer",
                  fontWeight: "bold",
                  fontSize: "12px",
                }}
              >
                {historicoAberto === observacao.id
                  ? "Ocultar histórico"
                  : `Ver histórico (${observacao.historico.length})`}
              </button>

              {historicoAberto === observacao.id && (
                <div
                  style={{
                    marginTop: "10px",
                    paddingTop: "10px",
                    borderTop: "1px solid #eee",
                    display: "grid",
                    gap: "8px",
                  }}
                >
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
