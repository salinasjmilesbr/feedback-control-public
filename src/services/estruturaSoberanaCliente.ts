/**
 * F5-08 P6 (correção da auditoria GPT) — ESTRUTURA SOBERANA DO CLIENTE.
 *
 * ## Papel deste módulo (fronteira)
 *
 * 1. **PRODUTOR** da projeção estrutural pelo caminho NORMAL já existente:
 *    `lerEstrutura` (RLS/own-tenant, P4) + `listarColaboradores` (F5-07) →
 *    `montarProjecaoEstrutural` (UUID). Nada é injetado manualmente em produção:
 *    o shell autenticado carrega a estrutura e os consumidores leem a projeção
 *    publicada.
 * 2. **PONTE de compatibilidade** matrícula ↔ UUID, exclusivamente para os
 *    domínios LEGADOS que ainda indexam por matrícula (ciclo/meta).
 *    A hierarquia/projeção soberana NÃO conhece matrícula (ver
 *    `projecaoEstruturalSoberana.ts`): aqui a matrícula é apenas o rótulo humano
 *    usado pelo payload legado, conforme §19.3.
 * 3. **FIXTURE de DEV/teste**: o adaptador do mundo local fica atrás do gate
 *    explícito (`simulacaoDevPermitida`) e usa identificadores de FIXTURE
 *    (`fixture:<matrícula>`), nunca os UUIDs soberanos nem a matrícula como
 *    chave estrutural.
 *
 * ## Fail-closed
 *
 * - Supabase/serviço falhou, sessão ausente, organização ausente ou estrutura
 *   inconsistente ⇒ a projeção fica INDISPONÍVEL e as decisões devolvem o lado
 *   negativo (nunca dado local).
 * - Fora de DEV, a ausência de carregamento não é "modo normal": o shell
 *   carrega a estrutura automaticamente; enquanto isso a resposta é a negativa.
 */

import { simulacaoDevPermitida } from "../config/ambiente";
import type { Colaborador } from "../types/Colaborador";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import type { ColaboradorSoberano } from "./colaboradoresSoberanos/acessoColaboradoresSoberanos";
import {
  listarColaboradores,
  lerEstrutura,
  type DependenciasAcessoColaboradores,
} from "./colaboradoresSoberanos/acessoColaboradoresSoberanos";
import {
  PROJECAO_ESTRUTURAL_VAZIA,
  alcanceSoberano,
  colegiadoSoberano,
  criarProjecaoEstrutural,
  gestorSoberano,
  gestorSoberanoTemSuperior,
  montarProjecaoEstrutural,
  raizDaCadeiaSoberana,
  temCadeiaDeGestaoSoberana,
  vinculoEstrutural,
  type ProjecaoEstruturalSoberana,
  type VinculoEstruturalSoberano,
} from "./projecaoEstruturalSoberana";

/**
 * Estrutura soberana pronta para o cliente: a projeção (UUID) + a ponte de
 * compatibilidade do domínio legado (matrícula ↔ UUID).
 */
export interface EstruturaSoberanaDoCliente {
  readonly projecao: ProjecaoEstruturalSoberana;
  /** Ponte legado → UUID (`collaborator_identifiers.business_code` → `id`). */
  readonly ponteMatriculas: ReadonlyMap<string, string>;
  /** Ponte UUID → matrícula LEGADA numérica (só quando ela é um inteiro). */
  readonly matriculaLegada: ReadonlyMap<string, number>;
}

export const ESTRUTURA_SOBERANA_VAZIA: EstruturaSoberanaDoCliente = {
  projecao: PROJECAO_ESTRUTURAL_VAZIA,
  ponteMatriculas: new Map(),
  matriculaLegada: new Map(),
};

export type FaseEstruturaSoberana = "ocioso" | "carregando" | "pronta" | "indisponivel";

export interface EstadoEstruturaSoberana {
  readonly fase: FaseEstruturaSoberana;
  readonly organizacaoId: string | null;
  readonly estrutura: EstruturaSoberanaDoCliente;
  /** Código público quando indisponível (nunca detalhe do banco). */
  readonly codigo?: CodigoPublico;
  readonly mensagem?: string;
}

/** Construtor para teste/injeção explícita (nunca usado pelo caminho normal). */
export function criarEstruturaDoCliente(entrada: {
  readonly projecao: ProjecaoEstruturalSoberana;
  readonly ponteMatriculas?: ReadonlyMap<string, string>;
  readonly matriculaLegada?: ReadonlyMap<string, number>;
}): EstruturaSoberanaDoCliente {
  return {
    projecao: entrada.projecao,
    ponteMatriculas: entrada.ponteMatriculas ?? new Map(),
    matriculaLegada: entrada.matriculaLegada ?? new Map(),
  };
}

// ---------------------------------------------------------------------------
// Ponte de compatibilidade (matrícula ↔ UUID) — SOMENTE para o domínio legado
// ---------------------------------------------------------------------------

/** Matrícula legada numérica (o domínio legado indexa por inteiro). */
export function matriculaLegadaNumerica(matriculaSoberana: string | null): number | null {
  if (typeof matriculaSoberana !== "string") return null;
  const limpo = matriculaSoberana.trim();
  if (!/^\d+$/.test(limpo)) return null;
  const numero = Number(limpo);
  return Number.isSafeInteger(numero) ? numero : null;
}

/** UUID canônico da matrícula legada (ponte), ou `null` sem correspondência. */
export function collaboratorIdDoLegado(
  estrutura: EstruturaSoberanaDoCliente,
  matriculaLegada: number
): string | null {
  return estrutura.ponteMatriculas.get(String(matriculaLegada)) ?? null;
}

/** Matrícula legada do UUID canônico (ponte inversa), ou `null`. */
export function matriculaLegadaDoCollaborator(
  estrutura: EstruturaSoberanaDoCliente,
  collaboratorId: string
): number | null {
  return estrutura.matriculaLegada.get(collaboratorId) ?? null;
}

/**
 * Fatos estruturais do domínio LEGADO (matrícula), derivados do modelo por UUID
 * através da ponte. `null` = estrutura não provada ⇒ fail-closed.
 */
export interface VisaoEstruturalLegada {
  readonly collaboratorId: string;
  /** UUID do gestor direto (relação soberana). */
  readonly gestorCollaboratorId: string | null;
  /** Matrícula legada do gestor direto (ou `null` se não mapeável). */
  readonly gestorMatriculaLegada: number | null;
  /** Matrícula legada do SUPERIOR do gestor direto (um nível acima). */
  readonly superiorDoGestorMatriculaLegada: number | null;
  /** Matrícula legada da raiz da cadeia ("gerente responsável"). */
  readonly raizMatriculaLegada: number | null;
  /** Existe cadeia de gestão RESOLVIDA acima (há responsável pela avaliação)? */
  readonly temCadeiaDeGestao: boolean;
  /** O gestor direto é nível intermediário (papel "coordenador direto")? */
  readonly gestorTemSuperior: boolean;
  /** Colegiado vigente em matrículas legadas (para o payload legado de votos). */
  readonly colegiadoMatriculasLegadas: readonly number[];
}

export function visaoEstruturalLegada(
  estrutura: EstruturaSoberanaDoCliente,
  matriculaDaPessoa: number
): VisaoEstruturalLegada | null {
  const collaboratorId = collaboratorIdDoLegado(estrutura, matriculaDaPessoa);
  if (!collaboratorId) return null;

  const vinculo = vinculoEstrutural(estrutura.projecao, collaboratorId);
  if (!vinculo) return null;

  const gestorCollaboratorId = gestorSoberano(estrutura.projecao, collaboratorId);
  const superiorDoGestor =
    vinculo.cadeiaConfiavel ? (vinculo.cadeiaDeGestaoCollaboratorIds[1] ?? null) : null;
  const raiz = raizDaCadeiaSoberana(estrutura.projecao, collaboratorId);

  return {
    collaboratorId,
    gestorCollaboratorId,
    gestorMatriculaLegada:
      gestorCollaboratorId === null
        ? null
        : matriculaLegadaDoCollaborator(estrutura, gestorCollaboratorId),
    superiorDoGestorMatriculaLegada:
      superiorDoGestor === null
        ? null
        : matriculaLegadaDoCollaborator(estrutura, superiorDoGestor),
    raizMatriculaLegada:
      raiz === null ? null : matriculaLegadaDoCollaborator(estrutura, raiz),
    temCadeiaDeGestao: temCadeiaDeGestaoSoberana(estrutura.projecao, collaboratorId),
    gestorTemSuperior: gestorSoberanoTemSuperior(estrutura.projecao, collaboratorId),
    colegiadoMatriculasLegadas: colegiadoSoberano(estrutura.projecao, collaboratorId)
      .map((membro) => matriculaLegadaDoCollaborator(estrutura, membro))
      .filter((matricula): matricula is number => matricula !== null),
  };
}

/** Alcance estrutural em MATRÍCULAS legadas (quem o ator enxerga). */
export function alcanceLegado(
  estrutura: EstruturaSoberanaDoCliente,
  matriculaDoAtor: number
): ReadonlySet<number> {
  const collaboratorId = collaboratorIdDoLegado(estrutura, matriculaDoAtor);
  if (!collaboratorId) return new Set();

  const alcance = new Set<number>();
  for (const alcancado of alcanceSoberano(estrutura.projecao, collaboratorId)) {
    const matricula = matriculaLegadaDoCollaborator(estrutura, alcancado);
    if (matricula !== null) alcance.add(matricula);
  }
  return alcance;
}

/** Vínculo cru por matrícula legada (usado por decisões que precisam do UUID). */
export function vinculoLegado(
  estrutura: EstruturaSoberanaDoCliente,
  matriculaDaPessoa: number
): VinculoEstruturalSoberano | null {
  const collaboratorId = collaboratorIdDoLegado(estrutura, matriculaDaPessoa);
  if (!collaboratorId) return null;
  return vinculoEstrutural(estrutura.projecao, collaboratorId) ?? null;
}

// ---------------------------------------------------------------------------
// FIXTURE de DEV/teste (nunca autoridade de produção)
// ---------------------------------------------------------------------------

/**
 * Identificador de FIXTURE do mundo local. É deliberadamente namespaced para não
 * ser confundido com um UUID soberano — e para que a matrícula NÃO seja a chave
 * estrutural nem mesmo em DEV.
 */
export function idDeFixture(matricula: number): string {
  return `fixture:${matricula}`;
}

/**
 * Converte o mundo LOCAL (fixture/DEV) em estrutura do cliente. Só é alcançável
 * sob o gate `simulacaoDevPermitida` (ver `estruturaSoberanaEfetiva`).
 */
export function estruturaDeFixtureLocal(
  colaboradores: readonly Colaborador[]
): EstruturaSoberanaDoCliente {
  const porMatricula = new Map(
    colaboradores.map((colaborador) => [colaborador.matricula, colaborador])
  );

  const vinculos = colaboradores.map((colaborador): VinculoEstruturalSoberano => {
    const cadeiaPosicoes: string[] = [];
    const cadeiaColaboradores: string[] = [];
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

      cadeiaPosicoes.push(idDeFixture(matriculaGestor));
      cadeiaColaboradores.push(idDeFixture(matriculaGestor));
      atual = gestor;
    }

    const gestorDireto = colaborador.gestorDiretoMatricula
      ? porMatricula.get(colaborador.gestorDiretoMatricula)
      : undefined;

    return {
      collaboratorId: idDeFixture(colaborador.matricula),
      posicaoId: idDeFixture(colaborador.matricula),
      gestorSoberanoPositionId: colaborador.gestorDiretoMatricula
        ? idDeFixture(colaborador.gestorDiretoMatricula)
        : null,
      gestorSoberanoCollaboratorId: colaborador.gestorDiretoMatricula
        ? idDeFixture(colaborador.gestorDiretoMatricula)
        : null,
      cadeiaDeGestaoPositionIds: cadeiaPosicoes,
      cadeiaDeGestaoCollaboratorIds: cadeiaColaboradores,
      cadeiaConfiavel: confiavel && colaborador.gestorDiretoMatricula !== undefined,
      gestorTemSuperior: Boolean(gestorDireto?.gestorDiretoMatricula),
      colegiadoSoberanoCollaboratorIds: [
        ...(colaborador.avaliadoresColegiadoMatriculas ?? []),
      ].map(idDeFixture),
    };
  });

  const ponteMatriculas = new Map<string, string>();
  const matriculaLegada = new Map<string, number>();
  for (const colaborador of colaboradores) {
    ponteMatriculas.set(String(colaborador.matricula), idDeFixture(colaborador.matricula));
    matriculaLegada.set(idDeFixture(colaborador.matricula), colaborador.matricula);
  }

  return {
    projecao: criarProjecaoEstrutural(vinculos),
    ponteMatriculas,
    matriculaLegada,
  };
}

// ---------------------------------------------------------------------------
// ESTADO publicado (uma vez por sessão de página)
// ---------------------------------------------------------------------------

const ESTADO_INICIAL: EstadoEstruturaSoberana = {
  fase: "ocioso",
  organizacaoId: null,
  estrutura: ESTRUTURA_SOBERANA_VAZIA,
};

const SEM_ORGANIZACAO_ATIVA =
  "Selecione uma organização ativa para consultar a estrutura.";

let estado: EstadoEstruturaSoberana = ESTADO_INICIAL;
const assinantes = new Set<() => void>();

/**
 * GERAÇÃO monotônica das solicitações de estrutura.
 *
 * Cada solicitação (carga de uma organização OU invalidação de contexto)
 * incrementa a geração. Uma resposta assíncrona só pode PUBLICAR se a geração
 * capturada no início da carga ainda for a vigente — é o que impede que a
 * estrutura de uma organização antiga sobrescreva a da organização ativa
 * (troca A → B, perda de organização ativa, logout/unmount).
 */
let geracao = 0;

/** Organização do contexto VIGENTE (a última solicitada). */
let organizacaoVigente: string | null = null;

/**
 * Carga em curso. A deduplicação é por ORGANIZAÇÃO: duas chamadas simultâneas
 * da MESMA organização compartilham a promessa; A e B NUNCA são tratadas como a
 * mesma solicitação.
 */
let carregamentoEmCurso: {
  readonly organizacaoId: string;
  readonly geracao: number;
  readonly promessa: Promise<EstadoEstruturaSoberana>;
} | null = null;

function publicar(novo: EstadoEstruturaSoberana): void {
  estado = novo;
  for (const assinante of assinantes) assinante();
}

/** A carga desta geração/contexto ainda é a vigente? */
function cargaVigente(minhaGeracao: number, minhaOrganizacaoId: string): boolean {
  return minhaGeracao === geracao && organizacaoVigente === minhaOrganizacaoId;
}

/**
 * Publica SOMENTE se a carga ainda for a vigente; caso contrário devolve o
 * estado corrente (a resposta antiga é descartada sem efeito).
 */
function publicarSeVigente(
  novo: EstadoEstruturaSoberana,
  minhaGeracao: number,
  minhaOrganizacaoId: string
): EstadoEstruturaSoberana {
  if (!cargaVigente(minhaGeracao, minhaOrganizacaoId)) return estado;
  publicar(novo);
  return novo;
}

export function estadoEstruturaSoberana(): EstadoEstruturaSoberana {
  return estado;
}

export function assinarEstruturaSoberana(assinante: () => void): () => void {
  assinantes.add(assinante);
  return () => assinantes.delete(assinante);
}

/** Somente para testes: descarta o estado publicado e o carregamento em curso. */
export function redefinirEstruturaSoberana(): void {
  estado = ESTADO_INICIAL;
  geracao = 0;
  organizacaoVigente = null;
  carregamentoEmCurso = null;
  assinantes.clear();
}

/** Publicação explícita (teste/injeção determinística) — invalida cargas antigas. */
export function definirEstruturaSoberana(
  estrutura: EstruturaSoberanaDoCliente,
  organizacaoId: string | null = null
): void {
  geracao += 1;
  organizacaoVigente = organizacaoId;
  carregamentoEmCurso = null;
  publicar({ fase: "pronta", organizacaoId, estrutura });
}

/**
 * INVALIDA o contexto estrutural: nenhuma carga anterior pode publicar e a
 * estrutura anterior deixa de ser exposta (fail-closed). Usado quando a
 * organização ativa deixa de existir (seleção removida, troca para `null`,
 * logout/unmount do shell).
 */
export function invalidarEstruturaSoberana(): EstadoEstruturaSoberana {
  geracao += 1;
  organizacaoVigente = null;
  carregamentoEmCurso = null;

  // Idempotente: não notifica assinantes se o estado já é o inválido.
  if (estado.fase === "indisponivel" && estado.organizacaoId === null) return estado;

  const indisponivel: EstadoEstruturaSoberana = {
    fase: "indisponivel",
    organizacaoId: null,
    estrutura: ESTRUTURA_SOBERANA_VAZIA,
    codigo: "FORBIDDEN",
    mensagem: SEM_ORGANIZACAO_ATIVA,
  };
  publicar(indisponivel);
  return indisponivel;
}

/**
 * Carrega a estrutura SOBERANA pelo caminho normal: leitura RLS (`lerEstrutura`)
 * + projeção de colaboradores (`listarColaboradores`, que traz a ponte de
 * matrícula). Falha real ⇒ estado `indisponivel` (fail-closed), nunca dado local.
 *
 * ## Segurança multi-tenant
 *
 * - **Troca de organização**: uma nova carga incrementa a geração e publica
 *   imediatamente `carregando` com estrutura VAZIA — a estrutura da organização
 *   anterior deixa de ser acessível como estado atual;
 * - **Resposta obsoleta**: só publica quem ainda for a carga vigente; a resposta
 *   de A que chega depois de B é DESCARTADA (nunca sobrescreve B);
 * - **Deduplicação**: apenas para a MESMA organização e a MESMA geração;
 * - **Sem organização ativa**: o contexto é invalidado (estrutura VAZIA), nunca
 *   preservando a do tenant anterior.
 */
export function carregarEstruturaSoberana(
  entrada: { readonly organizationId?: string | null },
  deps: DependenciasAcessoColaboradores = {}
): Promise<EstadoEstruturaSoberana> {
  const organizationId =
    typeof entrada.organizationId === "string" && entrada.organizationId.length > 0
      ? entrada.organizationId
      : null;

  // Sem contexto válido: não preserva a estrutura anterior como utilizável.
  if (!organizationId) return Promise.resolve(invalidarEstruturaSoberana());

  // Dedupe SOMENTE da MESMA organização na MESMA geração.
  if (
    carregamentoEmCurso &&
    carregamentoEmCurso.organizacaoId === organizationId &&
    carregamentoEmCurso.geracao === geracao &&
    organizacaoVigente === organizationId
  ) {
    return carregamentoEmCurso.promessa;
  }

  geracao += 1;
  const minhaGeracao = geracao;
  organizacaoVigente = organizationId;

  // Troca de tenant: a estrutura publicada anterior deixa de ser válida JÁ.
  publicar({
    fase: "carregando",
    organizacaoId: organizationId,
    estrutura: ESTRUTURA_SOBERANA_VAZIA,
  });

  const promessa = (async (): Promise<EstadoEstruturaSoberana> => {
    try {
      const [leituraEstrutura, leituraColaboradores] = await Promise.all([
        lerEstrutura({ organizationId }, deps),
        listarColaboradores({ organizationId }, deps),
      ]);

      if (!leituraEstrutura.ok || !leituraColaboradores.ok) {
        const falha = leituraEstrutura.ok ? leituraColaboradores : leituraEstrutura;
        return publicarSeVigente(
          {
            fase: "indisponivel",
            organizacaoId: organizationId,
            estrutura: ESTRUTURA_SOBERANA_VAZIA,
            codigo: falha.ok ? "INTERNAL" : falha.codigo,
            mensagem: falha.ok
              ? "Não foi possível carregar a estrutura."
              : falha.mensagem,
          },
          minhaGeracao,
          organizationId
        );
      }

      const projecao = montarProjecaoEstrutural({
        posicoes: leituraEstrutura.dados.posicoes,
        reportingLines: leituraEstrutura.dados.reportingLines,
        ocupacoes: leituraEstrutura.dados.ocupacoes,
        colegiados: leituraEstrutura.dados.colegiados,
      });

      const estrutura = criarEstruturaDoCliente({
        projecao,
        ...montarPonte(leituraColaboradores.dados),
      });

      return publicarSeVigente(
        { fase: "pronta", organizacaoId: organizationId, estrutura },
        minhaGeracao,
        organizationId
      );
    } catch {
      return publicarSeVigente(
        {
          fase: "indisponivel",
          organizacaoId: organizationId,
          estrutura: ESTRUTURA_SOBERANA_VAZIA,
          codigo: "INTERNAL",
          mensagem: "Não foi possível carregar a estrutura organizacional.",
        },
        minhaGeracao,
        organizationId
      );
    } finally {
      // Só limpa a carga em curso se ela ainda for a DESTA requisição.
      if (carregamentoEmCurso?.geracao === minhaGeracao) carregamentoEmCurso = null;
    }
  })();

  carregamentoEmCurso = { organizacaoId: organizationId, geracao: minhaGeracao, promessa };
  return promessa;
}

function montarPonte(colaboradores: readonly ColaboradorSoberano[]): {
  readonly ponteMatriculas: ReadonlyMap<string, string>;
  readonly matriculaLegada: ReadonlyMap<string, number>;
} {
  const ponteMatriculas = new Map<string, string>();
  const matriculaLegada = new Map<string, number>();

  for (const colaborador of colaboradores) {
    if (!colaborador.collaboratorId || !colaborador.matricula) continue;
    ponteMatriculas.set(colaborador.matricula, colaborador.collaboratorId);
    const numero = matriculaLegadaNumerica(colaborador.matricula);
    if (numero !== null) matriculaLegada.set(colaborador.collaboratorId, numero);
  }

  return { ponteMatriculas, matriculaLegada };
}

/**
 * Estrutura EFETIVA para os consumidores:
 * 1. a projeção SOBERANA publicada (produção normal);
 * 2. em DEV, a fixture local (explícita e gated) quando a soberana não está
 *    disponível;
 * 3. caso contrário, VAZIA ⇒ fail-closed.
 */
export function estruturaSoberanaEfetiva(
  mundoLocalDev?: readonly Colaborador[]
): EstruturaSoberanaDoCliente {
  if (estado.fase === "pronta") return estado.estrutura;
  if (simulacaoDevPermitida && mundoLocalDev) return estruturaDeFixtureLocal(mundoLocalDev);
  return ESTRUTURA_SOBERANA_VAZIA;
}
