import type { IdentidadeResolvida } from "./tipos";

/**
 * F5-03: organização ativa = intenção/contexto de UX, **nunca autoridade** de
 * tenant. Lógica pura de seleção e persistência local (conveniência de UX),
 * sempre revalidada contra as organizações disponíveis (memberships ativas) do
 * snapshot soberano de identidade (F5-01).
 *
 * - A lista de organizações disponíveis é soberana (servidor/RLS);
 * - a "organização solicitada" (intenção) vive no cliente;
 * - a "organização efetiva" é derivada: N=0 ⇒ null; N=1 ⇒ única (implícita);
 *   N>1 ⇒ a selecionada, se ainda válida; senão null (exige seleção).
 */

export const CHAVE_ULTIMA_ORGANIZACAO = "virtus.auth.ultimaOrganizacao";

export interface ArmazenamentoUltimaOrganizacao {
  ler(userId: string): string | null;
  definir(userId: string, organizationId: string): void;
  remover(userId: string): void;
}

interface StorageCompativel {
  getItem(chave: string): string | null;
  setItem(chave: string, valor: string): void;
  removeItem(chave: string): void;
}

/**
 * Marcador local da última organização selecionada, por usuário. Somente
 * conveniência de UX (pré-seleção de intenção); nunca usado como prova de
 * tenant. Tolerante a falhas/JSON corrompido (fallback em memória).
 */
export function criarArmazenamentoUltimaOrganizacaoLocal(
  obterStorage: () => StorageCompativel | null = () =>
    typeof window === "undefined" ? null : window.localStorage
): ArmazenamentoUltimaOrganizacao {
  const memoria = new Map<string, string>();
  let carregado = false;

  function obterStorageSeguro(): StorageCompativel | null {
    try {
      return obterStorage();
    } catch {
      return null;
    }
  }

  function lerRegistro(): Record<string, string> {
    if (carregado) return Object.fromEntries(memoria);

    carregado = true;
    const storage = obterStorageSeguro();
    if (!storage) return Object.fromEntries(memoria);

    try {
      const bruto = storage.getItem(CHAVE_ULTIMA_ORGANIZACAO);
      if (!bruto) return Object.fromEntries(memoria);
      const parseado: unknown = JSON.parse(bruto);
      if (typeof parseado !== "object" || parseado === null) {
        return Object.fromEntries(memoria);
      }
      for (const [userId, orgId] of Object.entries(parseado as Record<string, unknown>)) {
        if (typeof orgId === "string" && orgId.length > 0) {
          memoria.set(userId, orgId);
        }
      }
    } catch {
      // JSON corrompido/storage indisponível: segue em memória.
    }
    return Object.fromEntries(memoria);
  }

  function gravarStorage(): void {
    const storage = obterStorageSeguro();
    if (!storage) return;
    try {
      storage.setItem(CHAVE_ULTIMA_ORGANIZACAO, JSON.stringify(Object.fromEntries(memoria)));
    } catch {
      // sem persistência: a conveniência segue em memória.
    }
  }

  return {
    ler(userId) {
      return lerRegistro()[userId] ?? null;
    },
    definir(userId, organizationId) {
      memoria.set(userId, organizationId);
      gravarStorage();
    },
    remover(userId) {
      memoria.delete(userId);
      gravarStorage();
    },
  };
}

/** `true` quando `organizationId` pertence às organizações disponíveis. */
export function selecaoValida(
  identidade: IdentidadeResolvida | undefined,
  organizationId: string | null | undefined
): boolean {
  if (!organizationId || !identidade) return false;
  return identidade.organizacoes.some((organizacao) => organizacao.id === organizationId);
}

/**
 * Organização efetiva (contexto de UX derivado do snapshot + intenção):
 * - 0 disponíveis ⇒ null (semOrganizacao);
 * - 1 disponível ⇒ a única (implícita — não é escolha);
 * - N>1 ⇒ a selecionada se ainda válida; senão null (exige seleção).
 */
export function organizacaoEfetiva(
  identidade: IdentidadeResolvida | undefined,
  selecionadaId: string | null
): string | null {
  if (!identidade) return null;
  const organizacoes = identidade.organizacoes;

  if (organizacoes.length === 0) return null;
  if (organizacoes.length === 1) return organizacoes[0].id;
  return selecaoValida(identidade, selecionadaId) ? selecionadaId : null;
}
