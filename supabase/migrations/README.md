# Migrations e padrões do PostgreSQL — F1-02

Entrega documental que define e versiona as convenções que todas as migrations
do Virtus Team devem seguir. Esta fase não cria migration, tabela, schema de
domínio, Auth, RLS, seed, procedure ou transação de negócio: apenas fixa os
padrões técnicos que serão aplicados pela F1-03 (foundation) e pelas fases
seguintes. Nenhuma regra aqui substitui a Especificação v1.0 nem as regras de
negócio, autorização, workflow, persistência e auditoria da aplicação.

## Migrations atuais

| Migration | Propósito |
| --- | --- |
| `20260906185540_foundation.sql` | Foundation técnica (F1-03): helper de trigger `set_updated_at` e padrões documentados de UUID, timestamps e versionamento; sem entidades funcionais. |
| `20260906201856_organizations_user_profiles.sql` | F2-01 (Issue #68): entidades-base de identidade `organizations` e `user_profiles` (perfil interno ligado 1:1 a `auth.users`), timestamps/version conforme F1-02, RLS habilitado e deny-by-default, sem policies nesta etapa. |
| `20260906203358_user_organization_memberships.sql` | F2-02 (Issue #69): membership usuário-organização (`user_organization_memberships`) por UUID, status e unique por par usuário/organização; sem `collaborator_id` nesta etapa (tabela de colaboradores ainda não existe); RLS habilitado e deny-by-default, sem policies. |
| `20260906205425_auth_read_policies.sql` | F2-03 (Issue #70): policies mínimas de leitura para o usuário autenticado resolver o próprio perfil, as próprias memberships e as organizações de membership ativa (`auth.uid()`), com grants de SELECT somente a `authenticated`; sem policies de escrita. |
| `20260906230400_criar_perfil_membership_rpc.sql` | F2-06 (Issue #73): RPC `criar_perfil_membership` (SECURITY DEFINER, EXECUTE só para `service_role`) que cria perfil interno + membership em uma única transação — fronteira server-side do convite administrativo. |
| `20260907000250_desativacao_perfil_policy.sql` | F2-07 (Issue #74): reforça a policy `user_profiles_select_own` para exigir `status = 'active'` — um perfil desabilitado deixa de ser resolvido pelo próprio usuário (enforcement server-side). |
| `20260907103000_enable_btree_gist.sql` | F3-01 (Issue #78): extensão `btree_gist` habilitada em migration dedicada (convenção F1-02), necessária para as exclusion constraints temporais das tabelas de lifecycle. |
| `20260907103100_collaborators_identifiers_status_periods.sql` | F3-01 (Issue #78): `collaborators` (identidade técnica UUID por organização), `collaborator_identifiers` (códigos de negócio com validade temporal, unique por organização) e `collaborator_status_periods` (lifecycle `active`/`leave`/`inactive` com linha do tempo única); FKs `ON DELETE RESTRICT`, checks de validade temporal, exclusion constraints de não-sobreposição, triggers `set_updated_at` e RLS deny-by-default sem policies. |
| `20260907120000_job_roles_seniority_levels.sql` | F3-02 (Issue #79): catálogos configuráveis por organização `job_roles` e `seniority_levels` — conceitos independentes entre si, da hierarquia e da autorização; `name` único por organização (check de trim), `status` `active`/`disabled` (desativação sem exclusão física), sem coluna de ordenação/rank, sem FKs cruzadas entre catálogos, FKs `ON DELETE RESTRICT` para `organizations`, triggers `set_updated_at` e RLS deny-by-default sem policies. |
| `20260907130000_organizational_units_positions.sql` | F3-03 (Issue #80): estrutura formal — `organizational_units` (name único por org, existência temporal `valid_from`/`valid_to` na própria linha), `organizational_unit_parent_periods` (composição temporal pai/filho: parent null = raiz, exclusion de um parent vigente por unidade, auto-parent proibido, histórico de reestruturação) e `organizational_positions` (unidade + job_role + seniority opcional, existência temporal, sem ocupante/collaborator_id); FKs compostas `(ref_id, organization_id)` para tenant integrity declarativa (com unique de referência aditiva em `job_roles`/`seniority_levels`), FKs `ON DELETE RESTRICT`, triggers `set_updated_at` e RLS deny-by-default sem policies. |
| `20260907140000_position_reporting_lines.sql` | F3-04 (Issue #81): hierarquia formal temporal — `position_reporting_lines` (subordinado → superior formal, `manager_position_id NOT NULL` com raiz por ausência de linha, `reason` obrigatório, período meio-aberto `valid_from`/`valid_to`, exclusion de um superior vigente por subordinado, self-reporting proibido); triggers de integridade (período contido na validade das posições; ciclos multi-nível recursivos temporais com `pg_advisory_xact_lock` por org; fechamento de posição fail-closed), unique de referência aditiva em `organizational_positions`, FKs compostas + `ON DELETE RESTRICT` e RLS deny-by-default sem policies. |
| `20260907150000_occupations.sql` | F3-05 (Issue #82): ocupações temporais — `occupations` (colaborador ↔ posição formal da mesma organização, `reason` obrigatório, período meio-aberto, exclusion de um ocupante por instante por posição — múltiplas posições simultâneas por colaborador livres); triggers de integridade (occupation contida na validade da posição; desligamento `inactive` bloqueado enquanto houver occupations vigentes — fail-closed, sem auto-cascade), FKs compostas `ON DELETE RESTRICT` e RLS deny-by-default sem policies. |
| `20260907160000_temporary_responsibilities.sql` | F3-06 (Issue #83): substituições temporárias — `temporary_responsibilities` (alvo = `organizational_position`, `substitute_collaborator`, `responsibility_type` `operational`/`evaluative`/`operational_evaluative`, `reason` obrigatório, período OBRIGATORIAMENTE fechado `[valid_from, valid_to)`, exclusion de uma responsabilidade por instante por posição — múltiplas posições por substituto livres; titular derivado de `occupations`); triggers de integridade (período contido na validade da posição; auto-substituição temporal proibida), FKs compostas `ON DELETE RESTRICT` e RLS deny-by-default sem policies. |
| `20260907170000_organization_resolution.sql` | F3-07 (Issue #84): resolução organizacional — funções SQL `SECURITY INVOKER`/`STABLE` sem grants que resolvem por data `responsavel_posicao` (titular + substituto + responsável efetivo), `gestor_direto`, `subordinados_diretos`, `descendentes`, `cadeia`, `escopo_posicoes` e `escopo_unidades` — gestor derivado da estrutura (sem campo redundante), posição vaga sem corromper a cadeia, múltiplas occupations com união coerente, distinção titular×substituto e sem filtragem por status/cargo. |
| `20260907180000_collegiate_configuration_snapshot.sql` | F3-08 (Issue #85): colegiado padrão e snapshot por ciclo — `collegiate_configurations` (+`_members`) com versões temporais por colaborador avaliado (0..N explícito, sem self/duplicados/cross-org) e `collegiate_cycle_snapshots` (+`_positions`/+`_members`) imutáveis keyed por `(organization_id, ano, ciclo, collaborator_id)` com posições ocupadas e superior direto resolvido na data; RPC `materializar_colegiado_ciclo` transacional/idempotente (ativação); FKs compostas `ON DELETE RESTRICT` e RLS deny-by-default sem policies. |
| `20260907190000_evaluator_responsibility_succession.sql` | F3-09 (Issue #86): responsabilidade avaliativa e sucessão de avaliador — funções de resolução avaliativa (`organizacao_resolver_responsavel_avaliativo_posicao`/`organizacao_resolver_avaliador_avaliado`: substituto `evaluative`/`operational_evaluative` > titular, por posição); `cycle_evaluation_responsibilities` (temporal close+open por `(snapshot, posição)`, congela o titular); `evaluation_succession_events` (imutável/append-only, data/motivo/`author_user_profile_id`); RPCs `materializar_responsabilidades_avaliacao` e `registrar_sucessao_avaliador` (transacionais/idempotentes) e `resolver_responsavel_avaliacao_vigente`; FKs compostas `ON DELETE RESTRICT` e RLS deny-by-default sem policies. |
| `20260908000000_authorization_capabilities_access_roles.sql` | F4-01 (Issue #88): modelo explícito de autorização — `capabilities` (catálogo global, `code` único em notação `domínio.verbo`, `status` active/disabled), `access_roles` (sistema `is_system`/org null + customizadas por organização, com unicidade parcial de nome de sistema), `access_role_capabilities` (N:N role→capability) e `membership_access_role_assignments` (membership→role, unique por par, `status` active/revoked, `created_by` autor mínimo); FK composta aditiva `(id, organization_id)` em memberships + FK composta de tenant + trigger `enforce_membership_role_within_organization` (role customizada de outra org bloqueada); funções server-side `conceder_acesso_role`/`revogar_acesso_role`/`resolver_capabilities_efetivas` (SECURITY DEFINER, EXECUTE só `service_role`); FKs `ON DELETE RESTRICT` e RLS deny-by-default nas quatro tabelas. |
| `20260908000001_authorization_system_catalog.sql` | F4-01 (Issue #88): catálogo de sistema determinístico/versionado — 21 capabilities globais (UUIDs fixos prefixo `c0`) e o access_role de sistema `admin` (conjunto mínimo de roles, D14) com bundle de 9 capabilities de administração, **sem** conteúdo confidencial (D18); nenhuma capability confidencial genérica. |
| `20260908010000_authorization_scopes_membership_collaborator.sql` | F4-02 (Issue #89): escopos de autorização — referência aditiva `(id, organization_id)` em assignments; `membership_collaborator_links` (vínculo membership→collaborator, 1 por membership, tenant por FKs compostas — D1); `access_role_assignment_scopes` (tabela filha 1:N por assignment, tipos SELF/DIRECT_REPORTS/DESCENDANTS/ORGANIZATIONAL_UNIT/ORGANIZATION/ASSIGNED, status active/revoked — D2/D3/D4/D5/D11); `access_role_assignment_unit_targets` (target tipado da unidade, trigger de tipo de scope — D5/D6); funções `resolver_collaborador_vinculado`/`resolver_capabilities_escopos_efetivas`/`resolver_alvos_escopo` (SECURITY INVOKER/STABLE — D18) e `enforce_unit_target_scope_type`; FKs `ON DELETE RESTRICT` e RLS deny-by-default nas três tabelas novas. |
| `20260909000000_f5_02_hardening_resolver_collaborador.sql` | F5-02 (Issue #161): endurece `resolver_collaborador_vinculado` para exigir `user_profiles.status='active'` (Q4=A; profile ausente/inativo/desconhecido ⇒ vazio) — paridade com `resolver_capabilities_escopos_efetivas`; mantém `SECURITY INVOKER`/STABLE e fechado para `authenticated` (Q1=A; sem superfície nova; F4-02 D18 inalterado). `create or replace` preserva grants. |
| `20260909010000_f5_02_link_active_uniqueness.sql` | F5-02 (Issue #161): cardinalidade/histórico — remove o unique TOTAL de `membership_id` e cria dois **unique indexes parciais** (1 `status='active'` por membership — Q6=B; 1 `status='active'` por `(collaborator_id, organization_id)` — Q3=B); linhas `disabled` permanecem como histórico. Exceção documentada à F1-02 (unicidade parcial exige unique index com predicado — `UNIQUE` constraint não aceita `WHERE`). FKs compostas preservadas (tenant correlation). |
| `20260909020000_f5_02_link_mutation_functions.sql` | F5-02 (Issue #161): caminho administrativo server-side/transacional (D9) — funções `vincular_colaborador`/`desativar_vinculo_colaborador`/`trocar_vinculo_colaborador` (`SECURITY INVOKER`, `EXECUTE` só `service_role`); troca atômica (desativa ativo + insere novo; nunca `UPDATE` de `collaborator_id`; rollback total em falha); sem DML direto para `authenticated` e sem `valid_from`/`valid_to`. |
| `20260910000000_f5_04_catalog_reconciliation.sql` | F5-04 (Issue #165): reconciliação do catálogo de capabilities (D14/D15) — colunas aditivas `grantable_via_role`/`deprecated` em `capabilities`; +10 capabilities canônicas (ações granulares de ciclo/observação/colaborador + `exceptional_access.grant`/`pilot_full_access.grant`); depreca `collaborator.manage`/`observation.write` (sem remoção física); ajusta o bundle `admin` para 8 capabilities funcionais (sem controle, sem deprecado, sem confidencial); trigger `enforce_role_capability_grantable` (controle/deprecada nunca transitam por role); endurece `resolver_capabilities_efetivas`/`resolver_capabilities_escopos_efetivas` para excluir deprecadas (fail-closed). |
| `20260910010000_f5_04_privilege_audit_trail.sql` | F5-04 (Issue #165): trilha append-only de mutações de privilégio (D18) — `privilege_mutation_audit` (grant/revoke com autoria soberana `actor_user_profile_id`); imutabilidade no caminho de aplicação (UPDATE bloqueado por trigger; UPDATE/DELETE/TRUNCATE revogados de `service_role`, que mantém só SELECT+INSERT — higienização exclusiva do proprietário/superuser); RLS deny-by-default sem policies/grants a `authenticated`. |
| `20260910020000_f5_04_admin_rpc_functions.sql` | F5-04 (Issue #165): operações administrativas server-side/transacionais (D16/Q3) — `conceder_acesso_role_rpc`/`revogar_acesso_role_rpc` (`SECURITY INVOKER`, `EXECUTE` só `service_role`); ator = identidade autenticada VERIFICADA server-side (`auth.getUser` na Edge Function) passada como parâmetro (nunca do cliente), separada da execução privilegiada service_role; tenant revalidado (cross-tenant DENY); anti-self-escalation; **autorização administrativa** via `usuario_eh_administrador` (membership ativa com role de sistema `admin` no tenant — coerente com D15, sem capability auto-servida); gravação da trilha append-only (D18). |
| `20260911000000_f5_06_evaluation_schema.sql` | F5-06 (Issue #103): schema de avaliações orientado a **participantes** — 12 tabelas (`evaluation_config_versions`/`_criteria`/`_subcriteria`/`_scale_bands`/`_participant_roles`, `evaluation_cycles`, `evaluations`, `evaluation_participants`, `evaluation_scores`, `evaluation_comments`, `evaluation_events`, `evaluation_pendencies`); participantes como **ocorrências históricas** (`valid_from`/`valid_to` + exclusion `ex_evaluation_participants_vigencia`, sem unique eterno); unique **parcial** `uq_evaluations_org_cycle_collaborator_nao_cancelada` (`WHERE status <> 'CANCELADA'`); 28 FKs (12 compostas de tenant `(id, organization_id)`, todas `ON DELETE RESTRICT`), 40 checks (nota `1..5` e domínios de status/papel/escopo) e agregados em `numeric(12,8)` (nunca float); trigger append-only `trg_evaluation_events_append_only`; RLS habilitado nas 12 tabelas com zero policies e DML/SELECT revogados de `anon`/`authenticated`. |
| `20260911010000_f5_06_evaluation_functions.sql` | F5-06 (Issue #103): cálculo oficial e workflow server-side — tabela `evaluation_aggregates` (agregados materializados por critério/subcritério em `numeric(12,8)`, 13ª tabela do domínio); funções `evaluation_ator_valido` (membership ativa revalidada server-side), `evaluation_config_bootstrap` (baseline idempotente: 8 critérios, 25 subcritérios, 5 faixas de escala 5→4.7/4→3.9/3→2.9/2→2.0/1→1.0 e 3 papéis de participante), `evaluation_calcular` (D24/D25: **colegiado como UMA parcela agregada** — média dos votos válidos —, sem arredondamento intermediário e tolerância de paridade `1e-8`), `evaluation_criar` (snapshot de ocorrências de participante + evento `CRIADA` na mesma transação), `evaluation_gravar_notas`, `evaluation_gravar_comentario`, `evaluation_pendencias_calcular` (completude conforme a configuração congelada), `evaluation_concluir` (exige completude — D18), `evaluation_reabrir`/`evaluation_cancelar` (motivo obrigatório, auditados), `evaluation_fechar_ciclo_pendencias` (marcador permanente + pendências **sem** concluir automaticamente) e `evaluation_leitura_avaliado` (projeção de transparência do avaliado: agregados + lista do colegiado, **nunca** voto/nota individual nem `participant_id` correlacionado); todas `SECURITY INVOKER` com `EXECUTE` somente `service_role`. |

| `20260915000000_f5_09_cycle_sovereign.sql` | F5-09 P1: fundação soberana de ciclos e trilha de auditoria — **I5** índice único **parcial** `uq_evaluation_cycles_org_ativo` (no máximo um ciclo `ATIVO` por organização, regra que existia só no cliente); **I6** exclusion **parcial** `ex_evaluation_cycles_periodo_no_overlap` (`organization_id` + `daterange(data_inicio, data_fim + 1, '[)')`, `data_fim` **inclusiva** para o produto e comparação meio-aberta, com `CANCELADO` e linhas sem período fora do índice); **D8/D9** `DELETE`/`TRUNCATE` de `evaluation_cycles` revogados de `public`/`anon`/`authenticated`/`service_role` (exclusão física proibida — cancelamento é o encerramento definitivo, RPC no P4); tabela **`cycle_events`** append-only (trilha de mutações oficiais: 4 FKs — inclui a FK **composta** `(cycle_id, organization_id)` e a de autoria `(actor_membership_id, organization_id)` —, `unique (organization_id, operation_id)` para idempotência, `payload_hash` em SHA-256 hex, CHECKs de `entity_type`/`event_type` — já incluindo `ADMISSAO_INCLUIDA` do P3 —, `reason` e hash, trigger `trg_cycle_events_append_only`, RLS deny-by-default integral com `service_role` recebendo apenas `SELECT`/`INSERT`); helper `ciclo_ator_valido` (perfil + membership ativa + allowlist fechada das capabilities de ciclo + capability efetiva, reusando `evaluation_ator_valido`/`resolver_capabilities_efetivas`) e `ciclo_lock_organizacao` (chave **normativa** única da família: `evaluation_cycles:<organization_id>`); `pre-flight` de baseline e guarda final fail-closed. **Sem RPCs `ciclo_*`** (P2+) e **sem** policy de leitura (P5). |

| `20260916000000_f5_09_cycle_rpc.sql` | F5-09 P2: RPCs soberanas de gestão de ciclo — `ciclo_criar` (T0: nasce `PLANEJADO` com `version=0`, período explícito e versão de configuração do `evaluation_config_bootstrap`; evento `CRIADO`), `ciclo_editar` (T1: só ciclo `PLANEJADO`, edita ano/número/período com `expected_version`; evento `EDITADO` com before/after), `ciclo_ativar` (T2: `PLANEJADO`→`ATIVO` materializando **na mesma transação** o snapshot de colegiado da população elegível — colaboradores com status `active` vigente no instante — por `materializar_colegiado_ciclo` (F3-08) e as responsabilidades de avaliação por `materializar_responsabilidades_avaliacao` (F3-09); recusa sem `config_version_id` e com outro `ATIVO` na organização; evento `ATIVADO`) e `ciclo_encerrar` (T3: `ATIVO`→`ENCERRADO` reusando `evaluation_fechar_ciclo_pendencias` (F5-06) para marcar pendências permanentes e gravar os contadores do ciclo; evento `ENCERRADO` com motivo obrigatório). Todas `SECURITY INVOKER`, `search_path` fixo, `EXECUTE` só `service_role`, idempotentes por `(organization_id, operation_id)` + hash canônico derivado server-side, serializadas pela chave normativa `evaluation_cycles:<organization_id>` (P1), com preflight fail-closed das primitivas e guarda final. **Sem** cancelar/reabrir/corrigir período (P4), **sem** admissão posterior (P3) e **sem** leitura de cliente (P5). |
| `20260917000000_f5_09_cycle_admission.sql` | F5-09 P3: inclusão aditiva soberana de nova admissão em ciclo `ATIVO` (D26) — helper **`ciclo_admissao_pos_ativacao_elegivel`** (`SECURITY INVOKER`, `STABLE`, **read-only**) que aplica as provas **P1–P7** do §7.2 (P1 evento soberano `ADMISSAO` com `cycle_scope = 'CICLO_ATUAL_E_POSTERIORES'` e `effective_date > data_ativacao`; P2 ausência de período de status anterior à ativação; P3 aditividade — recusa se o colaborador já está materializado no ciclo; P4 ciclo `ATIVO` do tenant; P5 status `active` vigente e estrutura resolvida **somente** nas fontes relacionais — ocupação/posição/reporting line; P6 `SOMENTE_CICLOS_POSTERIORES` recusado de forma **estrita**; P7 ausência de prova ⇒ **fail-closed**, com `collaborators.admission_date` explicitamente **não** valendo como prova) e devolve elegibilidade + motivo da recusa + evidências; e RPC **`ciclo_incluir_admissao`** (`p_cycle_id`, `p_organization_id`, `p_collaborator_id`, `p_motivo`, `p_expected_version`, `p_actor_user_profile_id`, `p_operation_id` — **nenhum parâmetro estrutural**) que exige ator com membership ativa + `cycle.manage` (capability **reusada**, nenhuma capability nova), `expected_version` e motivo, e materializa de forma **exclusivamente aditiva** reusando `materializar_colegiado_ciclo` (F3-08) com **um único** `collaborator_id` e `materializar_responsabilidades_avaliacao` (F3-09, idempotente), sem `UPDATE`/`DELETE` em nenhuma tabela de snapshot/responsabilidade; grava **um** evento `ADMISSAO_INCLUIDA` na mesma transação, com o id do evento `ADMISSAO` que autorizou, posição/unidade/superior resolvidos e a `version` resultante; serializada por `ciclo_lock_organizacao` (chave `evaluation_cycles:<organization_id>`) e idempotente por `(organization_id, operation_id)` + SHA-256 derivado server-side; guarda final fail-closed (assinatura, `INVOKER`, `search_path`, ACL só `service_role`, ausência de escrita direta em snapshot e ausência de P4+). **Sem** cancelar/reabrir/corrigir período (P4) e **sem** leitura de cliente (P5). |
| `20260918000000_f5_09_cycle_exceptional_transitions.sql` | F5-09 P4: transições excepcionais soberanas de ciclo — **`ciclo_cancelar`** (T4/T5, `cycle.cancel`): `PLANEJADO`\|`ATIVO` → `CANCELADO` (terminal, D8) com motivo obrigatório e `expected_version`; em ciclo `ATIVO` resolve **na mesma transação** as avaliações **não concluídas** reusando `evaluation_cancelar` (F5-06) e **preserva** as `CONCLUIDA`; em `PLANEJADO` exige que o operador tenha resolvido antes as avaliações (fail-closed); **`ciclo_reabrir`** (T6, `cycle.reopen`): unicamente `ENCERRADO` → `ATIVO`, com motivo, sem outro `ATIVO` na organização (I5/D14) e sem sobreposição (I6/D15), **sem rematerializar** nada (nenhuma escrita em snapshots/posições/membros/responsabilidades/participantes e nenhuma chamada a F3-08/F3-09) e **sem criar avaliações** — apenas `status`, `data_encerramento=null` e `version+1`, preservando o histórico na trilha; **`ciclo_corrigir_periodo`** (T7, `cycle.period.correct`): só `ATIVO`, com `data_inicio <= data_fim`, `justificativa` obrigatória, período diferente do atual e sem sobreposição, **sem tocar em estrutura/gestores/colegiado/participantes/responsabilidades**, com **impacto calculado server-side** (deltas de dias, avaliações por status, avaliações concluídas fora do novo período e participantes materializados — o cliente não declara impacto) gravado no evento `PERIODO_CORRIGIDO` junto de before/after. Todas `SECURITY INVOKER`, `search_path` fixo, `EXECUTE` só `service_role`, **zero `DELETE`** (D9), `version+1` uma única vez (auditado: `evaluation_cancelar` não incrementa a versão do ciclo), serializadas por `ciclo_lock_organizacao` e idempotentes por `(organization_id, operation_id)` com SHA-256 derivado server-side. **Sem** leitura soberana/policy (P5), Policy Engine (P6), Edge `ciclos` (P7), cutover (P8) e validação integrada (P9). |
| `20260919000000_f5_09_cycle_read_rls.sql` | F5-09 P5: LEITURA soberana de ciclos por RLS own-tenant — `alter table public.evaluation_cycles enable row level security` + policy **`evaluation_cycles_select_same_tenant`** (`for select to authenticated using (public.user_has_active_membership(organization_id))`) + `grant select` **mínimo** a `authenticated` (a policy é criada **antes** do grant); escrita do cliente permanece **fechada** (nenhum `INSERT`/`UPDATE`/`DELETE`, nenhum `REFERENCES`/`TRIGGER`), `anon` sem privilégio algum, `cycle_events` segue **deny-by-default** (nenhuma policy) e as 8 RPCs `ciclo_*` continuam `SECURITY INVOKER` com `EXECUTE` só `service_role`; o tenant é derivado do JWT (`auth.uid()`) e **revalidado** por `public.user_has_active_membership` (membership ativa + perfil ativo) — nunca aceito do cliente. Preflight e guarda final fail-closed (policy única e permissiva só para `authenticated`, grant mínimo, nenhuma policy de escrita, `service_role` preservado, catálogo de capabilities inalterado em 31). **Sem** Policy Engine `cycle.read`/`cycle.manage` (P6), Edge `ciclos` (P7), cutover do frontend (P8) e validação integrada (P9). |
| `20260920000000_f5_09_p6_cycle_cancel_description.sql` | F5-09 P6: atualização **aditiva** da descrição da capability **`cycle.cancel`** no catálogo F5-04 (`"Cancelar ciclo ATIVO"` → `"Cancelar ciclo PLANEJADO ou ATIVO (fluxo excepcional auditavel)"`), porque a P6 amplia o `domainState` de `cycle.cancel` para `{PLANEJADO, ATIVO}` (D8, ratificada na Q-F5-09-1). **Nenhuma** capability nova e **nenhuma** remoção física (F5-04 D14), **nenhuma** alteração de nome/status/`grantable_via_role`/`deprecated`, **nenhuma** alteração de bundle/role (`cycle.manage` no bundle `admin` é a D28, fase **P7**) e **nenhuma** alteração de schema, RLS, RPC, tabela ou coluna — preflight e guarda final fail-closed provam cada um desses pontos. |
| `20260921000000_f5_09_p7_catalog_admin_bundle.sql` | F5-09 P7: reconciliação **ADITIVA** do catálogo (**D28** / Q-F5-09-3 alternativa A) — `cycle.manage` entra no bundle administrativo de SISTEMA (`admin`, `c0000000-0000-4000-8000-0000000000f1`), tornando a gestão soberana de ciclo **executável em produção** (mitiga R9); `cycle.cancel`, `cycle.reopen` e `cycle.period.correct` permanecem **FORA** de qualquer role/bundle (concedíveis só por configuração explícita). **Nenhuma** capability nova (catálogo intacto), **nenhuma** remoção física (F5-04 D14), **nenhuma** alteração de atributo de capability e **nenhuma** alteração de schema/RLS/RPC/tabela/coluna; preflight e guarda final fail-closed provam o +1 exato no bundle, a permanência de `cycle.read` e a ausência das três excepcionais. |

## Plataforma e ferramentas

- Banco alvo: PostgreSQL 17 via Supabase (local primeiro, hospedado depois),
  conforme a estrutura local da F1-01.
- CLI Supabase fixada em **2.116.0**, sempre executada via `npx --yes`, sem
  instalação global e sem adicionar dependência ao package.json/lockfile.
- Migrations versionadas em `supabase/migrations/`, no formato de arquivo
  gerado pela CLI (`<timestamp>_<descricao>.sql`). Prefira criar arquivos com o
  comando oficial para manter nomes consistentes e o diff confiável.
- Aplicação local pelo fluxo oficial (`supabase start`/`db reset`/`db diff`);
  aplicação em ambiente remoto somente por fluxo versionado e aprovado. Não há
  vínculo com projeto hospedado nesta fase.

## Regras gerais de migration

- Uma migration por mudança coesa, aditiva e reversível por nova migration.
- Nunca editar uma migration já versionada e aplicada: correções entram como
  novas migrations.
- Migrations devem executar em ordem, tanto em banco vazio quanto sobre banco
  existente, e sobreviver ao fluxo de rebuild local sem depender de estado
  manual.
- Todo arquivo começa com um comentário curto indicando propósito e, quando
  aplicável, a Issue de origem. Sem valores reais, credenciais, tokens, chaves,
  e-mails ou nomes reais de pessoas/empresas em qualquer arquivo SQL.
- Apenas SQL declarativo e mudanças estruturais; sem lógica de negócio,
  procedures transacionais ou seeds nas migrations desta fase.

## Nomes de identificadores

- Identificadores em `lowercase` e `snake_case`, sem aspas desnecessárias e sem
  palavras reservadas do PostgreSQL.
- Tabelas no plural; colunas no singular.
- Nomes técnicos padronizados em inglês: `id`, `created_at`, `updated_at`,
  `version`, `organization_id`.
- Nomes de domínio derivam do termo já usado na aplicação (ex.: o tipo
  `Colaborador` em `src/types`), convertido para `snake_case`; quando o termo
  gerar ambiguidade de plural, o nome canônico da tabela é registrado em
  comentário na própria migration e na decisão técnica da Issue.
- Constraints e índices com prefixo e nome explícitos (exemplos ilustrativos,
  não criam nem antecipam tabelas):

| Tipo | Padrão | Exemplo |
| --- | --- | --- |
| primary key | `pk_<tabela>` | `pk_colaboradores` |
| unique | `uq_<tabela>_<colunas>` | `uq_colaboradores_email` |
| foreign key | `fk_<tabela>_<tabela_referenciada>` | `fk_avaliacoes_colaboradores` |
| check | `ck_<tabela>_<coluna>` | `ck_avaliacoes_nota` |
| index | `ix_<tabela>_<colunas>` | `ix_avaliacoes_ciclo_id` |

- Unicidade exige constraint `unique` própria (nunca índice avulso); índices
  comuns existem apenas para performance e são justificados em comentário.
- Limite de 63 bytes do PostgreSQL; sem abreviações, salvo decisão documentada.

## Identificador técnico (UUID)

- Toda tabela de domínio nova tem `id uuid primary key default gen_random_uuid()`.
- O `id` é identificador técnico imutável, nunca chave de negócio e nunca
  reutilizado após exclusão lógica. Chaves naturais de negócio, quando
  existirem, recebem `uq_` própria.
- `gen_random_uuid()` é nativo do PostgreSQL 17; nenhuma extensão extra é
  necessária apenas por causa do UUID.

## Timestamps e timezone

- Colunas de tempo sempre `timestamptz`; o PostgreSQL armazena UTC e a conversão
  para exibição fica na aplicação, nunca no banco.
- `created_at timestamptz not null default now()` em toda tabela de domínio.
- `updated_at timestamptz not null default now()` quando a linha admite
  atualização; manutenção automática por trigger técnico padrão da foundation
  (F1-03) quando existir, nunca escrita manualmente pelo cliente.
- Registros de histórico/auditoria preservam `created_at` original; a
  atualização nunca reescreve silenciosamente o passado. A modelagem concreta de
  histórico/auditoria pertence às fases de domínio correspondentes.

## Versionamento otimista

- `version integer not null default 0`, incrementado a cada atualização, quando
  a entidade admite edição concorrente; é controle técnico de concorrência, não
  dado de negócio nem informação exibida.
- Aplicável por tabela, decidido na criação; nem toda tabela precisa de
  `version`. Ausência ou presença fica documentada na migration.

## Escopo por organização

- Entidades que serão multi-organização incluem `organization_id` desde a
  criação, como `uuid` referenciando a entidade organizacional futura.
- Nesta fase e na F1-03 nenhuma tabela `organizations` é criada; a FK e os
  índices correspondentes entram na etapa que introduzir a entidade
  organizacional. Auth/RLS e o uso efetivo do `organization_id` pertencem a
  fases posteriores.
- Tabelas globais/técnicas não recebem `organization_id`; a decisão de escopo é
  registrada por tabela na migration.

## Foreign keys e exclusão

- Toda FK é nomeada (`fk_<tabela>_<tabela_referenciada>`) e acompanhada de
  índice na coluna que a compõe.
- Comportamento padrão de exclusão: `ON DELETE RESTRICT` (ou `NO ACTION`),
  preservando referências e históricos. `CASCADE` somente por decisão explícita
  de domínio documentada na Issue.
- Exclusão física de registros com valor histórico/auditoria é proibida por
  padrão; retenção e ciclo de vida são regras de domínio da aplicação, definidas
  nas fases correspondentes, e não devem ser duplicadas ou improvisadas em
  migrations.

## Enums e constraints

- Preferir `text` + `check` nomeado (`ck_...`) ou tabelas de referência
  pequenas quando o conjunto de valores puder evoluir ou precisar de metadados.
- Tipo `enum` nativo do PostgreSQL somente para conjuntos congelados e
  estáveis, pois `ALTER TYPE ... ADD VALUE` tem restrições transacionais e de
  lock que dificultam evolução segura.
- Valores em `lowercase` e `snake_case`; ampliar/alterar conjuntos sempre via
  nova migration.
- `check` para domínio de valor simples (ex.: faixa permitida). Validações de
  negócio, workflow e autorização permanecem na aplicação/policy central — o
  banco não duplica regra de negócio ou autorização.

## Extensões, schema e ambiente

- Somente extensões realmente necessárias e suportadas pelo Supabase, cada uma
  habilitada em migration dedicada e justificada.
- Schema padrão `public` (convenção Supabase); nenhum schema de domínio é criado
  nesta fase nem na F1-03.
- Configuração e migrations não contêm credenciais, secrets, URLs de projeto
  remoto ou dados reais; nada de `service_role` ou variáveis sensíveis.

## Limites desta fase

Este documento não autoriza, em nenhuma etapa desta Issue: tabelas de domínio;
migration SQL funcional; Auth/RLS/policies; seeds; procedures ou transações de
negócio; migração de localStorage; alteração do runtime da aplicação. A F1-03
criará a migration de foundation técnica seguindo estas convenções, sem criar
entidades funcionais.
