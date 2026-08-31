import type { Colaborador } from "../types/Colaborador";
import type {
  CargoExpectativa,
  ExpectativaCargo,
  ExpectativasCargo,
} from "../types/ExpectativaCargo";

const STORAGE_KEY = "feedback-control-expectativas-cargo";

export const expectativasCargoPadrao: ExpectativasCargo = [
  {
    cargo: "ESTAGIARIO",
    nome: "Estagiário",
    autonomia:
      "Inicial. Atua com acompanhamento próximo, orientação frequente e validação das atividades realizadas.",
    tarefas:
      "Executa atividades de apoio e baixa complexidade, contribuindo com rotinas da equipe e desenvolvendo conhecimentos técnicos e práticos.",
    responsabilidades:
      "Responsável por executar as atividades orientadas com atenção e organização, cumprir prazos acordados, buscar esclarecimentos quando necessário e demonstrar evolução no aprendizado.",
    foco:
      "Aprendizado, desenvolvimento de competências, compreensão dos processos e da cultura da empresa, ganho progressivo de autonomia e preparação para assumir responsabilidades de maior complexidade.",
  },
  {
    cargo: "ANALISTA_JUNIOR",
    nome: "Analista Júnior",
    autonomia:
      "Baixa. Atua com supervisão constante e orientação direta.",
    tarefas:
      "Executa atividades operacionais rotineiras e de baixa complexidade, com foco em volume e agilidade.",
    responsabilidades:
      "Responsável pela execução correta das tarefas atribuídas, seguindo processos estabelecidos.",
    foco:
      "Desenvolvimento técnico, aprendizado contínuo e adaptação à cultura e aos processos da empresa.",
  },
  {
    cargo: "ANALISTA_PLENO",
    nome: "Analista Pleno",
    autonomia:
      "Média. Atua com supervisão pontual e maior independência na execução das atividades.",
    tarefas:
      "Realiza atividades operacionais e analíticas de média complexidade, com foco em eficiência e qualidade.",
    responsabilidades:
      "Garante a entrega de resultados com autonomia, contribuindo para a melhoria dos processos e apoiando colegas menos experientes.",
    foco:
      "Consolidação do conhecimento técnico, entrega consistente de resultados e desenvolvimento de visão crítica.",
  },
  {
    cargo: "ANALISTA_SENIOR",
    nome: "Analista Sênior",
    autonomia:
      "Média, visão estratégica e domínio técnico.",
    tarefas:
      "Conduz atividades complexas, participa de projetos estratégicos e interage com diferentes áreas da empresa.",
    responsabilidades:
      "Liderança técnica, apoio à coordenação e proposição de melhorias nos processos.",
    foco:
      "Geração de impacto, inovação, melhoria contínua e influência positiva no ambiente e na equipe.",
  },
  {
    cargo: "CONSULTOR",
    nome: "Consultor",
    autonomia:
      "Alta. Atua com relativa independência e visão estratégica.",
    tarefas:
      "Desenvolve soluções complexas, conduz diagnósticos, propõe melhorias e atua como referência técnica em sua área.",
    responsabilidades:
      "Responsável por orientar e aplicar decisões definidas pela gerência, resolver problemas, apoiar diferentes áreas e liderar iniciativas de alto impacto.",
    foco:
      "Inovação, excelência técnica, geração de valor para o negócio e disseminação de boas práticas.",
  },
  {
    cargo: "COORDENADOR",
    nome: "Coordenador",
    autonomia:
      "Alta. Atua com autonomia relativa na gestão de pessoas e processos.",
    tarefas:
      "Planeja, organiza e acompanha atividades da equipe. Garante alinhamento com metas da área e da empresa.",
    responsabilidades:
      "Gestão de equipe, desenvolvimento de talentos, tomada de decisão, resolve problemas, comunicação com outras áreas e liderança de projetos.",
    foco:
      "Resultados estratégicos, desenvolvimento da equipe, eficiência operacional e cultura organizacional.",
  },
];

const ordemCargos: CargoExpectativa[] = [
  "ESTAGIARIO",
  "ANALISTA_JUNIOR",
  "ANALISTA_PLENO",
  "ANALISTA_SENIOR",
  "CONSULTOR",
  "COORDENADOR",
];

function clonarPadrao(): ExpectativasCargo {
  return expectativasCargoPadrao.map((item) => ({ ...item }));
}

function normalizarExpectativas(
  expectativas: ExpectativasCargo
): ExpectativasCargo {
  return ordemCargos.map((cargo) => {
    const padrao = expectativasCargoPadrao.find(
      (item) => item.cargo === cargo
    )!;
    const salvo = expectativas.find((item) => item.cargo === cargo);

    return {
      ...padrao,
      ...salvo,
      cargo,
      nome: salvo?.nome?.trim() || padrao.nome,
      autonomia: salvo?.autonomia ?? padrao.autonomia,
      tarefas: salvo?.tarefas ?? padrao.tarefas,
      responsabilidades:
        salvo?.responsabilidades ?? padrao.responsabilidades,
      foco: salvo?.foco ?? padrao.foco,
    };
  });
}

export function getExpectativasCargo(): ExpectativasCargo {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) return clonarPadrao();

  try {
    const parsed = JSON.parse(data) as ExpectativasCargo;
    if (!Array.isArray(parsed)) return clonarPadrao();
    return normalizarExpectativas(parsed);
  } catch {
    return clonarPadrao();
  }
}

export function salvarExpectativasCargo(
  expectativas: ExpectativasCargo
): void {
  const normalizadas = normalizarExpectativas(expectativas);

  for (const item of normalizadas) {
    if (
      !item.autonomia.trim() ||
      !item.tarefas.trim() ||
      !item.responsabilidades.trim() ||
      !item.foco.trim()
    ) {
      throw new Error(
        `Preencha todos os campos de expectativas para ${item.nome}.`
      );
    }
  }

  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify(normalizadas)
  );
}

export function restaurarExpectativasCargo(): ExpectativasCargo {
  const padrao = clonarPadrao();
  localStorage.setItem(STORAGE_KEY, JSON.stringify(padrao));
  return padrao;
}

export function getExpectativaCargo(
  cargo: CargoExpectativa
): ExpectativaCargo {
  return (
    getExpectativasCargo().find((item) => item.cargo === cargo) ??
    expectativasCargoPadrao.find((item) => item.cargo === cargo)!
  );
}


/**
 * Converte a função/senioridade estruturada do colaborador para a
 * categoria usada pela configuração de expectativas.
 */
export function resolverCargoExpectativa(
  colaborador: Colaborador
): CargoExpectativa | undefined {
  if (colaborador.funcao === "ESTAGIARIO") {
    return "ESTAGIARIO";
  }

  if (colaborador.funcao === "COORDENADOR") {
    return "COORDENADOR";
  }

  if (colaborador.funcao === "CONSULTOR") {
    return "CONSULTOR";
  }

  if (colaborador.funcao === "ANALISTA") {
    if (colaborador.senioridade === "JUNIOR") {
      return "ANALISTA_JUNIOR";
    }

    if (colaborador.senioridade === "PLENO") {
      return "ANALISTA_PLENO";
    }

    if (colaborador.senioridade === "SENIOR") {
      return "ANALISTA_SENIOR";
    }
  }

  return undefined;
}

export function getExpectativaDoColaborador(
  colaborador: Colaborador
): ExpectativaCargo | undefined {
  const cargo = resolverCargoExpectativa(colaborador);
  return cargo ? getExpectativaCargo(cargo) : undefined;
}
