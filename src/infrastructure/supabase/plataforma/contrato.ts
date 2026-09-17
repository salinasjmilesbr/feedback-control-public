/**
 * F6-A03 (Issue #266) — CONTRATO TRANSPORTÁVEL ÚNICO da superfície de
 * PLATAFORMA (`plataforma.*`).
 *
 * Fonte única de verdade compartilhada entre a Edge `provisionar-organizacao` e
 * o cliente (`edgePlataforma.ts`): operações, allowlist ESTRITA de chaves por
 * operação, códigos públicos (taxonomia F0-05) e validação de FORMA.
 *
 * Doutrina (contrato §6.1):
 * - a FORMA nunca é autoridade: o corpo carrega apenas INTENÇÃO (nome da
 *   organização, identificação do primeiro Admin, `operation_id`) e é validado
 *   por ALLOWLIST ESTRITA — chave fora dela ⇒ `INVALID_INPUT`;
 * - NUNCA são transportáveis `actor_*`, `organization_id`, `access_role_id`,
 *   `capability`, `scope`, `status`, `version`, `origin` ou `payload_hash`: a
 *   identidade do operador vem do JWT verificado server-side e o hash canônico é
 *   derivado server-side;
 * - nada aqui decide autorização, tenant ou papel: a decisão é sempre da Edge +
 *   RPC soberana.
 *
 * D21 — escopo fechado: as operações são EXATAMENTE duas (provisionar uma
 * organização e auto-checar a autoridade de plataforma). Não há listagem de
 * tenants, gestão de operadores, lifecycle ou gestão de roles.
 */

/** Provisiona organização + primeiro Admin do tenant (bootstrap do GREENFIELD). */
export const OPERACAO_PROVISIONAR_ORGANIZACAO = "plataforma.provisionar_organizacao";

/** Self-check de UX: "sou operador de plataforma?" — nunca autorização (D20). */
export const OPERACAO_OPERADOR_ATUAL = "plataforma.operador_atual";

export type OperacaoPlataforma =
  | typeof OPERACAO_PROVISIONAR_ORGANIZACAO
  | typeof OPERACAO_OPERADOR_ATUAL;

export const OPERACOES_PLATAFORMA: readonly OperacaoPlataforma[] = [
  OPERACAO_PROVISIONAR_ORGANIZACAO,
  OPERACAO_OPERADOR_ATUAL,
];

export function eOperacaoPlataforma(valor: unknown): valor is OperacaoPlataforma {
  return typeof valor === "string" && (OPERACOES_PLATAFORMA as readonly string[]).includes(valor);
}

/**
 * Allowlist ESTRITA de chaves por operação. Sem default permissivo: operação
 * desconhecida não tem allowlist e é recusada antes de qualquer efeito.
 */
export const CHAVES_POR_OPERACAO: Readonly<Record<OperacaoPlataforma, readonly string[]>> = {
  [OPERACAO_PROVISIONAR_ORGANIZACAO]: [
    "operacao",
    "operation_id",
    "organization_name",
    "founder_user_id",
    "founder_email",
    "founder_full_name",
    "founder_matricula",
  ],
  [OPERACAO_OPERADOR_ATUAL]: ["operacao"],
};

/**
 * Códigos públicos FECHADOS (§6.3). A fronteira só devolve um destes; código
 * desconhecido vindo do servidor NÃO é repassado (fail-closed).
 */
export type CodigoPublico =
  | "NOT_AUTHORIZED"
  | "INVALID_INPUT"
  | "INVALID_NAME"
  | "INVALID_FOUNDER"
  | "USER_EXISTS"
  | "OPERATION_ALREADY_APPLIED"
  | "INTERNAL"
  | "METHOD_NOT_ALLOWED";

export const CODIGOS_PUBLICOS: readonly CodigoPublico[] = [
  "NOT_AUTHORIZED",
  "INVALID_INPUT",
  "INVALID_NAME",
  "INVALID_FOUNDER",
  "USER_EXISTS",
  "OPERATION_ALREADY_APPLIED",
  "INTERNAL",
  "METHOD_NOT_ALLOWED",
];

export function eCodigoPublico(valor: unknown): valor is CodigoPublico {
  return typeof valor === "string" && (CODIGOS_PUBLICOS as readonly string[]).includes(valor);
}

/** UUID canônico (mesma forma aceita pelo Postgres `uuid`). */
export const UUID_CANONICO =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** E-mail mínimo (mesma forma adotada pelo convite administrativo da F2-06). */
export const EMAIL_MINIMO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Entrada normalizada da operação de provisionamento. */
export interface EntradaProvisaoPlataforma {
  readonly operacao: typeof OPERACAO_PROVISIONAR_ORGANIZACAO;
  readonly operationId: string;
  readonly organizationName: string;
  /**
   * F6-A11 (D22/D23): nome HUMANO do primeiro Admin — dado a criar, como o nome
   * da organização. É a fonte canônica de `collaborators.full_name` do founder
   * (nunca derivado do e-mail, nunca duplicado em `user_profiles`).
   */
  readonly founderFullName: string;
  /**
   * F6-A11 (D23/D28): matrícula declarada do primeiro Admin na organização nova
   * (`collaborator_identifiers.business_code`) — código de negócio DECLARADO,
   * nunca inventado pelo servidor.
   */
  readonly founderMatricula: string;
  /**
   * Identificação do primeiro Admin — EXATAMENTE uma das duas formas:
   * `founderUserId` (identidade já existente, caminho de API) OU `founderEmail`
   * (identidade nova, criada por convite). A UI mínima expõe "eu mesmo" como
   * `founderUserId` do próprio operador e "outra pessoa" como `founderEmail`.
   */
  readonly founderUserId?: string;
  readonly founderEmail?: string;
}

export type ResultadoValidacaoPlataforma =
  | { readonly ok: true; readonly entrada: EntradaProvisaoPlataforma }
  | { readonly ok: false; readonly codigo: CodigoPublico; readonly message: string };

function corpoEhObjeto(corpo: unknown): corpo is Record<string, unknown> {
  return typeof corpo === "object" && corpo !== null && !Array.isArray(corpo);
}

/**
 * Valida a FORMA da operação de provisionamento por allowlist ESTRITA.
 * Fail-closed: qualquer chave fora da allowlist da operação, campo obrigatório
 * ausente, UUID/e-mail inválido ou XOR de founder violado ⇒ `INVALID_INPUT`/
 * `INVALID_NAME`.
 */
export function validarEntradaProvisaoPlataforma(corpo: unknown): ResultadoValidacaoPlataforma {
  if (!corpoEhObjeto(corpo)) {
    return { ok: false, codigo: "INVALID_INPUT", message: "Corpo da requisição inválido." };
  }

  const permitidas = CHAVES_POR_OPERACAO[OPERACAO_PROVISIONAR_ORGANIZACAO];
  for (const chave of Object.keys(corpo)) {
    if (!permitidas.includes(chave)) {
      return {
        ok: false,
        codigo: "INVALID_INPUT",
        message: `Chave não aceita nesta operação: ${chave}.`,
      };
    }
  }

  const operationId = typeof corpo.operation_id === "string" ? corpo.operation_id.trim() : "";
  if (!UUID_CANONICO.test(operationId)) {
    return { ok: false, codigo: "INVALID_INPUT", message: "operation_id inválido." };
  }

  const organizationName =
    typeof corpo.organization_name === "string" ? corpo.organization_name.trim() : "";
  if (organizationName === "") {
    return { ok: false, codigo: "INVALID_NAME", message: "Informe o nome da organização." };
  }

  // F6-A11/D26: identidade funcional mínima do primeiro Admin, validada por FORMA
  // com a taxonomia FECHADA (nenhum código público novo): nome humano ⇒
  // `INVALID_NAME`; matrícula ⇒ `INVALID_FOUNDER`. A mensagem específica é do
  // validador (o cliente exibe a mensagem canônica do código — F0-05).
  const founderFullName =
    typeof corpo.founder_full_name === "string" ? corpo.founder_full_name.trim() : "";
  if (founderFullName === "") {
    return { ok: false, codigo: "INVALID_NAME", message: "Informe o nome do primeiro Admin." };
  }

  const founderMatricula =
    typeof corpo.founder_matricula === "string" ? corpo.founder_matricula.trim() : "";
  if (founderMatricula === "") {
    return {
      ok: false,
      codigo: "INVALID_FOUNDER",
      message: "Informe a matrícula do primeiro Admin.",
    };
  }

  const temUserId = corpo.founder_user_id !== undefined;
  const temEmail = corpo.founder_email !== undefined;
  if (temUserId === temEmail) {
    return {
      ok: false,
      codigo: "INVALID_INPUT",
      message: "Informe exatamente uma forma de identificação do primeiro Admin.",
    };
  }

  if (temUserId) {
    const founderUserId =
      typeof corpo.founder_user_id === "string" ? corpo.founder_user_id.trim() : "";
    if (!UUID_CANONICO.test(founderUserId)) {
      return { ok: false, codigo: "INVALID_FOUNDER", message: "Identificador do primeiro Admin inválido." };
    }
    return {
      ok: true,
      entrada: {
        operacao: OPERACAO_PROVISIONAR_ORGANIZACAO,
        operationId,
        organizationName,
        founderFullName,
        founderMatricula,
        founderUserId,
      },
    };
  }

  const founderEmail =
    typeof corpo.founder_email === "string" ? corpo.founder_email.trim().toLowerCase() : "";
  if (!EMAIL_MINIMO.test(founderEmail)) {
    return { ok: false, codigo: "INVALID_FOUNDER", message: "E-mail do primeiro Admin inválido." };
  }
  return {
    ok: true,
    entrada: {
      operacao: OPERACAO_PROVISIONAR_ORGANIZACAO,
      operationId,
      organizationName,
      founderFullName,
      founderMatricula,
      founderEmail,
    },
  };
}

/**
 * Valida a FORMA das operações que só transportam `operacao` (self-check).
 * Allowlist estrita: qualquer chave adicional ⇒ `INVALID_INPUT`.
 */
export function validarSomenteOperacao(
  corpo: unknown,
  operacao: OperacaoPlataforma
): { readonly ok: true } | { readonly ok: false; readonly codigo: CodigoPublico; readonly message: string } {
  if (!corpoEhObjeto(corpo)) {
    return { ok: false, codigo: "INVALID_INPUT", message: "Corpo da requisição inválido." };
  }
  const permitidas = CHAVES_POR_OPERACAO[operacao];
  for (const chave of Object.keys(corpo)) {
    if (!permitidas.includes(chave)) {
      return {
        ok: false,
        codigo: "INVALID_INPUT",
        message: `Chave não aceita nesta operação: ${chave}.`,
      };
    }
  }
  return { ok: true };
}
