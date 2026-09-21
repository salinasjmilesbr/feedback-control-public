-- ============================================================================
-- F6-A19 / Issue #319 — CONVITE ADMINISTRATIVO COM VÍNCULO SOBERANO
-- ----------------------------------------------------------------------------
-- CONTEXTO (defeito corrigido, diagnóstico aprovado):
--   o convite administrativo criava perfil + membership e NENHUM vínculo: a
--   conta do convidado ficava sem correspondência com a pessoa organizacional
--   já cadastrada (`membership_collaborator_links` vazio). A Edge passa a exigir
--   a colaboradora JÁ CRIADA (`collaborator_id`) e o vínculo é criado pelo
--   primitivo canônico da F5-02.
--
-- O QUE ESTA MIGRATION CRIA (aditiva):
--   `public.convidado_acesso_criar(p_user_id, p_organization_id,
--   p_collaborator_id) returns uuid` — em UMA transação:
--     (1) valida que o colaborador existe NO tenant informado (cross-tenant é
--         NEGADO antes de qualquer escrita);
--     (2) cria perfil + membership pelo MESMO primitivo do convite F2-06
--         (`criar_perfil_membership`, SECURITY DEFINER já existente);
--     (3) vincula a membership ao colaborador pelo primitivo da F5-02 (D9)
--         `vincular_colaborador` — mesmas checagens de tenant, 1 vínculo ativo
--         por membership (Q6=B) e 1 por colaborador/organização (Q3=B).
--
-- O QUE ESTA MIGRATION NÃO FAZ (invariantes):
--   - NENHUMA role é concedida (nem `admin`): a autoridade administrativa não é
--     auto-servida (F5-04 D15/D16) e papel funcional é ato administrativo próprio
--     (`conceder_acesso_role_rpc`, F5-04/F5-11 P5.4);
--   - NENHUMA alteração de catálogo, `grantable_via_role`, RLS, policy, grant de
--     tabela/coluna ou tipo: `membership.manage` continua NÃO concedível por role;
--   - NENHUM `SECURITY DEFINER` novo (a função é INVOKER; o total permanece 4,
--     invariante da F4-08);
--   - NENHUM DML direto em `membership_collaborator_links` (só pelo primitivo);
--   - NADA é recriado, renomeado ou alterado na colaboradora já existente.
--
-- ASSINATURA/ACL: `SECURITY INVOKER`, `search_path = public`, EXECUTE SOMENTE
-- `service_role` (a Edge Function é a única chamadora; identidade e tenant são
-- revalidados server-side — nenhuma autoridade vem do cliente).
-- ============================================================================

create or replace function public.convidado_acesso_criar(
  p_user_id uuid,
  p_organization_id uuid,
  p_collaborator_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_membership uuid;
begin
  -- (1) Entrada obrigatória (fail-closed).
  if p_user_id is null or p_organization_id is null or p_collaborator_id is null then
    raise exception 'F6_A19_INVALID_INPUT: parametros obrigatorios'
      using errcode = '22023';
  end if;

  -- (2) TENANT ISOLATION: o colaborador precisa existir NO tenant informado.
  --     Cross-tenant é NEGADO aqui, ANTES de qualquer escrita.
  if not exists (
    select 1
      from public.collaborators c
     where c.id = p_collaborator_id and c.organization_id = p_organization_id
  ) then
    raise exception 'F6_A19_INVALID_COLLABORATOR: colaborador inexistente no tenant'
      using errcode = 'P0002';
  end if;

  -- (3) Perfil + membership pelo primitivo do convite (F2-06/D3): atômico e sem
  --     duplicar a regra de criação (perfil 1:1 com auth.users + membership).
  perform public.criar_perfil_membership(p_user_id, p_organization_id);

  select m.id
    into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_user_id
     and m.organization_id = p_organization_id
     and m.status = 'active';

  if v_membership is null then
    raise exception 'F6_A19_INTERNAL: membership nao criada' using errcode = 'P0001';
  end if;

  -- (4) VÍNCULO conta ↔ colaboradora pelo PRIMITIVO canônico (F5-02 D9).
  perform public.vincular_colaborador(v_membership, p_collaborator_id);

  -- (5) NENHUMA role é concedida aqui (D15/D16). O retorno é o vínculo criado.
  return v_membership;
end;
$fn$;

comment on function public.convidado_acesso_criar(uuid, uuid, uuid) is
  'F6-A19 (#319): provisiona o acesso do convidado em UMA transacao — perfil + '
  'membership (primitivo F2-06) + vinculo da membership ao collaborator_id '
  '(primitivo F5-02 D9). Cross-tenant negado (P0002) antes de escrever. NENHUMA '
  'role e concedida. SECURITY INVOKER, search_path fixo, EXECUTE somente '
  'service_role.';

revoke all on function public.convidado_acesso_criar(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.convidado_acesso_criar(uuid, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- Guardas fail-closed da própria migration (molde F6-A11): a definição
-- resultante e as invariantes herdadas são verificadas antes de encerrar.
-- ----------------------------------------------------------------------------
do $guarda$
declare
  v_def     text;
  v_definer integer;
  v_control boolean;
begin
  v_def := pg_get_functiondef('public.convidado_acesso_criar(uuid, uuid, uuid)'::regprocedure);

  if position('SECURITY DEFINER' in v_def) <> 0 then
    raise exception 'F6_A19: a RPC do convite nao pode ser SECURITY DEFINER';
  end if;
  if position('vincular_colaborador' in v_def) = 0 then
    raise exception 'F6_A19: a RPC do convite nao usa o primitivo vincular_colaborador';
  end if;
  if position('organization_id = p_organization_id' in v_def) = 0 then
    raise exception 'F6_A19: a RPC do convite nao valida o tenant do colaborador';
  end if;
  if position('conceder_acesso_role' in v_def) <> 0
     or position('membership_access_role_assignments' in lower(v_def)) <> 0 then
    raise exception 'F6_A19: a RPC do convite nao pode conceder role';
  end if;
  if position('insert into public.membership_collaborator_links' in lower(v_def)) <> 0 then
    raise exception 'F6_A19: o vinculo deve ser criado pelo primitivo, nunca por INSERT direto';
  end if;

  -- Invariante F4-08 preservada: exatamente 4 SECURITY DEFINER em public.
  select count(*) into v_definer
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_definer <> 4 then
    raise exception 'F6_A19: esperado exatamente 4 SECURITY DEFINER, encontrado %', v_definer;
  end if;

  -- D15 preservada: a capability de controle continua NÃO concedível por role.
  select grantable_via_role into v_control
    from public.capabilities
   where code = 'membership.manage';
  if v_control is distinct from false then
    raise exception 'F6_A19: membership.manage deveria permanecer grantable_via_role = false (D15)';
  end if;

  -- ACL: EXECUTE somente service_role.
  if has_function_privilege('anon', 'public.convidado_acesso_criar(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.convidado_acesso_criar(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception 'F6_A19: EXECUTE indevido para anon/authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.convidado_acesso_criar(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception 'F6_A19: EXECUTE ausente para service_role';
  end if;

  raise notice '[PASS] F6-A19: convidado_acesso_criar INVOKER/service_role-only, tenant validado, vinculo pelo primitivo, nenhuma role, 4 DEFINER e D15 intactos';
end $guarda$;
