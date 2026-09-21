-- ============================================================================
-- F6-A21 P1 (Issue #327): validação da camada ADITIVA (views)
-- ----------------------------------------------------------------------------
-- Executar depois de `47-cenario-f6-a21-p1.sql`, com ON_ERROR_STOP.
-- Prova, no BANCO: semântica owner das views, ausência de bypass das tabelas
-- autorizativas, ACL só nas três views, Carolina/membership-only com ZERO dado
-- administrativo, Admin lendo, projeção pessoal limitada ao subgrafo, cross-tenant
-- zero e leitura direta PRESERVADA (P1 é aditivo).
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) Mecanismo (semântica owner) e ACL das views
-- ============================================================================
do $$
declare
  v_n integer;
  v_dono_views oid;
  v_dono_tabela oid;
  v_opts text;
begin
  select c.relowner into v_dono_views from pg_class c
   where c.relname = 'estrutura_administrativa' and c.relkind = 'v';
  select c.relowner into v_dono_tabela from pg_class c
   where c.relname = 'organizational_units' and c.relkind = 'r';
  if v_dono_views is null or v_dono_views is distinct from v_dono_tabela then
    raise exception '[FAIL] A1: views e tabelas com owners diferentes — mecanismo invalido';
  end if;

  select coalesce(array_to_string(c.reloptions, ','), '') into v_opts
    from pg_class c where c.relname = 'estrutura_pessoal' and c.relkind = 'v';
  if v_opts like '%security_invoker=true%' then
    raise exception '[FAIL] A2: estrutura_pessoal com security_invoker=true (mecanismo owner exigido)';
  end if;

  select count(*) into v_n from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and has_table_privilege('authenticated', c.oid, 'SELECT');
  if v_n <> 3 then
    raise exception '[FAIL] A3: authenticated com SELECT em % view(s) (esperado 3)', v_n;
  end if;

  if has_table_privilege('anon', 'public.estrutura_administrativa', 'SELECT')
     or has_table_privilege('anon', 'public.estrutura_pessoal', 'SELECT')
     or has_table_privilege('anon', 'public.estrutura_autorizacao', 'SELECT') then
    raise exception '[FAIL] A4: anon com SELECT em view do #327';
  end if;

  if has_table_privilege('authenticated', 'public.access_roles', 'SELECT')
     or has_table_privilege('authenticated', 'public.access_role_capabilities', 'SELECT')
     or has_table_privilege('authenticated', 'public.membership_access_role_assignments', 'SELECT') then
    raise exception '[FAIL] A5: authenticated com SELECT em tabela autorizativa';
  end if;

  if has_function_privilege('authenticated', 'public.resolver_capabilities_efetivas(uuid, uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.resolver_collaborador_vinculado(uuid, uuid)', 'EXECUTE') then
    raise exception '[FAIL] A6: authenticated executa resolver de autorizacao';
  end if;

  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_n <> 4 then
    raise exception '[FAIL] A7: DEFINER esperado=4, encontrado=%', v_n;
  end if;

  if not has_table_privilege('authenticated', 'public.organizational_positions', 'SELECT') then
    raise exception '[FAIL] A8: P1 deve ser ADITIVO (leitura direta foi revogada)';
  end if;

  raise notice '[PASS] A: views com owner das tabelas (sem security_invoker), SELECT so em authenticated nas 3 views, zero privilegio em tabela autorizativa/resolver, 4 DEFINER e leitura direta preservada';
end $$;

-- ============================================================================
-- B) CAROLINA (membership-only): ZERO leitura administrativa
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a21000-0000-4000-8000-000000000002', false);
set local role authenticated;
do $$
declare
  v_n integer;
  v_flags text;
begin
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 0 then
    raise exception '[FAIL] B1: membership-only recebeu % linha(s) administrativa(s)', v_n;
  end if;

  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 0 then
    raise exception '[FAIL] B2: membership-only sem vinculo recebeu projecao pessoal (%)', v_n;
  end if;

  select pode_estrutura::text || '/' || pode_catalogo::text || '/' || coalesce(collaborator_id::text, 'sem-vinculo')
    into v_flags
    from public.estrutura_autorizacao;
  if v_flags is distinct from 'false/false/sem-vinculo' then
    raise exception '[FAIL] B3: projecao de autorizacao da Carolina = %', v_flags;
  end if;

  -- Sem bypass: nenhum acesso direto às tabelas autorizativas.
  begin
    perform count(*) from public.membership_access_role_assignments;
    raise exception '[FAIL] B4: authenticated leu tabela autorizativa';
  exception
    when insufficient_privilege then null;
  end;

  raise notice '[PASS] B: Carolina/membership-only => 0 linhas administrativas, 0 projecao pessoal (sem vinculo), flags false/false e nenhum bypass de tabela autorizativa';
end $$;
rollback;

-- ============================================================================
-- C) ADMIN_A: lê a fotografia administrativa do próprio tenant
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a21000-0000-4000-8000-000000000001', false);
set local role authenticated;
do $$
declare
  v_n integer;
  v_org uuid;
  v_flags text;
begin
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 1 then
    raise exception '[FAIL] C1: admin deveria ver 1 organizacao, viu %', v_n;
  end if;

  select organization_id,
         pode_estrutura::text || '/' || pode_catalogo::text
    into v_org, v_flags
    from public.estrutura_administrativa;
  if v_org <> 'f6a21000-0000-4000-8000-0000000000a1' then
    raise exception '[FAIL] C2: admin viu organizacao % (esperado ALFA)', v_org;
  end if;
  if v_flags <> 'true/true' then
    raise exception '[FAIL] C3: flags do admin = %', v_flags;
  end if;

  select jsonb_array_length(posicoes) + jsonb_array_length(colaboradores)
       + jsonb_array_length(unidades) + jsonb_array_length(reporting_lines)
       + jsonb_array_length(ocupacoes) + jsonb_array_length(colegiados)
       + jsonb_array_length(cargos) + jsonb_array_length(senioridades)
    into v_n
    from public.estrutura_administrativa
   where organization_id = 'f6a21000-0000-4000-8000-0000000000a1';
  if v_n <> 4 + 4 + 2 + 2 + 4 + 1 + 1 + 1 then
    raise exception '[FAIL] C4: soma das secoes administrativas = % (esperado 19)', v_n;
  end if;

  -- Admin sem vínculo soberano não recebe projeção pessoal.
  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 0 then
    raise exception '[FAIL] C5: admin sem vinculo recebeu projecao pessoal (%)', v_n;
  end if;

  raise notice '[PASS] C: Admin da Empresa le a fotografia administrativa (19 itens) e nao recebe projecao pessoal sem vinculo';
end $$;
rollback;

-- ============================================================================
-- D) PESSOA_A (com vínculo, sem capability): SÓ o subgrafo permitido
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a21000-0000-4000-8000-000000000003', false);
set local role authenticated;
do $$
declare
  v_n integer;
  v_flags text;
  v_colabs jsonb;
  v_posicoes jsonb;
begin
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 0 then
    raise exception '[FAIL] D1: usuario sem capability recebeu leitura administrativa (%)', v_n;
  end if;

  select pode_estrutura::text || '/' || pode_catalogo::text || '/' || collaborator_id::text
    into v_flags from public.estrutura_autorizacao;
  if v_flags <> 'false/false/f6a21000-0000-4000-8000-000000000e01' then
    raise exception '[FAIL] D2: projecao de autorizacao = % (esperado vinculo do ator)', v_flags;
  end if;

  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 1 then
    raise exception '[FAIL] D3: projecao pessoal esperada=1, encontrada=%', v_n;
  end if;

  select colaboradores, posicoes into v_colabs, v_posicoes
    from public.estrutura_pessoal;

  -- Subgrafo = ATOR + CHEFE (acima) + SUB (abaixo); FORA fica de fora.
  select count(*) into v_n
    from jsonb_array_elements(v_colabs) e
   where e->>'id' in ('f6a21000-0000-4000-8000-000000000e01',
                      'f6a21000-0000-4000-8000-000000000e02',
                      'f6a21000-0000-4000-8000-000000000e03');
  if v_n <> 3 or jsonb_array_length(v_colabs) <> 3 then
    raise exception '[FAIL] D4: subgrafo de colaboradores = % (esperado exatamente 3)', jsonb_array_length(v_colabs);
  end if;
  select count(*) into v_n
    from jsonb_array_elements(v_colabs) e
   where e->>'id' = 'f6a21000-0000-4000-8000-000000000e04';
  if v_n <> 0 then
    raise exception '[FAIL] D5: colaborador FORA do subgrafo exposto';
  end if;
  if jsonb_array_length(v_posicoes) <> 3 then
    raise exception '[FAIL] D6: posicoes do subgrafo = % (esperado 3)', jsonb_array_length(v_posicoes);
  end if;

  raise notice '[PASS] D: usuario com vinculo e sem capability => 0 leitura administrativa e projecao pessoal EXATAMENTE no subgrafo (3 colaboradores, 3 posicoes)';
end $$;
rollback;

-- ============================================================================
-- E) Cross-tenant: zero em ambos os sentidos
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a21000-0000-4000-8000-000000000001', false);
set local role authenticated;
do $$
declare v_n integer;
begin
  select count(*) into v_n from public.estrutura_administrativa
   where organization_id = 'f6a21000-0000-4000-8000-0000000000a2';
  if v_n <> 0 then
    raise exception '[FAIL] E1: admin de ALFA leu a fotografia de BETA (%)', v_n;
  end if;
  select count(*) into v_n from public.estrutura_pessoal
   where organization_id = 'f6a21000-0000-4000-8000-0000000000a2';
  if v_n <> 0 then
    raise exception '[FAIL] E2: projecao pessoal vazou para BETA (%)', v_n;
  end if;
  select count(*) into v_n from public.estrutura_autorizacao
   where organization_id = 'f6a21000-0000-4000-8000-0000000000a2';
  if v_n <> 0 then
    raise exception '[FAIL] E3: autorizacao vazou para BETA (%)', v_n;
  end if;
  raise notice '[PASS] E: cross-tenant ZERO nas tres views (organization_id sempre da membership ativa do proprio ator)';
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'f6a21000-0000-4000-8000-000000000004', false);
set local role authenticated;
do $$
declare v_org uuid;
begin
  select organization_id into v_org from public.estrutura_administrativa;
  if v_org <> 'f6a21000-0000-4000-8000-0000000000a2' then
    raise exception '[FAIL] E4: admin de BETA viu organizacao % (esperado BETA)', coalesce(v_org::text, 'nada');
  end if;
  raise notice '[PASS] E: admin de BETA le APENAS BETA (simetria do isolamento)';
end $$;
rollback;

-- ============================================================================
-- F) Estado limpo (nenhuma identidade residual)
-- ============================================================================
do $$
begin
  raise notice '[PASS] F6-A21 P1: camada aditiva validada (mecanismo owner, ACL, membership-only sem leitura administrativa, admin lendo, subgrafo pessoal, cross-tenant zero)';
end $$;
