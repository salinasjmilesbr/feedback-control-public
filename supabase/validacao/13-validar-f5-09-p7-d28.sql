-- ============================================================================
-- F5-09 P7 (Issue #202) — VALIDACAO D28: guardas por TIPO de role (A–H) e
-- idempotencia da reconciliacao do catalogo.
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de:
--   1) `12-cenario-f5-09-p7-d28.sql` (role customizada com as 3 excepcionais e
--      estado E preparado);
--   2) a REAPLICACAO da migration D28 duas vezes (primeira insercao e reexecucao).
-- Como superuser local, com ON_ERROR_STOP ativo.
--
-- Cobre:
--   A/B/C — role CUSTOMIZADA (nao-sistema) com as tres capabilities excepcionais
--           e ACEITA pelas guardas da migration;
--   D     — o predicado das guardas RECUSA role DE SISTEMA com qualquer uma das
--           tres (avaliado com role de sistema temporaria, limpa em seguida);
--   E/F   — idempotencia: `admin` x `cycle.manage` existe EXATAMENTE UMA vez,
--           com o bundle no tamanho esperado apos primeira execucao e reexecucao;
--   G     — catalogo intacto (31 linhas; nenhuma capability nova);
--   H     — este validador e a migration compartilham a MESMA semantica
--           (proibicao restrita a roles de sistema).
-- ============================================================================

-- ============================================================================
-- A/B/C — concessoes LEGITIMAS em role CUSTOMIZADA (is_system = false)
-- ============================================================================
do $$
declare
  v_role constant uuid := 'e7f00000-0000-4000-8000-0000000000f1';
  v_sistema boolean;
  v_concedivel integer;
  v_codes text[];
begin
  select is_system into v_sistema from public.access_roles where id = v_role;
  if v_sistema is null then
    raise exception '[FAIL] A/B/C: role customizada do cenario ausente';
  end if;
  if v_sistema is not false then
    raise exception '[FAIL] A/B/C: role do cenario deveria ser NAO-sistema';
  end if;

  select array_agg(c.code order by c.code) into v_codes
    from public.access_role_capabilities m
    join public.capabilities c on c.id = m.capability_id
   where m.access_role_id = v_role;

  if v_codes is distinct from array[
    'cycle.cancel','cycle.period.correct','cycle.reopen'
  ]::text[] then
    raise exception '[FAIL] A/B/C: role customizada deveria manter as 3 excepcionais, encontradas: %', v_codes;
  end if;

  -- As tres continuam CONCEDIVEIS por role (F5-04 D14: sem remocao fisica).
  select count(*) into v_concedivel
    from public.capabilities
   where code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct')
     and grantable_via_role = true and deprecated = false and status = 'active';
  if v_concedivel <> 3 then
    raise exception '[FAIL] A/B/C: capabilities excepcionais deveriam seguir concediveis por role (% de 3)', v_concedivel;
  end if;

  raise notice '[PASS] A/B/C: migration ACEITA role customizada (nao-sistema) com cycle.cancel, cycle.reopen e cycle.period.correct';
end $$;

-- ============================================================================
-- D — o predicado das guardas RECUSA role DE SISTEMA com capability excepcional
-- ============================================================================
do $$
declare
  v_role constant uuid := 'e7f00000-0000-4000-8000-0000000000f2';
  v_detectou boolean := false;
begin
  -- Role de SISTEMA temporaria com `cycle.cancel` (a trigger de D15 permite:
  -- a capability e concedivel por role; a proibicao de D28 e sobre o TIPO da role).
  insert into public.access_roles (id, name, status, is_system, organization_id, version)
  values (v_role, 'd28_sistema_temporaria_p7', 'active', true, null, 0);

  insert into public.access_role_capabilities (access_role_id, capability_id)
  select v_role, c.id from public.capabilities c where c.code = 'cycle.cancel';

  -- MESMO predicado das guardas da migration D28 (restrito a roles de sistema).
  select exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.is_system = true
       and c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct')
  ) into v_detectou;

  -- Limpeza imediata (nao deixa fixture de sistema no banco).
  delete from public.access_role_capabilities where access_role_id = v_role;
  delete from public.access_roles where id = v_role;

  if v_detectou is not true then
    raise exception '[FAIL] D: o predicado das guardas NAO detectou role de sistema com capability excepcional';
  end if;

  raise notice '[PASS] D: predicado das guardas detecta role DE SISTEMA com capability excepcional (migration recusaria)';
end $$;

-- ============================================================================
-- E/F — idempotencia e unicidade de `admin` x `cycle.manage`
-- ============================================================================
do $$
declare
  v_role constant uuid := 'c0000000-0000-4000-8000-0000000000f1';
  v_n integer;
  v_bundle integer;
begin
  select count(*) into v_n
    from public.access_role_capabilities m
    join public.capabilities c on c.id = m.capability_id
   where m.access_role_id = v_role and c.code = 'cycle.manage';

  if v_n <> 1 then
    raise exception '[FAIL] E/F: admin x cycle.manage deveria existir EXATAMENTE uma vez (encontrado %)', v_n;
  end if;

  select count(*) into v_bundle
    from public.access_role_capabilities where access_role_id = v_role;
  if v_bundle <> 9 then
    raise exception '[FAIL] E/F: bundle admin deveria ter 9 capabilities apos primeira execucao + reexecucao (tem %)', v_bundle;
  end if;

  if not exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_role and c.code = 'cycle.read'
  ) then
    raise exception '[FAIL] E/F: cycle.read saiu do bundle admin';
  end if;

  raise notice '[PASS] E/F: idempotencia provada — primeira execucao adiciona 1, reexecucao nao duplica (bundle = 9, cycle.manage presente 1x)';
end $$;

-- ============================================================================
-- G — catalogo intacto (nenhuma capability nova)
-- ============================================================================
do $$
declare
  v_total integer;
  v_cycle text[];
begin
  select count(*) into v_total from public.capabilities;
  if v_total <> 31 then
    raise exception '[FAIL] G: catalogo deveria ter 31 linhas, encontradas %', v_total;
  end if;

  select array_agg(code order by code) into v_cycle from public.capabilities where code like 'cycle.%';
  if v_cycle is distinct from array[
    'cycle.cancel','cycle.manage','cycle.period.correct','cycle.read','cycle.reopen'
  ]::text[] then
    raise exception '[FAIL] G: conjunto de capabilities de ciclo divergente: %', v_cycle;
  end if;

  raise notice '[PASS] G: catalogo intacto (31 linhas; 5 capabilities de ciclo; nenhuma nova)';
end $$;

-- ============================================================================
-- H — semantica compartilhada: proibicao restrita a roles DE SISTEMA
-- ============================================================================
do $$
declare
  v_sistema_com_excepcional integer;
  v_custom_com_excepcional integer;
begin
  -- Invariante que a migration garante: NENHUMA role de sistema com as tres.
  select count(*) into v_sistema_com_excepcional
    from public.access_role_capabilities m
    join public.access_roles r on r.id = m.access_role_id
    join public.capabilities c on c.id = m.capability_id
   where r.is_system = true
     and c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct');
  if v_sistema_com_excepcional <> 0 then
    raise exception '[FAIL] H: role de SISTEMA com capability excepcional de ciclo (%)', v_sistema_com_excepcional;
  end if;

  -- E o caminho legitimo segue ABERTO: pelo menos as 3 concessoes da role
  -- customizada deste cenario (outros cenarios de P3/P4 tambem concedem as
  -- excepcionais a roles de fixture NAO-sistema, o que e legitimo).
  select count(*) into v_custom_com_excepcional
    from public.access_role_capabilities m
    join public.access_roles r on r.id = m.access_role_id
    join public.capabilities c on c.id = m.capability_id
   where r.is_system = false
     and c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct');
  if v_custom_com_excepcional < 3 then
    raise exception '[FAIL] H: concessoes legitimas em roles customizadas deveriam permanecer (>= 3), encontradas %', v_custom_com_excepcional;
  end if;

  raise notice '[PASS] H: semantica D28 coerente — proibido apenas em roles de SISTEMA (0); roles customizadas preservadas (%)',
    v_custom_com_excepcional;
end $$;
