/**
 * F5-10 P6 (Issue #220) — apoio PURO da tela "Minhas Metas".
 *
 * Módulo COMPANHEIRO de `MinhasMetasPage.tsx`, no padrão do repositório
 * (`painelCicloStatus.ts`, `painelCicloAvaliacaoAction.ts`, `apoioEstrutura.ts`,
 * `confirmarCorrecaoPeriodoCiclo.ts`): a página exporta o COMPONENTE e os tipos
 * do seu estado; todo auxiliar de RUNTIME vive aqui.
 *
 * Nada neste módulo concede autoridade, tenant, papel ou estado:
 * - `relacao`, `exigida`, `vigente` e `limites` são FATOS da projeção soberana e
 *   são apenas LIDOS (a regra de exigência de aprovação e a quota do ciclo não
 *   são reconstruídas aqui);
 * - `operationId` é CHAVE DE IDEMPOTÊNCIA de uma tentativa lógica (D11), jamais
 *   identidade de meta — o id canônico é atribuído pelo banco;
 * - nenhum caminho local, dual-read, cache de decisão ou armazenamento do
 *   navegador existe nesta superfície.
 *
 * Este módulo NÃO importa a página (nem em runtime, nem em tipo): a dependência
 * é sempre `MinhasMetasPage.tsx` → `minhasMetasApoio.ts`.
 */

import type {
  AprovacaoSoberana,
  ErroMetasSoberanos,
  LimiteSoberano,
  MetaSoberana,
} from "../application/ports/GoalRepository";
import type {
  PapelAprovacaoMeta,
  TipoMetaSoberana,
} from "../infrastructure/supabase/metas/contrato";
import type { ColaboradorSoberano } from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";

/**
 * Mensagem do 409: o conflito é de CONCORRÊNCIA (a linha mudou no servidor), não
 * uma falha do usuário — a tela diz o que aconteceu e que a lista foi relida.
 */
export const MENSAGEM_CONFLITO =
  "A meta foi alterada por outra sessão desde esta leitura. A lista foi recarregada com o estado do servidor: revise os dados e repita a ação.";

/** Identidade soberana do dono das metas (UUID) + rótulos de apresentação. */
export interface IdentidadeDasMinhasMetas {
  readonly colaboradorId: string;
  readonly matricula: string;
  readonly nome: string;
}

/**
 * `operation_id` (idempotência, D11) — NUNCA identidade de meta: o id canônico é
 * atribuído pelo banco (`evaluation_goals.id`). Este valor só evita que a mesma
 * intenção seja aplicada duas vezes.
 */
function novoOperationId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (caractere) => {
    const aleatorio = Math.floor(Math.random() * 16);
    const valor = caractere === "x" ? aleatorio : (aleatorio & 0x3) | 0x8;
    return valor.toString(16);
  });
}

export interface RegistroDeTentativas {
  /** Id de idempotência da tentativa lógica; a MESMA chave devolve o MESMO id. */
  idDa(chave: string): string;
  /** Encerra a tentativa: a próxima ação com a mesma chave gera um id NOVO. */
  encerrar(chave: string): void;
}

/**
 * Registro de tentativas lógicas. A chave identifica a intenção COMPLETA
 * (operação + alvo + `expectedVersion` + conteúdo): retry da mesma tentativa
 * reutiliza o `operationId` (seguro por idempotência); qualquer alteração — ou
 * uma nova ação depois de concluída — gera um id diferente.
 */
export function criarRegistroDeTentativas(): RegistroDeTentativas {
  const tentativas = new Map<string, string>();
  return {
    idDa(chave) {
      const existente = tentativas.get(chave);
      if (existente !== undefined) return existente;
      const novo = novoOperationId();
      tentativas.set(chave, novo);
      return novo;
    },
    encerrar(chave) {
      tentativas.delete(chave);
    },
  };
}

/** Chave da tentativa lógica (nunca usada como identidade de meta). */
export function chaveDaTentativa(
  partes: readonly (string | number | boolean | null)[]
): string {
  return partes.map((parte) => (parte === null ? "" : String(parte))).join("|");
}

/** Quota do CICLO/tipo; AUSÊNCIA de linha = quota ZERO (fail-closed, §5). */
export function limiteDoTipo(
  limites: readonly LimiteSoberano[],
  tipo: TipoMetaSoberana
): number {
  return limites.find((limite) => limite.tipo === tipo)?.quantidade ?? 0;
}

/**
 * Metas do ATOR que participam da tela e da quota: relação `SELF` (FATO do
 * servidor) e não excluídas (exclusão lógica não consome quota).
 */
export function metasDoAtor(metas: readonly MetaSoberana[]): readonly MetaSoberana[] {
  return metas.filter((meta) => meta.relacao === "SELF" && !meta.excluida);
}

/** Aprovação do papel (a projeção traz SEMPRE os dois papéis). */
export function aprovacaoDoPapel(
  meta: MetaSoberana,
  papel: PapelAprovacaoMeta
): AprovacaoSoberana | undefined {
  return meta.aprovacoes.find((aprovacao) => aprovacao.papel === papel);
}

/**
 * Meta aprovada = TODOS os papéis EXIGIDOS estão vigentes. `exigida` é FATO do
 * servidor — a tela não deriva a regra de exigência.
 */
export function metaAprovada(meta: MetaSoberana): boolean {
  return meta.aprovacoes
    .filter((aprovacao) => aprovacao.exigida)
    .every((aprovacao) => aprovacao.vigente);
}

/** Mensagem pública por código (a mensagem crua do banco nunca é exibida). */
export function mensagemDeFalhaDeMetas(erro: ErroMetasSoberanos): string {
  switch (erro.code) {
    case "FORBIDDEN":
    case "NOT_AUTHORIZED":
      return "Você não tem permissão para esta operação.";
    case "NOT_FOUND":
      return "Meta ou ciclo não encontrado nesta organização.";
    case "CONFLICT":
    case "INVALID_INPUT":
      // Descrevem a INTENÇÃO do próprio usuário: a mensagem do servidor ajuda.
      return erro.message;
    case "METHOD_NOT_ALLOWED":
      return "Operação indisponível neste ambiente.";
    default:
      return "Não foi possível concluir a operação de meta.";
  }
}

/** Mensagem da operação; o 409 tem texto próprio e dispara refresh soberano. */
export function mensagemDeFalhaDeOperacao(erro: ErroMetasSoberanos): string {
  return erro.code === "CONFLICT" ? MENSAGEM_CONFLITO : mensagemDeFalhaDeMetas(erro);
}

/** Identidade de apresentação derivada da projeção soberana (UUID + rótulos). */
export function identidadeDe(colaborador: ColaboradorSoberano): IdentidadeDasMinhasMetas {
  return {
    colaboradorId: colaborador.collaboratorId,
    matricula: colaborador.matricula ?? "",
    nome: colaborador.fullName,
  };
}
