/**
 * Marcador persistente do início da sessão (F2-08).
 *
 * Guarda, por usuário autenticado e por dispositivo, quando a sessão corrente
 * começou (epoch ms). Serve apenas à política de duração máxima (1 dia) e
 * refresh/reabertura coerentes: é metadado de política — NÃO é credencial,
 * não autentica nada e não substitui o Supabase Auth (que permanece o gestor
 * da sessão e dono de `supabase.auth.token`).
 *
 * Formato: chave única `CHAVE_INICIO_SESSAO` com um mapa `{ [userId]: ms }`,
 * tolerante a falhas/JSON corrompido (fallback em memória) para não quebrar o
 * fluxo quando o `localStorage` estiver indisponível (modo privado etc.).
 */

export const CHAVE_INICIO_SESSAO = "virtus.auth.inicioSessao";

export interface ArmazenamentoInicioSessao {
  ler(userId: string): number | null;
  definir(userId: string, inicioMs: number): void;
  remover(userId: string): void;
}

interface StorageCompativel {
  getItem(chave: string): string | null;
  setItem(chave: string, valor: string): void;
  removeItem(chave: string): void;
}

export function criarArmazenamentoInicioSessaoLocal(
  obterStorage: () => StorageCompativel | null = () =>
    typeof window === "undefined" ? null : window.localStorage
): ArmazenamentoInicioSessao {
  const memoria = new Map<string, number>();
  let carregadoDoStorage = false;

  function obterStorageSeguro(): StorageCompativel | null {
    try {
      return obterStorage();
    } catch {
      return null;
    }
  }

  function lerRegistro(): Record<string, number> {
    if (carregadoDoStorage) return Object.fromEntries(memoria);

    carregadoDoStorage = true;
    const storage = obterStorageSeguro();
    if (!storage) return Object.fromEntries(memoria);

    try {
      const bruto = storage.getItem(CHAVE_INICIO_SESSAO);
      if (!bruto) return Object.fromEntries(memoria);
      const parseado: unknown = JSON.parse(bruto);
      if (typeof parseado !== "object" || parseado === null) {
        return Object.fromEntries(memoria);
      }
      for (const [userId, valor] of Object.entries(parseado as Record<string, unknown>)) {
        if (typeof valor === "number" && Number.isFinite(valor) && valor > 0) {
          memoria.set(userId, valor);
        }
      }
    } catch {
      // JSON corrompido ou storage indisponível: segue apenas em memória.
    }
    return Object.fromEntries(memoria);
  }

  function gravarStorage(): void {
    const storage = obterStorageSeguro();
    if (!storage) return;
    try {
      storage.setItem(CHAVE_INICIO_SESSAO, JSON.stringify(Object.fromEntries(memoria)));
    } catch {
      // Sem persistência (ex.: cota/privacidade): a política segue em memória.
    }
  }

  return {
    ler(userId) {
      return lerRegistro()[userId] ?? null;
    },
    definir(userId, inicioMs) {
      memoria.set(userId, inicioMs);
      gravarStorage();
    },
    remover(userId) {
      memoria.delete(userId);
      gravarStorage();
    },
  };
}
