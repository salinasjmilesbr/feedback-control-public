-- ============================================================================
-- F5-09 P6 — descricao ADITIVA da capability `cycle.cancel` (D8 / Q-F5-09-1)
-- ----------------------------------------------------------------------------
-- A P6 amplia o `domainState` de `cycle.cancel` de {ATIVO} para {PLANEJADO,
-- ATIVO} (D8 ratificada na Q-F5-09-1). O catalogo F5-04 descrevia a capability
-- apenas como "Cancelar ciclo ATIVO"; esta migration atualiza SOMENTE a
-- descricao (fonte de verdade do catalogo no PostgreSQL).
--
-- NAO faz (e o guard final prova):
--   - nenhuma capability nova nem remocao fisica (F5-04 D14);
--   - nenhuma alteracao de nome, status, `grantable_via_role` ou `deprecated`;
--   - nenhuma alteracao de BUNDLE/ROLE: `cycle.manage` entra aditivamente no
--     bundle `admin` apenas na D28 (fase P7), e `cycle.cancel`/`cycle.reopen`/
--     `cycle.period.correct` permanecem fora dele;
--   - nenhuma alteracao de schema, RLS, RPC, tabela ou coluna.
-- ============================================================================

do $$
declare
  v_antes integer;
  v_descricao text;
  v_novo constant text := 'Cancelar ciclo PLANEJADO ou ATIVO (fluxo excepcional auditavel).';
  v_antigo constant text := 'Cancelar ciclo ATIVO (fluxo excepcional auditavel).';
begin
  -- (1) Preflight: a capability existe, esta ativa e concedivel por role.
  select description into v_descricao
    from public.capabilities
   where code = 'cycle.cancel' and status = 'active' and deprecated = false;

  if v_descricao is null then
    raise exception '[FAIL] F5-09 P6: capability cycle.cancel ausente/inativa/depreciada';
  end if;

  if v_descricao not in (v_antigo, v_novo) then
    raise exception '[FAIL] F5-09 P6: descricao inesperada de cycle.cancel: %', v_descricao;
  end if;

  if not exists (
    select 1 from public.capabilities
     where code = 'cycle.cancel' and grantable_via_role
  ) then
    raise exception '[FAIL] F5-09 P6: cycle.cancel deveria permanecer concedivel por role';
  end if;

  -- (2) Preflight: NENHUMA role/bundle concede capability de gestao de ciclo
  -- nesta fase (D28 pertence a P7). Falha fechado se o estado divergir.
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where c.code in ('cycle.manage', 'cycle.cancel', 'cycle.reopen', 'cycle.period.correct')
  ) then
    raise exception '[FAIL] F5-09 P6: bundle/role nao pode conceder capabilities de ciclo nesta fase (D28 e P7)';
  end if;

  select count(*) into v_antes from public.capabilities;

  -- (3) Atualizacao ADITIVA da descricao (idempotente: so grava se divergir).
  update public.capabilities
     set description = v_novo
   where code = 'cycle.cancel' and description <> v_novo;

  -- (4) Guarda final fail-closed.
  if (select count(*) from public.capabilities) <> v_antes then
    raise exception '[FAIL] F5-09 P6: catalogo de capabilities mudou de tamanho (% -> %)',
      v_antes, (select count(*) from public.capabilities);
  end if;

  if (select description from public.capabilities where code = 'cycle.cancel') <> v_novo then
    raise exception '[FAIL] F5-09 P6: descricao de cycle.cancel nao foi atualizada';
  end if;

  if exists (
    select 1 from public.capabilities
     where code = 'cycle.cancel'
       and (name <> 'Cancelar ciclos' or status <> 'active'
            or not grantable_via_role or deprecated)
  ) then
    raise exception '[FAIL] F5-09 P6: atributos de cycle.cancel alterados indevidamente';
  end if;

  if exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where c.code in ('cycle.manage', 'cycle.cancel', 'cycle.reopen', 'cycle.period.correct')
  ) then
    raise exception '[FAIL] F5-09 P6: bundle/role passou a conceder capabilities de ciclo';
  end if;

  raise notice '[PASS] F5-09 P6: descricao de cycle.cancel ampliada para {PLANEJADO, ATIVO} sem capability nova e sem bundle';
end $$;
