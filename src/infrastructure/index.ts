/**
 * Fronteira para adapters de persistência e integrações externas.
 * Pode depender de domain e application/ports, sem importar UI ou casos de uso.
 * Implementa os contratos da aplicação, sem definir regras de negócio ou
 * autorização. Os adapters de transição em ./localStorage delegam aos storages
 * atuais, que permanecem em src/services e seguem como persistência ativa.
 */
export {};
