/**
 * LEGACY / TRANSITÓRIO (F5-09 P5) — **NÃO** é o caminho soberano de leitura.
 *
 * Este adapter existe apenas para os consumidores que AINDA leem o ciclo pelo
 * `localStorage` (`cicloAvaliacaoStorage`) e cujo cutover pertence ao P8. Ele:
 *
 * - **não é fallback** do adapter soberano
 *   (`src/infrastructure/supabase/ciclos/repositorioCiclosSoberanos.ts`): o
 *   caminho produtivo nunca cai para cá em caso de erro/sessão ausente;
 * - **não é dual-read**: nenhum módulo escolhe silenciosamente entre local e
 *   servidor;
 * - **não declara tenant**: o mundo legado não tem organização; a projeção usa a
 *   organização PEDIDA pelo chamador apenas como intenção de bridge (jamais como
 *   prova/evidência de tenant — isso é responsabilidade da RLS no caminho
 *   soberano);
 * - **não tem versão otimista**: o `version` devolvido é o sentinela `0`
 *   ("legado, sem versão"), que NÃO pode ser usado como `expected_version` de
 *   mutação soberana;
 * - **não cria/edita ciclo**: a porta é de leitura; as mutações são das RPCs
 *   P2–P4 pela fronteira autorizada (P7/P8).
 *
 * Remoção prevista: cutover do P8 (auditoria §2, classificação "A — autoridade
 * local").
 */

import type {
  CicloSoberano,
  CycleRepository,
  NumeroCiclo,
  ResultadoCiclos,
} from "../../application/ports/CycleRepository";
import type { CicloAvaliacao } from "../../types/CicloAvaliacao";
import { getCicloAtivo, getCiclosAvaliacao } from "../../services/cicloAvaliacaoStorage";

const ERRO_LEGADO = "Leitura local (LEGACY) indisponível.";

/** Número do ciclo restrito ao domínio fechado (1..3); fora dele, descarta. */
function numeroLegado(valor: unknown): NumeroCiclo | null {
  return valor === 1 || valor === 2 || valor === 3 ? valor : null;
}

/**
 * Projeta o ciclo local na projeção soberana. `null` quando o registro legado é
 * inválido (nunca inventa identidade/valores).
 */
function projetarLegado(ciclo: CicloAvaliacao, organizationId: string): CicloSoberano | null {
  const numero = numeroLegado(ciclo?.ciclo);
  if (typeof ciclo?.id !== "string" || ciclo.id.length === 0 || numero === null) return null;
  return {
    id: ciclo.id,
    organizationId,
    ano: ciclo.ano,
    numero,
    status: ciclo.status,
    dataInicio: ciclo.dataInicio ?? null,
    dataFim: ciclo.dataFim ?? null,
    dataAtivacao: ciclo.dataAtivacao ?? null,
    dataEncerramento: ciclo.dataEncerramento ?? null,
    encerradoComPendencias: ciclo.encerradoComPendencias ?? false,
    quantidadePendencias: ciclo.quantidadePendencias ?? 0,
    // Sentinela de LEGADO: o storage local não possui versão otimista.
    version: 0,
    criadoEm: ciclo.dataCriacao,
    atualizadoEm: ciclo.dataUltimaAtualizacao,
  };
}

function falhaLegado<T>(): ResultadoCiclos<T> {
  return { ok: false, error: { code: "INTERNAL", message: ERRO_LEGADO } };
}

export const localCycleRepository: CycleRepository = {
  async listarCiclos(organizationId) {
    try {
      const projecao = getCiclosAvaliacao()
        .map((ciclo) => projetarLegado(ciclo, organizationId))
        .filter((ciclo): ciclo is CicloSoberano => ciclo !== null);
      return { ok: true, data: projecao };
    } catch {
      return falhaLegado();
    }
  },

  async obterCiclo(organizationId, cycleId) {
    try {
      const encontrado = getCiclosAvaliacao().find((ciclo) => ciclo.id === cycleId);
      return { ok: true, data: encontrado ? projetarLegado(encontrado, organizationId) : null };
    } catch {
      return falhaLegado();
    }
  },

  async obterCicloAtivo(organizationId) {
    try {
      const ativo = getCicloAtivo();
      return { ok: true, data: ativo ? projetarLegado(ativo, organizationId) : null };
    } catch {
      return falhaLegado();
    }
  },
};
