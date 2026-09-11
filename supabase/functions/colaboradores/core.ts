// F5-07 — núcleo testável do caminho soberano de COLABORADORES.
//
// Compartilhado entre a Edge Function (Deno) e os testes (Vitest). NÃO contém
// APIs de runtime (Deno/Node): as dependências são INJETADAS — inclusive o
// executor privilegiado das RPC `p_*` (implementado na Edge, que é quem tem o
// cliente `service_role`).
//
// MODELO DE PRODUÇÃO (decisão × execução SEPARADAS — §7/§9.4/§9.5):
//
//   usuário autenticado (JWT no header `Authorization`)
//   → [resolveCaller] identidade SOBERANA via `auth.getUser(JWT)`;
//   → validação de FORMA do payload (nunca autoridade);
//   → organização pretendida REVALIDADA contra membership ativa (intenção de UX);
//   → alvo SOBERANO: `matricula` é INTENÇÃO resolvida aqui (ambígua/ausente ⇒
//     `NOT_FOUND`, nunca escolhe arbitrariamente);
//   → gate: plano FUNCIONAL (ActorContext + ResourceContext reais + Policy
//     Engine) para `collaborator.*`; plano ADMINISTRATIVO (D19) para
//     `colaborador.ocupacao.*`, `estrutura.*` e `colaborador.catalogo.bootstrap`;
//   → SOMENTE com ALLOW: [executarRpc] chama a RPC com credencial `service_role`
//     (SEM propagar o JWT do usuário) e com o ator VERIFICADO como parâmetro;
//   → a RPC revalida ator/membership/tenant, aplica as invariantes temporais e
//     grava o evento append-only na MESMA transação.
//
// `service_role` é credencial de EXECUÇÃO, nunca de decisão: se o gate negar, a
// RPC não é chamada (não existe caminho alternativo). A matrícula NUNCA é
// enviada às RPC como identidade: o que atravessa é o UUID resolvido.
//
// Sem cache de decisão entre requests (§9.5/I10): o contexto resolvido vale para
// ESTA requisição e é descartado ao fim dela.

import {
  ehOperacaoFuncional,
  ehUuid,
  ID_NEUTRO,
  validarEntradaColaborador,
  type CodigoPublico,
  type EntradaAlterarStatus,
  type EntradaBootstrapCatalogo,
  type EntradaColaborador,
  type EntradaCriar,
  type EntradaDefinirIdentificador,
  type EntradaDefinirOcupacao,
  type EntradaDefinirReporting,
  type EntradaDefinirResponsabilidade,
  type EntradaEditar,
  type EntradaEncerrarOcupacao,
  type EntradaEncerrarReporting,
  type EntradaEncerrarResponsabilidade,
  type EntradaHistorico,
  type EntradaListar,
  type EntradaObter,
  type EntradaRegistrarSucessao,
  type OperacaoColaborador,
} from "../../../src/infrastructure/supabase/colaboradores/contrato.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function erro(codigo: CodigoPublico, mensagem: string, status: number): Response {
  return json({ error: { code: codigo, message: mensagem } }, status);
}

/** Status HTTP de cada código público (§8.2). */
export function statusDoCodigo(codigo: CodigoPublico): number {
  switch (codigo) {
    case "INVALID_INPUT":
      return 400;
    case "NOT_AUTHORIZED":
      return 401;
    case "FORBIDDEN":
      return 403;
    case "NOT_FOUND":
      return 404;
    case "METHOD_NOT_ALLOWED":
      return 405;
    case "CONFLICT":
      return 409;
    case "INTERNAL":
      return 500;
  }
}

/**
 * Mensagem GENÉRICA por código público: a mensagem crua do banco (e a razão
 * interna da negação) nunca é exposta ao cliente.
 */
export function mensagemDoCodigo(codigo: CodigoPublico): string {
  switch (codigo) {
    case "INVALID_INPUT":
      return "Dados inválidos para a operação solicitada.";
    case "NOT_AUTHORIZED":
      return "Não autorizado.";
    case "FORBIDDEN":
      return "Operação não permitida.";
    case "NOT_FOUND":
      return "Registro não encontrado.";
    case "METHOD_NOT_ALLOWED":
      return "Método não permitido.";
    case "CONFLICT":
      return "A operação conflita com o estado atual do registro.";
    case "INTERNAL":
      return "Não foi possível concluir a operação.";
  }
}

// ---------------------------------------------------------------------------
// Contrato com a fronteira confiável (implementado na Edge)
// ---------------------------------------------------------------------------

/** Erro devolvido pelo executor de RPC (nunca exposto cru ao cliente). */
export interface ErroRpcColaborador {
  readonly code?: string;
  readonly message?: string;
}

export interface ResultadoRpcColaborador {
  readonly data?: unknown;
  readonly error?: ErroRpcColaborador | null;
}

/** Contexto SOBERANO já revalidado (ator + organização + membership). */
export interface ContextoAtorColaborador {
  /** `auth.uid()` VERIFICADO server-side — nunca do corpo. */
  readonly actorUserProfileId: string;
  /** Organização pretendida, REVALIDADA contra membership ativa. */
  readonly organizationId: string;
  /** Instante soberano da operação (relógio do servidor). */
  readonly agora: string;
  /** Filtros de `collaborator.listar` (chaves sanitizadas). */
  readonly filtrosListar: Readonly<Record<string, string>> | null;
  /** Data de referência da visão/linha do tempo (`null` ⇒ agora do banco). */
  readonly dataReferencia: string | null;
  /** Ciclo de referência opcional (escopo por ciclo — baseline §11.2). */
  readonly referenceCycleId: string | null;
  /** UUID soberano do colaborador alvo (quando a operação tem alvo). */
  readonly collaboratorId: string | null;
  /**
   * UUID do colaborador VINCULADO ao ator (F5-02) na organização revalidada —
   * âncora autorizável das operações sem alvo explícito (criar/listar).
   * null ⇒ ator sem vínculo: a operação funcional sem alvo é negada.
   */
  readonly atorCollaboratorId: string | null;
  /** Matrícula resolvida (quando a tela informou matrícula como intenção). */
  readonly matriculaResolvida: string | null;
}

export type OperacaoExecutavel =
  | { readonly operacao: "collaborator.listar"; readonly entrada: EntradaListar }
  | { readonly operacao: "collaborator.obter"; readonly entrada: EntradaObter }
  | { readonly operacao: "collaborator.criar"; readonly entrada: EntradaCriar }
  | { readonly operacao: "collaborator.editar"; readonly entrada: EntradaEditar }
  | {
      readonly operacao: "collaborator.identificador.definir";
      readonly entrada: EntradaDefinirIdentificador;
    }
  | { readonly operacao: "collaborator.status.alterar"; readonly entrada: EntradaAlterarStatus }
  | { readonly operacao: "colaborador.ocupacao.definir"; readonly entrada: EntradaDefinirOcupacao }
  | {
      readonly operacao: "colaborador.ocupacao.encerrar";
      readonly entrada: EntradaEncerrarOcupacao;
    }
  | { readonly operacao: "estrutura.reporting.definir"; readonly entrada: EntradaDefinirReporting }
  | { readonly operacao: "estrutura.reporting.encerrar"; readonly entrada: EntradaEncerrarReporting }
  | {
      readonly operacao: "estrutura.responsabilidade.definir";
      readonly entrada: EntradaDefinirResponsabilidade;
    }
  | {
      readonly operacao: "estrutura.responsabilidade.encerrar";
      readonly entrada: EntradaEncerrarResponsabilidade;
    }
  | { readonly operacao: "estrutura.sucessao.registrar"; readonly entrada: EntradaRegistrarSucessao }
  | { readonly operacao: "colaborador.historico.listar"; readonly entrada: EntradaHistorico }
  | {
      readonly operacao: "colaborador.catalogo.bootstrap";
      readonly entrada: EntradaBootstrapCatalogo;
    };

/**
 * Linha de capability × escopo efetiva do ator (F5-04). Usada SOMENTE pelo
 * plano administrativo (D19) para exigir a presença do código; escopo é
 * irrelevante nessas operações (o alvo é a organização).
 */
export interface LinhaCapability {
  readonly capability_code?: unknown;
}

export interface DepsColaboradores {
  /** Resolve a identidade soberana a partir do JWT via `auth.getUser`. */
  resolveCaller(authHeader: string): Promise<string | null>;
  /** Organizações com membership ATIVA do ator (intenção revalidada). */
  resolverOrganizacoesDoAtor(authUserId: string): Promise<readonly string[]>;
  /** O colaborador pertence a ESTA organização? (fail-closed em erro). */
  colaboradorPertenceAoAtor(entrada: {
    readonly actorUserProfileId: string;
    readonly organizationId: string;
    readonly collaboratorId: string;
  }): Promise<boolean>;
  /** Resolve a matrícula (INTENÇÃO) para o UUID soberano (§2). */
  resolverMatricula(entrada: {
    readonly actorUserProfileId: string;
    readonly organizationId: string;
    readonly matricula: string;
  }): Promise<string | null>;
  /**
   * Vínculo soberano do ATOR (F5-02): (authUserId, organizationId) → colaborador.
   * É a ÂNCORA autorizável das operações FUNCIONAIS sem alvo explícito
   * (collaborator.criar, collaborator.listar): um colaborador REAL do tenant,
   * resolvido server-side — nunca UUID neutro, nunca id do cliente e nunca uma
   * linha fictícia. Sem vínculo ⇒ null ⇒ o gate nega (fail-closed).
   */
  resolverColaboradorVinculado(
    authUserId: string,
    organizationId: string
  ): Promise<string | null>;
  /** Gate FUNCIONAL: Policy Engine com ActorContext/ResourceContext reais. */
  avaliarAutorizacao(entrada: {
    readonly actorUserProfileId: string;
    readonly organizationId: string;
    readonly operacao: OperacaoColaborador;
    readonly alvo: { readonly type: "collaborator"; readonly id: string };
    readonly dataNegocio: string | null;
  }): Promise<{ readonly permitido: boolean; readonly code?: CodigoPublico }>;
  /** Gate ADMINISTRATIVO (D19): capabilities efetivas do ator na organização. */
  resolverCapabilitiesEfetivas(entrada: {
    readonly actorUserProfileId: string;
    readonly organizationId: string;
  }): Promise<readonly LinhaCapability[]>;
  /** Executa a RPC com credencial privilegiada e ator VERIFICADO. */
  executarRpc(execucao: OperacaoExecutavel, contexto: ContextoAtorColaborador): Promise<ResultadoRpcColaborador>;
}

// ---------------------------------------------------------------------------
// Tradução de erro (o prefixo `F5_07_*` vira código público)
// ---------------------------------------------------------------------------

/**
 * Traduz a falha da RPC para o código público estável. A mensagem interna do
 * banco NUNCA é propagada: apenas o prefixo estável `F5_07_*` é interpretado.
 */
export function codigoDeErroRpc(erro: ErroRpcColaborador | null | undefined): CodigoPublico {
  const codigo = typeof erro?.code === "string" ? erro.code : "";
  const mensagem = typeof erro?.message === "string" ? erro.message : "";
  const assinatura = `${codigo} ${mensagem}`;

  if (assinatura.includes("F5_07_FORBIDDEN")) return "FORBIDDEN";
  if (assinatura.includes("F5_07_NOT_FOUND")) return "NOT_FOUND";
  if (assinatura.includes("F5_07_CONFLICT")) return "CONFLICT";
  if (assinatura.includes("F5_07_INVALID_INPUT")) return "INVALID_INPUT";

  // Integridade do banco (23503 FK, 23514 check, 23505 unique, 23P01 exclusion)
  // é conflito de DOMÍNIO — a operação foi autorizada e o estado recusou.
  if (codigo.startsWith("23")) return "CONFLICT";

  return "INTERNAL";
}

// ---------------------------------------------------------------------------
// Resolução do contexto soberano por request (sem cache entre requests)
// ---------------------------------------------------------------------------

/**
 * Parte do payload que ainda NÃO passou pelo gate. O núcleo devolve os campos
 * de intenção já validados por forma; o alvo resolvido no servidor NÃO está
 * aqui (a matrícula é transportada como intenção canônica em texto).
 */
export interface IntencaoColaborador {
  readonly operacao: OperacaoColaborador;
  readonly organizationId: string;
  readonly collaboratorId: string | null;
  readonly matricula: string | null;
  readonly dataReferencia: string | null;
  readonly referenceCycleId: string | null;
  readonly filtrosListar: Readonly<Record<string, string>> | null;
}

const OPERACOES_COM_ALVO: readonly OperacaoColaborador[] = [
  "collaborator.obter",
  "collaborator.editar",
  "collaborator.identificador.definir",
  "collaborator.status.alterar",
  "colaborador.historico.listar",
];

function operacaoTemAlvo(operacao: OperacaoColaborador): boolean {
  return OPERACOES_COM_ALVO.includes(operacao);
}

/**
 * Escapa os curingas de ILIKE: a tela informa SUBSTRING de busca, nunca um
 * padrão de banco (sem isso, `%` viraria "todos").
 */
function filtrosDoPayload(entrada: EntradaColaborador): Record<string, string> | null {
  if (!("filtros" in entrada) || !entrada.filtros) return null;
  const filtros: Record<string, string> = {};
  if (entrada.filtros.status) filtros.status = entrada.filtros.status;
  if (entrada.filtros.unit_id) filtros.unit_id = entrada.filtros.unit_id;
  if (entrada.filtros.busca) {
    filtros.busca = entrada.filtros.busca.replace(/[\\%_]/g, (caractere) => `\\${caractere}`);
  }
  return Object.keys(filtros).length > 0 ? filtros : null;
}

/** Extrai a intenção validada (nada aqui concede autoridade). */
export function montarIntencao(
  operacao: OperacaoColaborador,
  entrada: EntradaColaborador
): IntencaoColaborador {
  const collaboratorId =
    "collaborator_id" in entrada && typeof entrada.collaborator_id === "string"
      ? entrada.collaborator_id
      : null;
  const matricula =
    "matricula" in entrada && typeof entrada.matricula === "string" ? entrada.matricula : null;
  const dataReferencia =
    "data_referencia" in entrada && typeof entrada.data_referencia === "string"
      ? entrada.data_referencia
      : null;
  const referenceCycleId =
    "reference_cycle_id" in entrada && typeof entrada.reference_cycle_id === "string"
      ? entrada.reference_cycle_id
      : null;

  return {
    operacao,
    organizationId: entrada.organization_id,
    collaboratorId,
    matricula,
    dataReferencia,
    referenceCycleId,
    filtrosListar: filtrosDoPayload(entrada),
  };
}

/**
 * Resolve o CONTEXTO SOBERANO da operação: organização (intenção revalidada
 * contra membership ativa), alvo (UUID) e matrícula (INTENÇÃO resolvida).
 *
 * Falha fechado em qualquer elo: organização ausente/divergente ⇒ `FORBIDDEN`;
 * alvo inexistente, de outro tenant ou matrícula ambígua ⇒ `NOT_FOUND`
 * (indistinguíveis para o cliente — §7).
 */
export async function resolverContextoAtor(
  authUserId: string,
  intencao: IntencaoColaborador,
  deps: DepsColaboradores
): Promise<
  | { readonly ok: true; readonly contexto: ContextoAtorColaborador }
  | { readonly ok: false; readonly code: CodigoPublico }
> {
  if (!ehUuid(authUserId)) return { ok: false, code: "NOT_AUTHORIZED" };

  // A organização do payload é INTENÇÃO: só vale se houver membership ATIVA.
  const organizacoes = await deps.resolverOrganizacoesDoAtor(authUserId);
  if (!organizacoes.includes(intencao.organizationId)) {
    return { ok: false, code: "FORBIDDEN" };
  }

  // A matrícula é IDENTIDADE apenas quando a operação endereça um colaborador
  // EXISTENTE. Em collaborator.criar ela é DADO A CRIAR: resolvê-la devolveria
  // null (ainda não existe) e a criação terminaria em NOT_FOUND ANTES do gate.
  // Na criação a matrícula segue para a RPC apenas como DADO (p_matricula).
  let collaboratorId: string | null = null;
  if (operacaoTemAlvo(intencao.operacao) && intencao.matricula !== null) {
    // Matrícula → UUID na fronteira: ambígua/ausente ⇒ não encontrado.
    const resolvido = await deps.resolverMatricula({
      actorUserProfileId: authUserId,
      organizationId: intencao.organizationId,
      matricula: intencao.matricula,
    });
    if (!resolvido) return { ok: false, code: "NOT_FOUND" };
    collaboratorId = resolvido;
  } else if (intencao.collaboratorId !== null) {
    collaboratorId = intencao.collaboratorId;
  }

  if (operacaoTemAlvo(intencao.operacao)) {
    if (!collaboratorId) return { ok: false, code: "NOT_FOUND" };
    // Pertencimento ao tenant ANTES do gate: alvo de outro tenant ⇒ NOT_FOUND
    // (nunca `FORBIDDEN`, para não vazar existência cross-tenant).
    const pertence = await deps.colaboradorPertenceAoAtor({
      actorUserProfileId: authUserId,
      organizationId: intencao.organizationId,
      collaboratorId,
    });
    if (!pertence) return { ok: false, code: "NOT_FOUND" };
  }

  /**
   * Âncora soberana das operações FUNCIONAIS sem alvo explícito (criar/listar):
   * o PRÓPRIO colaborador vinculado do ator (F5-02), resolvido server-side na
   * organização JÁ revalidada. Nunca vem do corpo, nunca é UUID neutro e não
   * cria linha fictícia. Sem vínculo ⇒ null.
   */
  const atorCollaboratorId =
    ehOperacaoFuncional(intencao.operacao) && !operacaoTemAlvo(intencao.operacao)
      ? await deps.resolverColaboradorVinculado(authUserId, intencao.organizationId)
      : null;

  return {
    ok: true,
    contexto: {
      actorUserProfileId: authUserId,
      organizationId: intencao.organizationId,
      agora: new Date().toISOString(),
      filtrosListar: intencao.filtrosListar,
      dataReferencia: intencao.dataReferencia,
      referenceCycleId: intencao.referenceCycleId,
      collaboratorId,
      atorCollaboratorId,
      matriculaResolvida: intencao.matricula === null ? null : collaboratorId,
    },
  };
}

// ---------------------------------------------------------------------------
// Gate (dois planos — §9)
// ---------------------------------------------------------------------------

/**
 * Alvo autorizável. Criação (e o alvo derivado da matrícula) não têm UUID
 * conhecido ANTES da RPC: o alvo neutro é NEGADO pelo engine caso o recurso não
 * exista (fail-closed) — o cliente nunca fornece o alvo autorizável.
 */
export function alvoDaDecisao(
  entrada: EntradaColaborador,
  contexto: ContextoAtorColaborador
): string | null {
  if ("alvo" in entrada && entrada.alvo.id !== ID_NEUTRO) return entrada.alvo.id;
  // Operação que endereça um colaborador EXISTENTE: o alvo é o UUID resolvido
  // na fronteira (matrícula como INTENÇÃO ou id informado).
  if (contexto.collaboratorId) return contexto.collaboratorId;
  // Sem alvo explícito (criar/listar): a âncora é o colaborador VINCULADO do
  // ator — recurso REAL do tenant, resolvido server-side. O ID_NEUTRO do
  // contrato é apenas marcador de ausência de alvo no corpo e NUNCA chega ao
  // engine (não existe colaborador placeholder).
  return contexto.atorCollaboratorId;
}

/**
 * Gate FUNCIONAL = EXATAMENTE o caminho de decisão da Edge `avaliacoes`:
 * `avaliarOperacaoAutorizacao` monta ActorContext/ResourceContext reais e roda o
 * Policy Engine (F4-03) com a capability canônica de §9.2.
 */
export async function avaliarGateFuncional(
  authUserId: string,
  operacao: OperacaoColaborador,
  alvoId: string,
  organizationId: string,
  dataNegocio: string | null,
  deps: DepsColaboradores
): Promise<{ readonly permitido: boolean; readonly code?: CodigoPublico }> {
  return deps.avaliarAutorizacao({
    actorUserProfileId: authUserId,
    organizationId,
    operacao,
    alvo: { type: "collaborator", id: alvoId },
    dataNegocio,
  });
}

/**
 * Gate ADMINISTRATIVO (D19): as capabilities efetivas do ator na organização
 * precisam conter o código exigido (`org.structure.manage` / `org.catalog.manage`).
 * Ausente ⇒ `FORBIDDEN`. A allowlist funcional do engine NUNCA é consultada
 * aqui (essas capabilities têm target `[]` e seriam sempre negadas no engine).
 */
export async function avaliarGateAdministrativo(
  authUserId: string,
  organizationId: string,
  capabilityExigida: string,
  deps: DepsColaboradores
): Promise<{ readonly permitido: boolean; readonly code?: CodigoPublico }> {
  const capabilities = await deps.resolverCapabilitiesEfetivas({
    actorUserProfileId: authUserId,
    organizationId,
  });
  const possui = capabilities.some(
    (linha) => linha.capability_code === capabilityExigida
  );
  return possui ? { permitido: true } : { permitido: false, code: "FORBIDDEN" };
}

// ---------------------------------------------------------------------------
// Normalização do resultado da RPC → payload de resposta
// ---------------------------------------------------------------------------

function projetarResultado(
  operacao: OperacaoColaborador,
  valor: unknown
): { readonly ok: true; readonly resultado: unknown } | { readonly ok: false; readonly code: CodigoPublico } {
  // Leitura de item que não existe no tenant é `NOT_FOUND` (fail-closed).
  if (operacao === "collaborator.obter" && (valor === null || valor === undefined)) {
    return { ok: false, code: "NOT_FOUND" };
  }
  if (operacao === "collaborator.listar" || operacao === "colaborador.historico.listar") {
    return { ok: true, resultado: Array.isArray(valor) ? valor : [] };
  }
  if (valor === null || valor === undefined) {
    // Operação autorizada sem efeito confirmado pela RPC: conflito de domínio
    // (nunca `ok: true` sem entidade — a tela não pode achar que gravou).
    return { ok: false, code: "CONFLICT" };
  }
  return { ok: true, resultado: valor };
}

// ---------------------------------------------------------------------------
// Dispatch da requisição
// ---------------------------------------------------------------------------

export async function colaboradores(
  req: Request,
  deps: DepsColaboradores
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return erro("METHOD_NOT_ALLOWED", mensagemDoCodigo("METHOD_NOT_ALLOWED"), 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return erro("NOT_AUTHORIZED", mensagemDoCodigo("NOT_AUTHORIZED"), 401);
  }

  // 1) identidade soberana (nunca do corpo).
  const callerId = await deps.resolveCaller(authHeader);
  if (!callerId) {
    return erro("NOT_AUTHORIZED", mensagemDoCodigo("NOT_AUTHORIZED"), 401);
  }

  // 2) forma da intenção (nunca autoridade).
  let corpo: unknown;
  try {
    corpo = await req.json();
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.", 400);
  }
  const validacao = validarEntradaColaborador(corpo);
  if (!validacao.ok) {
    return erro(validacao.code, validacao.message, statusDoCodigo(validacao.code));
  }
  const entrada = validacao.entrada;
  const operacao = (corpo as { operacao: OperacaoColaborador }).operacao;

  // 3) contexto soberano: organização revalidada + alvo/matrícula resolvidos.
  const intencao = montarIntencao(operacao, entrada);
  const resolucao = await resolverContextoAtor(callerId, intencao, deps);
  if (!resolucao.ok) {
    return erro(resolucao.code, mensagemDoCodigo(resolucao.code), statusDoCodigo(resolucao.code));
  }
  const contexto = resolucao.contexto;

  // 4) gate por operação (funcional × administrativo — §9.2).
  const alvoId = alvoDaDecisao(entrada, contexto);
  let decisao: { readonly permitido: boolean; readonly code?: CodigoPublico };
  if (ehOperacaoFuncional(operacao)) {
    // Operação FUNCIONAL sem âncora soberana (ator sem vínculo F5-02): não há
    // recurso autorizável ⇒ fail-closed, sem recurso fictício e sem tocar a RPC.
    decisao = alvoId
      ? await avaliarGateFuncional(
          callerId,
          operacao,
          alvoId,
          contexto.organizationId,
          contexto.dataReferencia,
          deps
        )
      : { permitido: false, code: "FORBIDDEN" };
  } else {
    decisao = await avaliarGateAdministrativo(
      callerId,
      contexto.organizationId,
      capacidadeDaOperacao(operacao),
      deps
    );
  }

  if (!decisao.permitido) {
    const code = decisao.code ?? "FORBIDDEN";
    return erro(code, mensagemDoCodigo(code), statusDoCodigo(code));
  }

  // 5) execução privilegiada com o ator VERIFICADO (JWT nunca propagado).
  const resultado = await deps.executarRpc({ operacao, entrada } as OperacaoExecutavel, contexto);

  if (resultado.error) {
    const code = codigoDeErroRpc(resultado.error);
    return erro(code, mensagemDoCodigo(code), statusDoCodigo(code));
  }

  const projetado = projetarResultado(operacao, resultado.data ?? null);
  if (!projetado.ok) {
    return erro(projetado.code, mensagemDoCodigo(projetado.code), statusDoCodigo(projetado.code));
  }

  return json({ ok: true, operacao, resultado: projetado.resultado }, 200);
}

/** Capacidade exigida no plano administrativo (D19) — sem allowlist funcional. */
function capacidadeDaOperacao(operacao: OperacaoColaborador): string {
  switch (operacao) {
    case "colaborador.catalogo.bootstrap":
      return "org.catalog.manage";
    default:
      return "org.structure.manage";
  }
}
