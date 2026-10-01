/**
 * F5-06 (Issue #103) — contrato TRANSPORTÁVEL do caminho novo de avaliações.
 *
 * Este módulo define a superfície que o cliente pode pedir e o que a fronteira
 * confiável devolve. Invariantes (D3/D6/D10/D23/D26/D27):
 * - o cliente envia apenas a INTENÇÃO (operação, alvo, dados de entrada);
 * - `organization_id` é intenção a ser REVALIDADA contra membership ativa;
 * - identificadores são UUID (`collaborators.id` / `evaluations.id`), nunca
 *   matrícula, nome ou e-mail;
 * - nenhum `actor_id`, `participant_id` ou `config_version_id` do cliente é
 *   aceito como autoridade: o snapshot de participantes e a versão de
 *   configuração são derivados server-side, e a OCORRÊNCIA editável é resolvida
 *   a partir do ator autenticado (auth.uid → vínculo F5-02 → vigência);
 * - a resposta de erro expõe somente código público (F0-05), nunca a razão
 *   interna da negação.
 */

/** Operações suportadas pelo caminho novo (avaliações em PostgreSQL). */
export type OperacaoAvaliacao =
  | "evaluation.criar"
  | "evaluation.ler"
  | "evaluation.gravar_notas"
  | "evaluation.gravar_comentario"
  | "evaluation.concluir"
  | "evaluation.reabrir"
  | "evaluation.cancelar"
  | "evaluation.participantes_realinhar"
  | "evaluation.transparencia"
  | "evaluation.painel_participante"
  | "evaluation.resolver_ciclo"
  | "evaluation.do_colaborador_no_ciclo"
  | "evaluation.painel_participantes"
  | "report.listar";

/** Alvo autorizável (mesmo `TargetRef` do Policy Engine). */
export interface AlvoAvaliacao {
  readonly type: "evaluation" | "collaborator";
  readonly id: string;
}

export interface EntradaAvaliacao {
  readonly organization_id: string;
  readonly operacao: OperacaoAvaliacao;
  /** Ausente somente em `report.listar`: o universo nunca vem do cliente. */
  readonly alvo?: AlvoAvaliacao;
  /** Notas do lote: `{ subcriterion_id, nota }[]` (1..5). */
  readonly notas?: readonly { readonly subcriterion_id: string; readonly nota: number }[];
  /**
   * CORREÇÃO DE AUDITORIA (IDOR): `participant_id` NÃO faz parte deste contrato.
   * A ocorrência editável é resolvida server-side a partir do ator autenticado
   * (auth.uid → membership → vínculo F5-02 → ocorrência vigente). Enviar esse
   * campo é `INVALID_INPUT` — o browser não escolhe a ocorrência de ninguém.
   */
  readonly escopo?: "CRITERIO" | "FINAL";
  readonly criterion_id?: string | null;
  readonly texto?: string;
  readonly motivo?: string;
  /** Ciclo pretendido (intenção) na criação da avaliação. */
  readonly cycle_id?: string;
  /**
   * Matrícula do colaborador avaliado — usado SOMENTE na criação, para a ponte
   * matrícula → UUID resolvida na fronteira confiável (F3-01). Continua sendo
   * INTENÇÃO: o valor autoritativo é o UUID resolvido server-side.
   */
  readonly matricula_avaliado?: number | string;
  /** Ano/ciclo pretendidos (INTENÇÃO) na resolução do ciclo soberano. */
  readonly ano?: number;
  readonly numero?: number;
}

export type CodigoPublico =
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "INVALID_INPUT"
  | "INTERNAL"
  | "NOT_AUTHORIZED";

export interface RespostaAvaliacao {
  readonly ok: boolean;
  readonly code?: CodigoPublico;
  readonly message?: string;
  readonly resultado?: unknown;
}

/** Capacidade exigida por operação (contrato §8.3 — nenhuma capability nova). */
export const CAPABILITY_POR_OPERACAO: Readonly<Record<OperacaoAvaliacao, string>> = {
  "evaluation.criar": "evaluation.create",
  "evaluation.ler": "evaluation.read",
  "evaluation.gravar_notas": "evaluation.write",
  "evaluation.gravar_comentario": "evaluation.write",
  "evaluation.concluir": "evaluation.write",
  "evaluation.reabrir": "evaluation.reopen",
  "evaluation.cancelar": "evaluation.cancel",
  "evaluation.participantes_realinhar": "evaluation.write",
  "evaluation.transparencia": "evaluation.read",
  // Leitura de EDIÇÃO da própria ocorrência exige a capability de escrita: é a
  // operação que habilita o participante a editar o que ele mesmo lançou.
  "evaluation.painel_participante": "evaluation.write",
  // Resolver ano+ciclo é pré-requisito de criação ⇒ mesma capability de criação.
  "evaluation.resolver_ciclo": "evaluation.create",
  "report.listar": "report.read",
  /**
   * Descoberta da avaliação do colaborador no ciclo.
   *
   * O código declarado aqui é NOMINAL (a operação é uma LEITURA). A decisão real
   * é o OR explícito das três capabilities que habilitam alguma AÇÃO sobre o
   * par (colaborador, ciclo) — ver `CAPABILIDADES_DESCOBERTA_AVALIACAO` e
   * `resolverDescobertaAvaliacao`. Nenhuma capability nova é criada e o catálogo
   * fechado permanece intacto.
   */
  "evaluation.do_colaborador_no_ciclo": "evaluation.read",
  /**
   * Leitura COLETIVA dos participantes (R2). O código é NOMINAL: o entitlement
   * real é o OR explícito `evaluation.write` (scope do papel) ou
   * `evaluation.read + ASSIGNED` — ver `resolverLeituraColetiva`. Nenhuma
   * capability nova é criada.
   */
  "evaluation.painel_participantes": "evaluation.write",
};

/**
 * Conjunto FECHADO e explícito de capabilities aceitas pela descoberta.
 *
 * Cada uma corresponde a uma ação que o ator JÁ poderia executar com o id em
 * mãos: criar (`create`), editar a própria ocorrência (`write`) ou consultar
 * (`read`). A descoberta não amplia autoridade — apenas permite à ficha decidir
 * QUAL ação oferecer.
 */
export const CAPABILIDADES_DESCOBERTA_AVALIACAO: readonly string[] = [
  "evaluation.create",
  "evaluation.write",
  "evaluation.read",
];

/**
 * R2 — entitlements que sustentam a LEITURA COLETIVA dos participantes.
 *
 * `evaluation.write` em qualquer scope de F6-AVALIACOES-05 D4, conforme o papel
 * (`DIRECT_REPORTS`/`DESCENDANTS`/`ASSIGNED`); OU `evaluation.read` SOMENTE com
 * `ASSIGNED` (papel `evaluator` de #306). `evaluation.read` isolado, SELF,
 * scope administrativo ou acesso excepcional sem ASSIGNED NÃO bastam. Nenhuma
 * capability/scope/bundle é ampliado.
 */
export const SCOPES_ESCRITA_LEITURA_COLETIVA: readonly string[] = [
  "DIRECT_REPORTS",
  "DESCENDANTS",
  "ASSIGNED",
];
export const SCOPE_LEITURA_LEITURA_COLETIVA = "ASSIGNED";

/**
 * Regra PURA do entitlement da leitura coletiva (fail-closed).
 *
 * Exige, SIMULTANEAMENTE: ocorrência materializada vigente do ator (resolvida
 * server-side) E um dos dois caminhos de capability/scope. Qualquer ausência
 * nega. Não decide tenant, relação nem estado — isso é do Policy Engine.
 */
export function resolverLeituraColetiva(entrada: {
  readonly participanteVigente: boolean;
  readonly autorizaEscrita: boolean;
  readonly autorizaLeituraAssigned: boolean;
}): { readonly allowed: boolean } {
  if (entrada.participanteVigente !== true) return { allowed: false };
  return {
    allowed: entrada.autorizaEscrita === true || entrada.autorizaLeituraAssigned === true,
  };
}

/**
 * Projeção COLETIVA dos participantes (R2) — payload server-side.
 *
 * Participantes veem identidades/papéis dos demais, todas as notas individuais
 * existentes (inclusive de cada colegiado), comentários por critério e Feedbacks
 * Finais existentes. `progressoFactual` é apenas CONTAGEM derivada dos dados —
 * NÃO é completude normativa (pendências por ocorrência são do Incremento 2).
 */
export interface PainelParticipantesAvaliacao {
  readonly evaluationId: string;
  readonly organizationId: string;
  readonly cycleId: string;
  readonly cycleAno: number;
  readonly cycleNumero: number;
  readonly configVersionId: string;
  readonly status: string;
  readonly evaluatedCollaboratorId: string;
  /** Própria ocorrência: identificável para renderização; não concede escrita. */
  readonly meuParticipante: {
    readonly ocorrenciaId: string;
    readonly roleType: string;
    readonly meusPapeis: readonly string[];
  };
  readonly participantes: readonly {
    readonly collaboratorId: string;
    readonly nome: string | null;
    readonly roleType: string;
    readonly validFrom: string;
    readonly validTo: string | null;
  }[];
  readonly criterios: readonly {
    readonly criterionId: string;
    readonly code: string;
    readonly name: string;
    readonly position: number;
  }[];
  readonly subcriterios: readonly {
    readonly subcriterionId: string;
    readonly code: string;
    readonly name: string;
    readonly position: number;
    readonly criterionCode: string;
  }[];
  readonly notas: readonly {
    readonly collaboratorId: string;
    readonly roleType: string;
    readonly subcriterionId: string;
    readonly nota: number;
  }[];
  readonly comentarios: readonly {
    readonly collaboratorId: string;
    readonly roleType: string;
    readonly criterionId: string;
    readonly texto: string;
  }[];
  readonly feedbacksFinais: readonly {
    readonly collaboratorId: string;
    readonly roleType: string;
    readonly texto: string;
  }[];
  readonly progressoFactual: readonly {
    readonly collaboratorId: string;
    readonly roleType: string;
    readonly notasInformadas: number;
    readonly subcriteriosTotal: number;
  }[];
}

/** Payload MÍNIMO da descoberta: id soberano, estado e permissão de edição. */
export interface DescobertaAvaliacaoDoColaborador {
  readonly evaluationId?: string | null;
  readonly status?: string | null;
  /** CREATE válido permite conhecer somente a existência, sem acessar conteúdo.
   * Nesse ramo evaluationId e status são OMITIDOS do JSON, não nulos. */
  readonly existeSemAcesso?: true;
  /**
   * Decidido SERVER-SIDE pelo ramo `evaluation.write` (ocorrência materializada
   * vigente). A UI nunca reconstrói scopes/relações para decidir edição.
   */
  readonly podeEditar: boolean;
}

/** Estados da avaliação relevantes para a decisão da ficha. */
export type StatusAvaliacaoDescoberta = "RASCUNHO" | "CONCLUIDA" | string;

/**
 * Regra PURA da descoberta (fail-closed).
 *
 * - existe avaliação não cancelada ⇒ ALLOW com conteúdo se `evaluation.write`
 *   ou `evaluation.read`; somente `evaluation.create` ⇒ ALLOW com o bit de
 *   existência, sem id, status ou qualquer dado da avaliação.
 *   `podeEditar` vem EXCLUSIVAMENTE do ramo `write`; o status devolvido é o da
 *   avaliação real.
 * - NÃO existe (ou só cancelada) ⇒ ALLOW **somente** para quem pode CRIAR, com
 *   `{evaluationId:null, status:null, podeEditar:false}`; qualquer outro ator
 *   recebe DENY (não se revela ausência a quem não poderia agir).
 *
 * A função nunca lança e nunca devolve dados locais.
 */
export function resolverDescobertaAvaliacao(estado: {
  readonly avaliacao: { readonly id: string; readonly status: string } | null;
  readonly autorizaCriar: boolean;
  readonly autorizaEscrever: boolean;
  readonly autorizaLer: boolean;
}):
  | { readonly allowed: true; readonly resultado: DescobertaAvaliacaoDoColaborador }
  | { readonly allowed: false } {
  if (!estado.avaliacao) {
    if (!estado.autorizaCriar) return { allowed: false };
    return {
      allowed: true,
      resultado: { evaluationId: null, status: null, podeEditar: false },
    };
  }

  const allowed = estado.autorizaEscrever || estado.autorizaLer;
  if (!allowed) {
    return estado.autorizaCriar
      ? { allowed: true, resultado: { existeSemAcesso: true, podeEditar: false } }
      : { allowed: false };
  }

  return {
    allowed: true,
    resultado: {
      evaluationId: estado.avaliacao.id,
      status: estado.avaliacao.status,
      podeEditar:
        estado.autorizaEscrever &&
        ["RASCUNHO", "PRONTA_PARA_FEEDBACK"].includes(estado.avaliacao.status),
    },
  };
}

/** Alvo autorizável de cada operação (criação e resolução de ciclo usam o colaborador). */
export function tipoAlvoDaOperacao(operacao: OperacaoAvaliacao): AlvoAvaliacao["type"] {
  return operacao === "evaluation.criar" ||
    operacao === "evaluation.resolver_ciclo" ||
    operacao === "evaluation.do_colaborador_no_ciclo"
    ? "collaborator"
    : "evaluation";
}

export const OPERACOES_AVALIACAO: readonly OperacaoAvaliacao[] = Object.keys(
  CAPABILITY_POR_OPERACAO
) as readonly OperacaoAvaliacao[];

export function ehOperacaoAvaliacao(valor: unknown): valor is OperacaoAvaliacao {
  return typeof valor === "string" && (OPERACOES_AVALIACAO as readonly string[]).includes(valor);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function ehUuid(valor: unknown): valor is string {
  return typeof valor === "string" && UUID.test(valor.trim());
}

export type ResultadoValidacao =
  | { readonly ok: true; readonly entrada: EntradaAvaliacao }
  | { readonly ok: false; readonly code: CodigoPublico; readonly message: string };

/**
 * Valida a FORMA da intenção (nunca a autoridade): campos obrigatórios, UUIDs
 * bem formados e ausência de campos de identidade proibidos. Qualquer desvio é
 * `INVALID_INPUT` — fail-closed.
 */
export function validarEntradaAvaliacao(corpo: unknown): ResultadoValidacao {
  if (typeof corpo !== "object" || corpo === null || Array.isArray(corpo)) {
    return { ok: false, code: "INVALID_INPUT", message: "Corpo da requisição inválido." };
  }
  const cru = corpo as Record<string, unknown>;

  // Identidade nunca vem do cliente (D20/D27).
  for (const proibido of ["actor_id", "actor_user_profile_id", "user_profile_id", "ator"]) {
    if (cru[proibido] !== undefined) {
      return {
        ok: false,
        code: "INVALID_INPUT",
        message: "A identidade do ator não é aceita no corpo da requisição.",
      };
    }
  }

  // CORREÇÃO DE AUDITORIA (IDOR): a ocorrência editável é resolvida server-side.
  // Qualquer tentativa de escolhê-la pelo payload é recusada de forma explícita.
  if (cru.participant_id !== undefined && cru.participant_id !== null) {
    return {
      ok: false,
      code: "INVALID_INPUT",
      message: "A ocorrência do participante é resolvida no servidor e não é aceita no corpo.",
    };
  }

  if (!ehOperacaoAvaliacao(cru.operacao)) {
    return { ok: false, code: "INVALID_INPUT", message: "Operação de avaliação desconhecida." };
  }
  if (!ehUuid(cru.organization_id)) {
    return { ok: false, code: "INVALID_INPUT", message: "organization_id inválido." };
  }

  if (cru.operacao === "report.listar") {
    if (cru.alvo !== undefined) {
      return {
        ok: false,
        code: "INVALID_INPUT",
        message: "O universo do relatório é resolvido no servidor e não aceita alvo.",
      };
    }
    if (!ehUuid(cru.cycle_id)) {
      return { ok: false, code: "INVALID_INPUT", message: "cycle_id obrigatório e inválido." };
    }
    return { ok: true, entrada: cru as unknown as EntradaAvaliacao };
  }

  // Descoberta da avaliação do colaborador: LEITURA estrita — allowlist de
  // chaves própria. Nenhum campo de escrita/intenção de mutação é aceito.
  if (cru.operacao === "evaluation.do_colaborador_no_ciclo") {
    const permitidas = ["operacao", "organization_id", "alvo", "cycle_id"];
    if (Object.keys(cru).some((chave) => !permitidas.includes(chave))) {
      return {
        ok: false,
        code: "INVALID_INPUT",
        message: "A descoberta da avaliação do colaborador aceita apenas operacao, organization_id, alvo e cycle_id.",
      };
    }
    if (!ehUuid(cru.cycle_id)) {
      return { ok: false, code: "INVALID_INPUT", message: "cycle_id obrigatório e inválido." };
    }
  }

  // Leitura COLETIVA dos participantes (R2): LEITURA estrita — allowlist própria.
  // Nenhuma nota, comentário, ocorrência ou intenção de mutação é aceita.
  if (cru.operacao === "evaluation.painel_participantes") {
    const permitidas = ["operacao", "organization_id", "alvo"];
    if (Object.keys(cru).some((chave) => !permitidas.includes(chave))) {
      return {
        ok: false,
        code: "INVALID_INPUT",
        message:
          "A leitura coletiva dos participantes aceita apenas operacao, organization_id e alvo.",
      };
    }
  }

  const alvoCru = cru.alvo;
  if (typeof alvoCru !== "object" || alvoCru === null || Array.isArray(alvoCru)) {
    return { ok: false, code: "INVALID_INPUT", message: "Alvo inválido." };
  }
  const alvo = alvoCru as Record<string, unknown>;
  const tipoEsperado = tipoAlvoDaOperacao(cru.operacao);
  if (alvo.type !== tipoEsperado || !ehUuid(alvo.id)) {
    return {
      ok: false,
      code: "INVALID_INPUT",
      message: `A operação ${cru.operacao} exige alvo do tipo ${tipoEsperado}.`,
    };
  }

  if (cru.cycle_id !== undefined && cru.cycle_id !== null && !ehUuid(cru.cycle_id)) {
    return { ok: false, code: "INVALID_INPUT", message: "cycle_id inválido." };
  }
  // Ano/ciclo são INTENÇÃO da tela (resolvidos server-side no tenant validado).
  if (cru.ano !== undefined && cru.ano !== null) {
    if (typeof cru.ano !== "number" || !Number.isInteger(cru.ano) || cru.ano <= 0) {
      return { ok: false, code: "INVALID_INPUT", message: "ano inválido." };
    }
  }
  if (cru.numero !== undefined && cru.numero !== null) {
    if (typeof cru.numero !== "number" || ![1, 2, 3].includes(cru.numero)) {
      return { ok: false, code: "INVALID_INPUT", message: "numero de ciclo inválido (1..3)." };
    }
  }
  // Matrícula é INTENÇÃO (ponte resolvida server-side): aceita número inteiro
  // positivo ou sua forma textual; qualquer outro valor é recusado.
  if (cru.matricula_avaliado !== undefined && cru.matricula_avaliado !== null) {
    const bruto = cru.matricula_avaliado;
    const texto = typeof bruto === "number" ? String(bruto) : bruto;
    if (typeof texto !== "string" || !/^\d+$/.test(texto.trim()) || Number(texto.trim()) <= 0) {
      return { ok: false, code: "INVALID_INPUT", message: "matricula_avaliado inválida." };
    }
  }
  if (cru.criterion_id !== undefined && cru.criterion_id !== null && !ehUuid(cru.criterion_id)) {
    return { ok: false, code: "INVALID_INPUT", message: "criterion_id inválido." };
  }
  if (cru.escopo !== undefined && cru.escopo !== null && cru.escopo !== "CRITERIO" && cru.escopo !== "FINAL") {
    return { ok: false, code: "INVALID_INPUT", message: "escopo inválido." };
  }

  if (cru.notas !== undefined) {
    if (!Array.isArray(cru.notas)) {
      return { ok: false, code: "INVALID_INPUT", message: "notas deve ser uma lista." };
    }
    for (const item of cru.notas) {
      if (typeof item !== "object" || item === null) {
        return { ok: false, code: "INVALID_INPUT", message: "Item de nota inválido." };
      }
      const nota = item as Record<string, unknown>;
      if (!ehUuid(nota.subcriterion_id)) {
        return { ok: false, code: "INVALID_INPUT", message: "subcriterion_id inválido." };
      }
      const valor = nota.nota;
      if (typeof valor !== "number" || !Number.isInteger(valor) || valor < 1 || valor > 5) {
        return { ok: false, code: "INVALID_INPUT", message: "Nota deve ser inteiro de 1 a 5." };
      }
    }
  }

  return { ok: true, entrada: cru as unknown as EntradaAvaliacao };
}
