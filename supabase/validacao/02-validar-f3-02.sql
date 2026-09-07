-- ============================================================================
-- F3-02 (Issue #79): validação automatizada — catálogos de funções e
-- senioridades (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-02.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-02.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-02.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; qualquer falha levanta
-- exceção e aborta com código de saída não-zero. O script NÃO toca projeto
-- remoto, NÃO altera policies e remove ao final os dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Estrutura: tabelas esperadas e ausência de entidades antecipadas
-- ============================================================================

do $$
begin
  if exists (
    select 1
    from pg_tables t
    where t.schemaname = 'public'
      and t.tablename not in (
        'collaborator_identifiers',
        'collaborator_status_periods',
        'collaborators',
        'job_roles',
        'organizations',
        'seniority_levels',
        'user_organization_memberships',
        'user_profiles'
      )
  ) then
    raise exception '[FAIL] tabela inesperada no schema public (entidade fora do escopo F3-02)';
  end if;
  raise notice '[PASS] schema public contém somente as tabelas esperadas (F2 + F3-01 + F3-02)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_tables t
    where t.schemaname = 'public'
      and t.tablename in (
        'organizational_positions', 'organizational_units', 'reporting_lines',
        'direct_reports', 'position_occupancies', 'occupancies',
        'job_role_seniorities', 'role_seniorities', 'capabilities',
        'permissions', 'access_roles', 'hierarchy_levels', 'career_levels'
      )
  ) then
    raise exception '[FAIL] tabela de posicao/reporting/capability/juncao antecipada';
  end if;
  raise notice '[PASS] nenhuma tabela de posicao/reporting line/capability/juncao antecipada';
end $$;

-- ----------------------------------------------------------------------------
-- 1.1 Colunas exatas das tabelas F3-02 (núcleo mínimo; sem code/ordem/rank)
-- ----------------------------------------------------------------------------

do $$
declare
  v_cols text[];
  v_esperado text[] := array['created_at', 'id', 'name', 'organization_id',
                             'status', 'updated_at', 'version']::text[];
  v_tabela text;
  v_tabelas text[] := array['job_roles', 'seniority_levels'];
begin
  foreach v_tabela in array v_tabelas loop
    select array_agg(column_name order by column_name)
      into v_cols
    from information_schema.columns
    where table_schema = 'public' and table_name = v_tabela;

    if v_cols is distinct from v_esperado then
      raise exception '[FAIL] %: colunas fora do nucleo minimo (id/organization_id/name/status/created_at/updated_at/version)', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] job_roles e seniority_levels possuem exatamente id/organization_id/name/status/created_at/updated_at/version';
end $$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name in ('job_roles', 'seniority_levels')
      and (
        lower(c.column_name) like '%order%' or lower(c.column_name) like '%rank%'
        or lower(c.column_name) like '%hierar%' or lower(c.column_name) like '%manager%'
        or lower(c.column_name) like '%parent%' or lower(c.column_name) like '%position%'
        or lower(c.column_name) like '%report%' or lower(c.column_name) like '%code%'
        or lower(c.column_name) like '%capab%' or lower(c.column_name) like '%level%'
      )
  ) then
    raise exception '[FAIL] coluna de ordem/rank/hierarquia/code/capability encontrada nos catalogos F3-02';
  end if;
  raise notice '[PASS] nenhuma coluna de ordenacao/rank/hierarquia/code/capability nos catalogos F3-02';
end $$;

-- ----------------------------------------------------------------------------
-- 1.2 Identidade técnica: UUID gerado, PK única por id; name não é identidade
-- ----------------------------------------------------------------------------

do $$
declare
  v_expr text;
  v_tabela text;
  v_tabelas text[] := array['job_roles', 'seniority_levels'];
begin
  foreach v_tabela in array v_tabelas loop
    select pg_get_expr(d.adbin, d.adrelid)
      into v_expr
    from pg_attrdef d
    where d.adrelid = (quote_ident('public') || '.' || quote_ident(v_tabela))::regclass
      and d.adnum = (
        select a.attnum
        from pg_attribute a
        where a.attrelid = d.adrelid and a.attname = 'id'
      );

    if v_expr is null or v_expr not like '%gen_random_uuid()%' then
      raise exception '[FAIL] %: id nao possui default gen_random_uuid()', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] id de job_roles e seniority_levels possui default gen_random_uuid() (UUID tecnico)';
end $$;

do $$
begin
  if exists (
    select 1
    from information_schema.key_column_usage k
    join information_schema.table_constraints tc
      on tc.constraint_catalog = k.constraint_catalog
     and tc.constraint_schema = k.constraint_schema
     and tc.constraint_name = k.constraint_name
     and tc.table_name = k.table_name
    where k.table_schema = 'public'
      and k.table_name in ('job_roles', 'seniority_levels')
      and tc.constraint_type = 'PRIMARY KEY'
      and k.column_name in ('name', 'organization_id', 'status')
  ) then
    raise exception '[FAIL] name/status compoem alguma PK dos catalogos F3-02';
  end if;
  raise notice '[PASS] PKs de job_roles e seniority_levels sao compostas somente por id (uuid); name nao e identidade tecnica';
end $$;

-- ----------------------------------------------------------------------------
-- 1.3 Constraints, FKs (somente para organizations) e triggers
-- ----------------------------------------------------------------------------

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'pk_job_roles',
    'uq_job_roles_organization_name',
    'fk_job_roles_organizations',
    'ck_job_roles_name',
    'ck_job_roles_status',
    'pk_seniority_levels',
    'uq_seniority_levels_organization_name',
    'fk_seniority_levels_organizations',
    'ck_seniority_levels_name',
    'ck_seniority_levels_status'
  );
  if v_n <> 10 then
    raise exception '[FAIL] constraints esperadas da F3-02 ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] constraints pk/unique/fk/check esperadas presentes em job_roles e seniority_levels';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  where c.conrelid in ('public.job_roles'::regclass, 'public.seniority_levels'::regclass)
    and c.contype = 'f';
  if v_n <> 2 then
    raise exception '[FAIL] deveria haver exatamente 2 FKs (uma por catalogo para organizations)';
  end if;
  if exists (
    select 1
    from pg_constraint c
    where c.conrelid in ('public.job_roles'::regclass, 'public.seniority_levels'::regclass)
      and c.contype = 'f'
      and c.confrelid <> 'public.organizations'::regclass
  ) then
    raise exception '[FAIL] existe FK de catalogo apontando para tabela diferente de organizations';
  end if;
  raise notice '[PASS] FKs dos catalogos apontam somente para organizations (sem FK cruzada entre catalogos)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.confdeltype <> 'r'
    and c.conrelid in ('public.job_roles'::regclass, 'public.seniority_levels'::regclass);
  if v_n <> 0 then
    raise exception '[FAIL] existe FK sem ON DELETE RESTRICT nos catalogos F3-02';
  end if;
  raise notice '[PASS] FKs de job_roles e seniority_levels sao ON DELETE RESTRICT';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.confrelid in ('public.job_roles'::regclass, 'public.seniority_levels'::regclass);
  if v_n <> 0 then
    raise exception '[FAIL] existe dependencia (FK) referenciando os catalogos F3-02 (antecipacao de posicao/ocupacao)';
  end if;
  raise notice '[PASS] nenhuma tabela referencia job_roles/seniority_levels (uso futuro apenas por posicoes - F3-03)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_trigger t
  where not t.tgisinternal
    and t.tgrelid in ('public.job_roles'::regclass, 'public.seniority_levels'::regclass)
    and t.tgname in ('trg_job_roles_updated_at', 'trg_seniority_levels_updated_at');
  if v_n <> 2 then
    raise exception '[FAIL] triggers de updated_at esperados ausentes (% encontrados)', v_n;
  end if;
  raise notice '[PASS] triggers tecnicos de updated_at presentes em job_roles e seniority_levels';
end $$;

-- ----------------------------------------------------------------------------
-- 1.4 RLS habilitado e deny-by-default (estrutura)
-- ----------------------------------------------------------------------------

do $$
declare
  v_tabela text;
  v_tabelas text[] := array['job_roles', 'seniority_levels'];
begin
  foreach v_tabela in array v_tabelas loop
    perform 1
    from pg_class c
    where c.oid = (quote_ident('public') || '.' || quote_ident(v_tabela))::regclass
      and c.relrowsecurity = true;
    if not found then
      raise exception '[FAIL] RLS nao habilitado em %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] RLS habilitado em job_roles e seniority_levels';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename in ('job_roles', 'seniority_levels')
  ) then
    raise exception '[FAIL] existe policy nos catalogos F3-02 (deny-by-default violado)';
  end if;
  raise notice '[PASS] zero policies em job_roles e seniority_levels (deny-by-default estrutural)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('organizations', 'user_profiles', 'user_organization_memberships',
                        'collaborators', 'collaborator_identifiers', 'collaborator_status_periods')
      and c.relrowsecurity = false
  ) then
    raise exception '[FAIL] RLS de tabelas pre-existentes (F2/F3-01) foi enfraquecido';
  end if;
  raise notice '[PASS] RLS das tabelas pre-existentes (F2 e F3-01) permanece habilitado';
end $$;

-- ============================================================================
-- 2) Cenário: configuração independente por organização
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1';
  if v_n <> 9 then
    raise exception '[FAIL] job_roles da org Alfa esperado=9 (8 ativos + 1 desativado), encontrado=%', v_n;
  end if;
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1'
    and status = 'active';
  if v_n <> 8 then
    raise exception '[FAIL] job_roles ativos da org Alfa esperado=8, encontrado=%', v_n;
  end if;
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000b1';
  if v_n <> 3 then
    raise exception '[FAIL] job_roles da org Beta esperado=3, encontrado=%', v_n;
  end if;
  raise notice '[PASS] catalogos de funcoes pertencem a organizacao correta (Alfa=9, Beta=3)';
end $$;

do $$
declare
  v_n int;
begin
  -- Os oito conceitos do piloto são representáveis como linhas do catálogo
  -- (categorias sintéticas; nada de sequência/rank codificado).
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1'
    and name in (
      'Diretor', 'Gerente Senior', 'Gerente', 'Especialista',
      'Coordenador', 'Consultor', 'Analista', 'Estagiario'
    );
  if v_n <> 8 then
    raise exception '[FAIL] org Alfa deveria conter os oito conceitos do piloto como funcoes';
  end if;
  raise notice '[PASS] Diretor/Gerente Senior/Gerente/Especialista/Coordenador/Consultor/Analista/Estagiario representaveis (Alfa)';
end $$;

do $$
declare
  v_n int;
begin
  -- Beta usa subconjunto diferente: sem Diretor/Especialista/Coordenador/
  -- Gerente; com Analista/Consultor/Estagiario.
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000b1'
    and name in ('Diretor', 'Gerente Senior', 'Gerente', 'Especialista', 'Coordenador');
  if v_n <> 0 then
    raise exception '[FAIL] org Beta nao deveria conter as funcoes do subconjunto de Alfa';
  end if;
  raise notice '[PASS] organizacao Beta usa subconjunto diferente de funcoes (configuracao independente)';
end $$;

do $$
declare
  v_n int;
begin
  -- Mesmo nome de funcao em organizacoes diferentes é permitido (unique por org).
  select count(*) into v_n
  from public.job_roles
  where name = 'Analista';
  if v_n <> 2 then
    raise exception '[FAIL] Analista deveria existir nas duas organizacoes (esperado 2), encontrado %', v_n;
  end if;
  select count(*) into v_n
  from public.job_roles
  where name = 'Estagiario';
  if v_n <> 2 then
    raise exception '[FAIL] Estagiario deveria existir nas duas organizacoes (esperado 2), encontrado %', v_n;
  end if;
  raise notice '[PASS] mesmo nome de funcao permitido em organizacoes diferentes (unique por organization_id)';
end $$;

do $$
declare
  v_n int;
  v_nomes text[];
begin
  select count(*) into v_n
  from public.seniority_levels
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1';
  if v_n <> 3 then
    raise exception '[FAIL] seniorities da org Alfa esperado=3, encontrado=%', v_n;
  end if;

  select array_agg(name order by name) into v_nomes
  from public.seniority_levels
  where organization_id = 'f4a00000-0000-0000-0000-0000000000b1';
  if v_nomes is distinct from array['Senior']::text[] then
    raise exception '[FAIL] org Beta deveria ter somente a senioridade Senior';
  end if;
  raise notice '[PASS] organizacoes configuram senioridades diferentes (Alfa: Junior/Pleno/Senior; Beta: Senior)';
end $$;

-- ============================================================================
-- 3) Independência função x senioridade e ausência de hierarquia implícita
-- ============================================================================

do $$
declare
  v_n int;
begin
  -- Estruturalmente, Analista Junior/Pleno/Senior = job_role Analista +
  -- seniorities Junior/Pleno/Senior (linhas independentes).
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1'
    and name = 'Analista';
  if v_n <> 1 then
    raise exception '[FAIL] deveria existir exatamente 1 funcao Analista em Alfa';
  end if;
  select count(*) into v_n
  from public.seniority_levels
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1'
    and name in ('Junior', 'Pleno', 'Senior');
  if v_n <> 3 then
    raise exception '[FAIL] Alfa deveria ter as senioridades Junior, Pleno e Senior';
  end if;
  -- Nenhum nome composto obrigatorio (ex.: Analista Junior como funcao) no
  -- cenario: a combinacao é representada por duas entidades, nao por degraus.
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1'
    and name in ('Analista Junior', 'Analista Pleno', 'Analista Senior');
  if v_n <> 0 then
    raise exception '[FAIL] combinacao Analista+senioridade nao deve virar funcao composta no cenario';
  end if;
  raise notice '[PASS] Analista Junior/Pleno/Senior representado como funcao + senioridades independentes (sem degraus)';
end $$;

do $$
declare
  v_n int;
begin
  -- Especialista é função sem qualquer atributo de lideranca/equipe e sem
  -- hierarquia (colunas exatas ja verificadas; FK nenhuma para estrutura).
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1'
    and name = 'Especialista'
    and status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] Especialista deveria existir como funcao ativa em Alfa';
  end if;
  raise notice '[PASS] Especialista representavel como funcao sem equipe/lideranca implicita';
end $$;

do $$
declare
  v_n int;
begin
  -- Estagiario é função válida mesmo sem ocorrência nos dados piloto: os
  -- catalogos não dependem de colaboradores (nenhuma FK para collaborators) e
  -- a linha existe nas duas organizações sintéticas.
  select count(*) into v_n
  from public.job_roles
  where name = 'Estagiario';
  if v_n <> 2 then
    raise exception '[FAIL] Estagiario deveria ser representavel sem ocorrencia piloto';
  end if;
  raise notice '[PASS] Estagiario representavel como funcao (sem exigir ocorrencia em dados piloto)';
end $$;

do $$
declare
  v_n int;
begin
  -- Duas ocorrências futuras da mesma função não recebem hierarquia implícita:
  -- o catalogo é só de tipos; não existe coluna/tabela que ordene, ranqueie ou
  -- ancore ocorrencias a um nível (unicidade restringe apenas o nome do
  -- catalogo por organização).
  select count(*) into v_n
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'job_roles'
    and lower(column_name) in ('parent_id', 'rank', 'level', 'sort_order',
                               'display_order', 'direct_report_to');
  if v_n <> 0 then
    raise exception '[FAIL] coluna de ancoragem hierarquica encontrada em job_roles';
  end if;
  raise notice '[PASS] nenhuma ancoragem hierarquica para ocorrencias futuras da mesma funcao';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.job_roles'::regclass
      and c.contype = 'f'
      and c.confrelid = 'public.job_roles'::regclass
  ) then
    raise exception '[FAIL] auto-referencia (parent) em job_roles — hierarquia implícita';
  end if;
  raise notice '[PASS] job_roles sem auto-referencia/rank (independente de hierarquia)';
end $$;

do $$
begin
  -- Independência de autorização: nenhum vínculo entre catálogos e
  -- autorização/Auth/membership/capability.
  if exists (
    select 1
    from pg_constraint c
    where c.contype = 'f'
      and (
        (c.conrelid in ('public.job_roles'::regclass, 'public.seniority_levels'::regclass)
         and c.confrelid in ('public.user_profiles'::regclass,
                             'public.user_organization_memberships'::regclass,
                             'auth.users'::regclass))
        or
        (c.confrelid in ('public.job_roles'::regclass, 'public.seniority_levels'::regclass)
         and c.conrelid in ('public.user_profiles'::regclass,
                            'public.user_organization_memberships'::regclass))
      )
  ) then
    raise exception '[FAIL] vinculo indevido entre catalogos e Auth/membership';
  end if;
  raise notice '[PASS] funcao/senioridade sem vinculo com Auth/membership/autorizacao';
end $$;

-- ============================================================================
-- 4) Desativação sem exclusão física + timestamps/version
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1'
    and name = 'Gerente Regional'
    and status = 'disabled';
  if v_n <> 1 then
    raise exception '[FAIL] Gerente Regional deveria existir como disabled (desativacao preserva registro)';
  end if;
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000a1'
    and name = 'Gerente'
    and status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] Gerente deveria permanecer active (desativacao nao afeta outros itens)';
  end if;
  raise notice '[PASS] desativacao (status disabled) preserva o registro; evolucao sem exclusao fisica';
end $$;

do $$
declare
  v_ver int;
begin
  select version into v_ver
  from public.job_roles
  where organization_id = 'f4a00000-0000-0000-0000-0000000000b1'
    and name = 'Analista';
  if v_ver <> 0 then
    raise exception '[FAIL] version default de job_role inserida deveria ser 0';
  end if;
  raise notice '[PASS] version default 0 nas linhas inseridas (convencao F1-02)';
end $$;

do $$
declare
  v_ts timestamptz;
  v_ver int;
  v_id uuid;
begin
  select id into v_id
  from public.seniority_levels
  where organization_id = 'f4a00000-0000-0000-0000-0000000000b1'
    and name = 'Senior';

  update public.seniority_levels
     set updated_at = '2020-01-01T00:00:00Z'
   where id = v_id;

  update public.seniority_levels
     set version = version + 1
   where id = v_id;

  select updated_at, version into v_ts, v_ver
  from public.seniority_levels
  where id = v_id;

  if v_ver <> 1 then
    raise exception '[FAIL] version deveria ser 1 apos uma atualizacao (encontrado %)', v_ver;
  end if;
  if v_ts is null or v_ts <= '2020-01-01T00:00:00Z' then
    raise exception '[FAIL] updated_at nao foi redefinido pelo trigger tecnico';
  end if;
  raise notice '[PASS] version incrementada e updated_at mantido pelo trigger (set_updated_at) em seniority_levels';
end $$;

-- ============================================================================
-- 5) Rejeições (integridade no banco)
-- ============================================================================

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.job_roles (organization_id, name)
    values ('f4a00000-0000-0000-0000-0000000000a1', 'Analista');
  exception when unique_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] duplicidade de nome na mesma organizacao NAO foi rejeitada';
  end if;
  raise notice '[PASS] duplicidade de nome de funcao na mesma organizacao rejeitada (unique por org)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.seniority_levels (organization_id, name)
    values ('f4a00000-0000-0000-0000-0000000000a1', 'Pleno');
  exception when unique_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] duplicidade de senioridade na mesma organizacao NAO foi rejeitada';
  end if;
  raise notice '[PASS] duplicidade de senioridade na mesma organizacao rejeitada (unique por org)';
end $$;

do $$
begin
  begin
    insert into public.job_roles (organization_id, name)
    values ('f4a00000-0000-0000-0000-0000000000a1', ' Nova Funcao');
    raise exception '[FAIL] nome com espacos nas bordas NAO foi rejeitado';
  exception when check_violation then
    null;
  end;
  raise notice '[PASS] nome com espacos nas bordas rejeitado por check constraint';
end $$;

do $$
begin
  begin
    insert into public.job_roles (organization_id, name, status)
    values ('f4a00000-0000-0000-0000-0000000000a1', 'Funcao Arquivada', 'archived');
    raise exception '[FAIL] status fora do dominio NAO foi rejeitado';
  exception when check_violation then
    null;
  end;
  raise notice '[PASS] status fora do dominio (active/disabled) rejeitado por check constraint';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.job_roles (organization_id, name)
    values ('f4a00000-0000-0000-0000-0000000000c9', 'Funcao Orfa');
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] funcao com organization_id inexistente NAO foi rejeitada';
  end if;
  raise notice '[PASS] FK rejeita job_role com organizacao inexistente (isolamento/consistencia)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    delete from public.organizations
    where id = 'f4a00000-0000-0000-0000-0000000000a1';
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] exclusao fisica de organizacao com catalogos NAO foi bloqueada';
  end if;
  raise notice '[PASS] exclusao fisica de organizacao com catalogos bloqueada (FK RESTRICT)';
end $$;

-- ============================================================================
-- 6) RLS deny-by-default em execução (como authenticated)
-- ============================================================================

set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.job_roles;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de job_roles';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de job_roles';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.seniority_levels;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de seniority_levels';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de seniority_levels';
end $$;

do $$
begin
  begin
    insert into public.job_roles (organization_id, name)
    values ('f4a00000-0000-0000-0000-0000000000a1', 'Funcao RLS');
    raise exception '[FAIL] RLS permitiu INSERT de authenticated em job_roles';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] RLS: INSERT de authenticated em job_roles negado (row-level security)';
end $$;

do $$
declare
  v_n int;
begin
  update public.job_roles set version = version + 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu UPDATE de authenticated em job_roles (%)', v_n;
  end if;
  raise notice '[PASS] RLS: UPDATE de authenticated em job_roles afeta zero linhas';
end $$;

do $$
declare
  v_n int;
begin
  delete from public.seniority_levels;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu DELETE de authenticated em seniority_levels (%)', v_n;
  end if;
  raise notice '[PASS] RLS: DELETE de authenticated em seniority_levels afeta zero linhas';
end $$;

reset role;

-- ============================================================================
-- 7) F3-01 permanece intacta
-- ============================================================================

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'collaborators';

  if v_cols is distinct from
     array['created_at', 'id', 'organization_id', 'updated_at', 'version']::text[]
  then
    raise exception '[FAIL] collaborators (F3-01) foi alterada indevidamente';
  end if;
  raise notice '[PASS] F3-01 intacta: collaborators permanece com nucleo minimo (5 colunas)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_policies p
  where p.schemaname = 'public';
  if v_n <> 3 then
    raise exception '[FAIL] quantidade de policies alterada (esperado 3, encontrado %)', v_n;
  end if;
  raise notice '[PASS] policies existentes inalteradas (3 policies de identidade/sessao da F2)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'ex_collaborator_status_periods_no_overlap',
    'ex_collaborator_identifiers_no_overlap',
    'uq_collaborator_identifiers_organization_code'
  );
  if v_n <> 3 then
    raise exception '[FAIL] constraints temporais/uniques da F3-01 ausentes';
  end if;
  raise notice '[PASS] constraints de lifecycle/identificadores da F3-01 presentes';
end $$;

-- ============================================================================
-- 8) Limpeza do cenário sintético (banco local permanece limpo)
-- ============================================================================

delete from public.job_roles
where organization_id in (
  'f4a00000-0000-0000-0000-0000000000a1',
  'f4a00000-0000-0000-0000-0000000000b1'
);

delete from public.seniority_levels
where organization_id in (
  'f4a00000-0000-0000-0000-0000000000a1',
  'f4a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f4a00000-0000-0000-0000-0000000000a1',
  'f4a00000-0000-0000-0000-0000000000b1'
);

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.job_roles j
  where j.organization_id::text like 'f4a00000-0000-0000-0000-0000000000%';
  select v_n + count(*) into v_n
  from public.seniority_levels s
  where s.organization_id::text like 'f4a00000-0000-0000-0000-0000000000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-02 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F3-02 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-02: todas as verificacoes passaram (schema, FKs, constraints, triggers, RLS).';
end $$;
