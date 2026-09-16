/**
 * F5-11 P4 — contrato TRANSPORTÁVEL do caminho soberano de OBSERVAÇÕES
 * (`evaluation_observations`).
 *
 * Fonte ÚNICA da superfície que o cliente pode pedir, do GATE de cada operação
 * (§8 da F5-11) e da FORMA do corpo aceito (nunca autoridade). É importado pela
 * Edge Function (`supabase/functions/observacoes`, que apenas reexporta este
 * módulo) e pelo adapter de cliente
 * (`src/infrastructure/supabase/observacoes/edgeObservacoes.ts`), como o
 * contrato de metas da F5-10 — nenhuma cópia da lista de operações em nenhum dos
 * lados.
 *
 * Invariantes (F5-11 §8, D3/D4/D6/D7/D8/D10/D16/D21):
 * - o corpo carrega apenas INTENÇÃO: operação, alvo (UUID), versão esperada,
 *   campos de domínio da observação (tipo/texto/comunicado), motivo, escopo de
 *   leitura (com unidade opcional) e `operation_id`;
 * - `organization_id` é intenção REVALIDADA contra membership ativa — nunca
 *   autoridade de tenant;
 * - a AUTORIA (D3) é **exclusivamente derivada** de `auth.uid()` na fronteira:
 *   `author_user_profile_id`/`author_membership_id`/`author_collaborator_id`,
 *   `actorId`, `authorId`, `userId`, `membership*`, `matricula` e `autorNome` do
 *   corpo NUNCA definem autoria — essas chaves não existem em nenhuma operação
 *   deste contrato e enviá-las é `INVALID_INPUT` (D3/D4);
 * - `collaborator_id` e `cycle_id` existem APENAS na criação: são IMUTÁVEIS após
 *   a criação (D4) e o contrato de mutação existente nem os aceita;
 * - `comunicado` só é aceito como valor PRETENDIDO nas operações de definição
 *   (`editar`/`definir_comunicado`); `excluida`, `version`/`status`,
 *   `domainState`, `capability`, `role`, `cargo`/`funcao`, `papel` textual e os
 *   carimbos (`comunicado_em`, `excluida_em`, `*_por_*`) NÃO fazem parte do
 *   contrato: o estado real vem da LINHA soberana e a autorização, do Policy
 *   Engine;
 * - o INSTANTE/DATA da decisão (D21) **não** é transportável em NENHUMA
 *   operação: a fronteira/RPC usa o relógio SOBERANO. Uma `data` escolhida pelo
 *   chamador deixaria o ator escolher o instante em que escopos e relações são
 *   resolvidos (F4-02 resolve "na data") — autoridade declarada pelo cliente,
 *   proibida aqui (mesmo critério de `metas/contrato.ts`, que não tem campo de
 *   data);
 * - `payload_hash` NÃO é parâmetro: as RPCs derivam o hash canônico server-side
 *   (D6/D10, desvio já ratificado nas fases P2–P3);
 * - `expected_version` (D10) é OBRIGATÓRIO em toda mutação de observação
 *   EXISTENTE; a comparação pertence à RPC (a fronteira não compara versão);
 * - `operation_id` é CHAVE DE IDEMPOTÊNCIA (D6), nunca identidade funcional: o
 *   id canônico da observação é `evaluation_observations.id`, atribuído pelo
 *   banco.
 *
 * O que este módulo NÃO faz: lifecycle, comunicação/exibição, exclusão lógica,
 * revogação, trilha de eventos, comparação de versão, transação, autoria ou
 * autorização. Tudo isso pertence às RPCs PostgreSQL `observacao_*` (P2/P3) — a
 * Edge apenas autentica, autoriza e executa.
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
 * Operações contratadas da F5-11 (todas com RPC soberana já existente em P2/P3).
 *
 * `observacao_obter` e `observacao_historico` são operações de LEITURA
 * (`observation.read`): a trilha append-only não amplia alcance (§8 linha 10 —
 * "mesma regra de (3)"). Marcar/desmarcar comunicado é `observation.edit`
 * (`definir_comunicado`, D7) e revogar a exclusão também é `observation.edit`
 * (`revogar`, D8) — NENHUMA capability nova (§8/D7/D8).
 */
export type OperacaoObservacao =
  | "observacao.criar"
  | "observacao.editar"
  | "observacao.definir_comunicado"
  | "observacao.excluir"
  | "observacao.revogar"
  | "observacao.obter"
  | "observacao.listar_por_escopo"
  | "observacao.historico";

/**
 * Gate da operação (§8):
 * - `funcional`: Policy Engine com recurso REAL (`{type:"observation", id: UUID}`
 *   ou o colaborador-alvo da relação) e `domainState` derivado da LINHA SOBERANA
 *   da observação (estado do ciclo e status do colaborador-alvo);
 * - `administrativo`: plano administrativo (F5-04 D19) — a capability efetiva do
 *   ator na organização, sem alvo funcional no engine (a leitura por escopo não
 *   tem UMA observação como alvo autorizável: §8 linha 1, molde F5-10 §11).
 *
 * O tipo é mantido (fonte do campo derivado `funcional`) porque o núcleo da Edge
 * escrita em paralelo consome a MESMA forma do contrato de metas.
 */
export type TipoGate = "funcional" | "administrativo";

/** Capabilities CANÔNICAS de observação (F5-11 §8 — nenhuma capability nova). */
export type CapabilityObservacao =
  | "observation.read"
  | "observation.create"
  | "observation.edit"
  | "observation.delete";

export interface DefinicaoOperacaoObservacao {
  readonly gate: TipoGate;
  /** Capability CANÔNICA exigida (nenhuma capability nova — §8). */
  readonly capability: CapabilityObservacao;
  /**
   * Leitura BOOLEANA do gate, mantida como PONTE DE COMPATIBILIDADE com o núcleo
   * da Edge escrita em paralelo (que consome `funcional: boolean`). É DERIVADA de
   * `gate` — a consistência é exigida por teste
   * (`definicao.funcional === (definicao.gate === "funcional")`) e `gate`
   * permanece a fonte da verdade do contrato.
   */
  readonly funcional: boolean;
}

/**
 * Mapa EXPLÍCITO operação → gate/capability, sem fallback: operação fora deste
 * mapa é recusada antes de qualquer decisão (fail-closed).
 *
 * §8 (matriz normativa): CRIAR→`observation.create`;
 * EDITAR/COMUNICAR/DESCOMUNICAR/REVOGAR→`observation.edit`;
 * EXCLUIR→`observation.delete`; OBTER/HISTORICO/LISTAR_ESCOPO→`observation.read`.
 * Não existe capability de comunicação (§8/D7) e `observation.write` permanece
 * deprecada.
 *
 * Sete operações são FUNCIONAIS: a decisão é do Policy Engine sobre um recurso
 * SOBERANO real (a observação por UUID canônico ou o colaborador-alvo da
 * relação). A ÚNICA exceção é `observacao.listar_por_escopo`: §8 linha 1 declara
 * a leitura de terceiros **administrativa** (leitura sem alvo único
 * autorizável), como `goal.listar_por_escopo` na F5-10 — a capability efetiva é
 * conferida no plano administrativo e o ESCOPO/RELAÇÃO/AUTORIA são aplicados
 * pela RPC soberana `observacao_listar_por_escopo` (P3), que é a fonte única.
 * Exigir alvo funcional aqui seria impossível (a operação não tem
 * `observation_id`) e mataria a listagem.
 */
export const DEFINICAO_POR_OPERACAO: Readonly<
  Record<OperacaoObservacao, DefinicaoOperacaoObservacao>
> = {
  "observacao.criar": {
    gate: "funcional",
    capability: "observation.create",
    funcional: true,
  },
  "observacao.editar": { gate: "funcional", capability: "observation.edit", funcional: true },
  "observacao.definir_comunicado": {
    gate: "funcional",
    capability: "observation.edit",
    funcional: true,
  },
  "observacao.excluir": {
    gate: "funcional",
    capability: "observation.delete",
    funcional: true,
  },
  "observacao.revogar": { gate: "funcional", capability: "observation.edit", funcional: true },
  "observacao.obter": { gate: "funcional", capability: "observation.read", funcional: true },
  // §8 linha 1: a listagem de terceiros não tem UMA observação como alvo
  // autorizável — é decidida no plano ADMINISTRATIVO pela capability efetiva do
  // ator (molde `goal.listar_por_escopo`, F5-10 §11/D22).
  "observacao.listar_por_escopo": {
    gate: "administrativo",
    capability: "observation.read",
    funcional: false,
  },
  "observacao.historico": { gate: "funcional", capability: "observation.read", funcional: true },
};

export const OPERACOES_OBSERVACAO: readonly OperacaoObservacao[] = Object.keys(
  DEFINICAO_POR_OPERACAO
) as readonly OperacaoObservacao[];

export function ehOperacaoObservacao(valor: unknown): valor is OperacaoObservacao {
  return (
    typeof valor === "string" && (OPERACOES_OBSERVACAO as readonly string[]).includes(valor)
  );
}

export function ehOperacaoFuncional(operacao: OperacaoObservacao): boolean {
  return DEFINICAO_POR_OPERACAO[operacao].gate === "funcional";
}

/**
 * Capability exigida no plano ADMINISTRATIVO (D19). Operação que não seja
 * administrativa devolve `null` e o chamador NEGA (sem capability por default).
 * Aqui devolve `observation.read` SOMENTE para `observacao.listar_por_escopo`.
 */
export function capacidadeAdministrativaDaOperacao(
  operacao: OperacaoObservacao
): CapabilityObservacao | null {
  const definicao = DEFINICAO_POR_OPERACAO[operacao];
  return definicao && definicao.gate === "administrativo" ? definicao.capability : null;
}

/**
 * Mapa operação → RPC soberana (P2/P3). Faz parte do contrato congelado (a Edge
 * escrita em paralelo consome o MESMO mapa): nome divergente faz o PostgREST
 * responder "function not found" e quebra a operação inteira. Nenhuma função
 * INTERNA (`f5_11_*`) é operação de cliente.
 */
export const RPC_POR_OPERACAO: Readonly<Record<OperacaoObservacao, string>> = {
  "observacao.criar": "observacao_criar",
  "observacao.editar": "observacao_editar",
  "observacao.definir_comunicado": "observacao_definir_comunicado",
  "observacao.excluir": "observacao_excluir",
  "observacao.revogar": "observacao_revogar",
  "observacao.obter": "observacao_obter",
  "observacao.listar_por_escopo": "observacao_listar_por_escopo",
  "observacao.historico": "observacao_historico",
};

/** Tipo da observação (CHECK de `evaluation_observations.tipo` — §7.2/D4). */
export type TipoObservacaoSoberana = "POSITIVA" | "NEUTRA" | "NEGATIVA";

export const TIPOS_OBSERVACAO: readonly TipoObservacaoSoberana[] = [
  "POSITIVA",
  "NEUTRA",
  "NEGATIVA",
];

/**
 * Escopos de LISTAGEM aceitos (allowlist FECHADA da P3 no gate
 * `f5_11_exigir_autorizacao_observacao`/`observacao_listar_por_escopo`).
 *
 * `SELF` é a leitura das PRÓPRIAS comunicadas (§8 linha 2 — a única operação sem
 * exigência de scope de gestão); `DIRECT_REPORTS`/`DESCENDANTS` são os escopos de
 * gestão. O escopo é INTENÇÃO revalidada server-side contra os scopes efetivos da
 * capability — nunca autoridade.
 */
export type EscopoObservacao = "SELF" | "DIRECT_REPORTS" | "DESCENDANTS";

export const ESCOPOS_OBSERVACAO: readonly EscopoObservacao[] = [
  "SELF",
  "DIRECT_REPORTS",
  "DESCENDANTS",
];

/** Intenção já validada em FORMA (nunca autoridade). */
export interface EntradaObservacao {
  readonly organization_id: string;
  readonly operacao: OperacaoObservacao;
  readonly operation_id: string;
  /** Alvo de observação EXISTENTE (`evaluation_observations.id`) — UUID canônico. */
  readonly observation_id?: string;
  /** Ciclo da CRIAÇÃO (`evaluation_cycles.id`) — imutável depois (D2/D4). */
  readonly cycle_id?: string;
  /** Colaborador-ALVO (`collaborators.id`) — imutável depois (D2/D4). */
  readonly collaborator_id?: string;
  readonly tipo?: TipoObservacaoSoberana;
  readonly texto?: string;
  /** Valor PRETENDIDO do fato comunicado (D7) — a linha soberana é revalidada. */
  readonly comunicado?: boolean;
  /** Escopo de listagem (allowlist fechada — §8 linha 1/2). */
  readonly escopo?: EscopoObservacao;
  /** Unidade organizacional do escopo (opcional; forma UUID quando presente). */
  readonly organizational_unit_id?: string;
  /** Versão otimista da LINHA alvo (D10) — obrigatória em mutação existente. */
  readonly expected_version?: number;
  readonly motivo?: string;
}

export type ValidacaoEntradaObservacao =
  | { readonly ok: true; readonly entrada: EntradaObservacao }
  | { readonly ok: false; readonly code: CodigoPublico; readonly message: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Limite de FORMA de `texto`/`motivo`: o domínio (CHECK da P1, §7.2/D16) aceita
 * `char_length` entre 1 e 2000. A fronteira valida o MESMO intervalo — ser mais
 * restritiva recusaria conteúdo válido e ser mais permissiva deixaria a recusa
 * para o banco.
 */
const LIMITE_TEXTO = 2000;

export function ehUuid(valor: unknown): valor is string {
  return typeof valor === "string" && UUID.test(valor.trim());
}

function ehInteiro(valor: unknown): valor is number {
  return typeof valor === "number" && Number.isInteger(valor);
}

function ehTipo(valor: unknown): valor is TipoObservacaoSoberana {
  return (
    typeof valor === "string" && (TIPOS_OBSERVACAO as readonly string[]).includes(valor)
  );
}

function ehEscopo(valor: unknown): valor is EscopoObservacao {
  return (
    typeof valor === "string" && (ESCOPOS_OBSERVACAO as readonly string[]).includes(valor)
  );
}

function ehBooleano(valor: unknown): valor is boolean {
  return typeof valor === "boolean";
}

function textoObrigatorio(valor: unknown): string | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  if (limpo.length === 0 || limpo.length > LIMITE_TEXTO) return null;
  return limpo;
}

/**
 * Chaves aceitas por operação. Allowlist ESTRITA: qualquer chave fora dela —
 * `actor_id`, `actor_user_profile_id`, `author_id`, `author_collaborator_id`,
 * `author_membership_id`, `membership_id`, `matricula`, `autorNome`, `status`,
 * `aprovado`, `excluida`, `excluida_em`, `excluida_por_*`, `motivo_exclusao`,
 * `comunicado_em`, `comunicado_por_*`, `version`, `domainState`, `capability`,
 * `scope`, `data`, `role`, `cargo`, `funcao`, `papel`, `payload_hash`,
 * `tenant_id` etc. — é `INVALID_INPUT`. Forma nunca é autoridade;
 * `cycle_id`/`collaborator_id` só existem na CRIAÇÃO (D4 — a mutação de linha
 * existente não os aceita) e o INSTANTE da decisão (D21) não é transportável em
 * nenhuma operação.
 */
const CHAVES_COMUNS = ["organization_id", "operacao", "operation_id"] as const;

export const CHAVES_POR_OPERACAO: Readonly<
  Record<OperacaoObservacao, readonly string[]>
> = {
  "observacao.criar": [
    ...CHAVES_COMUNS,
    "cycle_id",
    "collaborator_id",
    "tipo",
    "texto",
  ],
  // §7.5/D4: a edição recebe a DEFINIÇÃO COMPLETA (tipo/texto/comunicado) e não
  // faz merge parcial; alvo/ciclo/colaborador/autoria NÃO são aceitos.
  "observacao.editar": [
    ...CHAVES_COMUNS,
    "observation_id",
    "tipo",
    "texto",
    "comunicado",
    "expected_version",
  ],
  "observacao.definir_comunicado": [
    ...CHAVES_COMUNS,
    "observation_id",
    "comunicado",
    "expected_version",
  ],
  // D8/D16: exclusão SEMPRE lógica e com MOTIVO obrigatório.
  "observacao.excluir": [...CHAVES_COMUNS, "observation_id", "motivo", "expected_version"],
  // D8: revogar a exclusão é operação DISTINTA, com motivo obrigatório.
  "observacao.revogar": [...CHAVES_COMUNS, "observation_id", "motivo", "expected_version"],
  "observacao.obter": [...CHAVES_COMUNS, "observation_id"],
  // Listagem por ESCOPO: o escopo é obrigatório (allowlist fechada da P3) e a
  // unidade é intenção OPCIONAL do recorte — nunca um alvo de observação. A DATA
  // NÃO viaja: o instante da decisão é soberano (D21).
  "observacao.listar_por_escopo": [
    ...CHAVES_COMUNS,
    "escopo",
    "organizational_unit_id",
  ],
  "observacao.historico": [...CHAVES_COMUNS, "observation_id"],
};

/** Operações cujo alvo é uma observação EXISTENTE (`observation_id` obrigatório). */
const OPERACOES_COM_OBSERVACAO: readonly OperacaoObservacao[] = [
  "observacao.editar",
  "observacao.definir_comunicado",
  "observacao.excluir",
  "observacao.revogar",
  "observacao.obter",
  "observacao.historico",
];

/**
 * Mutações de LINHA EXISTENTE: exigem `expected_version` (D10). `criar` não tem
 * versão prévia e as leituras (`obter`/`listar_por_escopo`/`historico`) não
 * mutam nada.
 */
const OPERACOES_COM_VERSAO: readonly OperacaoObservacao[] = [
  "observacao.editar",
  "observacao.definir_comunicado",
  "observacao.excluir",
  "observacao.revogar",
];

function invalido(message: string): ValidacaoEntradaObservacao {
  return { ok: false, code: "INVALID_INPUT", message };
}

function exigirUuid(entrada: Record<string, unknown>, chave: string): string | null {
  return ehUuid(entrada[chave]) ? (entrada[chave] as string).trim() : null;
}

/**
 * Valida a FORMA da intenção (nunca a autoridade). Fail-closed: qualquer campo
 * desconhecido, identidade/autoria/instante no corpo, UUID malformado, texto
 * vazio ou acima do limite, booleano ausente, escopo fora da allowlist ou versão
 * ausente ⇒ `INVALID_INPUT`.
 */
export function validarEntradaObservacao(corpo: unknown): ValidacaoEntradaObservacao {
  if (typeof corpo !== "object" || corpo === null || Array.isArray(corpo)) {
    return invalido("Corpo da requisição inválido.");
  }
  const bruto = corpo as Record<string, unknown>;

  if (!ehOperacaoObservacao(bruto.operacao)) {
    return invalido("Operação de observação não suportada.");
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

  // Alvo de observação EXISTENTE: SEMPRE UUID canônico
  // (`evaluation_observations.id`).
  if (OPERACOES_COM_OBSERVACAO.includes(operacao)) {
    const observationId = exigirUuid(bruto, "observation_id");
    if (!observationId) return invalido("observation_id inválido.");
    entrada.observation_id = observationId;
  }

  // D10: versão otimista obrigatória em toda mutação de linha EXISTENTE.
  if (OPERACOES_COM_VERSAO.includes(operacao)) {
    const versao = bruto.expected_version;
    if (!ehInteiro(versao) || versao < 0) return invalido("expected_version inválido.");
    entrada.expected_version = versao;
  }

  switch (operacao) {
    case "observacao.criar": {
      // D2: o ciclo é OBRIGATÓRIO e soberano desde a criação; o colaborador-alvo
      // é a relação do ciclo (D11 — SELF não cria sobre si, decidido no engine).
      const cycleId = exigirUuid(bruto, "cycle_id");
      if (!cycleId) return invalido("cycle_id inválido.");
      const collaboratorId = exigirUuid(bruto, "collaborator_id");
      if (!collaboratorId) return invalido("collaborator_id inválido.");
      const tipo = bruto.tipo;
      if (!ehTipo(tipo)) return invalido("tipo inválido.");
      const texto = textoObrigatorio(bruto.texto);
      if (!texto) return invalido("texto obrigatório.");
      entrada.cycle_id = cycleId;
      entrada.collaborator_id = collaboratorId;
      entrada.tipo = tipo;
      entrada.texto = texto;
      break;
    }
    case "observacao.editar": {
      // A RPC recebe a DEFINIÇÃO completa (§7.5): a fronteira exige os três
      // campos mutáveis e não faz merge de domínio.
      const tipo = bruto.tipo;
      if (!ehTipo(tipo)) return invalido("tipo inválido.");
      const texto = textoObrigatorio(bruto.texto);
      if (!texto) return invalido("texto obrigatório.");
      const comunicado = bruto.comunicado;
      if (!ehBooleano(comunicado)) return invalido("comunicado inválido.");
      entrada.tipo = tipo;
      entrada.texto = texto;
      entrada.comunicado = comunicado;
      break;
    }
    case "observacao.definir_comunicado": {
      const comunicado = bruto.comunicado;
      if (!ehBooleano(comunicado)) return invalido("comunicado inválido.");
      entrada.comunicado = comunicado;
      break;
    }
    case "observacao.excluir":
    case "observacao.revogar": {
      // D8/D16: sem motivo não há exclusão nem revogação.
      const motivo = textoObrigatorio(bruto.motivo);
      if (!motivo) return invalido("motivo obrigatório.");
      entrada.motivo = motivo;
      break;
    }
    case "observacao.obter":
    case "observacao.historico":
      // Leitura de UMA observação: apenas o alvo já validado acima.
      break;
    case "observacao.listar_por_escopo": {
      // Allowlist FECHADA da P3: escopo fora dela é `INVALID_INPUT` antes de
      // qualquer decisão.
      const escopo = bruto.escopo;
      if (!ehEscopo(escopo)) return invalido("escopo inválido.");
      entrada.escopo = escopo;
      // Unidade é intenção OPCIONAL do recorte: presente, precisa ter FORMA
      // válida; ausente, o servidor resolve. O INSTANTE da decisão é soberano e
      // NÃO é aceito do chamador (D21).
      if (bruto.organizational_unit_id !== undefined) {
        const unidade = exigirUuid(bruto, "organizational_unit_id");
        if (!unidade) return invalido("organizational_unit_id inválido.");
        entrada.organizational_unit_id = unidade;
      }
      break;
    }
  }

  return { ok: true, entrada: entrada as unknown as EntradaObservacao };
}
