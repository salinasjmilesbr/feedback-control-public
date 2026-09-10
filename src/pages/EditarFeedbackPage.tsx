import { useEffect, useState, type CSSProperties } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { EvaluationResource } from "../authorization/ResourceContext";
import AccessRestrictedState from "../components/AccessRestrictedState";
import CriterionIcon from "../components/CriterionIcon";
import { getColaboradorByMatricula, getColaboradores } from "../services/colaboradorStorage";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import CollaboratorIdentity from "../components/CollaboratorIdentity";
import RoleExpectationsCard from "../components/RoleExpectationsCard";
import { calcularProgressoAvaliacao } from "../services/progressoAvaliacao";
import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
import { getFeedbacksByColaborador } from "../services/feedbackStorage";
import type { Feedback } from "../types/Feedback";
import { useAuth } from "../auth/AuthContext";
import {
  concluirAvaliacaoSoberana,
  gravarComentarioFinalSoberano,
  gravarNotasSoberanas,
  gravarObservacoesSoberanas,
} from "../services/acessoAvaliacoesSoberanas";
import type {
  ObservacaoDoPainel,
  NotaDoPainelPorNome,
} from "../services/avaliacoesSoberanas/cutoverAvaliacoesService";
import type { PainelParticipante } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import {
  ehCandidataAvaliacaoNova,
  lerAvaliacaoParaTela,
} from "../services/origemAvaliacaoTela";
import {
  getMetasDoColaboradorNoCiclo,
  metaEstaAprovada,
} from "../services/metaStorage";
import {
  formatarPeriodoCiclo,
  getCiclosAvaliacao,
} from "../services/cicloAvaliacaoStorage";
import { getColaboradorEfetivoNoCiclo } from "../services/historicoOrganizacionalStorage";
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

const criterioIcons = Array.from({ length: 8 }, (_, index) => (
  <CriterionIcon index={index} key={index} />
));


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

function criarEstadoInicialEdicao(feedback?: Feedback): Avaliacoes {
  const estadoInicial = criarEstadoInicial();

  feedback?.criteriosDetalhados?.forEach((criterioSalvo) => {
    if (!estadoInicial[criterioSalvo.criterioId]) {
      return;
    }

    estadoInicial[criterioSalvo.criterioId].observacaoGerente =
      criterioSalvo.observacaoGerente ?? "";
    estadoInicial[criterioSalvo.criterioId].observacaoCoordenador =
      criterioSalvo.observacaoCoordenador ?? "";

    criterioSalvo.subcriterios.forEach((subcriterioSalvo) => {
      if (!estadoInicial[criterioSalvo.criterioId].notas[subcriterioSalvo.nome]) {
        return;
      }

      estadoInicial[criterioSalvo.criterioId].notas[subcriterioSalvo.nome] = {
        gerente: subcriterioSalvo.notaGerente ?? 0,
        coordenador: subcriterioSalvo.notaCoordenador ?? 0,
        colegiado: subcriterioSalvo.notaColegiado ?? 0,
      };
    });
  });

  return estadoInicial;
}

function criarVotosColegiadoIniciais(feedback?: Feedback) {
  const votos: Record<string, Record<string, Record<number, number>>> = {};

  feedback?.criteriosDetalhados?.forEach((criterio) => {
    criterio.subcriterios.forEach((subcriterio) => {
      subcriterio.votosColegiado?.forEach((voto) => {
        votos[criterio.criterioId] ??= {};
        votos[criterio.criterioId][subcriterio.nome] ??= {};
        votos[criterio.criterioId][subcriterio.nome][voto.avaliadorMatricula] =
          voto.nota;
      });
    });
  });

  return votos;
}

/** Coluna do formulário correspondente ao papel do ator na ocorrência. */
function colunaDoPapel(roleType: string): keyof NotasPorAvaliador {
  return roleType.startsWith("GESTAO_CADEIA")
    ? "gerente"
    : roleType.startsWith("GESTAO_DIRETA")
      ? "coordenador"
      : "colegiado";
}

interface EstadoInicialEdicao {
  readonly avaliacoes: Avaliacoes;
  readonly feedbackFinalGerente: string;
  readonly feedbackFinalCoordenador: string;
  readonly status: Feedback["status"];
}

/**
 * Estado inicial do formulário, derivado PURAMENTE da origem da avaliação:
 * - avaliação NOVA ⇒ da PRÓPRIA ocorrência devolvida pelo painel (o catálogo
 *   congelado do banco é traduzido para o vocabulário da tela pelo NOME);
 * - legado ⇒ do registro local (somente leitura).
 *
 * Sem estado derivado em efeito: a tela só monta quando a leitura terminou.
 */
function criarEstadoInicialDaOrigem(
  painel: PainelParticipante | null,
  feedbackLegado?: Feedback
): EstadoInicialEdicao {
  if (!painel) {
    return {
      avaliacoes: criarEstadoInicialEdicao(feedbackLegado),
      feedbackFinalGerente: feedbackLegado?.feedbackFinalGerente ?? "",
      feedbackFinalCoordenador: feedbackLegado?.feedbackFinalCoordenador ?? "",
      status: feedbackLegado?.status ?? "RASCUNHO",
    };
  }

  const avaliacoes = criarEstadoInicial();
  const coluna = colunaDoPapel(painel.participanteRoleType);
  const notaPorOcorrencia = new Map(
    painel.minhasNotas.map((registro) => [registro.subcriterionId, registro.nota])
  );

  // Tradução ESTRUTURAL banco → tela: o critério é identificado pelo NOME do
  // catálogo congelado e o subcritério pelo nome dentro do critério correto.
  for (const criterio of criterios) {
    const criterioCongelado = painel.criterios.find(
      (item) => item.name === criterio.nome
    );
    if (!criterioCongelado) continue;

    for (const subcriterio of criterio.subcriterios) {
      const subcriterioCongelado = painel.subcriterios.find(
        (item) =>
          item.criterionCode === criterioCongelado.code &&
          item.name === subcriterio
      );
      if (!subcriterioCongelado) continue;

      const nota = notaPorOcorrencia.get(subcriterioCongelado.subcriterionId) ?? 0;
      if (nota > 0) avaliacoes[criterio.id].notas[subcriterio][coluna] = nota;
    }
  }

  const comentarioDoCriterio = new Map(
    painel.meusComentarios
      .filter(
        (comentario) =>
          comentario.escopo === "CRITERIO" && comentario.criterionId !== null
      )
      .map((comentario) => [String(comentario.criterionId), comentario.texto])
  );
  for (const criterio of criterios) {
    const criterioCongelado = painel.criterios.find(
      (item) => item.name === criterio.nome
    );
    if (!criterioCongelado) continue;
    const texto = comentarioDoCriterio.get(criterioCongelado.criterionId) ?? "";
    if (!texto) continue;
    if (coluna === "gerente") avaliacoes[criterio.id].observacaoGerente = texto;
    if (coluna === "coordenador") {
      avaliacoes[criterio.id].observacaoCoordenador = texto;
    }
  }

  const textoFinal =
    painel.meusComentarios.find((comentario) => comentario.escopo === "FINAL")
      ?.texto ?? "";

  return {
    avaliacoes,
    feedbackFinalGerente: coluna === "gerente" ? textoFinal : "",
    feedbackFinalCoordenador: coluna === "coordenador" ? textoFinal : "",
    status: (painel.status as Feedback["status"]) ?? "RASCUNHO",
  };
}

function EditarFeedbackPage() {
  const { id, feedbackId } = useParams();
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const { organizacaoAtivaId } = useAuth();

  const matricula = Number(id);
  const colaborador = Number.isFinite(matricula)
    ? getColaboradorByMatricula(matricula)
    : undefined;

  const colaboradores = getColaboradores();

  const feedbacks = colaborador
    ? getFeedbacksByColaborador(colaborador.matricula)
    : [];

  const feedbackLegado = feedbacks.find((item) => item.id === feedbackId);
  // Id com formato técnico é CANDIDATO a avaliação nova: a existência é provada
  // pelo SERVIDOR (soberano-first), não pelo formato nem pelo livro-caixa local.
  const candidataAvaliacaoNova = ehCandidataAvaliacaoNova(feedbackId);

  const [painel, setPainel] = useState<PainelParticipante | null>(null);
  const [carregandoNova, setCarregandoNova] = useState(candidataAvaliacaoNova);
  const [erroLeitura, setErroLeitura] = useState("");
  const [salvando, setSalvando] = useState(false);
  const [erroAcao, setErroAcao] = useState("");

  // Estado EDITADO pelo usuário. `null` = ainda não editado, e o valor exibido é
  // derivado da origem (painel do banco ou registro legado).
  const [avaliacoesEditadas, setAvaliacoes] = useState<Avaliacoes | null>(null);
  const [votosColegiado, setVotosColegiado] = useState<
    Record<string, Record<string, Record<number, number>>>
  >(() => criarVotosColegiadoIniciais(feedbackLegado));
  const [feedbackFinalGerenteEditado, setFeedbackFinalGerente] = useState<
    string | null
  >(null);
  const [feedbackFinalCoordenadorEditado, setFeedbackFinalCoordenador] = useState<
    string | null
  >(null);
  const [statusEditado, setStatus] = useState<Feedback["status"] | null>(null);
  const [criterioAberto, setCriterioAberto] = useState<string>(criterios[0].id);
  const [criterioParaAlinhar, setCriterioParaAlinhar] = useState<string | null>(null);
  const [feedbackFinalAberto, setFeedbackFinalAberto] = useState(false);

  // Leitura da avaliação NOVA: o painel do próprio participante (server-side)
  // devolve o catálogo congelado e SOMENTE a própria ocorrência. A prova de
  // existência vem do servidor — funciona com `localStorage` vazio e em URL
  // aberta diretamente. Falha de leitura é fail-closed; um registro legado
  // homônimo só é usado quando o servidor responde SEM a avaliação.
  useEffect(() => {
    if (!candidataAvaliacaoNova) return;
    let ativo = true;

    void (async () => {
      const resultado = await lerAvaliacaoParaTela({
        organizationId: organizacaoAtivaId ?? "",
        evaluationId: feedbackId,
      });
      if (!ativo) return;

      if (!resultado.ok) {
        // Backend indeterminado: não há leitura segura (sem fallback local).
        setErroLeitura(resultado.erro);
        setCarregandoNova(false);
        return;
      }

      if (resultado.leitura?.origem === "POSTGRES") {
        setPainel(resultado.leitura.painel);
        setCarregandoNova(false);
        return;
      }

      // Sem avaliação soberana: segue o fluxo do acervo legado (somente leitura)
      // — inclusive quando não há registro algum (tela "não encontrada").
      setCarregandoNova(false);
    })();

    return () => {
      ativo = false;
    };
  }, [candidataAvaliacaoNova, feedbackId, organizacaoAtivaId]);

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

    const timeoutId = window.setTimeout(() => {
      setCriterioParaAlinhar(null);
    }, 0);

    return () => window.clearTimeout(timeoutId);
  }, [criterioAberto, criterioParaAlinhar]);

  if (!colaborador) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Colaborador não encontrado</h1>
      </div>
    );
  }

  if (carregandoNova) {
    return (
      <div style={{ padding: "30px" }} role="status" aria-live="polite">
        <h1>Carregando a avaliação…</h1>
      </div>
    );
  }

  // Uma avaliação NOVA existe apenas no PostgreSQL: se a leitura do painel
  // falhou, NÃO há fallback para o acervo local (fail-closed).
  if (erroLeitura) {
    return (
      <div style={{ padding: "30px" }}>
        <button
          onClick={() => navigate(`/colaborador/${colaborador.matricula}`)}
          style={{ marginBottom: "20px", padding: "10px 16px" }}
        >
          ← Voltar
        </button>
        <h1>Avaliação indisponível</h1>
        <p>{erroLeitura}</p>
      </div>
    );
  }

  const feedbackAtual = feedbackLegado;
  // Contexto do ciclo: o da avaliação NOVA vem da própria linha do banco; o do
  // legado vem do registro local.
  const anoAvaliacao = feedbackAtual?.ano ?? painel?.cycleAno;
  const cicloAvaliacao = feedbackAtual?.ciclo ?? painel?.cycleNumero;

  // Estado inicial do formulário derivado da ORIGEM (painel do banco ou registro
  // local). Derivar aqui — e não em efeito — evita estado espelhado e mantém a
  // autoridade onde ela pertence: no servidor para a avaliação nova.
  const estadoInicialDaOrigem = criarEstadoInicialDaOrigem(painel, feedbackLegado);
  const avaliacoes = avaliacoesEditadas ?? estadoInicialDaOrigem.avaliacoes;
  const feedbackFinalGerente =
    feedbackFinalGerenteEditado ?? estadoInicialDaOrigem.feedbackFinalGerente;
  const feedbackFinalCoordenador =
    feedbackFinalCoordenadorEditado ??
    estadoInicialDaOrigem.feedbackFinalCoordenador;
  const status = statusEditado ?? estadoInicialDaOrigem.status;

  if (!feedbackAtual && !painel) {
    return (
      <div style={{ padding: "30px" }}>
        <button
          onClick={() => navigate(`/colaborador/${colaborador.matricula}`)}
          style={{
            marginBottom: "20px",
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

        <h1>Feedback não encontrado</h1>
      </div>
    );
  }

  if (anoAvaliacao === undefined || cicloAvaliacao === undefined) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Avaliação sem ciclo associado</h1>
      </div>
    );
  }

  const cicloDaAvaliacao = getCiclosAvaliacao().find(
    (item) => item.ano === anoAvaliacao && item.ciclo === cicloAvaliacao
  );
  const colaboradorEfetivo = cicloDaAvaliacao
    ? getColaboradorEfetivoNoCiclo(
        colaborador,
        cicloDaAvaliacao,
        colaboradores
      )
    : colaborador;

  const escalaAvaliacao = getEscalaAvaliacao();

  const metasDoCiclo = cicloDaAvaliacao
    ? getMetasDoColaboradorNoCiclo(
        colaborador.matricula,
        cicloDaAvaliacao.id
      )
    : [];
  const metasSemAprovacaoFormal = metasDoCiclo.filter(
    (meta) => !metaEstaAprovada(meta, colaborador, colaboradores)
  );

  const avaliadoresColegiado = (
    colaboradorEfetivo.avaliadoresColegiadoMatriculas ?? []
  )
    .map((matriculaAvaliador) =>
      colaboradores.find((item) => item.matricula === matriculaAvaliador)
    )
    .filter((item) => item !== undefined);

  const authorizationContext: AuthorizationContext | undefined = usuarioAtual
    ? {
        actor: {
          matricula: usuarioAtual.matricula,
          funcao: usuarioAtual.funcao,
          status: usuarioAtual.status,
        },
      }
    : undefined;
  const evaluationResource: EvaluationResource = {
    kind: "evaluation",
    evaluatedCollaborator: colaborador,
    collaborators: colaboradores,
    cycle: cicloDaAvaliacao,
    evaluationStatus: feedbackAtual?.status ?? status,
  };
  const podeAvaliarComoGerente = authorizationContext
    ? can(authorizationContext, "evaluation.edit.manager", evaluationResource)
    : false;
  const podeAvaliarComoCoordenador = authorizationContext
    ? can(
        authorizationContext,
        "evaluation.edit.coordinator",
        evaluationResource
      )
    : false;
  const podeAvaliarComoColegiado = authorizationContext
    ? can(authorizationContext, "evaluation.edit.board", evaluationResource)
    : false;
  const podeAvaliar =
    podeAvaliarComoGerente ||
    podeAvaliarComoCoordenador ||
    podeAvaliarComoColegiado;

  if (!podeAvaliar) {
    return (
      <AccessRestrictedState
        message="Você não possui permissão para editar esta avaliação."
        actionLabel="Voltar"
        onAction={() => navigate(-1)}
      />
    );
  }

  const papeisPermitidos: string[] = [];
  if (podeAvaliarComoGerente) papeisPermitidos.push("Gerente");
  if (podeAvaliarComoCoordenador) papeisPermitidos.push("Coordenador direto");
  if (podeAvaliarComoColegiado) papeisPermitidos.push("Colegiado");

  function podeEditarPapel(papel: PapelAvaliador) {
    if (papel === "gerente") return podeAvaliarComoGerente;
    if (papel === "coordenador") return podeAvaliarComoCoordenador;
    return podeAvaliarComoColegiado;
  }

  function atualizarNota(
    criterioId: string,
    subcriterio: string,
    papel: PapelAvaliador,
    nota: number
  ) {
    setAvaliacoes((estadoAtual) => {
      const base = estadoAtual ?? criarEstadoInicial();
      return {
        ...base,
        [criterioId]: {
          ...base[criterioId],
          notas: {
            ...base[criterioId].notas,
            [subcriterio]: {
              ...base[criterioId].notas[subcriterio],
              [papel]: nota,
            },
          },
        },
      } satisfies Avaliacoes;
    });
  }

  function atualizarVotoColegiado(
    criterioId: string,
    subcriterio: string,
    avaliadorMatricula: number,
    nota: number
  ) {
    if (usuarioAtual?.matricula !== avaliadorMatricula) return;

    setVotosColegiado((estadoAtual) => {
      const votosAtualizados: Record<
        string,
        Record<string, Record<number, number>>
      > = {
        ...estadoAtual,
        [criterioId]: {
          ...(estadoAtual[criterioId] ?? {}),
          [subcriterio]: {
            ...(estadoAtual[criterioId]?.[subcriterio] ?? {}),
            [avaliadorMatricula]: nota,
          },
        },
      };

      const notas = Object.values<number>(
        votosAtualizados[criterioId][subcriterio]
      ).filter((valor) => valor > 0);

      const mediaColegiado =
        notas.length === 0
          ? 0
          : notas.reduce((total, valor) => total + valor, 0) / notas.length;

      setAvaliacoes((avaliacoesAtuais) => {
        const base = avaliacoesAtuais ?? criarEstadoInicial();
        return {
          ...base,
          [criterioId]: {
            ...base[criterioId],
            notas: {
              ...base[criterioId].notas,
              [subcriterio]: {
                ...base[criterioId].notas[subcriterio],
                colegiado: mediaColegiado,
              },
            },
          },
        } satisfies Avaliacoes;
      });

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
            podeAvaliarComoColegiado &&
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
    setAvaliacoes((estadoAtual) => {
      const base = estadoAtual ?? criarEstadoInicial();
      return {
        ...base,
        [criterioId]: {
          ...base[criterioId],
          [campo]: valor,
        },
      } satisfies Avaliacoes;
    });
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

  function preencherTudoParaTeste() {
    const notaTeste = 4;

    setAvaliacoes(() =>
      criterios.reduce((acc, criterio) => {
        acc[criterio.id] = {
          notas: criterio.subcriterios.reduce((subAcc, subcriterio) => {
            subAcc[subcriterio] = {
              gerente: notaTeste,
              coordenador: notaTeste,
              colegiado:
                avaliadoresColegiado.length > 0 ? notaTeste : 0,
            };
            return subAcc;
          }, {} as Record<string, NotasPorAvaliador>),
          observacaoGerente:
            avaliacoes[criterio.id]?.observacaoGerente ?? "",
          observacaoCoordenador:
            avaliacoes[criterio.id]?.observacaoCoordenador ?? "",
        };
        return acc;
      }, {} as Avaliacoes)
    );

    setVotosColegiado(() =>
      criterios.reduce((acc, criterio) => {
        acc[criterio.id] = {};

        criterio.subcriterios.forEach((subcriterio) => {
          acc[criterio.id][subcriterio] = {};

          avaliadoresColegiado.forEach((avaliador) => {
            acc[criterio.id][subcriterio][avaliador.matricula] =
              notaTeste;
          });
        });

        return acc;
      }, {} as Record<
        string,
        Record<string, Record<number, number>>
      >)
    );

    setFeedbackFinalGerente(
      "Feedback final de teste preenchido automaticamente."
    );
    setFeedbackFinalCoordenador(
      "Feedback final de teste preenchido automaticamente."
    );
    setStatus("RASCUNHO");
  }

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

  /**
   * F5-06 (Issue #103) — CUTOVER da edição.
   *
   * A edição de avaliação NOVA passa exclusivamente pelo PostgreSQL: a tela NÃO
   * grava mais no `localStorage` (o acervo legado é somente leitura) e NÃO
   * calcula a nota oficial — o agregado é materializado pelo servidor.
   *
   * Notas e comentários são gravados na PRÓPRIA ocorrência, resolvida
   * server-side pelo painel; o status é ajustado pelas operações de domínio
   * (`concluir`), porque completude e imutabilidade são regras do servidor.
   *
   * Qualquer falha é FAIL-CLOSED: a tela reporta o erro público e nada é
   * gravado localmente como compensação (D12/§11.3).
   */
  async function handleSalvarAlteracoes() {
    if (status !== "RASCUNHO" && !progressoAvaliacao.completo) {
      alert(
        `Não é possível salvar com este status.\n\n${progressoAvaliacao.pendencias.join(
          "\n"
        )}`
      );
      return;
    }

    setErroAcao("");

    // Avaliação NOVA: caminho soberano (o painel é obrigatório).
    if (candidataAvaliacaoNova) {
      if (!painel) {
        setErroAcao("Painel da avaliação indisponível para gravação.");
        return;
      }

      setSalvando(true);
      try {
        const colunaDoAtor: keyof NotasPorAvaliador =
          painel.participanteRoleType.startsWith("GESTAO_CADEIA")
            ? "gerente"
            : painel.participanteRoleType.startsWith("GESTAO_DIRETA")
              ? "coordenador"
              : "colegiado";

        // Notas PREENCHIDAS da própria coluna (o banco valida a ocorrência e o
        // subcritério contra a configuração congelada).
        const notas: NotaDoPainelPorNome[] = [];
        for (const criterio of criterios) {
          for (const subcriterio of criterio.subcriterios) {
            const nota = avaliacoes[criterio.id].notas[subcriterio][colunaDoAtor];
            if (nota > 0) notas.push({ subcriterio, nota });
          }
        }

        const gravouNotas = await gravarNotasSoberanas({
          organizationId: organizacaoAtivaId ?? "",
          evaluationId: painel.evaluationId,
          painel,
          notas,
        });
        if (!gravouNotas.ok) {
          setErroAcao(gravouNotas.erro ?? "Não foi possível gravar as notas.");
          return;
        }

        const observacoes: ObservacaoDoPainel[] = [];
        criterios.forEach((criterio, indice) => {
          const code = painel.criterios[indice]?.code;
          if (!code) return;
          const texto =
            colunaDoAtor === "gerente"
              ? avaliacoes[criterio.id].observacaoGerente
              : colunaDoAtor === "coordenador"
                ? avaliacoes[criterio.id].observacaoCoordenador
                : "";
          if (texto.trim()) observacoes.push({ criterioCode: code, texto });
        });

        const gravouObservacoes = await gravarObservacoesSoberanas({
          organizationId: organizacaoAtivaId ?? "",
          evaluationId: painel.evaluationId,
          painel,
          observacoes,
        });
        if (!gravouObservacoes.ok) {
          setErroAcao(
            gravouObservacoes.erro ?? "Não foi possível gravar as observações."
          );
          return;
        }

        const textoFinal =
          colunaDoAtor === "gerente"
            ? feedbackFinalGerente
            : colunaDoAtor === "coordenador"
              ? feedbackFinalCoordenador
              : "";

        const gravouFinal = await gravarComentarioFinalSoberano({
          organizationId: organizacaoAtivaId ?? "",
          evaluationId: painel.evaluationId,
          painel,
          texto: textoFinal,
        });
        if (!gravouFinal.ok) {
          setErroAcao(
            gravouFinal.erro ?? "Não foi possível gravar o feedback final."
          );
          return;
        }

        // Conclusão é operação de domínio do servidor (D18): o frontend só a
        // solicita, e o banco decide se há completude.
        if (status === "CONCLUIDA") {
          const conclusao = await concluirAvaliacaoSoberana({
            organizationId: organizacaoAtivaId ?? "",
            evaluationId: painel.evaluationId,
          });
          if (!conclusao.ok) {
            setErroAcao(
              conclusao.erro ?? "Não foi possível concluir a avaliação."
            );
            return;
          }
        }

        alert("Avaliação atualizada com sucesso.");
        navigate(
          `/colaborador/${colaborador!.matricula}/feedback/${painel.evaluationId}`
        );
      } catch (error) {
        setErroAcao(
          error instanceof Error
            ? error.message
            : "Não foi possível salvar a avaliação."
        );
      } finally {
        setSalvando(false);
      }
      return;
    }

    // Acervo LEGADO: permanece somente leitura — não existe mais gravação local.
    setErroAcao(
      "Avaliações criadas antes do cutover são somente leitura. Use o caminho de avaliações no PostgreSQL para editar."
    );
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
          <h1>Editar Avaliação</h1>
          <p>Revise os critérios, acompanhe as médias e atualize a avaliação do ciclo.</p>
        </div>
      </section>

      <section className="new-evaluation-person">
        <CollaboratorIdentity colaborador={colaboradorEfetivo} variant="standard" />

        <div className="new-evaluation-cycle">
          <span>Ciclo da avaliação</span>
          <strong>{anoAvaliacao} • Ciclo {cicloAvaliacao}</strong>
          <small>
            {cicloDaAvaliacao ? formatarPeriodoCiclo(cicloDaAvaliacao.dataInicio, cicloDaAvaliacao.dataFim) : "Período não disponível"}
          </small>
        </div>
      </section>

      <RoleExpectationsCard
        expectativa={feedbackAtual?.expectativaCargoSnapshot}
      />

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
            {papeisPermitidos.length > 0 ? (
              papeisPermitidos.map((papel) => (
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
                  {criterio.subcriterios.map((subcriterio, subcriterioIndex) => (
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
                        <div className="new-evaluation-subcriterion__heading">
                          <span className="new-evaluation-subcriterion__index">
                            {subcriterioIndex + 1}
                          </span>
                          <strong>{subcriterio}</strong>
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
                        disabled={!podeAvaliarComoGerente}
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
                        disabled={!podeAvaliarComoCoordenador}
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
                    disabled={!podeAvaliarComoGerente}
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
                    disabled={!podeAvaliarComoCoordenador}
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
          gap: "12px",
          flexWrap: "wrap",
        }}>
        <button
          type="button"
          onClick={preencherTudoParaTeste}
          style={{
            padding: "12px 20px",
            borderRadius: "10px",
            border: "1px solid #660099",
            cursor: "pointer",
            backgroundColor: "#fff",
            color: "#660099",
            fontWeight: "bold",
            fontSize: "14px",
          }}
        >
          Preencher notas para teste
        </button>
<button
          onClick={() => {
            void handleSalvarAlteracoes();
          }}
          disabled={!podeAvaliar || salvando}
          style={{
            padding: "12px 24px",
            borderRadius: "10px",
            border: "none",
            cursor: salvando ? "progress" : "pointer",
            backgroundColor: salvando ? "#B98FD0" : "#660099",
            color: "#fff",
            fontWeight: "bold",
            fontSize: "15px",
          }}
        >
          {salvando ? "Salvando no servidor…" : "Salvar Avaliação"}
        </button>
      </div>

      {erroAcao && (
        <section
          className="new-evaluation-goals-warning"
          role="alert"
          style={{ marginTop: "16px" }}
        >
          <div className="new-evaluation-goals-warning__icon" aria-hidden="true">
            !
          </div>
          <div>
            <strong>Alterações não salvas</strong>
            <p>{erroAcao}</p>
          </div>
        </section>
      )}
    </main>
  );
}

export default EditarFeedbackPage;








