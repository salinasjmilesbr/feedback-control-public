# Auditoria transversal CI #541 — Issue #414 / PR #415

Data: 2026-09-30  
Branch auditada: `feat/issue-414-company-admin-lifecycle`  
HEAD auditado: `3b65013e524e266e449dd3217cad13538c353846`

## Escopo e método

Auditoria estática do job **Supabase local — RLS/policy validation** em
`.github/workflows/ci.yml`, das famílias efetivamente chamadas por ele e dos
contratos #414 que incidem sobre fixtures: `1..4` Admins ativos por tenant,
role soberana `admin`, operações dedicadas `company_admin_*` e guardas D12.

Não houve execução PostgreSQL/Docker, alteração de produto, migration, RLS,
RPC, trigger, fixture ou workflow nesta auditoria. Resultados marcados como
**confirmados** decorrem de caminho/SQLSTATE demonstrável no código; os demais
permanecem riscos estáticos e exigem runner PostgreSQL descartável.

## A. Causa-raiz confirmada — F5-04

`02-validar-f5-04.sql:309-317` prova corretamente que `USER_A`, que não é
admin, não pode conceder uma role. O RPC chamado em `:309-313` é
`conceder_acesso_role_rpc` com `USER_A` como ator. Desde #414,
`20261019000000_f6_414_company_admin_lifecycle.sql:171-175` rejeita esse caso
com `F5_04_NOT_AUTHORIZED`, SQLSTATE `42501`.

O bloco de teste captura somente `exception when raise_exception` em
`:314`. `raise_exception` corresponde a `P0001`, não a `42501`; por isso o
DENY esperado escapa do bloco e encerra o arquivo sob `ON_ERROR_STOP`.

Conclusão: não é defeito de produto nem autorização removida indevidamente.
O ator não-admin continua sendo o ator certo para a prova negativa; falta
capturar `insufficient_privilege` (idealmente de modo explícito e com cheque de
não persistência). Correção mínima proposta: trocar apenas o handler dessa
prova negativa para `exception when insufficient_privilege then ...`, sem
alterar o RPC ou D12.

## B. Matriz transversal das famílias do workflow

| Família / arquivos | Achado | Classe | Evidência estática | Correção mecânica proposta | Prioridade / confiança |
| --- | --- | --- | --- | --- | --- |
| F4-08 — `01/02/03-validar-f4-08*.sql` | Família já passou no CI #541. Usa fixture com bootstrap #414 e runner próprio. | D | workflow `:153-157`; CI informado | Nenhuma | Baixa / alta |
| F5-04 — `02-validar-f5-04.sql` | Falha histórica do CI: DENY de não-admin não capturava `42501`; correção está no working tree atual. | A, corrigido localmente | bloco 5.2 atual `:303-352`; migration #414 `:171-175` | Revalidar em PostgreSQL descartável; conservar `USER_A`. | P0 / alta |
| F5-04 — `01-cenario-f5-04.sql` | Comentário diz bootstrap por primitivo genérico, mas fixture insere admin diretamente; o cenário também deixa limpeza física comentada. | A, confirmado (documentação/fixture) | `:1-15`, `:145-173`; `:576-623` | Atualizar comentário e manter bootstrap técnico mínimo direto; não reativar teardown físico. | P1 / alta |
| F5-06 — `01-cenario-f5-06.sql` | Cria organização (`:64`) e faz limpeza linha a linha (`:39-60`); requer admin técnico antes do commit e não pode desmontar último Admin. | A, risco forte | workflow `:225-229`; criação/cleanup citados | Criar profile+membership+assignment admin técnico na mesma transação; retirar cleanup físico agora redundante no runner descartável. | P1 / média |
| F5-07 — `01-cenario-f5-07.sql`, `03-validar-f5-07-cutover.sql` | Cenário cria tenant (`:138`) e remove tenants anteriores (`:86-131`); cutover alterna membership (`03:949,984`). | A, risco forte | workflow `:231-235`; mutações citadas | Bootstrap técnico independente dos atores estruturais; garantir que status testado não seja o único admin; não fazer cleanup físico. | P1 / média |
| F5-08 — `01/02/03-validar-f5-08*.sql` | Cria Alfa/Beta (`01:144`) e limpa memberships/tenants (`:111-134`). Pode entrar em conflito com D12 na reexecução. | A, risco forte | workflow `:165-169`; mutações citadas | Bootstrap mínimo transacional por tenant e substituição do teardown pelo descarte do runner. | P1 / média |
| F5-09 P1–P5 — `01..10-*.sql` | P1, P2, P3, P4 e P5 criam organizações próprias (`01:65`, `03:52`, `05:58`, `07:55`, `09:52`) sem bootstrap visível no workflow. | A, risco forte | workflow `:171-192`; inserts citados | Cada cenário deve criar admin técnico na mesma transação e preservar a ordem interna da família. | P0 / média |
| F5-09 P7/D28 — `11..13-*.sql` | Há replay de migration duas vezes no mesmo banco; é dependência legítima, mas o plano deve manter paths/replay e os tenants de `12` (`:36`) devem cumprir 1..4. | A, risco forte | workflow `:181-185`; `MIGRATION_REPLAY` repetido | Manter `Plan`; acrescentar bootstrap transitório no cenário, não no runner. | P0 / média |
| F5-09 P9 — `14..18-*.sql` | Concorrência exige duas sessões reais e `WAIT`; tenant do cenário (`14:83`) deve permanecer válido antes/depois. | A, risco forte | workflow `:185-192`; background/foreground/wait | Bootstrap no cenário e executar somente via `Plan`; validar sem interferir nos locks próprios da P9. | P0 / média |
| F5-10 P1–P5.2 — `19..28-*.sql` | P1–P4 inserem organizações (`19:43`, `21:75`, `23:68`, `25:100`) e P4 alterna membership/profile (`26:387-438`). | A, risco forte | workflow `:194-207`; mutações citadas | Bootstrap separado; para transições de status, alvo funcional não pode ser o único admin. | P0 / média |
| F5-10 P7 — `29..33-*.sql` | Cria tenant (`29:115`) e executa concorrência real. | A, risco forte | workflow `:205-212`; steps psql | Bootstrap no cenário; conservar plano concorrente e estado compartilhado da família. | P0 / média |
| F5-11 P1/P1.1/P2/P3 — `34..41-*.sql` | Quatro cenários criam organizações (`34:51`, `36:60`, `38:79`, `40:67`) sem passo explícito de admin técnico no workflow. | A, risco forte | workflow `:213-217`; inserts citados | Bootstrap mínimo por organização, sem capabilities funcionais; conservar atores de observação. | P0 / média |
| F5-11 P5.1 — `42/43-*.sql` | Cria organização adicional (`42:238`), muda profile status (`43:611-679`) e contém cleanup de memberships/organização (`43:876-925`). | A + B | workflow `:213-217`; linhas citadas | Isolar admin técnico do profile cujo lifecycle é testado e remover teardown físico incompatível. `format()` histórico referido em `43` é dívida B, salvo prova de nexo. | P0 / média |
| F6-A03 — `44/45-*.sql` | Cenário tem cleanup físico (`44:30-77`) e cria tenant (`:90`); validador desativa fundador (`45:836`) e também limpa fisicamente (`:1103-1156`). | A, confirmado por contrato | workflow `:219-223`; linhas citadas | Criar segundo admin legítimo antes de testar founder disabled; usar descarte do runner como limpeza da família. | P0 / alta |
| Runner/workflow — `Invoke-DisposableValidation.ps1`, `ci.yml` | `Script` cobre família linear; `Plan` cobre replay/concorrência. CI #541 prova runner e F4-08, mas não prova famílias posteriores. | D | `ci.yml:153-235`; CI informado | Nenhuma mudança arquitetural. Validar paths e planos antes do push. | P1 / alta |
| F5-11 P2/P5.1 | `malformed array literal` (P2) e `format()` (P5.1) já são falhas históricas reportadas, independentes até prova contrária. | B | histórico da auditoria #414; `39-validar-f5-11-p2.sql`, `43-validar-f5-11-p5-1.sql` | Abrir/usar dívida separada; não mascarar nesta Issue. | P2 / média |

## C. Cobertura de negativos e contratos que precisam permanecer

1. **F5-04 5.1, 5.2, 5.4–5.7** são negativos intencionais. Cada bloco precisa
capturar o SQLSTATE que o contrato de produção realmente emite. Em especial,
`42501` não é intercambiável com `P0001`.
2. `conceder_acesso_role_rpc`/`revogar_acesso_role_rpc` continuam adequados
para roles funcionais e devem negar admin com
`F6_414_ADMIN_USE_COMPANY_OPERATION`; não se deve reintroduzir grant/revoke
genérico de admin para acomodar fixture.
3. Os testes de profile/membership disabled devem atingir ator funcional ou,
quando atingirem administrador, preparar um segundo admin técnico ativo antes
da alteração. O guard D12 deve continuar observável e fail-closed.
4. Nenhuma fixture pode fazer depender o ator funcional do bootstrap de admin:
o admin técnico não recebe collaborator, posição, reporting, occupation ou
capability funcional confidencial.

## D. Alterações recomendadas, em um único pacote posterior

1. `supabase/validacao/02-validar-f5-04.sql`: correção já aplicada no handler
do DENY 5.2 para `insufficient_privilege`, com ausência de escrita residual;
falta somente a prova PostgreSQL descartável.
2. Cenários F5-04, F5-06, F5-07, F5-08, F5-09, F5-10 e F5-11: em cada
transação que cria organização, inserir bootstrap técnico mínimo (auth user,
profile ativo, membership ativa, assignment ativa da role system `admin`).
3. Validadores de lifecycle F5-07, F5-10 P4, F5-11 P5.1 e F6-A03: assegurar
segundo admin técnico antes de desabilitar/remover o administrador que seria o
último.
4. Remover apenas os cleanups físicos que se tornaram impossíveis pela D12 e
que são substituídos comprovadamente pelo descarte da família. Não remover
cleanups de dados internos que a mesma família ainda reutiliza.
5. Preservar o workflow por famílias: linear com `-Script`; F5-09/F5-10 com
`-Plan` para replay e concorrência. Não alterar produto, migration, RLS, RPC
ou trigger.

## E. Impacto reverso e riscos

- **Contagens históricas:** bootstrap acrescenta profile/membership/assignment.
  Antes de alterar qualquer assert, separar consulta de domínio do admin
  técnico; não aumentar expected count cegamente.
- **Sequência interna:** F5-09, F5-10 e F5-11 compartilham banco dentro da
  família; bootstrap deve ser idempotente e não apagar estado de fase anterior.
- **Auditoria append-only:** cleanups não podem tentar apagar
  `company_admin_operations` ou trilhas protegidas. O descarte completo do
  banco é a fronteira de higiene.
- **SQL preexistente:** array literal/formatação não devem entrar no pacote
  sem reprodução que prove nexo com #414.

## F. Plano de validação pré-push

| Camada | Gate |
| --- | --- |
| Estático | parsing PowerShell, `Test-DisposableValidationSequence.ps1`, `Test-DisposableValidationGuard.ps1`, paths de todos os `-Script`/`-Plan`, `git diff --check` |
| PostgreSQL descartável | executar cada família completa na ordem de `ci.yml`; capturar primeiro erro por família; provar runner descarta banco após sucesso e falha |
| Negativos #414 | último admin, grant/revoke admin genérico, status de membership/profile e `F5_04_NOT_AUTHORIZED` com SQLSTATE correto |
| CI | confirmar o job completo no SHA publicado; CI é confirmação final, não descoberta de catálogo/fixture |

Docker/runner PostgreSQL descartável é obrigatório para confirmar comportamento
SQL e concorrência. Se indisponível localmente, a auditoria estática não pode
declarar essas famílias PASS; a limitação deve ser registrada no PR e o CI deve
executar a prova.

## G. Sequência recomendada e executor

1. **Luna:** implementar o pacote mecânico de fixtures/validadores acima,
família por família, sem mudar produto.
2. **Terra:** executar o preflight PostgreSQL descartável completo e consolidar
os SQLSTATEs/contagens após as alterações.
3. **Sol:** auditoria independente do diff e da matriz antes do push.

Não há indicação, nesta auditoria, de mudança arquitetural adicional. Há **1
problema confirmado** (F5-04 SQLSTATE não capturado) e **10 riscos potenciais
agrupados por família** que exigem correção/preflight PostgreSQL para
classificação final. Famílias afetadas: F5-04, F5-06, F5-07, F5-08, F5-09,
F5-10, F5-11 e F6-A03. F4-08 e o runner não têm finding novo confirmado.

## Conclusão

O próximo passo não é corrigir produção: é implementar e validar um pacote
único de compatibilidade de fixtures, preservando D12. Após esse pacote, o job
inteiro deve ser executado em PostgreSQL descartável antes de novo push.

## H. Reconciliação após inspeção da branch atual

Esta seção registra a reconciliação solicitada após a correção local da F5-04.
Ela não altera o diagnóstico de runtime: sem PostgreSQL descartável, ausência
de erro não é PASS SQL.

| Família | Estado atual na branch | Classificação do achado original | Evidência / decisão |
| --- | --- | --- | --- |
| F4-08 | Já resolvido | Já resolvido | CI #541 reportou PASS; workflow chama os três arquivos no runner descartável. |
| F5-04 | Correção aplicada localmente | Correção confirmada | `02-validar-f5-04.sql:309-352` agora exige `insufficient_privilege`, SQLSTATE `42501`, mensagem `F5_04_NOT_AUTHORIZED` e compara assignment/auditoria antes/depois. Runtime ainda não foi reexecutado. |
| F5-06 | Bootstrap/adaptações anteriores presentes | Risco ainda não comprovado | O cenário contém preparação administrativa; não há prova PostgreSQL nesta rodada de que todas as transições/limpeza permanecem válidas. |
| F5-07 | Bootstrap/adaptações anteriores presentes | Risco ainda não comprovado | O cenário e cutover existem no workflow; status mutations e contagens dependem de banco descartável. |
| F5-08 | Bootstrap/adaptações anteriores presentes | Risco ainda não comprovado | F4-08 não implica PASS de F5-08; executar a família separadamente no runner. |
| F5-09 | Plano sequencial presente | Risco ainda não comprovado | P7/D28 inclui dois replays e P9 inclui duas sessões; a ordem está declarada, mas a execução SQL desta rodada não ocorreu. |
| F5-10 | Plano sequencial presente | Risco ainda não comprovado | P7 inclui concorrência; P4 altera status. Não há base para repetir bootstrap ou alterar assertions sem execução. |
| F5-11 | Scripts sequenciais presentes | Risco ainda não comprovado | P1/P1.1/P2/P3/P5.1 têm cenários e validadores; malformed-array/`format()` permanecem dívida histórica independente até prova de regressão. |
| F6-A03 | Bootstrap e segundo-admin previstos no estado atual | Risco ainda não comprovado | O contrato do validador exige fundador ativo e segundo admin para desativação; só SQL descartável confirma cardinalidade final. |
| Runner | Parser, preflight e guard já verdes | Já resolvido | `Invoke-DisposableValidation.ps1`, `Test-DisposableValidationSequence.ps1` e guard passaram; paths do workflow foram verificados, incluindo migration replay. |

### Gates desta rodada

- Parsing PowerShell: **PASS**.
- Preflight executável do runner: **PASS** — normalização sem `Id`, com `Id`,
  `WAIT` sem `Id` e tipo desconhecido foram exercitados.
- Guard do runner: **PASS**.
- Resolução estática dos paths declarados pelo workflow: **PASS** para os
  60 references SQL; migration replay foi resolvido em `supabase/migrations`.
- `git diff --check`: **PASS**.
- PostgreSQL descartável: **NÃO EXECUTADO** nesta rodada; Docker/runtime
  descartável não foi iniciado.

### Arquivos alterados nesta implementação controlada

- `supabase/validacao/02-validar-f5-04.sql`: captura específica do DENY
  `42501`/`F5_04_NOT_AUTHORIZED` e verificação de não persistência.
- `docs/auditoria-ci-541-issue-414.md`: este relatório.

Não foram alterados produto, migrations, RPCs, RLS, triggers, workflow ou
dados de Acme/Cycle 1. A implementação permanece sem commit/push e aguarda
auditoria GPT.
