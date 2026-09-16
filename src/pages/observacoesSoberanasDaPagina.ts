/**
 * F5-11 P5 (Issue #250), L4 — APRESENTAÇÃO soberana das observações do
 * colaborador-alvo (detalhe do gestor).
 *
 * Este módulo é a fronteira de APRESENTAÇÃO do cutover:
 * - recebe a projeção SOBERANA da porta (`ObservacaoSoberana`) e o UUID
 *   `collaborator_id` do alvo; nada de matrícula, nome, ano ou ciclo é tratado
 *   como identidade (D1/D3);
 * - a identidade de cada item é o UUID da linha (`id`) e a chave de recorte é o
 *   `collaboratorId` do alvo — o servidor já entregou SOMENTE o que o escopo
 *   autoriza (o cliente não reaplica regra de autorização);
 * - o AUTOR é um rótulo de apresentação resolvido por PARÂMETRO, a partir dos
 *   colaboradores que a página JÁ carregou (mesma doutrina do mapeador de UI,
 *   L2): UUID de autor ausente no mapa ⇒ rótulo explicitamente ausente — nunca o
 *   UUID cru, nunca nome/matrícula inventados;
 * - NÃO há leitura de acervo do navegador nem de armazenamento local: a única
 *   fonte é a lista soberana recebida por parâmetro (D13).
 *
 * Nada aqui decide autorização, tenant ou escopo: o ESCOPO é intenção enviada à
 * porta e revalidado server-side.
 */

import type { ObservacaoSoberana } from "../application/ports/ObservationRepository";

/** Rótulos de autor por UUID — dado de OUTRA superfície soberana já carregada. */
export interface MapaDeNomesDeColaborador {
  readonly [collaboratorId: string]: string | undefined;
}

/** Rótulo explícito quando o autor não está entre os colaboradores carregados. */
export const AUTOR_NAO_IDENTIFICADO =
  "Autor não identificado na estrutura carregada";

/**
 * Estado da leitura soberana das observações do alvo. Ausência de dados é
 * EXPLÍCITA (`pronta` com lista vazia); falha é `indisponivel` — nunca lista
 * vazia silenciosa e nunca fallback local.
 */
export type EstadoObservacoesSoberanas =
  | { readonly fase: "carregando" }
  | { readonly fase: "indisponivel"; readonly mensagem: string }
  | {
      readonly fase: "pronta";
      readonly observacoes: readonly ObservacaoSoberana[];
    };

/** Contagem por tipo (os três tipos do domínio; nenhum tipo é inventado). */
export interface ResumoDeObservacoesPorTipo {
  readonly positivas: number;
  readonly neutras: number;
  readonly negativas: number;
}

/** Item de apresentação de UMA observação do alvo. */
export interface ObservacaoDoAlvo {
  readonly id: string;
  readonly tipo: ObservacaoSoberana["tipo"];
  readonly texto: string;
  readonly comunicado: boolean;
  readonly criadoEm: string;
  /** Rótulo do autor; `null` = autor fora dos colaboradores carregados. */
  readonly autorNome: string | null;
}

/**
 * Observações do colaborador-ALVO, na ordem soberana recebida. O recorte é por
 * `collaboratorId` (UUID) — o servidor já aplicou o escopo; nada é filtrado por
 * matrícula, nome, ano ou ciclo.
 */
export function observacoesDoAlvo(
  observacoes: readonly ObservacaoSoberana[],
  collaboratorId: string | null,
  nomesDeColaborador: MapaDeNomesDeColaborador = {}
): readonly ObservacaoDoAlvo[] {
  if (!collaboratorId) return [];
  return observacoes
    .filter((observacao) => observacao.collaboratorId === collaboratorId)
    .map((observacao) => ({
      id: observacao.id,
      tipo: observacao.tipo,
      texto: observacao.texto,
      comunicado: observacao.comunicado,
      criadoEm: observacao.criadoEm,
      autorNome: observacao.autorCollaboratorId
        ? nomesDeColaborador[observacao.autorCollaboratorId] ?? null
        : null,
    }));
}

/** Contagem por tipo do recorte exibido. */
export function resumoDeObservacoesPorTipo(
  observacoes: readonly ObservacaoDoAlvo[]
): ResumoDeObservacoesPorTipo {
  return observacoes.reduce<ResumoDeObservacoesPorTipo>(
    (total, observacao) => {
      if (observacao.tipo === "POSITIVA") {
        return { ...total, positivas: total.positivas + 1 };
      }
      if (observacao.tipo === "NEGATIVA") {
        return { ...total, negativas: total.negativas + 1 };
      }
      return { ...total, neutras: total.neutras + 1 };
    },
    { positivas: 0, neutras: 0, negativas: 0 }
  );
}

/** Rótulo textual do tipo (apresentação; o domínio permanece o do contrato). */
export function rotuloDoTipo(tipo: ObservacaoSoberana["tipo"]): string {
  if (tipo === "POSITIVA") return "Positiva";
  if (tipo === "NEGATIVA") return "Negativa";
  return "Neutra";
}

/** Data da observação em pt-BR; `—` quando o fato não é uma data válida. */
export function formatarDataDaObservacao(valor: string): string {
  const data = new Date(valor);
  return Number.isNaN(data.getTime()) ? "—" : data.toLocaleDateString("pt-BR");
}
