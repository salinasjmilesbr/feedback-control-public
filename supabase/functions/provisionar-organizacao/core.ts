/**
 * F6-A03 (Issue #266) — núcleo TESTÁVEL da Edge Function `provisionar-organizacao`.
 *
 * Fronteira confiável do PLANO DE PLATAFORMA (contrato §5/§6):
 *
 *   método → JWT (`auth.getUser` via deps) → AUTORIDADE DE PLATAFORMA
 *   (allowlist do ambiente, resolvida nas deps — nunca no corpo) → FORMA da
 *   intenção por ALLOWLIST ESTRITA → convite do primeiro Admin (quando novo) →
 *   RPC soberana `organizacao_provisionar_inicial` (idempotente) → resultado.
 *
 * Garantias deste núcleo:
 * - NÃO usa APIs de runtime (sem `Deno`, sem cliente Supabase): tudo é injetado
 *   por `DepsPlataforma`, o que o torna testável e mantém a credencial
 *   privilegiada exclusivamente no `index.ts`;
 * - a IDENTIDADE do ator é sempre o `auth.uid()` verificado (`resolveCaller`) —
 *   jamais um campo do corpo; a autoridade de plataforma é decidida por
 *   `operadorAutorizado`, também fora do corpo;
 * - a FORMA nunca é autoridade: `actor_*`, `organization_id`, `capability`,
 *   `scope`, `status`, `version` e `payload_hash` NÃO são transportáveis
 *   (allowlist estrita no contrato único);
 * - FAIL-CLOSED: sem JWT válido ⇒ 401; fora da allowlist ⇒ 403 (na operação de
 *   provisionamento) ou `{ operador: false }` (no self-check de UX, D20);
 *   resposta fora do contrato, código desconhecido ou erro do executor ⇒ erro
 *   público fechado, nunca "sucesso presumido";
 * - COMPENSAÇÃO: o usuário criado no Auth pelo convite é removido quando a RPC
 *   falha, para não deixar estado parcial silencioso (molde `convidar-usuario`).
 */

import {
  OPERACAO_OPERADOR_ATUAL,
  OPERACAO_PROVISIONAR_ORGANIZACAO,
  eOperacaoPlataforma,
  validarEntradaProvisaoPlataforma,
  validarSomenteOperacao,
  type CodigoPublico,
} from "../../../src/infrastructure/supabase/plataforma/contrato.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MENSAGENS: Readonly<Record<CodigoPublico, string>> = {
  NOT_AUTHORIZED: "Não autorizado.",
  INVALID_INPUT: "Dados da requisição inválidos.",
  INVALID_NAME: "Informe o nome da organização.",
  INVALID_FOUNDER: "Identificação do primeiro Admin inválida.",
  USER_EXISTS: "Já existe um usuário com este e-mail.",
  OPERATION_ALREADY_APPLIED: "Esta operação já foi aplicada com dados diferentes.",
  INTERNAL: "Não foi possível concluir a operação.",
  METHOD_NOT_ALLOWED: "Método não permitido.",
};

const STATUS: Readonly<Record<CodigoPublico, number>> = {
  NOT_AUTHORIZED: 403,
  INVALID_INPUT: 400,
  INVALID_NAME: 400,
  INVALID_FOUNDER: 400,
  USER_EXISTS: 409,
  OPERATION_ALREADY_APPLIED: 409,
  INTERNAL: 500,
  METHOD_NOT_ALLOWED: 405,
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function erro(codigo: CodigoPublico, mensagem?: string, status?: number): Response {
  return json(
    { error: { code: codigo, message: mensagem ?? MENSAGENS[codigo] } },
    status ?? STATUS[codigo]
  );
}

/** Erro devolvido por um executor (RPC/Auth Admin) — nunca exposto cru. */
export interface ErroExecucao {
  readonly code?: string;
  readonly message?: string;
}

/** Execução privilegiada do provisionamento, já com o ator VERIFICADO. */
export interface ExecucaoProvisionamento {
  readonly operationId: string;
  readonly organizationName: string;
  /** UUID da identidade autenticada do primeiro Admin (nunca do corpo cru). */
  readonly founderUserId: string;
  /** `auth.uid()` verificado server-side — NUNCA do corpo. */
  readonly actorUserProfileId: string;
  /**
   * F6-A11/D22-D23: nome humano do primeiro Admin — DADO a criar (como o nome da
   * organização), nunca autoridade; vira `collaborators.full_name`.
   */
  readonly founderFullName: string;
  /** F6-A11/D23/D28: matrícula declarada do primeiro Admin na nova organização. */
  readonly founderMatricula: string;
}

export interface ResultadoConvite {
  readonly userId: string | null;
  /** `true` quando o e-mail já pertence a um usuário existente (§6.3). */
  readonly existente: boolean;
  readonly erro: ErroExecucao | null;
}

export interface ResultadoProvisionamento {
  readonly organizationId: string | null;
  readonly erro: ErroExecucao | null;
}

export interface DepsPlataforma {
  /** Identidade soberana a partir do header `Authorization` (Gotrue). */
  readonly resolveCaller: (authHeader: string | null) => Promise<string | null>;
  /**
   * Autoridade de PLATAFORMA (allowlist do ambiente + piso de perfil, D14/D17).
   * Fail-closed: qualquer erro deve resolver `false`.
   */
  readonly operadorAutorizado: (authUserId: string) => Promise<boolean>;
  /**
   * Operação JÁ registrada na âncora de idempotência (D6/D7), com o e-mail da
   * identidade do primeiro Admin da PRIMEIRA execução resolvido. `null` =
   * operação NOVA.
   *
   * Existe para que a Edge **não** produza efeito colateral no Auth (convite)
   * antes de reconhecer um REPLAY: sem esta consulta, repetir a mesma operação
   * do caminho por e-mail encontraria o e-mail já existente e devolveria
   * `USER_EXISTS`, quebrando a idempotência ponta a ponta.
   */
  readonly operacaoAplicada: (
    operationId: string
  ) => Promise<OperacaoAplicadaRegistrada | null>;
  /** Cria a identidade do primeiro Admin no Auth (Auth Admin, server-side). */
  readonly convidarFounder: (email: string) => Promise<ResultadoConvite>;
  /** Executa a RPC soberana transacional/idempotente. */
  readonly provisionar: (execucao: ExecucaoProvisionamento) => Promise<ResultadoProvisionamento>;
  /** Compensação: remove o usuário criado quando a RPC falha. */
  readonly compensarFounder: (userId: string) => Promise<void>;
}

/** Operação já aplicada, como a Edge a enxerga para reconhecer o REPLAY. */
export interface OperacaoAplicadaRegistrada {
  readonly organizationId: string;
  readonly actorUserProfileId: string;
  readonly organizationName: string;
  /** Identidade do primeiro Admin que a PRIMEIRA execução estabeleceu. */
  readonly founderUserId: string;
  /** E-mail dessa identidade; `null` quando não foi possível resolver. */
  readonly founderEmail: string | null;
}

export type ReconhecimentoOperacao =
  | { readonly tipo: "nenhum" }
  /** Mesma intenção: delega o REPLAY à RPC (fonte única), sem novo efeito. */
  | { readonly tipo: "replay"; readonly founderUserId: string }
  /** A âncora já existe com intenção DIVERGENTE: recusa fail-closed. */
  | { readonly tipo: "divergente" };

/**
 * Decide se a intenção declarada é um REPLAY da operação já registrada.
 *
 * Função PURA. Duas garantias:
 * - a Edge **nunca** declara sucesso nem devolve `organization_id` por conta
 *   própria: o REPLAY é sempre resolvido pela RPC (fonte única da idempotência);
 * - intenção divergente (outro ator, outro nome ou outro primeiro Admin) é
 *   RECUSADA — nunca reaproveita silenciosamente a organização anterior.
 *
 * `founderEmail` ausente na operação registrada (ou não resolvido) ⇒
 * `divergente` (fail-closed): sem prova de que o primeiro Admin é o mesmo, não há
 * replay.
 */
export function reconhecerOperacaoAplicada(
  aplicada: OperacaoAplicadaRegistrada | null,
  intencao: {
    readonly actorUserProfileId: string;
    readonly organizationName: string;
    readonly founderEmail: string;
  }
): ReconhecimentoOperacao {
  if (!aplicada) return { tipo: "nenhum" };

  const mesmaIntencao =
    aplicada.actorUserProfileId === intencao.actorUserProfileId &&
    aplicada.organizationName === intencao.organizationName &&
    typeof aplicada.founderEmail === "string" &&
    aplicada.founderEmail.trim().toLowerCase() === intencao.founderEmail;

  if (!mesmaIntencao) return { tipo: "divergente" };
  return { tipo: "replay", founderUserId: aplicada.founderUserId };
}

/**
 * Mapa FECHADO de erro do executor → código público. Código/mensagem
 * desconhecidos ⇒ `INTERNAL` (fail-closed): nada de vazar detalhe interno nem de
 * presumir sucesso. Os prefixos `F6_A03_*` são os levantados pela RPC soberana.
 */
export function codigoPublicoDeErroRpc(erro: ErroExecucao | null): CodigoPublico {
  if (!erro) return "INTERNAL";
  const texto = `${erro.code ?? ""} ${erro.message ?? ""}`;

  if (texto.includes("F6_A03_FORBIDDEN")) return "NOT_AUTHORIZED";
  if (texto.includes("F6_A03_INVALID_NAME")) return "INVALID_NAME";
  if (texto.includes("F6_A03_INVALID_FOUNDER")) return "INVALID_FOUNDER";
  if (texto.includes("F6_A03_INVALID_INPUT")) return "INVALID_INPUT";
  if (texto.includes("F6_A03_CONFLICT")) return "OPERATION_ALREADY_APPLIED";
  if (texto.includes("F6_A03_INTERNAL")) return "INTERNAL";

  // Classes do Postgres que a RPC pode propagar (FK/not-null/check/unique).
  switch (erro.code) {
    case "23503":
      return "INVALID_FOUNDER";
    case "23502":
    case "23514":
      return "INVALID_INPUT";
    case "23505":
      return "OPERATION_ALREADY_APPLIED";
    default:
      return "INTERNAL";
  }
}

/**
 * Autoridade de PLATAFORMA resolvida FAIL-CLOSED: qualquer falha do resolvedor
 * (rede, exceção, ausência de allowlist) ⇒ `false`. Nunca lança.
 */
async function autoridadeDePlataforma(
  deps: DepsPlataforma,
  authUserId: string
): Promise<boolean> {
  try {
    return await deps.operadorAutorizado(authUserId);
  } catch {
    return false;
  }
}

/**
 * Handler da Edge `provisionar-organizacao`. Devolve sempre `Response` com o
 * corpo no contrato (`{ ok, operacao, resultado }` ou `{ error: { code, message } }`).
 */
export async function plataforma(req: Request, deps: DepsPlataforma): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return erro("METHOD_NOT_ALLOWED");
  }

  let corpo: unknown;
  try {
    corpo = await req.json();
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.");
  }

  if (typeof corpo !== "object" || corpo === null || Array.isArray(corpo)) {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.");
  }

  const operacao = (corpo as Record<string, unknown>).operacao;
  if (!eOperacaoPlataforma(operacao)) {
    // Operação desconhecida NÃO tem allowlist nem default permissivo.
    return erro("INVALID_INPUT", "Operação não suportada.");
  }

  // (1) Identidade soberana SEMPRE antes de qualquer decisão de conteúdo.
  const callerIdResolvido = await deps.resolveCaller(req.headers.get("Authorization"));
  if (!callerIdResolvido) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }
  /** Ator VERIFICADO, já sem `null`: atravessa closures sem perder o tipo. */
  const callerId: string = callerIdResolvido;

  // (2) Self-check de UX (D20). NUNCA autoriza nada e NUNCA recusa com 403:
  //     devolve `{ operador: boolean }` — fail-closed em qualquer falha.
  if (operacao === OPERACAO_OPERADOR_ATUAL) {
    const forma = validarSomenteOperacao(corpo, operacao);
    if (!forma.ok) {
      return erro(forma.codigo, forma.message);
    }
    const operador = await autoridadeDePlataforma(deps, callerId);
    return json({ ok: true, operacao, resultado: { operador } });
  }

  // (3) Provisionamento: AUTORIDADE antes da forma (não vaza detalhe de
  //     validação para quem não é operador).
  const autorizado = await autoridadeDePlataforma(deps, callerId);
  if (!autorizado) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 403);
  }

  // (4) FORMA da intenção (allowlist estrita + XOR de identificação do founder).
  const validacao = validarEntradaProvisaoPlataforma(corpo);
  if (!validacao.ok) {
    return erro(validacao.codigo, validacao.message);
  }
  const entrada = validacao.entrada;

  // (5) Execução soberana: transacional e idempotente (a RPC deriva o hash
  //     canônico server-side, revalida o ator e é a fonte ÚNICA do REPLAY).
  //     A compensação é BEST-EFFORT: a falha dela NUNCA mascara o código público
  //     real (o usuário órfão fica sem perfil/membership ⇒ inacessível).
  async function executar(
    founderUserId: string,
    criadoAgora: string | null
  ): Promise<Response> {
    const resultado = await deps.provisionar({
      operationId: entrada.operationId,
      organizationName: entrada.organizationName,
      founderUserId,
      actorUserProfileId: callerId,
      // F6-A11/D23: identidade funcional mínima (dado, nunca autoridade). O
      // e-mail do colaborador é resolvido server-side no `index.ts` (D25).
      founderFullName: entrada.founderFullName,
      founderMatricula: entrada.founderMatricula,
    });

    if (resultado.erro || !resultado.organizationId) {
      if (criadoAgora) {
        try {
          await deps.compensarFounder(criadoAgora);
        } catch {
          // Silencioso por desenho: a falha da compensação não altera a resposta
          // (o órfão não tem perfil nem membership — fail-closed).
        }
      }
      return erro(codigoPublicoDeErroRpc(resultado.erro));
    }

    return json({
      ok: true,
      operacao: OPERACAO_PROVISIONAR_ORGANIZACAO,
      resultado: { organization_id: resultado.organizationId },
    });
  }

  // (6) Identidade JÁ declarada (caminho `founder_user_id`): a RPC reconhece o
  //     REPLAY por si — nenhum efeito colateral no Auth.
  const founderDeclarado = entrada.founderUserId;
  if (founderDeclarado) {
    return executar(founderDeclarado, null);
  }

  // (7) Caminho por E-MAIL: reconhecer o REPLAY **antes** de qualquer convite.
  const email = entrada.founderEmail;
  if (!email) {
    return erro("INVALID_FOUNDER");
  }

  const reconhecimento = reconhecerOperacaoAplicada(
    await deps.operacaoAplicada(entrada.operationId),
    {
      actorUserProfileId: callerId,
      organizationName: entrada.organizationName,
      founderEmail: email,
    }
  );

  if (reconhecimento.tipo === "divergente") {
    // A âncora já existe com OUTRA intenção: recusa fail-closed, sem convidar.
    return erro("OPERATION_ALREADY_APPLIED");
  }
  if (reconhecimento.tipo === "replay") {
    // REPLAY: ZERO efeito colateral no Auth; a RPC devolve o MESMO
    // `organization_id` da primeira execução.
    return executar(reconhecimento.founderUserId, null);
  }

  // (8) Operação NOVA: cria a identidade do primeiro Admin e provisiona.
  const convite = await deps.convidarFounder(email);
  if (convite.erro) {
    return erro(codigoPublicoDeErroRpc(convite.erro));
  }
  if (convite.existente) {
    // Identidade existente de terceiro exige o caminho `founder_user_id`
    // (limitação registrada no contrato, §13 F6).
    return erro("USER_EXISTS");
  }
  if (!convite.userId) {
    return erro("INTERNAL");
  }

  return executar(convite.userId, convite.userId);
}
