-- F6-A20 / Issue #310: primeiro acesso do founder provisionado.
--
-- Migration aditiva: reaproveita a definição canônica existente e altera
-- somente a criação de founder novo. Perfil preexistente permanece intocado.

do $migration$
declare
  v_def text;
begin
  -- Transformação temporária: a função auxiliar não sobrevive à migration.
  alter function public.organizacao_provisionar_inicial(
    uuid, text, uuid, uuid, text, text, text
  ) rename to organizacao_provisionar_inicial_f6_a20_transform;

  select pg_get_functiondef(
    'public.organizacao_provisionar_inicial_f6_a20_transform(uuid, text, uuid, uuid, text, text, text)'::regprocedure
  ) into v_def;

  v_def := replace(
    v_def,
    'organizacao_provisionar_inicial_f6_a20_transform',
    'organizacao_provisionar_inicial'
  );
  v_def := replace(
    v_def,
    'insert into public.user_profiles (id) values (p_founder_user_profile_id)',
    'insert into public.user_profiles (id, first_access_pending) values (p_founder_user_profile_id, true)'
  );

  execute v_def;
  drop function public.organizacao_provisionar_inicial_f6_a20_transform(
    uuid, text, uuid, uuid, text, text, text
  );
end;
$migration$;

comment on function public.organizacao_provisionar_inicial(
  uuid, text, uuid, uuid, text, text, text
) is
  'F6-A20/#310: bootstrap canônico marca founder novo como primeiro acesso pendente; perfil preexistente permanece inalterado.';

revoke all on function public.organizacao_provisionar_inicial(
  uuid, text, uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.organizacao_provisionar_inicial(
  uuid, text, uuid, uuid, text, text, text
) to service_role;
