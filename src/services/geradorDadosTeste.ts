import { criteriosAvaliacao } from "../data/modeloAvaliacao";
import { getColaboradores } from "./colaboradorStorage";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import type { Meta, TipoMeta } from "../types/Meta";
import type {
  Observacao,
  TipoObservacao,
} from "../types/Observacao";
import { getCiclosAvaliacao } from "./cicloAvaliacaoStorage";

const FEEDBACKS_KEY = "feedback-control-feedbacks";
const METAS_KEY = "feedback-control-metas";
const OBSERVACOES_KEY = "feedback-control-observacoes";

const frasesCompetencia = {
  alta: [
    "Apresenta desempenho consistente e entrega com qualidade acima do esperado.",
    "Demonstra domínio do tema, boa autonomia e contribui positivamente para o time.",
    "Mantém um nível elevado de execução e atua como referência em situações relevantes.",
  ],
  media: [
    "Apresenta desempenho consistente, com oportunidades pontuais de evolução.",
    "Atende às expectativas da função e demonstra boa capacidade de desenvolvimento.",
    "Mantém entregas adequadas e pode ampliar o impacto com maior consistência.",
  ],
  baixa: [
    "Apresenta pontos importantes de desenvolvimento e requer acompanhamento mais próximo.",
    "Precisa ganhar consistência nas entregas e reforçar práticas essenciais da função.",
    "Há oportunidades claras de evolução que devem ser acompanhadas ao longo do próximo ciclo.",
  ],
};

const feedbacksFinais = {
  alta: [
    "O ciclo demonstra uma evolução muito positiva, com entregas consistentes e impacto relevante para a equipe. O próximo passo é ampliar ainda mais a autonomia e compartilhar boas práticas com os colegas.",
    "O desempenho no período ficou acima do esperado. Recomenda-se manter o nível de execução, ampliar a contribuição transversal e buscar desafios de maior complexidade.",
    "A avaliação mostra excelente consistência ao longo do ciclo. O foco para o próximo período deve ser consolidar o protagonismo e ampliar a influência positiva sobre o time.",
  ],
  media: [
    "O desempenho no ciclo atende às expectativas da função. Para o próximo período, o foco deve estar em aumentar a consistência, priorização e autonomia nas entregas.",
    "O período apresentou resultados adequados e evolução em pontos importantes. Há espaço para ampliar o impacto por meio de maior proatividade e aprofundamento técnico.",
    "A avaliação mostra uma trajetória estável. Recomenda-se transformar os pontos de desenvolvimento identificados em ações objetivas para o próximo ciclo.",
  ],
  baixa: [
    "O ciclo apresenta pontos relevantes de desenvolvimento. É importante estabelecer um plano de evolução com objetivos claros, acompanhamento frequente e foco nas competências com menor resultado.",
    "Os resultados indicam necessidade de maior consistência nas entregas e comportamentos esperados. O próximo ciclo deve priorizar ações específicas de desenvolvimento e acompanhamento.",
    "A avaliação evidencia oportunidades importantes de evolução. Recomenda-se alinhar expectativas, definir ações concretas e acompanhar os avanços ao longo do próximo período.",
  ],
};

const observacoesPorTipo: Record<TipoObservacao, string[]> = {
  POSITIVA: [
    "Demonstrou boa colaboração com a equipe em uma entrega de alta prioridade.",
    "Teve iniciativa para antecipar um risco e propor uma solução antes do prazo.",
    "Apresentou evolução perceptível na qualidade das entregas durante o ciclo.",
    "Contribuiu de forma relevante para o resultado de uma atividade transversal.",
    "Recebeu reconhecimento pela disponibilidade e apoio aos colegas.",
  ],
  NEUTRA: [
    "Foi alinhada uma oportunidade de melhorar a priorização das atividades da semana.",
    "Foi discutida a necessidade de manter maior previsibilidade na comunicação das entregas.",
    "Foi registrado um ponto de acompanhamento sobre organização e planejamento.",
    "Houve alinhamento sobre expectativas e próximos passos para uma atividade em andamento.",
  ],
  NEGATIVA: [
    "Uma entrega precisou de retrabalho e foi combinado um plano para evitar recorrência.",
    "Houve atraso em uma atividade relevante e foram alinhadas ações de prevenção.",
    "Foi identificado um ponto de atenção na comunicação com as áreas envolvidas.",
  ],
};

const metasNegocio = [
  {
    descricao: "Melhorar a eficiência de uma frente operacional prioritária",
    kpi: "Redução de retrabalho",
    alvo: "Reduzir em 15%",
  },
  {
    descricao: "Aumentar a qualidade das entregas do time no ciclo",
    kpi: "Índice de qualidade",
    alvo: "Atingir 95%",
  },
  {
    descricao: "Contribuir para uma iniciativa estratégica da área",
    kpi: "Marcos do projeto",
    alvo: "100% dos marcos no prazo",
  },
];

const metasIndividuais = [
  {
    descricao: "Desenvolver uma competência técnica relevante para a função",
    kpi: "Plano de desenvolvimento",
    alvo: "Concluir 100%",
  },
  {
    descricao: "Aumentar a autonomia na condução das atividades",
    kpi: "Entregas sem retrabalho",
    alvo: "Atingir 90%",
  },
  {
    descricao: "Ampliar a colaboração e compartilhamento de conhecimento",
    kpi: "Ações de compartilhamento",
    alvo: "Realizar 3 ações",
  },
];

function lerArray<T>(chave: string): T[] {
  const valor = localStorage.getItem(chave);
  if (!valor) return [];

  try {
    return JSON.parse(valor) as T[];
  } catch {
    return [];
  }
}

function sortear<T>(itens: readonly T[]): T {
  return itens[Math.floor(Math.random() * itens.length)];
}

function aleatorio(min: number, max: number) {
  return min + Math.random() * (max - min);
}

function inteiro(min: number, max: number) {
  return Math.floor(aleatorio(min, max + 1));
}

function limitar(valor: number, min: number, max: number) {
  return Math.min(max, Math.max(min, valor));
}

function notaAoRedor(base: number, variacao = 1.05) {
  return limitar(Math.round(base + aleatorio(-variacao, variacao)), 1, 5);
}

function media(notas: number[]) {
  const validas = notas.filter((nota) => nota > 0);
  if (validas.length === 0) return 0;
  return validas.reduce((total, nota) => total + nota, 0) / validas.length;
}

function faixa(valor: number): "alta" | "media" | "baixa" {
  if (valor >= 4) return "alta";
  if (valor >= 3) return "media";
  return "baixa";
}

function dataAleatoriaCiclo(ciclo: CicloAvaliacao) {
  const inicio = ciclo.dataInicio
    ? new Date(`${ciclo.dataInicio}T12:00:00`).getTime()
    : Date.now() - 30 * 86400000;
  const fim = ciclo.dataFim
    ? new Date(`${ciclo.dataFim}T12:00:00`).getTime()
    : Date.now();

  const minimo = Math.min(inicio, fim);
  const maximo = Math.max(inicio, fim);
  return new Date(aleatorio(minimo, maximo)).toISOString();
}

function gerarFeedback(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  todos: Colaborador[]
): Feedback {
  const agora = dataAleatoriaCiclo(ciclo);
  const basePessoa = aleatorio(2.15, 4.75);

  const coordenador = colaborador.gestorDiretoMatricula
    ? todos.find(
        (item) => item.matricula === colaborador.gestorDiretoMatricula
      )
    : undefined;

  const colegiado = (colaborador.avaliadoresColegiadoMatriculas ?? [])
    .map((matricula) =>
      todos.find((item) => item.matricula === matricula)
    )
    .filter((item): item is Colaborador => Boolean(item));

  const criteriosDetalhados = criteriosAvaliacao.map((criterio) => {
    const baseCriterio = limitar(basePessoa + aleatorio(-0.45, 0.45), 1, 5);

    const subcriterios = criterio.subcriterios.map((nome) => {
      const notaGerente = notaAoRedor(baseCriterio);
      const notaCoordenador = coordenador
        ? notaAoRedor(baseCriterio + aleatorio(-0.2, 0.2))
        : 0;

      const votosColegiado = colegiado.map((avaliador) => ({
        avaliadorMatricula: avaliador.matricula,
        avaliadorNome: avaliador.nome,
        nota: notaAoRedor(baseCriterio + aleatorio(-0.35, 0.35)),
        dataAtualizacao: agora,
      }));

      const notaColegiado =
        votosColegiado.length > 0
          ? media(votosColegiado.map((voto) => voto.nota))
          : 0;

      const notaFinal = media([
        notaGerente,
        notaCoordenador,
        notaColegiado,
      ]);

      return {
        nome,
        notaGerente,
        notaCoordenador,
        notaColegiado,
        votosColegiado,
        notaFinal,
      };
    });

    const nota = media(subcriterios.map((item) => item.notaFinal));
    const grupo = faixa(nota);

    return {
      criterioId: criterio.id,
      criterioNome: criterio.nome,
      nota,
      subcriterios,
      observacaoGerente: sortear(frasesCompetencia[grupo]),
      observacaoCoordenador: coordenador
        ? sortear(frasesCompetencia[grupo])
        : "",
    };
  });

  const notaMedia = media(
    criteriosDetalhados.map((criterio) => criterio.nota)
  );
  const grupoFinal = faixa(notaMedia);

  const status: Feedback["status"] =
    ciclo.status === "ENCERRADO"
      ? "CONCLUIDA"
      : Math.random() < 0.65
      ? "CONCLUIDA"
      : Math.random() < 0.7
      ? "PRONTA_PARA_FEEDBACK"
      : "RASCUNHO";

  return {
    id: crypto.randomUUID(),
    colaboradorId: colaborador.matricula,
    colaboradorNome: colaborador.nome,
    status,
    data: agora,
    dataCriacao: agora,
    dataUltimaAtualizacao: agora,
    dataConclusao: status === "CONCLUIDA" ? agora : undefined,
    ano: ciclo.ano,
    ciclo: ciclo.ciclo,
    notaMedia,
    competencias: criteriosDetalhados.map((criterio) => ({
      competenciaId: criterio.criterioId,
      competenciaNome: criterio.criterioNome,
      nota: criterio.nota,
      comentario: [
        criterio.observacaoGerente
          ? `Observação do Gerente: ${criterio.observacaoGerente}`
          : "",
        criterio.observacaoCoordenador
          ? `Observação do Coordenador: ${criterio.observacaoCoordenador}`
          : "",
      ]
        .filter(Boolean)
        .join("\n\n"),
    })),
    criteriosDetalhados,
    feedbackFinalGerente: sortear(feedbacksFinais[grupoFinal]),
    feedbackFinalCoordenador: coordenador
      ? sortear(feedbacksFinais[grupoFinal])
      : "",
  };
}

function gerarMeta(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  tipo: TipoMeta,
  indice: number
): Meta {
  const modelo =
    tipo === "NEGOCIO_PROJETO"
      ? metasNegocio[indice % metasNegocio.length]
      : metasIndividuais[indice % metasIndividuais.length];

  const agora = dataAleatoriaCiclo(ciclo);
  const progresso = inteiro(20, 100);
  const encerrado = ciclo.status === "ENCERRADO";
  const atingida = encerrado ? Math.random() < 0.72 : undefined;

  const status: Meta["status"] = encerrado
    ? atingida
      ? "ATINGIDA"
      : "NAO_ATINGIDA"
    : "EM_ANDAMENTO";

  const resultadoAtual =
    progresso >= 80
      ? "Execução em estágio avançado, com os principais resultados já observados."
      : progresso >= 50
      ? "A meta apresenta evolução consistente e segue em acompanhamento."
      : "A execução está em andamento e ainda exige evolução relevante no ciclo.";

  const resultadoFinal = encerrado
    ? atingida
      ? "Meta concluída com o resultado esperado para o ciclo."
      : "Meta encerrada abaixo do resultado esperado, com aprendizados registrados para o próximo ciclo."
    : undefined;

  return {
    id: crypto.randomUUID(),
    colaboradorMatricula: colaborador.matricula,
    colaboradorNome: colaborador.nome,
    cicloId: ciclo.id,
    ano: ciclo.ano,
    ciclo: ciclo.ciclo,
    tipo,
    descricao: modelo.descricao,
    kpi: modelo.kpi,
    valorAlvo: modelo.alvo,
    status,
    resultadoAtual,
    progressoPercentual: encerrado ? 100 : progresso,
    dataUltimoAcompanhamento: agora,
    resultadoFinal,
    atingida,
    dataFechamento: encerrado ? agora : undefined,
    dataCriacao: agora,
    dataUltimaAtualizacao: agora,
    excluida: false,
    historico: [
      {
        id: crypto.randomUUID(),
        acao: "CRIACAO",
        data: agora,
        autorMatricula: colaborador.matricula,
        autorNome: colaborador.nome,
      },
      {
        id: crypto.randomUUID(),
        acao: "ATUALIZACAO_PROGRESSO",
        data: agora,
        autorMatricula: colaborador.matricula,
        autorNome: colaborador.nome,
      },
      ...(encerrado
        ? [
            {
              id: crypto.randomUUID(),
              acao: "FINALIZACAO" as const,
              data: agora,
              autorMatricula: colaborador.matricula,
              autorNome: colaborador.nome,
            },
          ]
        : []),
    ],
  };
}

function sortearTipoObservacao(base: number): TipoObservacao {
  const chance = Math.random();

  if (base >= 4) {
    if (chance < 0.65) return "POSITIVA";
    if (chance < 0.92) return "NEUTRA";
    return "NEGATIVA";
  }

  if (base < 3) {
    if (chance < 0.25) return "POSITIVA";
    if (chance < 0.62) return "NEUTRA";
    return "NEGATIVA";
  }

  if (chance < 0.48) return "POSITIVA";
  if (chance < 0.82) return "NEUTRA";
  return "NEGATIVA";
}

function gerarObservacoes(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  gerente: Colaborador,
  notaBase: number
): Observacao[] {
  return Array.from({ length: inteiro(2, 4) }, () => {
    const tipo = sortearTipoObservacao(notaBase);
    const agora = dataAleatoriaCiclo(ciclo);

    return {
      id: crypto.randomUUID(),
      colaboradorMatricula: colaborador.matricula,
      tipo,
      texto: sortear(observacoesPorTipo[tipo]),
      comunicado: Math.random() < 0.68,
      ano: ciclo.ano,
      ciclo: ciclo.ciclo,
      autorMatricula: gerente.matricula,
      autorNome: gerente.nome,
      dataCriacao: agora,
      dataUltimaAtualizacao: agora,
      excluida: false,
      historico: [
        {
          id: crypto.randomUUID(),
          acao: "CRIACAO",
          data: agora,
          autorMatricula: gerente.matricula,
          autorNome: gerente.nome,
        },
      ],
    };
  });
}

export interface ResultadoGeracaoDadosTeste {
  avaliacoes: number;
  metas: number;
  observacoes: number;
  colaboradores: number;
}

export function gerarDadosTesteDoCiclo(
  ciclo: CicloAvaliacao,
  usuarioAtual: Colaborador
): ResultadoGeracaoDadosTeste {
  const cicloPersistido = getCiclosAvaliacao().find(
    (item) => item.id === ciclo.id
  );
  if (cicloPersistido?.status === "CANCELADO") {
    throw new Error("Dados de ciclo cancelado não podem ser alterados.");
  }

  if (usuarioAtual.funcao !== "GERENTE") {
    throw new Error(
      "A geração de dados de teste está disponível apenas para o perfil Gerente."
    );
  }

  const todos = getColaboradores();
  const analistas = todos.filter(
    (colaborador) =>
      colaborador.status === "ATIVO" &&
      colaborador.funcao === "ANALISTA"
  );

  const feedbacksExistentes = lerArray<Feedback>(FEEDBACKS_KEY).filter(
    (feedback) =>
      !(
        feedback.ano === ciclo.ano &&
        feedback.ciclo === ciclo.ciclo
      )
  );

  const metasExistentes = lerArray<Meta>(METAS_KEY).filter(
    (meta) => meta.cicloId !== ciclo.id
  );

  const observacoesExistentes = lerArray<Observacao>(
    OBSERVACOES_KEY
  ).filter(
    (observacao) =>
      !(
        observacao.ano === ciclo.ano &&
        observacao.ciclo === ciclo.ciclo
      )
  );

  const feedbacksNovos = analistas.map((colaborador) =>
    gerarFeedback(colaborador, ciclo, todos)
  );

  const metasNovas = analistas.flatMap((colaborador) => [
    ...Array.from(
      { length: ciclo.quantidadeMetasNegocio ?? 0 },
      (_, indice) =>
        gerarMeta(colaborador, ciclo, "NEGOCIO_PROJETO", indice)
    ),
    ...Array.from(
      { length: ciclo.quantidadeMetasIndividuais ?? 0 },
      (_, indice) => gerarMeta(colaborador, ciclo, "INDIVIDUAL", indice)
    ),
  ]);

  const feedbackPorMatricula = new Map(
    feedbacksNovos.map((feedback) => [
      feedback.colaboradorId,
      feedback.notaMedia,
    ])
  );

  const observacoesNovas = analistas.flatMap((colaborador) =>
    gerarObservacoes(
      colaborador,
      ciclo,
      usuarioAtual,
      feedbackPorMatricula.get(colaborador.matricula) ?? 3
    )
  );

  localStorage.setItem(
    FEEDBACKS_KEY,
    JSON.stringify([...feedbacksExistentes, ...feedbacksNovos])
  );
  localStorage.setItem(
    METAS_KEY,
    JSON.stringify([...metasExistentes, ...metasNovas])
  );
  localStorage.setItem(
    OBSERVACOES_KEY,
    JSON.stringify([...observacoesExistentes, ...observacoesNovas])
  );

  return {
    avaliacoes: feedbacksNovos.length,
    metas: metasNovas.length,
    observacoes: observacoesNovas.length,
    colaboradores: analistas.length,
  };
}
