/**
 * F5-08 P6 (correção da auditoria GPT) — hook de PRODUÇÃO da estrutura soberana.
 *
 * Montado no shell autenticado (`LayoutFuncional`), este hook garante que a
 * projeção estrutural seja obtida pelo caminho NORMAL já existente — leitura RLS
 * (`lerEstrutura`, P4) + projeção de colaboradores (`listarColaboradores`,
 * F5-07) — sem injeção manual. Os consumidores legados (ciclo/meta) leem a
 * projeção publicada de forma síncrona.
 *
 * Em DEV/teste a fixture local continua disponível, atrás do gate explícito
 * (`simulacaoDevPermitida`) e somente quando a estrutura soberana não está
 * disponível.
 */

import { useEffect, useState } from "react";
import {
  assinarEstruturaSoberana,
  carregarEstruturaSoberana,
  estadoEstruturaSoberana,
  invalidarEstruturaSoberana,
  type EstadoEstruturaSoberana,
} from "../services/estruturaSoberanaCliente";
import type { DependenciasAcessoColaboradores } from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";

/**
 * @param organizacaoAtivaId organização ATIVA de UX (intenção; o servidor
 *   revalida a membership). `null`/`undefined` INVALIDA o contexto: a estrutura
 *   da organização anterior deixa de ser exposta (fail-closed) e nenhuma
 *   resposta em voo consegue republicá-la.
 * @param deps dependências das portas soberanas (injeção de teste). Deve ser
 *   estável entre renders.
 */
export function useEstruturaSoberanaDoCliente(
  organizacaoAtivaId: string | null | undefined,
  deps?: DependenciasAcessoColaboradores
): EstadoEstruturaSoberana {
  const [estado, setEstado] = useState<EstadoEstruturaSoberana>(() =>
    estadoEstruturaSoberana()
  );

  useEffect(() => assinarEstruturaSoberana(() => setEstado(estadoEstruturaSoberana())), []);

  useEffect(() => {
    if (!organizacaoAtivaId) {
      // Perder a organização ativa (seleção removida, logout) NÃO pode manter a
      // estrutura do tenant anterior utilizável.
      invalidarEstruturaSoberana();
      return;
    }

    const atual = estadoEstruturaSoberana();
    const jaResolvidoParaOrg =
      atual.organizacaoId === organizacaoAtivaId &&
      (atual.fase === "pronta" || atual.fase === "carregando");
    if (jaResolvidoParaOrg) return;

    // Troca de organização: o produtor invalida a estrutura anterior e só
    // publica a resposta da carga ainda vigente.
    void carregarEstruturaSoberana({ organizationId: organizacaoAtivaId }, deps ?? {});
  }, [organizacaoAtivaId, deps]);

  return estado;
}
