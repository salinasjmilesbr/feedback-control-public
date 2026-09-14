-- ============================================================================
-- F5-10 P7 (Issue #232): CONCORRENCIA REAL entre DUAS sessoes PostgreSQL
-- SESSAO A (primeiro processo psql; roda em BACKGROUND e VENCE as duas corridas)
-- ----------------------------------------------------------------------------
-- Papel desta sessao (processo psql 1 de 3):
--   (1) cria, pelo caminho LEGITIMO (`meta_criar`), as DUAS metas PROPRIAS da
--       corrida na organizacao Gama-P7 (a fixture 29 cria Gama-P7 com ciclo
--       ATIVO 2041/1, quota e snapshot congelado, mas SEM meta alguma);
--   (2) instala DOIS artefatos TEMPORARIOS em `public` — sequences NAO
--       transacionais usadas como MARCA de contencao e gatilhos que atrasam uma
--       escrita em ~8s (`pg_sleep`) cada:
--         * `_mut_p7_seq_edit` + gatilho BEFORE UPDATE em `evaluation_goals`
--           (escopo: a meta NEGOCIO_PROJETO da corrida) — corrida de EDICAO;
--         * `_mut_p7_seq_apr`  + gatilho BEFORE INSERT em
--           `evaluation_goal_approvals` (escopo: a meta INDIVIDUAL da corrida) —
--           corrida de APROVACAO.
--   (3) executa as DUAS operacoes vencedoras: `meta_editar` (expected_version 0)
--       e `meta_aprovar` (papel GERENTE, expected_version 0). Durante TODO o
--       UPDATE/INSERT a sessao A detem o advisory lock NORMATIVO da familia de
--       ciclos — `ciclo_lock_organizacao` = chave
--       `evaluation_cycles:<organization_id>` (adquirido dentro da RPC, ANTES da
--       resolucao da linha e da checagem de `expected_version`, D10/D12).
--
-- Ordem REAL de execucao (tres processos psql INDEPENDENTES; sem `dblink`, sem
-- `postgres_fdw`, sem extensao nova — a prova e entre backends REAIS):
--   1) `31-sessao-a-f5-10-p7-concorrencia.sql` (ESTE arquivo) -> BACKGROUND,
--      iniciado PRIMEIRO;
--   2) `32-sessao-b-f5-10-p7-concorrencia.sql`               -> FOREGROUND,
--      iniciado DEPOIS e BLOQUEADO pelo lock da sessao A nas duas fases;
--   3) `33-validar-f5-10-p7-concorrencia.sql`                -> single-session,
--      SOMENTE depois de A e B terminarem (estado consolidado + higiene).
--   Nao existe ordem interna pressuposta entre A e B: a UNICA coordenacao e o
--   laco de espera DETERMINISTICO da sessao B (existencia do alvo + MARCA nao
--   transacional publicada pelos gatilhos de A).
--
-- Evidencia de contencao esperada (server-side):
--   * EDICAO — A dorme ~8s DENTRO da transacao de `meta_editar` com o lock da
--     organizacao em maos; B tenta a MESMA edicao com o MESMO
--     `expected_version = 0` e fica BLOQUEADA no MESMO advisory lock ate A
--     commitar; ao adquirir o lock, B rele a versao (agora 1) e termina em
--     `F5_10_CONFLICT: versao divergente` — nenhum lost update;
--   * APROVACAO — A dorme ~8s DENTRO do INSERT da aprovacao (mesmo lock); B
--     tenta aprovar o MESMO papel com outro `operation_id`. A aprovacao NAO
--     altera `version` da meta (D2/D3), portanto o `expected_version` de B
--     continua valido: o que reprova B e a regra "uma unica aprovacao VIGENTE por
--     (meta, papel)", avaliada SO depois do lock — B termina em
--     `F5_10_CONFLICT: ja existe aprovacao vigente do papel GERENTE para a meta`.
--     Sem a serializacao pelo lock, a segunda sessao poderia passar pela mesma
--     checagem `exists` antes do commit da primeira (READ COMMITTED).
--   * PAPEIS DISTINTOS (contraparte positiva, na sessao B): com o lock ja livre,
--     o COORDENADOR congelado aprova a MESMA meta — os dois fatos coexistem, um
--     vigente por papel, sem perda do fato de A.
--
-- `operation_id` desta sessao (UUIDs sinteticos fixos, NUNCA reutilizados entre
-- as duas sessoes):
--   meta_criar  G_edit -> e8a10000-0000-0000-0000-0000000000a1
--   meta_criar  G_apr  -> e8a10000-0000-0000-0000-0000000000a2
--   meta_editar G_edit -> e8a10000-0000-0000-0000-0000000000a3  (vencedora)
--   meta_aprovar G_apr -> e8a10000-0000-0000-0000-0000000000a4  (vencedora)
--   (a sessao B usa e8b10000-…-b1 / -b2 / -b3 — todos distintos)
--
-- Alvo fixo do contrato P7 (Gama-P7 = ano 2041, EXCLUSIVO desta corrida):
--   organizacao : e8a00000-0000-0000-0000-0000000000c1
--   ciclo ATIVO : e8d10000-0000-0000-0000-0000000000c1 (2041/1)
--   dono        : e8c00000-0000-0000-0000-0000000000a1 (colaborador cg1)
--   gerente     : e8c00000-0000-0000-0000-0000000000a2 (congelado GESTAO_CADEIA)
--   coordenador : e8c00000-0000-0000-0000-0000000000a3 (congelado GESTAO_DIRETA)
--
-- LIMITACOES CONHECIDAS (declaradas, nao presumidas):
--   - a janela de contencao e o `pg_sleep(8)` dentro da escrita. Se o runner
--     demorar mais que ~8s para subir o segundo psql, aumente o `pg_sleep` AQUI e
--     o teto do laco de espera de B (120 x 0.25s) de forma coerente nos arquivos;
--   - a marca do gatilho e uma SEQUENCE (nao transacional) DE PROPOSITO: e ela que
--     permite a B provar que A JA esta DENTRO da escrita (com o lock em maos) no
--     instante da tentativa, eliminando a corrida de "quem pega o lock primeiro";
--   - a trilha de metas e append-only e as FKs sao RESTRICT: a prova NAO tem reset
--     parcial. Para reexecutar: `supabase db reset --local` + fixtures (29/30) +
--     31/32/33;
--   - os artefatos temporarios NAO sao removidos por esta sessao (evita a corrida
--     de B lendo uma sequence ja removida): a higiene e do consolidador 33.
--
-- Como executar (Supabase local; NUNCA remoto). A em BACKGROUND e B em FOREGROUND:
--   A) Get-Content supabase/validacao/31-sessao-a-f5-10-p7-concorrencia.sql -Raw -Encoding UTF8 |
--        docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   B) idem para 32-...sql (foreground) e, ao final dos dois, 33-...sql.
-- ============================================================================

\set ON_ERROR_STOP on

-- A prova tem uma janela LEGITIMA de ~8s dentro de UMA instrucao (o pg_sleep do
-- artefato temporario): o timeout e desligado APENAS nestas sessoes de validacao
-- (nenhum objeto do banco e alterado, nenhum controle do produto e relaxado).
set statement_timeout = 0;
set lock_timeout = 0;

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture 29 presente, alvos livres e RPCs na assinatura exata
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama   uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg     uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_dono   uuid := 'e8c00000-0000-0000-0000-0000000000a1';
  v_ger    uuid := 'e8c00000-0000-0000-0000-0000000000a2';
  v_memb   uuid;
  v_n      int;
  v_args   text;
begin
  if not exists (select 1 from public.organizations o where o.id = v_gama) then
    raise exception '[FAIL] pre-condicao A: organizacao Gama-P7 (%) ausente — execute 29-cenario-f5-10-p7.sql', v_gama;
  end if;
  if not exists (
    select 1 from public.evaluation_cycles c
     where c.id = v_cg and c.organization_id = v_gama and c.ano = 2041
       and c.status = 'ATIVO'
  ) then
    raise exception '[FAIL] pre-condicao A: ciclo ATIVO 2041/1 de Gama-P7 ausente';
  end if;
  -- Gama-P7 e a organizacao EXCLUSIVA da corrida: nasce SEM meta alguma.
  select count(*) into v_n from public.evaluation_goals where organization_id = v_gama;
  if v_n <> 0 then
    raise exception '[FAIL] pre-condicao A: Gama-P7 ja possui % meta(s) — a trilha e append-only: reexecute apos `supabase db reset --local`', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events where organization_id = v_gama;
  if v_n <> 0 then
    raise exception '[FAIL] pre-condicao A: Gama-P7 ja possui % evento(s) de meta — reexecute apos `supabase db reset --local`', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals where organization_id = v_gama;
  if v_n <> 0 then
    raise exception '[FAIL] pre-condicao A: Gama-P7 ja possui % aprovacao(oes) — reexecute apos `supabase db reset --local`', v_n;
  end if;

  if not exists (select 1 from public.user_profiles p where p.id = v_dono and p.status = 'active') then
    raise exception '[FAIL] pre-condicao A: perfil ATIVO do dono-gama (%) ausente', v_dono;
  end if;
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_dono and m.organization_id = v_gama and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] pre-condicao A: membership ATIVA do dono-gama em Gama-P7 ausente';
  end if;
  if not public.f5_10_ator_valido_meta(v_dono, v_gama, 'goal.write') then
    raise exception '[FAIL] pre-condicao A: dono-gama sem goal.write efetivo em Gama-P7';
  end if;
  if not public.f5_10_ator_valido_meta(v_ger, v_gama, 'goal.approve') then
    raise exception '[FAIL] pre-condicao A: gerente-gama sem goal.approve efetivo em Gama-P7';
  end if;

  -- Assinaturas EXATAS do contrato para as RPCs usadas pela corrida.
  select pg_get_function_arguments(p.oid) into v_args from pg_proc p
   where p.oid = to_regprocedure('public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)');
  if v_args is distinct from
     'p_organization_id uuid, p_cycle_id uuid, p_collaborator_id uuid, p_tipo text, p_descricao text, p_kpi text, p_valor_alvo text, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] pre-condicao A: assinatura de meta_criar fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;
  select pg_get_function_arguments(p.oid) into v_args from pg_proc p
   where p.oid = to_regprocedure('public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_goal_id uuid, p_organization_id uuid, p_descricao text, p_kpi text, p_valor_alvo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] pre-condicao A: assinatura de meta_editar fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;
  select pg_get_function_arguments(p.oid) into v_args from pg_proc p
   where p.oid = to_regprocedure('public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_goal_id uuid, p_organization_id uuid, p_papel text, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] pre-condicao A: assinatura de meta_aprovar fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;

  raise notice '[PASS] pre-condicoes da sessao A: Gama-P7 com ciclo ATIVO 2041/1, SEM meta/evento/aprovacao (organizacao exclusiva da corrida), dono-gama % com goal.write, gerente-gama com goal.approve e as 3 RPCs na assinatura exata do contrato',
    v_dono;
end $$;

-- ----------------------------------------------------------------------------
-- 1) Artefatos TEMPORARIOS da prova (autocommit: visiveis a sessao B ANTES do
--    commit da sessao A — e isso que torna a marca deterministica)
-- ----------------------------------------------------------------------------
-- Higiene fail-safe: remove artefato de uma execucao ANTERIOR interrompida
-- (idempotente; nao altera nada quando nao existe).
drop trigger if exists _mut_p7_contencao_edicao on public.evaluation_goals;
drop function if exists public._mut_p7_contencao_edicao_fn();
drop sequence if exists public._mut_p7_seq_edit;
drop trigger if exists _mut_p7_contencao_aprovacao on public.evaluation_goal_approvals;
drop function if exists public._mut_p7_contencao_aprovacao_fn();
drop sequence if exists public._mut_p7_seq_apr;

create sequence public._mut_p7_seq_edit;
create sequence public._mut_p7_seq_apr;

create or replace function public._mut_p7_contencao_edicao_fn()
returns trigger
language plpgsql
as $mut$
declare
  v_gama  uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg    uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_alvo  uuid;
  v_marca bigint;
begin
  select g.id into v_alvo
    from public.evaluation_goals g
   where g.organization_id = v_gama and g.cycle_id = v_cg
     and g.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a1'
     and g.tipo = 'NEGOCIO_PROJETO';
  if v_alvo is not null and new.id = v_alvo then
    v_marca := nextval('public._mut_p7_seq_edit');
    raise notice 'sessao A: DENTRO do UPDATE de evaluation_goals (Gama-P7) com o lock evaluation_cycles:% em maos — dormindo 8s antes do commit (marca=%)',
      v_gama, v_marca;
    perform pg_sleep(8);
  end if;
  return new;
end;
$mut$;

create trigger _mut_p7_contencao_edicao
  before update on public.evaluation_goals
  for each row execute function public._mut_p7_contencao_edicao_fn();

create or replace function public._mut_p7_contencao_aprovacao_fn()
returns trigger
language plpgsql
as $mut$
declare
  v_gama  uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg    uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_alvo  uuid;
  v_marca bigint;
begin
  select g.id into v_alvo
    from public.evaluation_goals g
   where g.organization_id = v_gama and g.cycle_id = v_cg
     and g.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a1'
     and g.tipo = 'INDIVIDUAL';
  -- ESCopo ESTRITO: apenas a intencao CONTRATADA da corrida (papel GERENTE). A
  -- contraparte POSITIVA da sessao B (COORDENADOR, fase 3) insere na mesma meta
  -- DEPOIS da contencao e NAO pode consumir a marca — assim "marca == 1" prova que
  -- houve UMA unica escrita na janela de contencao, e nao que a fase 3 rodou.
  if v_alvo is not null and new.goal_id = v_alvo and new.papel = 'GERENTE' then
    v_marca := nextval('public._mut_p7_seq_apr');
    raise notice 'sessao A: DENTRO do INSERT de evaluation_goal_approvals (Gama-P7, papel GERENTE) com o lock evaluation_cycles:% em maos — dormindo 8s antes do commit (marca=%)',
      v_gama, v_marca;
    perform pg_sleep(8);
  end if;
  return new;
end;
$mut$;

create trigger _mut_p7_contencao_aprovacao
  before insert on public.evaluation_goal_approvals
  for each row execute function public._mut_p7_contencao_aprovacao_fn();

-- ----------------------------------------------------------------------------
-- 2) Passo 1: criacao das DUAS metas da corrida pelo caminho LEGITIMO
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama  uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg    uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_dono  uuid := 'e8b00000-0000-0000-0000-0000000000a1';
  v_ator  uuid := 'e8c00000-0000-0000-0000-0000000000a1';
  v_res   jsonb;
  v_id    uuid;
  v_n     int;
begin
  v_res := public.meta_criar(v_gama, v_cg, v_dono, 'NEGOCIO_PROJETO',
    'Descricao da meta da corrida de EDICAO (P7)',
    'KPI da corrida de edicao (P7)', '100 unidades (P7)',
    v_ator, 'e8a10000-0000-0000-0000-0000000000a1');
  v_id := (v_res->>'goal_id')::uuid;
  if v_id is null or (v_res->>'version')::int <> 0 then
    raise exception '[FAIL] A/criacao: meta_criar (EDICAO) deveria devolver goal_id/version 0 (%)', v_res;
  end if;

  v_res := public.meta_criar(v_gama, v_cg, v_dono, 'INDIVIDUAL',
    'Descricao da meta da corrida de APROVACAO (P7)',
    'KPI da corrida de aprovacao (P7)', '50 unidades (P7)',
    v_ator, 'e8a10000-0000-0000-0000-0000000000a2');
  if (v_res->>'goal_id')::uuid is null or (v_res->>'version')::int <> 0 then
    raise exception '[FAIL] A/criacao: meta_criar (APROVACAO) deveria devolver goal_id/version 0 (%)', v_res;
  end if;

  select count(*) into v_n from public.evaluation_goals
   where organization_id = v_gama and cycle_id = v_cg and version = 0 and excluida = false;
  if v_n <> 2 then
    raise exception '[FAIL] A/criacao: esperadas 2 metas da corrida em Gama-P7 (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events
   where organization_id = v_gama and event_type = 'CRIADA';
  if v_n <> 2 then
    raise exception '[FAIL] A/criacao: esperados 2 eventos CRIADA em Gama-P7 (%)', v_n;
  end if;

  raise notice '[PASS] sessao A: as 2 metas da corrida foram criadas pelo caminho LEGITIMO `meta_criar` (NEGOCIO_PROJETO para a EDICAO e INDIVIDUAL para a APROVACAO), ambas version 0 em Gama-P7';
end $$;

-- ----------------------------------------------------------------------------
-- 3) FASE 1 — EDICAO que VENCE a corrida (expected_version = 0)
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama  uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg    uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_ator  uuid := 'e8c00000-0000-0000-0000-0000000000a1';
  v_alvo  uuid;
  v_res   jsonb;
  v_ini   timestamptz;
  v_fim   timestamptz;
  v_seg   numeric;
  v_marca bigint;
  v_called boolean;
  v_before jsonb;
  v_after  jsonb;
  v_n      int;
begin
  select g.id into v_alvo
    from public.evaluation_goals g
   where g.organization_id = v_gama and g.cycle_id = v_cg
     and g.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a1'
     and g.tipo = 'NEGOCIO_PROJETO';
  if v_alvo is null then
    raise exception '[FAIL] A/edicao: meta da corrida de EDICAO ausente';
  end if;

  raise notice 'sessao A: chamando meta_editar com expected_version = 0 (mesmo alvo e mesma versao que a sessao B tentara); o lock da organizacao fica em maos ate o commit';
  v_ini := clock_timestamp();
  v_res := public.meta_editar(v_alvo, v_gama,
    'Descricao VENCEDORA da corrida de edicao (P7)',
    'KPI VENCEDOR da corrida de edicao (P7)',
    '111 unidades (P7)', 0, v_ator,
    'e8a10000-0000-0000-0000-0000000000a3');
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  -- Prova de que o gatilho temporario REALMENTE disparou nesta transacao: a marca
  -- e uma sequence NAO transacional, portanto visivel a qualquer sessao.
  select s.last_value, s.is_called into v_marca, v_called from public._mut_p7_seq_edit s;
  if v_called is not true or v_marca < 1 then
    raise exception '[FAIL] A/edicao: o gatilho temporario nao registrou a marca de contencao (is_called=%, last_value=%)',
      v_called, v_marca;
  end if;
  if v_seg < 4.0 then
    raise exception '[FAIL] A/edicao: a escrita durou % segundos (esperado >= 4s: o pg_sleep(8) dentro do UPDATE e a janela de contencao que a sessao B deve sentir)',
      round(v_seg, 3);
  end if;
  if (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] A/edicao: retorno deveria ser version 1 (%)', v_res;
  end if;

  select e.before_value, e.after_value into v_before, v_after
    from public.evaluation_goal_events e
   where e.organization_id = v_gama and e.goal_id = v_alvo
     and e.operation_id = 'e8a10000-0000-0000-0000-0000000000a3';
  if v_before is null or v_after is null then
    raise exception '[FAIL] A/edicao: evento EDITADO da edicao vencedora ausente';
  end if;
  if (v_before->>'version')::int <> 0 or (v_after->>'version')::int <> 1 then
    raise exception '[FAIL] A/edicao: before/after deveriam registrar version 0 -> 1 (%) / (%)', v_before, v_after;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama and e.goal_id = v_alvo and e.event_type = 'EDITADA';
  if v_n <> 1 then
    raise exception '[FAIL] A/edicao: esperado exatamente 1 evento EDITADA da intencao vencedora (%)', v_n;
  end if;

  raise notice '[PASS] sessao A: FASE 1 (EDICAO) aplicada com o lock evaluation_cycles:% em maos por ~% segundos (janela de contencao da sessao B) — version 0 -> 1',
    v_gama, round(v_seg, 3);
end $$;

-- ----------------------------------------------------------------------------
-- 4) FASE 2 — APROVACAO (papel GERENTE) que VENCE a corrida
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama  uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg    uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_ger   uuid := 'e8c00000-0000-0000-0000-0000000000a2';
  v_alvo  uuid;
  v_res   jsonb;
  v_ini   timestamptz;
  v_fim   timestamptz;
  v_seg   numeric;
  v_marca bigint;
  v_called boolean;
  v_n     int;
begin
  select g.id into v_alvo
    from public.evaluation_goals g
   where g.organization_id = v_gama and g.cycle_id = v_cg
     and g.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a1'
     and g.tipo = 'INDIVIDUAL';
  if v_alvo is null then
    raise exception '[FAIL] A/aprovacao: meta da corrida de APROVACAO ausente';
  end if;

  raise notice 'sessao A: chamando meta_aprovar (GERENTE) com expected_version = 0 — a aprovacao NAO altera `version` da meta, portanto a sessao B tentara o MESMO papel com a MESMA versao';
  v_ini := clock_timestamp();
  v_res := public.meta_aprovar(v_alvo, v_gama, 'GERENTE',
    'Aprovacao VENCEDORA da corrida (P7)', 0, v_ger,
    'e8a10000-0000-0000-0000-0000000000a4');
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  select s.last_value, s.is_called into v_marca, v_called from public._mut_p7_seq_apr s;
  if v_called is not true or v_marca < 1 then
    raise exception '[FAIL] A/aprovacao: o gatilho temporario nao registrou a marca de contencao (is_called=%, last_value=%)',
      v_called, v_marca;
  end if;
  if v_seg < 4.0 then
    raise exception '[FAIL] A/aprovacao: a escrita durou % segundos (esperado >= 4s: o pg_sleep(8) dentro do INSERT e a janela de contencao)',
      round(v_seg, 3);
  end if;
  if (v_res->>'aprovado')::boolean is not true then
    raise exception '[FAIL] A/aprovacao: o retorno deveria marcar aprovado = true (%)', v_res;
  end if;
  -- `version` no retorno e a version da META (nao do fato): a aprovacao NAO muda
  -- o estado funcional da meta (D2/D3).
  if (v_res->>'version')::int <> 0 then
    raise exception '[FAIL] A/aprovacao: a aprovacao NAO pode alterar a version da meta (retorno %)', v_res;
  end if;

  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_gama and a.goal_id = v_alvo
     and a.papel = 'GERENTE' and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] A/aprovacao: esperada exatamente 1 aprovacao VIGENTE de GERENTE (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama and e.goal_id = v_alvo
     and e.event_type = 'APROVACAO_GERENTE'
     and e.operation_id = 'e8a10000-0000-0000-0000-0000000000a4';
  if v_n <> 1 then
    raise exception '[FAIL] A/aprovacao: esperado 1 evento APROVACAO_GERENTE da intencao vencedora (%)', v_n;
  end if;

  raise notice '[PASS] sessao A: FASE 2 (APROVACAO GERENTE) aplicada com o lock evaluation_cycles:% em maos por ~% segundos — fato vigente e version da meta INTACTA (0)',
    v_gama, round(v_seg, 3);
end $$;

-- ----------------------------------------------------------------------------
-- 5) Estado consolidado POS-COMMIT da sessao A (o lock ja foi liberado)
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama  uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_n     int;
  v_desc  text;
begin
  select g.descricao, g.version into v_desc, v_n
    from public.evaluation_goals g
   where g.organization_id = v_gama and g.tipo = 'NEGOCIO_PROJETO'
     and g.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a1';
  if v_desc <> 'Descricao VENCEDORA da corrida de edicao (P7)' or v_n <> 1 then
    raise exception '[FAIL] A/estado final: a meta da EDICAO deveria manter a intencao de A (descricao=%, version=%)', v_desc, v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events where organization_id = v_gama;
  if v_n <> 4 then
    raise exception '[FAIL] A/estado final: esperados 4 eventos em Gama-P7 apos as 2 fases (2 CRIADA + 1 EDITADA + 1 APROVACAO_GERENTE), encontrados % — verifique se outro arquivo passou a escrever em Gama-P7', v_n;
  end if;
  if exists (select 1 from public.evaluation_goal_events e
              where e.organization_id = v_gama
                and e.operation_id in ('e8b10000-0000-0000-0000-0000000000b1',
                                       'e8b10000-0000-0000-0000-0000000000b2')) then
    raise exception '[FAIL] A/estado final: intencao da sessao B nao pode existir na trilha antes de B tentar';
  end if;

  raise notice '[PASS] sessao A: estado consolidado — EDICAO em version 1 com a descricao de A, APROVACAO de GERENTE vigente, 4 eventos em Gama-P7 e nenhuma intencao de B; os artefatos temporarios seguem instalados para a sessao B e serao removidos pelo consolidador 33';
  raise notice 'sessao A: a contencao server-side sera provada pelo tempo de espera medido pela sessao B (arquivo 32) e o estado final sera conferido pelo validador 33';
end $$;
