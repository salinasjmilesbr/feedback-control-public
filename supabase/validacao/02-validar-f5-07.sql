-- ============================================================================
-- F5-07: validação automatizada — colaboradores e histórico organizacional
-- soberanos (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de 01-cenario-f5-07.sql, como superuser local
-- (`psql -U postgres`), com ON_ERROR_STOP ativo.
--
-- Cobre a matriz do desenho técnico (docs/F5-07-desenho-tecnico.md §16.2):
--   T-01 (CRUD autorizado), T-02 (CRUD negado / capability), T-03 (cross-tenant),
--   T-07 (usuário sem colaborador), T-08 (troca de gestor), T-09 (troca de
--   unidade/posição), T-10 (status active→leave→active), T-11 (licença),
--   T-12 (inativação com pendência), T-13 (sucessão), T-14 (histórico
--   temporal), T-19 (RLS own-tenant), T-20 (evento obrigatório na mesma
--   transação), T-22 (job_roles.code não altera autoridade), T-23 (append-only).
--   T-04/T-05/T-06/T-15/T-16/T-17/T-18/T-24 em 03-validar-f5-07-cutover.sql.
--
-- Fronteira validada (espinha F5-07 §1): as RPC são SECURITY INVOKER com
-- EXECUTE somente service_role e revalidam o ator via `colaborador_ator_valido`
-- (perfil ativo + membership ativa no tenant). O gate de CAPABILITY do plano
-- funcional (`collaborator.read/create/edit`) e o plano ADMINISTRATIVO
-- (`org.structure.manage`/`org.catalog.manage`, D19) vivem na Edge Function; no
-- banco a validação correspondente é o predicado soberano
-- `resolver_capabilities_escopos_efetivas` + `usuario_eh_administrador`.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Schema: collaborator_events (tabela nova, append-only)
-- ============================================================================
do $$
begin
  if not exists (
    select 1 from pg_tables t
     where t.schemaname = 'public' and t.tablename = 'collaborator_events'
  ) then
    raise exception '[FAIL] tabela collaborator_events ausente';
  end if;
  if not exists (
    select 1 from pg_class c
     where c.oid = 'public.collaborator_events'::regclass and c.relrowsecurity = true
  ) then
    raise exception '[FAIL] RLS nao habilitado em collaborator_events';
  end if;
  raise notice '[PASS] collaborator_events presente com RLS habilitado';
end $$;

do $$
declare
  v_esperado record;
  v_tipo text;
  v_null text;
begin
  for v_esperado in
    select * from (values
      ('id','uuid','NO'),
      ('organization_id','uuid','NO'),
      ('collaborator_id','uuid','YES'),
      ('position_id','uuid','YES'),
      ('event_type','text','NO'),
      ('effective_date','timestamptz','NO'),
      ('cycle_scope','text','NO'),
      ('reference_cycle_id','uuid','YES'),
      ('reason','text','NO'),
      ('before_value','jsonb','YES'),
      ('after_value','jsonb','YES'),
      ('payload_hash','text','YES'),
      ('result_entity_id','uuid','YES'),
      ('actor_user_profile_id','uuid','NO'),
      ('actor_membership_id','uuid','NO'),
      ('operation_id','uuid','NO'),
      ('created_at','timestamptz','NO')
    ) as t(col, tipo, nullable)
  loop
    select (case when c.data_type = 'timestamp with time zone' then 'timestamptz' else c.data_type end),
           c.is_nullable
      into v_tipo, v_null
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.table_name = 'collaborator_events'
       and c.column_name = v_esperado.col;

    if v_tipo is null then
      raise exception '[FAIL] collaborator_events.% ausente (coluna do contrato)', v_esperado.col;
    end if;
    if v_tipo <> v_esperado.tipo then
      raise exception '[FAIL] collaborator_events.% tem tipo % (esperado %)', v_esperado.col, v_tipo, v_esperado.tipo;
    end if;
    if v_null <> v_esperado.nullable then
      raise exception '[FAIL] collaborator_events.% tem nullability % (esperado %)', v_esperado.col, v_null, v_esperado.nullable;
    end if;
  end loop;
  raise notice '[PASS] collaborator_events: 17 colunas do contrato com tipo e nullability corretos';
end $$;

do $$
declare
  v_def text;
  v_tipo text;
  v_tipos text[] := array[
    'admissao','dados_pessoais_alterados','identificador_definido','identificador_encerrado',
    'status_alterado','ocupacao_iniciada','ocupacao_encerrada','reporting_line_iniciada',
    'reporting_line_encerrada','responsabilidade_iniciada','responsabilidade_encerrada',
    'sucessao_registrada'];
  v_escopos text[] := array['ciclo_atual_e_posteriores','somente_ciclos_posteriores'];
begin
  select string_agg(replace(lower(pg_get_constraintdef(c.oid)), ' ', ' '), ' | ')
    into v_def
    from pg_constraint c
   where c.conrelid = 'public.collaborator_events'::regclass
     and c.contype = 'c';

  if v_def is null then
    raise exception '[FAIL] collaborator_events sem CHECK constraints';
  end if;

  foreach v_tipo in array v_tipos loop
    if position(v_tipo in v_def) = 0 then
      raise exception '[FAIL] CHECK de event_type sem o valor do contrato: %', v_tipo;
    end if;
  end loop;

  foreach v_tipo in array v_escopos loop
    if position(v_tipo in v_def) = 0 then
      raise exception '[FAIL] CHECK de cycle_scope sem o valor do contrato: %', v_tipo;
    end if;
  end loop;

  if position('btrim(reason)' in v_def) = 0 then
    raise exception '[FAIL] CHECK de reason (nao vazio e sem espacos nas bordas) ausente';
  end if;

  if position('num_nonnulls(collaborator_id,position_id)' in replace(v_def, ' ', '')) = 0 then
    raise exception '[FAIL] CHECK num_nonnulls(collaborator_id, position_id) >= 1 ausente';
  end if;

  raise notice '[PASS] collaborator_events: CHECKs de event_type (12), cycle_scope (2), reason e num_nonnulls(collaborator_id, position_id)';
end $$;

do $$
declare
  v_fk record;
  v_n int;
begin
  -- 4 FKs do contrato: colaborador, ciclo de referencia, ator e membership do ator
  select count(*) into v_n
    from pg_constraint c
   where c.conrelid = 'public.collaborator_events'::regclass and c.contype = 'f';
  if v_n <> 4 then
    raise exception '[FAIL] collaborator_events deveria ter 4 FKs, encontradas %', v_n;
  end if;

  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.collaborator_events'::regclass and c.contype = 'f'
                    and c.confrelid = 'public.collaborators'::regclass and array_length(c.conkey, 1) = 2) then
    raise exception '[FAIL] FK composta (collaborator_id, organization_id) -> collaborators ausente';
  end if;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.collaborator_events'::regclass and c.contype = 'f'
                    and c.confrelid = 'public.evaluation_cycles'::regclass and array_length(c.conkey, 1) = 2) then
    raise exception '[FAIL] FK composta (reference_cycle_id, organization_id) -> evaluation_cycles ausente';
  end if;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.collaborator_events'::regclass and c.contype = 'f'
                    and c.confrelid = 'public.user_profiles'::regclass and array_length(c.conkey, 1) = 1) then
    raise exception '[FAIL] FK actor_user_profile_id -> user_profiles ausente';
  end if;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.collaborator_events'::regclass and c.contype = 'f'
                    and c.confrelid = 'public.user_organization_memberships'::regclass and array_length(c.conkey, 1) = 2) then
    raise exception '[FAIL] FK composta (actor_membership_id, organization_id) -> user_organization_memberships ausente';
  end if;

  -- Toda FK de 2 colunas precisa amarrar o tenant (organization_id) na chave.
  for v_fk in
    select c.oid, c.conname from pg_constraint c
     where c.conrelid = 'public.collaborator_events'::regclass and c.contype = 'f'
       and array_length(c.conkey, 1) > 1
  loop
    select count(*) into v_n
      from unnest((select conkey from pg_constraint where oid = v_fk.oid)) k
      join pg_attribute a on a.attrelid = 'public.collaborator_events'::regclass and a.attnum = k
     where a.attname = 'organization_id';
    if v_n <> 1 then
      raise exception '[FAIL] FK % nao inclui organization_id (tenant integrity)', v_fk.conname;
    end if;
  end loop;

  -- Unique (organization_id, operation_id) — idempotência por operação (D13).
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.collaborator_events'::regclass
       and (c.contype = 'u' or c.contype = 'p')
       and array_length(c.conkey, 1) = 2
       and (select count(*) from unnest(c.conkey) k
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k
             where a.attname in ('organization_id', 'operation_id')) = 2
  ) then
    raise exception '[FAIL] unique (organization_id, operation_id) ausente em collaborator_events';
  end if;

  raise notice '[PASS] collaborator_events: 4 FKs (tenant em todas as compostas) + unique (organization_id, operation_id)';
end $$;

do $$
begin
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'collaborator_events'
                    and indexdef like '%collaborator_id%') then
    raise exception '[FAIL] indice por collaborator_id ausente em collaborator_events';
  end if;
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'collaborator_events'
                    and indexdef like '%organization_id%') then
    raise exception '[FAIL] indice por organization_id ausente em collaborator_events';
  end if;
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.collaborator_events'::regclass and not t.tgisinternal
  ) then
    raise exception '[FAIL] trigger append-only ausente em collaborator_events (UPDATE proibido)';
  end if;
  raise notice '[PASS] collaborator_events: indices por collaborator_id/organization_id + trigger append-only';
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'collaborator_events'
       and p.cmd = 'SELECT' and 'authenticated'::name = any(p.roles)
  ) then
    raise exception '[FAIL] collaborator_events sem policy SELECT para authenticated (own-tenant)';
  end if;
  if exists (
    select 1 from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'collaborator_events'
       and p.cmd <> 'SELECT'
  ) then
    raise exception '[FAIL] collaborator_events com policy de ESCRITA (mutacao so por RPC)';
  end if;
  if exists (
    select 1 from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'collaborator_events'
       and (p.qual = 'true' or p.with_check = 'true')
  ) then
    raise exception '[FAIL] policy trivially-permissive em collaborator_events';
  end if;
  raise notice '[PASS] collaborator_events: somente policy SELECT own-tenant, nenhuma policy de escrita';
end $$;

do $$
begin
  if not has_table_privilege('service_role', 'public.collaborator_events', 'SELECT') then
    raise exception '[FAIL] service_role sem SELECT em collaborator_events (leitura por RPC)';
  end if;
  if not has_table_privilege('service_role', 'public.collaborator_events', 'INSERT') then
    raise exception '[FAIL] service_role sem INSERT em collaborator_events';
  end if;
  if has_table_privilege('service_role', 'public.collaborator_events', 'UPDATE') then
    raise exception '[FAIL] service_role com UPDATE em collaborator_events (append-only)';
  end if;
  if has_table_privilege('service_role', 'public.collaborator_events', 'DELETE') then
    raise exception '[FAIL] service_role com DELETE em collaborator_events (append-only)';
  end if;
  if has_table_privilege('anon', 'public.collaborator_events', 'SELECT') then
    raise exception '[FAIL] anon com SELECT em collaborator_events';
  end if;
  if has_table_privilege('authenticated', 'public.collaborator_events', 'INSERT')
     or has_table_privilege('authenticated', 'public.collaborator_events', 'UPDATE')
     or has_table_privilege('authenticated', 'public.collaborator_events', 'DELETE')
     or has_table_privilege('authenticated', 'public.collaborator_events', 'TRUNCATE') then
    raise exception '[FAIL] authenticated com DML em collaborator_events (mutacao so por RPC)';
  end if;
  -- SELECT de authenticated (se houver) exige a policy own-tenant: nunca leitura
  -- direta sem barreira de tenant. As duas leituras do contrato (spine §1.2 e
  -- desenho §10.3) sao aceitas por esta verificacao.
  if has_table_privilege('authenticated', 'public.collaborator_events', 'SELECT')
     and not exists (
       select 1 from pg_policies p
        where p.schemaname = 'public' and p.tablename = 'collaborator_events'
          and p.cmd = 'SELECT' and 'authenticated'::name = any(p.roles)
     ) then
    raise exception '[FAIL] authenticated com SELECT em collaborator_events SEM policy own-tenant';
  end if;
  raise notice '[PASS] grants de collaborator_events: service_role somente SELECT/INSERT; authenticated sem DML';
end $$;

-- ============================================================================
-- 2) Schema: extensoes aditivas (collaborators.full_name/email, job_roles.code)
-- ============================================================================
do $$
declare
  v_tipo text;
  v_null text;
  v_def text;
begin
  select c.data_type, c.is_nullable into v_tipo, v_null
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'collaborators' and c.column_name = 'full_name';
  if v_tipo is null or v_tipo <> 'text' then
    raise exception '[FAIL] collaborators.full_name ausente ou nao textual (%)', coalesce(v_tipo, '-');
  end if;
  if v_null <> 'NO' then
    raise exception '[FAIL] collaborators.full_name deveria ser NOT NULL';
  end if;

  select c.data_type, c.is_nullable into v_tipo, v_null
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'collaborators' and c.column_name = 'email';
  if v_tipo is null or v_tipo <> 'text' then
    raise exception '[FAIL] collaborators.email ausente ou nao textual (%)', coalesce(v_tipo, '-');
  end if;
  if v_null <> 'NO' then
    raise exception '[FAIL] collaborators.email deveria ser NOT NULL';
  end if;

  select c.data_type, c.is_nullable into v_tipo, v_null
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'collaborators' and c.column_name = 'admission_date';
  if v_tipo is null or v_tipo <> 'date' then
    raise exception '[FAIL] collaborators.admission_date ausente ou nao date (%)', coalesce(v_tipo, '-');
  end if;

  select string_agg(replace(lower(pg_get_constraintdef(c.oid)), ' ', ''), ' | ') into v_def
    from pg_constraint c
   where c.conrelid = 'public.collaborators'::regclass and c.contype = 'c';
  if v_def is null or position('btrim(full_name)' in v_def) = 0 then
    raise exception '[FAIL] CHECK de full_name (trim, nao vazio) ausente em collaborators';
  end if;
  if position('btrim(email)' in v_def) = 0 then
    raise exception '[FAIL] CHECK de email (trim, nao vazio) ausente em collaborators';
  end if;
  if position('@' in v_def) = 0 then
    raise exception '[FAIL] CHECK de formato minimo de email (position de @) ausente em collaborators';
  end if;

  select replace(lower(pg_get_indexdef(i.indexrelid)), ' ', '') into v_def
    from pg_index i
    join pg_class c on c.oid = i.indexrelid
   where c.relname = 'uq_collaborators_org_email';
  if v_def is null then
    raise exception '[FAIL] indice unico uq_collaborators_org_email ausente';
  end if;
  if position('createuniqueindex' in v_def) = 0
     or position('organization_id' in v_def) = 0
     or position('lower(email)' in v_def) = 0 then
    raise exception '[FAIL] uq_collaborators_org_email deveria ser unique (organization_id, lower(email)) — def=%', v_def;
  end if;
  raise notice '[PASS] collaborators: full_name/email NOT NULL com CHECKs + unique uq_collaborators_org_email (organization_id, lower(email))';
end $$;

do $$
declare
  v_tipo text;
  v_null text;
  v_def text;
begin
  select c.data_type, c.is_nullable into v_tipo, v_null
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'job_roles' and c.column_name = 'code';
  if v_tipo is null or v_tipo <> 'text' then
    raise exception '[FAIL] job_roles.code ausente ou nao textual (%)', coalesce(v_tipo, '-');
  end if;
  if v_null <> 'YES' then
    raise exception '[FAIL] job_roles.code deveria ser anulavel';
  end if;

  select string_agg(replace(lower(pg_get_constraintdef(c.oid)), ' ', ''), ' | ') into v_def
    from pg_constraint c
   where c.conrelid = 'public.job_roles'::regclass and c.contype = 'c';
  if v_def is null or position('btrim(code)' in v_def) = 0 or position('upper(code)' in v_def) = 0 then
    raise exception '[FAIL] CHECK de job_roles.code (trim, nao vazio, maiusculo) ausente';
  end if;

  select replace(lower(pg_get_indexdef(i.indexrelid)), ' ', '') into v_def
    from pg_index i
    join pg_class c on c.oid = i.indexrelid
   where c.relname = 'uq_job_roles_org_code';
  if v_def is null then
    raise exception '[FAIL] indice unico uq_job_roles_org_code ausente';
  end if;
  if position('createuniqueindex' in v_def) = 0
     or position('organization_id' in v_def) = 0
     or position('code' in v_def) = 0
     or position('codeisnotnull' in v_def) = 0 then
    raise exception '[FAIL] uq_job_roles_org_code deveria ser unique parcial (organization_id, code) where code is not null — def=%', v_def;
  end if;
  raise notice '[PASS] job_roles.code: anulavel, CHECK trim/maiusculo e unique parcial uq_job_roles_org_code';
end $$;

-- ============================================================================
-- 3) Funcoes F5-07: existencia, SECURITY INVOKER e EXECUTE somente service_role
-- ============================================================================
do $$
declare
  v_funcs text[] := array[
    'colaborador_ator_valido',
    'colaborador_visao_listar','colaborador_visao_obter',
    'colaborador_resolver_matricula','colaborador_historico_listar',
    'colaborador_criar','colaborador_editar','colaborador_identificador_definir',
    'colaborador_status_alterar','estrutura_ocupacao_definir',
    'estrutura_ocupacao_encerrar','estrutura_reporting_definir',
    'estrutura_reporting_encerrar','estrutura_responsabilidade_definir',
    'estrutura_responsabilidade_encerrar','colaborador_catalogo_bootstrap'];
  v_fn text;
  v_n int;
begin
  foreach v_fn in array v_funcs loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;
    if v_n <> 1 then
      raise exception '[FAIL] funcao public.% deveria ter exatamente 1 assinatura (encontradas=%)', v_fn, v_n;
    end if;
  end loop;
  raise notice '[PASS] as 16 funcoes F5-07 existem com 1 assinatura cada';
end $$;

do $$
declare
  v_funcs text[] := array[
    'colaborador_ator_valido',
    'colaborador_visao_listar','colaborador_visao_obter',
    'colaborador_resolver_matricula','colaborador_historico_listar',
    'colaborador_criar','colaborador_editar','colaborador_identificador_definir',
    'colaborador_status_alterar','estrutura_ocupacao_definir',
    'estrutura_ocupacao_encerrar','estrutura_reporting_definir',
    'estrutura_reporting_encerrar','estrutura_responsabilidade_definir',
    'estrutura_responsabilidade_encerrar','colaborador_catalogo_bootstrap'];
  v_lista text;
  v_n int;
begin
  select count(*), string_agg(p.proname, ', ' order by p.proname) into v_n, v_lista
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = any(v_funcs) and p.prosecdef;
  if v_n <> 0 then
    raise exception '[FAIL] funcao F5-07 SECURITY DEFINER (proibido pela espinha): %', v_lista;
  end if;
  raise notice '[PASS] as 16 funcoes F5-07 sao SECURITY INVOKER (nenhum DEFINER novo)';
end $$;

do $$
declare
  v_funcs text[] := array[
    'colaborador_ator_valido',
    'colaborador_visao_listar','colaborador_visao_obter',
    'colaborador_resolver_matricula','colaborador_historico_listar',
    'colaborador_criar','colaborador_editar','colaborador_identificador_definir',
    'colaborador_status_alterar','estrutura_ocupacao_definir',
    'estrutura_ocupacao_encerrar','estrutura_reporting_definir',
    'estrutura_reporting_encerrar','estrutura_responsabilidade_definir',
    'estrutura_responsabilidade_encerrar','colaborador_catalogo_bootstrap'];
  v_fn text;
  v_oid oid;
  v_n int;
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
   where n.nspname = 'public' and p.proname = any(v_funcs)
     and a.privilege_type = 'EXECUTE'
     and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole);
  if v_n <> 0 then
    raise exception '[FAIL] EXECUTE indevido (public/anon/authenticated) em % funcoes F5-07', v_n;
  end if;

  foreach v_fn in array v_funcs loop
    select p.oid into v_oid
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;
    if not has_function_privilege('service_role', v_oid, 'EXECUTE') then
      raise exception '[FAIL] funcao public.% sem EXECUTE para service_role', v_fn;
    end if;
  end loop;
  raise notice '[PASS] EXECUTE somente service_role nas 16 funcoes F5-07 (nenhuma superficie para authenticated)';
end $$;

do $$
declare
  v_cols text[] := array[
    'collaborator_id uuid','matricula text','full_name text','email text','status text',
    'admission_date date','unit_id uuid','unit_name text','job_role_code text',
    'job_role_name text','seniority_name text','manager_collaborator_id uuid',
    'manager_full_name text','version integer'];
  v_hist text[] := array[
    'event_id uuid','event_type text','effective_date timestamptz','reason text',
    'cycle_scope text','reference_cycle_id uuid','actor_user_profile_id uuid',
    'actor_full_name text','before_value jsonb','after_value jsonb','created_at timestamptz'];
  v_def text;
  v_col text;
  v_fn text;
begin
  foreach v_fn in array array['colaborador_visao_listar','colaborador_visao_obter'] loop
    select replace(replace(lower(pg_get_function_result(p.oid)), ' ', ''), 'timestampwithtimezone', 'timestamptz')
      into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;
    if v_def is null or v_def not like 'table(%' then
      raise exception '[FAIL] % deveria devolver TABLE (%)', v_fn, coalesce(v_def, '-');
    end if;
    foreach v_col in array v_cols loop
      if position(replace(v_col, ' ', '') in v_def) = 0 then
        raise exception '[FAIL] projecao de % sem a coluna congelada: %', v_fn, v_col;
      end if;
    end loop;
  end loop;

  select replace(replace(lower(pg_get_function_result(p.oid)), ' ', ''), 'timestampwithtimezone', 'timestamptz')
    into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'colaborador_historico_listar';
  if v_def is null or v_def not like 'table(%' then
    raise exception '[FAIL] colaborador_historico_listar deveria devolver TABLE (%)', coalesce(v_def, '-');
  end if;
  foreach v_col in array v_hist loop
    if position(replace(v_col, ' ', '') in v_def) = 0 then
      raise exception '[FAIL] projecao de colaborador_historico_listar sem a coluna congelada: %', v_col;
    end if;
  end loop;

  select lower(pg_get_function_result(p.oid)) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'colaborador_resolver_matricula';
  if v_def is null or v_def <> 'uuid' then
    raise exception '[FAIL] colaborador_resolver_matricula deveria devolver uuid (%)', coalesce(v_def, '-');
  end if;
  raise notice '[PASS] projecoes soberanas: 14 colunas (visao), 11 colunas (historico) e resolucao de matricula em uuid';
end $$;

-- ============================================================================
-- 4) T-19 + T-18: RLS em execucao (own-tenant) e nenhuma superficie direta
-- ============================================================================
select set_config('request.jwt.claim.sub', 'd7b00000-0000-0000-0000-0000000000a2', false);
set role authenticated;

do $$
declare
  v_n int;
  v_tabelas text[] := array[
    'collaborator_identifiers','occupations','position_reporting_lines',
    'organizational_units','organizational_positions'];
  v_tab text;
begin
  -- own-tenant visivel
  select count(*) into v_n from public.collaborators
   where organization_id = 'd7a00000-0000-0000-0000-0000000000a1';
  if v_n < 1 then
    raise exception '[FAIL] authenticated (Alfa) nao leu colaboradores do proprio tenant';
  end if;

  -- outro tenant invisivel, inclusive por UUID direto (IDOR)
  select count(*) into v_n from public.collaborators
   where organization_id = 'd7a00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] authenticated (Alfa) leu % colaboradores de Beta', v_n;
  end if;
  select count(*) into v_n from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] IDOR: colaborador de outro tenant visivel por UUID direto';
  end if;

  foreach v_tab in array v_tabelas loop
    execute format(
      'select count(*) from public.%I where organization_id = ''d7a00000-0000-0000-0000-0000000000b1''',
      v_tab) into v_n;
    if v_n <> 0 then
      raise exception '[FAIL] authenticated (Alfa) leu % linhas de outro tenant em %', v_n, v_tab;
    end if;
  end loop;

  -- collaborator_status_periods e filha indireta (sem organization_id)
  select count(*) into v_n
    from public.collaborator_status_periods p
    join public.collaborators c on c.id = p.collaborator_id
   where c.organization_id = 'd7a00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] authenticated (Alfa) leu periodos de status de outro tenant';
  end if;

  -- collaborator_events: a leitura direta de authenticated pode estar revogada
  -- (spine §1.2) ou concedida com policy own-tenant (desenho §10.3). Nos dois
  -- casos NENHUM dado de outro tenant pode ser visivel.
  v_n := -1;
  begin
    execute 'select count(*) from public.collaborator_events where organization_id = ''d7a00000-0000-0000-0000-0000000000b1'''
      into v_n;
  exception when insufficient_privilege then v_n := -1;
  end;
  if v_n > 0 then
    raise exception '[FAIL] authenticated (Alfa) leu % eventos de outro tenant', v_n;
  end if;

  raise notice '[PASS] T-19 RLS own-tenant em execucao: leitura restrita ao proprio tenant (inclusive por UUID direto e por heranca)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.collaborators (id, organization_id, full_name, email)
    values ('d7c00000-0000-0000-0000-0000000000e1', 'd7a00000-0000-0000-0000-0000000000a1',
            'Intruso Sintetico F5-07', 'intruso.f5-07@example.invalid');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated inseriu em collaborators (DML direto proibido)';
  end if;

  v_ok := false;
  begin
    update public.collaborators set full_name = 'adulterado';
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated atualizou collaborators';
  end if;

  v_ok := false;
  begin
    delete from public.collaborators;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated excluiu collaborators';
  end if;

  v_ok := false;
  begin
    insert into public.collaborator_events
      (organization_id, collaborator_id, event_type, effective_date, reason,
       actor_user_profile_id, actor_membership_id, operation_id)
    values ('d7a00000-0000-0000-0000-0000000000a1', 'd7c00000-0000-0000-0000-0000000000c2',
            'ADMISSAO', now(), 'intruso', 'd7b00000-0000-0000-0000-0000000000a2',
            'd7d00000-0000-0000-0000-0000000000a2', 'd7100000-0000-0000-0000-0000000000ff');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated inseriu na trilha append-only';
  end if;

  v_ok := false;
  begin
    update public.collaborator_events set reason = 'adulterado';
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated atualizou a trilha append-only';
  end if;

  v_ok := false;
  begin
    delete from public.collaborator_events;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated excluiu a trilha append-only';
  end if;

  raise notice '[PASS] authenticated sem INSERT/UPDATE/DELETE em colaboradores e no historico (mutacao somente por RPC)';
end $$;

reset role;

-- ============================================================================
-- 5) T-02 + T-22: capability e o plano administrativo NAO vem de cargo
-- ============================================================================
do $$
declare
  v_caps text[];
  v_n int;
begin
  -- ADMIN do tenant: plano administrativo (D19) via role de sistema atribuida
  select array_agg(x.capability_code) into v_caps
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a1','d7a00000-0000-0000-0000-0000000000a1') x;
  if v_caps is null then
    raise exception '[FAIL] ator ADMIN nao possui capability efetiva na organizacao';
  end if;
  if not ('org.structure.manage' = any(v_caps)) then
    raise exception '[FAIL] ator ADMIN sem org.structure.manage';
  end if;
  if not ('org.catalog.manage' = any(v_caps)) then
    raise exception '[FAIL] ator ADMIN sem org.catalog.manage';
  end if;
  if not ('collaborator.create' = any(v_caps)) or not ('collaborator.edit' = any(v_caps)) then
    raise exception '[FAIL] ator ADMIN sem collaborator.create/collaborator.edit';
  end if;
  if not public.usuario_eh_administrador('d7b00000-0000-0000-0000-0000000000a1','d7a00000-0000-0000-0000-0000000000a1') then
    raise exception '[FAIL] ator ADMIN nao reconhecido pelo plano administrativo';
  end if;

  -- Ator funcional: collaborator.read/create/edit e NENHUMA capability de estrutura
  select array_agg(x.capability_code) into v_caps
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1') x;
  if v_caps is null
     or not ('collaborator.read' = any(v_caps))
     or not ('collaborator.create' = any(v_caps))
     or not ('collaborator.edit' = any(v_caps)) then
    raise exception '[FAIL] ator funcional sem collaborator.read/create/edit (%)', coalesce(v_caps::text, '-');
  end if;
  if 'org.structure.manage' = any(v_caps) then
    raise exception '[FAIL] ator funcional possui org.structure.manage (plano administrativo vazado)';
  end if;
  if public.usuario_eh_administrador('d7b00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1') then
    raise exception '[FAIL] ator funcional reconhecido como administrador';
  end if;

  -- Ator SEM permissao: predicado vazio => a fronteira nega (fail-closed)
  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a3','d7a00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] ator sem permissao possui % capabilities efetivas', v_n;
  end if;

  -- Perfil inativo: predicado vazio mesmo com membership ativa
  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a6','d7a00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] perfil inativo possui % capabilities efetivas', v_n;
  end if;

  raise notice '[PASS] T-02 plano de autorizacao: ADMIN com org.structure.manage/org.catalog.manage, ator funcional com collaborator.read/create/edit e ator sem permissao sem nenhuma capability';
end $$;

do $$
declare
  v_caps_antes text[];
  v_caps_depois text[];
  v_n int;
begin
  -- Antes: o ator vinculado a um colaborador que OCUPA posicao de cargo GERENTE
  -- (a4 -> c3 -> p4 -> job_role code GERENTE) NAO possui capability nenhuma.
  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a4','d7a00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] ator vinculado a cargo GERENTE possui % capabilities (autorizacao por cargo)', v_n;
  end if;
  if public.usuario_eh_administrador('d7b00000-0000-0000-0000-0000000000a4','d7a00000-0000-0000-0000-0000000000a1') then
    raise exception '[FAIL] cargo GERENTE concedeu autoridade administrativa';
  end if;

  select array_agg(x.capability_code order by x.capability_code) into v_caps_antes
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a1','d7a00000-0000-0000-0000-0000000000a1') x;

  -- Troca o codigo do cargo ocupado (GERENTE -> COORDENADOR) e o do cargo vago.
  update public.job_roles set code = 'COORDENADOR'
   where id = 'd7f00000-0000-0000-0000-0000000000a1';
  update public.job_roles set code = 'GERENTE'
   where id = 'd7f00000-0000-0000-0000-0000000000a3';

  select array_agg(x.capability_code order by x.capability_code) into v_caps_depois
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a1','d7a00000-0000-0000-0000-0000000000a1') x;

  if v_caps_depois is distinct from v_caps_antes then
    raise exception '[FAIL] T-22 violado: alterar job_roles.code mudou a capability efetiva do ator';
  end if;

  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a4','d7a00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] T-22 violado: job_roles.code passou a conceder capability (%)', v_n;
  end if;

  -- Restaura o catalogo do cenario (a ordem evita colisao no unique parcial).
  update public.job_roles set code = 'CONSULTOR'
   where id = 'd7f00000-0000-0000-0000-0000000000a3';
  update public.job_roles set code = 'GERENTE'
   where id = 'd7f00000-0000-0000-0000-0000000000a1';

  raise notice '[PASS] T-22 job_roles.code nao altera capability/escopo nem autoridade administrativa (autorizacao nunca vem de cargo)';
end $$;

-- ============================================================================
-- 6) T-07: ator sem colaborador vinculado nao alcanca escopos estruturais
-- ============================================================================
do $$
declare
  v_n int;
  v_self int;
begin
  select count(*) into v_n
    from public.resolver_collaborador_vinculado(
      'd7b00000-0000-0000-0000-0000000000a3','d7a00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] ator sem vinculo possui colaborador vinculado';
  end if;

  select count(*) into v_self
    from public.resolver_alvos_escopo(
      'd7b00000-0000-0000-0000-0000000000a3','d7a00000-0000-0000-0000-0000000000a1',
      'SELF', null, '2025-06-15T00:00:00Z');
  if v_self <> 0 then
    raise exception '[FAIL] escopo SELF resolveu alvos para ator sem vinculo (%)', v_self;
  end if;
  select count(*) into v_self
    from public.resolver_alvos_escopo(
      'd7b00000-0000-0000-0000-0000000000a3','d7a00000-0000-0000-0000-0000000000a1',
      'DIRECT_REPORTS', null, '2025-06-15T00:00:00Z');
  if v_self <> 0 then
    raise exception '[FAIL] escopo DIRECT_REPORTS resolveu alvos para ator sem vinculo (%)', v_self;
  end if;
  select count(*) into v_self
    from public.resolver_alvos_escopo(
      'd7b00000-0000-0000-0000-0000000000a3','d7a00000-0000-0000-0000-0000000000a1',
      'DESCENDANTS', null, '2025-06-15T00:00:00Z');
  if v_self <> 0 then
    raise exception '[FAIL] escopo DESCENDANTS resolveu alvos para ator sem vinculo (%)', v_self;
  end if;

  -- Controle positivo: o ator COM vinculo (a2 -> c1) resolve SELF.
  select count(*) into v_self
    from public.resolver_alvos_escopo(
      'd7b00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1',
      'SELF', null, '2025-06-15T00:00:00Z');
  if v_self <> 1 then
    raise exception '[FAIL] escopo SELF do ator vinculado deveria resolver 1 alvo (encontrados=%)', v_self;
  end if;

  raise notice '[PASS] T-07 ator sem colaborador vinculado: escopos SELF/DIRECT_REPORTS/DESCENDANTS vazios (DENY) e o vinculado resolve o proprio alvo';
end $$;

-- ============================================================================
-- 7) T-01: CRUD autorizado de colaborador (criar, editar, identificador)
-- ============================================================================
do $$
declare
  v_id uuid;
  v_ev int;
  v_status text;
  v_matricula text;
begin
  -- Criar pelo ATOR FUNCIONAL (collaborator.create no plano funcional).
  v_id := public.colaborador_criar(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a2',
    'd7100000-0000-0000-0000-000000000001',
    'Colaborador Sintetico F5-07 Dez',
    'colaborador.f5-07.10@example.invalid',
    'F507-0100',
    date '2025-01-01',
    'active');

  if v_id is null then
    raise exception '[FAIL] colaborador_criar nao devolveu o UUID soberano';
  end if;

  select full_name, email into v_status, v_matricula
    from public.collaborators where id = v_id;
  if v_status <> 'Colaborador Sintetico F5-07 Dez'
     or v_matricula <> 'colaborador.f5-07.10@example.invalid' then
    raise exception '[FAIL] colaborador_criar nao persistiu os dados de pessoa (%)', v_status;
  end if;

  if not exists (
    select 1 from public.collaborator_identifiers
     where collaborator_id = v_id
       and organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and business_code = 'F507-0100'
       and valid_to is null
  ) then
    raise exception '[FAIL] colaborador_criar nao abriu o identificador (linha aberta)';
  end if;

  if not exists (
    select 1 from public.collaborator_status_periods
     where collaborator_id = v_id and status = 'active' and valid_to is null
       and valid_from = '2025-01-01T00:00:00Z'
  ) then
    raise exception '[FAIL] colaborador_criar nao abriu o periodo de status inicial';
  end if;

  select count(*) into v_ev
    from public.collaborator_events
   where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
     and operation_id = 'd7100000-0000-0000-0000-000000000001'
     and event_type = 'ADMISSAO'
     and collaborator_id = v_id
     and actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a2'
     and actor_membership_id = 'd7d00000-0000-0000-0000-0000000000a2'
     and payload_hash is not null
     and result_entity_id is not null;
  if v_ev <> 1 then
    raise exception '[FAIL] colaborador_criar sem evento ADMISSAO com autoria/operation_id (encontrados=%)', v_ev;
  end if;

  raise notice '[PASS] T-01 colaborador_criar: pessoa + identificador aberto + status inicial + evento ADMISSAO com autoria na mesma transacao';
end $$;

do $$
declare
  v_id uuid;
  v_ev int;
begin
  -- Criar pelo ADMIN do tenant com status inicial 'leave' (aceito pela espinha).
  v_id := public.colaborador_criar(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000002',
    'Colaborador Sintetico F5-07 Onze',
    'colaborador.f5-07.11@example.invalid',
    'F507-0101',
    null,
    'leave');

  if not exists (
    select 1 from public.collaborator_status_periods
     where collaborator_id = v_id and status = 'leave' and valid_to is null
  ) then
    raise exception '[FAIL] colaborador_criar nao aceitou/protegeu o status inicial leave';
  end if;

  select count(*) into v_ev from public.collaborator_events
   where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
     and operation_id = 'd7100000-0000-0000-0000-000000000002'
     and event_type = 'ADMISSAO' and collaborator_id = v_id;
  if v_ev < 1 then
    raise exception '[FAIL] criar com status inicial leave sem evento ADMISSAO';
  end if;

  raise notice '[PASS] T-01 colaborador_criar com status inicial leave (admissao sem alocacao, evento com autoria)';
end $$;

do $$
declare
  v_msg text := null;
  v_state text := null;
begin
  -- Status inicial fora do dominio (inactive exige fluxo proprio) => recusa sem efeito.
  begin
    perform public.colaborador_criar(
      'd7a00000-0000-0000-0000-0000000000a1',
      'd7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000003',
      'Colaborador Sintetico F5-07 Invalido',
      'colaborador.f5-07.invalido@example.invalid',
      'F507-0102',
      null,
      'inactive');
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_criar (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null then
    raise exception '[FAIL] colaborador_criar aceitou status inicial inactive';
  end if;
  if v_msg not like 'F5_07_%' then
    raise exception '[FAIL] recusa de status inicial sem prefixo padronizado (msg=%)', v_msg;
  end if;
  if exists (select 1 from public.collaborators
              where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
                and email = 'colaborador.f5-07.invalido@example.invalid') then
    raise exception '[FAIL] status inicial invalido deixou colaborador escrito (escrita parcial)';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000003') then
    raise exception '[FAIL] status inicial invalido deixou evento escrito';
  end if;

  raise notice '[PASS] T-01/T-20 colaborador_criar recusa status inicial fora do dominio (F5_07_*) sem escrita parcial';
end $$;

do $$
declare
  v_ver_antes int;
  v_ver_nova int;
  v_id uuid := 'd7c00000-0000-0000-0000-0000000000c2';
begin
  select version into v_ver_antes from public.collaborators where id = v_id;

  v_ver_nova := public.colaborador_editar(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000004',
    v_id,
    'Colaborador Sintetico F5-07 Dois Editado',
    'colaborador.f5-07.2.editado@example.invalid',
    date '2024-02-02',
    v_ver_antes);

  if v_ver_nova is null or v_ver_nova <= v_ver_antes then
    raise exception '[FAIL] colaborador_editar nao devolveu versao superior (% -> %)', v_ver_antes, v_ver_nova;
  end if;

  if not exists (
    select 1 from public.collaborators
     where id = v_id
       and full_name = 'Colaborador Sintetico F5-07 Dois Editado'
       and email = 'colaborador.f5-07.2.editado@example.invalid'
       and admission_date = date '2024-02-02'
       and version = v_ver_nova
  ) then
    raise exception '[FAIL] colaborador_editar nao persistiu pessoa/versao';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000004'
       and event_type = 'DADOS_PESSOAIS_ALTERADOS'
       and collaborator_id = v_id
       and actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
       and before_value is not null
       and after_value is not null
       and payload_hash is not null
  ) then
    raise exception '[FAIL] colaborador_editar sem evento DADOS_PESSOAIS_ALTERADOS com delta e autoria';
  end if;

  raise notice '[PASS] T-01 colaborador_editar: dados de pessoa + version nova + evento DADOS_PESSOAIS_ALTERADOS com delta/autoria';
end $$;

do $$
declare
  v_msg text := null;
  v_state text := null;
  v_ver_obsoleta int;
begin
  select version - 1 into v_ver_obsoleta
    from public.collaborators where id = 'd7c00000-0000-0000-0000-0000000000c2';

  begin
    perform public.colaborador_editar(
      'd7a00000-0000-0000-0000-0000000000a1',
      'd7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000005',
      'd7c00000-0000-0000-0000-0000000000c2',
      'Nome Que Nao Deve Persistir',
      'nao.persistir.f5-07@example.invalid',
      date '2024-03-03',
      v_ver_obsoleta);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_editar (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null or v_msg not like 'F5_07_CONFLICT%' then
    raise exception '[FAIL] expected_version obsoleto deveria falhar com F5_07_CONFLICT (msg=%)', v_msg;
  end if;
  if exists (select 1 from public.collaborators
              where id = 'd7c00000-0000-0000-0000-0000000000c2'
                and full_name = 'Nome Que Nao Deve Persistir') then
    raise exception '[FAIL] conflito de versao escreveu o cadastro (last-write-wins)';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000005') then
    raise exception '[FAIL] conflito de versao gravou evento';
  end if;

  raise notice '[PASS] T-01/13.1 versao otimista: expected_version divergente => F5_07_CONFLICT sem nenhuma escrita';
end $$;

do $$
declare
  v_ret int;
  v_ver int;
  v_ret_mat uuid;
begin
  select version into v_ver from public.collaborators where id = 'd7c00000-0000-0000-0000-0000000000c2';

  v_ret := public.colaborador_identificador_definir(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000006',
    'd7c00000-0000-0000-0000-0000000000c2',
    'F507-0002B',
    '2025-05-01T00:00:00Z',
    'Troca de matricula sintetica F5-07',
    v_ver);

  if v_ret is null then
    raise exception '[FAIL] colaborador_identificador_definir nao devolveu a versao';
  end if;

  if not exists (
    select 1 from public.collaborator_identifiers
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c2'
       and business_code = 'F507-0002'
       and valid_to is not null and valid_to <= '2025-05-01T00:00:00Z'
  ) then
    raise exception '[FAIL] identificador anterior nao foi encerrado (historico nao destrutivo)';
  end if;

  if not exists (
    select 1 from public.collaborator_identifiers
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c2'
       and business_code = 'F507-0002B'
       and valid_from = '2025-05-01T00:00:00Z' and valid_to is null
  ) then
    raise exception '[FAIL] novo identificador nao foi aberto na vigencia informada';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000006'
       and event_type = 'IDENTIFICADOR_DEFINIDO'
       and collaborator_id = 'd7c00000-0000-0000-0000-0000000000c2'
       and actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
  ) then
    raise exception '[FAIL] colaborador_identificador_definir sem evento IDENTIFICADOR_DEFINIDO com autoria';
  end if;

  v_ret_mat := public.colaborador_resolver_matricula(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'F507-0002B');
  if v_ret_mat is distinct from 'd7c00000-0000-0000-0000-0000000000c2'::uuid then
    raise exception '[FAIL] resolucao da nova matricula devolveu % (esperado c2)', coalesce(v_ret_mat::text, 'NULL');
  end if;

  if public.colaborador_resolver_matricula(
       'd7a00000-0000-0000-0000-0000000000a1',
       'd7b00000-0000-0000-0000-0000000000a1',
       'F507-0002') is not null then
    raise exception '[FAIL] matricula encerrada ainda resolve colaborador (linha fechada nao e identidade)';
  end if;

  raise notice '[PASS] T-01 colaborador_identificador_definir: fecha a linha aberta, abre a nova, evento com autoria e resolucao server-side da matricula';
end $$;

do $$
declare
  v_msg text := null;
  v_state text := null;
  v_ver int;
begin
  select version into v_ver from public.collaborators where id = 'd7c00000-0000-0000-0000-0000000000c4';

  -- Matricula ja usada na organizacao (sem reutilizacao de codigo) => fail-closed.
  begin
    perform public.colaborador_identificador_definir(
      'd7a00000-0000-0000-0000-0000000000a1',
      'd7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000007',
      'd7c00000-0000-0000-0000-0000000000c4',
      'F507-0001',
      '2025-07-01T00:00:00Z',
      'Reuso de matricula sintetica F5-07',
      v_ver);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_identificador_definir (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null then
    raise exception '[FAIL] identificador_definir aceitou matricula ja usada na organizacao';
  end if;
  if exists (select 1 from public.collaborator_identifiers
              where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c4'
                and business_code = 'F507-0001') then
    raise exception '[FAIL] reuso de matricula deixou identificador escrito';
  end if;
  if not exists (select 1 from public.collaborator_identifiers
                  where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c4'
                    and business_code = 'F507-0004' and valid_to is null) then
    raise exception '[FAIL] reuso de matricula alterou a linha vigente do colaborador (escrita parcial)';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000007') then
    raise exception '[FAIL] reuso de matricula gravou evento';
  end if;

  raise notice '[PASS] T-01 identificador_definir recusa matricula ja existente na organizacao (fail-closed, sem escrita parcial)';
end $$;

-- ============================================================================
-- 8) T-09 + T-08 + T-14: troca de unidade/posicao, troca de gestor e tempo
-- ============================================================================
do $$
declare
  v_oc uuid;
begin
  v_oc := public.estrutura_ocupacao_definir(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000008',
    'd7c00000-0000-0000-0000-0000000000c5',
    'd7f00000-0000-0000-0000-0000000000c6',
    '2025-04-01T00:00:00Z',
    'Troca de unidade e posicao sintetica F5-07',
    'CICLO_ATUAL_E_POSTERIORES',
    'd7f00000-0000-0000-0000-0000000000d9');

  if v_oc is null then
    raise exception '[FAIL] estrutura_ocupacao_definir nao devolveu a ocupacao';
  end if;

  if not exists (
    select 1 from public.occupations
     where id = 'd7f00000-0000-0000-0000-0000000000f5'
       and valid_to is not null and valid_to <= '2025-04-01T00:00:00Z'
  ) then
    raise exception '[FAIL] ocupacao anterior nao foi encerrada (historico preservado por fechar-e-abrir)';
  end if;

  if not exists (
    select 1 from public.occupations
     where id = v_oc
       and collaborator_id = 'd7c00000-0000-0000-0000-0000000000c5'
       and organizational_position_id = 'd7f00000-0000-0000-0000-0000000000c6'
       and valid_from = '2025-04-01T00:00:00Z' and valid_to is null
  ) then
    raise exception '[FAIL] nova ocupacao nao foi aberta na posicao/vigencia informadas';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000008'
       and event_type = 'OCUPACAO_INICIADA'
       and actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
       and payload_hash is not null
  ) then
    raise exception '[FAIL] estrutura_ocupacao_definir sem evento OCUPACAO_INICIADA com autoria';
  end if;

  raise notice '[PASS] T-09 estrutura_ocupacao_definir: fecha a ocupacao vigente, abre a nova e registra OCUPACAO_INICIADA com autoria';
end $$;

do $$
declare
  v_rl uuid;
begin
  v_rl := public.estrutura_reporting_definir(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000009',
    'd7f00000-0000-0000-0000-0000000000c2',
    'd7f00000-0000-0000-0000-0000000000c3',
    '2025-03-01T00:00:00Z',
    'Troca de gestor sintetica F5-07');

  if v_rl is null then
    raise exception '[FAIL] estrutura_reporting_definir nao devolveu a linha';
  end if;

  if not exists (
    select 1 from public.position_reporting_lines
     where id = 'd7f00000-0000-0000-0000-0000000000e1'
       and valid_to is not null and valid_to <= '2025-03-01T00:00:00Z'
  ) then
    raise exception '[FAIL] linha de reporting anterior nao foi encerrada (passado reescrito?)';
  end if;

  if not exists (
    select 1 from public.position_reporting_lines
     where id = v_rl
       and subordinate_position_id = 'd7f00000-0000-0000-0000-0000000000c2'
       and manager_position_id = 'd7f00000-0000-0000-0000-0000000000c3'
       and valid_from = '2025-03-01T00:00:00Z' and valid_to is null
  ) then
    raise exception '[FAIL] nova linha de reporting nao foi aberta';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000009'
       and event_type = 'REPORTING_LINE_INICIADA'
       and actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
  ) then
    raise exception '[FAIL] estrutura_reporting_definir sem evento REPORTING_LINE_INICIADA com autoria';
  end if;

  raise notice '[PASS] T-08 estrutura_reporting_definir: fecha a linha vigente, abre a nova e registra REPORTING_LINE_INICIADA com autoria';
end $$;

do $$
declare
  v_data_ant timestamptz := '2025-01-15T00:00:00Z';
  v_data_pos timestamptz := '2025-06-15T00:00:00Z';
  v_status_ant text;
  v_uni_ant uuid;
  v_fun_ant text;
  v_ges_ant uuid;
  v_status_pos text;
  v_uni_pos uuid;
  v_fun_pos text;
  v_ges_pos uuid;
  v_n int;
  v_arr timestamptz[];
  v_ordenado timestamptz[];
begin
  select v.status, v.unit_id, v.job_role_code, v.manager_collaborator_id
    into v_status_ant, v_uni_ant, v_fun_ant, v_ges_ant
    from public.colaborador_visao_obter(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c2', v_data_ant) v;

  select v.status, v.unit_id, v.job_role_code, v.manager_collaborator_id
    into v_status_pos, v_uni_pos, v_fun_pos, v_ges_pos
    from public.colaborador_visao_obter(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c2', v_data_pos) v;

  if v_uni_ant is null or v_fun_ant is null then
    raise exception '[FAIL] T-14 visao historica vazia para data valida (estado por data nao resolvido)';
  end if;

  -- T-08: o gestor DERIVADO muda na data nova e NAO na data anterior.
  if v_ges_ant is distinct from 'd7c00000-0000-0000-0000-0000000000c1'::uuid then
    raise exception '[FAIL] T-08 gestor na data anterior deveria ser c1 (%)', coalesce(v_ges_ant::text, 'NULL');
  end if;
  if v_ges_pos is distinct from 'd7c00000-0000-0000-0000-0000000000c4'::uuid then
    raise exception '[FAIL] T-08 gestor na data nova deveria ser c4 (%)', coalesce(v_ges_pos::text, 'NULL');
  end if;
  if v_ges_ant = v_ges_pos then
    raise exception '[FAIL] T-08 troca de gestor nao alterou a hierarquia derivada';
  end if;

  -- A ocupacao de c2 nao mudou: unidade/funcao estaveis nas duas datas.
  if v_uni_ant is distinct from 'd7f00000-0000-0000-0000-0000000000b2'::uuid
     or v_uni_pos is distinct from 'd7f00000-0000-0000-0000-0000000000b2'::uuid then
    raise exception '[FAIL] T-14 unidade derivada indevida na visao historica';
  end if;
  if v_fun_ant <> 'ANALISTA' or v_fun_pos <> 'ANALISTA' then
    raise exception '[FAIL] T-14 job_role_code derivado indevido (%) / (%)', v_fun_ant, v_fun_pos;
  end if;
  if v_status_ant <> 'active' or v_status_pos <> 'active' then
    raise exception '[FAIL] T-14 status vigente indevido (%) / (%)', v_status_ant, v_status_pos;
  end if;

  -- Anti-anacronismo: antes do inicio do periodo nao existe status "vigente".
  select count(*) into v_n
    from public.colaborador_visao_obter(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c2', '2023-01-01T00:00:00Z') v
   where v.status is not null;
  if v_n <> 0 then
    raise exception '[FAIL] T-14 anacronismo: status exibido antes do inicio da vigencia';
  end if;

  -- T-09: c5 troca de unidade/funcao a partir de 2025-04-01.
  select v.unit_id, v.job_role_code into v_uni_ant, v_fun_ant
    from public.colaborador_visao_obter(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c5', '2025-01-15T00:00:00Z') v;
  select v.unit_id, v.job_role_code into v_uni_pos, v_fun_pos
    from public.colaborador_visao_obter(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c5', '2025-06-15T00:00:00Z') v;

  if v_uni_ant is distinct from 'd7f00000-0000-0000-0000-0000000000b2'::uuid
     or v_fun_ant <> 'ANALISTA' then
    raise exception '[FAIL] T-09 unidade/funcao anteriores incorretas (% / %)', v_uni_ant, v_fun_ant;
  end if;
  if v_uni_pos is distinct from 'd7f00000-0000-0000-0000-0000000000b1'::uuid
     or v_fun_pos <> 'CONSULTOR' then
    raise exception '[FAIL] T-09 unidade/funcao novas incorretas (% / %)', v_uni_pos, v_fun_pos;
  end if;

  -- Historico de c2: ordenado, com autoria e delta.
  select count(*) into v_n
    from public.colaborador_historico_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c2') h
   where h.event_type = 'DADOS_PESSOAIS_ALTERADOS'
     and h.actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
     and h.after_value is not null;
  if v_n <> 1 then
    raise exception '[FAIL] historico sem o evento DADOS_PESSOAIS_ALTERADOS com autoria/delta (%)', v_n;
  end if;

  select count(*) into v_n
    from public.colaborador_historico_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c2') h
   where h.event_type = 'IDENTIFICADOR_DEFINIDO';
  if v_n < 1 then
    raise exception '[FAIL] historico sem o evento IDENTIFICADOR_DEFINIDO';
  end if;

  select count(*) into v_n
    from public.colaborador_historico_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c2');
  if v_n < 2 then
    raise exception '[FAIL] historico de c2 deveria conter ao menos 2 eventos (%)', v_n;
  end if;

  -- Ordenacao do historico: effective_date desc, created_at desc.
  select array_agg(h.effective_date) into v_arr
    from public.colaborador_historico_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c2') h;
  select array_agg(h.effective_date) into v_ordenado
    from (select * from public.colaborador_historico_listar(
            'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
            'd7c00000-0000-0000-0000-0000000000c2')
           order by effective_date desc, created_at desc) h;
  if v_arr is distinct from v_ordenado then
    raise exception '[FAIL] historico fora da ordenacao (effective_date desc, created_at desc)';
  end if;

  raise notice '[PASS] T-08/T-09/T-14 hierarquia e estrutura derivadas por data (gestor/unidade/funcao mudam na data nova, nao na anterior) com historico ordenado e autorado';
end $$;

do $$
declare
  v_msg text := null;
  v_state text := null;
begin
  -- Posicao de OUTRO tenant como destino => DENY, nada escrito.
  begin
    perform public.estrutura_ocupacao_definir(
      'd7a00000-0000-0000-0000-0000000000a1',
      'd7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000010',
      'd7c00000-0000-0000-0000-0000000000c2',
      'd7f00000-0000-0000-0000-0000000000d3',
      '2025-08-01T00:00:00Z',
      'Posicao de outro tenant (IDOR)',
      'CICLO_ATUAL_E_POSTERIORES',
      null);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a estrutura_ocupacao_definir (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null then
    raise exception '[FAIL] T-03 ocupacao com posicao de outro tenant foi ACEITA';
  end if;
  if exists (select 1 from public.occupations
              where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
                and organizational_position_id = 'd7f00000-0000-0000-0000-0000000000d3') then
    raise exception '[FAIL] T-03 cross-tenant deixou ocupacao escrita';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000010') then
    raise exception '[FAIL] T-03 cross-tenant gravou evento';
  end if;

  raise notice '[PASS] T-03 cross-tenant: posicao de outro tenant recusada (fail-closed) e nada escrito';
end $$;

do $$
declare
  v_msg text := null;
  v_state text := null;
begin
  -- Auto-reporting (posicao subordinada = posicao gestora) => recusa.
  begin
    perform public.estrutura_reporting_definir(
      'd7a00000-0000-0000-0000-0000000000a1',
      'd7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000011',
      'd7f00000-0000-0000-0000-0000000000c2',
      'd7f00000-0000-0000-0000-0000000000c2',
      '2025-09-01T00:00:00Z',
      'Auto-reporting sintetico F5-07');
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a estrutura_reporting_definir (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null then
    raise exception '[FAIL] auto-reporting foi aceito';
  end if;
  if exists (select 1 from public.position_reporting_lines
              where subordinate_position_id = 'd7f00000-0000-0000-0000-0000000000c2'
                and manager_position_id = 'd7f00000-0000-0000-0000-0000000000c2') then
    raise exception '[FAIL] auto-reporting deixou linha escrita';
  end if;
  if not exists (select 1 from public.position_reporting_lines
                  where subordinate_position_id = 'd7f00000-0000-0000-0000-0000000000c2'
                    and manager_position_id = 'd7f00000-0000-0000-0000-0000000000c3'
                    and valid_to is null) then
    raise exception '[FAIL] tentativa recusada alterou a linha vigente (escrita parcial)';
  end if;

  raise notice '[PASS] T-08 auto-reporting recusado e a linha vigente permanece intacta (sem escrita parcial)';
end $$;

-- ============================================================================
-- 9) T-10/T-11: ciclo de status (active -> leave -> active) preservando ocupacao
-- ============================================================================
do $$
declare
  v_ver int;
  v_ret int;
  v_n int;
begin
  select version into v_ver from public.collaborators where id = 'd7c00000-0000-0000-0000-0000000000c6';

  v_ret := public.colaborador_status_alterar(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000012',
    'd7c00000-0000-0000-0000-0000000000c6',
    'leave',
    '2025-02-01T00:00:00Z',
    'Licenca sintetica F5-07',
    'CICLO_ATUAL_E_POSTERIORES',
    'd7f00000-0000-0000-0000-0000000000d9',
    v_ver);

  if v_ret is null then
    raise exception '[FAIL] colaborador_status_alterar nao devolveu a versao';
  end if;

  if not exists (
    select 1 from public.collaborator_status_periods
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
       and status = 'leave' and valid_from = '2025-02-01T00:00:00Z' and valid_to is null
  ) then
    raise exception '[FAIL] T-11 periodo de licenca nao foi aberto';
  end if;

  if not exists (
    select 1 from public.collaborator_status_periods
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
       and status = 'active' and valid_to is not null
  ) then
    raise exception '[FAIL] T-11 periodo anterior de status nao foi encerrado';
  end if;

  -- T-11: a licenca NAO encerra a ocupacao.
  if not exists (
    select 1 from public.occupations
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6' and valid_to is null
  ) then
    raise exception '[FAIL] T-11 licenca encerrou a ocupacao (proibido: LEAVE nao encerra posicao)';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000012'
       and event_type = 'STATUS_ALTERADO'
       and collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
       and actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
       and cycle_scope = 'CICLO_ATUAL_E_POSTERIORES'
       and reference_cycle_id = 'd7f00000-0000-0000-0000-0000000000d9'
       and payload_hash is not null
  ) then
    raise exception '[FAIL] T-11 evento STATUS_ALTERADO sem escopo de ciclo/ciclo de referencia/autoria';
  end if;

  select count(*) into v_n
    from public.collaborator_status_periods p
   where p.collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
     and p.valid_from <= '2025-03-01T00:00:00Z'::timestamptz
     and (p.valid_to is null or p.valid_to > '2025-03-01T00:00:00Z'::timestamptz);
  if v_n <> 1 then
    raise exception '[FAIL] T-10 sobreposicao de periodos de status em 2025-03-01 (%)', v_n;
  end if;

  raise notice '[PASS] T-10/T-11 licenca: vigencia encadeada sem sobreposicao, ocupacao preservada, evento STATUS_ALTERADO com escopo de ciclo e autoria';
end $$;

do $$
declare
  v_ver int;
  v_ret int;
  v_n int;
begin
  select version into v_ver from public.collaborators where id = 'd7c00000-0000-0000-0000-0000000000c6';

  v_ret := public.colaborador_status_alterar(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000013',
    'd7c00000-0000-0000-0000-0000000000c6',
    'active',
    '2025-05-01T00:00:00Z',
    'Retorno de licenca sintetico F5-07',
    'SOMENTE_CICLOS_POSTERIORES',
    'd7f00000-0000-0000-0000-0000000000d9',
    v_ver);

  if not exists (
    select 1 from public.collaborator_status_periods
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
       and status = 'active' and valid_from = '2025-05-01T00:00:00Z' and valid_to is null
  ) then
    raise exception '[FAIL] T-10 retorno de licenca nao abriu o periodo active';
  end if;

  if not exists (
    select 1 from public.collaborator_status_periods
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
       and status = 'leave' and valid_to is not null and valid_to <= '2025-05-01T00:00:00Z'
  ) then
    raise exception '[FAIL] T-10 periodo de licenca nao foi encerrado no retorno';
  end if;

  select count(*) into v_n
    from public.collaborator_status_periods
   where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
     and valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] T-10 deveria haver exatamente 1 periodo aberto (%)', v_n;
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000013'
       and event_type = 'STATUS_ALTERADO'
       and cycle_scope = 'SOMENTE_CICLOS_POSTERIORES'
  ) then
    raise exception '[FAIL] T-10 evento STATUS_ALTERADO de retorno ausente ou sem cycle_scope';
  end if;

  raise notice '[PASS] T-10 active -> leave -> active: tres vigenciais encadeadas, exatamente um periodo aberto, eventos append-only';
end $$;

-- ============================================================================
-- 10) T-12 + T-20: inativacao com pendencia (CONFLICT) e depois permitida
-- ============================================================================
do $$
declare
  v_ver int;
  v_msg text := null;
  v_state text := null;
begin
  select version into v_ver from public.collaborators where id = 'd7c00000-0000-0000-0000-0000000000c3';

  begin
    perform public.colaborador_status_alterar(
      'd7a00000-0000-0000-0000-0000000000a1',
      'd7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000014',
      'd7c00000-0000-0000-0000-0000000000c3',
      'inactive',
      '2025-10-01T00:00:00Z',
      'Desligamento com pendencia estrutural F5-07',
      'CICLO_ATUAL_E_POSTERIORES',
      null,
      v_ver);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_status_alterar (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null or v_msg not like 'F5_07_CONFLICT%' then
    raise exception '[FAIL] T-12 inactive com ocupacao vigente deveria falhar com F5_07_CONFLICT (msg=%)', v_msg;
  end if;

  -- T-20: a mutacao recusada NAO deixa nada escrito (estado nem evento).
  if exists (select 1 from public.collaborator_status_periods
              where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c3'
                and status = 'inactive') then
    raise exception '[FAIL] T-12 periodo inactive escrito apesar do CONFLICT';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000014') then
    raise exception '[FAIL] T-20 mutacao recusada gravou evento (fora da mesma transacao)';
  end if;
  if not exists (select 1 from public.occupations
                  where id = 'd7f00000-0000-0000-0000-0000000000f3' and valid_to is null) then
    raise exception '[FAIL] T-12 pendencia foi fechada silenciosamente (D6 proibe cascata)';
  end if;

  raise notice '[PASS] T-12/T-20 inactive com ocupacao vigente: F5_07_CONFLICT listando pendencia, estado e evento intactos (nada escrito)';
end $$;

do $$
declare
  v_ver int;
  v_ret int;
begin
  perform public.estrutura_ocupacao_encerrar(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000015',
    'd7c00000-0000-0000-0000-0000000000c3',
    '2025-10-01T00:00:00Z',
    'Encerramento da ocupacao antes do desligamento F5-07');

  if not exists (
    select 1 from public.occupations
     where id = 'd7f00000-0000-0000-0000-0000000000f3'
       and valid_to is not null and valid_to <= '2025-10-01T00:00:00Z'
  ) then
    raise exception '[FAIL] estrutura_ocupacao_encerrar nao encerrou a ocupacao vigente';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000015'
       and event_type = 'OCUPACAO_ENCERRADA'
       and actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
  ) then
    raise exception '[FAIL] estrutura_ocupacao_encerrar sem evento OCUPACAO_ENCERRADA com autoria';
  end if;

  select version into v_ver from public.collaborators where id = 'd7c00000-0000-0000-0000-0000000000c3';

  v_ret := public.colaborador_status_alterar(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000016',
    'd7c00000-0000-0000-0000-0000000000c3',
    'inactive',
    '2025-10-01T00:00:00Z',
    'Desligamento apos encerrar a pendencia F5-07',
    'CICLO_ATUAL_E_POSTERIORES',
    null,
    v_ver);

  if not exists (
    select 1 from public.collaborator_status_periods
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c3'
       and status = 'inactive' and valid_from = '2025-10-01T00:00:00Z' and valid_to is null
  ) then
    raise exception '[FAIL] T-12 desligamento permitido apos encerrar a pendencia nao foi aplicado';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000016'
       and event_type = 'STATUS_ALTERADO'
       and after_value is not null
  ) then
    raise exception '[FAIL] desligamento sem evento STATUS_ALTERADO com delta';
  end if;

  raise notice '[PASS] T-12 encerrar a pendencia explicitamente e entao desligar (close+open, evento com delta e autoria)';
end $$;

-- ============================================================================
-- 11) T-13: sucessao avaliativa (RPC existente F3-09/F4-08, com autoria)
-- ============================================================================
do $$
declare
  v_hist int;
begin
  if not exists (select 1 from public.cycle_evaluation_responsibilities
                  where id = 'd7f00000-0000-0000-0000-0000000000c9'
                    and responsible_collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
                    and valid_from = '2024-01-01T00:00:00Z' and valid_to is null) then
    raise exception '[FAIL] pre-condicao da sucessao: responsabilidade original nao esta aberta';
  end if;

  perform public.registrar_sucessao_avaliador(
    array['d7f00000-0000-0000-0000-0000000000c9']::uuid[],
    '2025-06-01T00:00:00Z',
    'Sucessao sintetica F5-07',
    'd7b00000-0000-0000-0000-0000000000a1');

  -- Fecha a responsabilidade original no ponto de sucessao (passado preservado).
  if not exists (
    select 1 from public.cycle_evaluation_responsibilities
     where id = 'd7f00000-0000-0000-0000-0000000000c9'
       and valid_to = '2025-06-01T00:00:00Z'
       and responsible_collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
       and valid_from = '2024-01-01T00:00:00Z'
  ) then
    raise exception '[FAIL] T-13 a responsabilidade original foi reescrita (o passado nao muda)';
  end if;

  -- Abre a nova responsabilidade (titular da posicao superior na data).
  if not exists (
    select 1 from public.cycle_evaluation_responsibilities
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and snapshot_id = 'd7f00000-0000-0000-0000-0000000000a9'
       and position_id = 'd7f00000-0000-0000-0000-0000000000c2'
       and responsible_collaborator_id = 'd7c00000-0000-0000-0000-0000000000c1'
       and valid_from = '2025-06-01T00:00:00Z' and valid_to is null
  ) then
    raise exception '[FAIL] T-13 nova responsabilidade nao foi aberta para o novo titular';
  end if;

  if not exists (
    select 1 from public.evaluation_succession_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and snapshot_id = 'd7f00000-0000-0000-0000-0000000000a9'
       and position_id = 'd7f00000-0000-0000-0000-0000000000c2'
       and previous_responsible_collaborator_id = 'd7c00000-0000-0000-0000-0000000000c6'
       and new_responsible_collaborator_id = 'd7c00000-0000-0000-0000-0000000000c1'
       and succession_date = '2025-06-01T00:00:00Z'
       and author_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
  ) then
    raise exception '[FAIL] T-13 evento de sucessao sem autor/data/valores corretos';
  end if;

  select count(*) into v_hist from public.evaluation_succession_events
   where snapshot_id = 'd7f00000-0000-0000-0000-0000000000a9';
  if v_hist <> 1 then
    raise exception '[FAIL] T-13 sucessao duplicou eventos (%)', v_hist;
  end if;

  raise notice '[PASS] T-13 sucessao: close+open, evento com autoria soberana e passado preservado (sem reescrita)';
end $$;

-- ============================================================================
-- 12) Responsabilidade temporaria: definir/encerrar com eventos
-- ============================================================================
do $$
declare
  v_resp uuid;
begin
  v_resp := public.estrutura_responsabilidade_definir(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000017',
    'd7f00000-0000-0000-0000-0000000000c1',
    'd7c00000-0000-0000-0000-0000000000c2',
    'operational',
    '2025-07-01T00:00:00Z',
    'Responsabilidade temporaria sintetica F5-07');

  if v_resp is null then
    raise exception '[FAIL] estrutura_responsabilidade_definir nao devolveu a responsabilidade';
  end if;

  if not exists (
    select 1 from public.temporary_responsibilities
     where id = v_resp
       and organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and organizational_position_id = 'd7f00000-0000-0000-0000-0000000000c1'
       and substitute_collaborator_id = 'd7c00000-0000-0000-0000-0000000000c2'
       and responsibility_type = 'operational'
       and valid_from = '2025-07-01T00:00:00Z'
       and valid_to > valid_from
  ) then
    raise exception '[FAIL] responsabilidade temporaria nao foi persistida nos moldes do contrato';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000017'
       and event_type = 'RESPONSABILIDADE_INICIADA'
       and payload_hash is not null
  ) then
    raise exception '[FAIL] responsabilidade_definir sem evento RESPONSABILIDADE_INICIADA';
  end if;

  perform public.estrutura_responsabilidade_encerrar(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000018',
    v_resp,
    '2025-08-01T00:00:00Z',
    'Encerramento da responsabilidade sintetica F5-07');

  if not exists (
    select 1 from public.temporary_responsibilities
     where id = v_resp and valid_to is not null and valid_to <= '2025-08-01T00:00:00Z'
  ) then
    raise exception '[FAIL] responsabilidade temporaria nao foi encerrada na vigencia';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000018'
       and event_type = 'RESPONSABILIDADE_ENCERRADA'
       and actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
  ) then
    raise exception '[FAIL] responsabilidade_encerrar sem evento RESPONSABILIDADE_ENCERRADA com autoria';
  end if;

  raise notice '[PASS] responsabilidade temporaria: definir/encerrar por vigencia com eventos iniciada/encerrada e autoria';
end $$;

-- ============================================================================
-- 13) T-14 + T-20: leitura soberana (lista, filtros, ordenacao, sem alocacao)
-- ============================================================================
do $$
declare
  v_n int;
  v_arr text[];
  v_ordenado text[];
begin
  -- Sem filtros: universo do proprio tenant (nenhum colaborador de Beta).
  select count(*) into v_n
    from public.colaborador_visao_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      '2025-06-15T00:00:00Z', '{}'::jsonb);
  if v_n < 9 then
    raise exception '[FAIL] colaborador_visao_listar incompleta (% linhas)', v_n;
  end if;

  select count(*) into v_n
    from public.colaborador_visao_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      '2025-06-15T00:00:00Z', '{}'::jsonb) v
   where v.collaborator_id = 'd7c00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] colaborador_visao_listar vazou colaborador de outro tenant';
  end if;

  -- Ordenacao estavel por full_name, collaborator_id.
  select array_agg(v.full_name) into v_arr
    from public.colaborador_visao_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      '2025-06-15T00:00:00Z', '{}'::jsonb) v;
  select array_agg(v.full_name) into v_ordenado
    from (select * from public.colaborador_visao_listar(
            'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
            '2025-06-15T00:00:00Z', '{}'::jsonb)
           order by full_name, collaborator_id) v;
  if v_arr is distinct from v_ordenado then
    raise exception '[FAIL] colaborador_visao_listar fora da ordenacao estavel (full_name, collaborator_id)';
  end if;

  -- Filtro de status.
  select count(*) into v_n
    from public.colaborador_visao_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      '2025-06-15T00:00:00Z', '{"status":"active"}'::jsonb) v
   where v.status is distinct from 'active';
  if v_n <> 0 then
    raise exception '[FAIL] filtro de status devolveu % linhas fora do status pedido', v_n;
  end if;

  -- Filtro de unidade.
  select count(*) into v_n
    from public.colaborador_visao_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      '2025-06-15T00:00:00Z',
      jsonb_build_object('unit_id', 'd7f00000-0000-0000-0000-0000000000b1')) v
   where v.unit_id is distinct from 'd7f00000-0000-0000-0000-0000000000b1'::uuid;
  if v_n <> 0 then
    raise exception '[FAIL] filtro de unidade devolveu % linhas de outra unidade', v_n;
  end if;

  -- Busca textual (nome/email/matricula).
  select count(*) into v_n
    from public.colaborador_visao_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      '2025-06-15T00:00:00Z', '{"busca":"Cinco"}'::jsonb);
  if v_n <> 1 then
    raise exception '[FAIL] busca textual deveria devolver 1 colaborador (devolveu %)', v_n;
  end if;

  raise notice '[PASS] T-14 colaborador_visao_listar: universo own-tenant, ordenacao estavel e filtros de status/unidade/busca';
end $$;

do $$
declare
  v_uni uuid;
  v_fun text;
  v_status text;
  v_n int;
begin
  -- Colaborador SEM alocacao: estrutura derivada NULL (nao erro) — §14.6.
  select v.unit_id, v.job_role_code, v.status
    into v_uni, v_fun, v_status
    from public.colaborador_visao_obter(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c8', '2025-06-15T00:00:00Z') v;

  if v_status is distinct from 'active' then
    raise exception '[FAIL] colaborador sem alocacao nao foi projetado (%)', coalesce(v_status, 'NULL');
  end if;
  if v_uni is not null or v_fun is not null then
    raise exception '[FAIL] colaborador sem alocacao projetou estrutura (% / %)', v_uni, v_fun;
  end if;

  -- Historico de um colaborador sem mudancas: leitura funciona e devolve vazio
  -- (nada e inventado na leitura — I7).
  select count(*) into v_n
    from public.colaborador_historico_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c9');
  if v_n <> 0 then
    raise exception '[FAIL] I7 violado: leitura de historico inventou % eventos', v_n;
  end if;

  raise notice '[PASS] T-14 colaborador sem alocacao projeta estrutura NULL sem erro e a leitura nao inventa registros (I7)';
end $$;

-- ============================================================================
-- 14) T-23: append-only do historico (superuser e service_role)
-- ============================================================================
do $$
declare
  v_n int;
  v_msg text := null;
  v_state text := null;
begin
  select count(*) into v_n from public.collaborator_events
   where organization_id = 'd7a00000-0000-0000-0000-0000000000a1';
  if v_n = 0 then
    raise exception '[FAIL] trilha vazia: append-only nao pode ser provado';
  end if;

  begin
    update public.collaborator_events set reason = 'adulterado'
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1';
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state = '00000' or v_state is null then
    raise exception '[FAIL] T-23 UPDATE da trilha foi aceito (append-only violado)';
  end if;
  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] UPDATE da trilha falhou por causa inesperada (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if exists (select 1 from public.collaborator_events where reason = 'adulterado') then
    raise exception '[FAIL] T-23 trilha adulterada persistiu';
  end if;

  raise notice '[PASS] T-23 collaborator_events e append-only: UPDATE levanta excecao e a trilha permanece intacta';
end $$;

set role service_role;

do $$
declare
  v_ok boolean := false;
begin
  begin
    update public.collaborator_events set reason = 'adulterado';
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] service_role atualizou a trilha append-only';
  end if;

  v_ok := false;
  begin
    delete from public.collaborator_events;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] service_role excluiu a trilha append-only';
  end if;

  raise notice '[PASS] T-23 service_role sem UPDATE/DELETE na trilha (somente INSERT/SELECT)';
end $$;

reset role;

-- ============================================================================
-- 15) T-20: toda mutacao bem-sucedida tem evento; nenhuma recusada escreve
-- ============================================================================
do $$
declare
  v_aceitas text[] := array[
    'd7100000-0000-0000-0000-000000000001','d7100000-0000-0000-0000-000000000002',
    'd7100000-0000-0000-0000-000000000004','d7100000-0000-0000-0000-000000000006',
    'd7100000-0000-0000-0000-000000000008','d7100000-0000-0000-0000-000000000009',
    'd7100000-0000-0000-0000-000000000012','d7100000-0000-0000-0000-000000000013',
    'd7100000-0000-0000-0000-000000000015','d7100000-0000-0000-0000-000000000016',
    'd7100000-0000-0000-0000-000000000017','d7100000-0000-0000-0000-000000000018'];
  v_recusadas text[] := array[
    'd7100000-0000-0000-0000-000000000003','d7100000-0000-0000-0000-000000000005',
    'd7100000-0000-0000-0000-000000000007','d7100000-0000-0000-0000-000000000010',
    'd7100000-0000-0000-0000-000000000011','d7100000-0000-0000-0000-000000000014'];
  v_op text;
  v_n int;
begin
  foreach v_op in array v_aceitas loop
    select count(*) into v_n
      from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = v_op::uuid
       and actor_user_profile_id is not null
       and actor_membership_id is not null
       and payload_hash is not null
       and reason <> ''
       and effective_date is not null
       and num_nonnulls(collaborator_id, position_id) >= 1;
    if v_n < 1 then
      raise exception '[FAIL] T-20 mutacao aceita sem evento com autoria/escopo/hash (operacao %)', v_op;
    end if;
    select count(distinct e.actor_user_profile_id) into v_n
      from public.collaborator_events e
     where e.organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and e.operation_id = v_op::uuid;
    if v_n <> 1 then
      raise exception '[FAIL] T-20 operacao % com autoria ambigua (%)', v_op, v_n;
    end if;
  end loop;

  foreach v_op in array v_recusadas loop
    select count(*) into v_n
      from public.collaborator_events
     where operation_id = v_op::uuid;
    if v_n <> 0 then
      raise exception '[FAIL] T-20 operacao recusada % gravou evento (%)', v_op, v_n;
    end if;
  end loop;

  raise notice '[PASS] T-20 evento obrigatorio na mesma transacao: 12 mutacoes aceitas com evento/autor/hash e 6 recusadas sem nenhuma escrita';
end $$;

do $$
declare
  v_mutacoes text[] := array[
    'colaborador_criar','colaborador_editar','colaborador_identificador_definir',
    'colaborador_status_alterar','estrutura_ocupacao_definir',
    'estrutura_ocupacao_encerrar','estrutura_reporting_definir',
    'estrutura_reporting_encerrar','estrutura_responsabilidade_definir',
    'estrutura_responsabilidade_encerrar','colaborador_catalogo_bootstrap'];
  v_fn text;
  v_def text;
  v_gravadoras text[];
  v_gravadora text;
  v_delega boolean;
begin
  -- Funcoes que gravam o evento diretamente (mesma transacao da mutacao).
  select array_agg(p.proname) into v_gravadoras
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
     and pg_get_functiondef(p.oid) ~* 'insert[[:space:]]+into[[:space:]]+public\.collaborator_events';

  if v_gravadoras is null then
    raise exception '[FAIL] nenhuma funcao public grava insert em collaborator_events';
  end if;

  foreach v_fn in array v_mutacoes loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;

    if v_def is null then
      raise exception '[FAIL] funcao de mutacao % ausente', v_fn;
    end if;

    if v_def !~* 'insert[[:space:]]+into[[:space:]]+public\.collaborator_events' then
      -- Aceita delegacao explicita a uma funcao que grava o evento na mesma
      -- transacao (a fronteira continua transacional: a RPC e o evento).
      v_delega := false;
      foreach v_gravadora in array v_gravadoras loop
        if v_def ~* ('public\.' || v_gravadora || '\(') then
          v_delega := true;
        end if;
      end loop;
      if not v_delega then
        raise exception '[FAIL] T-20 mutacao % nao grava nem delega a gravacao de collaborator_events', v_fn;
      end if;
    end if;
  end loop;

  raise notice '[PASS] T-20 nenhuma mutacao existe sem escrita (ou delegacao explicita) do evento append-only na mesma transacao';
end $$;

-- ============================================================================
-- 16) D16: o bootstrap de catalogo nunca fabrica estrutura
-- ============================================================================
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'colaborador_catalogo_bootstrap';

  if v_def is null then
    raise exception '[FAIL] colaborador_catalogo_bootstrap ausente';
  end if;

  if v_def ~* 'insert[[:space:]]+into[[:space:]]+public\.organizational_units'
     or v_def ~* 'insert[[:space:]]+into[[:space:]]+public\.organizational_positions'
     or v_def ~* 'insert[[:space:]]+into[[:space:]]+public\.position_reporting_lines' then
    raise exception '[FAIL] D16 violado: colaborador_catalogo_bootstrap cria estrutura organizacional';
  end if;

  if v_def !~* 'job_roles' or v_def !~* 'seniority_levels' then
    raise exception '[FAIL] colaborador_catalogo_bootstrap nao garante job_roles/seniority_levels';
  end if;

  raise notice '[PASS] D16 bootstrap de catalogo: garante job_roles/seniority_levels e NAO cria unidades/posicoes/reporting lines';
end $$;

-- ============================================================================
-- 17) Encerramento de reporting line (T-08 complementar) e visao resultante
-- ============================================================================
do $$
declare
  v_ges uuid;
begin
  perform public.estrutura_reporting_encerrar(
    'd7a00000-0000-0000-0000-0000000000a1',
    'd7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000019',
    'd7f00000-0000-0000-0000-0000000000c5',
    '2025-02-01T00:00:00Z',
    'Encerramento da reporting line sintetica F5-07');

  if not exists (
    select 1 from public.position_reporting_lines
     where id = 'd7f00000-0000-0000-0000-0000000000e2'
       and valid_to is not null and valid_to <= '2025-02-01T00:00:00Z'
  ) then
    raise exception '[FAIL] estrutura_reporting_encerrar nao encerrou a linha vigente';
  end if;

  if not exists (
    select 1 from public.collaborator_events
     where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'd7100000-0000-0000-0000-000000000019'
       and event_type = 'REPORTING_LINE_ENCERRADA'
       and actor_user_profile_id = 'd7b00000-0000-0000-0000-0000000000a1'
  ) then
    raise exception '[FAIL] estrutura_reporting_encerrar sem evento REPORTING_LINE_ENCERRADA com autoria';
  end if;

  -- Depois de 2025-02-01 c5 (ainda na posicao p5) nao tem gestor derivado.
  select v.manager_collaborator_id into v_ges
    from public.colaborador_visao_obter(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000c5', '2025-02-15T00:00:00Z') v;
  if v_ges is not null then
    raise exception '[FAIL] gestor derivado permanece apos encerrar a reporting line (%)', v_ges;
  end if;

  raise notice '[PASS] T-08 estrutura_reporting_encerrar: vigencia encerrada, evento com autoria e gestor derivado deixando de resolver na data';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-07: todas as verificacoes passaram (schema, constraints, RLS/grants, funcoes, CRUD autorizado/negado, cross-tenant, ciclo de status, inativacao com pendencia, sucessao, historico temporal, append-only, D16 e autorizacao sem cargo).';
end $$;
