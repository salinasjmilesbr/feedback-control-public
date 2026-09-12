-- ============================================================================
-- F5-09 P2: validacao automatizada das RPCs de gestao de ciclo
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes` (migrations)
--   2) `03-cenario-f5-09-p2.sql` (fixture / guarda de estado limpo)
--   3) este arquivo             (asserts `[PASS]`/`[FAIL]`)
--
-- Cobertura do contrato (docs/F5-09-desenho-tecnico.md §6 T0–T3/T8/T9, §8, §10,
-- §11, §12, §13.2, §13.3, §19 P2):
--   A  criacao valida (PLANEJADO, version 0, config soberana, evento CRIADO);
--   B  criacao sem membership ativa => FORBIDDEN;
--   C  criacao sem capability cycle.manage => FORBIDDEN;
--   D  tentativa cross-tenant => FORBIDDEN;
--   E  edicao valida de PLANEJADO (periodo/ano/numero, version+1, EDITADO);
--   F  edicao com expected_version obsoleto => CONFLICT;
--   G  edicao de ciclo NAO PLANEJADO => CONFLICT;
--   H  ativacao valida (ATIVO, data_ativacao, version+1, evento ATIVADO);
--   I  segunda ativacao conflitante na mesma organizacao => CONFLICT (I5);
--   J  falha durante a materializacao => ROLLBACK TOTAL (prova por falha injetada);
--   K  estrutura materializada pertence ao tenant/ciclo corretos;
--   L  hierarquia vem das fontes RELACIONAIS (F3-04/F3-07/F3-08), nao de texto;
--   M  encerramento valido reusando a F5-06 (pendencias permanentes + contadores);
--   N  encerramento em estado invalido => CONFLICT (sem duplicar fechamento);
--   O  falha no fechamento F5-06 => ROLLBACK TOTAL da transicao;
--   P  eventos corretos por mutacao (tipos, ordem, um por operacao);
--   Q  autoria server-side (ator verificado + membership ativa);
--   R  payload nao forja tenant/autoria/status/versao/estrutura;
--   S  ACL/grants finais (INVOKER, search_path, EXECUTE so service_role);
--   T  ausencia de SELECT authenticated antecipado (P5 nao antecipado);
--   U  concorrencia: lock normativo por organizacao + expected_version + I5
--      (contensao real entre DUAS sessoes nao e prova vel aqui — ver §U);
--   V  idempotencia por (organization_id, operation_id) + hash canonico;
--   W  reexecucao: fixture insert-once sem duplicar; recriacao do mesmo
--      (ano,numero) falha de forma deterministica; estado limpo exige db reset.
--
-- Saida deterministica: um `[PASS]` por verificacao; qualquer falha aborta.
-- Asserts negativos rodam em subtransacao (a excecao esperada reverte apenas a
-- tentativa). Falhas injetadas usam triggers TEMPORARIOS removidos ao final.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture presente e organizacao sem ciclos (estado limpo)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_colabs int;
  v_ciclos int;
begin
  select count(*) into v_colabs from public.collaborators
   where organization_id = v_org and id::text like 'e9b00000%';
  if v_colabs <> 4 then
    raise exception '[FAIL] pre-condicao: fixture F5-09 P2 ausente (colaboradores=%) — execute 03-cenario-f5-09-p2.sql', v_colabs;
  end if;
  select count(*) into v_ciclos from public.evaluation_cycles
   where organization_id = v_org;
  if v_ciclos <> 0 then
    raise exception '[FAIL] pre-condicao: organizacao da fixture ja possui % ciclo(s) — execute `supabase db reset` (dominio append-only nao tem reset parcial)', v_ciclos;
  end if;
  raise notice '[PASS] pre-condicoes: fixture presente e organizacao sem ciclos';
end $$;

-- ============================================================================
-- 1) B/C/D) Recusas de autorizacao/tenant na criacao (nenhum efeito)
-- ============================================================================
do $$
declare
  v_org   uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'e9a00000-0000-0000-0000-0000000000b1';
  v_ok    boolean;
begin
  -- (B) ator com membership DISABLED.
  v_ok := false;
  begin
    perform public.ciclo_criar(v_org, 2031, 1, date '2031-01-01', date '2031-03-31',
      'e9c00000-0000-0000-0000-000000000004', 'e9a10000-0000-0000-0000-000000000001');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] B: criacao com membership disabled deveria ser FORBIDDEN';
  end if;

  -- (C) ator sem capability `cycle.manage` (membership ativa, sem assignment).
  v_ok := false;
  begin
    perform public.ciclo_criar(v_org, 2031, 1, date '2031-01-01', date '2031-03-31',
      'e9c00000-0000-0000-0000-000000000002', 'e9a10000-0000-0000-0000-000000000002');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] C: criacao sem capability deveria ser FORBIDDEN';
  end if;

  -- (D) ator de OUTRO tenant criando na organizacao Alfa.
  v_ok := false;
  begin
    perform public.ciclo_criar(v_org, 2031, 1, date '2031-01-01', date '2031-03-31',
      'e9c00000-0000-0000-0000-000000000003', 'e9a10000-0000-0000-0000-000000000003');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] D: criacao cross-tenant deveria ser FORBIDDEN';
  end if;

  -- Nenhum ciclo e nenhum evento foram criados pelas tentativas recusadas.
  if exists (select 1 from public.evaluation_cycles where organization_id = v_org) then
    raise exception '[FAIL] B/C/D: tentativa recusada criou ciclo';
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id in (v_org, v_beta)
       and e.operation_id in ('e9a10000-0000-0000-0000-000000000001',
                              'e9a10000-0000-0000-0000-000000000002',
                              'e9a10000-0000-0000-0000-000000000003')
  ) then
    raise exception '[FAIL] B/C/D: tentativa recusada gravou evento na trilha';
  end if;

  raise notice '[PASS] B/C/D: recusas FORBIDDEN sem efeito (membership, capability e cross-tenant)';
end $$;

-- ============================================================================
-- 2) A) Criacao valida (T0)
-- ============================================================================
do $$
declare
  v_org   uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_res   jsonb;
  v_id    uuid;
  v_ciclo record;
  v_evt   record;
  v_qtd   int;
begin
  v_res := public.ciclo_criar(v_org, 2030, 1, date '2030-01-01', date '2030-03-31',
    'e9c00000-0000-0000-0000-000000000001', 'e9a10000-0000-0000-0000-0000000000a1');
  v_id := (v_res->>'cycle_id')::uuid;

  select c.* into v_ciclo from public.evaluation_cycles c where c.id = v_id;
  if v_ciclo.id is null then
    raise exception '[FAIL] A: ciclo nao criado';
  end if;
  if v_ciclo.organization_id <> v_org then
    raise exception '[FAIL] A: ciclo criado em tenant errado';
  end if;
  if v_ciclo.status <> 'PLANEJADO' or v_ciclo.version <> 0 then
    raise exception '[FAIL] A: ciclo deveria nascer PLANEJADO/version 0 (status=%, version=%)',
      v_ciclo.status, v_ciclo.version;
  end if;
  if v_ciclo.ano <> 2030 or v_ciclo.numero <> 1 then
    raise exception '[FAIL] A: ano/numero divergentes';
  end if;
  if v_ciclo.data_inicio <> date '2030-01-01' or v_ciclo.data_fim <> date '2030-03-31' then
    raise exception '[FAIL] A: periodo divergente';
  end if;
  if v_ciclo.config_version_id is null then
    raise exception '[FAIL] A/D19: versao de configuracao soberana nao gravada';
  end if;
  if v_res->>'status' <> 'PLANEJADO' or (v_res->>'version')::int <> 0 then
    raise exception '[FAIL] A: retorno divergente do estado criado';
  end if;

  -- Evento CRIADO: um, do tenant/ciclo corretos, com autoria soberana.
  select count(*) into v_qtd from public.cycle_events e
   where e.organization_id = v_org and e.cycle_id = v_id;
  if v_qtd <> 1 then
    raise exception '[FAIL] A: esperado 1 evento para o ciclo novo (encontrado %)', v_qtd;
  end if;
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org and e.cycle_id = v_id;
  if v_evt.event_type <> 'CRIADO' then
    raise exception '[FAIL] A: evento deveria ser CRIADO (recebido %)', v_evt.event_type;
  end if;
  if v_evt.actor_user_profile_id <> 'e9c00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] A/Q: autoria do evento nao e o ator verificado';
  end if;
  if v_evt.actor_membership_id <> 'e9d00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] A/Q: membership de autoria divergente';
  end if;
  if v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] A: payload_hash fora do formato SHA-256';
  end if;
  if (v_evt.after_value->>'config_version_id') is null then
    raise exception '[FAIL] A: after_value sem versao de configuracao';
  end if;

  raise notice '[PASS] A: criacao valida (PLANEJADO/version 0, config soberana, evento CRIADO com autoria server-side)';
end $$;

-- O UUID do ciclo criado no teste A NAO e transportado por variavel do psql: a
-- interpolacao `:'var'` do psql nao e aplicada dentro de corpos dollar-quoted
-- (blocos `DO`), o que geraria erro de sintaxe no servidor. Cada bloco resolve o
-- ciclo da fixture por SELECT DETERMINISTICO (organization_id + ano + numero).

-- ============================================================================
-- 3) V) Idempotencia por (organization_id, operation_id) + hash canonico
-- ============================================================================
do $$
declare
  v_org    uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator   uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_res1   jsonb;
  v_res2   jsonb;
  v_qtd    int;
  v_ok     boolean;
begin
  -- Mesmo operation_id + mesma intencao => MESMO resultado, sem novo evento.
  v_res1 := public.ciclo_criar(v_org, 2030, 1, date '2030-01-01', date '2030-03-31',
    v_ator, 'e9a10000-0000-0000-0000-0000000000a1');
  v_res2 := public.ciclo_criar(v_org, 2030, 1, date '2030-01-01', date '2030-03-31',
    v_ator, 'e9a10000-0000-0000-0000-0000000000a1');
  if v_res1 <> v_res2 then
    raise exception '[FAIL] V: replay idempotente devolveu resultado diferente (% vs %)', v_res1, v_res2;
  end if;
  select count(*) into v_qtd from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = 'e9a10000-0000-0000-0000-0000000000a1';
  if v_qtd <> 1 then
    raise exception '[FAIL] V: replay duplicou evento (linhas=%)', v_qtd;
  end if;

  -- Mesmo operation_id + intencao DIFERENTE => CONFLICT (nunca executa).
  v_ok := false;
  begin
    perform public.ciclo_criar(v_org, 2030, 3, date '2030-07-01', date '2030-09-30',
      v_ator, 'e9a10000-0000-0000-0000-0000000000a1');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] V: operation_id reutilizado com intencao diferente deveria ser CONFLICT';
  end if;
  if exists (
    select 1 from public.evaluation_cycles c
     where c.organization_id = v_org and c.ano = 2030 and c.numero = 3
  ) then
    raise exception '[FAIL] V: CONFLICT gravou estado parcial';
  end if;

  raise notice '[PASS] V: idempotencia por operation_id + hash canonico (replay sem efeito; divergencia => CONFLICT)';
end $$;

-- ============================================================================
-- 4) E/F) Edicao de ciclo PLANEJADO
-- ============================================================================
do $$
declare
  v_org    uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator   uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_c1     uuid;
  v_res    jsonb;
  v_ciclo  record;
  v_evt    record;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 1;

  v_res := public.ciclo_editar(v_c1, v_org, 2030, 1,
    date '2030-01-15', date '2030-04-15', 0, v_ator,
    'e9a10000-0000-0000-0000-0000000000e1');

  select c.* into v_ciclo from public.evaluation_cycles c where c.id = v_c1;
  if (v_res->>'version')::int <> 1 or v_ciclo.version <> 1 then
    raise exception '[FAIL] E: edicao deveria elevar a versao para 1 (retorno=%, linha=%)',
      v_res->>'version', v_ciclo.version;
  end if;
  if v_ciclo.status <> 'PLANEJADO' then
    raise exception '[FAIL] E: edicao comum alterou o status (%)', v_ciclo.status;
  end if;
  if v_ciclo.data_inicio <> date '2030-01-15' or v_ciclo.data_fim <> date '2030-04-15' then
    raise exception '[FAIL] E: periodo nao atualizado';
  end if;
  if v_ciclo.ano <> 2030 or v_ciclo.numero <> 1 then
    raise exception '[FAIL] E: ano/numero nao preservados';
  end if;

  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'e9a10000-0000-0000-0000-0000000000e1';
  if v_evt.event_type <> 'EDITADO' then
    raise exception '[FAIL] E: evento deveria ser EDITADO (%)', v_evt.event_type;
  end if;
  if (v_evt.before_value->>'data_inicio') <> '2030-01-01'
     or (v_evt.after_value->>'data_inicio') <> '2030-01-15' then
    raise exception '[FAIL] E: before/after do evento nao registram a mudanca';
  end if;
  if (v_evt.after_value->>'version')::int <> 1 then
    raise exception '[FAIL] E: evento sem a versao resultante';
  end if;

  raise notice '[PASS] E: edicao valida de PLANEJADO (periodo novo, version+1, evento EDITADO com before/after)';
end $$;

do $$
declare
  v_org  uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_ok   boolean := false;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 1;

  -- expected_version OBSOLETO (a versao atual e 1).
  begin
    perform public.ciclo_editar(v_c1, v_org, 2030, 1,
      date '2030-02-01', date '2030-05-01', 0, v_ator,
      'e9a10000-0000-0000-0000-0000000000e2');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] F: expected_version obsoleto deveria ser CONFLICT';
  end if;

  if (select c.data_inicio from public.evaluation_cycles c where c.id = v_c1)
     <> date '2030-01-15' then
    raise exception '[FAIL] F: CONFLICT alterou o periodo';
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'e9a10000-0000-0000-0000-0000000000e2'
  ) then
    raise exception '[FAIL] F: CONFLICT gravou evento';
  end if;

  raise notice '[PASS] F: expected_version obsoleto => CONFLICT sem efeito';
end $$;

-- ============================================================================
-- 5) H/K/L) Ativacao valida + materializacao inicial (F3-08 + F3-09)
-- ============================================================================
do $$
declare
  v_org     uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator    uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_c1      uuid;
  v_res     jsonb;
  v_ciclo   record;
  v_evt     record;
  v_snap    int;
  v_pos     int;
  v_membros int;
  v_resp    int;
  v_sup     uuid;
  v_membro  uuid;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 1;

  v_res := public.ciclo_ativar(v_c1, v_org, 1, v_ator,
    'e9a10000-0000-0000-0000-0000000000a2');

  select c.* into v_ciclo from public.evaluation_cycles c where c.id = v_c1;
  if v_ciclo.status <> 'ATIVO' then
    raise exception '[FAIL] H: ativacao nao mudou o status (%)', v_ciclo.status;
  end if;
  if v_ciclo.data_ativacao is null then
    raise exception '[FAIL] H: data_ativacao nao registrada';
  end if;
  if v_ciclo.version <> 2 then
    raise exception '[FAIL] H: ativacao deveria elevar a versao para 2 (%)', v_ciclo.version;
  end if;
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] H: retorno divergente da ativacao';
  end if;
  if (v_res->>'snapshot_materializado')::int <> 4 then
    raise exception '[FAIL] H/K: snapshot da populacao elegivel deveria ter 4 linhas (%)',
      v_res->>'snapshot_materializado';
  end if;

  -- (K) A estrutura materializada pertence ao MESMO tenant e ao ciclo correto.
  select count(*) into v_snap from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2030 and s.ciclo = 1;
  if v_snap <> 4 then
    raise exception '[FAIL] K: snapshots do ciclo = % (esperado 4)', v_snap;
  end if;
  if exists (
    select 1 from public.collegiate_cycle_snapshots s
     where s.organization_id <> v_org
       and (s.ano = 2030 and s.ciclo = 1)
       and s.collaborator_id::text like 'e9b00000%'
  ) then
    raise exception '[FAIL] K: snapshot materializado em tenant errado';
  end if;

  -- (L) Hierarquia RELACIONAL congelada: o snapshot do colaborador c1 (que ocupa
  -- a posicao subordinada) guarda o superior = colaborador c2. Nada disso vem de
  -- cargo/texto/payload: vem de `position_reporting_lines` + `occupations`.
  select sp.superior_collaborator_id, count(*)
    into v_sup, v_pos
    from public.collegiate_cycle_snapshots s
    join public.collegiate_cycle_snapshot_positions sp on sp.snapshot_id = s.id
   where s.organization_id = v_org and s.ano = 2030 and s.ciclo = 1
     and s.collaborator_id = 'e9b00000-0000-0000-0000-000000000001'
   group by sp.superior_collaborator_id;
  if v_pos <> 1 or v_sup is distinct from 'e9b00000-0000-0000-0000-000000000002'::uuid then
    raise exception '[FAIL] L: superior do c1 no snapshot deveria ser c2 (posicoes=%, superior=%)',
      v_pos, v_sup;
  end if;

  -- (L) Colegiado congelado do AVALIADO c3 = membro c2 (configuracao F3-08).
  select m.member_collaborator_id, count(*)
    into v_membro, v_membros
    from public.collegiate_cycle_snapshots s
    join public.collegiate_cycle_snapshot_members m on m.snapshot_id = s.id
   where s.organization_id = v_org and s.ano = 2030 and s.ciclo = 1
     and s.collaborator_id = 'e9b00000-0000-0000-0000-000000000003'
   group by m.member_collaborator_id;
  if v_membros <> 1 or v_membro is distinct from 'e9b00000-0000-0000-0000-000000000002'::uuid then
    raise exception '[FAIL] L: colegiado congelado do c3 deveria ser o colaborador c2 (membros=%, membro=%)',
      v_membros, v_membro;
  end if;

  -- (L) Responsabilidades de avaliacao (F3-09) materializadas para o ciclo.
  select count(*) into v_resp
    from public.cycle_evaluation_responsibilities r
    join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
   where s.organization_id = v_org and s.ano = 2030 and s.ciclo = 1;
  if v_resp < 1 then
    raise exception '[FAIL] L: responsabilidades de avaliacao (F3-09) nao materializadas';
  end if;
  if exists (
    select 1 from public.cycle_evaluation_responsibilities r
     where r.organization_id <> v_org
       and r.id::text like 'e9%'
  ) then
    raise exception '[FAIL] L: responsabilidade materializada em tenant errado';
  end if;

  -- Evento ATIVADO com os numeros da materializacao.
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'e9a10000-0000-0000-0000-0000000000a2';
  if v_evt.event_type <> 'ATIVADO' then
    raise exception '[FAIL] H: evento deveria ser ATIVADO (%)', v_evt.event_type;
  end if;
  if (v_evt.after_value->>'snapshot_materializado')::int <> 4
     or (v_evt.after_value->>'colaboradores_elegiveis')::int <> 4 then
    raise exception '[FAIL] H: after_value do ATIVADO sem os numeros da materializacao';
  end if;

  raise notice '[PASS] H/K/L: ativacao valida com populacao elegivel (4), snapshot F3-08 e responsabilidades F3-09 do tenant/ciclo corretos, hierarquia relacional (c1 -> c2; colegiado de c3 = c2)';
end $$;

-- ============================================================================
-- 6) G) Edicao de ciclo NAO PLANEJADO => CONFLICT  |  I) segunda ativacao
-- ============================================================================
do $$
declare
  v_org  uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_ok   boolean;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 1;

  -- (G) ciclo ATIVO nao aceita edicao comum.
  v_ok := false;
  begin
    perform public.ciclo_editar(v_c1, v_org, 2030, 1,
      date '2030-01-20', date '2030-04-20', 2, v_ator,
      'e9a10000-0000-0000-0000-0000000000e3');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] G: edicao de ciclo ATIVO deveria ser CONFLICT';
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> 2 then
    raise exception '[FAIL] G: tentativa de edicao de ATIVO alterou a versao';
  end if;

  raise notice '[PASS] G: edicao comum em ciclo ATIVO recusada (transicoes proprias de dominio)';
end $$;

do $$
declare
  v_org  uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_res  jsonb;
  v_c2   uuid;
  v_ok   boolean;
  v_snap int;
begin
  -- Cria o segundo ciclo (periodo adjacente, sem sobreposicao — I6).
  v_res := public.ciclo_criar(v_org, 2030, 2, date '2030-05-01', date '2030-07-31',
    v_ator, 'e9a10000-0000-0000-0000-0000000000b1');
  v_c2 := (v_res->>'cycle_id')::uuid;

  -- (I) Segunda ativacao na MESMA organizacao => CONFLICT (I5/D14).
  v_ok := false;
  begin
    perform public.ciclo_ativar(v_c2, v_org, 0, v_ator,
      'e9a10000-0000-0000-0000-0000000000b2');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] I: segunda ativacao na organizacao deveria ser CONFLICT';
  end if;

  if (select c.status from public.evaluation_cycles c where c.id = v_c2) <> 'PLANEJADO' then
    raise exception '[FAIL] I: ciclo recusado nao permaneceu PLANEJADO';
  end if;
  select count(*) into v_snap from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2030 and s.ciclo = 2;
  if v_snap <> 0 then
    raise exception '[FAIL] I: ativacao recusada materializou snapshot (%)', v_snap;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'e9a10000-0000-0000-0000-0000000000b2'
  ) then
    raise exception '[FAIL] I: ativacao recusada gravou evento';
  end if;

  raise notice '[PASS] I: segunda ativacao na mesma organizacao => CONFLICT fail-closed (nenhum snapshot/evento)';
end $$;

-- ============================================================================
-- 7) J) Falha durante a MATERIALIZACAO => ROLLBACK TOTAL (falha injetada)
-- ============================================================================
do $$
declare
  v_org  uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator uuid := 'e9c00000-0000-0000-0000-000000000001';
begin
  -- Terceiro ciclo, PLANEJADO, para a prova de rollback da materializacao.
  perform public.ciclo_criar(v_org, 2030, 3, date '2030-08-01', date '2030-10-31',
    v_ator, 'e9a10000-0000-0000-0000-0000000000c1');
end $$;

-- Falha injetada: qualquer INSERT em `collegiate_cycle_snapshots` aborta
-- (DDL fora de bloco PL/pgSQL — comandos utilitarios exigem o nivel SQL).
create or replace function public._mut_p2_falhar()
returns trigger language plpgsql as $mut$
begin
  raise exception 'MUT_F5_09_P2: falha injetada na materializacao';
end;
$mut$;

create trigger _mut_p2_snapshot before insert on public.collegiate_cycle_snapshots
  for each row execute function public._mut_p2_falhar();

do $$
declare
  v_org  uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_c3   uuid;
  v_ok   boolean := false;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 3;

  begin
    perform public.ciclo_ativar(v_c3, v_org, 0, v_ator,
      'e9a10000-0000-0000-0000-0000000000c2');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P2%';
  end;

  if not v_ok then
    raise exception '[FAIL] J: a falha injetada na materializacao nao abortou a ativacao';
  end if;
end $$;

drop trigger _mut_p2_snapshot on public.collegiate_cycle_snapshots;
drop function public._mut_p2_falhar();

do $$
declare
  v_org    uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator   uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_c3     uuid;
  v_status text;
  v_snap   int;
begin
  select c.id, c.status into v_c3, v_status from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 3;

  if v_status <> 'PLANEJADO' then
    raise exception '[FAIL] J: rollback incompleto (status=%) — a ativacao deveria reverter', v_status;
  end if;
  if not exists (select 1 from public.evaluation_cycles c where c.id = v_c3 and c.data_ativacao is null) then
    raise exception '[FAIL] J: rollback incompleto (data_ativacao gravada)';
  end if;
  select count(*) into v_snap from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2030 and s.ciclo = 3;
  if v_snap <> 0 then
    raise exception '[FAIL] J: rollback incompleto (snapshots=%)', v_snap;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'e9a10000-0000-0000-0000-0000000000c2'
  ) then
    raise exception '[FAIL] J: rollback incompleto (evento ATIVADO gravado)';
  end if;

  -- Removida a falha injetada, a ativacao do MESMO ciclo passa a funcionar.
  perform public.ciclo_ativar(v_c3, v_org, 0, v_ator,
    'e9a10000-0000-0000-0000-0000000000c3');
  if (select c.status from public.evaluation_cycles c where c.id = v_c3) <> 'ATIVO' then
    raise exception '[FAIL] J: ativacao deveria funcionar apos remover a falha injetada';
  end if;

  raise notice '[PASS] J: falha na materializacao => ROLLBACK TOTAL (ciclo PLANEJADO, sem snapshot e sem evento) e ativacao posterior bem-sucedida';
end $$;

-- ============================================================================
-- 8) O) Falha no fechamento F5-06 => ROLLBACK TOTAL (falha injetada)
-- ============================================================================
do $$
declare
  v_org  uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_c3   uuid;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 3;

  -- Avaliacao incompleta do avaliado c3 (reuso legitimo da F5-06: exige o
  -- snapshot F3-08 materializado na ativacao).
  perform public.evaluation_criar(v_org, v_c3,
    'e9b00000-0000-0000-0000-000000000003', v_ator);
end $$;

-- Falha injetada APENAS na transicao de status para ENCERRADO: o UPDATE interno
-- da F5-06 (contadores/versao) passa e o do encerramento falha — provando que os
-- efeitos da F5-06 sao revertidos junto. DDL no nivel SQL (fora de bloco).
create or replace function public._mut_p2_falhar_encerrar()
returns trigger language plpgsql as $mut$
begin
  if new.status = 'ENCERRADO' and old.status is distinct from 'ENCERRADO' then
    raise exception 'MUT_F5_09_P2: falha injetada no encerramento';
  end if;
  return new;
end;
$mut$;

create trigger _mut_p2_encerrar before update on public.evaluation_cycles
  for each row execute function public._mut_p2_falhar_encerrar();

do $$
declare
  v_org  uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_c3   uuid;
  v_ok   boolean := false;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 3;

  begin
    perform public.ciclo_encerrar(v_c3, v_org, 'tentativa com falha injetada', 1, v_ator,
      'e9a10000-0000-0000-0000-0000000000d1');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P2%';
  end;

  if not v_ok then
    raise exception '[FAIL] O: a falha injetada no fechamento nao abortou o encerramento';
  end if;
end $$;

drop trigger _mut_p2_encerrar on public.evaluation_cycles;
drop function public._mut_p2_falhar_encerrar();

do $$
declare
  v_org    uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_c3     uuid;
  v_eval   uuid;
  v_ciclo  record;
  v_pend   int;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 3;
  select e.id into v_eval from public.evaluations e
   where e.organization_id = v_org and e.cycle_id = v_c3
   order by e.created_at limit 1;

  select c.status, c.version, c.encerrado_com_pendencias, c.quantidade_pendencias
    into v_ciclo
    from public.evaluation_cycles c where c.id = v_c3;
  if v_ciclo.status <> 'ATIVO' then
    raise exception '[FAIL] O: rollback incompleto (status=%)', v_ciclo.status;
  end if;
  if v_ciclo.version <> 1 then
    raise exception '[FAIL] O: rollback incompleto (version=%; a F5-06 havia incrementado)', v_ciclo.version;
  end if;
  if v_ciclo.encerrado_com_pendencias is not false or v_ciclo.quantidade_pendencias <> 0 then
    raise exception '[FAIL] O: rollback incompleto nos contadores de pendencia (%, %)',
      v_ciclo.encerrado_com_pendencias, v_ciclo.quantidade_pendencias;
  end if;
  if exists (
    select 1 from public.evaluations e
     where e.id = v_eval and e.encerrada_com_pendencias
  ) then
    raise exception '[FAIL] O: rollback incompleto (avaliacao marcada pela F5-06 permaneceu)';
  end if;
  select count(*) into v_pend from public.evaluation_pendencies p where p.evaluation_id = v_eval;
  if v_pend <> 0 then
    raise exception '[FAIL] O: rollback incompleto (pendencias persistidas=%)', v_pend;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'e9a10000-0000-0000-0000-0000000000d1'
  ) then
    raise exception '[FAIL] O: rollback incompleto (evento ENCERRADO gravado)';
  end if;

  raise notice '[PASS] O: falha no fechamento => ROLLBACK TOTAL (inclusive dos efeitos da F5-06)';
end $$;

-- ============================================================================
-- 9) M/N) Encerramento valido reusando a F5-06
-- ============================================================================
do $$
declare
  v_org    uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator   uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_c3     uuid;
  v_eval   uuid;
  v_res    jsonb;
  v_ciclo  record;
  v_evt    record;
  v_ok     boolean;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2030 and c.numero = 3;
  select e.id into v_eval from public.evaluations e
   where e.organization_id = v_org and e.cycle_id = v_c3
   order by e.created_at limit 1;

  v_res := public.ciclo_encerrar(v_c3, v_org, 'Encerramento de teste F5-09 P2', 1, v_ator,
    'e9a10000-0000-0000-0000-0000000000d2');

  select c.* into v_ciclo from public.evaluation_cycles c where c.id = v_c3;
  if v_ciclo.status <> 'ENCERRADO' or v_ciclo.data_encerramento is null then
    raise exception '[FAIL] M: encerramento nao aplicou status/data (%)', v_ciclo.status;
  end if;
  if v_ciclo.version <> 2 then
    raise exception '[FAIL] M: encerramento deveria resultar em expected_version + 1 = 2 (version=%)', v_ciclo.version;
  end if;
  if v_ciclo.encerrado_com_pendencias is not true or v_ciclo.quantidade_pendencias < 1 then
    raise exception '[FAIL] M/N: pendencias da F5-06 nao registradas (%, %)',
      v_ciclo.encerrado_com_pendencias, v_ciclo.quantidade_pendencias;
  end if;
  if (v_res->>'quantidade_pendencias')::int <> v_ciclo.quantidade_pendencias then
    raise exception '[FAIL] M: retorno sem a contagem de pendencias do ciclo';
  end if;

  -- Prova do REUSO da F5-06: marcador permanente na avaliacao + pendencias
  -- persistidas + evento da F5-06 na trilha da avaliacao.
  if not exists (
    select 1 from public.evaluations e
     where e.id = v_eval and e.encerrada_com_pendencias
  ) then
    raise exception '[FAIL] M: avaliacao incompleta nao recebeu o marcador permanente da F5-06';
  end if;
  if not exists (select 1 from public.evaluation_pendencies p where p.evaluation_id = v_eval) then
    raise exception '[FAIL] M: pendencias da F5-06 nao persistidas';
  end if;
  if not exists (
    select 1 from public.evaluation_events ev
     where ev.evaluation_id = v_eval and ev.event_type = 'PENDENCIA_MARCADA'
  ) then
    raise exception '[FAIL] M: evento PENDENCIA_MARCADA da F5-06 ausente';
  end if;

  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'e9a10000-0000-0000-0000-0000000000d2';
  if v_evt.event_type <> 'ENCERRADO' or v_evt.reason <> 'Encerramento de teste F5-09 P2' then
    raise exception '[FAIL] M/P: evento ENCERRADO ausente ou sem motivo';
  end if;
  if (v_evt.after_value->>'quantidade_pendencias')::int <> v_ciclo.quantidade_pendencias then
    raise exception '[FAIL] M: evento sem a contagem de pendencias';
  end if;

  -- (N) Segunda tentativa de encerrar (novo operation_id) => CONFLICT.
  v_ok := false;
  begin
    perform public.ciclo_encerrar(v_c3, v_org, 'segunda tentativa', 2, v_ator,
      'e9a10000-0000-0000-0000-0000000000d3');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] N: encerrar ciclo ja ENCERRADO deveria ser CONFLICT';
  end if;

  raise notice '[PASS] M/N: encerramento valido reusando a F5-06 (marcador permanente + contadores + evento) e recusa determinista no estado invalido';
end $$;

-- ============================================================================
-- 10) R) Payload nao forja tenant/autoria/status/versao/estrutura
-- ============================================================================
do $$
declare
  v_org   uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'e9a00000-0000-0000-0000-0000000000b1';
  v_ok    boolean;
begin
  -- (i) Ator de Beta declarando a organizacao Alfa (tenant divergente).
  v_ok := false;
  begin
    perform public.ciclo_criar(v_org, 2032, 1, date '2032-01-01', date '2032-03-31',
      'e9c00000-0000-0000-0000-000000000003', 'e9a10000-0000-0000-0000-0000000000f1');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] R: tenant declarado pelo payload foi aceito';
  end if;

  -- (ii) Ator de Alfa declarando a organizacao Beta.
  v_ok := false;
  begin
    perform public.ciclo_criar(v_beta, 2032, 1, date '2032-01-01', date '2032-03-31',
      'e9c00000-0000-0000-0000-000000000001', 'e9a10000-0000-0000-0000-0000000000f2');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] R: ator fora do tenant declarado foi aceito';
  end if;

  -- (iii) A ASSINATURA nao expoe status, version, config_version, autor nem
  --       estrutura: esses campos nao existem como parametro (prova estrutural).
  if pg_get_function_arguments(to_regprocedure('public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)'))
     <> 'p_organization_id uuid, p_ano integer, p_numero integer, p_data_inicio date, p_data_fim date, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] R: assinatura de ciclo_criar fora do contrato';
  end if;
  if pg_get_function_arguments(to_regprocedure('public.ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)'))
     <> 'p_cycle_id uuid, p_organization_id uuid, p_ano integer, p_numero integer, p_data_inicio date, p_data_fim date, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] R: assinatura de ciclo_editar fora do contrato';
  end if;
  if pg_get_function_arguments(to_regprocedure('public.ciclo_ativar(uuid, uuid, integer, uuid, uuid)'))
     <> 'p_cycle_id uuid, p_organization_id uuid, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] R: assinatura de ciclo_ativar fora do contrato';
  end if;
  if pg_get_function_arguments(to_regprocedure('public.ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)'))
     <> 'p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] R: assinatura de ciclo_encerrar fora do contrato';
  end if;

  -- (iv) A trilha nao tem campo de autoria vindo do corpo: autoria != payload.
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'cycle_events'
       and column_name in ('autor_matricula', 'autor_nome', 'created_by')
  ) then
    raise exception '[FAIL] R: trilha com campo de autoria textual do cliente';
  end if;

  raise notice '[PASS] R: tenant/autoria/status/versao/estrutura nao vem do payload (recusas FORBIDDEN + assinaturas fechadas)';
end $$;

-- ============================================================================
-- 11) P/Q) Eventos e autoria em toda a trilha da fixture
-- ============================================================================
do $$
declare
  v_org     uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_qtd     int;
  v_sem_aut int;
  v_dup     int;
begin
  -- Um evento por operacao (operation_id unico) e tipos do contrato.
  select count(*) into v_dup from (
    select e.operation_id
      from public.cycle_events e
     where e.organization_id = v_org
     group by e.operation_id
    having count(*) > 1
  ) x;
  if v_dup <> 0 then
    raise exception '[FAIL] P: operation_id repetido na trilha (%)', v_dup;
  end if;

  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.event_type not in ('CRIADO', 'EDITADO', 'ATIVADO', 'ENCERRADO')
  ) then
    raise exception '[FAIL] P: evento fora do contrato da P2';
  end if;

  -- O conjunto de tipos da trilha da fixture e EXATAMENTE o do contrato da P2
  -- (CRIADO/EDITADO/ATIVADO/ENCERRADO), sem faltar nem sobrar.
  if exists (
    select 1 from (
      select e.event_type from public.cycle_events e where e.organization_id = v_org
      except
      select unnest(array['CRIADO', 'EDITADO', 'ATIVADO', 'ENCERRADO'])
    ) x
  ) or exists (
    select 1 from (
      select unnest(array['CRIADO', 'EDITADO', 'ATIVADO', 'ENCERRADO'])
      except
      select e.event_type from public.cycle_events e where e.organization_id = v_org
    ) y
  ) then
    raise exception '[FAIL] P: conjunto de eventos diferente do contrato da P2';
  end if;

  -- Autoria: sempre o ator verificado + a membership ativa dele.
  select count(*) into v_sem_aut
    from public.cycle_events e
   where e.organization_id = v_org
     and (e.actor_user_profile_id is null or e.actor_membership_id is null);
  if v_sem_aut <> 0 then
    raise exception '[FAIL] Q: evento sem autoria soberana (%)', v_sem_aut;
  end if;
  if exists (
    select 1
      from public.cycle_events e
      left join public.user_organization_memberships m
        on m.id = e.actor_membership_id and m.organization_id = e.organization_id
     where e.organization_id = v_org
       and (m.id is null or m.user_profile_id <> e.actor_user_profile_id)
  ) then
    raise exception '[FAIL] Q: membership da trilha nao pertence ao ator/tenant';
  end if;

  select count(*) into v_qtd from public.cycle_events e where e.organization_id = v_org;
  if v_qtd < 5 then
    raise exception '[FAIL] P: trilha da fixture com menos eventos que o esperado (%)', v_qtd;
  end if;

  raise notice '[PASS] P/Q: % eventos, um por operacao, tipos do contrato e autoria sempre do ator verificado', v_qtd;
end $$;

-- ============================================================================
-- 12) U) Concorrencia: lock normativo + expected_version + I5
-- ============================================================================
do $$
declare
  v_fn   text;
  v_def  text;
begin
  -- (a) TODAS as RPCs de mutacao adquirem a chave normativa da familia de
  --     ciclos (P1) — serializacao por organizacao (§11).
  foreach v_fn in array array['ciclo_criar', 'ciclo_editar', 'ciclo_ativar', 'ciclo_encerrar']
  loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = v_fn;
    if v_def is null or position('ciclo_lock_organizacao' in v_def) = 0 then
      raise exception '[FAIL] U: % nao adquire o lock normativo de ciclos', v_fn;
    end if;
    if position('position_reporting_lines:' in v_def) > 0
       or position('f5_07_estrutura:' in v_def) > 0 then
      raise exception '[FAIL] U: % usa chave de OUTRA familia de lock', v_fn;
    end if;
  end loop;

  -- (b) expected_version obsoleto => CONFLICT (provado em F) e
  -- (c) segunda ativacao => CONFLICT (provado em I).
  if (select count(*) from public.evaluation_cycles c
       where c.organization_id = 'e9a00000-0000-0000-0000-0000000000a1'
         and c.status = 'ATIVO') > 1 then
    raise exception '[FAIL] U: mais de um ciclo ATIVO na organizacao';
  end if;

  raise notice '[PASS] U: lock normativo da familia de ciclos nas 4 RPCs; expected_version e I5 provados por comportamento (contensao entre DUAS sessoes nao e provavel neste validador de sessao unica — coberto na P9/CI integrado)';
end $$;

-- ============================================================================
-- 13) S/T) ACL/grants finais e ausencia de leitura antecipada (P5)
-- ============================================================================
do $$
declare
  v_fn        text;
  v_rec       record;
  v_problemas text[] := array[]::text[];
begin
  foreach v_fn in array array[
    'ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)',
    'ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)',
    'ciclo_ativar(uuid, uuid, integer, uuid, uuid)',
    'ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)']
  loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config
      into v_rec
      from pg_proc p where p.oid = to_regprocedure('public.' || v_fn);
    if not found then
      v_problemas := v_problemas || ('ausente: ' || v_fn);
      continue;
    end if;
    if v_rec.prosecdef then
      v_problemas := v_problemas || ('SECURITY DEFINER: ' || v_fn);
    end if;
    if position('search_path=public' in v_rec.config) = 0 then
      v_problemas := v_problemas || ('sem search_path: ' || v_fn);
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_problemas := v_problemas || ('sem EXECUTE para service_role: ' || v_fn);
    end if;
    if has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE') then
      v_problemas := v_problemas || ('EXECUTE exposto: ' || v_fn);
    end if;
  end loop;

  -- (T) P5 nao antecipado: nenhuma policy nova e nenhum acesso de cliente.
  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('evaluation_cycles', 'cycle_events')
  ) then
    v_problemas := v_problemas || 'policy antecipada em evaluation_cycles/cycle_events';
  end if;
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'SELECT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_problemas := v_problemas || 'anon/authenticated com acesso a ciclo/trilha';
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] S/T: %', array_to_string(v_problemas, '; ');
  end if;

  raise notice '[PASS] S/T: 4 RPCs INVOKER com search_path fixo e EXECUTE so service_role; leitura de cliente (P5) nao antecipada';
end $$;

-- ============================================================================
-- 14) W) Reexecucao: fixture insert-once e recriacao deterministica
-- ============================================================================
do $$
declare
  v_org  uuid := 'e9a00000-0000-0000-0000-0000000000a1';
  v_ator uuid := 'e9c00000-0000-0000-0000-000000000001';
  v_ok   boolean;
  v_qtd  int;
begin
  -- A fixture nao duplica (guarda insert-once do cenario).
  select count(*) into v_qtd from public.organizations
   where id = v_org;
  if v_qtd <> 1 then
    raise exception '[FAIL] W: fixture duplicada (%)', v_qtd;
  end if;
  select count(*) into v_qtd from public.collaborators
   where organization_id = v_org and id::text like 'e9b00000%';
  if v_qtd <> 4 then
    raise exception '[FAIL] W: colaboradores da fixture duplicados (%)', v_qtd;
  end if;

  -- Recriar o mesmo (ano,numero) com OUTRO operation_id => CONFLICT estavel.
  v_ok := false;
  begin
    perform public.ciclo_criar(v_org, 2030, 1, date '2030-01-01', date '2030-03-31',
      v_ator, 'e9a10000-0000-0000-0000-0000000000ff');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] W: recriacao do mesmo ano/numero deveria ser CONFLICT';
  end if;
  select count(*) into v_qtd from public.evaluation_cycles
   where organization_id = v_org and ano = 2030 and numero = 1;
  if v_qtd <> 1 then
    raise exception '[FAIL] W: recriacao gerou estado duplicado (%)', v_qtd;
  end if;

  raise notice '[PASS] W: fixture insert-once sem duplicacao; recriacao deterministica (CONFLICT) e estado limpo sempre via `db reset` (dominio append-only)';
end $$;

-- ============================================================================
-- 15) Resumo
-- ============================================================================
do $$
begin
  raise notice '============================================================';
  raise notice 'F5-09 P2: criacao, edicao, ativacao (com materializacao F3-08/F3-09) e encerramento (reuso F5-06) validados — autorizacao, idempotencia, rollback, trilha e deny-by-default conformes.';
end $$;
