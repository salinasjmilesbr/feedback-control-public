-- ============================================================================
-- F5-02 (vínculo usuário autenticado ↔ colaborador): validação automatizada
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f5-02.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f5-02.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f5-02.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; falha aborta (código
-- não-zero). NÃO toca projeto remoto, NÃO altera policies e remove ao final os
-- dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Estrutura: indexes parciais, functions, INVOKER, grants
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_indexes
  where schemaname='public' and tablename='membership_collaborator_links'
    and indexname in (
      'uq_membership_collaborator_links_active_membership',
      'uq_membership_collaborator_links_active_collaborator'
    );
  if v_n <> 2 then
    raise exception '[FAIL] unique indexes parciais do vinculo ativo ausentes (esperado=2, encontrado=%)', v_n;
  end if;

  if exists (
    select 1 from pg_constraint
    where conname = 'uq_membership_collaborator_links_membership'
  ) then
    raise exception '[FAIL] unicidade TOTAL por membership ainda presente (deveria ter sido removida — Q6=B)';
  end if;
  raise notice '[PASS] unicidade parcial aplicada (1 active por membership e 1 active por colaborador+org; unique total removido)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname in (
    'resolver_collaborador_vinculado',
    'vincular_colaborador',
    'desativar_vinculo_colaborador',
    'trocar_vinculo_colaborador'
  );
  if v_n <> 4 then
    raise exception '[FAIL] funcoes F5-02 esperadas=4, encontradas=%', v_n;
  end if;
  raise notice '[PASS] funcoes F5-02 presentes (resolver endurecido + vincular/desativar/trocar)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public'
    and p.proname in ('resolver_collaborador_vinculado',
                      'vincular_colaborador',
                      'desativar_vinculo_colaborador',
                      'trocar_vinculo_colaborador')
    and p.prosecdef;
  if v_n <> 0 then
    raise exception '[FAIL] funcao F5-02 nao deveria ser SECURITY DEFINER (sem DEFINER novo)';
  end if;
  raise notice '[PASS] funcoes F5-02 sao SECURITY INVOKER (Q1/Q2; F4-02 D18 inalterado)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public'
    and p.proname in ('vincular_colaborador','desativar_vinculo_colaborador','trocar_vinculo_colaborador')
    and a.privilege_type='EXECUTE'
    and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole);
  if v_n <> 0 then
    raise exception '[FAIL] EXECUTE indevido (public/anon/authenticated) nas mutacoes de vinculo: %', v_n;
  end if;
  raise notice '[PASS] mutacoes de vinculo sem EXECUTE para public/anon/authenticated';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public'
    and p.proname in ('vincular_colaborador','desativar_vinculo_colaborador','trocar_vinculo_colaborador')
    and a.privilege_type='EXECUTE'
    and a.grantee = 'service_role'::regrole;
  if v_n <> 3 then
    raise exception '[FAIL] EXECUTE service_role ausente nas mutacoes de vinculo (esperado=3, encontrado=%)', v_n;
  end if;
  raise notice '[PASS] mutacoes de vinculo com EXECUTE somente para service_role';
end $$;

-- ============================================================================
-- 2) Resolução (resolver endurecido Q4=A; fail-closed em todos os elos; Q5=A)
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_collaborador_vinculado(
    'd2b00000-0000-0000-0000-0000000000a1',
    'd2a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 1 then raise exception '[FAIL] vinculo ativo deveria resolver 1 colaborador (%)', v_n; end if;
  raise notice '[PASS] vinculo ativo resolve corretamente (U_A -> COLLAB_A)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_collaborador_vinculado(
    'd2b00000-0000-0000-0000-0000000000a3',
    'd2a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then raise exception '[FAIL] profile desabilitado deveria resolver vazio (%)', v_n; end if;
  raise notice '[PASS] profile desabilitado => resolucao vazia (Q4=A)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_collaborador_vinculado(
    'd2b00000-0000-0000-0000-0000000000a4',
    'd2a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then raise exception '[FAIL] membership desabilitada deveria resolver vazio (%)', v_n; end if;
  raise notice '[PASS] membership desabilitada => resolucao vazia';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_collaborador_vinculado(
    'd2b00000-0000-0000-0000-0000000000a5',
    'd2a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then raise exception '[FAIL] sem vinculo ativo deveria resolver vazio (%)', v_n; end if;
  raise notice '[PASS] sem vinculo ativo => resolucao vazia (D17)';
end $$;

do $$
declare
  v_id uuid;
begin
  select collaborator_id into v_id
  from public.resolver_collaborador_vinculado(
    'd2b00000-0000-0000-0000-0000000000a6',
    'd2a00000-0000-0000-0000-0000000000a1'
  );
  if v_id <> 'd2c00000-0000-0000-0000-0000000000c5' then
    raise exception '[FAIL] colaborador em leave deveria continuar como ancora (%)', v_id;
  end if;
  raise notice '[PASS] leave NAO remapeia identidade (Q5=A): ancora preservada';
end $$;

do $$
declare
  v_id uuid;
begin
  select collaborator_id into v_id
  from public.resolver_collaborador_vinculado(
    'd2b00000-0000-0000-0000-0000000000a7',
    'd2a00000-0000-0000-0000-0000000000a1'
  );
  if v_id <> 'd2c00000-0000-0000-0000-0000000000c6' then
    raise exception '[FAIL] colaborador inactive deveria continuar como ancora (%)', v_id;
  end if;
  raise notice '[PASS] inactive NAO remapeia identidade (Q5=A): ancora preservada';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_collaborador_vinculado(
    'd2b00000-0000-0000-0000-0000000000a1',
    'd2a00000-0000-0000-0000-0000000000b1'
  );
  if v_n <> 0 then raise exception '[FAIL] organizacao sem membership ativa deveria resolver vazio (%)', v_n; end if;
  raise notice '[PASS] organizacao sem membership ativa => resolucao vazia (tenant)';
end $$;

-- ============================================================================
-- 3) Fechado para authenticated (sem SELECT/DML/EXECUTE — Q1=A)
-- ============================================================================

set role authenticated;
do $$
declare v_ok boolean := false;
begin
  begin perform 1 from public.membership_collaborator_links; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated leu tabela fechada membership_collaborator_links'; end if;
  raise notice '[PASS] authenticated sem SELECT direto na tabela do vinculo';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin
    insert into public.membership_collaborator_links (membership_id, organization_id, collaborator_id, status)
    values ('d2d00000-0000-0000-0000-000000000005', 'd2a00000-0000-0000-0000-0000000000a1',
            'd2c00000-0000-0000-0000-0000000000c8', 'active');
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated inseriu na tabela fechada'; end if;
  raise notice '[PASS] authenticated sem INSERT direto na tabela do vinculo';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin
    update public.membership_collaborator_links set status='disabled'
    where membership_id = 'd2d00000-0000-0000-0000-000000000001';
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated alterou a tabela fechada'; end if;
  raise notice '[PASS] authenticated sem UPDATE direto na tabela do vinculo';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin
    perform 1 from public.resolver_collaborador_vinculado(
      'd2b00000-0000-0000-0000-0000000000a1',
      'd2a00000-0000-0000-0000-0000000000a1'
    );
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated executou resolver do vinculo'; end if;
  raise notice '[PASS] authenticated sem EXECUTE no resolver_collaborador_vinculado';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin
    perform public.vincular_colaborador(
      'd2d00000-0000-0000-0000-000000000005',
      'd2c00000-0000-0000-0000-0000000000c8'
    );
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated executou vincular_colaborador'; end if;
  raise notice '[PASS] authenticated sem EXECUTE nas mutacoes de vinculo';
end $$;

reset role;

-- ============================================================================
-- 4) Mutações server-side (D9): cross-tenant, Q3, Q6, troca atômica, rollback
-- ============================================================================

do $$
declare v_ok boolean := false;
begin
  begin
    perform public.vincular_colaborador(
      'd2d00000-0000-0000-0000-000000000001',
      'd2c00000-0000-0000-0000-0000000000b1'  -- colaborador de Beta
    );
  exception when others then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] vincular cross-tenant nao foi bloqueado'; end if;
  raise notice '[PASS] vincular cross-tenant bloqueado (tenant correlation)';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin
    perform public.trocar_vinculo_colaborador(
      'd2d00000-0000-0000-0000-000000000001',
      'd2c00000-0000-0000-0000-0000000000b1'
    );
  exception when others then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] trocar cross-tenant nao foi bloqueado'; end if;
  raise notice '[PASS] trocar cross-tenant bloqueado (tenant correlation)';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin
    perform public.vincular_colaborador(
      'd2d00000-0000-0000-0000-000000000005',
      'd2c00000-0000-0000-0000-0000000000c1'  -- COLLAB_A já ativo via M_A
    );
  exception when others then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] Q3: segundo active para mesmo colaborador+org nao foi bloqueado'; end if;
  raise notice '[PASS] Q3: segundo vinculo active para mesmo colaborador+organization falha';
end $$;

do $$
declare
  v_id uuid;
  v_n int;
  v_ok boolean := false;
begin
  select public.vincular_colaborador(
    'd2d00000-0000-0000-0000-000000000005',
    'd2c00000-0000-0000-0000-0000000000c8'
  ) into v_id;
  if v_id is null then raise exception '[FAIL] vincular valido nao retornou id'; end if;

  -- segundo active na mesma membership falha
  begin
    perform public.vincular_colaborador(
      'd2d00000-0000-0000-0000-000000000005',
      'd2c00000-0000-0000-0000-0000000000c9'
    );
  exception when others then
    v_ok := true;
  end;
  if not v_ok then raise exception '[FAIL] Q6: segundo active na mesma membership nao foi bloqueado'; end if;

  select count(*) into v_n from public.membership_collaborator_links
  where membership_id = 'd2d00000-0000-0000-0000-000000000005' and status='active';
  if v_n <> 1 then raise exception '[FAIL] exatamente 1 active esperado para m5 (%)', v_n; end if;
  raise notice '[PASS] Q6: exatamente 1 active por membership; segundo active na mesma membership falha';
end $$;

do $$
declare
  v_id uuid;
  v_n_active int;
  v_n_total int;
  v_old_collab uuid;
  v_old_status text;
begin
  select public.trocar_vinculo_colaborador(
    'd2d00000-0000-0000-0000-000000000001',
    'd2c00000-0000-0000-0000-0000000000c7'
  ) into v_id;
  if v_id is null then raise exception '[FAIL] trocar valido nao retornou id'; end if;

  select count(*) into v_n_active from public.membership_collaborator_links
  where membership_id = 'd2d00000-0000-0000-0000-000000000001' and status='active';
  if v_n_active <> 1 then raise exception '[FAIL] apos troca deveria haver 1 active em m1 (%)', v_n_active; end if;

  select count(*) into v_n_total from public.membership_collaborator_links
  where membership_id = 'd2d00000-0000-0000-0000-000000000001';
  if v_n_total <> 2 then raise exception '[FAIL] apos troca deveria haver 2 linhas (historico + ativa) em m1 (%)', v_n_total; end if;

  select collaborator_id, status into v_old_collab, v_old_status
  from public.membership_collaborator_links
  where membership_id = 'd2d00000-0000-0000-0000-000000000001' and collaborator_id = 'd2c00000-0000-0000-0000-0000000000c1';
  if v_old_collab is null or v_old_status <> 'disabled' then
    raise exception '[FAIL] linha antiga deveria permanecer disabled com collaborator_id preservado';
  end if;
  raise notice '[PASS] Q6: troca A->B preserva A como disabled (historico) e cria B active';
end $$;

do $$
declare v_ok boolean := false; v_n int;
begin
  begin
    perform public.trocar_vinculo_colaborador(
      'd2d00000-0000-0000-0000-000000000002',
      'd2c00000-0000-0000-0000-0000000000c7'  -- COLLAB_NEW já ativo via M_A
    );
  exception when others then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] Q3 na troca nao foi bloqueado (colaborador ja ativo em outra membership)'; end if;

  -- rollback: M_B permanece inalterado (ativo = c2; 1 linha)
  select count(*) into v_n from public.membership_collaborator_links
  where membership_id = 'd2d00000-0000-0000-0000-000000000002';
  if v_n <> 1 then raise exception '[FAIL] rollback da troca deveria manter M_B com 1 linha (%)', v_n; end if;
  select count(*) into v_n from public.membership_collaborator_links
  where membership_id = 'd2d00000-0000-0000-0000-000000000002'
    and status='active' and collaborator_id='d2c00000-0000-0000-0000-0000000000c2';
  if v_n <> 1 then raise exception '[FAIL] rollback da troca deveria manter M_B ativo=c2'; end if;
  raise notice '[PASS] rollback da troca (Q3) nao deixa estado intermediario invalido';
end $$;

do $$
declare v_ok boolean := false; v_n int;
begin
  begin
    perform public.trocar_vinculo_colaborador(
      'd2d00000-0000-0000-0000-000000000001',
      'd2c00000-0000-0000-0000-0000000000b1'  -- Beta
    );
  exception when others then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] trocar cross-tenant (pos-troca) nao foi bloqueado'; end if;

  select count(*) into v_n from public.membership_collaborator_links
  where membership_id = 'd2d00000-0000-0000-0000-000000000001' and status='active'
    and collaborator_id='d2c00000-0000-0000-0000-0000000000c7';
  if v_n <> 1 then raise exception '[FAIL] rollback cross-tenant deveria manter M_A ativo=c7'; end if;
  raise notice '[PASS] rollback cross-tenant nao deixa estado intermediario invalido';
end $$;

do $$
declare v_n int;
begin
  perform public.desativar_vinculo_colaborador('d2d00000-0000-0000-0000-000000000006');
  select count(*) into v_n from public.resolver_collaborador_vinculado(
    'd2b00000-0000-0000-0000-0000000000a6',
    'd2a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then raise exception '[FAIL] apos desativar, resolver deveria retornar vazio (%)', v_n; end if;
  raise notice '[PASS] desativar vinculo torna o link historico (resolver vazio)';
end $$;

-- ============================================================================
-- 5) Limpeza do cenário F5-02
-- ============================================================================

delete from public.membership_collaborator_links
 where organization_id in (
   'd2a00000-0000-0000-0000-0000000000a1',
   'd2a00000-0000-0000-0000-0000000000b1'
 );

delete from public.user_organization_memberships
 where organization_id in (
   'd2a00000-0000-0000-0000-0000000000a1',
   'd2a00000-0000-0000-0000-0000000000b1'
 );

delete from public.user_profiles
 where id::text like 'd2b00000-0000-0000-0000-0000000000%';

delete from auth.users
 where id::text like 'd2b00000-0000-0000-0000-0000000000%';

delete from public.collaborator_status_periods
 where collaborator_id::text like 'd2c00000-0000-0000-0000-0000000000%';

delete from public.collaborators
 where id::text like 'd2c00000-0000-0000-0000-0000000000%';

delete from public.organizations
 where id in (
   'd2a00000-0000-0000-0000-0000000000a1',
   'd2a00000-0000-0000-0000-0000000000b1'
 );

do $$
begin
  if exists (select 1 from public.membership_collaborator_links
             where organization_id::text like 'd2a00000%') then
    raise exception '[FAIL] limpeza do cenario F5-02 incompleta (links)';
  end if;
  if exists (select 1 from public.collaborators
             where id::text like 'd2c00000%') then
    raise exception '[FAIL] limpeza do cenario F5-02 incompleta (collaborators)';
  end if;
  raise notice '[PASS] cenario sintetico F5-02 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-02: todas as verificacoes passaram (vinculo, resolver endurecido, unicidade parcial, mutacoes atomicas, cross-tenant, RLS fechado).';
end $$;
