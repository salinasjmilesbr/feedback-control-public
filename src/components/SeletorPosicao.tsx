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
  nomeDaUnidade,
  ocupanteDaPosicao,
  rotuloDoCargo,
  rotuloDaSenioridade,
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
  readonly unidadeId?: string;
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
  unidadeId,
}: SeletorPosicaoProps) {
  const posicoes = posicoesVigentes(estrutura).filter(
    (posicao) =>
      posicao.posicaoId !== excluirPosicaoId &&
      (unidadeId === undefined || posicao.unitId === unidadeId)
  );

  const contexto = (posicaoId: string): string => {
    const posicao = estrutura.posicoes.find((item) => item.posicaoId === posicaoId);
    if (!posicao) return "—";
    const senioridade = posicao.seniorityLevelId
      ? ` (${rotuloDaSenioridade(estrutura, posicao.seniorityLevelId)})`
      : "";
    return `${nomeDaUnidade(estrutura, posicao.unitId)} • ${rotuloDoCargo(estrutura, posicao.jobRoleId)}${senioridade}`;
  };
  const chaves = new Map<string, number>();
  for (const posicao of posicoes) {
    const chave = `${rotuloDaPosicao(estrutura, posicao.posicaoId)}|${contexto(posicao.posicaoId)}`;
    chaves.set(chave, (chaves.get(chave) ?? 0) + 1);
  }

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
          const nome = rotuloDaPosicao(estrutura, posicao.posicaoId);
          const contextoPosicao = contexto(posicao.posicaoId);
          const chave = `${nome}|${contextoPosicao}`;
          const sufixoUuid = (chaves.get(chave) ?? 0) > 1
            ? ` — ${posicao.posicaoId.slice(0, 8)}`
            : "";
          const ocupanteId = mostrarOcupante
            ? ocupanteDaPosicao(estrutura, posicao.posicaoId)
            : null;
          const complemento = ocupanteId
            ? ` — ocupante: ${nomeDoColaborador(estrutura, ocupanteId)}`
            : "";
          return (
            <option key={posicao.posicaoId} value={posicao.posicaoId}>
              {`${nome} — ${contextoPosicao}${sufixoUuid}${complemento}`}
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
