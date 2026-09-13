-- ============================================================================
-- F5-09 P7 (Issue #202) — D28: reconciliacao ADITIVA do catalogo
-- ----------------------------------------------------------------------------
-- Coloca `cycle.manage` no bundle administrativo de SISTEMA (`admin`), para que
-- a gestao soberana de ciclo seja EXECUTAVEL em producao (R9) depois do cutover
-- (P8): sem isso, ninguem teria a capability em producao.
--
-- ADITIVO, ESTRITO e IDEMPOTENTE:
--   - NENHUMA capability nova (o catalogo continua com o mesmo tamanho);
--   - NENHUMA remocao fisica (F5-04 D14) e nenhuma alteracao de atributo de
--     capability;
--   - SOMENTE a relacao `admin` × `cycle.manage`, provada apos o INSERT;
--   - `cycle.cancel`, `cycle.reopen` e `cycle.period.correct` permanecem FORA
--     dos bundles/roles DE SISTEMA (Q-F5-09-3 alternativa A / D28). Elas
--     continuam CONCEDIVEIS por configuracao EXPLICITA em roles CUSTOMIZADAS
--     (`is_system = false`) — as guardas desta migration restringem a proibicao
--     as roles de sistema e NAO bloqueiam concessoes legitimas em roles
--     customizadas;
--   - reexecucao e SEGURA: se `admin` × `cycle.manage` ja existir, o INSERT nao
--     adiciona nada e o bundle NAO cresce (o tamanho esperado e calculado a
--     partir do estado anterior);
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
  v_ja_existia boolean;
  v_bundle_esperado integer;
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

  -- (3) Preflight (D28): as tres capabilities EXCEPCIONAIS nao podem estar em
  -- role/bundle DE SISTEMA. Roles CUSTOMIZADAS (`is_system = false`) sao um
  -- caminho LEGITIMO de configuracao explicita e NAO entram nesta guarda.
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.is_system = true
       and c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct')
  ) then
    raise exception '[FAIL] F5-09 P7 (D28): capability excepcional de ciclo concedida a role DE SISTEMA';
  end if;

  select count(*) into v_catalogo_antes from public.capabilities;
  select count(*) into v_bundle_antes
    from public.access_role_capabilities where access_role_id = v_role;
  select exists (
    select 1 from public.access_role_capabilities
     where access_role_id = v_role and capability_id = v_cap
  ) into v_ja_existia;

  -- Tamanho esperado do bundle: +1 SOMENTE se a relacao ainda nao existia.
  v_bundle_esperado := v_bundle_antes + (case when v_ja_existia then 0 else 1 end);

  -- (4) Reconciliacao ADITIVA e IDEMPOTENTE: somente `admin` × `cycle.manage`.
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

  -- A relacao existe EXATAMENTE UMA vez (a constraint UNIQUE
  -- `uq_access_role_capabilities_role_capability` impede duplicata; aqui provamos).
  if (select count(*) from public.access_role_capabilities
       where access_role_id = v_role and capability_id = v_cap) <> 1 then
    raise exception '[FAIL] F5-09 P7 (D28): relacao admin × cycle.manage ausente ou duplicada';
  end if;

  if (select count(*) from public.access_role_capabilities where access_role_id = v_role)
     <> v_bundle_esperado then
    raise exception '[FAIL] F5-09 P7 (D28): bundle admin com tamanho inesperado (% -> %, ja_existia=%)',
      v_bundle_antes, (select count(*) from public.access_role_capabilities where access_role_id = v_role),
      v_ja_existia;
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

  -- As tres excepcionais continuam FORA das roles DE SISTEMA (roles
  -- customizadas permanecem livres para recebe-las por configuracao explicita).
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.is_system = true
       and c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct')
  ) then
    raise exception '[FAIL] F5-09 P7 (D28): role DE SISTEMA passou a conceder capability excepcional de ciclo';
  end if;

  raise notice '[PASS] F5-09 P7 (D28): cycle.manage no bundle admin (ja_existia=%, bundle=% de %); excepcionais fora das roles de sistema; catalogo intacto',
    v_ja_existia, (select count(*) from public.access_role_capabilities where access_role_id = v_role),
    v_bundle_esperado;
end $$;
