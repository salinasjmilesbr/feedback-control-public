import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { colaboradores } from "../data/colaboradores";
import { saveFeedback, getFeedbacksByColaborador,} from "../services/feedbackStorage";
import type { Feedback } from "../types/Feedback";

const criterios = [
  {
    id: "desempenho-tecnico",
    nome: "Desempenho técnico",
    subcriterios: [
      "Qualidade do trabalho entregue",
      "Cumprimento de prazos",
      "Conhecimento técnico e aplicação prática",
      "Capacidade de resolver problemas",
    ],
  },
  {
    id: "produtividade",
    nome: "Produtividade",
    subcriterios: [
      "Volume de trabalho realizado",
      "Eficiência no uso do tempo",
      "Organização e priorização de tarefas",
    ],
  },
  {
    id: "comunicacao",
    nome: "Comunicação",
    subcriterios: [
      "Clareza na comunicação verbal e escrita",
      "Capacidade de ouvir e compreender",
      "Participação em reuniões e interações com a equipe",
    ],
  },
  {
    id: "trabalho-em-equipe",
    nome: "Trabalho em equipe",
    subcriterios: [
      "Colaboração com colegas",
      "Respeito e empatia no ambiente de trabalho",
      "Contribuição para um clima positivo",
    ],
  },
  {
    id: "proatividade-e-iniciativa",
    nome: "Proatividade e iniciativa",
    subcriterios: [
      "Capacidade de tomar decisões sem depender sempre de orientação",
      "Sugestão de melhorias e novas ideias",
      "Disposição para assumir responsabilidades",
    ],
  },
  {
    id: "adaptacao-e-flexibilidade",
    nome: "Adaptação e flexibilidade",
    subcriterios: [
      "Reação a mudanças e imprevistos",
      "Facilidade de aprender novas ferramentas ou processos",
      "Resiliência diante de desafios",
    ],
  },
  {
    id: "comprometimento-e-responsabilidade",
    nome: "Comprometimento e responsabilidade",
    subcriterios: [
      "Pontualidade e assiduidade",
      "Cumprimento de metas e compromissos",
      "Alinhamento com os valores da empresa",
    ],
  },
  {
    id: "desenvolvimento-profissional",
    nome: "Desenvolvimento profissional",
    subcriterios: [
      "Busca por aprendizado contínuo",
      "Participação em treinamentos ou cursos",
      "Aplicação de novos conhecimentos no dia a dia",
    ],
  },
];

type PapelAvaliador = "gerente" | "coordenador" | "colegiado";

type NotasPorAvaliador = {
  gerente: number;
  coordenador: number;
  colegiado: number;
};

type AvaliacaoCriterio = {
  notas: Record<string, NotasPorAvaliador>;
  observacaoGerente: string;
  observacaoCoordenador: string;
};

type Avaliacoes = Record<string, AvaliacaoCriterio>;

function criarEstadoInicial(): Avaliacoes {
  return criterios.reduce((acc, criterio) => {
    acc[criterio.id] = {
      notas: criterio.subcriterios.reduce((subAcc, subcriterio) => {
        subAcc[subcriterio] = {
          gerente: 0,
          coordenador: 0,
          colegiado: 0,
        };
        return subAcc;
      }, {} as Record<string, NotasPorAvaliador>),
      observacaoGerente: "",
      observacaoCoordenador: "",
    };
    return acc;
  }, {} as Avaliacoes);
}

function NovoFeedbackPage() {
  const { id } = useParams();
  const navigate = useNavigate();

  const colaborador = colaboradores.find(
    (item) => item.matricula.toString() === id
  );

  const [avaliacoes, setAvaliacoes] = useState<Avaliacoes>(criarEstadoInicial);
  const [feedbackFinalGerente, setFeedbackFinalGerente] = useState("");
  const [feedbackFinalCoordenador, setFeedbackFinalCoordenador] = useState("");
  const [status, setStatus] = useState<Feedback["status"]>("RASCUNHO");
  const [anoAvaliacao] = useState(new Date().getFullYear());
  const [cicloAvaliacao, setCicloAvaliacao] = useState<1 | 2 | 3>(1);
  const [criterioAberto, setCriterioAberto] = useState<string>(criterios[0].id);
  const [feedbackFinalAberto, setFeedbackFinalAberto] = useState(false);
  const feedbacksExistentes = getFeedbacksByColaborador(colaborador?.matricula ?? 0);
  const ciclosUtilizados = feedbacksExistentes.filter((feedback) => feedback.ano === anoAvaliacao).map((feedback) => feedback.ciclo);
  
  if (!colaborador) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Colaborador não encontrado</h1>
      </div>
    );
  }

  function atualizarNota(
    criterioId: string,
    subcriterio: string,
    papel: PapelAvaliador,
    nota: number
  ) {
    setAvaliacoes((estadoAtual) => ({
      ...estadoAtual,
      [criterioId]: {
        ...estadoAtual[criterioId],
        notas: {
          ...estadoAtual[criterioId].notas,
          [subcriterio]: {
            ...estadoAtual[criterioId].notas[subcriterio],
            [papel]: nota,
          },
        },
      },
    }));
  }

  function atualizarObservacao(
    criterioId: string,
    campo: "observacaoGerente" | "observacaoCoordenador",
    valor: string
  ) {
    setAvaliacoes((estadoAtual) => ({
      ...estadoAtual,
      [criterioId]: {
        ...estadoAtual[criterioId],
        [campo]: valor,
      },
    }));
  }

  function calcularMediaSubcriterio(criterioId: string, subcriterio: string) {
    const notas = Object.values(avaliacoes[criterioId].notas[subcriterio]).filter(
      (nota) => nota > 0
    );

    if (notas.length === 0) {
      return 0;
    }

    return notas.reduce((total, nota) => total + nota, 0) / notas.length;
  }

  function calcularNotaCriterio(criterioId: string) {
    const criterio = criterios.find((item) => item.id === criterioId);

    if (!criterio) {
      return 0;
    }

    const mediasSubcriterios = criterio.subcriterios
      .map((subcriterio) => calcularMediaSubcriterio(criterioId, subcriterio))
      .filter((nota) => nota > 0);

    if (mediasSubcriterios.length === 0) {
      return 0;
    }

    return (
      mediasSubcriterios.reduce((total, nota) => total + nota, 0) /
      mediasSubcriterios.length
    );
  }

  function calcularSubcriteriosConcluidosDoCriterio(criterioId: string) {
    const criterio = criterios.find((item) => item.id === criterioId);

    if (!criterio) {
      return 0;
    }

    return criterio.subcriterios.filter((subcriterio) => {
      const notas = avaliacoes[criterioId].notas[subcriterio];
      return notas.gerente > 0 && notas.coordenador > 0 && notas.colegiado > 0;
    }).length;
  }

  function criterioEstaConcluido(criterioId: string) {
    const criterio = criterios.find((item) => item.id === criterioId);

    if (!criterio) {
      return false;
    }

    return (
      calcularSubcriteriosConcluidosDoCriterio(criterioId) ===
      criterio.subcriterios.length
    );
  }

  function abrirCriterioAnterior(criterioId: string) {
    const indiceAtual = criterios.findIndex((item) => item.id === criterioId);

    if (indiceAtual > 0) {
      setCriterioAberto(criterios[indiceAtual - 1].id);
    }
  }

  function abrirProximoCriterioPendente(criterioId: string) {
    const indiceAtual = criterios.findIndex((item) => item.id === criterioId);

    for (let i = indiceAtual + 1; i < criterios.length; i++) {
      const proximoCriterio = criterios[i];

      if (!criterioEstaConcluido(proximoCriterio.id)) {
        setCriterioAberto(proximoCriterio.id);
        return;
      }
    }
  }

  const notasDosCriterios = criterios
    .map((criterio) => calcularNotaCriterio(criterio.id))
    .filter((nota) => nota > 0);

  const notaMedia =
    notasDosCriterios.length === 0
      ? 0
      : notasDosCriterios.reduce((total, nota) => total + nota, 0) /
        notasDosCriterios.length;

  const totalSubcriterios = criterios.reduce(
    (total, criterio) => total + criterio.subcriterios.length,
    0
  );

  const totalNotasPossiveis = totalSubcriterios * 3;

  const subcriteriosConcluidos = criterios.reduce(
    (total, criterio) =>
      total +
      criterio.subcriterios.filter((subcriterio) => {
        const notas = avaliacoes[criterio.id].notas[subcriterio];
        return (
          notas.gerente > 0 &&
          notas.coordenador > 0 &&
          notas.colegiado > 0
        );
      }).length,
    0
  );

  const notasPreenchidas = criterios.reduce(
    (total, criterio) =>
      total +
      criterio.subcriterios.reduce((subtotal, subcriterio) => {
        const notas = avaliacoes[criterio.id].notas[subcriterio];
        return (
          subtotal +
          Object.values(notas).filter((nota) => nota > 0).length
        );
      }, 0),
    0
  );

  const percentualConcluido =
    totalSubcriterios === 0
      ? 0
      : Math.round((subcriteriosConcluidos / totalSubcriterios) * 100);

  const totalFeedbacksFinaisPreenchidos = [
    feedbackFinalGerente,
    feedbackFinalCoordenador,
  ].filter((texto) => texto.trim().length > 0).length;

  const statusFeedbackFinal =
    totalFeedbacksFinaisPreenchidos === 0
      ? "Pendente"
      : `${totalFeedbacksFinaisPreenchidos} comentário${
          totalFeedbacksFinaisPreenchidos > 1 ? "s" : ""
        } preenchido${totalFeedbacksFinaisPreenchidos > 1 ? "s" : ""}`;

  function renderNotas(
    criterioId: string,
    subcriterio: string,
    papel: PapelAvaliador
  ) {
    const valorAtual = avaliacoes[criterioId].notas[subcriterio][papel];

    return (
      <div
        style={{
          display: "flex",
          gap: "12px",
          flexWrap: "wrap",
          marginTop: "8px",
          justifyContent: "center",
        }}
      >
        {[1, 2, 3, 4, 5].map((nota) => (
          <label
            key={nota}
            style={{
              display: "flex",
              alignItems: "center",
              gap: "4px",
              cursor: "pointer",
              color: "#444",
            }}
          >
            <input
              type="radio"
              name={`${criterioId}-${subcriterio}-${papel}`}
              checked={valorAtual === nota}
              onChange={() => atualizarNota(criterioId, subcriterio, papel, nota)}
            />
            {nota}
          </label>
        ))}
      </div>
    );
  }

  function handleSalvarFeedback() {
    const novoFeedback = {
      id: crypto.randomUUID(),
      colaboradorId: colaborador!.matricula,
      colaboradorNome: colaborador!.nome,
      data: new Date().toISOString(),

      dataCriacao: new Date().toISOString(),
      dataUltimaAtualizacao: new Date().toISOString(),

      ano: anoAvaliacao,
      ciclo: cicloAvaliacao,
      status,
      notaMedia,
      competencias: criterios.map((criterio) => {
        const avaliacao = avaliacoes[criterio.id];

        return {
          competenciaId: criterio.id,
          competenciaNome: criterio.nome,
          nota: calcularNotaCriterio(criterio.id),
          comentario: [
            avaliacao.observacaoGerente
              ? `Observação do Gerente: ${avaliacao.observacaoGerente}`
              : "",
            avaliacao.observacaoCoordenador
              ? `Observação do Coordenador: ${avaliacao.observacaoCoordenador}`
              : "",
          ]
            .filter(Boolean)
            .join("\n\n"),
        };
      }),
      criteriosDetalhados: criterios.map((criterio) => ({
        criterioId: criterio.id,
        criterioNome: criterio.nome,
        nota: calcularNotaCriterio(criterio.id),
        subcriterios: criterio.subcriterios.map((subcriterio) => {
          const notas = avaliacoes[criterio.id].notas[subcriterio];

          return {
            nome: subcriterio,
            notaGerente: notas.gerente,
            notaCoordenador: notas.coordenador,
            notaColegiado: notas.colegiado,
            notaFinal: calcularMediaSubcriterio(criterio.id, subcriterio),
          };
        }),
        observacaoGerente: avaliacoes[criterio.id].observacaoGerente,
        observacaoCoordenador: avaliacoes[criterio.id].observacaoCoordenador,
      })),
      feedbackFinalGerente,
      feedbackFinalCoordenador,
    } as unknown as Feedback;

    const feedbackExistente = getFeedbacksByColaborador(
      colaborador!.matricula
    ).find(
      (feedback) =>
        feedback.ano === anoAvaliacao &&
        feedback.ciclo === cicloAvaliacao
    );

if (feedbackExistente) {
  alert(
    `Já existe uma avaliação para ${anoAvaliacao} - Ciclo ${cicloAvaliacao}.`
  );

  return;
}

    saveFeedback(novoFeedback);
    alert("Avaliação salva com sucesso.");
    navigate(`/colaborador/${colaborador!.matricula}`);
  }

  return (
    <div style={{ padding: "30px" }}>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          marginBottom: "30px",
        }}
      >
        <button
          onClick={() => navigate(-1)}
          style={{
            padding: "10px 16px",
            borderRadius: "8px",
            border: "1px solid #660099",
            backgroundColor: "#fff",
            color: "#660099",
            cursor: "pointer",
            fontWeight: "bold",
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
            flex: 1,
            margin: 0,
            textAlign: "center",
            fontSize: "36px",
          }}
        >
          Nova Avaliação
        </h1>

        <div style={{ width: "100px" }}></div>
      </div>

      <div
        style={{
          border: "1px solid #ddd",
          borderRadius: "10px",
          padding: "20px",
          marginBottom: "20px",
          backgroundColor: "#fff",
        }}
      >
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            gap: "20px",
          }}
        >
          <div style={{ flex: 1, textAlign: "left" }}>
            <h2
              style={{
                margin: 0,
                marginBottom: "12px",
                color: "#660099",
                textAlign: "left",
              }}
            >
              {colaborador.nome}
            </h2>
            <p style={{ margin: "0 0 8px 0", textAlign: "left" }}>
              <strong>Matrícula:</strong> {colaborador.matricula}
            </p>
            <p style={{ margin: 0, textAlign: "left" }}>
              <strong>Área:</strong> {colaborador.area}
            </p>
            <div
              style={{
                marginTop: "08px",
                display: "flex",
                alignItems: "center",
                gap: "20px",
                flexWrap: "wrap",
              }}
            >
              <div>
                <strong>Ano:</strong> {anoAvaliacao}
              </div>

              <div style={{ display: "flex", gap: "12px" }}>
                <label>
                  <input
                    type="radio"
                    checked={cicloAvaliacao === 1}
                    disabled={ciclosUtilizados.includes(1)}
                    onChange={() => setCicloAvaliacao(1)}
                  />
                  {" "}Ciclo 1
                </label>

                <label>
                  <input
                    type="radio"
                    checked={cicloAvaliacao === 2}
                    disabled={ciclosUtilizados.includes(2)}
                    onChange={() => setCicloAvaliacao(2)}
                  />
                  {" "}Ciclo 2
                </label>

                <label>
                  <input
                    type="radio"
                    checked={cicloAvaliacao === 3}
                    disabled={ciclosUtilizados.includes(3)}
                    onChange={() => setCicloAvaliacao(3)}
                  />
                  {" "}Ciclo 3
                </label>
              </div>
            </div>
          </div>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              justifyContent: "center",
              alignItems: "flex-end",
              gap: "12px",
            }}
          >
            <span style={{ fontWeight: "bold" }}>
              {colaborador.ativo ? "✅ Ativo" : "❌ Inativo"}
            </span>
          </div>
        </div>
      </div>

      <div
        style={{
          border: "1px solid #ddd",
          borderRadius: "12px",
          padding: "20px",
          marginBottom: "20px",
          backgroundColor: "#fff",
        }}
      >
        <h3
          style={{
            marginTop: 0,
            marginBottom: "20px",
            color: "#660099",
            textAlign: "left",
          }}
        >
          Status da Avaliação
        </h3>

        <div
          style={{
            display: "flex",
            gap: "24px",
            flexWrap: "wrap",
          }}
        >
          <label>
            <input
              type="radio"
              checked={status === "RASCUNHO"}
              onChange={() => setStatus("RASCUNHO")}
            />
            {" "}Rascunho 📝
          </label>

          <label>
            <input
              type="radio"
              checked={status === "PRONTA_PARA_FEEDBACK"}
              onChange={() => setStatus("PRONTA_PARA_FEEDBACK")}
            />
            {" "}Pronta para Feedback 🎯
          </label>

          <label>
            <input
              type="radio"
              checked={status === "CONCLUIDA"}
              onChange={() => setStatus("CONCLUIDA")}
            />
            {" "}Concluída ✅
          </label>
        </div>
      </div>

      <div
        style={{
          border: "1px solid #ddd",
          borderRadius: "12px",
          padding: "20px",
          marginBottom: "20px",
          backgroundColor: "#fff",
        }}
      >
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            gap: "16px",
            marginBottom: "14px",
          }}
        >
          <div>
            <h3
              style={{
                margin: 0,
                color: "#660099",
              }}
            >
              Progresso da Avaliação
            </h3>
            <p
              style={{
                margin: "6px 0 0 0",
                color: "#555",
                fontSize: "14px",
              }}
            >
              {subcriteriosConcluidos} de {totalSubcriterios} subcritérios concluídos
            </p>
          </div>

          <div
            style={{
              fontSize: "28px",
              fontWeight: "bold",
              color: "#660099",
            }}
          >
            {percentualConcluido}%
          </div>
        </div>

        <div
          style={{
            width: "100%",
            height: "12px",
            borderRadius: "999px",
            backgroundColor: "#EDEDED",
            overflow: "hidden",
          }}
        >
          <div
            style={{
              width: `${percentualConcluido}%`,
              height: "100%",
              borderRadius: "999px",
              backgroundColor: "#660099",
              transition: "width 0.2s ease-in-out",
            }}
          ></div>
        </div>

        <div
          style={{
            marginTop: "12px",
            display: "flex",
            justifyContent: "space-between",
            gap: "16px",
            flexWrap: "wrap",
            color: "#555",
            fontSize: "14px",
          }}
        >
          <span>
            Notas preenchidas: {notasPreenchidas} de {totalNotasPossiveis}
          </span>
          <span>
            Critério de conclusão: Gerente + Coordenador + Colegiado
          </span>
        </div>
      </div>

      {criterios.map((criterio) => {
        const estaAberto = criterioAberto === criterio.id;
        const estaConcluido = criterioEstaConcluido(criterio.id);
        const indiceCriterio = criterios.findIndex((item) => item.id === criterio.id);
        const existeCriterioAnterior = indiceCriterio > 0;
        const existeProximoPendente = criterios
          .slice(indiceCriterio + 1)
          .some((item) => !criterioEstaConcluido(item.id));
        const subcriteriosConcluidosDoCriterio = calcularSubcriteriosConcluidosDoCriterio(
          criterio.id
        );

        return (
          <div
            key={criterio.id}
            style={{
              marginTop: "20px",
              border: estaAberto ? "1px solid #660099" : "1px solid #ddd",
              borderRadius: "12px",
              backgroundColor: "#fff",
              overflow: "hidden",
            }}
          >
            <button
              type="button"
              onClick={() =>
                setCriterioAberto((criterioAtual) =>
                  criterioAtual === criterio.id ? "" : criterio.id
                )
              }
              style={{
                width: "100%",
                padding: "18px 20px",
                border: "none",
                backgroundColor: estaAberto ? "#F8F1FF" : "#fff",
                cursor: "pointer",
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                gap: "16px",
                textAlign: "left",
              }}
            >
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "12px",
                  flex: 1,
                }}
              >
                <span
                  style={{
                    fontSize: "18px",
                    color: "#660099",
                    fontWeight: "bold",
                    width: "20px",
                  }}
                >
                  {estaAberto ? "▼" : "▶"}
                </span>

                <div>
                  <h3
                    style={{
                      margin: 0,
                      color: "#660099",
                    }}
                  >
                    {criterio.nome}
                  </h3>

                  <p
                    style={{
                      margin: "6px 0 0 0",
                      color: "#555",
                      fontSize: "14px",
                    }}
                  >
                    {subcriteriosConcluidosDoCriterio} de {criterio.subcriterios.length} subcritérios concluídos
                  </p>
                </div>
              </div>

              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "10px",
                  flexWrap: "wrap",
                  justifyContent: "flex-end",
                }}
              >
                {estaConcluido && (
                  <span
                    style={{
                      padding: "6px 10px",
                      borderRadius: "999px",
                      backgroundColor: "#E7F6EC",
                      color: "#107C10",
                      fontWeight: "bold",
                      fontSize: "13px",
                      whiteSpace: "nowrap",
                    }}
                  >
                    Concluído
                  </span>
                )}

                <span
                  style={{
                    padding: "8px 14px",
                    borderRadius: "12px",
                    backgroundColor: "#E8F4FF",
                    color: "#0078D4",
                    fontWeight: "bold",
                    whiteSpace: "nowrap",
                  }}
                >
                  Nota {calcularNotaCriterio(criterio.id).toFixed(2)}
                </span>
              </div>
            </button>

            {estaAberto && (
              <div
                style={{
                  padding: "20px",
                  borderTop: "1px solid #eee",
                }}
              >
                <div style={{ display: "grid", gap: "18px" }}>
                  {criterio.subcriterios.map((subcriterio) => (
                    <div
                      key={subcriterio}
                      style={{
                        border: "1px solid #eee",
                        borderRadius: "10px",
                        padding: "16px",
                        backgroundColor: "#FAFAFA",
                      }}
                    >
                      <div
                        style={{
                          display: "flex",
                          justifyContent: "space-between",
                          alignItems: "center",
                          gap: "16px",
                          marginBottom: "14px",
                        }}
                      >
                        <div style={{ fontWeight: "bold", color: "#333" }}>
                          {subcriterio}
                        </div>
                        <div
                          style={{
                            padding: "6px 12px",
                            borderRadius: "10px",
                            backgroundColor: "#F4E8FF",
                            color: "#660099",
                            fontWeight: "bold",
                            whiteSpace: "nowrap",
                          }}
                        >
                          Média {calcularMediaSubcriterio(criterio.id, subcriterio).toFixed(2)}
                        </div>
                      </div>

                      <div
                        style={{
                          display: "grid",
                          gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
                          gap: "14px",
                        }}
                      >
                        <div style={{ textAlign: "center" }}>
                          <div
                            style={{
                              fontWeight: "bold",
                              color: "#555",
                              marginBottom: "10px",
                            }}
                          >
                            Nota do Gerente
                          </div>
                          {renderNotas(criterio.id, subcriterio, "gerente")}
                        </div>

                        <div style={{ textAlign: "center" }}>
                          <div
                            style={{
                              fontWeight: "bold",
                              color: "#555",
                              marginBottom: "10px",
                            }}
                          >
                            Nota do Coordenador
                          </div>
                          {renderNotas(criterio.id, subcriterio, "coordenador")}
                        </div>

                        <div style={{ textAlign: "center" }}>
                          <div
                            style={{
                              fontWeight: "bold",
                              color: "#555",
                              marginBottom: "10px",
                            }}
                          >
                            Nota do Colegiado
                          </div>
                          {renderNotas(criterio.id, subcriterio, "colegiado")}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>

                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
                    gap: "16px",
                    marginTop: "20px",
                  }}
                >
                  <div>
                    <label style={{ fontWeight: "bold", color: "#333" }}>
                      Observação do Gerente
                    </label>
                    <textarea
                      value={avaliacoes[criterio.id].observacaoGerente}
                      onChange={(event) =>
                        atualizarObservacao(
                          criterio.id,
                          "observacaoGerente",
                          event.target.value
                        )
                      }
                      style={{
                        width: "100%",
                        minHeight: "90px",
                        marginTop: "8px",
                        padding: "10px",
                        borderRadius: "8px",
                        border: "1px solid #ccc",
                        boxSizing: "border-box",
                      }}
                    />
                  </div>

                  <div>
                    <label style={{ fontWeight: "bold", color: "#333" }}>
                      Observação do Coordenador
                    </label>
                    <textarea
                      value={avaliacoes[criterio.id].observacaoCoordenador}
                      onChange={(event) =>
                        atualizarObservacao(
                          criterio.id,
                          "observacaoCoordenador",
                          event.target.value
                        )
                      }
                      style={{
                        width: "100%",
                        minHeight: "90px",
                        marginTop: "8px",
                        padding: "10px",
                        borderRadius: "8px",
                        border: "1px solid #ccc",
                        boxSizing: "border-box",
                      }}
                    />
                  </div>
                </div>

                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    gap: "12px",
                    marginTop: "20px",
                    flexWrap: "wrap",
                  }}
                >
                  <button
                    type="button"
                    disabled={!existeCriterioAnterior}
                    onClick={() => abrirCriterioAnterior(criterio.id)}
                    style={{
                      padding: "10px 16px",
                      borderRadius: "10px",
                      border: "1px solid #660099",
                      backgroundColor: existeCriterioAnterior ? "#fff" : "#F2F2F2",
                      color: existeCriterioAnterior ? "#660099" : "#999",
                      cursor: existeCriterioAnterior ? "pointer" : "not-allowed",
                      fontWeight: "bold",
                    }}
                  >
                    ← Critério anterior
                  </button>

                  <button
                    type="button"
                    disabled={!existeProximoPendente}
                    onClick={() => abrirProximoCriterioPendente(criterio.id)}
                    style={{
                      padding: "10px 18px",
                      borderRadius: "10px",
                      border: "none",
                      backgroundColor: existeProximoPendente ? "#660099" : "#D9D9D9",
                      color: "#fff",
                      cursor: existeProximoPendente ? "pointer" : "not-allowed",
                      fontWeight: "bold",
                    }}
                  >
                    Próximo critério pendente →
                  </button>
                </div>
              </div>
            )}
          </div>
        );
      })}

      <div
        style={{
          marginTop: "20px",
          border: "1px solid #660099",
          borderRadius: "12px",
          padding: "20px",
          backgroundColor: "#fff",
          textAlign: "center",
        }}
      >
        <h3 style={{ marginTop: 0 }}>Resumo da Avaliação</h3>
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
            gap: "16px",
            marginTop: "20px",
          }}
        >
          {criterios.map((criterio) => (
            <div
              key={criterio.id}
              style={{
                border: "1px solid #eee",
                borderRadius: "12px",
                padding: "16px",
                backgroundColor: "#F8FBFF",
              }}
            >
              <div style={{ fontSize: "14px", color: "#555" }}>
                {criterio.nome}
              </div>
              <div
                style={{
                  marginTop: "8px",
                  fontSize: "28px",
                  fontWeight: "bold",
                  color: "#0078D4",
                }}
              >
                {calcularNotaCriterio(criterio.id).toFixed(2)}
              </div>
            </div>
          ))}
        </div>

        <div
          style={{
            marginTop: "24px",
            paddingTop: "20px",
            borderTop: "1px solid #ddd",
          }}
        >
          <div style={{ fontSize: "16px", color: "#555" }}>Nota Final</div>
          <div
            style={{
              marginTop: "8px",
              fontSize: "36px",
              fontWeight: "bold",
              color: "#660099",
            }}
          >
            {notaMedia.toFixed(2)}
          </div>
        </div>

      </div>

      <div
        style={{
          marginTop: "20px",
          border: feedbackFinalAberto ? "1px solid #660099" : "1px solid #ddd",
          borderRadius: "12px",
          backgroundColor: "#fff",
          overflow: "hidden",
        }}
      >
        <button
          type="button"
          onClick={() => setFeedbackFinalAberto((estadoAtual) => !estadoAtual)}
          style={{
            width: "100%",
            padding: "18px 20px",
            border: "none",
            backgroundColor: feedbackFinalAberto ? "#F8F1FF" : "#fff",
            cursor: "pointer",
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            gap: "16px",
            textAlign: "left",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: "12px",
              flex: 1,
            }}
          >
            <span
              style={{
                fontSize: "18px",
                color: "#660099",
                fontWeight: "bold",
                width: "20px",
              }}
            >
              {feedbackFinalAberto ? "▼" : "▶"}
            </span>

            <div>
              <h3
                style={{
                  margin: 0,
                  color: "#660099",
                }}
              >
                Feedback Final
              </h3>
              <p
                style={{
                  margin: "6px 0 0 0",
                  color: "#555",
                  fontSize: "14px",
                }}
              >
                Disponível para abertura após a explicação das notas
              </p>
            </div>
          </div>

          <span
            style={{
              padding: "8px 14px",
              borderRadius: "12px",
              backgroundColor:
                totalFeedbacksFinaisPreenchidos > 0 ? "#E7F6EC" : "#FFF4CE",
              color: totalFeedbacksFinaisPreenchidos > 0 ? "#107C10" : "#8A6D00",
              fontWeight: "bold",
              whiteSpace: "nowrap",
            }}
          >
            {statusFeedbackFinal}
          </span>
        </button>

        {feedbackFinalAberto && (
          <div
            style={{
              padding: "20px",
              borderTop: "1px solid #eee",
            }}
          >
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
                gap: "16px",
              }}
            >
              <div>
                <label style={{ fontWeight: "bold", color: "#333" }}>
                  Feedback Final do Gerente
                </label>
                <textarea
                  value={feedbackFinalGerente}
                  onChange={(event) => setFeedbackFinalGerente(event.target.value)}
                  style={{
                    width: "100%",
                    minHeight: "160px",
                    marginTop: "8px",
                    padding: "10px",
                    borderRadius: "8px",
                    border: "1px solid #ccc",
                    boxSizing: "border-box",
                  }}
                />
              </div>

              <div>
                <label style={{ fontWeight: "bold", color: "#333" }}>
                  Feedback Final do Coordenador
                </label>
                <textarea
                  value={feedbackFinalCoordenador}
                  onChange={(event) =>
                    setFeedbackFinalCoordenador(event.target.value)
                  }
                  style={{
                    width: "100%",
                    minHeight: "160px",
                    marginTop: "8px",
                    padding: "10px",
                    borderRadius: "8px",
                    border: "1px solid #ccc",
                    boxSizing: "border-box",
                  }}
                />
              </div>
            </div>
          </div>
        )}
      </div>

      <div
        style={{
          marginTop: "20px",
          display: "flex",
          justifyContent: "center",
        }}
      >
        <button
          onClick={handleSalvarFeedback}
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
          Salvar Avaliação
        </button>
      </div>
    </div>
  );
}

export default NovoFeedbackPage;
