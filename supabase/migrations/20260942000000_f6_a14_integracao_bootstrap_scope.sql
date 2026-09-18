-- F6-A14: integração explícita no bootstrap F6-A11.
-- Remove o mecanismo global anterior: assignments normais e fixtures não são
-- bootstrap e não devem receber scope por efeito colateral.

drop trigger if exists trg_f6_a14_scope_bootstrap_admin
  on public.membership_access_role_assignments;
drop function if exists public.f6_a14_materializar_scope_bootstrap_admin();

do $migration$
declare
  v_def       text;
  v_decl      text := E'  v_collaborator  uuid;';
  v_decl_repl text := E'  v_collaborator  uuid;\n  v_assignment   uuid;';
  v_ancora    text := E'  perform public.conceder_acesso_role(v_membership, v_role, p_actor_user_profile_id);\n\n  -- (11)';
  v_repl      text := E'  perform public.conceder_acesso_role(v_membership, v_role, p_actor_user_profile_id);\n\n  -- F6-A14: scope ORGANIZATION da assignment real do primeiro Admin.\n  select a.id into v_assignment\n    from public.membership_access_role_assignments a\n   where a.membership_id = v_membership\n     and a.organization_id = v_org\n     and a.access_role_id = v_role\n     and a.status = ''active''\n     and a.created_by = p_actor_user_profile_id;\n  if v_assignment is null then\n    raise exception using message = v_assignment::text;\n  end if;\n\n  insert into public.access_role_assignment_scopes (\n    assignment_id, organization_id, scope_type, status, created_by\n  ) values (\n    v_assignment, v_org, ''ORGANIZATION'', ''active'', p_actor_user_profile_id\n  ) on conflict (assignment_id, scope_type) do nothing;\n\n  -- (11)';
  v_novo     text;
begin
  if to_regprocedure(
       'public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text)'
     ) is null then
    raise exception 'F6-A14: RPC F6-A11 nao encontrada';
  end if;

  select pg_get_functiondef(
    'public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text)'::regprocedure
  ) into v_def;

  if position('v_assignment' in v_def) <> 0
     or position(v_decl in v_def) = 0
     or position(v_ancora in v_def) = 0 then
    raise exception 'F6-A14: ancora da RPC F6-A11 inesperada ou ja aplicada';
  end if;

  v_novo := replace(replace(v_def, v_decl, v_decl_repl), v_ancora, v_repl);
  if v_novo = v_def then
    raise exception 'F6-A14: CREATE OR REPLACE nao alterou a RPC F6-A11';
  end if;
  execute v_novo;

  if exists (
    select 1
      from pg_trigger t
     where t.tgname = 'trg_f6_a14_scope_bootstrap_admin'
       and not t.tgisinternal
  ) then
    raise exception 'F6-A14: trigger global ainda instalado';
  end if;

  select pg_get_functiondef(
    'public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text)'::regprocedure
  ) into v_novo;
  if position('access_role_assignment_scopes' in v_novo) = 0
     or position('v_assignment' in v_novo) = 0
     or position('p_actor_user_profile_id' in v_novo) = 0 then
    raise exception 'F6-A14: bootstrap sem materializacao completa do scope';
  end if;
end;
$migration$;

comment on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text) is
  'F6-A03 + F6-A11 + F6-A14: bootstrap inicial com scope ORGANIZATION '
  'explicito na assignment admin, sem trigger global ou backfill.';
