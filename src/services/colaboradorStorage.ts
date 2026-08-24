import type {
  Colaborador,
  FuncaoColaborador,
} from "../types/Colaborador";
import { colaboradores as colaboradoresIniciais } from "../data/colaboradores";

const STORAGE_KEY = "feedback-control-colaboradores";

const gestoresIniciais: Colaborador[] = [
  {
    matricula: 900001,
    status: "ATIVO",
    nome: "RICARDO MENEZES BARROS",
    email: "ricardo.barros@example.com",
    cargo: "Gerente",
    area: "Gerência de Operações Digitais",
    funcao: "GERENTE",
    respondePara: "",
  },
  {
    matricula: 900002,
    status: "ATIVO",
    nome: "MARCOS ALMEIDA COSTA",
    email: "marcos.costa@example.com",
    cargo: "Coordenador",
    area: "Coordenação de Operações Digitais",
    funcao: "COORDENADOR",
    gestorDiretoMatricula: 900001,
    respondePara: "RICARDO MENEZES BARROS",
    gerente: "RICARDO MENEZES BARROS",
  },
  {
    matricula: 900003,
    status: "ATIVO",
    nome: "PAULA RIBEIRO SANTOS",
    email: "paula.santos@example.com",
    cargo: "Coordenador",
    area: "Coordenação de Criação e Conteúdo",
    funcao: "COORDENADOR",
    gestorDiretoMatricula: 900001,
    respondePara: "RICARDO MENEZES BARROS",
    gerente: "RICARDO MENEZES BARROS",
  },
  {
    matricula: 900004,
    status: "ATIVO",
    nome: "RENATO FONSECA LIMA",
    email: "renato.lima@example.com",
    cargo: "Coordenador",
    area: "Coordenação de Tecnologia e Autoração",
    funcao: "COORDENADOR",
    gestorDiretoMatricula: 900001,
    respondePara: "RICARDO MENEZES BARROS",
    gerente: "RICARDO MENEZES BARROS",
  },
];

const gestorMatriculaPorNome: Record<string, number> = {
  "RICARDO MENEZES BARROS": 900001,
  "MARCOS ALMEIDA COSTA": 900002,
  "PAULA RIBEIRO SANTOS": 900003,
  "RENATO FONSECA LIMA": 900004,
};

function normalizarNome(nome?: string): string {
  return (nome ?? "").trim().toUpperCase();
}

function migrarColaborador(colaborador: Colaborador): Colaborador {
  const gestorDiretoMatricula =
    colaborador.gestorDiretoMatricula ??
    gestorMatriculaPorNome[normalizarNome(colaborador.respondePara)];

  const funcao: FuncaoColaborador =
    colaborador.funcao ?? "ANALISTA";

  return {
    ...colaborador,
    funcao,
    gestorDiretoMatricula,
  };
}

function garantirGestores(
  colaboradores: Colaborador[]
): Colaborador[] {
  const matriculasExistentes = new Set(
    colaboradores.map((colaborador) => colaborador.matricula)
  );

  const gestoresFaltantes = gestoresIniciais.filter(
    (gestor) => !matriculasExistentes.has(gestor.matricula)
  );

  return [...colaboradores, ...gestoresFaltantes];
}

export function getColaboradores(): Colaborador[] {
  const data = localStorage.getItem(STORAGE_KEY);

  const base: Colaborador[] = data
    ? (JSON.parse(data) as Colaborador[])
    : colaboradoresIniciais;

  const comGestores = garantirGestores(base);

  const migrados = comGestores.map(migrarColaborador);

  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify(migrados)
  );

  return migrados;
}

export function getColaboradorByMatricula(
  matricula: number
): Colaborador | undefined {
  return getColaboradores().find(
    (colaborador) => colaborador.matricula === matricula
  );
}

export function saveColaborador(colaborador: Colaborador): void {
  const colaboradores = getColaboradores();

  if (
    colaboradores.some(
      (item) => item.matricula === colaborador.matricula
    )
  ) {
    throw new Error("Já existe um colaborador com esta matrícula.");
  }

  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify([...colaboradores, colaborador])
  );
}

export function updateColaborador(
  updatedColaborador: Colaborador
): void {
  const colaboradores = getColaboradores();

  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify(
      colaboradores.map((colaborador) =>
        colaborador.matricula === updatedColaborador.matricula
          ? updatedColaborador
          : colaborador
      )
    )
  );
}
