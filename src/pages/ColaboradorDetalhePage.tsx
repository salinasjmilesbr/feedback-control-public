import { Link, useNavigate, useParams } from "react-router-dom";

import { getColaboradorByMatricula, getColaboradores } from "../services/colaboradorStorage";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";
import type { Feedback } from "../types/Feedback";

const criterioSiglas = [
  "DT",
  "PR",
  "CO",
  "TE",
  "PI",
  "AF",
  "CR",
  "DP",
] as const;

const criterioNomePorSigla: Record<(typeof criterioSiglas)[number], string> = {
  DT: "Desempenho técnico",
  PR: "Produtividade",
  CO: "Comunicação",
  TE: "Trabalho em equipe",
  PI: "Proatividade e iniciativa",
  AF: "Adaptação e flexibilidade",
  CR: "Comprometimento e responsabilidade",
  DP: "Desenvolvimento profissional",
};

function normalizarTexto(valor: string) {
  return valor
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function calcularPercentual(parte: number, total: number) {
  if (total === 0) {
    return 0;
  }

  return Math.round((parte / total) * 100);
}

function obterCorPercentual(percentual: number) {
  if (percentual === 100) {
    return {
      backgroundColor: "#E7F6EC",
      color: "#107C41",
      borderColor: "#B7E3C4",
    };
  }

  if (percentual >= 50) {
    return {
      backgroundColor: "#FFF4CE",
      color: "#8A6D00",
      borderColor: "#F7D774",
    };
  }

  return {
    backgroundColor: "#FDE7E9",
    color: "#A4262C",
    borderColor: "#F3B6BC",
  };
}

function calcularPreenchimentoFeedback(feedback: Feedback) {
  const subcriterios =
    feedback.criteriosDetalhados?.flatMap((criterio) => criterio.subcriterios) ?? [];

  const totalSubcriterios = subcriterios.length;
  const totalNotasPossiveis = totalSubcriterios * 3;

  const notasGerentePreenchidas = subcriterios.filter(
    (subcriterio) => subcriterio.notaGerente > 0
  ).length;

  const notasCoordenadorPreenchidas = subcriterios.filter(
    (subcriterio) => subcriterio.notaCoordenador > 0
  ).length;

  const notasColegiadoPreenchidas = subcriterios.filter(
    (subcriterio) => subcriterio.notaColegiado > 0
  ).length;

  const notasPreenchidas =
    notasGerentePreenchidas +
    notasCoordenadorPreenchidas +
    notasColegiadoPreenchidas;

  return {
    geral: calcularPercentual(notasPreenchidas, totalNotasPossiveis),
    gerente: calcularPercentual(notasGerentePreenchidas, totalSubcriterios),
    coordenador: calcularPercentual(
      notasCoordenadorPreenchidas,
      totalSubcriterios
    ),
    colegiado: calcularPercentual(notasColegiadoPreenchidas, totalSubcriterios),
    notasPreenchidas,
    totalNotasPossiveis,
  };
}

function ColaboradorDetalhePage() {
  const { id } = useParams();
  const navigate = useNavigate();

  const matricula = Number(id);
  const colaborador = Number.isFinite(matricula)
    ? getColaboradorByMatricula(matricula)
    : undefined;

  if (!colaborador) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Colaborador não encontrado</h1>
      </div>
    );
  }

  const todosColaboradores = getColaboradores();

  const gestorDireto = colaborador.gestorDiretoMatricula
    ? todosColaboradores.find(
        (item) => item.matricula === colaborador.gestorDiretoMatricula
      )
    : undefined;

  const avaliadoresColegiado = (
    colaborador.avaliadoresColegiadoMatriculas ?? []
  )
    .map((matriculaAvaliador) =>
      todosColaboradores.find(
        (item) => item.matricula === matriculaAvaliador
      )
    )
    .filter((item) => item !== undefined);

  const funcaoLabel =
    colaborador.funcao === "GERENTE"
      ? "Gerente"
      : colaborador.funcao === "COORDENADOR"
      ? "Coordenador"
      : "Analista";

  const senioridadeLabel =
    colaborador.senioridade === "JUNIOR"
      ? "Júnior"
      : colaborador.senioridade === "PLENO"
      ? "Pleno"
      : colaborador.senioridade === "SENIOR"
      ? "Sênior"
      : undefined;

  const feedbacks = getFeedbacksByColaborador(colaborador.matricula);

  const feedbacksOrdenados = [...feedbacks].sort(
    (a, b) =>
      new Date(b.dataCriacao ?? b.data).getTime() -
      new Date(a.dataCriacao ?? a.data).getTime()
  );

  const quantidadeFeedbacks = feedbacks.length;

  const medias = feedbacks.map((feedback) => feedback.notaMedia);

  const ultimaMedia =
    feedbacksOrdenados.length > 0 ? feedbacksOrdenados[0].notaMedia : 0;

  const maiorMedia = medias.length > 0 ? Math.max(...medias) : 0;

  const menorMedia = medias.length > 0 ? Math.min(...medias) : 0;

  const totalRascunho = feedbacks.filter(
  (feedback) => feedback.status === "RASCUNHO"
  ).length;

  const totalProntaParaFeedback = feedbacks.filter(
  (feedback) => feedback.status === "PRONTA_PARA_FEEDBACK"
  ).length;

  const totalConcluida = feedbacks.filter(
  (feedback) => feedback.status === "CONCLUIDA"
  ).length;

  return (
    <div style={{ padding: "30px" }}>
      <div
        style={{
          display: "flex",
          alignItems: "center",
        }}
      >
        <button
          onClick={() => navigate("/")}
          style={{
            padding: "10px 20px",
            borderRadius: "10px",
            border: "1px solid #660099",
            backgroundColor: "#fff",
            color: "#660099",
            cursor: "pointer",
            fontWeight: "bold",
            fontSize: "16px",
            marginTop: "3px",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          ← Voltar
        </button>

        <h1
          style={{
            margin: 0,
            fontSize: "36px",
            flex: 1,
            textAlign: "center",
          }}
        >
          Detalhe do Colaborador
        </h1>

        <div style={{ width: "85px" }} />
      </div>

      <div
        style={{
          border: "1px solid #ddd",
          borderRadius: "10px",
          padding: "20px",
          marginTop: "20px",
          backgroundColor: "#fff",
        }}
      >
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "flex-start",
            gap: "20px",
          }}
        >
          <div>
            <h2
              style={{
                margin: 0,
                marginBottom: "12px",
                textAlign: "left",
                color: "#660099",
                fontSize: "24px",
              }}
            >
              {colaborador.nome}
            </h2>

            <p
              style={{
                margin: "0 0 8px 0",
                textAlign: "left",
              }}
            >
              <strong>Matrícula:</strong> {colaborador.matricula}
            </p>

            <p
              style={{
                margin: "0 0 8px 0",
                textAlign: "left",
              }}
            >
              <strong>Área:</strong> {colaborador.area}
            </p>

            <p
              style={{
                margin: "0 0 8px 0",
                textAlign: "left",
              }}
            >
              <strong>Função:</strong> {funcaoLabel}
            </p>

            {senioridadeLabel && (
              <p
                style={{
                  margin: "0 0 8px 0",
                  textAlign: "left",
                }}
              >
                <strong>Senioridade:</strong> {senioridadeLabel}
              </p>
            )}

            {gestorDireto && (
              <p
                style={{
                  margin: "0 0 8px 0",
                  textAlign: "left",
                }}
              >
                <strong>Gestor direto:</strong> {gestorDireto.nome}
              </p>
            )}

            {avaliadoresColegiado.length > 0 && (
              <div
                style={{
                  marginTop: "12px",
                  textAlign: "left",
                }}
              >
                <strong>Avaliadores do colegiado:</strong>
                <ul
                  style={{
                    margin: "6px 0 0 20px",
                    padding: 0,
                  }}
                >
                  {avaliadoresColegiado.map((avaliador) => (
                    <li key={avaliador.matricula}>
                      {avaliador.nome}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "flex-end",
              gap: "12px",
              paddingTop: "12px",
            }}
          >
            <span
              style={{
                fontWeight: "bold",
              }}
            >
              {colaborador.status === "ATIVO"
                ? "✅ Ativo"
                : colaborador.status === "LICENCA"
                ? "🟡 Em licença"
                : "❌ Desligado"}
            </span>

            <Link to={`/colaborador/${colaborador.matricula}/novo-feedback`}>
              <button
                style={{
                  padding: "12px 24px",
                  borderRadius: "10px",
                  border: "none",
                  cursor: "pointer",
                  backgroundColor: "#660099",
                  color: "#fff",
                  fontWeight: "bold",
                  fontSize: "15px",
                }}
              >
                + Novo Feedback
              </button>
            </Link>
          </div>
        </div>
      </div>

      <div
        style={{
          marginTop: "20px",
          border: "1px solid #ddd",
          borderRadius: "10px",
          padding: "20px",
          backgroundColor: "#fff",
          textAlign: "center",
        }}
      >
        <h3>Indicadores do Colaborador</h3>

        <div
          style={{
            display: "flex",
            gap: "16px",
            justifyContent: "space-between",
            flexWrap: "wrap",
            marginTop: "20px",
          }}
        >
          <div
            style={{
              flex: 1,
              minWidth: "150px",
              border: "1px solid #eee",
              borderRadius: "12px",
              padding: "16px",
              backgroundColor: "#F4E8FF",
            }}
          >
            <div>Total de Avaliações</div>
            <div
              style={{
                fontSize: "36px",
                fontWeight: "bold",
                marginTop: "8px",
                color: "#660099",
              }}
            >
              {quantidadeFeedbacks}
            </div>
          </div>

          <div
            style={{
              flex: 1,
              minWidth: "150px",
              border: "1px solid #eee",
              borderRadius: "12px",
              padding: "16px",
              backgroundColor: "#E8F4FF",
            }}
          >
            <div>Última Nota</div>
            <div
              style={{
                fontSize: "36px",
                fontWeight: "bold",
                marginTop: "8px",
                color: "#0078D4",
              }}
            >
              {ultimaMedia.toFixed(2)}
            </div>
          </div>

          <div
            style={{
              flex: 1,
              minWidth: "150px",
              border: "1px solid #eee",
              borderRadius: "12px",
              padding: "16px",
              backgroundColor: "#E8F8EF",
            }}
          >
            <div>Melhor Nota</div>
            <div
              style={{
                fontSize: "36px",
                fontWeight: "bold",
                marginTop: "8px",
                color: "#107C41",
              }}
            >
              {maiorMedia.toFixed(2)}
            </div>
          </div>

          <div
            style={{
              flex: 1,
              minWidth: "150px",
              border: "1px solid #eee",
              borderRadius: "8px",
              padding: "16px",
              backgroundColor: "#FFF4E5",
            }}
          >
            <div>Menor Nota</div>
            <div
              style={{
                fontSize: "36px",
                fontWeight: "bold",
                marginTop: "8px",
                color: "#D97706",
              }}
            >
              {menorMedia.toFixed(2)}
            </div>
          </div>          
        </div>

      <div
        style={{
          display: "flex",
          gap: "16px",
          justifyContent: "space-between",
          flexWrap: "wrap",
          marginTop: "16px",
        }}
      >
      
          <div
            style={{
              flex: 1,
              minWidth: "150px",
              border: "1px solid #eee",
              borderRadius: "12px",
              padding: "16px",
              backgroundColor: "#F4E8FF",
            }}
          >
            <div>Rascunho</div>
            <div
              style={{
                fontSize: "36px",
                fontWeight: "bold",
                marginTop: "8px",
                color: "#660099",
              }}
            >
              {totalRascunho}
            </div>
          </div>

          <div
            style={{
              flex: 1,
              minWidth: "150px",
              border: "1px solid #eee",
              borderRadius: "12px",
              padding: "16px",
              backgroundColor: "#FFF4CE",
            }}
          >
            <div>Pronta p/ Feedback</div>
            <div
              style={{
                fontSize: "36px",
                fontWeight: "bold",
                marginTop: "8px",
                color: "#8A6D00",
              }}
            >
              {totalProntaParaFeedback}
            </div>
          </div>

          <div
            style={{
              flex: 1,
              minWidth: "150px",
              border: "1px solid #eee",
              borderRadius: "12px",
              padding: "16px",
              backgroundColor: "#E7F6EC",
            }}
          >
            <div>Concluída</div>
            <div
              style={{
                fontSize: "36px",
                fontWeight: "bold",
                marginTop: "8px",
                color: "#107C41",
              }}
            >
              {totalConcluida}
            </div>
          </div>

                </div>

                </div>

      <div
        style={{
          marginTop: "30px",
          border: "1px solid #ddd",
          borderRadius: "10px",
          padding: "20px",
          backgroundColor: "#fff",
          textAlign: "center",
        }}
      >
        <h3>Avaliações Realizadas</h3>

        {feedbacks.length === 0 ? (
          <p>Nenhum feedback registrado.</p>
        ) : (
          <ul
            style={{
              listStyle: "none",
              padding: 0,
              margin: 0,
            }}
          >
            {feedbacksOrdenados.map((feedback) => {
              const preenchimento = calcularPreenchimentoFeedback(feedback);
              const corGerente = obterCorPercentual(preenchimento.gerente);
              const corCoordenador = obterCorPercentual(
                preenchimento.coordenador
              );
              const corColegiado = obterCorPercentual(preenchimento.colegiado);

              return (
                <li
                  key={feedback.id}
                  onMouseEnter={(event) => {
                    event.currentTarget.style.transform = "translateY(-2px)";
                    event.currentTarget.style.boxShadow =
                      "0 4px 12px rgba(0,0,0,0.10)";
                  }}
                  onMouseLeave={(event) => {
                    event.currentTarget.style.transform = "translateY(0)";
                    event.currentTarget.style.boxShadow =
                      "0 2px 6px rgba(0,0,0,0.05)";
                  }}
                  style={{
                    marginBottom: "12px",
                    border: "1px solid #eee",
                    borderRadius: "12px",
                    padding: "16px",
                    backgroundColor: "#F8FBFF",
                    textAlign: "left",
                    cursor: "pointer",
                    boxShadow: "0 2px 6px rgba(0,0,0,0.05)",
                    transition: "all 0.2s ease",
                  }}
                >
                  <Link
                    to={`/colaborador/${colaborador.matricula}/feedback/${feedback.id}`}
                    style={{
                      color: "#660099",
                      textDecoration: "none",
                      display: "block",
                    }}
                  >
                    <div
                      style={{
                        display: "flex",
                        justifyContent: "space-between",
                        alignItems: "flex-start",
                        gap: "20px",
                      }}
                    >
                      <div
                        style={{
                          minWidth: "190px",
                          maxWidth: "260px",
                        }}
                      >
                        <div
                          style={{
                            fontSize: "11px",
                            textTransform: "uppercase",
                            color: "#666",
                            fontWeight: "bold",
                            letterSpacing: "1px",
                          }}
                        >
                          Nota Final
                        </div>

                        <div
                          style={{
                            fontSize: "34px",
                            fontWeight: "bold",
                            color: "#0078D4",
                            lineHeight: 1,
                            marginTop: "4px",
                          }}
                        >
                          {feedback.notaMedia.toFixed(2)}
                        </div>

                        <div
                          style={{
                            marginTop: "14px",
                          }}
                        >
                          <div
                            style={{
                              display: "flex",
                              justifyContent: "space-between",
                              alignItems: "center",
                              gap: "10px",
                              fontSize: "12px",
                              color: "#555",
                              fontWeight: "bold",
                              marginBottom: "6px",
                            }}
                          >
                            <span>Preenchimento</span>
                            <span>{preenchimento.geral}%</span>
                          </div>

                          <div
                            style={{
                              width: "100%",
                              height: "8px",
                              borderRadius: "999px",
                              backgroundColor: "#EDEDED",
                              overflow: "hidden",
                            }}
                          >
                            <div
                              style={{
                                width: `${preenchimento.geral}%`,
                                height: "100%",
                                borderRadius: "999px",
                                backgroundColor: "#660099",
                                transition: "width 0.2s ease-in-out",
                              }}
                            />
                          </div>

                          <div
                            style={{
                              marginTop: "8px",
                              display: "flex",
                              gap: "6px",
                              flexWrap: "wrap",
                            }}
                          >
                            <span
                              title="Percentual preenchido pelo gerente"
                              style={{
                                padding: "4px 8px",
                                borderRadius: "999px",
                                border: `1px solid ${corGerente.borderColor}`,
                                backgroundColor: corGerente.backgroundColor,
                                color: corGerente.color,
                                fontSize: "11px",
                                fontWeight: "bold",
                                whiteSpace: "nowrap",
                              }}
                            >
                              G {preenchimento.gerente}%
                            </span>

                            <span
                              title="Percentual preenchido pelo coordenador"
                              style={{
                                padding: "4px 8px",
                                borderRadius: "999px",
                                border: `1px solid ${corCoordenador.borderColor}`,
                                backgroundColor: corCoordenador.backgroundColor,
                                color: corCoordenador.color,
                                fontSize: "11px",
                                fontWeight: "bold",
                                whiteSpace: "nowrap",
                              }}
                            >
                              C {preenchimento.coordenador}%
                            </span>

                            <span
                              title="Percentual preenchido pelo colegiado"
                              style={{
                                padding: "4px 8px",
                                borderRadius: "999px",
                                border: `1px solid ${corColegiado.borderColor}`,
                                backgroundColor: corColegiado.backgroundColor,
                                color: corColegiado.color,
                                fontSize: "11px",
                                fontWeight: "bold",
                                whiteSpace: "nowrap",
                              }}
                            >
                              COL {preenchimento.colegiado}%
                            </span>
                          </div>
                        </div>

                        <div
                          style={{
                            marginTop: "12px",
                            fontSize: "13px",
                            color: "#666",
                            lineHeight: 1.5,
                          }}
                        >
                          <div>
                            📅 Avaliado em: {" "}
                            {new Date(
                              feedback.dataCriacao ?? feedback.data
                            ).toLocaleDateString("pt-BR")}
                          </div>

                          {feedback.dataUltimaAtualizacao &&
                            feedback.dataCriacao &&
                            feedback.dataCriacao !==
                              feedback.dataUltimaAtualizacao && (
                              <div style={{ marginTop: "2px" }}>
                                ✏️ Editado em: {" "}
                                {new Date(
                                  feedback.dataUltimaAtualizacao
                                ).toLocaleDateString("pt-BR")}
                              </div>
                            )}
                        </div>
                      </div>

                      <div
                        style={{
                          flex: 1,
                          display: "flex",
                          flexDirection: "column",
                          alignItems: "flex-end",
                        }}
                      >
                        <div
                          style={{
                            display: "flex",
                            gap: "8px",
                            flexWrap: "wrap",
                            justifyContent: "flex-end",
                          }}
                        >
                          {criterioSiglas.map((sigla) => {
                            const nomeCriterioEsperado =
                              criterioNomePorSigla[sigla];

                            const criterioEncontrado =
                              feedback.criteriosDetalhados?.find(
                                (criterio) =>
                                  normalizarTexto(criterio.criterioNome) ===
                                  normalizarTexto(nomeCriterioEsperado)
                              );

                            return (
                              <div
                                key={sigla}
                                title={criterioNomePorSigla[sigla]}
                                style={{
                                  width: "58px",
                                  height: "58px",
                                  border: "1px solid #660099",
                                  borderRadius: "8px",
                                  display: "flex",
                                  flexDirection: "column",
                                  justifyContent: "center",
                                  alignItems: "center",
                                  backgroundColor: "#FAFAFA",
                                  boxShadow: "0 1px 4px rgba(0,0,0,0.08)",
                                  transition: "all 0.2s ease",
                                }}
                              >
                                <div
                                  style={{
                                    fontSize: "10px",
                                    color: "#666",
                                    fontWeight: "bold",
                                  }}
                                >
                                  {sigla}
                                </div>

                                <div
                                  style={{
                                    fontSize: "16px",
                                    color: "#660099",
                                    fontWeight: "bold",
                                  }}
                                >
                                  {criterioEncontrado?.nota.toFixed(1) ?? "-"}
                                </div>
                              </div>
                            );
                          })}
                        </div>

                        <div
                          style={{
                            marginTop: "10px",
                            display: "flex",
                            justifyContent: "flex-end",
                          }}
                        >
                          <div
                            style={{
                              display: "inline-flex",
                              alignItems: "center",
                              gap: "6px",
                              padding: "4px 10px",
                              borderRadius: "999px",
                              backgroundColor: "#F4E8FF",
                              color: "#660099",
                              fontSize: "12px",
                              fontWeight: "bold",
                            }}
                          >
                            {feedback.ano ??
                              new Date(feedback.data).getFullYear()}
                            {" • "}
                            Ciclo {feedback.ciclo ?? 1}
                          </div>
                          <div
                            style={{
                              display: "inline-flex",
                              alignItems: "center",
                              gap: "6px",
                              padding: "4px 10px",
                              borderRadius: "999px",
                              backgroundColor:
                                feedback.status === "CONCLUIDA"
                                  ? "#E7F6EC"
                                  : feedback.status === "PRONTA_PARA_FEEDBACK"
                                  ? "#FFF4CE"
                                  : "#F4E8FF",
                              color:
                                feedback.status === "CONCLUIDA"
                                  ? "#107C41"
                                  : feedback.status === "PRONTA_PARA_FEEDBACK"
                                  ? "#8A6D00"
                                  : "#660099",
                              fontSize: "12px",
                              fontWeight: "bold",
                              marginTop: "0px",
                            }}
                          >
                            {feedback.status === "RASCUNHO" && "📝 Rascunho"}
                            {feedback.status === "PRONTA_PARA_FEEDBACK" &&
                              "🎯 Pronta para Feedback"}
                            {feedback.status === "CONCLUIDA" && "✅ Concluída"}
                          </div>
                        </div>
                      </div>
                    </div>

                    <div
                      style={{
                        marginTop: "16px",
                        fontSize: "14px",
                        color: "#660099",
                        fontWeight: "bold",
                        textAlign: "right",
                      }}
                    >
                      Ver Avaliação →
                    </div>
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}

export default ColaboradorDetalhePage;
