# F3-09 — Desenho técnico consolidado (Issue #86)

> **Status:** decisões D1–D9 **fechadas**. Desenho pronto para implementação.
> Preserva F3-01..F3-08 intactas; snapshots F3-08 permanecem imutáveis; sem dados reais.

## 1. Objetivo e escopo da Issue #86

**F3-09 — Mudanças organizacionais durante ciclo.**

Aplicar as regras fechadas para **transferência, sucessão e substituição temporária**
sem perder o snapshot/histórico do ciclo.

Escopo obrigatório: snapshot organizacional/avaliativo na ativação; mudança definitiva de
gestor transfere responsabilidade pendente ao novo gestor; preservar responsável original e
registrar evento de sucessão (data/motivo/autor); avaliação concluída não é reaberta;
substituição temporária permite substituto avaliar e titular reassumir no retorno; substituto
não vira gestor permanente; entrada sem carência; desligamento/licença seguem a Fase B;
múltiplas posições resolvidas separadamente.

Fora do escopo: redesign visual, capabilities/RLS finais, dados reais.

## 2. Estado atual relevante

- Banco: `collaborators`/`collaborator_identifiers`/`collaborator_status_periods` (F3-01),
  `organizational_units`/`organizational_positions` (F3-03), `position_reporting_lines`
  (F3-04), `occupations` (F3-05), `temporary_responsibilities` (F3-06), funções de resolução
  (F3-07), `collegiate_configurations` + `collegiate_cycle_snapshots` + RPC
  `materializar_colegiado_ciclo` (F3-08).
- Frontend (localStorage, intacto): `CicloAvaliacao`, `Feedback`, `Colaborador`
  (denormalizado), `historicoOrganizacionalStorage` (**Fase B**: movimentações com `escopo`
  e outcomes de desligamento/licença), `permissaoAvaliacao` (resolução dinâmica de avaliador).
- "Fase B" = modelo de movimentações/desligamento/licença do frontend (não migrado ao banco).

## 3. Conflito com a F3-08 (resolvido)

A F3-08 declarou snapshots **imutáveis** (D9/D10). A F3-09 resolve isso com uma **camada
separada** (responsabilidade temporal + eventos de sucessão) que **referencia** o snapshot
como "original" e **nunca o muta**. A F3-08 congelou o superior **operacional**; a F3-09
resolve o responsável **avaliativo** (D2), sem reusar `superior_collaborator_id`.

## 4. Decisões fechadas (D1–D9)

- **D1 — A:** sucessão em camada separada; nunca altera o snapshot F3-08.
- **D2 — A:** resolução avaliativa própria — temporary responsibility `evaluative`/
  `operational_evaluative` > titular; não reusar o superior operacional da F3-08.
- **D3 — A:** granularidade por (avaliado/snapshot + `organizational_position` ocupada);
  múltiplas posições = responsabilidades separadas; sem "posição primária".
- **D4 — A:** modelar apenas o gestor direto/responsável avaliativo resolvido estruturalmente;
  sem reificar papéis GERENTE/COORDENADOR; sem inferir hierarquia por job_role/seniority.
- **D5 — A:** sucessão apenas por RPC explícita, transacional e idempotente; sem triggers.
- **D6 — A (refinado):** responsabilidade temporal close+open + evento append-only; a
  responsabilidade ORIGINAL é materializada explicitamente uma única vez a partir do
  contexto aplicável na ativação (nunca reconstruída retroativamente da estrutura atual).
- **D7 — ALTERADO:** `author_user_profile_id uuid NOT NULL` → `user_profiles(id)` (usuário
  autenticado ≠ colaborador; auditoria registra quem executou no sistema, inclusive ator
  administrativo sem collaborator; sem duplicar nome/e-mail textual).
- **D8 — A (refinado):** o chamador determina quais relações ainda estão pendentes; a RPC
  recebe explicitamente as responsabilidades afetadas por IDs canônicos
  (`cycle_evaluation_responsibilities.id` ou `snapshot_id + position_id`); o banco só altera
  responsabilidade aberta, nunca reabre encerrada, preserva histórico e não cria status de
  avaliação. Documentar que a garantia de não enviar avaliação CONCLUIDA pertence ao
  chamador enquanto o domínio de avaliações viver no localStorage (reforço server-side na
  migração futura).
- **D9 — A:** reusar leave/inactive/desligamento existentes; não migrar "escopo" das
  movimentações; sem carência; o chamador fornece explicitamente o conjunto afetado.

### Regras adicionais consolidadas

- Preservar F3-01..F3-08 intactas; snapshots F3-08 continuam imutáveis.
- temporary responsibility nunca transforma substituto em gestor histórico permanente;
  encerrado o período, a resolução avaliativa volta ao responsável permanente vigente.
- FKs compostas multi-organização + `ON DELETE RESTRICT`; RLS deny-by-default; sem
  capabilities/RLS finais; sem migração completa de ciclos/avaliações; sem dados reais.

## 5. Modelo resultante

### 5.1 Responsabilidade congela o responsável PERMANENTE (titular); substituto é overlay vivo

Consequência direta de D2 + D6 + D9 (não é regra nova):

- `cycle_evaluation_responsibilities` guarda o responsável **permanente** (titular da posição
  superior na data), materializado na ativação e alterado **somente** por sucessão
  (close+open).
- O substituto avaliativo **não** é congelado: ele é resolvido **por data** na consulta
  (`resolver_responsavel_avaliacao_vigente`) e nunca grava linha de responsabilidade. Assim,
  ao encerrar a substituição, a resolução volta naturalmente ao responsável permanente, e o
  substituto jamais aparece como gestor histórico permanente.

### 5.2 Funções de resolução avaliativa (espelho da F3-07)

- `organizacao_resolver_responsavel_avaliativo_posicao(position_id, data)` →
  `(position_id, titular_collaborator_id, substitute_collaborator_id, responsible_collaborator_id)`
  — `responsible = substituto avaliativo > titular`; `SECURITY INVOKER`/`STABLE`.
- `organizacao_resolver_avaliador_avaliado(collaborator_id, data)` →
  `(occupied_position_id, manager_position_id, manager_collaborator_id)` — por posição
  ocupada, a posição superior (reporting line) e o responsável avaliativo (substituto >
  titular). Uma pessoa com várias posições produz várias linhas (D3).

### 5.3 Tabelas

- `cycle_evaluation_responsibilities` (temporal close+open): `id`, `organization_id`,
  `snapshot_id` (→ `collegiate_cycle_snapshots(id, organization_id)`), `position_id`
  (→ `organizational_positions(id, organization_id)`), `responsible_collaborator_id`
  (→ `collaborators(id, organization_id)`), `valid_from`, `valid_to` (null = vigente),
  timestamps/version; exclusion de não-sobreposição por `(snapshot_id, position_id)`.
- `evaluation_succession_events` (imutável/append-only): `id`, `organization_id`,
  `snapshot_id`, `position_id`, `previous_responsible_collaborator_id`,
  `new_responsible_collaborator_id`, `succession_date`, `motive` (trim não-vazio),
  `author_user_profile_id` (→ `user_profiles(id)`, FK simples — D7), `created_at`; sem
  `updated_at`/`version`; unique `(snapshot_id, position_id, succession_date)` (idempotência).

### 5.4 RPCs (SECURITY INVOKER)

- `materializar_responsabilidades_avaliacao(p_organization_id, p_ano, p_ciclo)` → `void`:
  lê os snapshots F3-08 já materializados e, para cada posição ocupada com superior, resolve
  o titular (responsável permanente) da posição superior na `reference_date` do snapshot e
  insere **uma** responsabilidade original por `(snapshot, position)`; idempotente.
- `registrar_sucessao_avaliador(p_responsibility_ids uuid[], p_succession_date timestamptz,
  p_motive text, p_author_user_profile_id uuid)` → `void`: transacional/idempotente; para
  cada responsabilidade **aberta** afetada, resolve o novo responsável permanente (titular)
  da posição superior na data, fecha a linha aberta e abre a nova, e grava o evento de
  sucessão (data/motivo/autor). Só afeta responsabilidade aberta; nunca reabre encerrada.
- `resolver_responsavel_avaliacao_vigente(p_organization_id, p_ano, p_ciclo, p_data)` →
  por `(snapshot, position)`: responsável permanente vigente na data + overlay do substituto
  avaliativo ativo na data.

### 5.5 Limites determinados (comportamentos documentados, não bloqueiam)

- Sucessão considera mudança do **titular** da posição superior congelada no snapshot; mudança
  de reporting line do avaliado não é recalculada retroativamente (snapshot imutável — D1/D6).
- Posição superior **vaga sem substituto avaliativo** na data da sucessão → a RPC rejeita
  (fail-closed, "sem novo responsável resolvido"); não inventa responsável e não fecha para
  "vago" (não há conceito de responsabilidade vaga na Issue).
- Posição ocupada **sem superior** (raiz) → não gera responsabilidade de avaliação.

## 6. Fora do escopo (reafirmado)

Redesign visual; capabilities/RLS finais; dados reais; migração do domínio de
avaliações/ciclos; migração das movimentações (Fase B); agregação "avaliador único quando há
2 gerentes" (adiada para a fase de avaliação).

## 7. Implementação prevista

1. Migration `20260907190000_evaluator_responsibility_succession.sql` (funções + 2 tabelas +
   RPCs + RLS deny-by-default).
2. Validação `supabase/validacao/01-cenario-f3-09.sql` + `02-validar-f3-09.sql`
   (rebuild limpo, duas execuções).
3. Documentação (`supabase/README.md`, `supabase/migrations/README.md`,
   `supabase/validacao/README.md`).
4. `npm test` / `npm run build` / `npm run lint` / `git diff --check`.
5. Branch própria, commit, push e PR com `Closes #86` (sem merge).
