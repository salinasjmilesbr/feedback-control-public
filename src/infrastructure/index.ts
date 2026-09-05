/**
 * Fronteira para adapters de persistência e integrações externas.
 * Pode depender de domain e application/ports, sem importar UI ou casos de uso.
 * Implementa os contratos da aplicação, sem definir regras de negócio ou
 * autorização. Os storages atuais permanecem em src/services e seguem em uso;
 * esta estrutura não altera localStorage nem introduz um novo adapter.
 */
export {};
