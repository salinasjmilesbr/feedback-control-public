import type { Colaborador } from "../types/Colaborador";
import { funcaoUsaEstruturaAvaliacaoAnalista } from "../types/Colaborador";

type CriterioBase = {
  id: string;
  subcriterios: string[];
};

type NotaPapel = {
  gerente: number;
  coordenador: number;
  colegiado: number;
};

type AvaliacoesBase = Record<
  string,
  { notas: Record<string, NotaPapel> }
>;

type VotosColegiadoBase = Record<
  string,
  Record<string, Record<number, number>>
>;

export type ProgressoPapel = {
  necessario: boolean;
  preenchidos: number;
  total: number;
  percentual: number;
};

export type ProgressoAvaliacao = {
  gerente: ProgressoPapel;
  coordenador: ProgressoPapel;
  colegiado: ProgressoPapel;
  completo: boolean;
  pendencias: string[];
};

function percentual(preenchidos: number, total: number) {
  return total === 0 ? 100 : Math.round((preenchidos / total) * 100);
}

function temGerenteResponsavel(
  colaborador: Colaborador,
  colaboradores: Colaborador[]
) {
  const porMatricula = new Map(
    colaboradores.map((item) => [item.matricula, item])
  );

  let atual: Colaborador | undefined = colaborador;
  const visitados = new Set<number>();

  while (atual?.gestorDiretoMatricula) {
    if (visitados.has(atual.gestorDiretoMatricula)) return false;
    visitados.add(atual.gestorDiretoMatricula);

    const gestor = porMatricula.get(atual.gestorDiretoMatricula);
    if (!gestor) return false;
    if (gestor.funcao === "GERENTE") return true;
    atual = gestor;
  }

  return false;
}

export function calcularProgressoAvaliacao(
  criterios: CriterioBase[],
  avaliacoes: AvaliacoesBase,
  votosColegiado: VotosColegiadoBase,
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  feedbackFinalGerente: string,
  feedbackFinalCoordenador: string
): ProgressoAvaliacao {
  const totalSubcriterios = criterios.reduce(
    (total, criterio) => total + criterio.subcriterios.length,
    0
  );

  const gestorDireto = colaborador.gestorDiretoMatricula
    ? colaboradores.find(
        (item) => item.matricula === colaborador.gestorDiretoMatricula
      )
    : undefined;

  const gerenteNecessario = temGerenteResponsavel(
    colaborador,
    colaboradores
  );
  const usaEstruturaAnalista =
    funcaoUsaEstruturaAvaliacaoAnalista(colaborador.funcao);
  const coordenadorNecessario =
    usaEstruturaAnalista &&
    gestorDireto?.funcao === "COORDENADOR";
  const avaliadoresColegiado = usaEstruturaAnalista
    ? colaborador.avaliadoresColegiadoMatriculas ?? []
    : [];
  const colegiadoNecessario =
    usaEstruturaAnalista &&
    avaliadoresColegiado.length > 0;

  let gerentePreenchidos = 0;
  let coordenadorPreenchidos = 0;
  let colegiadoPreenchidos = 0;

  criterios.forEach((criterio) => {
    criterio.subcriterios.forEach((subcriterio) => {
      const notas = avaliacoes[criterio.id]?.notas[subcriterio];

      if (notas?.gerente > 0) gerentePreenchidos += 1;
      if (notas?.coordenador > 0) coordenadorPreenchidos += 1;

      avaliadoresColegiado.forEach((matriculaAvaliador) => {
        if (
          (votosColegiado[criterio.id]?.[subcriterio]?.[
            matriculaAvaliador
          ] ?? 0) > 0
        ) {
          colegiadoPreenchidos += 1;
        }
      });
    });
  });

  const gerenteTotal = gerenteNecessario ? totalSubcriterios : 0;
  const coordenadorTotal = coordenadorNecessario ? totalSubcriterios : 0;
  const colegiadoTotal = colegiadoNecessario
    ? totalSubcriterios * avaliadoresColegiado.length
    : 0;

  const gerente: ProgressoPapel = {
    necessario: gerenteNecessario,
    preenchidos: gerentePreenchidos,
    total: gerenteTotal,
    percentual: percentual(gerentePreenchidos, gerenteTotal),
  };

  const coordenador: ProgressoPapel = {
    necessario: coordenadorNecessario,
    preenchidos: coordenadorPreenchidos,
    total: coordenadorTotal,
    percentual: percentual(coordenadorPreenchidos, coordenadorTotal),
  };

  const colegiado: ProgressoPapel = {
    necessario: colegiadoNecessario,
    preenchidos: colegiadoPreenchidos,
    total: colegiadoTotal,
    percentual: percentual(colegiadoPreenchidos, colegiadoTotal),
  };

  const pendencias: string[] = [];

  if (gerente.necessario && gerente.preenchidos < gerente.total) {
    pendencias.push(
      `Gerente: ${gerente.total - gerente.preenchidos} notas`
    );
  }

  if (
    coordenador.necessario &&
    coordenador.preenchidos < coordenador.total
  ) {
    pendencias.push(
      `Coordenador: ${coordenador.total - coordenador.preenchidos} notas`
    );
  }

  if (colegiado.necessario && colegiado.preenchidos < colegiado.total) {
    pendencias.push(
      `Colegiado: ${colegiado.total - colegiado.preenchidos} votos`
    );
  }

  if (
    gerente.necessario &&
    feedbackFinalGerente.trim().length === 0
  ) {
    pendencias.push("Feedback final do gerente");
  }

  if (
    coordenador.necessario &&
    feedbackFinalCoordenador.trim().length === 0
  ) {
    pendencias.push("Feedback final do coordenador");
  }

  return {
    gerente,
    coordenador,
    colegiado,
    completo: pendencias.length === 0,
    pendencias,
  };
}
