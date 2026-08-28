import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { getColaboradorByMatricula, getColaboradores } from "../services/colaboradorStorage";
import { saveFeedback, getFeedbacksByColaborador,} from "../services/feedbackStorage";
import type { Feedback } from "../types/Feedback";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { obterPermissoesAvaliacao } from "../services/permissaoAvaliacao";
import { calcularProgressoAvaliacao } from "../services/progressoAvaliacao";
import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import {
  getCicloAtivo,
  formatarPeriodoCiclo,
} from "../services/cicloAvaliacaoStorage";
import {
  getMetasDoColaboradorNoCiclo,
  metaEstaAprovada,
} from "../services/metaStorage";
import "../styles/nova-avaliacao.css";

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


function EvaluationIcon({ children }: { children: ReactNode }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      {children}
    </svg>
  );
}

const criterioIcons: ReactNode[] = [
  <EvaluationIcon>
    <path d="m12 3 1.45 4.55L18 9l-4.55 1.45L12 15l-1.45-4.55L6 9l4.55-1.45L12 3Z" />
    <path d="m18 15 .85 2.15L21 18l-2.15.85L18 21l-.85-2.15L15 18l2.15-.85L18 15Z" />
  </EvaluationIcon>,
  <EvaluationIcon>
    <circle cx="9" cy="8" r="3" />
    <path d="M3.5 19c.6-3.4 2.5-5.2 5.5-5.2s4.9 1.8 5.5 5.2" />
    <circle cx="17" cy="9" r="2.2" />
    <path d="M15.7 14.2c2.9-.4 4.6 1 5 3.8" />
  </EvaluationIcon>,
  <EvaluationIcon>
    <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />
  </EvaluationIcon>,
  <EvaluationIcon>
    <path d="M4 5.5h16v11H9l-5 4v-15Z" />
    <path d="M8 10h8M8 13h5" />
  </EvaluationIcon>,
  <EvaluationIcon>
    <circle cx="12" cy="12" r="8" />
    <circle cx="12" cy="12" r="4" />
    <circle cx="12" cy="12" r="1" />
  </EvaluationIcon>,
  <EvaluationIcon>
    <path d="M5 4.5h9.5A2.5 2.5 0 0 1 17 7v13H7.5A2.5 2.5 0 0 1 5 17.5v-13Z" />
    <path d="M17 7h2a2 2 0 0 1 2 2v11h-4M8 8h6M8 12h6" />
  </EvaluationIcon>,
  <EvaluationIcon>
    <path d="M12 3 20 6v5c0 5.2-2.8 8.5-8 10-5.2-1.5-8-4.8-8-10V6l8-3Z" />
    <path d="m8.5 12 2.2 2.2 4.8-5" />
  </EvaluationIcon>,
  <EvaluationIcon>
    <path d="m13 2-7 11h6l-1 9 7-12h-6l1-8Z" />
  </EvaluationIcon>,
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
  const { usuarioAtual } = useUsuarioAtual();

  const matricula = Number(id);
  const colaborador = Number.isFinite(matricula)
    ? getColaboradorByMatricula(matricula)
    : undefined;

  const colaboradores = getColaboradores();

  const [avaliacoes, setAvaliacoes] = useState<Avaliacoes>(criarEstadoInicial);
  const [votosColegiado, setVotosColegiado] = useState<
    Record<string, Record<string, Record<number, number>>>
  >({});
  const [feedbackFinalGerente, setFeedbackFinalGerente] = useState("");
  const [feedbackFinalCoordenador, setFeedbackFinalCoordenador] = useState("");
  const [status, setStatus] = useState<Feedback["status"]>("RASCUNHO");
  const [criterioAberto, setCriterioAberto] = useState<string>(criterios[0].id);
  const [criterioParaAlinhar, setCriterioParaAlinhar] = useState<string | null>(null);
  const [feedbackFinalAberto, setFeedbackFinalAberto] = useState(false);
  const cicloAtivo = getCicloAtivo();
  const escalaAvaliacao = getEscalaAvaliacao();
    
  if (!colaborador) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Colaborador não encontrado</h1>
      </div>
    );
  }

  if (!cicloAtivo) {
    return (
      <div style={{ padding: "30px" }}>
        <button
          type="button"
          onClick={() => navigate(-1)}
          style={{ marginBottom: "16px" }}
        >
          ← Voltar
        </button>
        <h1>Nenhum ciclo ativo</h1>
        <p>
          Ative um ciclo de avaliação antes de criar uma nova avaliação.
        </p>
        {usuarioAtual?.funcao === "GERENTE" && (
          <button
            type="button"
            onClick={() => navigate("/ciclos")}
          >
            Gerenciar ciclos
          </button>
        )}
      </div>
    );
  }

  const funcaoLabel =
    colaborador.funcao === "GERENTE"
      ? "Gerente"
      : colaborador.funcao === "COORDENADOR"
      ? "Coordenador"
      : colaborador.funcao === "CONSULTOR"
      ? "Consultor"
      : "Analista";

  const senioridadeLabel =
    colaborador.senioridade === "JUNIOR"
      ? "Júnior"
      : colaborador.senioridade === "PLENO"
      ? "Pleno"
      : colaborador.senioridade === "SENIOR"
      ? "Sênior"
      : undefined;

  const gestorDireto = colaborador.gestorDiretoMatricula
    ? colaboradores.find(
        (item) => item.matricula === colaborador.gestorDiretoMatricula
      )
    : undefined;
  const anoAvaliacao = cicloAtivo.ano;
  const cicloAvaliacao = cicloAtivo.ciclo;
  const metasDoCiclo = getMetasDoColaboradorNoCiclo(
    colaborador.matricula,
    cicloAtivo.id
  );
  const metasSemAprovacaoFormal = metasDoCiclo.filter(
    (meta) => !metaEstaAprovada(meta, colaborador, colaboradores)
  );

  const avaliadoresColegiado = (
    colaborador.avaliadoresColegiadoMatriculas ?? []
  )
    .map((matriculaAvaliador) =>
      colaboradores.find(
        (item) => item.matricula === matriculaAvaliador
      )
    )
    .filter((item) => item !== undefined);

  const permissoes = obterPermissoesAvaliacao(
    usuarioAtual,
    colaborador,
    colaboradores
  );

  function podeEditarPapel(papel: PapelAvaliador) {
    if (papel === "gerente") return permissoes.podeAvaliarComoGerente;
    if (papel === "coordenador") return permissoes.podeAvaliarComoCoordenador;
    return permissoes.podeAvaliarComoColegiado;
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

  function atualizarVotoColegiado(
    criterioId: string,
    subcriterio: string,
    avaliadorMatricula: number,
    nota: number
  ) {
    setVotosColegiado((estadoAtual) => {
      const votosAtualizados = {
        ...estadoAtual,
        [criterioId]: {
          ...(estadoAtual[criterioId] ?? {}),
          [subcriterio]: {
            ...(estadoAtual[criterioId]?.[subcriterio] ?? {}),
            [avaliadorMatricula]: nota,
          },
        },
      };

      const notas = Object.values(
        votosAtualizados[criterioId][subcriterio]
      ).filter((valor) => valor > 0);

      const mediaColegiado =
        notas.length === 0
          ? 0
          : notas.reduce((total, valor) => total + valor, 0) /
            notas.length;

      setAvaliacoes((avaliacoesAtuais) => ({
        ...avaliacoesAtuais,
        [criterioId]: {
          ...avaliacoesAtuais[criterioId],
          notas: {
            ...avaliacoesAtuais[criterioId].notas,
            [subcriterio]: {
              ...avaliacoesAtuais[criterioId].notas[subcriterio],
              colegiado: mediaColegiado,
            },
          },
        },
      }));

      return votosAtualizados;
    });
  }

  function renderVotosColegiado(
    criterioId: string,
    subcriterio: string
  ) {
    if (avaliadoresColegiado.length === 0) {
      return (
        <div className="new-evaluation-rater-empty">
          Nenhum avaliador do colegiado cadastrado.
        </div>
      );
    }

    return (
      <div className="new-evaluation-collegiate-list">
        {avaliadoresColegiado.map((avaliador) => {
          const valorAtual =
            votosColegiado[criterioId]?.[subcriterio]?.[
              avaliador.matricula
            ] ?? 0;
          const podeEditar =
            permissoes.podeAvaliarComoColegiado &&
            usuarioAtual?.matricula === avaliador.matricula;

          return (
            <div
              className="new-evaluation-collegiate-member"
              key={avaliador.matricula}
            >
              <strong>
                {avaliador.nome}
                {usuarioAtual?.matricula === avaliador.matricula
                  ? " (você)"
                  : ""}
              </strong>

              <div className={`new-evaluation-note-options ${podeEditar ? "is-editable" : "is-readonly"}`}>
                {[1, 2, 3, 4, 5].map((nota) => (
                  <label className="new-evaluation-note-option" key={nota}>
                    <input
                      type="radio"
                      name={`${criterioId}-${subcriterio}-colegiado-${avaliador.matricula}`}
                      checked={valorAtual === nota}
                      disabled={!podeEditar}
                      onChange={() =>
                        atualizarVotoColegiado(
                          criterioId,
                          subcriterio,
                          avaliador.matricula,
                          nota
                        )
                      }
                    />
                    <span>{nota}</span>
                  </label>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    );
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

  useEffect(() => {
    if (!criterioParaAlinhar) return;

    const elemento = document.getElementById(
      `criterio-toggle-${criterioParaAlinhar}`
    );

    if (!elemento) return;

    const offsetTopo = 118;
    const destino =
      elemento.getBoundingClientRect().top +
      window.scrollY -
      offsetTopo;

    window.scrollTo({
      top: Math.max(0, destino),
      behavior: "smooth",
    });

    setCriterioParaAlinhar(null);
  }, [criterioAberto, criterioParaAlinhar]);
  function abrirCriterioEAlinhar(criterioId: string) {
    setCriterioAberto(criterioId);
    setCriterioParaAlinhar(criterioId);
  }
  function abrirCriterioAnterior(criterioId: string) {
    const indiceAtual = criterios.findIndex((item) => item.id === criterioId);

    if (indiceAtual > 0) {
      abrirCriterioEAlinhar(criterios[indiceAtual - 1].id);
    }
  }

  function abrirProximoCriterioPendente(criterioId: string) {
    const indiceAtual = criterios.findIndex((item) => item.id === criterioId);

    for (let i = indiceAtual + 1; i < criterios.length; i++) {
      const proximoCriterio = criterios[i];

      if (!criterioEstaConcluido(proximoCriterio.id)) {
        abrirCriterioEAlinhar(proximoCriterio.id);
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

  const progressoAvaliacao = calcularProgressoAvaliacao(
    criterios,
    avaliacoes,
    votosColegiado,
    colaborador,
    colaboradores,
    feedbackFinalGerente,
    feedbackFinalCoordenador
  );

  function alterarStatus(novoStatus: Feedback["status"]) {
    if (
      novoStatus !== "RASCUNHO" &&
      !progressoAvaliacao.completo
    ) {
      alert(
        `A avaliação ainda não está completa.\n\n${progressoAvaliacao.pendencias.join(
          "\n"
        )}`
      );
      return;
    }

    if (
      novoStatus === "CONCLUIDA" &&
      status === "RASCUNHO"
    ) {
      alert(
        "A avaliação precisa passar primeiro por 'Pronta para Feedback' antes de ser concluída."
      );
      return;
    }

    setStatus(novoStatus);
  }

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

  function estiloNota(valor: number) {
    if (valor <= 0) return undefined;

    const faixa = getItemEscalaPorNota(valor, escalaAvaliacao);

    return {
      "--score-color": faixa.cor,
      "--score-bg": faixa.corFundo,
      "--score-border": `${faixa.cor}44`,
    } as CSSProperties;
  }
  function renderNotas(
    criterioId: string,
    subcriterio: string,
    papel: PapelAvaliador
  ) {
    const valorAtual = avaliacoes[criterioId].notas[subcriterio][papel];

    return (
      <div className={`new-evaluation-note-options ${podeEditarPapel(papel) ? "is-editable" : "is-readonly"}`}>
        {[1, 2, 3, 4, 5].map((nota) => (
          <label className="new-evaluation-note-option" key={nota}>
            <input
              type="radio"
              name={`${criterioId}-${subcriterio}-${papel}`}
              checked={valorAtual === nota}
              disabled={!podeEditarPapel(papel)}
              onChange={() => atualizarNota(criterioId, subcriterio, papel, nota)}
            />
            <span>{nota}</span>
          </label>
        ))}
      </div>
    );
  }

  function handleSalvarFeedback() {
    if (status !== "RASCUNHO" && !progressoAvaliacao.completo) {
      alert(
        `Não é possível salvar com este status.\n\n${progressoAvaliacao.pendencias.join(
          "\n"
        )}`
      );
      return;
    }

    const agora = new Date().toISOString();

    const novoFeedback = {
      id: crypto.randomUUID(),
      colaboradorId: colaborador!.matricula,
      colaboradorNome: colaborador!.nome,
      data: agora,

      dataCriacao: agora,
      dataUltimaAtualizacao: agora,
      dataConclusao: status === "CONCLUIDA" ? agora : undefined,

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
            votosColegiado: avaliadoresColegiado
              .map((avaliador) => {
                const nota =
                  votosColegiado[criterio.id]?.[subcriterio]?.[
                    avaliador.matricula
                  ] ?? 0;

                return nota > 0
                  ? {
                      avaliadorMatricula: avaliador.matricula,
                      avaliadorNome: avaliador.nome,
                      nota,
                      dataAtualizacao: new Date().toISOString(),
                    }
                  : undefined;
              })
              .filter((voto) => voto !== undefined),
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
    <main className="virtus-page new-evaluation-page">
      <section className="new-evaluation-header">
        <div>
          <button
            type="button"
            className="new-evaluation-header__back"
            onClick={() => navigate(-1)}
          >
            ← Voltar
          </button>
          <h1>Nova Avaliação</h1>
          <p>Preencha os critérios, acompanhe as médias e conclua a avaliação do ciclo.</p>
        </div>
      </section>

      <section className="new-evaluation-person">
        <div className="new-evaluation-person__name">
          <div className="new-evaluation-person__avatar" aria-hidden="true">
            {colaborador.nome
              .split(" ")
              .filter(Boolean)
              .slice(0, 2)
              .map((parte) => parte[0])
              .join("")
              .toUpperCase()}
          </div>
          <div className="new-evaluation-person__identity">
            <div className="new-evaluation-person__title">
              <h2>{colaborador.nome}</h2>
              <span
                className={`new-evaluation-person__status ${
                  colaborador.status === "ATIVO"
                    ? "is-active"
                    : colaborador.status === "LICENCA"
                    ? "is-leave"
                    : "is-inactive"
                }`}
              >
                {colaborador.status === "ATIVO"
                  ? "Ativo"
                  : colaborador.status === "LICENCA"
                  ? "Em licença"
                  : "Desligado"}
              </span>
            </div>

            <div className="new-evaluation-person__role">
              {funcaoLabel}
              {senioridadeLabel ? ` • ${senioridadeLabel}` : ""}
            </div>

            <div className="new-evaluation-person__meta">
              <span>
                <span className="new-evaluation-person__inline-icon">
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <path d="M4 21V5h11v16M15 10h5v11M8 9h3M8 13h3M8 17h3" />
                  </svg>
                </span>
                {colaborador.area}
              </span>

              <span>Matrícula {colaborador.matricula}</span>
            </div>

            {gestorDireto && (
              <div className="new-evaluation-person__manager">
                <span className="new-evaluation-person__inline-icon">
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <circle cx="9" cy="8" r="3" />
                    <path d="M3.5 19c.6-3.4 2.5-5.2 5.5-5.2 2 0 3.5.8 4.4 2.3" />
                    <path d="M16 14h5M18.5 11.5v5" />
                  </svg>
                </span>
                <span>
                  Gestor: <strong>{gestorDireto.nome}</strong>
                </span>
              </div>
            )}
          </div>
        </div>

        <div className="new-evaluation-cycle">
          <span>Ciclo da avaliação</span>
          <strong>
            {anoAvaliacao} • Ciclo {cicloAvaliacao}
          </strong>
          <small>
            {formatarPeriodoCiclo(cicloAtivo.dataInicio, cicloAtivo.dataFim)}
          </small>
        </div>
      </section>

      <section className="new-evaluation-overview">
        <article className="new-evaluation-progress-card">
          <div className="new-evaluation-progress-card__top">
            <div>
              <span className="new-evaluation-progress-card__label">
                Progresso
              </span>
              <h3>Avaliação do ciclo</h3>
            </div>
            <strong className="new-evaluation-progress-card__percent">
              {percentualConcluido}%
            </strong>
          </div>

          <div className="new-evaluation-progress-track">
            <span style={{ width: `${percentualConcluido}%` }} />
          </div>

          <div className="new-evaluation-progress-meta">
            <span>
              {subcriteriosConcluidos} de {totalSubcriterios} subcritérios
            </span>
            <span>
              {notasPreenchidas} de {totalNotasPossiveis} notas preenchidas
            </span>
          </div>
        </article>

        <article className="new-evaluation-role-card">
          <span className="new-evaluation-progress-card__label">
            Seu papel
          </span>
          <h3>Permissões nesta avaliação</h3>
          <div className="new-evaluation-role-list">
            {permissoes.papeisPermitidos.length > 0 ? (
              permissoes.papeisPermitidos.map((papel) => (
                <span key={papel}>{papel}</span>
              ))
            ) : (
              <span>Somente consulta</span>
            )}
          </div>
        </article>
      </section>

      <section className="new-evaluation-status-card">
        <div>
          <span className="new-evaluation-progress-card__label">
            Status da avaliação
          </span>
          <h3>Etapa atual</h3>
        </div>

        <div className="new-evaluation-status-options">
          <label className={status === "RASCUNHO" ? "is-active" : ""}>
            <input
              type="radio"
              checked={status === "RASCUNHO"}
              onChange={() => alterarStatus("RASCUNHO")}
            />
            <span>Rascunho</span>
          </label>

          <label
            className={
              status === "PRONTA_PARA_FEEDBACK" ? "is-active" : ""
            }
          >
            <input
              type="radio"
              checked={status === "PRONTA_PARA_FEEDBACK"}
              onChange={() => alterarStatus("PRONTA_PARA_FEEDBACK")}
            />
            <span>Pronta para feedback</span>
          </label>

          <label className={status === "CONCLUIDA" ? "is-active" : ""}>
            <input
              type="radio"
              checked={status === "CONCLUIDA"}
              onChange={() => alterarStatus("CONCLUIDA")}
            />
            <span>Concluída</span>
          </label>
        </div>

        {!progressoAvaliacao.completo && (
          <p className="new-evaluation-status-card__message">
            Ainda faltam: {progressoAvaliacao.pendencias.join(" • ")}
          </p>
        )}

        {progressoAvaliacao.completo && (
          <p className="new-evaluation-status-card__message is-complete">
            Todas as notas e feedbacks finais obrigatórios foram preenchidos.
          </p>
        )}
      </section>

      {metasSemAprovacaoFormal.length > 0 && (
        <section className="new-evaluation-goals-warning" role="status">
          <div className="new-evaluation-goals-warning__icon" aria-hidden="true">
            !
          </div>
          <div>
            <strong>Meta não formalmente aprovada</strong>
            <p>
              {metasSemAprovacaoFormal.length === 1
                ? "Existe 1 meta deste ciclo que ainda não possui todas as aprovações formais."
                : `Existem ${metasSemAprovacaoFormal.length} metas deste ciclo que ainda não possuem todas as aprovações formais.`}
              {" "}A avaliação pode continuar normalmente.
            </p>
          </div>
        </section>
      )}

      <div className="new-evaluation-section-heading">
        <span>Competências</span>
        <h2>Critérios avaliados</h2>
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
            className="new-evaluation-criterion new-evaluation-criterion--scroll-target"
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
              id={`criterio-toggle-${criterio.id}`}
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
                <span className="new-evaluation-criterion__icon">
                  {criterioIcons[indiceCriterio % criterioIcons.length]}
                </span>

                <div className="new-evaluation-criterion__title">
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

                {calcularNotaCriterio(criterio.id) > 0 ? (
                  <span
                    className="new-evaluation-criterion__score is-semantic"
                    style={estiloNota(calcularNotaCriterio(criterio.id))}
                  >
                    {formatarNota(calcularNotaCriterio(criterio.id))}
                  </span>
                ) : (
                  <span className="new-evaluation-criterion__score is-empty">
                    —
                  </span>
                )}
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
                      className="new-evaluation-subcriterion"
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
                        {calcularMediaSubcriterio(criterio.id, subcriterio) > 0 ? (
                          <div
                            className="new-evaluation-subcriterion__average"
                            style={estiloNota(
                              calcularMediaSubcriterio(
                                criterio.id,
                                subcriterio
                              )
                            )}
                          >
                            <small>Média</small>
                            <strong>
                              {formatarNota(
                                calcularMediaSubcriterio(
                                  criterio.id,
                                  subcriterio
                                )
                              )}
                            </strong>
                          </div>
                        ) : (
                          <div className="new-evaluation-subcriterion__average is-empty">
                            <small>Média</small>
                            <strong>—</strong>
                          </div>
                        )}
                      </div>

                      <div
                        style={{
                          display: "grid",
                          gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
                          gap: "14px",
                        }}
                      >
                        {progressoAvaliacao.gerente.necessario && (
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
                        )}

                        {progressoAvaliacao.coordenador.necessario && (
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
                        )}

                        {progressoAvaliacao.colegiado.necessario && (
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
                            {renderVotosColegiado(criterio.id, subcriterio)}
                          </div>
                        )}
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
                  {progressoAvaliacao.gerente.necessario && (
                    <div>
                      <label style={{ fontWeight: "bold", color: "#333" }}>
                        Observação do Gerente
                      </label>
                      <textarea
                        value={avaliacoes[criterio.id].observacaoGerente}
                        disabled={!permissoes.podeAvaliarComoGerente}
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
                  )}

                  {progressoAvaliacao.coordenador.necessario && (
                    <div>
                      <label style={{ fontWeight: "bold", color: "#333" }}>
                        Observação do Coordenador
                      </label>
                      <textarea
                        value={avaliacoes[criterio.id].observacaoCoordenador}
                        disabled={!permissoes.podeAvaliarComoCoordenador}
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
                  )}
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

      <section className="new-evaluation-summary">
        <div className="new-evaluation-summary__header">
          <div>
            <span className="new-evaluation-progress-card__label">
              Resultado consolidado
            </span>
            <h2>Competências avaliadas</h2>
          </div>

          <div
            className={`new-evaluation-summary__final ${
              notaMedia > 0 ? "has-score" : "is-empty"
            }`}
            style={notaMedia > 0 ? estiloNota(notaMedia) : undefined}
          >
            <span>Nota final</span>
            <strong>{notaMedia > 0 ? formatarNota(notaMedia) : "—"}</strong>
          </div>
        </div>

        <div className="new-evaluation-summary__grid">
          {criterios.map((criterio, indiceCriterio) => {
            const notaCriterio = calcularNotaCriterio(criterio.id);

            return (
              <article
                className={`new-evaluation-summary__item ${
                  notaCriterio > 0 ? "has-score" : "is-empty"
                }`}
                key={criterio.id}
                style={
                  notaCriterio > 0
                    ? estiloNota(notaCriterio)
                    : undefined
                }
              >
                <span className="new-evaluation-summary__icon">
                  {criterioIcons[indiceCriterio % criterioIcons.length]}
                </span>

                <div className="new-evaluation-summary__content">
                  <strong>{criterio.nome}</strong>
                  <small>
                    {notaCriterio > 0 ? "Nota consolidada" : "Ainda não avaliada"}
                  </small>
                </div>

                <span className="new-evaluation-summary__score">
                  {notaCriterio > 0 ? formatarNota(notaCriterio) : "—"}
                </span>
              </article>
            );
          })}
        </div>
      </section>
      <div className={`new-evaluation-final-feedback ${feedbackFinalAberto ? "is-open" : ""}`} style={{
          marginTop: "20px",
          border: feedbackFinalAberto ? "1px solid #660099" : "1px solid #ddd",
          borderRadius: "12px",
          backgroundColor: "#fff",
          overflow: "hidden",
        }}
      >
        <button
          className="new-evaluation-final-feedback__toggle"
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
              {progressoAvaliacao.gerente.necessario && (
                <div>
                  <label style={{ fontWeight: "bold", color: "#333" }}>
                    Feedback Final do Gerente
                  </label>
                  <textarea
                    value={feedbackFinalGerente}
                    disabled={!permissoes.podeAvaliarComoGerente}
                    onChange={(event) => setFeedbackFinalGerente(event.target.value)}
                    style={{
                      width: "100%",
                      minHeight: "230px",
                      marginTop: "8px",
                      padding: "10px",
                      borderRadius: "8px",
                      border: "1px solid #ccc",
                      boxSizing: "border-box",
                    }}
                  />
                </div>
              )}

              {progressoAvaliacao.coordenador.necessario && (
                <div>
                  <label style={{ fontWeight: "bold", color: "#333" }}>
                    Feedback Final do Coordenador
                  </label>
                  <textarea
                    value={feedbackFinalCoordenador}
                    disabled={!permissoes.podeAvaliarComoCoordenador}
                    onChange={(event) =>
                      setFeedbackFinalCoordenador(event.target.value)
                    }
                    style={{
                      width: "100%",
                      minHeight: "230px",
                      marginTop: "8px",
                      padding: "10px",
                      borderRadius: "8px",
                      border: "1px solid #ccc",
                      boxSizing: "border-box",
                    }}
                  />
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      <div className="new-evaluation-save-actions" style={{
          marginTop: "20px",
          display: "flex",
          justifyContent: "center",
        }}>
<button
          onClick={handleSalvarFeedback}
          disabled={!permissoes.podeAvaliar}
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
    </main>
  );
}

export default NovoFeedbackPage;




















