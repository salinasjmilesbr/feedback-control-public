import type { Colaborador } from "../types/Colaborador";
import { ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL } from "./projecaoEstruturalSoberana";
import {
  estruturaSoberanaEfetiva,
  visaoEstruturalLegada,
  type EstruturaSoberanaDoCliente,
} from "./estruturaSoberanaCliente";

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
 * Papéis exigidos pela estrutura de avaliação — FATOS RELACIONAIS da estrutura
 * soberana (nunca `funcao` textual, nunca cadeia local):
 * - gerente: existe cadeia de gestão resolvida acima do avaliado;
 * - coordenador: o gestor direto é nível INTERMEDIÁRIO (tem superior);
 * - colegiado: existe configuração de colegiado vigente com membros.
 */
export function calcularProgressoAvaliacao(
  criterios: CriterioBase[],
  avaliacoes: AvaliacoesBase,
  votosColegiado: VotosColegiadoBase,
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  feedbackFinalGerente: string,
  feedbackFinalCoordenador: string,
  estruturaSoberana?: EstruturaSoberanaDoCliente
): ProgressoAvaliacao {
  const totalSubcriterios = criterios.reduce(
    (total, criterio) => total + criterio.subcriterios.length,
    0
  );

  // F5-08 P6: a estrutura vem do PRODUTOR soberano (leitura RLS publicada pelo
  // shell autenticado). A fixture local só existe sob o gate explícito de DEV.
  const estrutura =
    estruturaSoberana ??
    estruturaSoberanaEfetiva([...colaboradores, colaborador]);
  const visao = visaoEstruturalLegada(estrutura, colaborador.matricula);

  // FAIL-CLOSED: sem evidência estrutural nenhuma exigência é presumida e a
  // avaliação NUNCA é declarada completa por dado local.
  const semEvidenciaEstrutural = visao === null;
  const gerenteNecessario = visao?.temCadeiaDeGestao ?? false;
  const coordenadorNecessario = visao?.gestorTemSuperior ?? false;
  const avaliadoresColegiado = visao?.colegiadoMatriculasLegadas ?? [];
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
