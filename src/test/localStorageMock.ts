export function instalarLocalStorageEmMemoria(): Storage {
  const dados = new Map<string, string>();

  const storage: Storage = {
    get length() {
      return dados.size;
    },
    clear() {
      dados.clear();
    },
    getItem(chave) {
      return dados.get(chave) ?? null;
    },
    key(indice) {
      return Array.from(dados.keys())[indice] ?? null;
    },
    removeItem(chave) {
      dados.delete(chave);
    },
    setItem(chave, valor) {
      dados.set(chave, String(valor));
    },
  };

  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: storage,
  });

  return storage;
}
