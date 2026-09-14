/**
 * F5-10 P5 (Issue #218), Bloco 1/S2 — contrato TRANSPORTÁVEL do caminho soberano
 * de METAS (`goal`).
 *
 * Fonte ÚNICA da superfície que o cliente pode pedir, do GATE de cada operação
 * (§10/D19/D21) e da FORMA do corpo aceito (nunca autoridade). É importado pela
 * Edge Function (`supabase/functions/metas`, escrita em paralelo — que apenas
 * reexporta este módulo) e pelo adapter de cliente
 * (`src/infrastructure/supabase/metas/edgeMetas.ts`), como o contrato de ciclos
 * da F5-09 — nenhuma cópia da lista de operações em nenhum dos lados.
 *
 * Invariantes (D6/D7/D8/D9/D11/D12/D22/§13):
 * - o corpo carrega apenas INTENÇÃO: operação, alvo (UUID), versão esperada,
 *   campos de domínio da meta, motivo e `operation_id`;
 * - `organization_id` é intenção REVALIDADA contra membership ativa — nunca
 *   autoridade de tenant;
 * - `actorId`/`authorId`/`userId`/`membership*` do corpo NUNCA definem autoria
 *   (o ator é `auth.uid` verificado na fronteira); enviá-los é `INVALID_INPUT`;
 * - `status`, `aprovado`, `domainState`, `excluida`, `version`, `capability`,
 *   `role`, `cargo`, `funcao` NÃO fazem parte do contrato: o estado da meta vem
 *   da LINHA SOBERANA e a autorização, do Policy Engine (a aprovação é FATO
 *   derivado de `evaluation_goal_approvals`, nunca um campo do cliente — D3);
 * - `payload_hash` NÃO é parâmetro: as RPCs derivam o hash canônico server-side
 *   (D11, desvio já ratificado nas fases P2–P4);
 * - `expected_version` (D12) é OBRIGATÓRIO em toda mutação de meta/limite
 *   EXISTENTE; a comparação pertence à RPC (a fronteira não compara versão);
 * - `operation_id` é CHAVE DE IDEMPOTÊNCIA (D11), nunca identidade funcional:
 *   o id canônico da meta é `evaluation_goals.id`, atribuído pelo banco.
 *
 * O que este módulo NÃO faz: lifecycle (status, revisão de fechamento), quota,
 * aprovação relacional congelada, invalidação, transação, comparação de versão
 * ou autoria. Tudo isso pertence às RPCs PostgreSQL (§13) — a Edge apenas
 * autentica, autoriza e executa.
 */

/** Códigos públicos (F0-05) — a mensagem crua do banco nunca chega ao cliente. */
export type CodigoPublico =
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "INVALID_INPUT"
  | "INTERNAL"
  | "NOT_AUTHORIZED"
  | "METHOD_NOT_ALLOWED";

/**
 * Operações contratadas da F5-10 (todas com RPC soberana já existente em P2/P3/P4).
 *
 * `meta_invalidar_aprovacoes` NÃO é operação de cliente: o desenho a declara
 * "interna às mutações" (§13/§9.4) — a invalidação é disparada DENTRO da RPC da
 * mutação material e não possui superfície transportável.
 */
export type OperacaoMeta =
  | "goal.criar"
  | "goal.editar"
  | "goal.atualizar_progresso"
  | "goal.finalizar"
  | "goal.revisar_finalizacao"
  | "goal.excluir"
  | "goal.aprovar"
  | "goal.definir_limites_do_ciclo"
  | "goal.listar_por_escopo";

/**
 * Gate da operação (§10/D19):
 * - `funcional`: Policy Engine com recurso REAL (`{type:"goal", id: UUID}` — D8)
 *   e `domainState` derivado da linha soberana da meta e do status do ciclo;
 * - `administrativo`: plano administrativo (F5-04 D19) — a capability efetiva do
 *   ator na organização, sem alvo no engine (a leitura por escopo não tem uma
 *   meta única como alvo autorizável: §11/D22).
 */
export type TipoGate = "funcional" | "administrativo";

/** Capabilities CANÔNICAS de metas (D6 — nenhuma capability nova). */
export type CapabilityMeta = "goal.read" | "goal.write" | "goal.approve" | "cycle.manage";

export interface DefinicaoOperacaoMeta {
  readonly gate: TipoGate;
  /** Capability CANÔNICA exigida (nenhuma capability nova — D6). */
  readonly capability: CapabilityMeta;
  /**
   * Leitura BOOLEANA do gate, mantida como PONTE DE COMPATIBILIDADE com o núcleo
   * da Edge escrito em paralelo (que consome `funcional: boolean`). É DERIVADA de
   * `gate` — a consistência é exigida por teste
   * (`definicao.funcional === (definicao.gate === "funcional")`) e `gate`
   * permanece a fonte da verdade do contrato congelado.
   */
  readonly funcional: boolean;
}

/**
 * Mapa EXPLÍCITO operação → gate/capability, sem fallback: operação fora deste
 * mapa é recusada antes de qualquer decisão (fail-closed).
 *
 * D7/D9: `goal.approve` NÃO implica `goal.write` — aprovar não autoriza editar,
 * progredir, finalizar, re-finalizar nem excluir.
 * D21: a quota do ciclo é `cycle.manage` (a mesma capability já usada pelos
 * ciclos), no plano funcional com alvo de CICLO real.
 */
export const DEFINICAO_POR_OPERACAO: Readonly<
  Record<OperacaoMeta, DefinicaoOperacaoMeta>
> = {
  "goal.criar": { gate: "funcional", capability: "goal.write", funcional: true },
  "goal.editar": { gate: "funcional", capability: "goal.write", funcional: true },
  "goal.atualizar_progresso": { gate: "funcional", capability: "goal.write", funcional: true },
  "goal.finalizar": { gate: "funcional", capability: "goal.write", funcional: true },
  "goal.revisar_finalizacao": { gate: "funcional", capability: "goal.write", funcional: true },
  "goal.excluir": { gate: "funcional", capability: "goal.write", funcional: true },
  "goal.aprovar": { gate: "funcional", capability: "goal.approve", funcional: true },
  "goal.definir_limites_do_ciclo": {
    gate: "funcional",
    capability: "cycle.manage",
    funcional: true,
  },
  // §11/D22: a leitura de terceiros não tem UMA meta como alvo autorizável e o
  // probe de ciclo NEGA `goal.read` (estadoDominioCiclo) — logo ela é decidida no
  // plano ADMINISTRATIVO pela capability efetiva do ator na organização.
  "goal.listar_por_escopo": {
    gate: "administrativo",
    capability: "goal.read",
    funcional: false,
  },
};

export const OPERACOES_META: readonly OperacaoMeta[] = Object.keys(
  DEFINICAO_POR_OPERACAO
) as readonly OperacaoMeta[];

export function ehOperacaoMeta(valor: unknown): valor is OperacaoMeta {
  return typeof valor === "string" && (OPERACOES_META as readonly string[]).includes(valor);
}

export function ehOperacaoFuncional(operacao: OperacaoMeta): boolean {
  return DEFINICAO_POR_OPERACAO[operacao].gate === "funcional";
}

/**
 * Capability exigida no plano ADMINISTRATIVO (D19). Operação que não seja
 * administrativa devolve `null` e o chamador NEGA (sem capability por default).
 */
export function capacidadeAdministrativaDaOperacao(operacao: OperacaoMeta): CapabilityMeta | null {
  const definicao = DEFINICAO_POR_OPERACAO[operacao];
  return definicao && definicao.gate === "administrativo" ? definicao.capability : null;
}

/**
 * Mapa operação → RPC soberana. Faz parte do contrato congelado (a Edge escrita
 * em paralelo consome o MESMO mapa): nome divergente faz o PostgREST responder
 * "function not found" e quebra a operação inteira.
 */
export const RPC_POR_OPERACAO: Readonly<Record<OperacaoMeta, string>> = {
  "goal.criar": "meta_criar",
  "goal.editar": "meta_editar",
  "goal.atualizar_progresso": "meta_atualizar_progresso",
  "goal.finalizar": "meta_finalizar",
  "goal.revisar_finalizacao": "meta_revisar_finalizacao",
  "goal.excluir": "meta_excluir",
  "goal.aprovar": "meta_aprovar",
  "goal.definir_limites_do_ciclo": "meta_definir_limites_do_ciclo",
  "goal.listar_por_escopo": "meta_listar_por_escopo",
};

/** Tipo de meta (CHECK de `evaluation_goals.tipo` — D4/§6.2). */
export type TipoMetaSoberana = "NEGOCIO_PROJETO" | "INDIVIDUAL";

/** Papel de aprovação (CHECK de `evaluation_goal_approvals.papel` — §9). */
export type PapelAprovacaoMeta = "GERENTE" | "COORDENADOR";

export const TIPOS_META: readonly TipoMetaSoberana[] = ["NEGOCIO_PROJETO", "INDIVIDUAL"];
export const PAPEIS_APROVACAO_META: readonly PapelAprovacaoMeta[] = ["GERENTE", "COORDENADOR"];

/** Intenção já validada em FORMA (nunca autoridade). */
export interface EntradaMeta {
  readonly organization_id: string;
  readonly operacao: OperacaoMeta;
  readonly operation_id: string;
  /** Alvo de meta EXISTENTE (`evaluation_goals.id`) — UUID canônico. */
  readonly goal_id?: string;
  /** Alvo de ciclo (`evaluation_cycles.id`) — criação, limites e leitura. */
  readonly cycle_id?: string;
  /** Dono da meta (`collaborators.id`) — revalidado contra SELF na fronteira. */
  readonly collaborator_id?: string;
  readonly tipo?: TipoMetaSoberana;
  readonly descricao?: string;
  readonly kpi?: string;
  readonly valor_alvo?: string;
  readonly resultado_atual?: string;
  readonly progresso_percentual?: number;
  readonly resultado_final?: string;
  readonly atingida?: boolean;
  readonly papel?: PapelAprovacaoMeta;
  readonly quantidade?: number;
  /** Versão otimista da LINHA alvo (D12) — obrigatória em mutação existente. */
  readonly expected_version?: number;
  readonly motivo?: string;
}

export type ValidacaoEntradaMeta =
  | { readonly ok: true; readonly entrada: EntradaMeta }
  | { readonly ok: false; readonly code: CodigoPublico; readonly message: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LIMITE_TEXTO = 500;

export function ehUuid(valor: unknown): valor is string {
  return typeof valor === "string" && UUID.test(valor.trim());
}

function ehInteiro(valor: unknown): valor is number {
  return typeof valor === "number" && Number.isInteger(valor);
}

function ehTipo(valor: unknown): valor is TipoMetaSoberana {
  return typeof valor === "string" && (TIPOS_META as readonly string[]).includes(valor);
}

function ehPapel(valor: unknown): valor is PapelAprovacaoMeta {
  return typeof valor === "string" && (PAPEIS_APROVACAO_META as readonly string[]).includes(valor);
}

function textoObrigatorio(valor: unknown): string | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  if (limpo.length === 0 || limpo.length > LIMITE_TEXTO) return null;
  return limpo;
}

/**
 * Chaves aceitas por operação. Allowlist ESTRITA: qualquer chave fora dela —
 * `actor_id`, `actor_user_profile_id`, `membership_id`, `status`, `aprovado`,
 * `domainState`, `excluida`, `version`, `capability`, `role`, `cargo`, `funcao`,
 * `payload_hash` etc. — é `INVALID_INPUT`. Forma nunca é autoridade.
 */
const CHAVES_COMUNS = ["organization_id", "operacao", "operation_id"] as const;

export const CHAVES_POR_OPERACAO: Readonly<Record<OperacaoMeta, readonly string[]>> = {
  "goal.criar": [
    ...CHAVES_COMUNS,
    "cycle_id",
    "collaborator_id",
    "tipo",
    "descricao",
    "kpi",
    "valor_alvo",
  ],
  "goal.editar": [
    ...CHAVES_COMUNS,
    "goal_id",
    "descricao",
    "kpi",
    "valor_alvo",
    "expected_version",
  ],
  "goal.atualizar_progresso": [
    ...CHAVES_COMUNS,
    "goal_id",
    "resultado_atual",
    "progresso_percentual",
    "expected_version",
  ],
  "goal.finalizar": [
    ...CHAVES_COMUNS,
    "goal_id",
    "resultado_final",
    "atingida",
    "expected_version",
  ],
  "goal.revisar_finalizacao": [
    ...CHAVES_COMUNS,
    "goal_id",
    "resultado_final",
    "atingida",
    "motivo",
    "expected_version",
  ],
  "goal.excluir": [...CHAVES_COMUNS, "goal_id", "motivo", "expected_version"],
  "goal.aprovar": [...CHAVES_COMUNS, "goal_id", "papel", "motivo", "expected_version"],
  "goal.definir_limites_do_ciclo": [
    ...CHAVES_COMUNS,
    "cycle_id",
    "tipo",
    "quantidade",
    "motivo",
    "expected_version",
  ],
  "goal.listar_por_escopo": [...CHAVES_COMUNS, "cycle_id"],
};

/** Operações cujo alvo é uma meta EXISTENTE (`goal_id` obrigatório). */
const OPERACOES_COM_META: readonly OperacaoMeta[] = [
  "goal.editar",
  "goal.atualizar_progresso",
  "goal.finalizar",
  "goal.revisar_finalizacao",
  "goal.excluir",
  "goal.aprovar",
];

/** Operações cujo alvo é o CICLO (`cycle_id` obrigatório). */
const OPERACOES_COM_CICLO: readonly OperacaoMeta[] = [
  "goal.criar",
  "goal.definir_limites_do_ciclo",
  "goal.listar_por_escopo",
];

/**
 * Mutações de LINHA EXISTENTE: exigem `expected_version` (D12). `goal.criar` não
 * tem versão prévia e `goal.listar_por_escopo` é leitura (sem versão).
 */
const OPERACOES_COM_VERSAO: readonly OperacaoMeta[] = [
  ...OPERACOES_COM_META,
  "goal.definir_limites_do_ciclo",
];

function invalido(message: string): ValidacaoEntradaMeta {
  return { ok: false, code: "INVALID_INPUT", message };
}

function exigirUuid(entrada: Record<string, unknown>, chave: string): string | null {
  return ehUuid(entrada[chave]) ? (entrada[chave] as string).trim() : null;
}

/**
 * Texto OPCIONAL (ex.: `motivo` de revisão/aprovação, que a RPC aceita nulo):
 * ausente é aceito; presente precisa ser texto não vazio com até 500 caracteres.
 */
function textoOpcional(valor: unknown): { readonly ok: boolean; readonly valor?: string } {
  if (valor === undefined || valor === null) return { ok: true };
  const limpo = textoObrigatorio(valor);
  return limpo === null ? { ok: false } : { ok: true, valor: limpo };
}

/**
 * Valida a FORMA da intenção (nunca a autoridade). Fail-closed: qualquer campo
 * desconhecido, identidade no corpo, UUID malformado, texto vazio, booleano
 * ausente, inteiro fora da faixa, versão ausente ⇒ `INVALID_INPUT`.
 */
export function validarEntradaMeta(corpo: unknown): ValidacaoEntradaMeta {
  if (typeof corpo !== "object" || corpo === null || Array.isArray(corpo)) {
    return invalido("Corpo da requisição inválido.");
  }
  const bruto = corpo as Record<string, unknown>;

  if (!ehOperacaoMeta(bruto.operacao)) {
    return invalido("Operação de meta não suportada.");
  }
  const operacao = bruto.operacao;

  const permitidas = CHAVES_POR_OPERACAO[operacao];
  const desconhecidas = Object.keys(bruto).filter((chave) => !permitidas.includes(chave));
  if (desconhecidas.length > 0) {
    return invalido(`Campo não aceito nesta operação: ${desconhecidas.sort().join(", ")}.`);
  }

  const organizationId = exigirUuid(bruto, "organization_id");
  if (!organizationId) return invalido("organization_id inválido.");
  const operationId = exigirUuid(bruto, "operation_id");
  if (!operationId) return invalido("operation_id inválido.");

  const entrada: Record<string, unknown> = {
    organization_id: organizationId,
    operacao: operacao,
    operation_id: operationId,
  };

  // Alvo de meta EXISTENTE: SEMPRE UUID canônico (`evaluation_goals.id`).
  if (OPERACOES_COM_META.includes(operacao)) {
    const goalId = exigirUuid(bruto, "goal_id");
    if (!goalId) return invalido("goal_id inválido.");
    entrada.goal_id = goalId;
  }

  // Alvo de CICLO: SEMPRE UUID canônico (`evaluation_cycles.id`).
  if (OPERACOES_COM_CICLO.includes(operacao)) {
    const cycleId = exigirUuid(bruto, "cycle_id");
    if (!cycleId) return invalido("cycle_id inválido.");
    entrada.cycle_id = cycleId;
  }

  // D12: versão otimista obrigatória em toda mutação de linha EXISTENTE.
  if (OPERACOES_COM_VERSAO.includes(operacao)) {
    const versao = bruto.expected_version;
    if (!ehInteiro(versao) || versao < 0) return invalido("expected_version inválido.");
    entrada.expected_version = versao;
  }

  switch (operacao) {
    case "goal.criar": {
      const collaboratorId = exigirUuid(bruto, "collaborator_id");
      if (!collaboratorId) return invalido("collaborator_id inválido.");
      const tipo = bruto.tipo;
      if (!ehTipo(tipo)) return invalido("tipo inválido.");
      const descricao = textoObrigatorio(bruto.descricao);
      if (!descricao) return invalido("descricao obrigatória.");
      const kpi = textoObrigatorio(bruto.kpi);
      if (!kpi) return invalido("kpi obrigatório.");
      const valorAlvo = textoObrigatorio(bruto.valor_alvo);
      if (!valorAlvo) return invalido("valor_alvo obrigatório.");
      entrada.collaborator_id = collaboratorId;
      entrada.tipo = tipo;
      entrada.descricao = descricao;
      entrada.kpi = kpi;
      entrada.valor_alvo = valorAlvo;
      break;
    }
    case "goal.editar": {
      // A RPC recebe a DEFINIÇÃO completa (não há edição parcial): a fronteira
      // exige os três campos e não faz merge de domínio.
      const descricao = textoObrigatorio(bruto.descricao);
      if (!descricao) return invalido("descricao obrigatória.");
      const kpi = textoObrigatorio(bruto.kpi);
      if (!kpi) return invalido("kpi obrigatório.");
      const valorAlvo = textoObrigatorio(bruto.valor_alvo);
      if (!valorAlvo) return invalido("valor_alvo obrigatório.");
      entrada.descricao = descricao;
      entrada.kpi = kpi;
      entrada.valor_alvo = valorAlvo;
      break;
    }
    case "goal.atualizar_progresso": {
      const resultadoAtual = textoObrigatorio(bruto.resultado_atual);
      if (!resultadoAtual) return invalido("resultado_atual obrigatório.");
      const progresso = bruto.progresso_percentual;
      if (!ehInteiro(progresso) || progresso < 0 || progresso > 100) {
        return invalido("progresso_percentual inválido.");
      }
      entrada.resultado_atual = resultadoAtual;
      entrada.progresso_percentual = progresso;
      break;
    }
    case "goal.finalizar": {
      const resultadoFinal = textoObrigatorio(bruto.resultado_final);
      if (!resultadoFinal) return invalido("resultado_final obrigatório.");
      const atingida = bruto.atingida;
      if (typeof atingida !== "boolean") return invalido("atingida inválida.");
      entrada.resultado_final = resultadoFinal;
      entrada.atingida = atingida;
      break;
    }
    case "goal.revisar_finalizacao": {
      const resultadoFinal = textoObrigatorio(bruto.resultado_final);
      if (!resultadoFinal) return invalido("resultado_final obrigatório.");
      const atingida = bruto.atingida;
      if (typeof atingida !== "boolean") return invalido("atingida inválida.");
      const motivo = textoOpcional(bruto.motivo);
      if (!motivo.ok) return invalido("motivo inválido.");
      entrada.resultado_final = resultadoFinal;
      entrada.atingida = atingida;
      if (motivo.valor !== undefined) entrada.motivo = motivo.valor;
      break;
    }
    case "goal.excluir": {
      const motivo = textoObrigatorio(bruto.motivo);
      if (!motivo) return invalido("motivo obrigatório.");
      entrada.motivo = motivo;
      break;
    }
    case "goal.aprovar": {
      const papel = bruto.papel;
      if (!ehPapel(papel)) return invalido("papel inválido.");
      const motivo = textoOpcional(bruto.motivo);
      if (!motivo.ok) return invalido("motivo inválido.");
      entrada.papel = papel;
      if (motivo.valor !== undefined) entrada.motivo = motivo.valor;
      break;
    }
    case "goal.definir_limites_do_ciclo": {
      const tipo = bruto.tipo;
      if (!ehTipo(tipo)) return invalido("tipo inválido.");
      const quantidade = bruto.quantidade;
      // Forma apenas: o teto do domínio (0..3, §6.2) é INVARIANTE server-side
      // (D20) — a fronteira não replica a regra de negócio.
      if (!ehInteiro(quantidade) || quantidade < 0) return invalido("quantidade inválida.");
      const motivo = textoObrigatorio(bruto.motivo);
      if (!motivo) return invalido("motivo obrigatório.");
      entrada.tipo = tipo;
      entrada.quantidade = quantidade;
      entrada.motivo = motivo;
      break;
    }
    case "goal.listar_por_escopo":
      // Leitura por escopo: apenas o alvo de CICLO já validado acima.
      break;
  }

  return { ok: true, entrada: entrada as unknown as EntradaMeta };
}
