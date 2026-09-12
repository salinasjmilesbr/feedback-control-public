/**
 * F5-08 P6 (correção da auditoria GPT) — PROJEÇÃO ESTRUTURAL SOBERANA.
 *
 * ## O que este módulo encerra
 *
 * O contrato F5-08 §19.1 é explícito: as decisões de **papel/elegibilidade** de
 * `progressoAvaliacao`, `cicloEquipeService` e `metaStorage` passam a usar a
 * estrutura SOBERANA — `funcao` textual e `gestorDiretoMatricula` local **não**
 * decidem hierarquia. Antes desta correção esses três módulos derivavam papel,
 * cadeia de gestão e colegiado do cadastro local (`colaboradorStorage` /
 * `src/data/colaboradores`), inclusive em produção.
 *
 * Este módulo é a ÚNICA fronteira entre a estrutura organizacional e essas
 * decisões: os consumidores recebem uma **projeção** (fatos já resolvidos) e
 * nunca mais leem os campos estruturais locais. Por isso os fatos soberanos têm
 * nomes PRÓPRIOS (`gestorSoberanoMatricula`, `colegiadoSoberanoMatriculas`) —
 * distintos dos campos do cadastro local —, e a guarda estática
 * (`estruturaUiSeguranca.test.ts`) reprova quem voltar a lê-los.
 *
 * ## De onde vem a projeção
 *
 * 1. **Soberana (produção):** injetada por quem tem a estrutura lida do
 *    PostgreSQL pela leitura RLS/portas já existentes (P4/P5) — nenhuma fonte
 *    nova é criada aqui. Enquanto essa injeção não existir para um domínio, a
 *    projeção é VAZIA e a decisão é **fail-closed** (§19.1: "sem dado soberano ⇒
 *    vazio, nunca inventado").
 * 2. **Fixture de DEV/teste:** `projecaoDeFixtureLocal` converte o mundo local
 *    em projeção e é o ÚNICO lugar onde `funcao` textual e
 *    `gestorDiretoMatricula` local podem virar papel/cadeia — atrás do gate
 *    explícito de DEV (`simulacaoDevPermitida`), como o resto do cutover do P6.
 *
 * ## Proibições preservadas
 *
 * - nenhum papel é concedido por cargo/nome/matrícula textual;
 * - nenhuma cadeia é inferida de `respostaPara`, de `funcao` ou de fixture;
 * - nenhuma estrutura é fabricada para "destravar" a UI (§19.3): sem evidência,
 *   o consumidor devolve o estado NEGATIVO (não aplicável/sem alcance/negado).
 */

import { simulacaoDevPermitida } from "../config/ambiente";
import type { Colaborador } from "../types/Colaborador";
import { funcaoUsaEstruturaAvaliacaoAnalista } from "../types/Colaborador";

/** Papel estrutural RESOLVIDO pela estrutura organizacional (posição/cargo). */
export type PapelEstrutural = "GERENTE" | "COORDENADOR" | "OUTRO";

/** Fatos estruturais de UM colaborador, já resolvidos na origem. */
export interface VinculoEstruturalSoberano {
  readonly matricula: number;
  readonly papel: PapelEstrutural;
  /** Gestor DIRETO resolvido pela relação hierárquica vigente. */
  readonly gestorSoberanoMatricula: number | null;
  /**
   * Cadeia de gestão resolvida (gestor direto → raiz). Vazia quando não há
   * gestor ou quando a cadeia NÃO pôde ser resolvida por inteiro.
   */
  readonly cadeiaDeGestaoMatriculas: readonly number[];
  /**
   * `true` somente quando a cadeia foi resolvida até uma raiz real. Ciclo ou
   * elo ausente ⇒ `false` (nunca inventa raiz).
   */
  readonly cadeiaConfiavel: boolean;
  /** Avaliadores de colegiado vigentes na estrutura organizacional. */
  readonly colegiadoSoberanoMatriculas: readonly number[];
  /** A estrutura de avaliação (gerente/coordenador/colegiado) se aplica? */
  readonly usaEstruturaAvaliacao: boolean;
}

/** Projeção estrutural consumida pelos serviços de ciclo/metas. */
export interface ProjecaoEstruturalSoberana {
  readonly vinculos: ReadonlyMap<number, VinculoEstruturalSoberano>;
}

/** Projeção VAZIA — nenhuma evidência estrutural ⇒ fail-closed. */
export const PROJECAO_ESTRUTURAL_VAZIA: ProjecaoEstruturalSoberana = {
  vinculos: new Map(),
};

/**
 * Mensagem única da barreira: sem estrutura soberana NÃO existe derivação
 * local de papel/cadeia/elegibilidade (fail-closed).
 */
export const ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL =
  "A estrutura organizacional não pôde ser resolvida a partir do PostgreSQL. " +
  "Papel, cadeia de gestão e elegibilidade não são derivados de dados locais; " +
  "a operação foi recusada (fail-closed).";

export function criarProjecaoEstrutural(
  vinculos: readonly VinculoEstruturalSoberano[]
): ProjecaoEstruturalSoberana {
  return {
    vinculos: new Map(vinculos.map((vinculo) => [vinculo.matricula, vinculo])),
  };
}

/**
 * Projeção efetiva: a EXPLÍCITA (soberana) sempre vence; só o contexto DEV do
 * Vite pode cair na fixture local; fora dele, projeção VAZIA (fail-closed).
 */
export function resolverProjecaoEstrutural(
  explicita: ProjecaoEstruturalSoberana | undefined,
  mundoLocalDev: readonly Colaborador[] | undefined
): ProjecaoEstruturalSoberana {
  if (explicita) return explicita;
  if (simulacaoDevPermitida && mundoLocalDev) {
    return projecaoDeFixtureLocal(mundoLocalDev);
  }
  return PROJECAO_ESTRUTURAL_VAZIA;
}

export function vinculoEstrutural(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
): VinculoEstruturalSoberano | undefined {
  return projecao.vinculos.get(matricula);
}

/** Existe evidência estrutural soberana para a matrícula? */
export function temEvidenciaEstrutural(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
): boolean {
  return projecao.vinculos.has(matricula);
}

/** Matrícula do gestor SOBERANO direto (ou `null`). */
export function gestorSoberano(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
): number | null {
  return vinculoEstrutural(projecao, matricula)?.gestorSoberanoMatricula ?? null;
}

/** Papel do gestor DIRETO (ou `undefined` sem evidência/gestor). */
export function papelDoGestorDireto(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
): PapelEstrutural | undefined {
  const matriculaGestor = gestorSoberano(projecao, matricula);
  if (matriculaGestor === null) return undefined;
  return vinculoEstrutural(projecao, matriculaGestor)?.papel;
}

/** Algum membro da cadeia de gestão (direto → raiz) possui o papel? */
export function temPapelNaCadeia(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number,
  papel: PapelEstrutural
): boolean {
  const vinculo = vinculoEstrutural(projecao, matricula);
  if (!vinculo) return false;
  return vinculo.cadeiaDeGestaoMatriculas.some(
    (matriculaGestor) =>
      vinculoEstrutural(projecao, matriculaGestor)?.papel === papel
  );
}

/**
 * Raiz da cadeia de gestão = "gerente responsável" (dado estrutural, nunca
 * `funcao`). Sem gestor, a própria pessoa é a raiz — mesma semântica do domínio.
 * Sem evidência ou com cadeia não resolvida devolve `null` (fail-closed).
 */
export function raizDaCadeiaSoberana(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
): number | null {
  const vinculo = vinculoEstrutural(projecao, matricula);
  if (!vinculo || !vinculo.cadeiaConfiavel) return null;
  const cadeia = vinculo.cadeiaDeGestaoMatriculas;
  return cadeia.length > 0 ? (cadeia[cadeia.length - 1] as number) : matricula;
}

/** A estrutura de avaliação (gerente/coordenador/colegiado) se aplica? */
export function usaEstruturaAvaliacaoSoberana(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
): boolean {
  return vinculoEstrutural(projecao, matricula)?.usaEstruturaAvaliacao ?? false;
}

/** Avaliadores de colegiado vigentes (vazio sem evidência). */
export function avaliadoresColegiadoSoberanos(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
): readonly number[] {
  const vinculo = vinculoEstrutural(projecao, matricula);
  if (!vinculo || !vinculo.usaEstruturaAvaliacao) return [];
  return vinculo.colegiadoSoberanoMatriculas;
}

/** Subordinados DIRETOS na estrutura. */
export function subordinadosDiretosSoberanos(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
): readonly number[] {
  const resultado: number[] = [];
  for (const vinculo of projecao.vinculos.values()) {
    if (
      vinculo.matricula !== matricula &&
      vinculo.gestorSoberanoMatricula === matricula
    ) {
      resultado.push(vinculo.matricula);
    }
  }
  return resultado;
}

/**
 * Alcance estrutural do ator (quem ele ENXERGA pela estrutura):
 * - sem evidência estrutural ⇒ vazio (fail-closed, nada é concedido);
 * - raiz da cadeia ⇒ todos os descendentes;
 * - demais ⇒ subordinados diretos + colaboradores que ele avalia no colegiado.
 *
 * Espelha exatamente a semântica de `getColaboradoresVisiveis` (F4-09 D2/D3),
 * agora derivada da projeção e não do cadastro local.
 */
export function alcanceSoberano(
  projecao: ProjecaoEstruturalSoberana,
  matricula: number
): ReadonlySet<number> {
  const vinculo = vinculoEstrutural(projecao, matricula);
  if (!vinculo) return new Set();

  if (vinculo.gestorSoberanoMatricula === null) {
    const descendentes = new Set<number>();
    for (const candidato of projecao.vinculos.values()) {
      if (
        candidato.matricula !== matricula &&
        candidato.cadeiaDeGestaoMatriculas.includes(matricula)
      ) {
        descendentes.add(candidato.matricula);
      }
    }
    return descendentes;
  }

  const alcance = new Set<number>(
    subordinadosDiretosSoberanos(projecao, matricula)
  );
  for (const candidato of projecao.vinculos.values()) {
    if (
      candidato.matricula !== matricula &&
      candidato.colegiadoSoberanoMatriculas.includes(matricula)
    ) {
      alcance.add(candidato.matricula);
    }
  }
  return alcance;
}

// ---------------------------------------------------------------------------
// ADAPTADOR DE FIXTURE (DEV/teste) — nunca autoridade de produção
// ---------------------------------------------------------------------------

function papelDeFixture(colaborador: Colaborador): PapelEstrutural {
  if (colaborador.funcao === "GERENTE") return "GERENTE";
  if (colaborador.funcao === "COORDENADOR") return "COORDENADOR";
  return "OUTRO";
}

/**
 * Converte o mundo LOCAL (fixture/DEV) em projeção. É o único ponto do caminho
 * de ciclo/metas onde `funcao` textual e `gestorDiretoMatricula` local podem
 * virar papel e cadeia — e somente sob o gate DEV (`simulacaoDevPermitida`).
 */
export function projecaoDeFixtureLocal(
  colaboradores: readonly Colaborador[]
): ProjecaoEstruturalSoberana {
  const porMatricula = new Map(
    colaboradores.map((colaborador) => [colaborador.matricula, colaborador])
  );

  const vinculos = colaboradores.map((colaborador): VinculoEstruturalSoberano => {
    const cadeia: number[] = [];
    const visitados = new Set<number>([colaborador.matricula]);
    let confiavel = true;
    let atual = colaborador;

    while (atual.gestorDiretoMatricula) {
      const matriculaGestor = atual.gestorDiretoMatricula;
      if (visitados.has(matriculaGestor)) {
        confiavel = false;
        break;
      }
      visitados.add(matriculaGestor);

      const gestor = porMatricula.get(matriculaGestor);
      if (!gestor) {
        confiavel = false;
        break;
      }

      cadeia.push(matriculaGestor);
      atual = gestor;
    }

    return {
      matricula: colaborador.matricula,
      papel: papelDeFixture(colaborador),
      gestorSoberanoMatricula: colaborador.gestorDiretoMatricula ?? null,
      cadeiaDeGestaoMatriculas: cadeia,
      cadeiaConfiavel: confiavel,
      colegiadoSoberanoMatriculas: [
        ...(colaborador.avaliadoresColegiadoMatriculas ?? []),
      ],
      usaEstruturaAvaliacao: funcaoUsaEstruturaAvaliacaoAnalista(
        colaborador.funcao
      ),
    };
  });

  return criarProjecaoEstrutural(vinculos);
}
