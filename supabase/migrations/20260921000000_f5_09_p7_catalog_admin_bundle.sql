-- ============================================================================
-- F5-09 P7 (Issue #202) — D28: reconciliacao ADITIVA do catalogo
-- ----------------------------------------------------------------------------
-- Coloca `cycle.manage` no bundle administrativo de SISTEMA (`admin`), para que
-- a gestao soberana de ciclo seja EXECUTAVEL em producao (R9) depois do cutover
-- (P8): sem isso, ninguem teria a capability em producao.
--
-- ADITIVO e ESTRITO:
--   - NENHUMA capability nova (o catalogo continua com o mesmo tamanho);
--   - NENHUMA remocao fisica (F5-04 D14) e nenhuma alteracao de atributo de
--     capability;
--   - SOMENTE a relacao `admin` × `cycle.manage`;
--   - `cycle.cancel`, `cycle.reopen` e `cycle.period.correct` permanecem FORA do
--     bundle (Q-F5-09-3 alternativa A) — concediveis apenas por configuracao
--     explicita de role;
--   - nenhuma alteracao de schema, RLS, RPC, tabela ou coluna.
--
-- Preflight e guarda final sao FAIL-CLOSED: qualquer divergencia de estado
-- aborta a migration em vez de "acomodar" o banco.
-- ============================================================================

do $$
declare
  v_role constant uuid := 'c0000000-0000-4000-8000-0000000000f1';
  v_cap uuid;
  v_catalogo_antes integer;
  v_bundle_antes integer;
begin
  -- (1) Preflight: role de SISTEMA `admin` presente, ativa e sem organizacao.
  if not exists (
    select 1 from public.access_roles
     where id = v_role and is_system = true and status = 'active'
       and organization_id is null
  ) then
    raise exception '[FAIL] F5-09 P7 (D28): access_role de sistema admin ausente/inativa';
  end if;

  -- (2) Preflight: a capability existe, esta ativa, nao deprecada e e concedivel
  -- por role (a trigger `trg_access_role_capabilities_grantable` exige isso).
  select id into v_cap
    from public.capabilities
   where code = 'cycle.manage' and status = 'active'
     and deprecated = false and grantable_via_role = true;
  if v_cap is null then
    raise exception '[FAIL] F5-09 P7 (D28): capability cycle.manage ausente/inativa/depreciada/nao concedivel';
  end if;

  -- (3) Preflight: as tres excepcionais NAO podem estar em bundle/role algum.
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct')
  ) then
    raise exception '[FAIL] F5-09 P7 (D28): capability excepcional de ciclo ja concedida a role';
  end if;

  select count(*) into v_catalogo_antes from public.capabilities;
  select count(*) into v_bundle_antes
    from public.access_role_capabilities where access_role_id = v_role;

  -- (4) Reconciliacao ADITIVA e idempotente: somente `admin` × `cycle.manage`.
  insert into public.access_role_capabilities (access_role_id, capability_id)
  select v_role, v_cap
   where not exists (
     select 1 from public.access_role_capabilities
      where access_role_id = v_role and capability_id = v_cap
   );

  -- (5) Guarda final FAIL-CLOSED.
  if (select count(*) from public.capabilities) <> v_catalogo_antes then
    raise exception '[FAIL] F5-09 P7 (D28): catalogo de capabilities mudou de tamanho (% -> %)',
      v_catalogo_antes, (select count(*) from public.capabilities);
  end if;

  if (select count(*) from public.access_role_capabilities where access_role_id = v_role)
     <> v_bundle_antes + 1 then
    raise exception '[FAIL] F5-09 P7 (D28): bundle admin deveria ganhar EXATAMENTE 1 capability (% -> %)',
      v_bundle_antes, (select count(*) from public.access_role_capabilities where access_role_id = v_role);
  end if;

  if not exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_role and c.code = 'cycle.manage'
  ) then
    raise exception '[FAIL] F5-09 P7 (D28): cycle.manage nao foi concedida ao bundle admin';
  end if;

  -- `cycle.read` (bundle admin desde a F5-04) permanece.
  if not exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_role and c.code = 'cycle.read'
  ) then
    raise exception '[FAIL] F5-09 P7 (D28): cycle.read saiu do bundle admin';
  end if;

  -- As tres excepcionais continuam fora (nenhuma role).
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct')
  ) then
    raise exception '[FAIL] F5-09 P7 (D28): bundle/role passou a conceder capability excepcional de ciclo';
  end if;

  raise notice '[PASS] F5-09 P7 (D28): cycle.manage no bundle admin (+1 exato); excepcionais fora do bundle; catalogo intacto';
end $$;
