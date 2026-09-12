# Auditoria read-only de preparação F5-09/P5–P9

## Identificação

- Repositório: `salinasjmilesbr/feedback-control-public`
- SHA analisado: `c804903d84c5dd6def690137f0ec286bc06ad56e`
- Escopo: preparação técnica P5–P9
- Modo: somente leitura
- Nenhum arquivo de código, migration ou configuração foi alterado.
- Arquivos P4 não rastreados presentes no worktree foram excluídos da análise do SHA autoritativo.

## 1. Mapa P5–P7

| Pacote | Dependências principais | Arquivos envolvidos |
|---|---|---|
| P5 — leitura soberana | Schema de ciclos P1, RPCs P2–P4, RLS own-tenant | `src/application/ports/CycleRepository.ts`, `src/infrastructure/localStorage/localCycleRepository.ts`, futuro adapter Supabase/Edge, `supabase/functions/ciclos`, policies de `evaluation_cycles` |
| P6 — autorização | Ciclo real e estado server-side de P5; capabilities F4/F5 | `src/authorization/authorizationPolicy.ts`, `src/authorization/policyEngine/*`, `src/authorization/resourceContextReal.ts`, catálogo de capabilities |
| P7 — Edge/catálogo | Contratos P5, gate de autorização P6, RPCs soberanas | `supabase/functions/ciclos/*`, contratos Edge, bundle admin e reconciliação D28 |

P5–P7 podem ser coordenados como frente técnica, mas devem permanecer em Issues/PRs separados para preservar rastreabilidade. P8 e P9 devem permanecer separados.

Riscos principais de conflito: `cicloAvaliacaoStorage.ts`, `CycleRepository.ts`, `CiclosAvaliacaoPage.tsx`, `authorizationPolicy.ts` e `AppRoutes.tsx`.

## 2. Inventário completo para P8

| Arquivo | Função/uso | Autoridade atual | Destino esperado | Pacote |
|---|---|---|---|---|
| `src/services/cicloAvaliacaoStorage.ts` | CRUD, ciclo ativo e transições | Autoridade local em `localStorage` | RPC/repositório soberano | P8 |
| `src/infrastructure/localStorage/localCycleRepository.ts` | Implementação de `CycleRepository` | LocalStorage | Adapter Supabase/Edge | P5/P8 |
| `src/application/ports/CycleRepository.ts` | Porta de ciclo | Abstração ainda local | Contrato UUID-first/assíncrono | P5 |
| `src/pages/CiclosAvaliacaoPage.tsx` | Gestão administrativa | Storage local | RPCs P2/P4 | P8 |
| `src/pages/PainelCicloPage.tsx` | Painel por ciclo | Resolve localmente | Leitura soberana | P5/P8 |
| `src/pages/PainelCiclosCoordenadorPage.tsx` | Lista ciclos | Local | `cycle.read` | P5–P8 |
| `src/pages/RelatoriosPage.tsx` | Filtros por ano/ciclo | Bridge legado | Ciclo soberano | P8 |
| `src/components/RelatorioHistoricoCiclos.tsx` | Histórico/apresentação | Apresentação local | Dados server-side | P8 |
| `src/pages/AcompanhamentoMetasPage.tsx` | Resolve ciclo de metas | Local | Estado server-side | P8 |
| `src/pages/MinhasMetasPage.tsx` | Ciclo ativo | Local | Leitura soberana | P5/P8 |
| `src/pages/MinhaAvaliacaoPage.tsx` | Lista ciclos/avaliações | Local/bridge | UUID soberano | P8 |
| `src/pages/MinhaAvaliacaoDetalhePage.tsx` | Detalhe por ciclo | Bridge local | Associação server-side | P8 |
| `src/components/ObservacoesColaborador.tsx` | Filtro/validação de ciclo | Local | Contexto soberano | P8/F5-10 |
| `src/services/metaStorage.ts` | Metas vinculadas a ciclo | LocalStorage | Consumir ciclo soberano | F5-10/P8 |
| `src/services/observacaoStorage.ts` | Observações por ciclo | LocalStorage | Consumir ciclo soberano | F5-10 |
| `src/services/cicloEquipeService.ts` | Painel/equipe e bridges | Local/ano+ciclo | UUID e snapshots | P8/P9 |
| `src/services/relatorioService.ts` | Relatórios | Ano/ciclo local | Consulta soberana | P8 |
| `src/services/historicoOrganizacionalStorage.ts` | Histórico por ciclo | Bridge local | Estrutura/ciclo soberanos | F5-10/P8 |
| `src/services/exportarAvaliacaoPdf.ts` | Rótulos de ciclo | Apresentação | Dados soberanos recebidos | P8 |
| `src/services/geradorDadosTeste.ts` | Fixtures | DEV/teste | Isolado de produção | DEV |
| `src/routes/AppRoutes.tsx` | Rotas de telas | Contexto de UI | Preservar rotas, trocar carregamento | P8 |

Também foram encontrados consumidores em `ColaboradorDetalhePage.tsx`, `NovoFeedbackPage.tsx`, `EditarFeedbackPage.tsx`, `FeedbackDetalhePage.tsx` e testes associados.

Classificação:

- **A — autoridade local:** `cicloAvaliacaoStorage.ts`, `localCycleRepository.ts`, gestão administrativa e serviços de transição.
- **B — contexto operacional:** painéis, metas, avaliações e histórico estrutural.
- **C — bridge legado:** relatórios, observações, metas, equipe e avaliações por `(ano, ciclo)`.
- **D — apresentação:** labels, filtros, histórico e PDF.
- **E — cache/DEV legítimo:** fixtures, mocks e reset de desenvolvimento isolados.

## 3. Matriz de testes P5–P9

| Teste | Pacote/tipo | Risco coberto | Bloqueador |
|---|---|---|---|
| Own-tenant read | P5, SQL/Edge | Exposição de ciclos | Sim |
| Cross-tenant/IDOR por UUID | P5/P7, SQL/Edge | Acesso a outro tenant | Sim |
| Membership/capability revogada | P6/P7, SQL/Edge | Autorização obsoleta | Sim |
| Tenant mismatch no payload | P7, Edge | Confiança no payload | Sim |
| Status server-side | P5/P6, SQL | Manipulação de estado | Sim |
| `expectedVersion` stale | P2/P4/P9, SQL | Lost update | Sim |
| RLS deny-by-default | P5, SQL | Leitura direta indevida | Sim |
| Edge authorization | P7, Edge | `service_role` decidindo | Sim |
| Payload tampering/hash | P2/P7, SQL/Edge | Replay alterado | Sim |
| Cargo/função textual | P6/P7, unit/SQL | Autoridade não soberana | Sim |
| UUID versus matrícula | P5/P8, unit/integration | Identidade errada | Sim |
| Bridges `(ano,ciclo)` | P5/P8, integration | Colisão/resolução errada | Sim |
| Fallback local/dual-write | P8, client/static | Divergência local/PG | Sim |
| Stale async, logout e unmount | P8, client | Vazamento de contexto | Não |
| Regressões F5-06/F5-07/F5-08 | P9, SQL | Integridade de domínios | Sim |
| Concorrência real | P9, PostgreSQL multi-sessão | Contenção | Sim |
| Rollback completo | P9, SQL | Efeitos parciais | Sim |
| Audit trail | P2–P9, SQL | Mutação sem evento | Sim |

## 4. Resíduos da Etapa 5

### CRITICAL — tratar em P8

`src/services/cicloAvaliacaoStorage.ts` ainda:

- cria ciclos com `crypto.randomUUID()` no cliente;
- semeia ciclos a partir de avaliações legadas;
- decide status localmente;
- grava em `localStorage`;
- aceita autoria funcional do cliente;
- implementa criar/ativar/encerrar/cancelar/reabrir/excluir localmente.

Isso é bloqueador do cutover P8, embora seja esperado no estado pré-P8.

### HIGH — P5/P8

`localCycleRepository.ts` ainda é exclusivamente local; não há adapter Supabase/Edge para ciclos.

### HIGH — P8/F5-10

`metaStorage.ts`, `observacaoStorage.ts`, `cicloEquipeService.ts` e `historicoOrganizacionalStorage.ts` ainda usam ciclo local e/ou bridges `(ano,ciclo)` em decisões operacionais.

### MEDIUM — P8

Muitos testes pré-carregam `feedback-control-ciclos`. São fixtures legadas válidas, mas não podem continuar como prova de autoridade soberana após o cutover.

### LOW/FALSE POSITIVE

`crypto.randomUUID()` em fixtures, mocks e dados sintéticos não representa identidade soberana de ciclo. `localStorage` de sessão, preferências ou testes isolados também não é, por si só, autoridade de ciclo.

## 5. Blockers potenciais para o fechamento

1. Remover a autoridade de `cicloAvaliacaoStorage.ts` sem perder consumidores.
2. Migrar todos os consumidores para `cycleId` UUID com tenant.
3. Garantir leitura own-tenant e RLS sem antecipar P5 em P2–P4.
4. Garantir que Edge use `service_role` apenas como executor.
5. Eliminar fallback local silencioso e dual-write.
6. Cobrir concorrência real e rollback integrado em P9.

## 6. Simplificações recomendadas

- Coordenar P5–P7 compartilhando contratos e fixtures, mantendo PRs separados.
- Definir primeiro um `CycleRepository` UUID-first.
- Reutilizar resoluções existentes de colaboradores, estrutura e capabilities.
- Centralizar bridges `(ano,ciclo)` em uma camada de intenção.
- Não misturar migração de metas/observações com a persistência soberana de ciclos.

## 7. Empacotamento recomendado

**Opção B: P5–P7 coordenados; P8 separado; P9 separado.**

Essa opção respeita dependências técnicas, reduz conflitos, mantém diffs auditáveis e evita misturar autorização, cutover e concorrência em um único PR.

## 8. Ordem ótima

1. P5 — leitura, repository/adapter, ciclo ativo e RLS.
2. P6 — recurso real, capabilities e estado derivado.
3. P7 — Edge, contratos, autorização, bundle admin e D28.
4. P8 — cutover de todos os consumidores, remoção de autoridade local e fallback.
5. P9 — concorrência, rollback, auditoria final e regressões.

## 9. Arquivos de maior risco

- `src/services/cicloAvaliacaoStorage.ts`
- `src/infrastructure/localStorage/localCycleRepository.ts`
- `src/pages/CiclosAvaliacaoPage.tsx`
- `src/services/cicloEquipeService.ts`
- `src/services/metaStorage.ts`
- `src/services/observacaoStorage.ts`
- `src/authorization/authorizationPolicy.ts`
- `src/authorization/resourceContextReal.ts`
- `src/routes/AppRoutes.tsx`

## 10. Não misturar à F5-09

- Migração completa de metas e observações.
- Reestruturação de avaliações F5-06.
- Alterações estruturais F5-07/F5-08.
- Capabilities novas.
- Redesign de frontend.
- Admissão pós-ativação ou transições excepcionais fora das atividades próprias.
- Edge Functions não relacionadas a ciclos.
- Cutover produtivo antes de P8.
- Concorrência integrada antes de P9.

## Conclusão

O repositório está preparado para iniciar P5–P7 de forma coordenada. Ainda existe autoridade local substancial, que deve ser removida explicitamente no cutover P8. Esses resíduos não devem ser tratados como implementação antecipada de P5+ nem como justificativa para misturar escopos.
