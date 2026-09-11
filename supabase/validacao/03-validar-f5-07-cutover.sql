-- ============================================================================
-- F5-07: validação de cutover, anti-IDOR, concorrência e idempotência
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de 01-cenario-f5-07.sql e 02-validar-f5-07.sql, como
-- superuser local (`psql -U postgres`), com ON_ERROR_STOP ativo.
--
-- Cobre a matriz do desenho técnico (docs/F5-07-desenho-tecnico.md §16.2):
--   T-03 (cross-tenant por UUID), T-04 (IDOR por UUID), T-05 (colaborador
--   inexistente), T-06 (membership revogada), T-15 (duas alterações
--   simultâneas), T-16 (revogação entre leitura e mutação), T-17 (matrícula de
--   outro tenant), T-18 (acesso direto de authenticated), T-24 (idempotência por
--   operation_id) — além do contrato de superfície das funções
--   (SECURITY INVOKER + EXECUTE somente service_role via pg_proc /
--   pg_get_function_identity_arguments / has_function_privilege).
--
-- Este arquivo RESTAURA todo estado que altera (membership, assignment,
-- catálogo), para que 01 → 02 → 03 sejam reaplicáveis.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Superfície das funções F5-07 (pg_proc / identity args / privilégio)
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
  v_leitura text[] := array[
    'colaborador_ator_valido','colaborador_visao_listar','colaborador_visao_obter',
    'colaborador_resolver_matricula','colaborador_historico_listar'];
  v_fn text;
  v_n int;
  v_definer text;
begin
  select count(*), string_agg(p.proname, ', ' order by p.proname)
    into v_n, v_definer
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = any(v_funcs) and p.prosecdef;

  if v_n <> 0 then
    raise exception '[FAIL] funcao F5-07 SECURITY DEFINER (proibido): %', v_definer;
  end if;

  foreach v_fn in array v_funcs loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn and not p.prosecdef;
    if v_n <> 1 then
      raise exception '[FAIL] funcao % nao e SECURITY INVOKER (assinaturas=%)', v_fn, v_n;
    end if;
  end loop;

  -- Leituras/helper sao STABLE (nunca escrevem); as mutacoes ficam VOLATILE.
  foreach v_fn in array v_leitura loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn and p.provolatile = 's';
    if v_n <> 1 then
      raise exception '[FAIL] funcao de leitura/helper % deveria ser STABLE', v_fn;
    end if;
  end loop;

  raise notice '[PASS] as 16 funcoes F5-07 sao SECURITY INVOKER (nenhum DEFINER novo) e as 5 leituras/helper sao STABLE';
end $$;

do $$
declare
  v_esp record;
  v_args text;
begin
  for v_esp in
    select * from (values
      ('colaborador_ator_valido','p_actor_user_profile_id uuid, p_organization_id uuid'),
      ('colaborador_visao_listar','p_organization_id uuid, p_actor_user_profile_id uuid, p_data timestamptz, p_filtros jsonb'),
      ('colaborador_visao_obter','p_organization_id uuid, p_actor_user_profile_id uuid, p_collaborator_id uuid, p_data timestamptz'),
      ('colaborador_resolver_matricula','p_organization_id uuid, p_actor_user_profile_id uuid, p_matricula text'),
      ('colaborador_historico_listar','p_organization_id uuid, p_actor_user_profile_id uuid, p_collaborator_id uuid'),
      ('colaborador_criar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_full_name text, p_email text, p_matricula text, p_admission_date date, p_status_inicial text'),
      ('colaborador_editar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_full_name text, p_email text, p_admission_date date, p_expected_version integer'),
      ('colaborador_identificador_definir','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_nova_matricula text, p_vigencia timestamptz, p_motivo text, p_expected_version integer'),
      ('colaborador_status_alterar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_novo_status text, p_vigencia timestamptz, p_motivo text, p_cycle_scope text, p_reference_cycle_id uuid, p_expected_version integer'),
      ('estrutura_ocupacao_definir','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_position_id uuid, p_vigencia timestamptz, p_motivo text, p_cycle_scope text, p_reference_cycle_id uuid'),
      ('estrutura_ocupacao_encerrar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_vigencia timestamptz, p_motivo text'),
      ('estrutura_reporting_definir','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_subordinate_position_id uuid, p_manager_position_id uuid, p_vigencia timestamptz, p_motivo text'),
      ('estrutura_reporting_encerrar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_subordinate_position_id uuid, p_vigencia timestamptz, p_motivo text'),
      ('estrutura_responsabilidade_definir','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_position_id uuid, p_substitute_collaborator_id uuid, p_responsibility_type text, p_vigencia timestamptz, p_motivo text'),
      ('estrutura_responsabilidade_encerrar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_responsibility_id uuid, p_vigencia timestamptz, p_motivo text'),
      ('colaborador_catalogo_bootstrap','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_catalogo jsonb')
    ) as t(fn, args)
  loop
    select replace(replace(lower(pg_get_function_identity_arguments(p.oid)), ' ', ''), 'timestampwithtimezone', 'timestamptz')
      into v_args
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_esp.fn;

    if v_args is null then
      raise exception '[FAIL] funcao public.% ausente', v_esp.fn;
    end if;
    if v_args is distinct from replace(lower(v_esp.args), ' ', '') then
      raise exception '[FAIL] assinatura de public.% divergente da espinha: % (esperado %)',
        v_esp.fn, v_args, v_esp.args;
    end if;
  end loop;

  raise notice '[PASS] as 16 assinaturas F5-07 conferem com a espinha (pg_get_function_identity_arguments, na ordem congelada)';
end $$;

do $$
declare
  v_esp record;
  v_oid oid;
begin
  for v_esp in
    select * from (values
      ('colaborador_ator_valido','p_actor_user_profile_id uuid, p_organization_id uuid'),
      ('colaborador_visao_listar','p_organization_id uuid, p_actor_user_profile_id uuid, p_data timestamptz, p_filtros jsonb'),
      ('colaborador_visao_obter','p_organization_id uuid, p_actor_user_profile_id uuid, p_collaborator_id uuid, p_data timestamptz'),
      ('colaborador_resolver_matricula','p_organization_id uuid, p_actor_user_profile_id uuid, p_matricula text'),
      ('colaborador_historico_listar','p_organization_id uuid, p_actor_user_profile_id uuid, p_collaborator_id uuid'),
      ('colaborador_criar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_full_name text, p_email text, p_matricula text, p_admission_date date, p_status_inicial text'),
      ('colaborador_editar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_full_name text, p_email text, p_admission_date date, p_expected_version integer'),
      ('colaborador_identificador_definir','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_nova_matricula text, p_vigencia timestamptz, p_motivo text, p_expected_version integer'),
      ('colaborador_status_alterar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_novo_status text, p_vigencia timestamptz, p_motivo text, p_cycle_scope text, p_reference_cycle_id uuid, p_expected_version integer'),
      ('estrutura_ocupacao_definir','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_position_id uuid, p_vigencia timestamptz, p_motivo text, p_cycle_scope text, p_reference_cycle_id uuid'),
      ('estrutura_ocupacao_encerrar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_vigencia timestamptz, p_motivo text'),
      ('estrutura_reporting_definir','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_subordinate_position_id uuid, p_manager_position_id uuid, p_vigencia timestamptz, p_motivo text'),
      ('estrutura_reporting_encerrar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_subordinate_position_id uuid, p_vigencia timestamptz, p_motivo text'),
      ('estrutura_responsabilidade_definir','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_position_id uuid, p_substitute_collaborator_id uuid, p_responsibility_type text, p_vigencia timestamptz, p_motivo text'),
      ('estrutura_responsabilidade_encerrar','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_responsibility_id uuid, p_vigencia timestamptz, p_motivo text'),
      ('colaborador_catalogo_bootstrap','p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_catalogo jsonb')
    ) as t(fn, args)
  loop
    select p.oid into v_oid
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_esp.fn;

    if v_oid is null then
      raise exception '[FAIL] funcao public.% ausente', v_esp.fn;
    end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') then
      raise exception '[FAIL] anon executa public.%', v_esp.fn;
    end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') then
      raise exception '[FAIL] authenticated executa public.% (superficie do cliente deve ser fechada)', v_esp.fn;
    end if;
    if not has_function_privilege('service_role', v_oid, 'EXECUTE') then
      raise exception '[FAIL] service_role NAO executa public.%', v_esp.fn;
    end if;
  end loop;

  raise notice '[PASS] has_function_privilege: EXECUTE somente service_role nas 16 funcoes (anon/authenticated negados)';
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
  v_n int;
  v_lista text;
begin
  select count(*), string_agg(distinct p.proname, ', ' order by p.proname)
    into v_n, v_lista
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
   where n.nspname = 'public' and p.proname = any(v_funcs)
     and a.privilege_type = 'EXECUTE'
     and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole);
  if v_n <> 0 then
    raise exception '[FAIL] ACL com EXECUTE para public/anon/authenticated: %', v_lista;
  end if;

  -- O helper tambem e STABLE e devolve boolean (fronteira de ator).
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'colaborador_ator_valido'
     and p.provolatile = 's'
     and pg_get_function_result(p.oid) = 'boolean';
  if v_n <> 1 then
    raise exception '[FAIL] colaborador_ator_valido deveria ser STABLE e devolver boolean';
  end if;

  raise notice '[PASS] ACL efetiva: nenhuma concessao a public/anon/authenticated e o helper de ator e STABLE boolean';
end $$;

-- ============================================================================
-- 2) T-18: nenhuma superficie direta de authenticated no dominio F5-07
-- ============================================================================
select set_config('request.jwt.claim.sub', 'd7b00000-0000-0000-0000-0000000000a2', false);
set role authenticated;

do $$
declare
  v_n int;
  v_ok boolean;
begin
  -- Leitura de outro tenant por UUID: impossivel (RLS own-tenant).
  select count(*) into v_n from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] T-18 authenticated leu colaborador de outro tenant por UUID';
  end if;

  select count(*) into v_n from public.occupations
   where organization_id = 'd7a00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] T-18 authenticated leu occupations de outro tenant';
  end if;

  -- A trilha append-only nao aceita leitura de outro tenant. A leitura direta de
  -- authenticated pode estar revogada (espinha §1.2) ou concedida com policy
  -- own-tenant (desenho §10.3): nos dois casos nenhum dado alheio e visivel.
  v_n := -1;
  begin
    execute 'select count(*) from public.collaborator_events where organization_id = ''d7a00000-0000-0000-0000-0000000000b1'''
      into v_n;
  exception when insufficient_privilege then v_n := -1;
  end;
  if v_n > 0 then
    raise exception '[FAIL] T-18 authenticated leu eventos de outro tenant (%)', v_n;
  end if;

  -- RPC de leitura (EXECUTE service_role): negada para o cliente.
  v_ok := false;
  begin
    perform public.colaborador_visao_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a2',
      now(), '{}'::jsonb);
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] T-18 authenticated executou colaborador_visao_listar';
  end if;

  v_ok := false;
  begin
    perform public.colaborador_resolver_matricula(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a2',
      'F507-0001');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] T-18 authenticated executou colaborador_resolver_matricula';
  end if;

  v_ok := false;
  begin
    perform public.colaborador_criar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a2',
      'd7100000-0000-0000-0000-0000000000f1','Intruso Direto','intruso.direto.f5-07@example.invalid',
      'F507-0F01', null, 'active');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] T-18 authenticated executou colaborador_criar (mutacao direta pelo cliente)';
  end if;

  v_ok := false;
  begin
    perform public.estrutura_ocupacao_definir(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a2',
      'd7100000-0000-0000-0000-0000000000f2','d7c00000-0000-0000-0000-0000000000c9',
      'd7f00000-0000-0000-0000-0000000000c6','2025-08-01T00:00:00Z',
      'Intrusao direta F5-07','CICLO_ATUAL_E_POSTERIORES', null);
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] T-18 authenticated executou estrutura_ocupacao_definir';
  end if;

  raise notice '[PASS] T-18 authenticated: RLS own-tenant em execucao e EXECUTE revogado nas RPC de leitura e de mutacao';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.occupations
      (organization_id, collaborator_id, organizational_position_id, reason, valid_from)
    values ('d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c9',
            'd7f00000-0000-0000-0000-0000000000c6','intrusao direta f5-07', now());
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated inseriu occupation (DML estrutural direto)';
  end if;

  v_ok := false;
  begin
    insert into public.position_reporting_lines
      (organization_id, subordinate_position_id, manager_position_id, reason, valid_from)
    values ('d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000c6',
            'd7f00000-0000-0000-0000-0000000000c1','intrusao direta f5-07', now());
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated inseriu reporting line (DML estrutural direto)';
  end if;

  v_ok := false;
  begin
    update public.occupations set reason = 'adulterado';
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated atualizou occupations';
  end if;

  v_ok := false;
  begin
    delete from public.position_reporting_lines;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated excluiu reporting lines';
  end if;

  v_ok := false;
  begin
    insert into public.temporary_responsibilities
      (organization_id, organizational_position_id, substitute_collaborator_id,
       responsibility_type, reason, valid_from, valid_to)
    values ('d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000c1',
            'd7c00000-0000-0000-0000-0000000000c9','operational','intrusao direta f5-07',
            now(), now() + interval '1 day');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated inseriu temporary responsibility';
  end if;

  raise notice '[PASS] T-18 authenticated sem DML em occupations/reporting lines/responsabilidades (mutacao somente por RPC transacional)';
end $$;

reset role;

-- ============================================================================
-- 3) T-04/T-05: colaborador inexistente e leitura fail-closed
-- ============================================================================
do $$
declare
  v_msg text := null;
  v_state text := null;
  v_ver int;
  v_inexistente uuid := 'd7c00000-0000-0000-0000-0000000000ff';
begin
  select version into v_ver from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000c9';

  begin
    perform public.colaborador_editar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000020', v_inexistente,
      'Colaborador Fantasma F5-07','fantasma.f5-07@example.invalid', null, v_ver);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_editar (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null then
    raise exception '[FAIL] T-05 colaborador inexistente foi aceito em colaborador_editar';
  end if;
  if v_msg not like 'F5_07_%' then
    raise exception '[FAIL] T-05 recusa de colaborador inexistente sem prefixo padronizado (msg=%)', v_msg;
  end if;
  if exists (select 1 from public.collaborators where id = v_inexistente) then
    raise exception '[FAIL] T-05 mutacao criou o colaborador inexistente';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000020') then
    raise exception '[FAIL] T-05 mutacao recusada gravou evento';
  end if;

  raise notice '[PASS] T-05 colaborador inexistente: recusa F5_07_* e nenhuma escrita';
end $$;

do $$
declare
  v_n int;
begin
  -- T-04: leitura de UUID inexistente e de outro tenant => VAZIO (fail-closed,
  -- sem distinguir existencia de acesso).
  select count(*) into v_n
    from public.colaborador_visao_obter(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000ff', now());
  if v_n <> 0 then
    raise exception '[FAIL] T-04 visao de colaborador inexistente devolveu % linhas', v_n;
  end if;

  select count(*) into v_n
    from public.colaborador_visao_obter(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000b1', now());
  if v_n <> 0 then
    raise exception '[FAIL] T-04 IDOR: visao devolveu colaborador de outro tenant (%)', v_n;
  end if;

  select count(*) into v_n
    from public.colaborador_historico_listar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7c00000-0000-0000-0000-0000000000b1');
  if v_n <> 0 then
    raise exception '[FAIL] T-04 IDOR: historico devolveu eventos de outro tenant (%)', v_n;
  end if;

  raise notice '[PASS] T-04 leitura fail-closed: UUID inexistente e UUID de outro tenant devolvem vazio (sem vazar existencia)';
end $$;

-- ============================================================================
-- 4) T-03: cross-tenant por UUID (nada escrito)
-- ============================================================================
do $$
declare
  v_msg text := null;
  v_state text := null;
  v_ver int;
begin
  -- Ator de Alfa tentando mutar colaborador de Beta (IDOR por UUID).
  select version into v_ver from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000b1';

  begin
    perform public.colaborador_editar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000021','d7c00000-0000-0000-0000-0000000000b1',
      'Colaborador Beta Invadido','beta.invadido.f5-07@example.invalid', null, v_ver);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_editar (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null or v_msg not like 'F5_07_%' then
    raise exception '[FAIL] T-03 cross-tenant deveria ser recusado com F5_07_* (msg=%)', v_msg;
  end if;
  if exists (select 1 from public.collaborators
              where id = 'd7c00000-0000-0000-0000-0000000000b1'
                and full_name = 'Colaborador Beta Invadido') then
    raise exception '[FAIL] T-03 cross-tenant escreveu o colaborador de outro tenant';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000021') then
    raise exception '[FAIL] T-03 cross-tenant gravou evento';
  end if;
  -- O tenant do recurso nao vaza: a mensagem nao cita a organizacao alvo.
  if position('Beta' in v_msg) > 0 then
    raise exception '[FAIL] T-03 recusa cross-tenant vazou o tenant do recurso (msg=%)', v_msg;
  end if;

  raise notice '[PASS] T-03 cross-tenant por UUID: recusa F5_07_*, nada escrito e nenhum vazamento do tenant do recurso';
end $$;

do $$
declare
  v_msg text := null;
  v_state text := null;
begin
  -- Ator de Beta tentando operar recurso de Alfa (tenant derivado do recurso).
  begin
    perform public.colaborador_status_alterar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a5',
      'd7100000-0000-0000-0000-000000000022','d7c00000-0000-0000-0000-0000000000c2',
      'leave','2025-11-01T00:00:00Z','Ator de outro tenant F5-07',
      'CICLO_ATUAL_E_POSTERIORES', null, 0);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_status_alterar (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null or v_msg not like 'F5_07_%' then
    raise exception '[FAIL] T-03 ator de outro tenant deveria ser recusado com F5_07_* (msg=%)', v_msg;
  end if;
  if exists (select 1 from public.collaborator_status_periods
              where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c2'
                and status = 'leave') then
    raise exception '[FAIL] T-03 ator de outro tenant alterou o status do colaborador';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000022') then
    raise exception '[FAIL] T-03 ator de outro tenant gravou evento';
  end if;

  raise notice '[PASS] T-03 ator de outro tenant: membership revalidada server-side, recusa F5_07_* e nenhuma escrita';
end $$;

do $$
declare
  v_msg text := null;
  v_state text := null;
begin
  -- Ocupacao estrutural cross-tenant: colaborador de Beta com posicao de Beta,
  -- ator de Alfa => o tenant do RECURSO e derivado do banco e recusado.
  begin
    perform public.estrutura_ocupacao_definir(
      'd7a00000-0000-0000-0000-0000000000b1','d7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000023','d7c00000-0000-0000-0000-0000000000b1',
      'd7f00000-0000-0000-0000-0000000000d3','2025-12-01T00:00:00Z',
      'Ocupacao cross-tenant F5-07','CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a estrutura_ocupacao_definir (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null or v_msg not like 'F5_07_%' then
    raise exception '[FAIL] T-03 mutacao estrutural cross-tenant deveria ser recusada com F5_07_* (msg=%)', v_msg;
  end if;
  if (select count(*) from public.occupations
       where collaborator_id = 'd7c00000-0000-0000-0000-0000000000b1'
         and organizational_position_id = 'd7f00000-0000-0000-0000-0000000000d3'
         and valid_to is null) <> 1 then
    raise exception '[FAIL] T-03 mutacao estrutural cross-tenant alterou as ocupacoes de Beta';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000023') then
    raise exception '[FAIL] T-03 mutacao estrutural cross-tenant gravou evento';
  end if;

  raise notice '[PASS] T-03 mutacao estrutural: tenant derivado do recurso e ator cross-tenant recusado (fail-closed, nada escrito)';
end $$;

-- ============================================================================
-- 5) T-17: matricula como INTENCAO (outro tenant, ambigua, inexistente)
-- ============================================================================
do $$
declare
  v_res uuid;
  v_msg text := null;
  v_state text := null;
begin
  -- Matricula de outro tenant: nunca devolve o UUID de Beta.
  begin
    v_res := public.colaborador_resolver_matricula(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'F507-9001');
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_resolver_matricula (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null and v_res is not null then
    raise exception '[FAIL] T-17 matricula de outro tenant resolveu o colaborador % de Beta', v_res;
  end if;
  if v_res = 'd7c00000-0000-0000-0000-0000000000b1'::uuid then
    raise exception '[FAIL] T-17 matricula de outro tenant devolveu o UUID soberano de Beta';
  end if;

  -- Matricula inexistente: NULL (nunca escolhe arbitrariamente).
  v_res := public.colaborador_resolver_matricula(
    'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
    'F507-NAO-EXISTE');
  if v_res is not null then
    raise exception '[FAIL] T-17 matricula inexistente resolveu %', v_res;
  end if;

  raise notice '[PASS] T-17 matricula de outro tenant e matricula inexistente: resolucao fail-closed (NULL/recusa), nunca UUID alheio';
end $$;

do $$
declare
  v_res uuid;
  v_msg text := null;
begin
  -- Ambiguidade REAL: duas linhas ABERTAS com a mesma matricula na organizacao.
  -- A unicidade por organizacao e suspensa e o identificador ANTERIOR de c9 e
  -- encerrado apenas durante o teste (a exclusion por colaborador continua
  -- valendo); tudo e restaurado no fim.
  alter table public.collaborator_identifiers
    drop constraint uq_collaborator_identifiers_organization_code;

  update public.collaborator_identifiers
     set valid_to = '2024-06-01T00:00:00Z'
   where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c9'
     and business_code = 'F507-0009'
     and valid_to is null;

  insert into public.collaborator_identifiers
    (collaborator_id, organization_id, business_code, valid_from)
  values ('d7c00000-0000-0000-0000-0000000000c9','d7a00000-0000-0000-0000-0000000000a1',
          'F507-0008','2024-06-01T00:00:00Z');

  begin
    v_res := public.colaborador_resolver_matricula(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'F507-0008');

    delete from public.collaborator_identifiers
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c9'
       and business_code = 'F507-0008';

    update public.collaborator_identifiers
       set valid_to = null
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c9'
       and business_code = 'F507-0009';

    alter table public.collaborator_identifiers
      add constraint uq_collaborator_identifiers_organization_code
      unique (organization_id, business_code);

    if v_res is not null then
      raise exception '[FAIL] T-17 matricula AMBIGUA resolveu arbitrariamente o colaborador %', v_res;
    end if;
  exception when others then
    -- Restaura a barreira de banco antes de propagar a falha.
    v_msg := SQLERRM;
    delete from public.collaborator_identifiers
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c9'
       and business_code = 'F507-0008';
    update public.collaborator_identifiers
       set valid_to = null
     where collaborator_id = 'd7c00000-0000-0000-0000-0000000000c9'
       and business_code = 'F507-0009';
    if not exists (
      select 1 from pg_constraint
       where conrelid = 'public.collaborator_identifiers'::regclass
         and conname = 'uq_collaborator_identifiers_organization_code'
    ) then
      alter table public.collaborator_identifiers
        add constraint uq_collaborator_identifiers_organization_code
        unique (organization_id, business_code);
    end if;
    raise exception '%', v_msg;
  end;

  raise notice '[PASS] T-17 matricula ambigua (2 linhas abertas na organizacao) recusada com NULL — nunca escolhe arbitrariamente';
end $$;

-- ============================================================================
-- 6) T-15: duas alteracoes simultaneas (versao otimista + barreira temporal)
-- ============================================================================
do $$
declare
  v_ver_lida int;
  v_ret int;
  v_msg text := null;
  v_state text := null;
  v_ev int;
begin
  -- Duas requisicoes concorrentes leram a MESMA versao (V).
  select version into v_ver_lida from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000c9';

  v_ret := public.colaborador_editar(
    'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000030','d7c00000-0000-0000-0000-0000000000c9',
    'Colaborador Sintetico F5-07 Nove A','colaborador.f5-07.9a@example.invalid', null, v_ver_lida);

  if v_ret <= v_ver_lida then
    raise exception '[FAIL] T-15 primeira alteracao nao incrementou a versao (% -> %)', v_ver_lida, v_ret;
  end if;

  -- A segunda requisicao (mesma versao lida) precisa falhar: nada de
  -- last-write-wins nem de duas escritas concorrentes.
  begin
    perform public.colaborador_editar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000031','d7c00000-0000-0000-0000-0000000000c9',
      'Colaborador Sintetico F5-07 Nove B','colaborador.f5-07.9b@example.invalid', null, v_ver_lida);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_editar (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null or v_msg not like 'F5_07_CONFLICT%' then
    raise exception '[FAIL] T-15 segunda alteracao simultanea deveria falhar com F5_07_CONFLICT (msg=%)', v_msg;
  end if;

  if exists (select 1 from public.collaborators
              where id = 'd7c00000-0000-0000-0000-0000000000c9'
                and full_name = 'Colaborador Sintetico F5-07 Nove B') then
    raise exception '[FAIL] T-15 perda silenciosa: a segunda alteracao sobrescreveu a primeira';
  end if;

  select count(*) into v_ev from public.collaborator_events
   where operation_id in ('d7100000-0000-0000-0000-000000000030'::uuid,
                          'd7100000-0000-0000-0000-000000000031'::uuid);
  if v_ev <> 1 then
    raise exception '[FAIL] T-15 deveria haver exatamente 1 evento para as duas requisicoes (%)', v_ev;
  end if;

  raise notice '[PASS] T-15 concorrencia: duas alteracoes com a mesma expected_version — a segunda falha por versao e apenas um efeito/evento persiste';
end $$;

do $$
declare
  v_ok boolean := false;
  v_msg text := null;
  v_state text := null;
begin
  -- Barreira TEMPORAL no banco (ultima linha de defesa): sobreposicao de
  -- ocupacao na mesma posicao e impossivel, mesmo por escrita direta.
  begin
    insert into public.occupations
      (organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to)
    values ('d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c4',
            'd7f00000-0000-0000-0000-0000000000c2','sobreposicao sintetica f5-07',
            '2025-01-01T00:00:00Z', null);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
    if v_state = '23P01' then v_ok := true; end if;
  end;

  if not v_ok then
    raise exception '[FAIL] exclusao de sobreposicao de occupations nao barrou a segunda vigencia (sqlstate=% msg=%)',
      v_state, v_msg;
  end if;

  if not exists (select 1 from public.occupations
                  where id = 'd7f00000-0000-0000-0000-0000000000f2'
                    and collaborator_id = 'd7c00000-0000-0000-0000-0000000000c2'
                    and valid_to is null) then
    raise exception '[FAIL] a ocupacao vigente original foi perdida na tentativa concorrente';
  end if;

  raise notice '[PASS] T-15 barreira temporal: exclusion de vigencia (23P01) impede duas ocupacoes vigentes na mesma posicao';
end $$;

-- ============================================================================
-- 7) T-24: idempotencia por operation_id
-- ============================================================================
do $$
declare
  v_a uuid;
  v_b uuid;
  v_n int;
begin
  v_a := public.colaborador_criar(
    'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000040','Colaborador Idempotente F5-07',
    'idempotente.f5-07@example.invalid','F507-0300', date '2025-01-01', 'active');

  -- Retry de rede: MESMO operation_id e MESMO payload.
  v_b := public.colaborador_criar(
    'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000040','Colaborador Idempotente F5-07',
    'idempotente.f5-07@example.invalid','F507-0300', date '2025-01-01', 'active');

  if v_a is null or v_b is distinct from v_a then
    raise exception '[FAIL] T-24 retry idempotente devolveu resultado diferente (% / %)',
      coalesce(v_a::text, 'NULL'), coalesce(v_b::text, 'NULL');
  end if;

  select count(*) into v_n from public.collaborators where id = v_a;
  if v_n <> 1 then
    raise exception '[FAIL] T-24 retry duplicou o colaborador (%)', v_n;
  end if;

  select count(*) into v_n from public.collaborator_identifiers
   where collaborator_id = v_a and business_code = 'F507-0300';
  if v_n <> 1 then
    raise exception '[FAIL] T-24 retry duplicou o identificador (%)', v_n;
  end if;

  select count(*) into v_n from public.collaborator_status_periods where collaborator_id = v_a;
  if v_n <> 1 then
    raise exception '[FAIL] T-24 retry duplicou o periodo de status (%)', v_n;
  end if;

  select count(*) into v_n from public.collaborator_events
   where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
     and operation_id = 'd7100000-0000-0000-0000-000000000040';
  if v_n <> 1 then
    raise exception '[FAIL] T-24 retry duplicou o evento (%)', v_n;
  end if;

  raise notice '[PASS] T-24 idempotencia: mesmo operation_id + mesmo payload devolve o MESMO resultado sem duplicar evento/mutacao';
end $$;

do $$
declare
  v_msg text := null;
  v_state text := null;
  v_n int;
begin
  -- Mesmo operation_id com payload DIFERENTE: nunca adivinha a intencao.
  begin
    perform public.colaborador_criar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000040','Colaborador Idempotente F5-07 DIVERGENTE',
      'idempotente.divergente.f5-07@example.invalid','F507-0301', date '2025-01-01', 'active');
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_criar (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null or v_msg not like 'F5_07_CONFLICT%' then
    raise exception '[FAIL] T-24 operation_id repetido com payload diferente deveria falhar com F5_07_CONFLICT (msg=%)', v_msg;
  end if;

  select count(*) into v_n from public.collaborators
   where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
     and email = 'idempotente.divergente.f5-07@example.invalid';
  if v_n <> 0 then
    raise exception '[FAIL] T-24 payload divergente criou colaborador';
  end if;

  select count(*) into v_n from public.collaborator_identifiers
   where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
     and business_code = 'F507-0301';
  if v_n <> 0 then
    raise exception '[FAIL] T-24 payload divergente criou identificador';
  end if;

  select count(*) into v_n from public.collaborator_events
   where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
     and operation_id = 'd7100000-0000-0000-0000-000000000040';
  if v_n <> 1 then
    raise exception '[FAIL] T-24 payload divergente duplicou/reescreveu o evento (%)', v_n;
  end if;

  raise notice '[PASS] T-24 operation_id repetido com payload diferente: F5_07_CONFLICT sem nenhum efeito adicional';
end $$;

do $$
declare
  v_ver int;
  v_a int;
  v_b int;
  v_n int;
  v_msg text := null;
  v_state text := null;
begin
  select version into v_ver from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000c1';

  v_a := public.colaborador_editar(
    'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
    'd7100000-0000-0000-0000-000000000041','d7c00000-0000-0000-0000-0000000000c1',
    'Colaborador Sintetico F5-07 Um Editado','colaborador.f5-07.1.editado@example.invalid',
    date '2024-01-01', v_ver);

  -- Retry do MESMO pedido (idempotencia tambem nas edicoes com versao).
  begin
    v_b := public.colaborador_editar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000041','d7c00000-0000-0000-0000-0000000000c1',
      'Colaborador Sintetico F5-07 Um Editado','colaborador.f5-07.1.editado@example.invalid',
      date '2024-01-01', v_ver);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_editar (sqlstate=% msg=%)', v_state, v_msg;
  end if;

  -- Retry idempotente (espinha §1.5/D13): devolve o MESMO resultado; se a
  -- implementacao recusar o retry, ela precisa ao menos falhar fechado com
  -- prefixo padronizado. Em NENHUM caso a mutacao e reaplicada.
  if v_msg is null then
    if v_a is null or v_b is distinct from v_a then
      raise exception '[FAIL] T-24 retry de edicao devolveu resultado diferente (% / %)',
        coalesce(v_a::text, 'NULL'), coalesce(v_b::text, 'NULL');
    end if;
  elsif v_msg not like 'F5_07_%' then
    raise exception '[FAIL] T-24 retry de edicao falhou fora do prefixo padronizado (msg=%)', v_msg;
  end if;

  select count(*) into v_n from public.collaborator_events
   where organization_id = 'd7a00000-0000-0000-0000-0000000000a1'
     and operation_id = 'd7100000-0000-0000-0000-000000000041'
     and event_type = 'DADOS_PESSOAIS_ALTERADOS';
  if v_n <> 1 then
    raise exception '[FAIL] T-24 retry de edicao duplicou o evento (%)', v_n;
  end if;

  select version into v_n from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000c1';
  if v_n <> v_a then
    raise exception '[FAIL] T-24 retry de edicao reaplicou a mutacao (% x %)', v_n, v_a;
  end if;

  raise notice '[PASS] T-24 idempotencia em edicao com expected_version: retry nao duplica evento nem reaplica a mutacao (versao estavel)';
end $$;

-- ============================================================================
-- 8) T-06/T-16: revogacao entre a leitura e a mutacao (TOCTOU)
-- ============================================================================
do $$
declare
  v_ver int;
  v_msg text := null;
  v_state text := null;
  v_antes boolean;
begin
  -- (1) Leitura: o ator e valido e a operacao seria autorizada.
  v_antes := public.colaborador_ator_valido(
    'd7b00000-0000-0000-0000-0000000000a7','d7a00000-0000-0000-0000-0000000000a1');
  if v_antes is not true then
    raise exception '[FAIL] T-06 pre-condicao: ator revogavel deveria ser valido antes da revogacao';
  end if;

  select version into v_ver from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000c6';

  -- (2) Revogacao da membership (outra sessao/administrador).
  update public.user_organization_memberships set status = 'disabled'
   where id = 'd7d00000-0000-0000-0000-0000000000a7';

  -- (3) A mutacao seguinte e negada (revogacao vale na operacao seguinte).
  begin
    perform public.colaborador_editar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a7',
      'd7100000-0000-0000-0000-000000000050','d7c00000-0000-0000-0000-0000000000c6',
      'Colaborador Revogado F5-07','colaborador.revogado.f5-07@example.invalid', null, v_ver);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_editar (sqlstate=% msg=%)', v_state, v_msg;
  end if;

  if public.colaborador_ator_valido(
       'd7b00000-0000-0000-0000-0000000000a7','d7a00000-0000-0000-0000-0000000000a1') then
    raise exception '[FAIL] T-06 membership revogada continuou valida no helper de ator';
  end if;
  if v_msg is null or v_msg not like 'F5_07_%' then
    raise exception '[FAIL] T-06 mutacao apos revogacao deveria ser recusada com F5_07_* (msg=%)', v_msg;
  end if;
  if exists (select 1 from public.collaborators
              where id = 'd7c00000-0000-0000-0000-0000000000c6'
                and full_name = 'Colaborador Revogado F5-07') then
    raise exception '[FAIL] T-06 mutacao apos revogacao escreveu o cadastro';
  end if;
  if exists (select 1 from public.collaborator_events
              where operation_id = 'd7100000-0000-0000-0000-000000000050') then
    raise exception '[FAIL] T-06 mutacao apos revogacao gravou evento';
  end if;

  -- Restaura o cenario.
  update public.user_organization_memberships set status = 'active'
   where id = 'd7d00000-0000-0000-0000-0000000000a7';

  raise notice '[PASS] T-06 membership revogada entre leitura e mutacao: helper de ator invalida, recusa F5_07_* e nenhuma escrita';
end $$;

do $$
declare
  v_n int;
begin
  -- (1) Leitura: o ator funcional possui collaborator.edit.
  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1') x
   where x.capability_code = 'collaborator.edit';
  if v_n < 1 then
    raise exception '[FAIL] T-16 pre-condicao: ator funcional sem collaborator.edit na leitura';
  end if;

  -- (2) Revogacao da ATRIBUICAO entre a leitura e a mutacao.
  update public.membership_access_role_assignments set status = 'revoked'
   where id = 'd7000000-0000-0000-0000-0000000000a1';

  -- (3) A decisao NAO pode ser reaproveitada: a capability desaparece.
  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1') x
   where x.capability_code = 'collaborator.edit';
  if v_n <> 0 then
    raise exception '[FAIL] T-16 capability sobreviveu a revogacao da atribuicao (cache de decisao)';
  end if;

  -- A membership continua ativa: a revogacao atua na CAPABILITY por operacao.
  if not public.colaborador_ator_valido(
       'd7b00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1') then
    raise exception '[FAIL] T-16 revogacao da atribuicao nao deveria invalidar a membership do ator';
  end if;

  -- Restaura o cenario.
  update public.membership_access_role_assignments set status = 'active'
   where id = 'd7000000-0000-0000-0000-0000000000a1';

  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(
      'd7b00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1') x
   where x.capability_code = 'collaborator.edit';
  if v_n < 1 then
    raise exception '[FAIL] T-16 restauracao da atribuicao nao devolveu a capability';
  end if;

  raise notice '[PASS] T-16 revogacao entre leitura e mutacao: capability recalculada por operacao (sem cache de ALLOW) e restaurada sem novo login';
end $$;

do $$
declare
  v_ver int;
  v_msg text := null;
  v_state text := null;
begin
  -- Perfil inativo (membership ativa) => DENY fail-closed na operacao.
  select version into v_ver from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000c8';

  begin
    perform public.colaborador_editar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a6',
      'd7100000-0000-0000-0000-000000000051','d7c00000-0000-0000-0000-0000000000c8',
      'Colaborador Perfil Inativo F5-07','perfil.inativo.f5-07@example.invalid', null, v_ver);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] chamada invalida a colaborador_editar (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg is null or v_msg not like 'F5_07_%' then
    raise exception '[FAIL] T-06 perfil inativo deveria ser recusado com F5_07_* (msg=%)', v_msg;
  end if;
  if exists (select 1 from public.collaborators
              where id = 'd7c00000-0000-0000-0000-0000000000c8'
                and full_name = 'Colaborador Perfil Inativo F5-07') then
    raise exception '[FAIL] T-06 perfil inativo escreveu o cadastro';
  end if;

  raise notice '[PASS] T-06 perfil inativo (membership ativa) recusado fail-closed na operacao, sem escrita';
end $$;

-- ============================================================================
-- 9) T-04: recusa uniforme (cross-tenant e inexistente) sem vazamento
-- ============================================================================
do $$
declare
  v_msg_inex text := null;
  v_msg_cross text := null;
  v_ver_inex int;
  v_ver_cross int;
begin
  select version into v_ver_inex from public.collaborators
   where id = 'd7c00000-0000-0000-0000-0000000000c9';
  v_ver_cross := v_ver_inex;

  begin
    perform public.colaborador_editar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000060','d7c00000-0000-0000-0000-0000000000fe',
      'Fantasma A F5-07','fantasma.a.f5-07@example.invalid', null, v_ver_inex);
  exception when others then
    v_msg_inex := SQLERRM;
  end;

  begin
    perform public.colaborador_editar(
      'd7a00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1',
      'd7100000-0000-0000-0000-000000000061','d7c00000-0000-0000-0000-0000000000b1',
      'Fantasma B F5-07','fantasma.b.f5-07@example.invalid', null, v_ver_cross);
  exception when others then
    v_msg_cross := SQLERRM;
  end;

  if v_msg_inex is null or v_msg_cross is null then
    raise exception '[FAIL] T-04 leitura de alvo inexistente/cross-tenant deveria ser recusada nos dois casos';
  end if;
  if v_msg_inex not like 'F5_07_%' or v_msg_cross not like 'F5_07_%' then
    raise exception '[FAIL] T-04 recusa fora do prefixo padronizado (% / %)', v_msg_inex, v_msg_cross;
  end if;

  -- Nenhum detalhe do recurso de outro tenant vaza (nem tenant, nem nome).
  if position('Beta' in v_msg_cross) > 0
     or position('d7a00000-0000-0000-0000-0000000000b1' in v_msg_cross) > 0 then
    raise exception '[FAIL] T-04 recusa cross-tenant vazou detalhe do recurso (msg=%)', v_msg_cross;
  end if;

  if exists (select 1 from public.collaborator_events
              where operation_id in ('d7100000-0000-0000-0000-000000000060'::uuid,
                                     'd7100000-0000-0000-0000-000000000061'::uuid)) then
    raise exception '[FAIL] T-04 recusa gravou evento';
  end if;

  raise notice '[PASS] T-04 recusa uniforme para UUID inexistente e UUID de outro tenant, sem vazamento de tenant e sem escrita';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-07 (cutover): todas as verificacoes passaram (superficie de funcoes, RLS/grants sem acesso direto de authenticated, anti-IDOR, cross-tenant, matricula como intencao, concorrencia, idempotencia, revogacao entre leitura e mutacao).';
end $$;
