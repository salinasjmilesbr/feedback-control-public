import type { Colaborador } from "../types/Colaborador";
import {
  ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL,
  avaliadoresColegiadoSoberanos,
  papelDoGestorDireto,
  resolverProjecaoEstrutural,
  temEvidenciaEstrutural,
  temPapelNaCadeia,
  usaEstruturaAvaliacaoSoberana,
  type ProjecaoEstruturalSoberana,
} from "./projecaoEstruturalSoberana";

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

/**
 * O colaborador possui um GERENTE em algum ponto da cadeia de gestão?
 *
 * F5-08 P6 (correção da auditoria): a cadeia vem da PROJEÇÃO ESTRUTURAL
 * SOBERANA — nunca de `gestorDiretoMatricula`/`funcao` do cadastro local.
 * Sem evidência, a resposta é `false` (fail-closed).
 */
function temGerenteResponsavel(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
) {
  return temPapelNaCadeia(projecao, matricula, "GERENTE");
}

export function calcularProgressoAvaliacao(
  criterios: CriterioBase[],
  avaliacoes: AvaliacoesBase,
  votosColegiado: VotosColegiadoBase,
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  feedbackFinalGerente: string,
  feedbackFinalCoordenador: string,
  projecaoEstrutural?: ProjecaoEstruturalSoberana
): ProgressoAvaliacao {
  const totalSubcriterios = criterios.reduce(
    (total, criterio) => total + criterio.subcriterios.length,
    0
  );

  // F5-08 P6: papel, cadeia e colegiado vêm da projeção estrutural SOBERANA
  // (fixture local somente sob o gate explícito de DEV).
  const projecao = resolverProjecaoEstrutural(projecaoEstrutural, [
    ...colaboradores,
    colaborador,
  ]);
  const semEvidenciaEstrutural = !temEvidenciaEstrutural(
    projecao,
    colaborador.matricula
  );

  const gerenteNecessario = temGerenteResponsavel(
    projecao,
    colaborador.matricula
  );
  const usaEstruturaAnalista = usaEstruturaAvaliacaoSoberana(
    projecao,
    colaborador.matricula
  );
  const coordenadorNecessario =
    usaEstruturaAnalista &&
    papelDoGestorDireto(projecao, colaborador.matricula) === "COORDENADOR";
  const avaliadoresColegiado = avaliadoresColegiadoSoberanos(
    projecao,
    colaborador.matricula
  );
  const colegiadoNecessario = avaliadoresColegiado.length > 0;

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

  // FAIL-CLOSED (F5-08 P6): sem evidência estrutural soberana não é possível
  // provar quais papéis são exigidos. A avaliação NÃO pode ser declarada
  // completa — e nunca é completada por estrutura local.
  if (semEvidenciaEstrutural) {
    pendencias.push(ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL);
  }

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
