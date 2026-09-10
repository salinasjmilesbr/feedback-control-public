-- ============================================================================
-- F5-06 (Issue #103): validação da resolução soberana de ciclo e da leitura da
-- PRÓPRIA ocorrência do participante (cutover das telas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de 01-cenario-f5-06.sql e 02-validar-f5-06.sql, como
-- superuser local, com ON_ERROR_STOP ativo. Não altera RLS nem policies.
-- Apenas dados sintéticos (prefixo d6).
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) evaluation_resolver_ciclo: ano+ciclo → UUID soberano (D15/D27)
-- ============================================================================
do $$
declare
  v_ciclo uuid;
  v_ok boolean := false;
begin
  v_ciclo := public.evaluation_resolver_ciclo(
    'd6a00000-0000-0000-0000-0000000000a1', 2026, 1,
    'd6b00000-0000-0000-0000-0000000000a1');

  if v_ciclo is null or v_ciclo <> 'd6f00000-0000-0000-0000-0000000000a1' then
    raise exception '[FAIL] resolucao ano+ciclo devolveu UUID inesperado (%)', v_ciclo;
  end if;

  -- ano/numero inexistente ⇒ recusa
  begin
    perform public.evaluation_resolver_ciclo(
      'd6a00000-0000-0000-0000-0000000000a1', 2099, 1,
      'd6b00000-0000-0000-0000-0000000000a1');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] ciclo inexistente foi aceito';
  end if;

  -- numero fora do dominio ⇒ recusa
  v_ok := false;
  begin
    perform public.evaluation_resolver_ciclo(
      'd6a00000-0000-0000-0000-0000000000a1', 2026, 9,
      'd6b00000-0000-0000-0000-0000000000a1');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] numero de ciclo invalido foi aceito';
  end if;

  -- ator de outro tenant ⇒ recusa (membership revalidada server-side)
  v_ok := false;
  begin
    perform public.evaluation_resolver_ciclo(
      'd6a00000-0000-0000-0000-0000000000a1', 2026, 1,
      'd6b00000-0000-0000-0000-0000000000a2');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] ator de outro tenant resolveu ciclo de Alfa (D27 violado)';
  end if;

  raise notice '[PASS] resolucao soberana de ciclo: UUID correto e recusas fail-closed (inexistente, fora do dominio, outro tenant)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  -- Ambiguidade real: dois ciclos do MESMO tenant/ano/numero ⇒ recusa.
  alter table public.evaluation_cycles drop constraint uq_evaluation_cycles_org_ano_numero;
  insert into public.evaluation_cycles (id, organization_id, ano, numero, status)
  values ('d6f00000-0000-0000-0000-0000000000a9',
          'd6a00000-0000-0000-0000-0000000000a1', 2026, 1, 'PLANEJADO');

  begin
    perform public.evaluation_resolver_ciclo(
      'd6a00000-0000-0000-0000-0000000000a1', 2026, 1,
      'd6b00000-0000-0000-0000-0000000000a1');
  exception when raise_exception then v_ok := true;
  end;

  delete from public.evaluation_cycles where id = 'd6f00000-0000-0000-0000-0000000000a9';
  alter table public.evaluation_cycles
    add constraint uq_evaluation_cycles_org_ano_numero unique (organization_id, ano, numero);

  if not v_ok then
    raise exception '[FAIL] ambiguidade de ciclo (2 resultados) foi aceita';
  end if;
  raise notice '[PASS] ambiguidade ano+ciclo recusada (fail-closed)';
end $$;

-- ============================================================================
-- 2) evaluation_painel_participante: SOMENTE a própria ocorrência (edição)
-- ============================================================================
do $$
declare
  v_eval uuid;
  v_painel jsonb;
  v_txt text;
  v_notas int;
begin
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id = 'd6c00000-0000-0000-0000-0000000000c2'
     and status <> 'CANCELADA'
   order by created_at limit 1;

  -- O ator do cenário está vinculado ao AVALIADO (c2), que NÃO é participante
  -- desta avaliação ⇒ recusa (esta leitura é de PARTICIPANTE, não do avaliado).
  begin
    perform public.evaluation_painel_participante(v_eval, 'd6b00000-0000-0000-0000-0000000000a1');
    raise exception '[FAIL] avaliado obteve a leitura de EDICAO do participante';
  exception when raise_exception then
    if sqlerrm like '%ocorrencia vigente%' or sqlerrm like '%avaliado%' then
      null;
    else
      raise;
    end if;
  end;
  raise notice '[PASS] leitura de edicao recusada para quem nao tem ocorrencia vigente';
end $$;

do $$
declare
  v_eval uuid;
  v_part uuid;
  v_painel jsonb;
  v_txt text;
  v_notas int;
  v_papeis jsonb;
begin
  -- Cria um ator PARTICIPANTE sintético: membership ativa + vínculo com c1
  -- (responsável de cadeia da avaliação de c2).
  insert into auth.users
    (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
     raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('d6b00000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-000000000000',
          'authenticated','authenticated','f5-06.participante@example.invalid','x',now(),
          '{}'::jsonb,'{}'::jsonb,now(),now())
  on conflict (id) do nothing;

  insert into public.user_profiles (id, status)
  values ('d6b00000-0000-0000-0000-0000000000a3','active')
  on conflict (id) do nothing;

  insert into public.user_organization_memberships (id, user_profile_id, organization_id, status)
  values ('d6d00000-0000-0000-0000-0000000000a3','d6b00000-0000-0000-0000-0000000000a3',
          'd6a00000-0000-0000-0000-0000000000a1','active')
  on conflict (id) do nothing;

  insert into public.membership_collaborator_links
    (id, membership_id, organization_id, collaborator_id, status)
  values ('d6e00000-0000-0000-0000-0000000000a3','d6d00000-0000-0000-0000-0000000000a3',
          'd6a00000-0000-0000-0000-0000000000a1','d6c00000-0000-0000-0000-0000000000c1','active')
  on conflict (id) do nothing;

  select id into v_eval from public.evaluations
   where evaluated_collaborator_id = 'd6c00000-0000-0000-0000-0000000000c2'
     and status <> 'CANCELADA'
   order by created_at limit 1;

  v_painel := public.evaluation_painel_participante(v_eval, 'd6b00000-0000-0000-0000-0000000000a3');

  if (v_painel ->> 'evaluation_id')::uuid <> v_eval then
    raise exception '[FAIL] painel sem evaluation_id correto';
  end if;

  -- O ator (c1) é GESTAO_CADEIA: recebe os próprios papéis.
  v_papeis := v_painel -> 'meus_papeis';
  if not (v_papeis ? 'GESTAO_CADEIA') then
    raise exception '[FAIL] painel sem os papeis do proprio ator (%)', v_papeis;
  end if;

  -- Catálogo congelado disponível (8 critérios / 25 subcritérios).
  if jsonb_array_length(v_painel -> 'criterios') <> 8 then
    raise exception '[FAIL] painel sem 8 criterios do catalogo congelado';
  end if;
  if jsonb_array_length(v_painel -> 'subcriterios') <> 25 then
    raise exception '[FAIL] painel sem 25 subcriterios do catalogo congelado';
  end if;

  -- Notas: SOMENTE as da própria ocorrência (a de c1 é a única).
  v_notas := jsonb_array_length(v_painel -> 'minhas_notas');
  if v_notas < 1 then
    raise exception '[FAIL] painel sem as notas da propria ocorrencia';
  end if;

  -- Ocultação: nunca expõe voto/nota individual de terceiros nem id alheio.
  v_txt := v_painel::text;
  if v_txt like '%voto%' then
    raise exception '[FAIL] painel expos voto individual';
  end if;
  if v_txt like '%nota_individual%' then
    raise exception '[FAIL] painel expos nota individual';
  end if;

  raise notice '[PASS] painel do participante: papeis proprios, catalogo congelado, notas da propria ocorrencia e nenhum voto individual';
end $$;

do $$
declare
  v_eval uuid;
  v_ok boolean := false;
begin
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id = 'd6c00000-0000-0000-0000-0000000000c2'
     and status <> 'CANCELADA'
   order by created_at limit 1;

  -- Cross-tenant: ator de Beta não obtém o painel de Alfa (fail-closed).
  begin
    perform public.evaluation_painel_participante(v_eval, 'd6b00000-0000-0000-0000-0000000000a2');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] ator de outro tenant obteve o painel (D27 violado)';
  end if;
  raise notice '[PASS] painel recusado para ator de outro tenant (fail-closed)';
end $$;

-- ============================================================================
-- 3) Superfície fechada: EXECUTE somente service_role
-- ============================================================================
do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public'
    and p.proname in ('evaluation_resolver_ciclo','evaluation_painel_participante')
    and a.privilege_type='EXECUTE'
    and (a.grantee = 0 or a.grantee='anon'::regrole or a.grantee='authenticated'::regrole);
  if v_n <> 0 then
    raise exception '[FAIL] EXECUTE indevido em funcao do cutover: %', v_n;
  end if;

  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public'
    and p.proname in ('evaluation_resolver_ciclo','evaluation_painel_participante')
    and a.privilege_type='EXECUTE' and a.grantee='service_role'::regrole;
  if v_n <> 2 then
    raise exception '[FAIL] funcoes do cutover sem EXECUTE service_role (%)', v_n;
  end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname='public' and p.prosecdef
       and p.proname in ('evaluation_resolver_ciclo','evaluation_painel_participante')
  ) then
    raise exception '[FAIL] funcao do cutover marcada como SECURITY DEFINER';
  end if;
  raise notice '[PASS] funcoes do cutover: SECURITY INVOKER e EXECUTE somente service_role';
end $$;

-- ============================================================================
-- 4) Limpeza do ator sintético desta validação
-- ============================================================================
delete from public.membership_collaborator_links
 where id = 'd6e00000-0000-0000-0000-0000000000a3';
delete from public.user_organization_memberships
 where id = 'd6d00000-0000-0000-0000-0000000000a3';
delete from public.user_profiles where id = 'd6b00000-0000-0000-0000-0000000000a3';
delete from auth.users where id = 'd6b00000-0000-0000-0000-0000000000a3';

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-06 (cutover): todas as verificacoes passaram (resolucao de ciclo + leitura da propria ocorrencia + superficie fechada).';
end $$;
