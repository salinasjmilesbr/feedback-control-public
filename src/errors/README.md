# Erros de aplicação

`src/errors` é uma fronteira compartilhada, sem dependência de UI, persistência
ou infraestrutura. A base comum fica em `applicationErrors.ts`; o ponto de
entrada `index.ts` também reexporta o `AuthorizationError` existente. Não há
segunda classe de autorização e a policy continua usando o caminho anterior.

| Classe | code | category |
| --- | --- | --- |
| ValidationError | VALIDATION_ERROR | validation |
| AuthorizationError | FORBIDDEN | authorization |
| ConflictError | CONFLICT | conflict |
| NotFoundError | NOT_FOUND | not_found |
| TechnicalError | TECHNICAL_ERROR | technical |

Use `toPublicError(error)` para obter `{ code, category, message }` destinado à
UI. As mensagens vêm de catálogo fixo: não interpolam conteúdo de avaliações,
metas ou observações, causas, stacks ou identificadores internos. Valores
desconhecidos (inclusive objetos remotos com um `code`) são falhas técnicas.
Nenhum erro é inferido por texto, nome ou formato de resposta de fornecedor.

`AuthorizationError` preserva construtor por capability, `name`, `message`,
`code=FORBIDDEN`, `capability` e `instanceof Error/AuthorizationError`. Sua
mensagem legada contém a capability; use a projeção pública para novos
consumidores de UI. Os fluxos e mensagens existentes não foram migrados.

`cause` e `errorId` são contexto interno opcional. `errorId` reserva um
identificador opaco para futura correlação/error_id; não é gerado, persistido,
enviado nem incluído na projeção pública. Não serialize o objeto Error inteiro
para a UI. Nenhuma observabilidade, retry ou integração externa é implementada.

As novas classes têm mensagens públicas fixas e aceitam apenas contexto interno
opcional. A única adoção em produção nesta etapa é a base do AuthorizationError;
demais erros legados permanecem intactos, sem reinterpretar regras de domínio.
