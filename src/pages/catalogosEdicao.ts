/**
 * F5-08 P4 (correção do BLOCKER 2) — confirmação de edição de CATÁLOGO.
 *
 * Módulo sem React para que a decisão seja testável com a porta injetada:
 *
 * - `expectedVersion` vem SEMPRE da fotografia soberana CORRENTE — jamais de um
 *   default sintético (`0`, `1`, versão derivada);
 * - se a entidade em edição não está mais na leitura atual, NADA é enviado à
 *   Edge: devolve `fotografia-desatualizada` (código/mensagem públicos) e o
 *   chamador recarrega a fotografia e exibe o estado desatualizado;
 * - nenhuma regra de autorização ou de domínio é decidida aqui: a concorrência
 *   real continua no servidor (`CONFLICT`) e a autorização na Edge (D19).
 */

import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import {
  alterarStatusCargo,
  alterarStatusSenioridade,
  renomearCargo,
  renomearSenioridade,
  type DependenciasAcessoColaboradores,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import { decidirVersaoOtimista } from "./apoioEstrutura";

/** Edição de catálogo como INTENÇÃO (sem estado de React). */
export interface EdicaoCatalogo {
  readonly tipo: "cargo" | "senioridade";
  readonly id: string;
  readonly acao: "renomear" | "status";
  readonly statusAtual: string;
}

export interface EntradaConfirmarEdicaoCatalogo {
  readonly estrutura: EstruturaSoberana;
  readonly edicao: EdicaoCatalogo;
  readonly nome: string;
  readonly motivo: string;
  readonly operationId: string;
  readonly organizationId?: string | null;
}

export type DesfechoEdicaoCatalogo =
  | { readonly tipo: "sem-motivo" }
  | {
      readonly tipo: "fotografia-desatualizada";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | { readonly tipo: "concluida"; readonly resultado: ResultadoColaboradores<unknown> };

/**
 * Confirma uma edição de catálogo a partir da fotografia CORRENTE.
 *
 * Proteção LOCAL (fail-closed) exigida pelo contrato do P4: `expectedVersion` só
 * pode vir da fotografia soberana. Se o item em edição não está mais na leitura
 * atual, NADA é enviado à Edge — devolve `fotografia-desatualizada` com código e
 * mensagem públicos, e o chamador recarrega a leitura. Jamais um default
 * sintético (`0`, `1`, versão derivada) é enviado. A decisão real de
 * concorrência continua no servidor (`CONFLICT`).
 */
export async function confirmarEdicaoCatalogo(
  entrada: EntradaConfirmarEdicaoCatalogo,
  deps: DependenciasAcessoColaboradores = {}
): Promise<DesfechoEdicaoCatalogo> {
  if (!entrada.motivo.trim()) return { tipo: "sem-motivo" };

  const fotografia =
    entrada.edicao.tipo === "cargo"
      ? entrada.estrutura.cargos.map((cargo) => ({
          id: cargo.jobRoleId,
          version: cargo.version,
        }))
      : entrada.estrutura.senioridades.map((senioridade) => ({
          id: senioridade.seniorityLevelId,
          version: senioridade.version,
        }));

  const decisao = decidirVersaoOtimista(fotografia, entrada.edicao.id);
  if (decisao.tipo === "fotografia-desatualizada") {
    return {
      tipo: "fotografia-desatualizada",
      codigo: decisao.codigo,
      mensagem: decisao.mensagem,
    };
  }

  const status: "active" | "disabled" =
    entrada.edicao.statusAtual === "active" ? "disabled" : "active";
  const comum = {
    operationId: entrada.operationId,
    expectedVersion: decisao.expectedVersion,
    motivo: entrada.motivo.trim(),
    ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
  };

  const resultado: ResultadoColaboradores<unknown> =
    entrada.edicao.tipo === "cargo"
      ? entrada.edicao.acao === "renomear"
        ? await renomearCargo(
            { ...comum, jobRoleId: entrada.edicao.id, nome: entrada.nome.trim() },
            deps
          )
        : await alterarStatusCargo({ ...comum, jobRoleId: entrada.edicao.id, status }, deps)
      : entrada.edicao.acao === "renomear"
        ? await renomearSenioridade(
            { ...comum, seniorityLevelId: entrada.edicao.id, nome: entrada.nome.trim() },
            deps
          )
        : await alterarStatusSenioridade(
            { ...comum, seniorityLevelId: entrada.edicao.id, status },
            deps
          );

  return { tipo: "concluida", resultado };
}
