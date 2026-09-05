/**
 * Fronteira para casos de uso: UI -> application -> domínio/autorização
 * -> contratos de persistência -> adapters.
 * Pode depender de domain, dos contratos em ./ports e da autorização central
 * em src/authorization; não importa UI nem implementações de infrastructure.
 * Os adapters serão fornecidos aos casos de uso pelo ponto de composição.
 * src/services continua válido durante a transição, sem migração nesta etapa.
 */
export {};
