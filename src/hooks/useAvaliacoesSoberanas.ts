/**
 * F5-06 (Issue #103) — hook reativo do caminho novo de avaliações.
 *
 * Apenas cola entre o React e o CONTROLADOR (`criarControladorAvaliacoes`):
 * nenhuma regra de autorização, cálculo oficial ou persistência vive aqui.
 * Depois de cada mutação o acervo é recarregado do servidor — a autoridade é o
 * banco, nunca o estado local.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  criarControladorAvaliacoes,
  type EstadoAvaliacoesSoberanas,
  type EntradaControladorAvaliacoes,
} from "../services/avaliacoesSoberanas/controladorAvaliacoes.ts";

export type { EstadoAvaliacoesSoberanas };

export interface RetornoUseAvaliacoesSoberanas<Registro = unknown>
  extends EstadoAvaliacoesSoberanas<Registro> {
  readonly recarregar: () => Promise<void>;
}

const ESTADO_INICIAL: EstadoAvaliacoesSoberanas<unknown> = {
  carregando: true,
  erro: null,
  acervo: null,
  avaliacaoSelecionada: null,
};

export function useAvaliacoesSoberanas<Registro = unknown>(
  deps: EntradaControladorAvaliacoes<Registro>
): RetornoUseAvaliacoesSoberanas<Registro> {
  const [estado, setEstado] = useState<EstadoAvaliacoesSoberanas<Registro>>(
    ESTADO_INICIAL as EstadoAvaliacoesSoberanas<Registro>
  );

  const { service, organizationId, cycleId, evaluationIds, ehEditavel } = deps;

  // Mantém os dados mais recentes disponíveis para o controlador SEM recriá-lo:
  // o controlador só é recriado quando muda a identidade da operação.
  const ultimaEntrada = useRef({ evaluationIds, ehEditavel });
  useEffect(() => {
    ultimaEntrada.current = { evaluationIds, ehEditavel };
  }, [evaluationIds, ehEditavel]);

  const controlador = useMemo(
    () =>
      criarControladorAvaliacoes<Registro>({
        service,
        organizationId,
        cycleId,
        evaluationIds,
        ...(ehEditavel ? { ehEditavel } : {}),
        aoMudar: (novo) => setEstado(novo),
      }),
    // Identidade da operação: serviço, tenant, ciclo e ids conhecidos.
    [service, organizationId, cycleId, evaluationIds, ehEditavel]
  );

  useEffect(() => {
    void controlador.carregar({ evaluationIds: ultimaEntrada.current.evaluationIds });
  }, [controlador]);

  const recarregar = useCallback(async () => {
    await controlador.carregar({ evaluationIds: ultimaEntrada.current.evaluationIds });
  }, [controlador]);

  return { ...estado, recarregar };
}
