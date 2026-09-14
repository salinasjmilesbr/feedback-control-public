-- ============================================================================
-- F5-10 P5 — BLOCO 2: HARDENING D22-A (Issue #218) — PREPARADO, AINDA NAO APLICADO
-- ----------------------------------------------------------------------------
-- Decisao D22-A aprovada pelo owner: eliminar o SELECT direto de metas por
-- browser/`authenticated` e fazer a AUTORIZACAO FUNCIONAL de leitura passar
-- exclusivamente pela superficie soberana (`meta_listar_por_escopo`), que aplica
-- `goal.read` + vinculo/relacao congelada.
--
-- Esta migration REVOGA a exposicao contratada na P4 (§11):
--   - drop das 2 policies own-tenant de metas;
--   - revoke select de `authenticated` nas 2 tabelas;
--   - as 4 tabelas de metas voltam a DENY-BY-DEFAULT integral (como na P1);
--   - `service_role` mantem EXATAMENTE os privilegios da P1 (executor tecnico);
--   - NENHUMA autorizacao funcional entra na RLS (Policy Engine continua soberano);
--   - `evaluation_cycles` NAO e tocada (assimetria analisada separadamente);
--   - nenhuma capability nova, nenhum SECURITY DEFINER, nenhuma RPC nova.
-- ============================================================================

do $$
declare
  v_pol   integer;
  v_n     integer;
begin
  -- Preflight: o estado de PARTIDA e o da P4 (2 policies + SELECT de cliente).
  select count(*) into v_pol
    from pg_policies
   where schemaname = 'public'
     and tablename in ('evaluation_goals', 'evaluation_goal_approvals');
  if v_pol <> 2 then
    raise exception 'F5_10_P5_D22A_PREFLIGHT: esperadas 2 policies de metas (estado da P4), encontradas %', v_pol;
  end if;
  if not has_table_privilege('authenticated', 'public.evaluation_goals', 'SELECT') then
    raise exception 'F5_10_P5_D22A_PREFLIGHT: `authenticated` sem SELECT em evaluation_goals (estado inesperado)';
  end if;
  if to_regprocedure('public.meta_listar_por_escopo(uuid, uuid, uuid)') is null then
    raise exception 'F5_10_P5_D22A_PREFLIGHT: superficie soberana de leitura ausente (meta_listar_por_escopo)';
  end if;
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('evaluation_goals', 'evaluation_goal_approvals',
                       'evaluation_goal_events', 'evaluation_cycle_goal_limits')
     and c.relrowsecurity;
  if v_n <> 4 then
    raise exception 'F5_10_P5_D22A_PREFLIGHT: RLS nao habilitada nas 4 tabelas de metas (%)', v_n;
  end if;

  raise notice 'F5-10 P5 (D22-A): preflight OK (estado da P4 confirmado e superficie soberana de leitura presente)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) Fechamento da rota alternativa (PostgREST) — fail-closed por construcao
-- ----------------------------------------------------------------------------
drop policy if exists evaluation_goals_select_same_tenant on public.evaluation_goals;
drop policy if exists evaluation_goal_approvals_select_same_tenant on public.evaluation_goal_approvals;

revoke select on public.evaluation_goals from authenticated;
revoke select on public.evaluation_goal_approvals from authenticated;

-- `service_role` permanece EXECUTOR TECNICO com os privilegios da P1 (nenhum DML
-- novo, nenhum DELETE/TRUNCATE): as RPCs soberanas continuam funcionando.
revoke all on public.evaluation_goals from service_role;
revoke all on public.evaluation_goal_approvals from service_role;
grant select, insert, update on public.evaluation_goals to service_role;
grant select, insert, update on public.evaluation_goal_approvals to service_role;

-- ----------------------------------------------------------------------------
-- 2) Guarda final FAIL-CLOSED
-- ----------------------------------------------------------------------------
do $$
declare
  v_tab     text;
  v_priv    text;
  v_n       integer;
  v_falhas  text[] := array[]::text[];
begin
  -- (a) As 4 tabelas de metas: deny-by-default INTEGRAL (zero policy).
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = v_tab
    ) then
      v_falhas := v_falhas || ('policy remanescente em ' || v_tab);
    end if;
    foreach v_priv in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      if has_table_privilege('authenticated', 'public.' || v_tab, v_priv) then
        v_falhas := v_falhas || format('%s: authenticated com %s', v_tab, v_priv);
      end if;
      if has_table_privilege('anon', 'public.' || v_tab, v_priv) then
        v_falhas := v_falhas || format('%s: anon com %s', v_tab, v_priv);
      end if;
    end loop;
    if has_table_privilege('service_role', 'public.' || v_tab, 'DELETE')
       or has_table_privilege('service_role', 'public.' || v_tab, 'TRUNCATE') then
      v_falhas := v_falhas || format('%s: service_role com DELETE/TRUNCATE', v_tab);
    end if;
  end loop;

  -- (b) `service_role` mantem exatamente a matriz da P1.
  if not has_table_privilege('service_role', 'public.evaluation_goals', 'SELECT')
     or not has_table_privilege('service_role', 'public.evaluation_goals', 'INSERT')
     or not has_table_privilege('service_role', 'public.evaluation_goals', 'UPDATE')
     or not has_table_privilege('service_role', 'public.evaluation_goal_approvals', 'SELECT')
     or not has_table_privilege('service_role', 'public.evaluation_goal_approvals', 'INSERT')
     or not has_table_privilege('service_role', 'public.evaluation_goal_approvals', 'UPDATE') then
    v_falhas := v_falhas || 'service_role perdeu privilegio de execucao tecnica';
  end if;

  -- (c) A superficie soberana de leitura continua INVOKER com EXECUTE so service_role.
  if (select p.prosecdef from pg_proc p
       where p.oid = to_regprocedure('public.meta_listar_por_escopo(uuid, uuid, uuid)')) then
    v_falhas := v_falhas || 'meta_listar_por_escopo virou SECURITY DEFINER';
  end if;
  if has_function_privilege('authenticated', 'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    v_falhas := v_falhas || 'meta_listar_por_escopo exposta a cliente';
  end if;

  -- (d) Catalogo intacto: nenhuma capability nova; nenhum DEFINER novo.
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname <> all (array[
       'conceder_acesso_role', 'criar_perfil_membership',
       'resolver_capabilities_efetivas', 'revogar_acesso_role']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('SECURITY DEFINER novo em public = %s (esperado 0)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception 'F5_10_P5_D22A_GUARD: hardening inconsistente: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-10 P5 (D22-A): guarda final OK (4 tabelas de metas deny-by-default integral, cliente sem privilegio, service_role executor tecnico preservado, leitura soberana intacta e catalogo sem capability nova)';
end $$;
