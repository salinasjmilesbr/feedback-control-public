# Documento histórico de auditoria

> **Status:** HISTÓRICO / NÃO NORMATIVO  
> **Data do checkpoint:** 10/09/2026  
> **Contexto:** diagnóstico transversal do repositório após a conclusão da F5-06.  
> **Uso:** evidência histórica para rastreabilidade do planejamento da Etapa 5.  
> **Fonte vigente para estado atual e próximos passos:** Plano Mestre e contratos `docs/F5-XX-desenho-tecnico.md` fechados.  
> **Importante:** o roadmap proposto neste diagnóstico foi posteriormente refinado durante a revisão arquitetural da F5-07. O roadmap vigente passou a ser F5-07 a F5-12, incluindo F5-08 — Estrutura organizacional e catálogos soberanos.

---

# VIRTUS — Diagnóstico do restante da Etapa 5

## Verdict

**VERDICT: CHANGES REQUIRED**

A auditoria foi somente de leitura. Nenhum arquivo de código foi alterado.

## 1. Resumo executivo

- F5-01 a F5-06 estão implementadas conforme seus escopos individuais.
- A trilha de avaliações novas está soberana no PostgreSQL/Supabase.
- O principal trabalho restante é concluir a migração dos domínios ainda dependentes de `localStorage`.
- Portanto, F5-06 está concluída, mas a Etapa 5 ainda não deve ser declarada encerrada.
- Não foi identificado novo bypass crítico introduzido por F5-06.
- O risco atual é arquitetural/de produto: parte relevante do sistema multiusuário ainda não é server-sovereign.

## 2. Matriz do estado real

| Domínio | Classificação | Evidência |
|---|---|---|
| Identidade `auth.uid()` | SOBERANO | Edge Functions usam `auth.getUser`; identidade não vem do payload. |
| Tenant/membership | SOBERANO | Membership ativa e organização são revalidadas server-side; falhas negam acesso. |
| Organização ativa | SOBERANO | `src/auth/organizacaoAtiva.ts` mantém apenas intenção local; autorização real ocorre no servidor. |
| Vínculo usuário–colaborador | SOBERANO | F5-02/F4 usam `membership_collaborator_links` e resolução server-side. |
| Policy Engine das avaliações | SOBERANO | Fluxo Edge → `authorize`/Policy Engine → RPC SQL. |
| Policy Engine legado | HÍBRIDO | Ainda existem caminhos de UX/política local em `authorizationPolicy.ts` e `localWorld.ts`. |
| ResourceContext de avaliação | SOBERANO | Avaliação é carregada server-side; colaborador, ciclo, status e participante vêm do banco. |
| Avaliações novas | SOBERANO | Criadas/editadas/concluídas no PostgreSQL via Edge/RPC. |
| Avaliações legadas | LEGADO | `feedbackStorage.ts` permanece somente leitura. |
| Participantes/snapshots | SOBERANO | Ocorrência, vigência e snapshot são resolvidos no banco. |
| Cálculo oficial | SOBERANO | SQL é a autoridade para notas e consolidação. |
| Ciclos | HÍBRIDO | `evaluation_cycles` existe, mas criação, edição, ativação, encerramento, cancelamento e reabertura continuam em `cicloAvaliacaoStorage.ts`. |
| Colaboradores | LEGADO | `colaboradorStorage.ts` continua sendo a fonte operacional da UI. |
| Histórico organizacional | LEGADO | `historicoOrganizacionalStorage.ts` calcula e persiste localmente. |
| Metas | LEGADO | `metaStorage.ts` usa exclusivamente `localStorage`; não há tabela PostgreSQL correspondente. |
| Observações | LEGADO | `observacaoStorage.ts` usa exclusivamente `localStorage`. |
| Escala de avaliação | HÍBRIDO | Configuração de avaliações novas está no banco; escala legada permanece local. |
| Cache/navegação/sessão | HÍBRIDO | Valores locais são intenção/cache; não concedem autoridade, mas ainda influenciam telas legadas. |
| RLS | SOBERANO nas tabelas F5 | Tabelas F5-06 possuem isolamento por tenant e grants restritos. |
| Auditoria de avaliações | SOBERANO | `evaluation_events` é append-only no fluxo novo. |
| Auditoria dos domínios legados | LEGADO | Ciclos, metas, observações e histórico ainda não possuem trilha server-side equivalente. |

## 3. Gaps bloqueantes para concluir a Etapa 5

### BLOCKER — Ciclos ainda têm autoridade local

- **Arquivo/função:** `src/services/cicloAvaliacaoStorage.ts` — `getCiclosAvaliacao`, `criarCiclo`, `ativarCiclo`, `encerrarCiclo`, `cancelarCiclo`, `reabrirCiclo`.
- **Problema concreto:** o ciclo usado pela aplicação ainda pode ser criado ou alterado em `localStorage`, embora avaliações novas dependam de `evaluation_cycles`.
- **Cenário:** usuário acessa outro navegador, perde o `localStorage`, ou outro administrador altera o ciclo.
- **Impacto:** ciclo pode não ser descoberto, ter estado divergente entre clientes e impedir ou alterar indevidamente a criação e conclusão de avaliações.
- **Correção recomendada:** migrar o ciclo completo para PostgreSQL, com lifecycle transacional, RLS, Policy Engine, listagem server-side e remoção da autoridade local.

### BLOCKER — Colaboradores e histórico estrutural ainda são locais

- **Arquivos/funções:** `src/services/colaboradorStorage.ts`, `src/services/historicoOrganizacionalStorage.ts`, telas `NovoColaboradorPage`, `EditarColaboradorPage`, `ColaboradorDetalhePage`.
- **Problema concreto:** CRUD, histórico e parte da resolução operacional continuam dependentes de `localStorage`, apesar de existirem tabelas F3 para colaboradores, identificadores, vigência e sucessão.
- **Cenário:** dois administradores usam navegadores diferentes ou um cliente mantém cache stale.
- **Impacto:** divergência de tenant, perda de alterações, histórico inconsistente e impossibilidade de garantir a mesma identidade soberana usada nas avaliações.
- **Correção recomendada:** conectar as telas aos repositórios/RPC server-side, usando UUID do colaborador, membership, vigência, sucessão e RLS como autoridade.

### BLOCKER — Metas e observações permanecem fora da autoridade PostgreSQL

- **Arquivos/funções:** `src/services/metaStorage.ts`, `src/services/observacaoStorage.ts`, telas de metas e observações.
- **Problema concreto:** esses domínios não possuem fonte server-side equivalente; não há tabelas PostgreSQL correspondentes nas migrations atuais.
- **Cenário:** alterações feitas por um usuário não são refletidas para outro tenant/browser.
- **Impacto:** a Etapa 5 não pode ser considerada multiusuário e tenant-safe de ponta a ponta.
- **Correção recomendada:** criar schema, políticas, RPC/Edge, auditoria append-only, transações e cutover dos consumidores.

Esses blockers não invalidam a conclusão da F5-06, pois o próprio desenho de F5-06 declarou ciclos, colaboradores, metas e observações como atividades próprias.

## 4. Itens não bloqueantes

- `feedbackStorage` legado somente leitura.
- Importação de histórico real antigo.
- Escala/expectativas locais usadas apenas por telas legadas.
- Ausência de exclusão de nota/comentário, se mantida como decisão de produto.
- Negação fail-closed quando existem duas ocorrências vigentes.
- Redesign visual e hardening/observabilidade de F6.

Nenhum desses itens deve ser usado como justificativa para reabrir decisões fechadas de F5-06 sem evidência técnica nova.

## 5. Plano mínimo recomendado

### F5-07 — Colaboradores e histórico organizacional PostgreSQL

Campos mínimos:

- identidade e membership;
- tenant/RLS;
- colaboradores e identificadores;
- períodos de status;
- sucessão e responsabilidades;
- Policy Engine;
- auditoria;
- cutover das telas e serviços locais.

### F5-08 — Ciclos de avaliação PostgreSQL

Campos mínimos:

- ciclo, ano, número, status e configuração;
- criação/edição/ativação/encerramento/cancelamento/reabertura;
- unicidade por tenant;
- transações com avaliações e pendências;
- listagem e descoberta server-side;
- remoção da autoridade de `cicloAvaliacaoStorage`.

### F5-09 — Metas e observações PostgreSQL

Campos mínimos:

- schema multi-tenant;
- ownership e vínculos de colaborador;
- Policy Engine/RLS;
- vigência e histórico;
- auditoria append-only;
- migração das telas e serviços;
- eliminação de escrita local.

**Total mínimo recomendado: 3 atividades.**

## 6. Gate recomendado para encerrar a Etapa 5

### Obrigatório

- todos os domínios ativos com fonte PostgreSQL soberana;
- `auth.uid()` como raiz de identidade;
- tenant/membership revalidados server-side;
- Policy Engine em toda mutação real;
- RLS e fail-closed;
- ausência de autoridade em cargo, payload, UUID isolado ou `localStorage`;
- transações críticas e auditoria append-only;
- testes de cross-tenant, revogação, IDOR e concorrência;
- avaliações novas permanecendo SQL-authoritative.

### Pode permanecer transitório

- leitura de avaliações legadas;
- cache, sessão e organização selecionada no navegador;
- dados DEV/localWorld;
- importação de histórico antigo explicitamente fora de escopo.

## 7. Questões abertas

Nenhuma questão arquitetural precisa ser reaberta. A recomendação é tratar os três domínios restantes como pré-requisitos objetivos para o fechamento da Etapa 5.

## 8. Evidências principais

- `src/services/cicloAvaliacaoStorage.ts`
- `src/services/colaboradorStorage.ts`
- `src/services/metaStorage.ts`
- `src/services/observacaoStorage.ts`
- `src/services/historicoOrganizacionalStorage.ts`
- `src/services/feedbackStorage.ts`
- `src/services/cicloEquipeService.ts`
- `src/authorization/authorizationPolicy.ts`
- migrations F3/F4/F5-06 em `supabase/migrations`
- `supabase/functions/avaliacoes/index.ts`
- `docs/F5-06-desenho-tecnico.md`
- `.ai/handoff.md`
- [Issue #103](https://github.com/salinasjmilesbr/feedback-control-public/issues/103)

## Conclusão

Os blockers anteriores de F5-06 estão resolvidos, mas ainda existem blockers de escopo maior para declarar a Etapa 5 encerrada.
