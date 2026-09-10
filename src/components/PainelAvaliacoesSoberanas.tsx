/**
 * F5-06 (Issue #103) — PAINEL do caminho novo de avaliações (PostgreSQL).
 *
 * Casca fina: monta o SERVICE e o controlador (via hook) e delega a renderização
 * para `ExibicaoAvaliacoesSoberanas` (componente puro). Nenhuma autorização é
 * decidida aqui — `editavel` reflete o estado do domínio, e a decisão de
 * autorização é do Policy Engine na fronteira confiável.
 *
 * O repositório é INJETADO (Supabase em produção; falso nos testes), o que
 * mantém o componente testável sem rede nem variáveis de ambiente.
 */

import { useMemo } from "react";
import { ExibicaoAvaliacoesSoberanas } from "./ExibicaoAvaliacoesSoberanas.tsx";
import {
  criarServiceAvaliacoes,
  type ServiceAvaliacoes,
} from "../services/avaliacoesSoberanas/serviceAvaliacoes.ts";
import { useAvaliacoesSoberanas } from "../hooks/useAvaliacoesSoberanas.ts";
import type { RepositorioAvaliacoes } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";

export interface PainelAvaliacoesSoberanasProps {
  readonly organizationId: string;
  readonly cycleId: string;
  /** Ids técnicos (UUID) das avaliações do ciclo. */
  readonly evaluationIds: readonly string[];
  /** Repositório do caminho novo (injetado: Supabase em produção). */
  readonly repositorio?: RepositorioAvaliacoes;
  /** Registros legados (localStorage) — somente leitura. */
  readonly lerRegistrosLegados?: () => readonly unknown[];
  /** Service pronto (tem precedência sobre `repositorio`). */
  readonly service?: ServiceAvaliacoes<unknown>;
}

export function PainelAvaliacoesSoberanas({
  organizationId,
  cycleId,
  evaluationIds,
  repositorio,
  lerRegistrosLegados,
  service: serviceInjetado,
}: PainelAvaliacoesSoberanasProps) {
  const service = useMemo(() => {
    if (serviceInjetado) return serviceInjetado;
    if (!repositorio) return null;
    return criarServiceAvaliacoes<unknown>({
      repositorio,
      lerRegistrosLegados: lerRegistrosLegados ?? (() => []),
    });
  }, [serviceInjetado, repositorio, lerRegistrosLegados]);

  if (!service) {
    // Sem repositório não existe caminho novo: nada do legado é lido por engano.
    return (
      <ExibicaoAvaliacoesSoberanas
        estado={{
          carregando: false,
          erro: "Caminho de avaliações no PostgreSQL indisponível neste ambiente.",
          acervo: null,
          avaliacaoSelecionada: null,
        }}
      />
    );
  }

  return (
    <PainelComService
      service={service}
      organizationId={organizationId}
      cycleId={cycleId}
      evaluationIds={evaluationIds}
    />
  );
}

function PainelComService({
  service,
  organizationId,
  cycleId,
  evaluationIds,
}: {
  readonly service: ServiceAvaliacoes<unknown>;
  readonly organizationId: string;
  readonly cycleId: string;
  readonly evaluationIds: readonly string[];
}) {
  const estado = useAvaliacoesSoberanas({
    service,
    organizationId,
    cycleId,
    evaluationIds,
  });

  return <ExibicaoAvaliacoesSoberanas estado={estado} />;
}
