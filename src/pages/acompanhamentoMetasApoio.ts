/**
 * F5-10 P6 (Issue #220) — APOIO da tela de ACOMPANHAMENTO de metas.
 *
 * Módulo companheiro da `AcompanhamentoMetasPage` (mesmo padrão de
 * `painelCicloStatus.ts`/`painelCicloAvaliacaoAction.ts`/`apoioEstrutura.ts`):
 * as decisões PURAS e as mensagens públicas vivem aqui para que a página exporte
 * apenas o componente (`react-refresh/only-export-components`).
 *
 * Nada aqui decide autorização: `funcao`, `gestorDiretoMatricula`, `localWorld`,
 * `can()`, `metaStorage` e `localStorage` não participam de nenhuma destas
 * funções. A autoridade continua sendo a relação CONGELADA (`relacao`) devolvida
 * pela superfície soberana, e o estado de aprovação é FATO da projeção — a UI
 * não reconstrói a regra de exigência.
 *
 * Este módulo NÃO importa a página (nem em runtime nem por tipo): o fluxo de
 * dependência é sempre página → companheiro.
 */

import type {
  AprovacaoSoberana,
  ErroMetasSoberanos,
  MetaSoberana,
  RelacaoMetaSoberana,
} from "../application/ports/GoalRepository";
import type { PapelAprovacaoMeta } from "../infrastructure/supabase/metas/contrato";

/** Mensagens públicas da tela (nenhuma mensagem crua do banco é inventada). */
export const ERRO_SEM_CAMINHO =
  "O caminho soberano de metas não está disponível neste ambiente.";
export const ERRO_SEM_ORGANIZACAO =
  "Selecione uma organização ativa para consultar metas.";
export const ERRO_CICLO_NAO_RESOLVIDO =
  "Não foi possível resolver o ciclo informado pelo caminho soberano.";
export const ERRO_OPERACAO = "Não foi possível concluir a operação de metas.";
export const ERRO_CONFLITO =
  "A meta foi alterada por outra pessoa. Os dados foram atualizados; revise e tente novamente.";


/**
 * Mensagem pública da falha. Os códigos são os do contrato (`CodigoPublico`) e a
 * mensagem do backend nunca é inventada: quando o código não tem texto próprio,
 * vale a mensagem pública devolvida pela fronteira.
 */
export function mensagemDoErro(erro: ErroMetasSoberanos, padrao: string): string {
  if (erro.code === "CONFLICT") return ERRO_CONFLITO;
  if (erro.code === "INVALID_INPUT") {
    return "O ciclo ou a meta informados são inválidos.";
  }
  if (erro.code === "FORBIDDEN" || erro.code === "NOT_AUTHORIZED") {
    return "Você não tem autorização para esta operação de metas.";
  }
  if (erro.code === "NOT_FOUND") {
    return "A meta não foi encontrada neste ciclo.";
  }
  return erro.message?.trim() ? erro.message : padrao;
}

/** Estado de aprovação de um papel na PROJEÇÃO (a UI não reconstrói a regra). */
export function aprovacaoDoPapel(
  meta: MetaSoberana,
  papel: PapelAprovacaoMeta
): AprovacaoSoberana | undefined {
  return meta.aprovacoes.find((aprovacao) => aprovacao.papel === papel);
}

/** Meta formalmente aprovada: TODOS os papéis EXIGIDOS estão vigentes. */
export function metaFormalmenteAprovada(meta: MetaSoberana): boolean {
  return meta.aprovacoes.every(
    (aprovacao) => !aprovacao.exigida || aprovacao.vigente
  );
}

/**
 * Papel aprovador DERIVADO da relação CONGELADA de UMA meta.
 *
 * A relação é propriedade da META: no MESMO ciclo o ator pode ser o aprovador
 * GERENTE_CONELADO de uma meta e o aprovador COORDENADOR_CONGELADO de outra.
 * Por isso NUNCA existe "papel do ator" global para o conjunto de metas — era
 * exatamente o achado MEDIUM da auditoria do PR #228. `SELF` não habilita
 * aprovação nenhuma.
 */
export function papelAprovadorDaRelacao(
  relacao: RelacaoMetaSoberana
): PapelAprovacaoMeta | null {
  if (relacao === "APROVADOR_GERENTE_CONGELADO") return "GERENTE";
  if (relacao === "APROVADOR_COORDENADOR_CONGELADO") return "COORDENADOR";
  return null;
}

/** A relação CONGELADA autoriza o ator a aprovar por ESTE papel NESTA meta? */
export function relacaoAutorizaPapel(
  relacao: RelacaoMetaSoberana,
  papel: PapelAprovacaoMeta
): boolean {
  return papelAprovadorDaRelacao(relacao) === papel;
}

/**
 * Pendência ACIONÁVEL do perfil PARA ESTA META, derivada da relação CONGELADA da
 * própria meta — nunca de um papel global do conjunto de metas.
 */
export function pendenteDoPerfil(meta: MetaSoberana): boolean {
  const papel = papelAprovadorDaRelacao(meta.relacao);
  if (papel === null) return false;
  const aprovacao = aprovacaoDoPapel(meta, papel);
  return Boolean(aprovacao?.exigida) && !aprovacao?.vigente;
}
