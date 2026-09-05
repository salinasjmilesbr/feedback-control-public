# Contratos de persistência

`CycleRepository` cobre consulta e cadastro de ciclos; `CollaboratorRepository`
cobre consulta, cadastro e atualização por matrícula. São recortes das APIs
atuais, com os mesmos argumentos, retornos síncronos e erros. Não representam
todos os serviços nem oferecem escrita genérica que contorne o lifecycle.

Os adapters em `src/infrastructure/localStorage` delegam diretamente aos storages
de `src/services`. Estes continuam responsáveis pelas chaves, inicialização,
migrações de dados legados e validações já existentes. Não há cache paralelo,
nova serialização, cópia de regras ou mudança dos consumidores atuais.

Casos de uso que adotarem a fronteira devem receber o contrato por parâmetro;
o ponto de composição fornece o adapter local. A aplicação não deve importar
esse adapter. Os testes de caracterização exercitam os contratos com o storage
real e a implementação de `Storage` em memória usada pelo projeto.

Um futuro adapter Supabase será fornecido nesse ponto de composição, mantendo
o fornecedor fora da UI. Isso não é uma troca imediata: acesso remoto exige
contratos assíncronos e adoção pelos casos de uso, em etapa posterior. Esta
entrega preserva as assinaturas síncronas e não migra páginas nem casos de uso.

Autorização, transições de ciclo e registro de histórico organizacional seguem
nos fluxos existentes. Os contratos não autorizam operações nem substituem
esses fluxos; em particular, `updateColaborador` não registra uma movimentação
organizacional por conta própria, assim como o storage atual.
