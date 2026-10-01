// F5-06 (Issue #103): núcleo testável do caminho server-side de AVALIAÇÕES.
//
// Compartilhado entre a Edge Function (Deno) e os testes (Vitest). NÃO contém
// APIs de runtime (Deno/Node) — as dependências são INJETADAS.
//
// MODELO DE PRODUÇÃO (decisão × execução SEPARADAS — D27):
//
//   usuário autenticado (JWT no header `Authorization`)
//   → [resolveCaller] identidade SOBERANA via `auth.getUser(JWT)` (Gotrue);
//   → [avaliarAutorizacao] ActorContext real + ResourceContext REAL da avaliação
//     (linha carregada server-side) + capabilities×scopes + Policy Engine;
//   → SOMENTE com ALLOW: [executarRpc] chama a RPC `evaluation_*` com a
//     credencial service_role (SEM propagar o JWT do usuário, senão o PostgREST
//     assumiria `authenticated` e perderia o EXECUTE) e com o ator VERIFICADO
//     como parâmetro;
//   → a RPC revalida perfil/membership/tenant e grava evento na mesma transação.
//
// `service_role` é credencial de EXECUÇÃO, nunca de decisão: se o Policy Engine
// negar, a RPC não é chamada (não existe caminho alternativo).

import {
  CAPABILITY_POR_OPERACAO,
  ehOperacaoAvaliacao,
  validarEntradaAvaliacao,
  type CodigoPublico,
  type DescobertaAvaliacaoDoColaborador,
  type EntradaAvaliacao,
  type OperacaoAvaliacao,
  type PainelParticipantesAvaliacao,
} from "../../../src/infrastructure/supabase/avaliacoes/contrato.ts";
import type { ApplicationErrorCode } from "../../../src/errors/applicationErrors.ts";

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

function erro(codigo: string, mensagem: string, status: number): Response {
  return json({ error: { code: codigo, message: mensagem } }, status);
}

/** Erro devolvido pelo executor de RPC (nunca exposto cru ao cliente). */
export interface ErroRpcAvaliacao {
  code?: string;
  message?: string;
}

export interface ResultadoRpcAvaliacao {
  readonly data?: unknown;
  readonly error?: ErroRpcAvaliacao | null;
}

/** Payload já validado e autorizado, pronto para execução privilegiada. */
export interface ExecucaoAvaliacao {
  readonly operacao: OperacaoAvaliacao;
  readonly organizationId: string;
  readonly evaluationId: string;
  readonly evaluatedCollaboratorId: string;
  readonly cycleId: string | null;
  /**
   * CORREÇÃO DE AUDITORIA (IDOR): NÃO existe ocorrência escolhida pelo cliente.
   * A ocorrência editável é resolvida dentro da RPC a partir do ator
   * autenticado (`actorUserProfileId`), com revalidação de tenant, vínculo
   * (F5-02) e vigência. O payload do browser nunca a seleciona.
   */
  readonly escopo: "CRITERIO" | "FINAL" | null;
  readonly criterionId: string | null;
  readonly texto: string | null;
  readonly motivo: string | null;
  readonly notas: readonly { readonly subcriterion_id: string; readonly nota: number }[];
  /**
   * Matrícula do avaliado (INTENÇÃO da tela legada). A fronteira confiável
   * resolve para `evaluatedCollaboratorId` (UUID) via F3-01 antes da RPC.
   */
  readonly matriculaAvaliado: number | string | null;
  /** Ano/ciclo pretendidos (INTENÇÃO) na resolução do ciclo soberano. */
  readonly ano: number | null;
  readonly numero: number | null;
  /** `auth.uid()` VERIFICADO server-side — nunca do corpo. */
  readonly actorUserProfileId: string;
}

export interface ResultadoRelatorioSoberano {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly scope: "DESCENDANTS";
  readonly colaboradores: readonly {
    readonly collaboratorId: string;
    readonly nome: string;
    readonly positionId: string;
    readonly status: string | null;
    readonly evaluationId: string | null;
    readonly evaluationStatus: string | null;
    readonly notaMedia: number | null;
    readonly dataConclusao: string | null;
  }[];
}

export interface DepsAvaliacoes {
  /** Resolve a identidade soberana a partir do JWT via `auth.getUser`. */
  resolveCaller(authHeader: string): Promise<string | null>;
  /**
   * Executa o Policy Engine na fronteira confiável (ActorContext real +
   * ResourceContext real + capabilities×scopes). Devolve `null` quando a
   * operação é PERMITIDA e o código público quando é NEGADA.
   */
  avaliarAutorizacao(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
    readonly operacao: OperacaoAvaliacao;
    readonly alvo: { readonly type: "evaluation" | "collaborator"; readonly id: string };
    readonly cycleId?: string;
    readonly dataNegocio?: unknown;
  }): Promise<{ readonly allowed: boolean; readonly code?: ApplicationErrorCode }>;
  /** Autoriza a coleção por report.read + alvos estruturais resolvidos no servidor. */
  avaliarRelatorio?(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
  }): Promise<{ readonly allowed: boolean; readonly code?: ApplicationErrorCode }>;
  /** Executa a RPC `evaluation_*` com credencial privilegiada e ator verificado. */
  executarRpc(execucao: ExecucaoAvaliacao): Promise<ResultadoRpcAvaliacao>;
  executarRelatorio?(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
    readonly cycleId: string;
  }): Promise<{ readonly data?: ResultadoRelatorioSoberano; readonly error?: ErroRpcAvaliacao | null }>;
  /**
   * Autoriza a DESCOBERTA da avaliação do colaborador no ciclo (OR explícito de
   * `evaluation.create` ∨ `evaluation.write` ∨ `evaluation.read`, decidido no
   * Policy Engine contra a avaliação carregada server-side). Nenhuma capability
   * nova; a decisão de EDIÇÃO vem exclusivamente do ramo `evaluation.write`.
   */
  avaliarDescoberta?(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
    readonly cycleId: string;
    readonly alvo: { readonly type: "collaborator"; readonly id: string };
  }): Promise<{ readonly allowed: boolean; readonly code?: ApplicationErrorCode }>;
  /** Payload mínimo da descoberta (id soberano + status + poder editar). */
  executarDescoberta?(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
    readonly cycleId: string;
    readonly evaluatedCollaboratorId: string;
  }): Promise<{
    readonly data?: DescobertaAvaliacaoDoColaborador | null;
    readonly error?: ErroRpcAvaliacao | null;
  }>;
  /**
   * F6 Incremento 1 (R2): autoriza a LEITURA COLETIVA dos participantes.
   *
   * O caminho (`probeLeituraColetiva` + entitlements) é determinado
   * EXCLUSIVAMENTE pela operação confiável da Edge — NUNCA por input do cliente.
   * Exige ocorrência materializada vigente E (`evaluation.write` com scope do
   * papel OU `evaluation.read + ASSIGNED`). Concede LEITURA apenas: nenhuma
   * escrita é liberada por este caminho.
   */
  avaliarPainelParticipantes?(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<{ readonly allowed: boolean; readonly code?: ApplicationErrorCode }>;
  /** Executa a RPC da projeção COLETIVA (R2) com credencial privilegiada. */
  executarPainelParticipantes?(entrada: {
    readonly authUserId: string;
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<{
    readonly data?: PainelParticipantesAvaliacao | null;
    readonly error?: ErroRpcAvaliacao | null;
  }>;
  /**
   * Resolve a matrícula (INTENÇÃO da tela) para o UUID do colaborador avaliado,
   * na fronteira confiável (ponte F3-01). Necessária em `criar` e
   * `resolver_ciclo`, porque o alvo autorizável precisa ser o UUID soberano.
   * Ausente ⇒ a operação que depende dela é recusada (fail-closed).
   */
  resolverMatricula?(
    matricula: number | string,
    organizationId: string
  ): Promise<string | null>;
}

function codigoPublico(valor: string | undefined): CodigoPublico {
  switch (valor) {
    case "FORBIDDEN":
    case "NOT_FOUND":
    case "CONFLICT":
    case "INVALID_INPUT":
    case "INTERNAL":
    case "NOT_AUTHORIZED":
      return valor;
    default:
      return "FORBIDDEN";
  }
}

function statusCodigo(codigo: CodigoPublico): number {
  switch (codigo) {
    case "INVALID_INPUT": return 400;
    case "NOT_AUTHORIZED": return 403;
    case "NOT_FOUND": return 404;
    case "CONFLICT": return 409;
    case "INTERNAL": return 500;
    default: return 403;
  }
}

function codigoErroExecutor(erroRpc: ErroRpcAvaliacao): CodigoPublico {
  if (erroRpc.code === "INVALID_INPUT" || erroRpc.code === "NOT_AUTHORIZED" || erroRpc.code === "NOT_FOUND" || erroRpc.code === "CONFLICT" || erroRpc.code === "INTERNAL") {
    return erroRpc.code;
  }
  if (erroRpc.code?.startsWith("P") || erroRpc.message?.includes("CONFLICT") || erroRpc.message?.includes("F5-06:")) {
    return "CONFLICT";
  }
  return "INTERNAL";
}

export async function avaliacoes(
  req: Request,
  deps: DepsAvaliacoes
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return erro("METHOD_NOT_ALLOWED", "Método não permitido.", 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }

  // 1) identidade soberana.
  const callerId = await deps.resolveCaller(authHeader);
  if (!callerId) {
    return erro("NOT_AUTHORIZED", "Não autorizado.", 401);
  }

  // 2) forma da intenção (nunca autoridade).
  let corpo: unknown;
  try {
    corpo = await req.json();
  } catch {
    return erro("INVALID_INPUT", "Corpo da requisição inválido.", 400);
  }
  const validacao = validarEntradaAvaliacao(corpo);
  if (!validacao.ok) {
    return erro(validacao.code, validacao.message, 400);
  }
  const entrada: EntradaAvaliacao = validacao.entrada;

  if (entrada.operacao === "report.listar") {
    if (!deps.avaliarRelatorio || !deps.executarRelatorio) {
      return erro("INTERNAL", "Operação não disponível.", 500);
    }
    const autorizacao = await deps.avaliarRelatorio({
      authUserId: callerId,
      organizationId: entrada.organization_id,
    });
    if (!autorizacao.allowed) {
      const code = codigoPublico(autorizacao.code);
      return erro(code, "Operação negada.", code === "NOT_FOUND" ? 404 : 403);
    }
    const resultado = await deps.executarRelatorio({
      authUserId: callerId,
      organizationId: entrada.organization_id,
      cycleId: entrada.cycle_id!,
    });
    if (resultado.error) {
      const code = codigoPublico(resultado.error.code);
      return erro(code, "Relatório indisponível.", code === "NOT_FOUND" ? 404 : 409);
    }
    return json({ ok: true, operacao: entrada.operacao, resultado: resultado.data ?? null }, 200);
  }

  // Descoberta soberana da avaliação do colaborador no ciclo: LEITURA gated pelo
  // OR explícito (create ∨ write ∨ read). Decisão ANTES da resposta; nenhum id
  // de avaliação vem do cliente e `podeEditar` é decidido no ramo `write`.
  if (entrada.operacao === "evaluation.do_colaborador_no_ciclo") {
    if (!deps.avaliarDescoberta || !deps.executarDescoberta) {
      return erro("INTERNAL", "Operação não disponível.", 500);
    }
    const alvoDescoberta = entrada.alvo;
    if (!alvoDescoberta || alvoDescoberta.type !== "collaborator") {
      return erro("INVALID_INPUT", "Alvo inválido.", 400);
    }
    const cycleId = entrada.cycle_id;
    if (!cycleId) {
      return erro("INVALID_INPUT", "cycle_id obrigatório.", 400);
    }

    const autorizacao = await deps.avaliarDescoberta({
      authUserId: callerId,
      organizationId: entrada.organization_id,
      cycleId,
      alvo: { type: "collaborator", id: alvoDescoberta.id },
    });
    if (!autorizacao.allowed) {
      const code = codigoPublico(autorizacao.code);
      return erro(code, "Operação negada.", code === "NOT_FOUND" ? 404 : 403);
    }

    const resultado = await deps.executarDescoberta({
      authUserId: callerId,
      organizationId: entrada.organization_id,
      cycleId,
      evaluatedCollaboratorId: alvoDescoberta.id,
    });
    if (resultado.error) {
      const code = codigoErroExecutor(resultado.error);
      return erro(code, "Descoberta indisponível.", statusCodigo(code));
    }
    if (!resultado.data) return erro("INTERNAL", "Descoberta indisponível.", 500);

    return json(
      {
        ok: true,
        operacao: entrada.operacao,
        resultado: resultado.data,
      },
      200
    );
  }

  // Leitura COLETIVA dos participantes (R2): identidades/papéis dos demais,
  // notas individuais EXISTENTES, comentários por critério e Feedbacks Finais
  // existentes dos papéis que os possuem, além de progresso FACTUAL. A operação
  // é de LEITURA — a concessão nunca libera escrita em estado algum.
  if (entrada.operacao === "evaluation.painel_participantes") {
    if (!deps.avaliarPainelParticipantes || !deps.executarPainelParticipantes) {
      return erro("INTERNAL", "Operação não disponível.", 500);
    }
    const alvoColetivo = entrada.alvo;
    if (!alvoColetivo || alvoColetivo.type !== "evaluation") {
      return erro("INVALID_INPUT", "Alvo inválido.", 400);
    }

    const autorizacao = await deps.avaliarPainelParticipantes({
      authUserId: callerId,
      organizationId: entrada.organization_id,
      evaluationId: alvoColetivo.id,
    });
    if (!autorizacao.allowed) {
      const code = codigoPublico(autorizacao.code);
      return erro(code, "Operação negada.", code === "NOT_FOUND" ? 404 : 403);
    }

    const resultado = await deps.executarPainelParticipantes({
      authUserId: callerId,
      organizationId: entrada.organization_id,
      evaluationId: alvoColetivo.id,
    });
    if (resultado.error) {
      const code = codigoErroExecutor(resultado.error);
      return erro(code, "Leitura coletiva indisponível.", statusCodigo(code));
    }
    // Payload ausente após ALLOW é inconsistência: falha fechado sem revelar
    // existência de terceiros.
    if (!resultado.data) return erro("INTERNAL", "Leitura coletiva indisponível.", 500);

    return json({ ok: true, operacao: entrada.operacao, resultado: resultado.data }, 200);
  }

  // 2.1) Alvo SOBERANO: quando a tela informa a MATRÍCULA do avaliado (criação e
  // resolução de ciclo), a fronteira confiável a resolve para o UUID (ponte
  // F3-01) ANTES do Policy Engine — o alvo autorizável é o colaborador
  // resolvido, nunca um valor enviado pelo cliente. Sem resolução ⇒ recusa.
  let alvoDaOperacao = entrada.alvo!;
  const operacaoComMatricula =
    entrada.operacao === "evaluation.criar" ||
    entrada.operacao === "evaluation.resolver_ciclo";

  if (operacaoComMatricula && entrada.matricula_avaliado !== undefined && entrada.matricula_avaliado !== null) {
    const resolvido = await deps.resolverMatricula?.(
      entrada.matricula_avaliado,
      entrada.organization_id
    );
    if (!resolvido) {
      return erro(
        "INVALID_INPUT",
        "Colaborador avaliado não resolvido para a matrícula informada.",
        400
      );
    }
    alvoDaOperacao = { type: "collaborator", id: resolvido };
  }

  // 3) Policy Engine (capability × scope × recurso REAL).
  const decisao = await deps.avaliarAutorizacao({
    authUserId: callerId,
    organizationId: entrada.organization_id,
    operacao: entrada.operacao,
    alvo: alvoDaOperacao,
    ...(entrada.cycle_id ? { cycleId: entrada.cycle_id } : {}),
  });
  if (!decisao.allowed) {
    const code = codigoPublico(decisao.code);
    const status = code === "NOT_FOUND" ? 404 : code === "CONFLICT" ? 409 : 403;
    return erro(code, "Operação negada.", status);
  }

  // 4) execução privilegiada com o ator VERIFICADO.
  const resultado = await deps.executarRpc({
    operacao: entrada.operacao,
    organizationId: entrada.organization_id,
    evaluationId: alvoDaOperacao.id,
    evaluatedCollaboratorId: alvoDaOperacao.id,
    cycleId: entrada.cycle_id ?? null,
    escopo: entrada.escopo ?? null,
    criterionId: entrada.criterion_id ?? null,
    texto: entrada.texto ?? null,
    motivo: entrada.motivo ?? null,
    notas: entrada.notas ?? [],
    matriculaAvaliado: entrada.matricula_avaliado ?? null,
    ano: entrada.ano ?? null,
    numero: entrada.numero ?? null,
    actorUserProfileId: callerId,
  });

  if (resultado.error) {
    const code = codigoErroExecutor(resultado.error);
    if (code !== "CONFLICT") {
      const message = code === "INVALID_INPUT"
        ? "Dados da requisicao invalidos."
        : code === "NOT_FOUND"
          ? "Recurso nao encontrado."
          : code === "INTERNAL"
            ? "Erro interno."
            : "Operacao negada.";
      return erro(code, message, statusCodigo(code));
    }
    // A operação FOI autorizada; a recusa vem do domínio (estado, completude,
    // vínculo, ocorrência não vigente). Resposta genérica de conflito — a
    // mensagem interna do banco nunca é exposta ao cliente.
    return erro("CONFLICT", "Operação recusada pelo estado atual da avaliação.", 409);
  }

  return json({ ok: true, operacao: entrada.operacao, resultado: resultado.data ?? null }, 200);
}

/** Exposto para testes de contrato da lista de operações. */
export { CAPABILITY_POR_OPERACAO, ehOperacaoAvaliacao };
