/**
 * Política de sessão do Virtus (F2-08), centralizada e pura.
 *
 * Regras iniciais de sessão aplicadas sobre a sessão gerida pelo Supabase Auth
 * (o Supabase continua sendo o gestor de autenticação; esta política só
 * acrescenta limites temporais de uso da aplicação):
 *
 * - timeout por inatividade: 60 minutos sem atividade do usuário na aplicação
 *   exige nova autenticação;
 * - duração máxima persistente: 1 dia desde o início da sessão neste
 *   dispositivo exige nova autenticação (inclusive após refresh/reabertura).
 *
 * Nenhuma credencial é representada aqui; o único dado persistido pela
 * política é um marcador temporal de início de sessão (metadado, não
 * autenticador) — senha nunca é armazenada e não há mecanismo próprio de
 * remember-password (ver `armazenamentoSessao.ts` e `AuthProvider.tsx`).
 */

/** Inatividade máxima antes de exigir nova autenticação (60 minutos). */
export const LIMITE_INATIVIDADE_MS = 60 * 60 * 1000;

/** Duração máxima persistente de uma sessão neste dispositivo (1 dia). */
export const DURACAO_MAXIMA_SESSAO_MS = 24 * 60 * 60 * 1000;

/** Cadência de verificação da política no `AuthProvider` (revalidação F2-07 + limites F2-08). */
export const INTERVALO_VERIFICACAO_SESSAO_MS = 60 * 1000;

export type MotivoExpiracaoSessao = "inatividade" | "duracaoMaxima";

/**
 * `true` quando o usuário ficou sem atividade por pelo menos
 * `LIMITE_INATIVIDADE_MS`. `ultimaAtividadeMs === null` (sem janela aberta)
 * nunca é considerado inativo.
 */
export function excedeuInatividade(
  ultimaAtividadeMs: number | null,
  agoraMs: number
): boolean {
  return (
    ultimaAtividadeMs !== null &&
    agoraMs - ultimaAtividadeMs >= LIMITE_INATIVIDADE_MS
  );
}

/**
 * `true` quando a sessão deste dispositivo já dura pelo menos
 * `DURACAO_MAXIMA_SESSAO_MS` desde o seu início. `inicioSessaoMs === null`
 * (sem marcador) nunca é considerado expirado por duração.
 */
export function excedeuDuracaoMaxima(
  inicioSessaoMs: number | null,
  agoraMs: number
): boolean {
  return (
    inicioSessaoMs !== null &&
    agoraMs - inicioSessaoMs >= DURACAO_MAXIMA_SESSAO_MS
  );
}

/**
 * Decide, em uma única passada, se a sessão viola algum limite e qual motivo
 * deve ser apresentado. A duração máxima tem prioridade na mensagem quando
 * ambos os limites foram cruzados (o desfecho é o mesmo: nova autenticação).
 */
export function motivoDeExpiracao(
  inicioSessaoMs: number | null,
  ultimaAtividadeMs: number | null,
  agoraMs: number
): MotivoExpiracaoSessao | null {
  if (excedeuDuracaoMaxima(inicioSessaoMs, agoraMs)) return "duracaoMaxima";
  if (excedeuInatividade(ultimaAtividadeMs, agoraMs)) return "inatividade";
  return null;
}

/** Mensagem pública exibida na tela de login quando a sessão expira. */
export function mensagemDeExpiracao(motivo: MotivoExpiracaoSessao): string {
  switch (motivo) {
    case "inatividade":
      return "Sua sessão foi encerrada por inatividade. Entre novamente para continuar.";
    case "duracaoMaxima":
      return "Sua sessão atingiu a duração máxima de 1 dia. Entre novamente para continuar.";
  }
}
