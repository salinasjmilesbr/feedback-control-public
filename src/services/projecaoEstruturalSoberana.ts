/**
 * F5-08 P6 (correção da auditoria GPT) — PROJEÇÃO ESTRUTURAL SOBERANA (UUID).
 *
 * ## O que este módulo é
 *
 * Um ADAPTADOR DE LEITURA: converte a fotografia SOBERANA já entregue pelo P4
 * (`lerEstrutura` → RLS own-tenant) em fatos estruturais prontos para as decisões
 * de papel/elegibilidade do domínio de ciclo/metas.
 *
 * Fontes soberanas usadas (todas já existentes; nenhuma fonte nova):
 * - `organizational_positions` (`posicoes`);
 * - `occupations` vigentes (`ocupacoes`);
 * - `position_reporting_lines` vigentes (`reportingLines`);
 * - `collegiate_configurations` + membros (`colegiados`).
 *
 * ## Identidade
 *
 * A identidade aqui é SEMPRE o UUID canônico (`collaborators.id`,
 * `organizational_positions.id`). **Este arquivo não conhece matrícula** — nem
 * como chave, nem como rótulo, nem como fallback (§19.3/§19.1: matrícula não é
 * identidade funcional). A compatibilidade com os domínios legados que ainda
 * usam matrícula vive na fronteira explícita de
 * `src/services/estruturaSoberanaCliente.ts` (ponte matrícula ↔ UUID), nunca
 * aqui.
 *
 * ## Hierarquia
 *
 * A hierarquia vem EXCLUSIVAMENTE de posições + reporting lines + ocupação
 * vigente (relações persistidas). Nenhum papel é inferido de texto, cargo, nome,
 * função ou matrícula: o que existe são FATOS RELACIONAIS —
 * "tem gestor?", "o gestor tem superior (é nível intermediário)?", "quem é a
 * raiz da cadeia?", "quem está no colegiado?".
 *
 * ## Vigência
 *
 * Modelo meio-aberto `[validFrom, validTo)` com referência injetável (mesma
 * regra do P4/P5 — `vigenteNaReferencia` replica `estaVigente` de
 * `apoioEstrutura`, com teste de equivalência). Valor inválido é FAIL-CLOSED:
 * nunca é tratado como vigente.
 *
 * ## Fail-closed
 *
 * Estrutura inconsistente (duas vigências simultâneas, ciclo de reporting,
 * posição de gestor vaga, ocupação ausente) NÃO é "adivinhada": o vínculo fica
 * marcado como não confiável e as decisões devolvem o lado negativo.
 */

import type {
  ColegiadoSoberano,
  OcupacaoSoberana,
  PeriodoParentSoberano,
  PosicaoSoberana,
  ReportingLineSoberana,
  UnidadeSoberana,
} from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";

/** Fatos estruturais de UM colaborador, resolvidos na hierarquia soberana. */
export interface VinculoEstruturalSoberano {
  /** UUID canônico (`collaborators.id`). */
  readonly collaboratorId: string;
  /** Posição ocupada VIGENTE (ou `null` sem ocupação vigente). */
  readonly posicaoId: string | null;
  /** Posição do gestor direto, resolvida por reporting line vigente. */
  readonly gestorSoberanoPositionId: string | null;
  /** Ocupante da posição do gestor (UUID) — `null` se a posição estiver vaga. */
  readonly gestorSoberanoCollaboratorId: string | null;
  /** Cadeia de gestão em POSIÇÕES (gestor direto → raiz). */
  readonly cadeiaDeGestaoPositionIds: readonly string[];
  /** Cadeia de gestão em COLABORADORES (gestor direto → raiz), em UUID. */
  readonly cadeiaDeGestaoCollaboratorIds: readonly string[];
  /** `true` somente quando a cadeia foi resolvida por inteiro até uma raiz. */
  readonly cadeiaConfiavel: boolean;
  /** O gestor direto tem superior (é nível INTERMEDIÁRIO da hierarquia)? */
  readonly gestorTemSuperior: boolean;
  /** Avaliadores de colegiado VIGENTES do colaborador (UUID). */
  readonly colegiadoSoberanoCollaboratorIds: readonly string[];
}

/** Projeção estrutural consumida pelos serviços de ciclo/metas. */
export interface ProjecaoEstruturalSoberana {
  readonly vinculos: ReadonlyMap<string, VinculoEstruturalSoberano>;
}

/** Fotografia soberana de entrada do adaptador (tipos do P4). */
export interface FotografiaEstruturalSoberana {
  readonly unidades?: readonly UnidadeSoberana[];
  readonly periodosParent?: readonly PeriodoParentSoberano[];
  readonly posicoes?: readonly PosicaoSoberana[];
  readonly reportingLines: readonly ReportingLineSoberana[];
  readonly ocupacoes: readonly OcupacaoSoberana[];
  readonly colegiados: readonly ColegiadoSoberano[];
  /** Instante ISO de referência da vigência (injetável; default = agora). */
  readonly referencia?: string;
}

/** Projeção VAZIA — nenhuma evidência estrutural ⇒ fail-closed. */
export const PROJECAO_ESTRUTURAL_VAZIA: ProjecaoEstruturalSoberana = {
  vinculos: new Map(),
};

/**
 * Mensagem única da barreira: sem estrutura soberana NÃO existe derivação local
 * de papel/cadeia/elegibilidade (fail-closed).
 */
export const ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL =
  "A estrutura organizacional não pôde ser resolvida a partir do PostgreSQL. " +
  "Papel, cadeia de gestão e elegibilidade não são derivados de dados locais; " +
  "a operação foi recusada (fail-closed).";

// ---------------------------------------------------------------------------
// Vigência (meio-aberto `[validFrom, validTo)`) — mesma regra do P4/P5
// ---------------------------------------------------------------------------

function instanteMs(valor: string | null | undefined): number | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  if (limpo.length === 0) return null;
  const ms = Date.parse(limpo);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Janela VIGENTE na referência? Início inclusivo, fim exclusivo. `validTo`
 * nulo/ausente = "sem término definido"; presente e inválido = FAIL-CLOSED.
 */
export function vigenteNaReferencia(
  validFrom: string | null | undefined,
  validTo: string | null | undefined,
  referencia: string
): boolean {
  const inicio = instanteMs(validFrom);
  const ref = instanteMs(referencia);
  const fimBruto = validTo === null || validTo === undefined ? null : validTo;
  const fim = fimBruto === null ? null : instanteMs(fimBruto);

  if (inicio === null || ref === null) return false;
  if (fimBruto !== null && fim === null) return false;
  if (fim !== null && fim <= inicio) return false;

  if (ref < inicio) return false;
  if (fim !== null && ref >= fim) return false;
  return true;
}

// ---------------------------------------------------------------------------
// Índices da fotografia (por UUID)
// ---------------------------------------------------------------------------

interface IndicesEstruturais {
  readonly posicaoDoColaborador: ReadonlyMap<string, string | null>;
  readonly gestorPosicaoDaPosicao: ReadonlyMap<string, string | null>;
  readonly ocupanteDaPosicao: ReadonlyMap<string, string | null>;
  readonly colegiadoDoColaborador: ReadonlyMap<string, readonly string[]>;
  readonly inconsistente: ReadonlySet<string>;
}

function montarIndices(fotografia: FotografiaEstruturalSoberana): IndicesEstruturais {
  const referencia = fotografia.referencia ?? new Date().toISOString();
  const inconsistente = new Set<string>();
  const vigente = <T extends { readonly validFrom: string; readonly validTo: string | null }>(
    item: T
  ) => vigenteNaReferencia(item.validFrom, item.validTo, referencia);

  const ocupacoesVigentes = fotografia.ocupacoes.filter(vigente);

  const posicaoDoColaborador = new Map<string, string | null>();
  for (const [collaboratorId, ocupacoes] of agrupar(
    ocupacoesVigentes,
    (ocupacao) => ocupacao.collaboratorId
  )) {
    if (ocupacoes.length > 1) {
      // Duas ocupações vigentes: a estrutura é ambígua ⇒ fail-closed.
      inconsistente.add(`colaborador:${collaboratorId}`);
      posicaoDoColaborador.set(collaboratorId, null);
      continue;
    }
    posicaoDoColaborador.set(collaboratorId, ocupacoes[0]?.posicaoId ?? null);
  }

  const ocupanteDaPosicao = new Map<string, string | null>();
  for (const [posicaoId, ocupacoes] of agrupar(
    ocupacoesVigentes,
    (ocupacao) => ocupacao.posicaoId
  )) {
    if (ocupacoes.length > 1) {
      inconsistente.add(`posicao:${posicaoId}`);
      ocupanteDaPosicao.set(posicaoId, null);
      continue;
    }
    ocupanteDaPosicao.set(posicaoId, ocupacoes[0]?.collaboratorId ?? null);
  }

  const gestorPosicaoDaPosicao = new Map<string, string | null>();
  for (const [posicaoId, linhas] of agrupar(
    fotografia.reportingLines.filter(vigente),
    (linha) => linha.subordinatePositionId
  )) {
    if (linhas.length > 1) {
      inconsistente.add(`reporting:${posicaoId}`);
      gestorPosicaoDaPosicao.set(posicaoId, null);
      continue;
    }
    gestorPosicaoDaPosicao.set(posicaoId, linhas[0]?.managerPositionId ?? null);
  }

  const colegiadoDoColaborador = new Map<string, readonly string[]>();
  for (const [collaboratorId, colegiados] of agrupar(
    fotografia.colegiados.filter(vigente),
    (colegiado) => colegiado.collaboratorId
  )) {
    if (colegiados.length > 1) {
      // Versão vigente ambígua ⇒ fail-closed: nenhum membro é presumido.
      inconsistente.add(`colegiado:${collaboratorId}`);
      colegiadoDoColaborador.set(collaboratorId, []);
      continue;
    }
    colegiadoDoColaborador.set(collaboratorId, [...(colegiados[0]?.membroIds ?? [])]);
  }

  return {
    posicaoDoColaborador,
    gestorPosicaoDaPosicao,
    ocupanteDaPosicao,
    colegiadoDoColaborador,
    inconsistente,
  };
}

function agrupar<T>(
  itens: readonly T[],
  chave: (item: T) => string
): ReadonlyMap<string, readonly T[]> {
  const grupos = new Map<string, T[]>();
  for (const item of itens) {
    const atual = grupos.get(chave(item)) ?? [];
    atual.push(item);
    grupos.set(chave(item), atual);
  }
  return grupos;
}

/**
 * ADAPTADOR de leitura: fotografia soberana → projeção estrutural por UUID.
 *
 * Percorre a hierarquia por POSIÇÕES (reporting lines) e resolve cada elo no
 * OCUPANTE da posição. Qualquer elo não resolvido (posição vaga, ciclo, dado
 * ambíguo) marca a cadeia como NÃO confiável — nunca é adivinhado.
 */
export function montarProjecaoEstrutural(
  fotografia: FotografiaEstruturalSoberana
): ProjecaoEstruturalSoberana {
  const indices = montarIndices(fotografia);
  const gestorDaPosicao = (posicaoId: string): string | null =>
    indices.gestorPosicaoDaPosicao.get(posicaoId) ?? null;

  const vinculos = new Map<string, VinculoEstruturalSoberano>();

  for (const [collaboratorId, posicaoId] of indices.posicaoDoColaborador) {
    const cadeiaPosicoes: string[] = [];
    const cadeiaColaboradores: string[] = [];
    let confiavel = !indices.inconsistente.has(`colaborador:${collaboratorId}`);

    let posicaoAtual = posicaoId;
    const visitados = new Set<string>(posicaoId ? [posicaoId] : []);

    while (posicaoAtual) {
      if (indices.inconsistente.has(`reporting:${posicaoAtual}`)) confiavel = false;

      const posicaoGestor = gestorDaPosicao(posicaoAtual);
      if (posicaoGestor === null) break;

      if (visitados.has(posicaoGestor)) {
        // Ciclo de reporting (o banco barra, mas a leitura não confia).
        confiavel = false;
        break;
      }
      visitados.add(posicaoGestor);
      cadeiaPosicoes.push(posicaoGestor);

      const ocupante = indices.ocupanteDaPosicao.get(posicaoGestor) ?? null;
      if (ocupante === null) {
        // Posição de gestor VAGA: não há gestor provado ⇒ fail-closed.
        confiavel = false;
        break;
      }
      if (indices.inconsistente.has(`posicao:${posicaoGestor}`)) confiavel = false;

      cadeiaColaboradores.push(ocupante);
      posicaoAtual = posicaoGestor;
    }

    const gestorSoberanoPositionId = posicaoId ? gestorDaPosicao(posicaoId) : null;
    const gestorSoberanoCollaboratorId = cadeiaColaboradores[0] ?? null;

    vinculos.set(collaboratorId, {
      collaboratorId,
      posicaoId,
      gestorSoberanoPositionId,
      gestorSoberanoCollaboratorId,
      cadeiaDeGestaoPositionIds: cadeiaPosicoes,
      cadeiaDeGestaoCollaboratorIds: cadeiaColaboradores,
      // `cadeiaConfiavel` = a cadeia foi resolvida POR INTEIRO, inclusive a
      // evidência de RAIZ quando não há gestor acima. Não confundir com "tem
      // gestor": quem não tem gestor é raiz PROVADA, não cadeia desconhecida.
      cadeiaConfiavel: confiavel,
      gestorTemSuperior:
        gestorSoberanoPositionId !== null &&
        gestorDaPosicao(gestorSoberanoPositionId) !== null,
      colegiadoSoberanoCollaboratorIds: [
        ...(indices.colegiadoDoColaborador.get(collaboratorId) ?? []),
      ],
    });
  }

  return { vinculos };
}

/** Projeção a partir de vínculos já resolvidos (teste/fixture explícita). */
export function criarProjecaoEstrutural(
  vinculos: readonly VinculoEstruturalSoberano[]
): ProjecaoEstruturalSoberana {
  return {
    vinculos: new Map(vinculos.map((vinculo) => [vinculo.collaboratorId, vinculo])),
  };
}

// ---------------------------------------------------------------------------
// Consultas soberanas (SEMPRE por UUID canônico)
// ---------------------------------------------------------------------------

export function vinculoEstrutural(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): VinculoEstruturalSoberano | undefined {
  return projecao.vinculos.get(collaboratorId);
}

/** Existe evidência estrutural soberana para o colaborador (UUID)? */
export function temEvidenciaEstrutural(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): boolean {
  return projecao.vinculos.has(collaboratorId);
}

/** Posição ocupada VIGENTE (UUID) ou `null`. */
export function posicaoSoberana(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): string | null {
  return vinculoEstrutural(projecao, collaboratorId)?.posicaoId ?? null;
}

/** Gestor direto (UUID) resolvido pela hierarquia, ou `null`. */
export function gestorSoberano(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): string | null {
  const vinculo = vinculoEstrutural(projecao, collaboratorId);
  if (!vinculo || !vinculo.cadeiaConfiavel) return null;
  return vinculo.gestorSoberanoCollaboratorId;
}

/**
 * Existe cadeia de gestão RESOLVIDA acima do colaborador? É o fato relacional
 * que sustenta "há um responsável pela avaliação" (antes: "existe GERENTE na
 * cadeia" por `funcao` textual).
 */
export function temCadeiaDeGestaoSoberana(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): boolean {
  const vinculo = vinculoEstrutural(projecao, collaboratorId);
  return Boolean(vinculo?.cadeiaConfiavel && vinculo.gestorSoberanoCollaboratorId);
}

/**
 * O gestor direto é NÍVEL INTERMEDIÁRIO (tem superior)? Fato relacional que
 * sustenta o papel "coordenador direto" (antes: `gestor.funcao === "COORDENADOR"`).
 */
export function gestorSoberanoTemSuperior(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): boolean {
  const vinculo = vinculoEstrutural(projecao, collaboratorId);
  if (!vinculo || !vinculo.cadeiaConfiavel) return false;
  return vinculo.gestorTemSuperior;
}

/**
 * Raiz da cadeia = "gerente responsável" (F4-09 D2/D3: dado relacional, nunca
 * `funcao`). Sem gestor, a própria pessoa é a raiz. Sem evidência/cadeia não
 * resolvida devolve `null` (fail-closed).
 */
export function raizDaCadeiaSoberana(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): string | null {
  const vinculo = vinculoEstrutural(projecao, collaboratorId);
  if (!vinculo || !vinculo.cadeiaConfiavel) return null;
  const cadeia = vinculo.cadeiaDeGestaoCollaboratorIds;
  return cadeia.length > 0 ? (cadeia[cadeia.length - 1] as string) : collaboratorId;
}

/** Avaliadores de colegiado VIGENTES (UUID); vazio sem evidência. */
export function colegiadoSoberano(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): readonly string[] {
  return (
    vinculoEstrutural(projecao, collaboratorId)?.colegiadoSoberanoCollaboratorIds ?? []
  );
}

/** Subordinados DIRETOS (UUID) na hierarquia. */
export function subordinadosDiretosSoberanos(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): readonly string[] {
  const resultado: string[] = [];
  for (const vinculo of projecao.vinculos.values()) {
    if (
      vinculo.collaboratorId !== collaboratorId &&
      vinculo.cadeiaConfiavel &&
      vinculo.gestorSoberanoCollaboratorId === collaboratorId
    ) {
      resultado.push(vinculo.collaboratorId);
    }
  }
  return resultado;
}

/**
 * Alcance estrutural do ator (quem ele ENXERGA pela estrutura), em UUID:
 * - sem evidência estrutural ⇒ vazio (fail-closed, nada é concedido);
 * - raiz (sem gestor) ⇒ todos os descendentes;
 * - demais ⇒ subordinados diretos + colaboradores que ele avalia no colegiado.
 *
 * Espelha a semântica de `getColaboradoresVisiveis` (F4-09 D2/D3), agora
 * derivada das relações soberanas — nunca do cadastro local.
 */
export function alcanceSoberano(
  projecao: ProjecaoEstruturalSoberana,
  collaboratorId: string
): ReadonlySet<string> {
  const vinculo = vinculoEstrutural(projecao, collaboratorId);
  if (!vinculo) return new Set();

  if (gestorSoberano(projecao, collaboratorId) === null) {
    const descendentes = new Set<string>();
    for (const candidato of projecao.vinculos.values()) {
      if (
        candidato.collaboratorId !== collaboratorId &&
        candidato.cadeiaConfiavel &&
        candidato.cadeiaDeGestaoCollaboratorIds.includes(collaboratorId)
      ) {
        descendentes.add(candidato.collaboratorId);
      }
    }
    return descendentes;
  }

  const alcance = new Set<string>(
    subordinadosDiretosSoberanos(projecao, collaboratorId)
  );
  for (const candidato of projecao.vinculos.values()) {
    if (
      candidato.collaboratorId !== collaboratorId &&
      candidato.colegiadoSoberanoCollaboratorIds.includes(collaboratorId)
    ) {
      alcance.add(candidato.collaboratorId);
    }
  }
  return alcance;
}
