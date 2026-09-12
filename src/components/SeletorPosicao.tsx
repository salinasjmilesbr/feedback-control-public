/**
 * F5-08 P5 — seletor de POSIÇÃO soberana (por UUID).
 *
 * - a identidade enviada é sempre `posicaoId` (UUID); o texto exibido é RÓTULO
 *   (`unidade • cargo (senioridade)`);
 * - apenas posições VIGENTES hoje (`[valid_from, valid_to)`) são oferecidas — uma
 *   posição com início futuro NÃO aparece como disponível agora;
 * - opcionalmente exibe o OCUPANTE da posição como rótulo AUXILIAR (nunca como
 *   identidade e nunca como substituto do UUID);
 * - nenhuma regra de ciclo/self-relation/capacidade é decidida aqui: a única
 *   exclusão é a própria posição quando o campo é o de gestor (`excluirPosicaoId`),
 *   que é UX — o banco continua recusando auto-relação e ciclos.
 */

import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import {
  nomeDoColaborador,
  ocupanteDaPosicao,
  rotuloDaPosicao,
} from "../pages/apoioEstrutura";
import { posicoesVigentes } from "../pages/alocacaoSoberana";

interface SeletorPosicaoProps {
  readonly id: string;
  readonly estrutura: EstruturaSoberana;
  readonly valor: string;
  readonly aoMudar: (posicaoId: string) => void;
  readonly rotulo: string;
  readonly vazio?: string;
  /** Posição que NÃO deve ser oferecida (ex.: a própria subordinada). */
  readonly excluirPosicaoId?: string;
  /** Exibe o ocupante da posição como rótulo auxiliar. */
  readonly mostrarOcupante?: boolean;
  readonly desabilitado?: boolean;
}

function SeletorPosicao({
  id,
  estrutura,
  valor,
  aoMudar,
  rotulo,
  vazio = "Selecione uma posição…",
  excluirPosicaoId,
  mostrarOcupante = false,
  desabilitado = false,
}: SeletorPosicaoProps) {
  const posicoes = posicoesVigentes(estrutura).filter(
    (posicao) => posicao.posicaoId !== excluirPosicaoId
  );

  return (
    <label className="collaborator-field collaborator-field--wide">
      <span>{rotulo}</span>
      <select
        id={id}
        value={valor}
        onChange={(evento) => aoMudar(evento.target.value)}
        disabled={desabilitado || posicoes.length === 0}
      >
        <option value="">{vazio}</option>
        {posicoes.map((posicao) => {
          const ocupanteId = mostrarOcupante
            ? ocupanteDaPosicao(estrutura, posicao.posicaoId)
            : null;
          const complemento = ocupanteId
            ? ` — ocupante: ${nomeDoColaborador(estrutura, ocupanteId)}`
            : "";
          return (
            <option key={posicao.posicaoId} value={posicao.posicaoId}>
              {`${rotuloDaPosicao(estrutura, posicao.posicaoId)}${complemento}`}
            </option>
          );
        })}
      </select>
      {posicoes.length === 0 && (
        <small>
          Nenhuma posição vigente disponível: cadastre a posição em Estrutura →
          Posições (nada é criado automaticamente).
        </small>
      )}
    </label>
  );
}

export default SeletorPosicao;
