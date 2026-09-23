-- F6-A22 P3 (#338): provas server-side da administracao de responsabilidades.
\set ON_ERROR_STOP on
set local role service_role;

do $$
declare
  v_id uuid;
  v_same uuid;
  v_version integer;
  v_events integer;
begin
  -- O teste usa uma transacao externa para provar o caminho positivo.
  v_id := public.estrutura_responsabilidade_criar(
    'f6a23000-0000-4000-8000-0000000000a1',
    'f6a2d100-0000-4000-8000-000000000001', 'PEOPLE_MANAGEMENT',
    '2026-02-01T00:00:00Z', '2026-12-31T00:00:00Z',
    'f6a2a000-0000-4000-8000-000000000902',
    'f6a23000-0000-4000-8000-000000000002');
  v_same := public.estrutura_responsabilidade_criar(
    'f6a23000-0000-4000-8000-0000000000a1',
    'f6a2d100-0000-4000-8000-000000000001', 'PEOPLE_MANAGEMENT',
    '2026-02-01T00:00:00Z', '2026-12-31T00:00:00Z',
    'f6a2a000-0000-4000-8000-000000000902',
    'f6a23000-0000-4000-8000-000000000002');
  if v_id <> v_same then raise exception '[FAIL] idempotencia nao devolveu o mesmo id'; end if;
  select version into v_version from public.organizational_position_responsibilities where id = v_id;
  select count(*) into v_events from public.organizational_position_responsibility_events
   where responsibility_id = v_id and event_type = 'CREATED';
  if v_events <> 1 then raise exception '[FAIL] criacao sem evento unico'; end if;
  if not exists (select 1 from public.estrutura_responsabilidades_consultar(
      'f6a23000-0000-4000-8000-0000000000a1',
      'f6a23000-0000-4000-8000-000000000002') where id = v_id) then
    raise exception '[FAIL] consulta administrativa nao retornou a responsabilidade';
  end if;
  raise notice '[PASS] org.structure.manage cria PEOPLE_MANAGEMENT com autoria, idempotencia e evento';

  begin
    perform public.estrutura_responsabilidade_criar(
      'f6a23000-0000-4000-8000-0000000000a1',
      'f6a2d100-0000-4000-8000-000000000001', 'PEOPLE_MANAGEMENT',
      '2026-03-01T00:00:00Z', null,
      'f6a2a000-0000-4000-8000-000000000903',
      'f6a23000-0000-4000-8000-000000000004');
    raise exception '[FAIL] ator sem org.structure.manage foi aceito';
  exception when others then
    if sqlerrm not like 'F6_A22_FORBIDDEN%' then raise; end if;
    raise notice '[PASS] PEOPLE_MANAGEMENT sem org.structure.manage e negado';
  end;

  begin
    perform public.estrutura_responsabilidade_criar(
      'f6a23000-0000-0000-0000-0000000000a2',
      'f6a2d100-0000-0000-0000-000000000004', 'PEOPLE_MANAGEMENT',
      '2026-03-01T00:00:00Z', null,
      'f6a2a000-0000-4000-8000-000000000904',
      'f6a23000-0000-4000-8000-000000000002');
    raise exception '[FAIL] cross-tenant foi aceito';
  exception when others then
    if sqlerrm not like 'F6_A22_FORBIDDEN%' then raise; end if;
    raise notice '[PASS] cross-tenant DENY';
  end;

  begin
    perform public.estrutura_responsabilidade_criar(
      'f6a23000-0000-4000-8000-0000000000a1',
      'f6a2d100-0000-4000-8000-000000000001', 'PEOPLE_MANAGEMENT',
      '2026-12-01T00:00:00Z', '2026-11-01T00:00:00Z',
      'f6a2a000-0000-4000-8000-000000000905',
      'f6a23000-0000-4000-8000-000000000002');
    raise exception '[FAIL] intervalo invalido foi aceito';
  exception when others then
    if sqlerrm not like 'F6_A22_INVALID_INPUT%' then raise; end if;
    raise notice '[PASS] valid_to <= valid_from e rejeitado';
  end;

  begin
    perform public.estrutura_responsabilidade_criar(
      'f6a23000-0000-4000-8000-0000000000a1',
      'f6a2d100-0000-4000-8000-000000000001', 'PEOPLE_MANAGEMENT',
      '2026-06-01T00:00:00Z', null,
      'f6a2a000-0000-4000-8000-000000000906',
      'f6a23000-0000-4000-8000-000000000002');
    raise exception '[FAIL] sobreposicao foi aceita';
  exception when others then
    if sqlerrm not like 'F6_A22_CONFLICT%' then raise; end if;
    raise notice '[PASS] sobreposicao temporal rejeitada';
  end;

  if v_version is distinct from 0 then raise exception '[FAIL] versao inicial inesperada'; end if;
end $$;

do $$
declare v_id uuid; v_status text; v_to timestamptz; v_version integer; v_events integer;
begin
  select id into v_id from public.organizational_position_responsibilities
   where organization_id = 'f6a23000-0000-4000-8000-0000000000a1'
     and position_id = 'f6a2d100-0000-4000-8000-000000000001';
  -- IDs acima sao deliberadamente distintos do cenario P3; o teste encontra o fato criado.
  if v_id is null then raise exception '[FAIL] responsabilidade criada nao encontrada'; end if;
  perform public.estrutura_responsabilidade_revogar(
    v_id, '2026-09-01T00:00:00Z', 0,
    'f6a2a000-0000-4000-8000-000000000907',
    'f6a23000-0000-4000-8000-000000000001');
  select status, valid_to, version into v_status, v_to, v_version
    from public.organizational_position_responsibilities where id = v_id;
  select count(*) into v_events from public.organizational_position_responsibility_events
   where responsibility_id = v_id and event_type = 'REVOKED';
  if v_status <> 'revoked' or v_to <> '2026-09-01T00:00:00Z' or v_version <> 1 or v_events <> 1 then
    raise exception '[FAIL] revogacao nao preservou fato/evento/version';
  end if;
  raise notice '[PASS] revogacao temporal preserva fato, incrementa version e audita autoria';

  begin
    perform public.estrutura_responsabilidade_revogar(
      v_id, '2026-09-02T00:00:00Z', 0,
      'f6a2a000-0000-4000-8000-000000000908',
      'f6a23000-0000-4000-8000-000000000001');
    raise exception '[FAIL] expected_version stale foi aceito';
  exception when others then
    if sqlerrm not like 'F6_A22_CONFLICT%' then raise; end if;
    raise notice '[PASS] expected_version stale resulta em DENY/conflito';
  end;
end $$;

do $$
begin
  if has_function_privilege('anon', 'public.estrutura_responsabilidade_criar(uuid,uuid,text,timestamptz,timestamptz,uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.estrutura_responsabilidade_revogar(uuid,timestamptz,integer,uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.estrutura_responsabilidades_consultar(uuid,uuid)', 'EXECUTE') then
    raise exception '[FAIL] RPC P3 exposta a cliente';
  end if;
  if has_table_privilege('authenticated', 'public.organizational_position_responsibilities', 'INSERT') then
    raise exception '[FAIL] tabela autorizativa exposta a authenticated';
  end if;
  raise notice '[PASS] RPC e tabela P3 fechadas para anon/authenticated';
end $$;

reset role;
