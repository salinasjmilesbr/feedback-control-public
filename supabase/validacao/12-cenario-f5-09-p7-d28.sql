-- ============================================================================
-- F5-09 P7 (Issue #202) — CENARIO D28: roles CUSTOMIZADAS com as tres
-- capabilities excepcionais de ciclo + reinicio do estado de idempotencia.
-- ----------------------------------------------------------------------------
-- PROVA (A/B/C): `cycle.cancel`, `cycle.reopen` e `cycle.period.correct` NAO
-- estao nos bundles de SISTEMA, mas continuam concediveis por configuracao
-- EXPLICITA em roles CUSTOMIZADAS (`is_system = false`). Este cenario cria uma
-- role customizada com as tres e a migration D28 e REAPLICADA em seguida pelo
-- CI: ela deve ACEITAR esse estado (guardas restritas a roles de sistema).
--
-- PROVA (E): o vinculo `admin` × `cycle.manage` e removido aqui para que a
-- reaplicacao da migration prove o caminho "primeira execucao" (adiciona
-- exatamente 1). A segunda reaplicacao (mesmo passo de CI) prova o caminho
-- "ja existia" (nao adiciona nada e nao falha) — F.
--
-- Fixture ISOLADA (prefixo `e7`), insert-once, sem tocar em dados de outros
-- cenarios. Executar como superuser local, antes da reaplicacao da migration.
-- ============================================================================

\set ON_ERROR_STOP on

-- Guarda de estado limpo (insert-once).
do $$
begin
  if exists (select 1 from public.access_roles where id = 'e7f00000-0000-4000-8000-0000000000f1') then
    raise exception '[FAIL] cenario D28 (F5-09 P7) ja aplicado: role customizada e7f00000 existe';
  end if;
  if exists (select 1 from public.organizations where id = 'e7a00000-0000-4000-8000-0000000000a1') then
    raise exception '[FAIL] cenario D28 (F5-09 P7) ja aplicado: organizacao e7a00000 existe';
  end if;
end $$;

-- Organizacao sintetica do cenario.
insert into public.organizations (id, name)
values ('e7a00000-0000-4000-8000-0000000000a1', 'Organizacao D28 P7');

-- Role CUSTOMIZADA (NAO-sistema) com as tres capabilities EXCEPCIONAIS.
insert into public.access_roles (id, name, status, is_system, organization_id, version)
values (
  'e7f00000-0000-4000-8000-0000000000f1',
  'd28_custom_ciclos_p7',
  'active',
  false,
  'e7a00000-0000-4000-8000-0000000000a1',
  0
);

insert into public.access_role_capabilities (access_role_id, capability_id)
select 'e7f00000-0000-4000-8000-0000000000f1', c.id
  from public.capabilities c
 where c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct');

-- Prova imediata (A/B/C): as tres concessoes existem na role customizada.
do $$
declare
  v_n integer;
begin
  select count(*) into v_n
    from public.access_role_capabilities m
    join public.capabilities c on c.id = m.capability_id
   where m.access_role_id = 'e7f00000-0000-4000-8000-0000000000f1'
     and c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct');

  if v_n <> 3 then
    raise exception '[FAIL] cenario D28: role customizada deveria ter as 3 capabilities excepcionais (tem %)', v_n;
  end if;

  raise notice '[PASS] cenario D28: role CUSTOMIZADA (nao-sistema) com cycle.cancel + cycle.reopen + cycle.period.correct';
end $$;

-- Estado de idempotencia (E): remove `admin` x `cycle.manage` para que a
-- reaplicacao da migration seja a PRIMEIRA insercao.
delete from public.access_role_capabilities
 where access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
   and capability_id = (select id from public.capabilities where code = 'cycle.manage');

do $$
begin
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
       and c.code = 'cycle.manage'
  ) then
    raise exception '[FAIL] cenario D28: vinculo admin x cycle.manage deveria ter sido removido (setup E)';
  end if;

  raise notice '[PASS] cenario D28: estado E preparado (admin x cycle.manage ausente) e role customizada com as 3 excepcionais';
end $$;
