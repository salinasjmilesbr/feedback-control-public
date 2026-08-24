import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import {
  ativarCiclo,
  criarCiclo,
  encerrarCiclo,
  getCiclosAvaliacao,
  atualizarPeriodoCiclo,
  formatarPeriodoCiclo,
} from "../services/cicloAvaliacaoStorage";

function CiclosAvaliacaoPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const [versao, setVersao] = useState(0);
  const [ano, setAno] = useState(new Date().getFullYear());
  const [ciclo, setCiclo] = useState<1 | 2 | 3>(1);
  const [dataInicio, setDataInicio] = useState("");
  const [dataFim, setDataFim] = useState("");
  const [ativarAgora, setAtivarAgora] = useState(true);
  const [editandoPeriodoId, setEditandoPeriodoId] = useState<string | null>(null);
  const [periodoInicioEdicao, setPeriodoInicioEdicao] = useState("");
  const [periodoFimEdicao, setPeriodoFimEdicao] = useState("");
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
      criarCiclo(
        ano,
        ciclo,
        dataInicio,
        dataFim,
        ativarAgora
      );
      setDataInicio("");
      setDataFim("");
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível criar o ciclo."
      );
    }
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
                  : "Encerrado"}
              </div>
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

            <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
              {item.status !== "ATIVO" && (
                <button
                  type="button"
                  onClick={() => {
                    ativarCiclo(item.id);
                    setVersao((valor) => valor + 1);
                  }}
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
                  Ativar
                </button>
              )}

              {item.status === "ATIVO" && (
                <button
                  type="button"
                  onClick={() => {
                    const confirmar = window.confirm(
                      "Encerrar o ciclo ativo? Novas avaliações ficarão bloqueadas até outro ciclo ser ativado."
                    );

                    if (!confirmar) return;

                    encerrarCiclo(item.id);
                    setVersao((valor) => valor + 1);
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
                  Encerrar ciclo
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default CiclosAvaliacaoPage;
