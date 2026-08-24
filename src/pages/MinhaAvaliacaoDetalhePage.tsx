import { useNavigate, useParams } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";
import { exportarAvaliacaoPdf } from "../services/exportarAvaliacaoPdf";
import { getObservacoesComunicadasByCiclo } from "../services/observacaoStorage";
import { getCiclosAvaliacao } from "../services/cicloAvaliacaoStorage";
import { getMetasDoColaboradorNoCiclo } from "../services/metaStorage";

function MinhaAvaliacaoDetalhePage() {
  const navigate = useNavigate();
  const { feedbackId } = useParams();
  const { usuarioAtual } = useUsuarioAtual();

  if (!usuarioAtual) {
    return <div style={{ padding: "30px" }}><h1>Usuário atual não definido</h1></div>;
  }

  const feedback = getFeedbacksByColaborador(
    usuarioAtual.matricula
  ).find(
    (item) =>
      item.id === feedbackId &&
      item.status === "CONCLUIDA"
  );

  if (!feedback) {
    return (
      <div style={{ padding: "30px" }}>
        <button type="button" onClick={() => navigate("/")}>
          ← Voltar
        </button>
        <h1>Avaliação não disponível</h1>
        <p>
          Somente avaliações concluídas do próprio colaborador
          podem ser consultadas nesta área.
        </p>
      </div>
    );
  }

  const criterios = feedback.criteriosDetalhados ?? [];

  const observacoesComunicadas = getObservacoesComunicadasByCiclo(
    usuarioAtual.matricula,
    feedback.ano,
    feedback.ciclo
  );

  const cicloDaAvaliacao = getCiclosAvaliacao().find(
    (ciclo) =>
      ciclo.ano === feedback.ano &&
      ciclo.ciclo === feedback.ciclo
  );

  const metasDoCiclo = cicloDaAvaliacao
    ? getMetasDoColaboradorNoCiclo(
        usuarioAtual.matricula,
        cicloDaAvaliacao.id
      )
    : [];

  const metasNegocio = metasDoCiclo.filter(
    (meta) => meta.tipo === "NEGOCIO_PROJETO"
  );

  const metasIndividuais = metasDoCiclo.filter(
    (meta) => meta.tipo === "INDIVIDUAL"
  );

  function labelStatusMeta(status: string) {
    if (status === "ATINGIDA") return "Atingida";
    if (status === "NAO_ATINGIDA") return "Não atingida";
    return "Pendente / Não finalizada";
  }

  return (
    <div style={{ padding: "30px" }}>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          gap: "12px",
          alignItems: "center",
        }}
      >
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

        <button
          type="button"
          onClick={() => exportarAvaliacaoPdf(usuarioAtual, feedback)}
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
          Exportar PDF
        </button>
      </div>

      <h1 style={{ textAlign: "center" }}>Minha Avaliação</h1>

      {feedback.encerradaComPendencias && (
        <div
          style={{
            marginTop: "16px",
            padding: "14px",
            borderRadius: "10px",
            backgroundColor: "#FFF4CE",
            color: "#6B5700",
          }}
        >
          <strong>Avaliação parcialmente concluída.</strong>
          <div style={{ marginTop: "6px" }}>
            O ciclo foi encerrado com notas pendentes. As médias consideram
            somente as avaliações efetivamente realizadas.
          </div>
          {(feedback.pendenciasEncerramento?.length ?? 0) > 0 && (
            <ul style={{ marginBottom: 0 }}>
              {feedback.pendenciasEncerramento!.map((pendencia) => (
                <li key={pendencia}>{pendencia}</li>
              ))}
            </ul>
          )}
        </div>
      )}

      <div style={{
        border: "1px solid #ddd",
        borderRadius: "12px",
        padding: "20px",
        backgroundColor: "#fff",
        marginTop: "20px",
        textAlign: "center",
      }}>
        <div style={{ color: "#555" }}>
          {feedback.ano} • Ciclo {feedback.ciclo}
        </div>
        <div style={{
          marginTop: "8px",
          fontSize: "36px",
          fontWeight: "bold",
          color: "#660099",
        }}>
          {feedback.notaMedia.toFixed(2)}
        </div>
        <div style={{ color: "#555" }}>Nota Final</div>
      </div>

      <div style={{ display: "grid", gap: "16px", marginTop: "20px" }}>
        {criterios.map((criterio) => (
          <div key={criterio.criterioId} style={{
            border: "1px solid #ddd",
            borderRadius: "12px",
            padding: "18px",
            backgroundColor: "#fff",
          }}>
            <div style={{
              display: "flex",
              justifyContent: "space-between",
              gap: "20px",
              alignItems: "center",
            }}>
              <h3 style={{ margin: 0, color: "#660099" }}>
                {criterio.criterioNome}
              </h3>
              <div style={{ textAlign: "right" }}>
                <strong>{criterio.nota.toFixed(2)}</strong>
                {feedback.encerradaComPendencias &&
                  criterio.subcriterios.some((subcriterio) =>
                    usuarioAtual.funcao === "ANALISTA"
                      ? subcriterio.notaGerente <= 0 ||
                        subcriterio.notaCoordenador <= 0 ||
                        subcriterio.notaColegiado <= 0
                      : subcriterio.notaGerente <= 0
                  ) && (
                    <div
                      style={{
                        marginTop: "4px",
                        color: "#8A6D00",
                        fontSize: "12px",
                      }}
                    >
                      Avaliação parcialmente concluída
                    </div>
                  )}
              </div>
            </div>

            <div style={{ display: "grid", gap: "8px", marginTop: "14px" }}>
              {criterio.subcriterios.map((subcriterio) => (
                <div
                  key={subcriterio.nome}
                  style={{
                    padding: "12px 0",
                    borderTop: "1px solid #eee",
                  }}
                >
                  <div
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      gap: "16px",
                      alignItems: "center",
                    }}
                  >
                    <span>{subcriterio.nome}</span>
                    <strong>
                      Nota final: {subcriterio.notaFinal.toFixed(2)}
                    </strong>
                  </div>

                  <div
                    style={{
                      marginTop: "8px",
                      display: "flex",
                      gap: "14px",
                      flexWrap: "wrap",
                      color: "#555",
                      fontSize: "14px",
                    }}
                  >
                    <span>
                      Gerente:{" "}
                      <strong>
                        {subcriterio.notaGerente > 0
                          ? subcriterio.notaGerente.toFixed(2)
                          : "Não avaliado"}
                      </strong>
                    </span>

                    {usuarioAtual.funcao === "ANALISTA" && (
                      <>
                        <span>
                          Coordenador:{" "}
                          <strong>
                            {subcriterio.notaCoordenador > 0
                              ? subcriterio.notaCoordenador.toFixed(2)
                              : "Não avaliado"}
                          </strong>
                        </span>
                        <span>
                          Colegiado:{" "}
                          <strong>
                            {subcriterio.notaColegiado > 0
                              ? subcriterio.notaColegiado.toFixed(2)
                              : "Não avaliado"}
                          </strong>
                        </span>
                      </>
                    )}
                  </div>
                </div>
              ))}

              {(criterio.observacaoGerente ||
                criterio.observacaoCoordenador) && (
                <div
                  style={{
                    marginTop: "16px",
                    paddingTop: "14px",
                    borderTop: "1px solid #ddd",
                    display: "grid",
                    gap: "12px",
                  }}
                >
                  {criterio.observacaoGerente && (
                    <div>
                      <strong>Observação do Gerente</strong>
                      <div
                        style={{
                          marginTop: "6px",
                          padding: "10px",
                          borderRadius: "8px",
                          backgroundColor: "#F8F8F8",
                          whiteSpace: "pre-wrap",
                        }}
                      >
                        {criterio.observacaoGerente}
                      </div>
                    </div>
                  )}

                  {usuarioAtual.funcao === "ANALISTA" &&
                    criterio.observacaoCoordenador && (
                      <div>
                        <strong>Observação do Coordenador</strong>
                        <div
                          style={{
                            marginTop: "6px",
                            padding: "10px",
                            borderRadius: "8px",
                            backgroundColor: "#F8F8F8",
                            whiteSpace: "pre-wrap",
                          }}
                        >
                          {criterio.observacaoCoordenador}
                        </div>
                      </div>
                    )}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      {(feedback.feedbackFinalGerente ||
        feedback.feedbackFinalCoordenador) && (
        <div
          style={{
            marginTop: "20px",
            border: "1px solid #ddd",
            borderRadius: "12px",
            padding: "18px",
            backgroundColor: "#fff",
          }}
        >
          <h3 style={{ marginTop: 0, color: "#660099" }}>
            Feedback Final
          </h3>

          <div style={{ display: "grid", gap: "14px" }}>
            {feedback.feedbackFinalGerente && (
              <div>
                <strong>Gerente</strong>
                <div
                  style={{
                    marginTop: "6px",
                    padding: "12px",
                    borderRadius: "8px",
                    backgroundColor: "#F8F8F8",
                    whiteSpace: "pre-wrap",
                  }}
                >
                  {feedback.feedbackFinalGerente}
                </div>
              </div>
            )}

            {usuarioAtual.funcao === "ANALISTA" &&
              feedback.feedbackFinalCoordenador && (
                <div>
                  <strong>Coordenador</strong>
                  <div
                    style={{
                      marginTop: "6px",
                      padding: "12px",
                      borderRadius: "8px",
                      backgroundColor: "#F8F8F8",
                      whiteSpace: "pre-wrap",
                    }}
                  >
                    {feedback.feedbackFinalCoordenador}
                  </div>
                </div>
              )}
          </div>
        </div>
      )}

      {metasDoCiclo.length > 0 && (
        <div
          style={{
            marginTop: "20px",
            border: "1px solid #ddd",
            borderRadius: "12px",
            padding: "18px",
            backgroundColor: "#fff",
          }}
        >
          <h3 style={{ marginTop: 0, color: "#660099" }}>
            Metas do Ciclo
          </h3>

          {[
            {
              titulo: "Metas de Negócio / Projetos",
              metas: metasNegocio,
            },
            {
              titulo: "Metas Individuais",
              metas: metasIndividuais,
            },
          ].map(
            (grupo) =>
              grupo.metas.length > 0 && (
                <div
                  key={grupo.titulo}
                  style={{ marginTop: "16px" }}
                >
                  <h4 style={{ margin: "0 0 10px 0" }}>
                    {grupo.titulo}
                  </h4>

                  <div style={{ display: "grid", gap: "12px" }}>
                    {grupo.metas.map((meta, indice) => (
                      <div
                        key={meta.id}
                        style={{
                          padding: "14px",
                          borderRadius: "10px",
                          backgroundColor: "#F8F8F8",
                          border: "1px solid #eee",
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
                          <strong>
                            {indice + 1}. {meta.descricao}
                          </strong>
                          <span
                            style={{
                              fontSize: "12px",
                              fontWeight: "bold",
                              color:
                                meta.status === "ATINGIDA"
                                  ? "#107C41"
                                  : meta.status === "NAO_ATINGIDA"
                                  ? "#A4262C"
                                  : "#8A6D00",
                            }}
                          >
                            {labelStatusMeta(meta.status)}
                          </span>
                        </div>

                        <div style={{ marginTop: "10px" }}>
                          KPI: <strong>{meta.kpi}</strong>
                        </div>

                        <div style={{ marginTop: "5px" }}>
                          Valor-alvo: <strong>{meta.valorAlvo}</strong>
                        </div>

                        <div style={{ marginTop: "5px" }}>
                          Resultado final:{" "}
                          {meta.resultadoFinal?.trim() ? (
                            <strong>{meta.resultadoFinal}</strong>
                          ) : (
                            <span style={{ color: "#999" }}>
                              Não informado
                            </span>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )
          )}
        </div>
      )}

      {observacoesComunicadas.length > 0 && (
        <div
          style={{
            marginTop: "20px",
            border: "1px solid #ddd",
            borderRadius: "12px",
            padding: "18px",
            backgroundColor: "#fff",
          }}
        >
          <h3 style={{ marginTop: 0, color: "#660099" }}>
            Observações do Ciclo
          </h3>

          <div style={{ display: "grid", gap: "12px" }}>
            {observacoesComunicadas.map((observacao) => (
              <div
                key={observacao.id}
                style={{
                  padding: "12px",
                  borderRadius: "8px",
                  backgroundColor: "#F8F8F8",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    gap: "12px",
                    flexWrap: "wrap",
                    fontSize: "13px",
                    color: "#666",
                  }}
                >
                  <strong>
                    {observacao.tipo === "POSITIVA"
                      ? "Positiva"
                      : observacao.tipo === "NEGATIVA"
                      ? "Negativa"
                      : "Neutra"}
                  </strong>
                  <span>
                    {new Date(observacao.dataCriacao).toLocaleDateString(
                      "pt-BR"
                    )}
                  </span>
                </div>

                <div
                  style={{
                    marginTop: "8px",
                    whiteSpace: "pre-wrap",
                  }}
                >
                  {observacao.texto}
                </div>

                <div
                  style={{
                    marginTop: "8px",
                    fontSize: "12px",
                    color: "#777",
                  }}
                >
                  Registrada por {observacao.autorNome}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      <div
        style={{
          marginTop: "20px",
          padding: "14px",
          borderRadius: "10px",
          backgroundColor: "#F8F8F8",
          color: "#555",
        }}
      >
        {usuarioAtual.funcao === "ANALISTA"
          ? "Nesta visão aparecem as notas do gerente, coordenador e a média do colegiado, sem revelar os votos individuais."
          : "Nesta visão aparecem apenas as notas, observações e feedbacks do gerente responsável pela avaliação."}
      </div>

    </div>
  );
}

export default MinhaAvaliacaoDetalhePage;
