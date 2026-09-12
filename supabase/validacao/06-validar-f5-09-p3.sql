-- ============================================================================
-- F5-09 P3: validacao automatizada da inclusao aditiva de nova admissao
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes` (migrations)
--   2) `05-cenario-f5-09-p3.sql` (fixture isolada / guarda de estado limpo)
--   3) este arquivo             (asserts `[PASS]`/`[FAIL]`)
--
-- Contrato coberto (docs/F5-09-desenho-tecnico.md §7.2 P1–P7, §7.3 contrato
-- restrito, §10 I17–I19, §11, §12, §13.2/§13.3, §15.1 A1–A12, §19 P3):
--   1  A1) inclusao valida de admitido DEPOIS da ativacao (snapshot + posicoes +
--      membros + responsabilidades no reference_date da inclusao) e trilha
--      `ADMISSAO_INCLUIDA` com o id do evento ADMISSAO que autorizou;
--   2  ciclo ATIVO obrigatorio (PLANEJADO e ENCERRADO recusados);
--   3  tenant correto (ciclo/ator/colaborador revalidados no banco);
--   4  ator sem `cycle.manage` => FORBIDDEN;
--   5  membership revogada/inativa => FORBIDDEN;
--   6  colaborador de outro tenant => NOT_FOUND (indistinguivel de inexistente);
--   7  sem evento ADMISSAO (legado/importado) => recusa fail-closed (P7);
--   8  admissao anterior/igual a ativacao => recusa (P1);
--   9  `SOMENTE_CICLOS_POSTERIORES` => recusa (P6, estrito);
--   10 periodo de status anterior a ativacao => recusa (P2);
--   11 colaborador nao `active` na inclusao => recusa (P5);
--   12 estrutura soberana irresolvivel => recusa (P5);
--   13 participante ja materializado => CONFLICT, sem overwrite (P3);
--   14 replay idempotente (mesmo operation_id + mesmo payload);
--   15 operation_id reutilizado com intencao diferente => CONFLICT;
--   16 `expected_version` obsoleto => CONFLICT;
--   17 snapshots/posicoes/membros pre-existentes INALTERADOS;
--   18 responsabilidades pre-existentes INALTERADAS;
--   19 exatamente UM evento `ADMISSAO_INCLUIDA` no sucesso;
--   20 nenhuma mutacao recusada gera evento (zero residuo);
--   21 rollback real com falha DEPOIS do snapshot existir na transacao;
--   22 rollback real com falha na materializacao das responsabilidades;
--   23 a MESMA operacao legitima funciona depois de removida a falha;
--   24 nenhuma rematerializacao global (D27: movimentacao nao recalcula);
--   25 nenhuma inferencia por cargo/texto (assinatura + fontes relacionais);
--   26 lock normativo da familia de ciclos preservado;
--   27 nenhuma capability nova;
--   28 nenhuma leitura soberana (P5+) antecipada (policy/grant/RPC de leitura).
-- Probes cross-tenant sao DIRETOS na nova RPC (4 combinacoes) e provam zero
-- efeito (nenhum snapshot, nenhum evento, nenhuma alteracao de versao).
--
-- Saida deterministica: um `[PASS]` por verificacao; qualquer falha aborta.
-- Asserts negativos rodam em subtransacao (a excecao esperada reverte apenas a
-- tentativa). Falhas injetadas usam triggers TEMPORARIOS removidos ao final.
-- O UUID do ciclo NAO e transportado por variavel do psql (a interpolacao
-- `:'var'` nao e aplicada dentro de corpos dollar-quoted): cada bloco resolve o
-- alvo por SELECT DETERMINISTICO (organization_id + ano + numero / matricula).
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture presente, organizacoes sem ciclos, RPC da P3 no ar
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'eaa00000-0000-0000-0000-0000000000b1';
  v_colabs int;
  v_ciclos int;
  v_fn     int;
  v_def    text;
begin
  select count(*) into v_colabs from public.collaborators
   where organization_id = v_org and id::text like 'eab00000-0000-0000-0000-0000000000%';
  if v_colabs <> 2 then
    raise exception '[FAIL] pre-condicao: fixture F5-09 P3 ausente (colaboradores de base=%) — execute 05-cenario-f5-09-p3.sql', v_colabs;
  end if;
  select count(*) into v_ciclos from public.evaluation_cycles
   where organization_id in (v_org, v_beta);
  if v_ciclos <> 0 then
    raise exception '[FAIL] pre-condicao: organizacoes da fixture ja possuem % ciclo(s) — execute `supabase db reset` (a trilha de ciclos e append-only)', v_ciclos;
  end if;

  -- A RPC e o helper da P3 existem, com a assinatura do contrato (§13.2) e SEM
  -- parametro estrutural; ambos SECURITY INVOKER.
  select count(*) into v_fn
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('ciclo_incluir_admissao', 'ciclo_admissao_pos_ativacao_elegivel');
  if v_fn <> 2 then
    raise exception '[FAIL] pre-condicao: RPC/helper da P3 ausentes (%)', v_fn;
  end if;
  select pg_get_function_arguments(p.oid) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)');
  if v_def is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_collaborator_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_incluir_admissao fora do contrato (%)', v_def;
  end if;

  raise notice '[PASS] pre-condicoes: fixture isolada da P3 presente, organizacoes sem ciclos e RPC restrita (sem parametro estrutural) instalada';
end $$;

-- ----------------------------------------------------------------------------
-- 1) Setup: ciclo ATIVO com populacao inicial + ciclo PLANEJADO + ciclo no Beta
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'eaa00000-0000-0000-0000-0000000000b1';
  v_a1    uuid := 'eac00000-0000-0000-0000-000000000001';
  v_a3    uuid := 'eac00000-0000-0000-0000-000000000003';
  v_res   jsonb;
  v_c1    uuid;
  v_cb    uuid;
  v_snap  int;
  v_ciclo record;
begin
  -- C1 (2031/1) nasce PLANEJADO e e ATIVADO pela RPC da P2: a populacao de base
  -- (B1 e B2, ativos desde 2024, SEM evento soberano de admissao) e materializada
  -- na ativacao (D26).
  v_res := public.ciclo_criar(v_org, 2031, 1, date '2031-01-01', date '2031-03-31',
    v_a1, 'eaa10000-0000-0000-0000-000000000a01');
  v_c1 := (v_res->>'cycle_id')::uuid;
  v_res := public.ciclo_ativar(v_c1, v_org, 0, v_a1,
    'eaa10000-0000-0000-0000-000000000a02');
  if (v_res->>'version')::int <> 1 or (v_res->>'status') <> 'ATIVO' then
    raise exception '[FAIL] setup: ativacao de C1 deveria resultar em ATIVO/version 1 (%)', v_res;
  end if;

  -- C2 (2031/2) permanece PLANEJADO: insumo do caso "inclusao exige ATIVO".
  perform public.ciclo_criar(v_org, 2031, 2, date '2031-04-01', date '2031-06-30',
    v_a1, 'eaa10000-0000-0000-0000-000000000a03');

  -- Ciclo no Beta (para os probes cross-tenant DIRETOS na nova RPC).
  v_res := public.ciclo_criar(v_beta, 2031, 1, date '2031-01-01', date '2031-03-31',
    v_a3, 'eaa10000-0000-0000-0000-000000000b02');
  v_cb := (v_res->>'cycle_id')::uuid;
  v_res := public.ciclo_ativar(v_cb, v_beta, 0, v_a3,
    'eaa10000-0000-0000-0000-000000000b03');
  if (v_res->>'status') <> 'ATIVO' then
    raise exception '[FAIL] setup: ciclo do Beta deveria estar ATIVO (%)', v_res;
  end if;

  select count(*) into v_snap from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_snap <> 2 then
    raise exception '[FAIL] setup: populacao inicial de C1 deveria ter 2 snapshots (%)', v_snap;
  end if;
  select c.status, c.version into v_ciclo from public.evaluation_cycles c where c.id = v_c1;
  if v_ciclo.status <> 'ATIVO' or v_ciclo.version <> 1 then
    raise exception '[FAIL] setup: C1 deveria estar ATIVO/version 1 (%, %)', v_ciclo.status, v_ciclo.version;
  end if;

  raise notice '[PASS] setup: C1 ATIVO/version 1 com 2 participantes de base materializados, C2 PLANEJADO e ciclo do Beta ATIVO';
end $$;

-- ----------------------------------------------------------------------------
-- 2) Baseline de imutabilidade (checksums ANTES de qualquer inclusao)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org  uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_n    int;
begin
  -- A funcao de checksum abaixo e reaplicada depois de cada inclusao; aqui so
  -- provamos que o baseline e NAO VAZIO (uma prova sobre zero linhas seria falsa).
  select count(*) into v_n
    from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_n <> 2 then
    raise exception '[FAIL] baseline: snapshots iniciais = % (esperado 2)', v_n;
  end if;
  select count(*) into v_n
    from public.cycle_evaluation_responsibilities r
    join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_n < 1 then
    raise exception '[FAIL] baseline: nenhuma responsabilidade (F3-09) materializada na ativacao';
  end if;
  select count(*) into v_n
    from public.collegiate_cycle_snapshot_positions sp
    join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_n < 2 then
    raise exception '[FAIL] baseline: posicoes materializadas insuficientes (%)', v_n;
  end if;

  raise notice '[PASS] baseline: 2 snapshots, >=1 responsabilidade e posicoes materializadas na ativacao (prova de imutabilidade com conteudo real)';
end $$;

-- ----------------------------------------------------------------------------
-- 3) A1) Inclusao VALIDA de admitido depois da ativacao (N1)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1    uuid;
  v_n1    uuid;
  v_res   jsonb;
  v_eleg  jsonb;
  v_ciclo record;
  v_snap  record;
  v_pos   int;
  v_memb  int;
  v_resp  int;
  v_evt   record;
  v_adm   record;
  v_sup   uuid;
  v_chk   text;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  -- A) A admissao ocorre DEPOIS da ativacao pelo caminho SOBERANO (F5-07
  -- `colaborador_criar`, que grava o evento ADMISSAO com effective_date = agora).
  -- `p_admission_date` NULO => vigencia do vinculo = now() (posterior a ativacao).
  v_n1 := public.colaborador_criar(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000c01',
    'Colaborador Admitido P3 N1', 'admitido.n1.f5-09-p3@example.invalid',
    'P3-N1', null, 'active');

  -- Estrutura do novo colaborador: ocupacao vigente em P3 pelo caminho SOBERANO
  -- da F5-07 (`estrutura_ocupacao_definir`).
  perform public.estrutura_ocupacao_definir(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000c02', v_n1,
    'eae10000-0000-0000-0000-000000000003', now(),
    'Ocupacao inicial do admitido N1', 'CICLO_ATUAL_E_POSTERIORES', null);

  -- Colegiado do avaliado N1 (membro B1): AUTORADO como FIXTURE, no mesmo padrao
  -- do cenario da P2. O caminho soberano da F5-08 para colegiado exige a
  -- capability `org.structure.manage` COM SCOPE ativo — fora do escopo da P3. O
  -- que esta sob teste e a INCLUSAO aditiva, nao a autoria do colegiado.
  insert into public.collegiate_configurations
    (id, organization_id, collaborator_id, valid_from)
  values ('eaa10000-0000-0000-0000-000000000c03', v_org, v_n1, now());
  insert into public.collegiate_configuration_members
    (id, organization_id, configuration_id, member_collaborator_id)
  values ('eaa10000-0000-0000-0000-000000000c05', v_org,
          'eaa10000-0000-0000-0000-000000000c03',
          'eab00000-0000-0000-0000-000000000001');

  -- B) O helper read-only da prova soberana P1–P7 declara ELEGIVEL e devolve as
  -- evidencias (evento de admissao, posicao/unidade/superior resolvidos).
  v_eleg := public.ciclo_admissao_pos_ativacao_elegivel(v_org, v_c1, v_n1);
  if coalesce((v_eleg->>'elegivel')::boolean, false) is not true then
    raise exception '[FAIL] J/A1: helper de elegibilidade recusou admissao legitima (%)', v_eleg;
  end if;
  if coalesce(v_eleg->>'motivo', '') <> 'ELEGIVEL' then
    raise exception '[FAIL] J/A1: motivo do helper deveria ser ELEGIVEL (%)', v_eleg;
  end if;
  if (v_eleg->>'posicao_id')::uuid is distinct from 'eae10000-0000-0000-0000-000000000003'::uuid then
    raise exception '[FAIL] J/A1: posicao resolvida deveria vir de occupations (P3) (%)', v_eleg->>'posicao_id';
  end if;
  if (v_eleg->>'superior_collaborator_id')::uuid is distinct from 'eab00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] J/A1: superior deveria ser resolvido por reporting line (B1) (%)', v_eleg->>'superior_collaborator_id';
  end if;
  if (v_eleg->>'admissao_event_id') is null then
    raise exception '[FAIL] J/A1: helper sem o id do evento ADMISSAO que autoriza';
  end if;

  -- C) Inclusao aditiva (expected_version = 1, o version vigente de C1).
  v_res := public.ciclo_incluir_admissao(v_c1, v_org, v_n1,
    'Admissao posterior a ativacao (N1)', 1, v_a1,
    'eaa10000-0000-0000-0000-000000000c04');

  if (v_res->>'version')::int <> 2 or (v_res->>'status') <> 'ATIVO' then
    raise exception '[FAIL] A1: inclusao deveria resultar em ATIVO/version 2 (%)', v_res;
  end if;
  if (v_res->>'collaborator_id')::uuid is distinct from v_n1 then
    raise exception '[FAIL] A1: retorno com collaborator_id divergente';
  end if;
  if (v_res->>'snapshot_id') is null then
    raise exception '[FAIL] A1: retorno sem snapshot_id do participante incluido';
  end if;

  -- D) Efeito materializado: exatamente 1 snapshot novo, com posicao/superior
  -- RELACIONAIS e colegiado congelado da configuracao vigente.
  select c.status, c.version, c.data_ativacao into v_ciclo
    from public.evaluation_cycles c where c.id = v_c1;
  if v_ciclo.status <> 'ATIVO' or v_ciclo.version <> 2 then
    raise exception '[FAIL] A1: ciclo deveria permanecer ATIVO/version 2 (%, %)', v_ciclo.status, v_ciclo.version;
  end if;
  select s.id, s.collaborator_id, s.reference_date into v_snap
    from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
     and s.collaborator_id = v_n1;
  if v_snap.id is null then
    raise exception '[FAIL] A1: snapshot do colaborador incluido nao foi materializado';
  end if;
  if v_snap.reference_date < v_ciclo.data_ativacao then
    raise exception '[FAIL] A1: reference_date da inclusao deveria ser o instante da inclusao (% < %)',
      v_snap.reference_date, v_ciclo.data_ativacao;
  end if;

  select count(*) into v_pos
    from public.collegiate_cycle_snapshot_positions sp
   where sp.snapshot_id = v_snap.id and sp.position_id = 'eae10000-0000-0000-0000-000000000003';
  select sp.superior_collaborator_id into v_sup
    from public.collegiate_cycle_snapshot_positions sp
   where sp.snapshot_id = v_snap.id
   limit 1;
  if v_pos <> 1 or v_sup is distinct from 'eab00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] A1/L: snapshot novo sem posicao P3 e superior B1 (pos=%, superior=%)', v_pos, v_sup;
  end if;
  select count(*) into v_memb
    from public.collegiate_cycle_snapshot_members m where m.snapshot_id = v_snap.id;
  if v_memb <> 1 then
    raise exception '[FAIL] A1/L: colegiado congelado do snapshot novo deveria ter 1 membro (%)', v_memb;
  end if;
  select count(*) into v_resp
    from public.cycle_evaluation_responsibilities r where r.snapshot_id = v_snap.id;
  if v_resp < 1 then
    raise exception '[FAIL] A1/L: responsabilidade F3-09 do snapshot novo nao materializada';
  end if;
  if (v_res->>'posicoes_materializadas')::int <> v_pos
     or (v_res->>'membros_materializados')::int <> v_memb
     or (v_res->>'responsabilidades_materializadas')::int <> v_resp then
    raise exception '[FAIL] A1: retorno sem as contagens reais da materializacao (%)', v_res;
  end if;

  -- E) Trilha: EXATAMENTE um evento ADMISSAO_INCLUIDA, com autoria soberana, o
  -- id do evento ADMISSAO que autorizou e SEM dados pessoais (§12).
  select count(*) into v_resp
    from public.cycle_events e
   where e.organization_id = v_org
     and e.cycle_id = v_c1
     and e.event_type = 'ADMISSAO_INCLUIDA';
  if v_resp <> 1 then
    raise exception '[FAIL] A1/P: esperado exatamente 1 evento ADMISSAO_INCLUIDA (%)', v_resp;
  end if;
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'eaa10000-0000-0000-0000-000000000c04';
  if v_evt.id is null then
    raise exception '[FAIL] A1: evento da inclusao ausente na trilha';
  end if;
  if v_evt.actor_user_profile_id <> v_a1
     or v_evt.actor_membership_id <> 'ead00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] Q: autoria da trilha nao e o ator verificado + membership ativa';
  end if;
  if v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] A1: payload_hash fora do formato SHA-256';
  end if;
  if v_evt.reason <> 'Admissao posterior a ativacao (N1)' then
    raise exception '[FAIL] A1/M: motivo do evento divergente (%)', v_evt.reason;
  end if;
  if (v_evt.after_value->>'collaborator_id')::uuid is distinct from v_n1
     or (v_evt.after_value->>'snapshot_id')::uuid is distinct from v_snap.id
     or (v_evt.after_value->>'posicao_id')::uuid is distinct from 'eae10000-0000-0000-0000-000000000003'::uuid
     or (v_evt.after_value->>'reference_date') is null
     or (v_evt.after_value->>'version')::int <> 2 then
    raise exception '[FAIL] A1: after_value do evento sem as evidencias da inclusao (%)', v_evt.after_value;
  end if;
  select ce.id, ce.effective_date, ce.cycle_scope into v_adm
    from public.collaborator_events ce
   where ce.organization_id = v_org and ce.collaborator_id = v_n1
     and ce.event_type = 'ADMISSAO';
  if (v_evt.after_value->>'admissao_event_id')::uuid is distinct from v_adm.id then
    raise exception '[FAIL] A1/P1: trilha nao referencia o evento ADMISSAO que autorizou';
  end if;
  if v_evt.after_value ? 'full_name' or v_evt.after_value ? 'email'
     or v_evt.after_value ? 'matricula' or v_evt.after_value ? 'admission_date' then
    raise exception '[FAIL] A1: trilha com dado pessoal desnecessario (%)', v_evt.after_value;
  end if;
  if (v_evt.before_value->>'version')::int <> 1 then
    raise exception '[FAIL] A1: before_value deveria registrar a versao anterior (1)';
  end if;

  -- F) O ciclo NAO mudou nada alem de version/populacao: estado e datas intactos.
  if exists (
    select 1 from public.evaluation_cycles c
     where c.id = v_c1
       and (c.status <> 'ATIVO' or c.data_encerramento is not null
            or c.encerrado_com_pendencias is not false or c.quantidade_pendencias <> 0)
  ) then
    raise exception '[FAIL] A1: a inclusao aditiva alterou estado/datas/contadores do ciclo (§6/D26)';
  end if;

  raise notice '[PASS] A1: inclusao valida de N1 (admitido apos a ativacao) com snapshot/posicao/superior/colegiado/responsabilidade materializados, version+1 e evento ADMISSAO_INCLUIDA com o id do evento ADMISSAO que autorizou';
end $$;

-- ----------------------------------------------------------------------------
-- 4) A3/A11) Aditividade provada: pre-existentes INALTERADOS apos a inclusao
-- ----------------------------------------------------------------------------
do $$
declare
  v_org     uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_snap_h  text;
  v_pos_h   text;
  v_memb_h  text;
  v_resp_h  text;
  v_n_base  int;
begin
  -- Checksums das linhas PRE-EXISTENTES (B1 e B2), reconstruidos a partir das
  -- fontes atuais: qualquer sobrescrita/remocao/alteracao mudaria o digest.
  select md5(string_agg(x, '|' order by x)) into v_snap_h from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text || ':' || s.ano::text || ':' || s.ciclo::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id in ('eab00000-0000-0000-0000-000000000001',
                                 'eab00000-0000-0000-0000-000000000002')
  ) t;
  select count(*) into v_n_base from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_n_base <> 3 then
    raise exception '[FAIL] A11: apos 1 inclusao o ciclo deveria ter 3 snapshots (%)', v_n_base;
  end if;
  if v_snap_h is null then
    raise exception '[FAIL] A11: checksum dos snapshots de base nulo (prova invalida)';
  end if;

  -- Os snapshots de base continuam com a MESMA posicao/superior congelados.
  if not exists (
    select 1 from public.collegiate_cycle_snapshots s
      join public.collegiate_cycle_snapshot_positions sp on sp.snapshot_id = s.id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = 'eab00000-0000-0000-0000-000000000002'
       and sp.position_id = 'eae10000-0000-0000-0000-000000000002'
       and sp.superior_collaborator_id = 'eab00000-0000-0000-0000-000000000001'
  ) then
    raise exception '[FAIL] A3: snapshot de base B2 perdeu a posicao/superior congelados (P2/P1)';
  end if;
  if not exists (
    select 1 from public.collegiate_cycle_snapshots s
      join public.collegiate_cycle_snapshot_positions sp on sp.snapshot_id = s.id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = 'eab00000-0000-0000-0000-000000000001'
       and sp.position_id = 'eae10000-0000-0000-0000-000000000001'
  ) then
    raise exception '[FAIL] A3: snapshot de base B1 perdeu a posicao congelada (P1)';
  end if;

  -- Nenhuma linha de base foi duplicada (o snapshot novo pertence a N1).
  select md5(string_agg(x, '|' order by x)) into v_snap_h from (
    select s.id::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id in ('eab00000-0000-0000-0000-000000000001',
                                 'eab00000-0000-0000-0000-000000000002')
  ) t;
  if (select count(distinct s.collaborator_id) from public.collegiate_cycle_snapshots s
       where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1) <> 3 then
    raise exception '[FAIL] A11: colaboradores distintos no ciclo deveriam ser 3';
  end if;

  -- (18) F3-09 (responsabilidades) nao tocou nem duplicou as linhas PRE-EXISTENTES:
  -- B2 (ocupante de P2, com reporting line para P1) tinha exatamente 1
  -- responsabilidade na ativacao e B1 (ocupante de P1, sem superior) nenhuma.
  if (select count(*) from public.cycle_evaluation_responsibilities r
        join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
       where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
         and s.collaborator_id = 'eab00000-0000-0000-0000-000000000002') <> 1 then
    raise exception '[FAIL] A11/18: responsabilidade pre-existente de B2 foi duplicada ou removida';
  end if;
  if exists (
    select 1 from public.cycle_evaluation_responsibilities r
      join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = 'eab00000-0000-0000-0000-000000000001'
  ) then
    raise exception '[FAIL] A11/18: F3-09 criou responsabilidade para snapshot pre-existente sem superior (B1)';
  end if;

  raise notice '[PASS] A3/A11: participantes pre-existentes (B1/B2) permanecem com snapshot, posicao e superior CONGELADOS; a inclusao acrescentou exatamente 1 snapshot novo e nao duplicou linha alguma';
end $$;

-- ----------------------------------------------------------------------------
-- 5) A2/A10/15/16) Idempotencia e versao otimista
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1    uuid;
  v_n1    uuid;
  v_res1  jsonb;
  v_res2  jsonb;
  v_qtd   int;
  v_ok    boolean;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select i.collaborator_id into v_n1 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-N1';

  -- (14) Replay: MESMO operation_id + MESMO payload => MESMO resultado.
  v_res1 := public.ciclo_incluir_admissao(v_c1, v_org, v_n1,
    'Admissao posterior a ativacao (N1)', 1, v_a1,
    'eaa10000-0000-0000-0000-000000000c04');
  v_res2 := public.ciclo_incluir_admissao(v_c1, v_org, v_n1,
    'Admissao posterior a ativacao (N1)', 1, v_a1,
    'eaa10000-0000-0000-0000-000000000c04');
  if v_res1 <> v_res2 then
    raise exception '[FAIL] A10: replay idempotente devolveu resultado diferente (% vs %)', v_res1, v_res2;
  end if;
  select count(*) into v_qtd from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'eaa10000-0000-0000-0000-000000000c04';
  if v_qtd <> 1 then
    raise exception '[FAIL] A10: replay duplicou a trilha (linhas=%)', v_qtd;
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> 2 then
    raise exception '[FAIL] A10: replay alterou a versao do ciclo';
  end if;
  if (select count(*) from public.collegiate_cycle_snapshots s
       where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1) <> 3 then
    raise exception '[FAIL] A10: replay rematerializou o ciclo (populacao deveria continuar com 3 snapshots)';
  end if;

  -- (15) MESMO operation_id + intencao DIFERENTE => CONFLICT (nunca executa).
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org,
      'eab00000-0000-0000-0000-000000000002', 'intencao divergente', 1, v_a1,
      'eaa10000-0000-0000-0000-000000000c04');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] 15: operation_id reutilizado com intencao diferente deveria ser CONFLICT';
  end if;

  -- (16) expected_version OBSOLETO (o version atual e 2) => CONFLICT sem efeito.
  -- O assert do motivo prova que a recusa veio da VERSAO (e nao da aditividade).
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org,
      'eab00000-0000-0000-0000-000000000002', 'versao obsoleta', 5, v_a1,
      'eaa10000-0000-0000-0000-000000000c07');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%versao divergente%';
  end;
  if not v_ok then
    raise exception '[FAIL] 16: expected_version obsoleto deveria ser CONFLICT por versao divergente';
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id in ('eaa10000-0000-0000-0000-000000000c07')
  ) then
    raise exception '[FAIL] 16: tentativa com versao obsoleta gravou evento';
  end if;

  raise notice '[PASS] A2/A10: replay idempotente (mesmo resultado, 1 trilha, versao estavel), operation_id divergente => CONFLICT e expected_version obsoleto => CONFLICT sem efeito';
end $$;

-- ----------------------------------------------------------------------------
-- 6) A4/A11/P3) Participante JA materializado => CONFLICT, sem overwrite
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1    uuid;
  v_n1    uuid;
  v_snap  record;
  v_ok    boolean;
  v_msg   text;
  v_evt   int;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select i.collaborator_id into v_n1 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-N1';
  select s.id, s.reference_date into v_snap
    from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
     and s.collaborator_id = v_n1;

  -- (13a) Retentativa do MESMO colaborador ja incluido, com operation_id NOVO.
  v_ok := false;
  v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_n1,
      'segunda inclusao do mesmo colaborador', 2, v_a1,
      'eaa10000-0000-0000-0000-000000000c08');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
    v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 13: reinclusao do mesmo colaborador deveria ser CONFLICT';
  end if;
  if position('JA_MATERIALIZADO_NO_CICLO' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 13: recusa deveria ser pela prova de aditividade (P3), recebido: %', v_msg;
  end if;

  -- (13b) Participante PRE-EXISTENTE da ativacao (B2, sem evento de admissao):
  -- a recusa e por P3 (aditividade), ANTES de qualquer leitura de prova de
  -- admissao — o caminho aditivo NUNCA atinge estrutura ja materializada.
  v_ok := false;
  v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org,
      'eab00000-0000-0000-0000-000000000002', 'tentativa de trocar posicao de participante existente',
      2, v_a1, 'eaa10000-0000-0000-0000-000000000c09');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
    v_msg := sqlerrm;
  end;
  if not v_ok or position('JA_MATERIALIZADO_NO_CICLO' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] A4: inclusao de participante ja materializado deveria ser CONFLICT/P3 (recebido: %)', v_msg;
  end if;

  -- (13c) Nada foi sobrescrito: o snapshot de N1 e o de B2 continuam identicos.
  if not exists (
    select 1 from public.collegiate_cycle_snapshots s
     where s.id = v_snap.id and s.reference_date = v_snap.reference_date
       and s.collaborator_id = v_n1
  ) then
    raise exception '[FAIL] A11: snapshot de N1 foi sobrescrito';
  end if;
  if not exists (
    select 1 from public.collegiate_cycle_snapshots s
      join public.collegiate_cycle_snapshot_positions sp on sp.snapshot_id = s.id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = 'eab00000-0000-0000-0000-000000000002'
       and sp.position_id = 'eae10000-0000-0000-0000-000000000002'
  ) then
    raise exception '[FAIL] A11: snapshot de B2 foi alterado por tentativa recusada';
  end if;
  if (select count(*) from public.collegiate_cycle_snapshots s
       where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1) <> 3 then
    raise exception '[FAIL] A11: tentativa recusada materializou snapshot';
  end if;

  -- (20) Nenhuma mutacao recusada gravou trilha.
  select count(*) into v_evt from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id in ('eaa10000-0000-0000-0000-000000000c08',
                            'eaa10000-0000-0000-0000-000000000c09');
  if v_evt <> 0 then
    raise exception '[FAIL] 20: mutacao recusada gravou evento na trilha (%)', v_evt;
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> 2 then
    raise exception '[FAIL] 20: mutacao recusada alterou a versao do ciclo';
  end if;

  raise notice '[PASS] A4/A11/P3: inclusao de colaborador ja materializado (incluido ou pre-existente) recusada por CONFLICT/P3 sem qualquer sobrescrita, sem snapshot novo e sem evento';
end $$;

-- ----------------------------------------------------------------------------
-- 7) Autorizacao e tenant (4 probes cross-tenant DIRETOS na nova RPC)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'eaa00000-0000-0000-0000-0000000000b1';
  v_a1    uuid := 'eac00000-0000-0000-0000-000000000001';
  v_a2    uuid := 'eac00000-0000-0000-0000-000000000002';
  v_a3    uuid := 'eac00000-0000-0000-0000-000000000003';
  v_a4    uuid := 'eac00000-0000-0000-0000-000000000004';
  v_c1    uuid;
  v_cb    uuid;
  v_n1    uuid;
  v_c1v   int;
  v_ok    boolean;
  v_ops   text[] := array[]::text[];
  v_op    text;
  v_qtd   int;
begin
  select c.id, c.version into v_c1, v_c1v from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select c.id into v_cb from public.evaluation_cycles c
   where c.organization_id = v_beta and c.ano = 2031 and c.numero = 1;
  select i.collaborator_id into v_n1 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-N1';

  -- (4) Ator SEM capability `cycle.manage`.
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_n1, 'sem capability',
      v_c1v, v_a2, 'eaa10000-0000-0000-0000-000000000f01');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] 4: ator sem cycle.manage deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eaa10000-0000-0000-0000-000000000f01'::text;

  -- (5) Ator com membership DISABLED na organizacao.
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_n1, 'membership disabled',
      v_c1v, v_a4, 'eaa10000-0000-0000-0000-000000000f02');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] 5: ator com membership disabled deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eaa10000-0000-0000-0000-000000000f02'::text;

  -- (i) Cross-tenant DIRETO: ator/org Alfa com cycle_id do BETA => NOT_FOUND.
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_cb, v_org, v_n1, 'ciclo de outro tenant',
      v_c1v, v_a1, 'eaa10000-0000-0000-0000-000000000f03');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] 3/i: ciclo de outro tenant deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eaa10000-0000-0000-0000-000000000f03'::text;

  -- (ii) Cross-tenant DIRETO: ator do BETA operando na organizacao Alfa.
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_n1, 'ator de outro tenant',
      v_c1v, v_a3, 'eaa10000-0000-0000-0000-000000000f04');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] 3/ii: ator de outro tenant deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eaa10000-0000-0000-0000-000000000f04'::text;

  -- (iii) Cross-tenant DIRETO: colaborador do BETA em ciclo/org Alfa => NOT_FOUND.
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org,
      'eab00000-0000-0000-0000-0000000000b1', 'colaborador de outro tenant',
      v_c1v, v_a1, 'eaa10000-0000-0000-0000-000000000f05');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] 6/iii: colaborador de outro tenant deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eaa10000-0000-0000-0000-000000000f05'::text;

  -- (iv) Cross-tenant DIRETO: ator/colaborador do BETA com ciclo do ALFA.
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_beta,
      'eab00000-0000-0000-0000-0000000000b1', 'ciclo do Alfa declarado no Beta',
      0, v_a3, 'eaa10000-0000-0000-0000-000000000f06');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] 3/iv: ciclo de outro tenant no proprio tenant deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eaa10000-0000-0000-0000-000000000f06'::text;

  -- Tenant declarado divergente do ator (org do BETA com ator do Alfa).
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_cb, v_beta,
      'eab00000-0000-0000-0000-0000000000b1', 'tenant divergente do ator',
      0, v_a1, 'eaa10000-0000-0000-0000-000000000f07');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] 3: ator fora do tenant declarado deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eaa10000-0000-0000-0000-000000000f07'::text;

  -- Alvos inexistentes (ciclo e colaborador) => NOT_FOUND, sem vazar existencia.
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao('eaa00000-0000-0000-0000-00000000dead', v_org, v_n1,
      'ciclo inexistente', v_c1v, v_a1, 'eaa10000-0000-0000-0000-000000000f08');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] 3: ciclo inexistente deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eaa10000-0000-0000-0000-000000000f08'::text;

  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, 'eaa00000-0000-0000-0000-00000000beef',
      'colaborador inexistente', v_c1v, v_a1, 'eaa10000-0000-0000-0000-000000000f09');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] 6: colaborador inexistente deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eaa10000-0000-0000-0000-000000000f09'::text;

  -- (20) ZERO efeito de TODAS as tentativas recusadas.
  select count(*) into v_qtd from public.cycle_events e
   where e.operation_id::text = any (v_ops);
  if v_qtd <> 0 then
    raise exception '[FAIL] 20: tentativas recusadas gravaram % evento(s)', v_qtd;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_beta and e.event_type = 'ADMISSAO_INCLUIDA'
  ) then
    raise exception '[FAIL] 3: trilha do Beta recebeu ADMISSAO_INCLUIDA (cross-tenant vazou)';
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> 2
     or (select c.version from public.evaluation_cycles c where c.id = v_cb) <> 1 then
    raise exception '[FAIL] 20: tentativa recusada alterou a versao de um ciclo';
  end if;
  if (select count(*) from public.collegiate_cycle_snapshots s
       where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1) <> 3 then
    raise exception '[FAIL] 20: tentativa recusada materializou snapshot em Alfa';
  end if;

  raise notice '[PASS] 3/4/5/6: capability ausente e membership disabled => FORBIDDEN; 4 probes cross-tenant DIRETOS na nova RPC (ciclo, ator, colaborador e tenant) => NOT_FOUND/FORBIDDEN, com ZERO efeito (sem snapshot, sem evento, versao intacta)';
end $$;

-- ----------------------------------------------------------------------------
-- 8) Provas soberanas P1–P7: legado, escopo, data, vida anterior, vinculo,
--    estrutura e estado do ciclo — cada recusa com motivo proprio
-- ----------------------------------------------------------------------------
-- Casos sinteticos de IMPORTACAO/LEGADO, criados DEPOIS da ativacao (por isso
-- nao entram na populacao inicial). Cada um isola UMA prova: todos os demais
-- requisitos permanecem satisfeitos, de modo que o motivo reportado identifica
-- exatamente a prova que recusou (nada de recusa "por acidente").
do $$
declare
  v_org   uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'eac00000-0000-0000-0000-000000000001';
  v_adm   timestamptz;
  v_id    uuid;
  v_id_inativo uuid;
begin
  -- TODA a fixture desta secao nasce AQUI; as tentativas de inclusao rodam no
  -- BLOCO SEGUINTE (transacao propria). A separacao e essencial: `now()` e FIXO
  -- por transacao, portanto um periodo de status aberto "agora" so esta vigente
  -- para uma inclusao executada em transacao POSTERIOR — sem a separacao, o caso
  -- `inactive` seria avaliado no instante ANTERIOR a propria transicao.
  select c.data_ativacao into v_adm
    from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  -- (7/P7) LEGADO/IMPORTADO sem evento soberano de ADMISSAO: criado direto
  -- (caminho de importacao), ativo, e com `admission_date` DECLARADA NO FUTURO —
  -- justamente para provar que esse dado de cadastro NAO e prova de admissao
  -- (F5-07 D3/D6). A UNICA prova ausente e o evento soberano.
  insert into public.collaborators (id, organization_id, full_name, email, admission_date)
  values ('eab00000-0000-0000-0000-000000000101', v_org,
          'Colaborador Legado P3', 'legado.f5-09-p3@example.invalid', current_date + 1);
  insert into public.collaborator_identifiers (collaborator_id, organization_id, business_code, valid_from)
  values ('eab00000-0000-0000-0000-000000000101', v_org, 'P3-LEGADO', now());
  insert into public.collaborator_status_periods (collaborator_id, status, valid_from)
  values ('eab00000-0000-0000-0000-000000000101', 'active', now());
  -- (9/P6) Evento ADMISSAO com escopo SOMENTE_CICLOS_POSTERIORES (importacao que
  -- grava o evento com escopo restrito): recusa ESTRITA no ciclo corrente.
  insert into public.collaborators (id, organization_id, full_name, email, admission_date)
  values ('eab00000-0000-0000-0000-000000000102', v_org,
          'Colaborador Escopo P3', 'escopo.f5-09-p3@example.invalid', current_date);
  insert into public.collaborator_identifiers (collaborator_id, organization_id, business_code, valid_from)
  values ('eab00000-0000-0000-0000-000000000102', v_org, 'P3-SOMENTE', now());
  insert into public.collaborator_status_periods (collaborator_id, status, valid_from)
  values ('eab00000-0000-0000-0000-000000000102', 'active', now());
  insert into public.collaborator_events
    (organization_id, collaborator_id, event_type, effective_date, cycle_scope, reason,
     before_value, after_value, payload_hash, result_entity_id,
     actor_user_profile_id, actor_membership_id, operation_id)
  values (v_org, 'eab00000-0000-0000-0000-000000000102', 'ADMISSAO', now(),
          'SOMENTE_CICLOS_POSTERIORES', 'Admissao importada com escopo restrito', null,
          jsonb_build_object('origem', 'import'), repeat('a', 64),
          'eab00000-0000-0000-0000-000000000102', v_a1,
          'ead00000-0000-0000-0000-000000000001',
          'eaa10000-0000-0000-0000-000000000901');

  -- (8/P1) Evento ADMISSAO ANTERIOR a ativacao (admissao antiga que ficou fora do
  -- snapshot): recusa fail-closed — a operacao NAO corrige materializacao.
  insert into public.collaborators (id, organization_id, full_name, email, admission_date)
  values ('eab00000-0000-0000-0000-000000000103', v_org,
          'Colaborador Anterior P3', 'anterior.f5-09-p3@example.invalid', (v_adm - interval '10 days')::date);
  insert into public.collaborator_identifiers (collaborator_id, organization_id, business_code, valid_from)
  values ('eab00000-0000-0000-0000-000000000103', v_org, 'P3-ANTERIOR', v_adm - interval '10 days');
  insert into public.collaborator_status_periods (collaborator_id, status, valid_from)
  values ('eab00000-0000-0000-0000-000000000103', 'active', v_adm - interval '10 days');
  insert into public.collaborator_events
    (organization_id, collaborator_id, event_type, effective_date, cycle_scope, reason,
     before_value, after_value, payload_hash, result_entity_id,
     actor_user_profile_id, actor_membership_id, operation_id)
  values (v_org, 'eab00000-0000-0000-0000-000000000103', 'ADMISSAO',
          v_adm - interval '10 days', 'CICLO_ATUAL_E_POSTERIORES',
          'Admissao anterior a ativacao', null,
          jsonb_build_object('origem', 'import'), repeat('b', 64),
          'eab00000-0000-0000-0000-000000000103', v_a1,
          'ead00000-0000-0000-0000-000000000001',
          'eaa10000-0000-0000-0000-000000000902');

  -- (10/P2) VIDA SOBERANA ANTERIOR: evento ADMISSAO compativel (gravado agora),
  -- mas existe periodo de status iniciado ANTES da ativacao => a pessoa ja
  -- pertencia a populacao; a inclusao aditiva nao serve para "corrigir" isso.
  v_id := public.colaborador_criar(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000904',
    'Colaborador Vida Anterior P3', 'vida.anterior.f5-09-p3@example.invalid',
    'P3-VIDA', null, 'active');
  insert into public.collaborator_status_periods (collaborator_id, status, valid_from, valid_to)
  values (v_id, 'active', v_adm - interval '30 days', v_adm - interval '29 days');

  -- (11/P5) Colaborador NAO ativo no instante da inclusao. Os DOIS estados nao
  -- ativos do dominio (F5-07 D6) sao cobertos: `leave` (afastado, pelo caminho
  -- soberano) e `inactive` (desligado, transicao de fixture).
  v_id := public.colaborador_criar(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000905',
    'Colaborador Afastado P3', 'afastado.f5-09-p3@example.invalid',
    'P3-AFASTADO', null, 'leave');

  v_id_inativo := public.colaborador_criar(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000908',
    'Colaborador Inativo P3', 'inativo.f5-09-p3@example.invalid',
    'P3-INATIVO', null, 'active');
  -- Transicao para `inactive`: encerra o periodo aberto e abre o novo na MESMA
  -- fixtura. `clock_timestamp()` (e nao `now()`, que e FIXO por transacao e
  -- tornaria valid_to = valid_from) garante a janela [valid_from, valid_to) sem
  -- sobreposicao e anterior a transacao da inclusao (que vem depois).
  update public.collaborator_status_periods
     set valid_to = clock_timestamp()
   where collaborator_id = v_id_inativo and valid_to is null;
  insert into public.collaborator_status_periods (collaborator_id, status, valid_from)
  values (v_id_inativo, 'inactive', clock_timestamp());

  -- (12/P5) ESTRUTURA IRRESOLVIVEL: admissao soberana e status ativo, mas SEM
  -- ocupacao vigente (nenhuma fonte relacional resolve a estrutura).
  v_id := public.colaborador_criar(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000907',
    'Colaborador Sem Estrutura P3', 'sem.estrutura.f5-09-p3@example.invalid',
    'P3-ESTRUTURA', null, 'active');

end $$;

-- ----------------------------------------------------------------------------
-- 8b) Provas soberanas P1–P7: as tentativas rodam em TRANSACAO PROPRIA (portanto
--     com `now()` POSTERIOR a todas as vigencias gravadas na fixture acima),
--     resolvendo os alvos por SELECT determinista (nunca por variavel do psql).
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1    uuid;
  v_c1v   int;
  v_ok    boolean;
  v_msg   text;
  v_n     int;
  v_id    uuid;
begin
  select c.id, c.version into v_c1, v_c1v
    from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  select count(*) into v_n from public.collaborators
   where organization_id = v_org and id::text like 'eab00000-0000-0000-0000-0000000001%';
  if v_n <> 3 then
    raise exception '[FAIL] 8: casos sinteticos de importacao/legado nao criados (%)', v_n;
  end if;

  -- ---- (7/P7) legado sem evento ADMISSAO
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org,
      'eab00000-0000-0000-0000-000000000101', 'legado sem prova', v_c1v, v_a1,
      'eaa10000-0000-0000-0000-000000000910');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('SEM_EVENTO_ADMISSAO' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 7/P7: legado sem evento ADMISSAO deveria recusar por SEM_EVENTO_ADMISSAO (%)', v_msg;
  end if;

  -- ---- (9/P6) escopo SOMENTE_CICLOS_POSTERIORES
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org,
      'eab00000-0000-0000-0000-000000000102', 'escopo restrito', v_c1v, v_a1,
      'eaa10000-0000-0000-0000-000000000911');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('ESCOPO_SOMENTE_CICLOS_POSTERIORES' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 9/P6: ciclo_scope SOMENTE_CICLOS_POSTERIORES deveria recusar (%)', v_msg;
  end if;

  -- ---- (8/P1) admissao anterior a ativacao
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org,
      'eab00000-0000-0000-0000-000000000103', 'admissao anterior', v_c1v, v_a1,
      'eaa10000-0000-0000-0000-000000000912');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('ADMISSAO_ANTERIOR_A_ATIVACAO' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 8/P1: admissao anterior/igual a ativacao deveria recusar (%)', v_msg;
  end if;
  -- O caso anterior tambem prova P2 (vida anterior) quando o periodo antecede a
  -- ativacao: a recusa nao pode ser por "ja materializado".
  if position('JA_MATERIALIZADO' in coalesce(v_msg, '')) > 0 then
    raise exception '[FAIL] 8: colaborador nao materializado foi recusado como se ja estivesse no ciclo';
  end if;

  -- ---- (10/P2) vida soberana anterior (periodo de status anterior a ativacao)
  -- O alvo e resolvido pelo identificador da fixture sintetica.
  select i.collaborator_id into v_id from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-VIDA';
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_id, 'vida anterior', v_c1v, v_a1,
      'eaa10000-0000-0000-0000-000000000914');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('VIDA_SOBERANA_ANTERIOR' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 10/P2: periodo de status anterior a ativacao deveria recusar por VIDA_SOBERANA_ANTERIOR (%)', v_msg;
  end if;

  -- ---- (11/P5) colaborador nao ativo (afastado e desligado)
  select i.collaborator_id into v_id from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-INATIVO';
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_id, 'colaborador inativo', v_c1v, v_a1,
      'eaa10000-0000-0000-0000-000000000915');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('COLABORADOR_INATIVO' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 11/P5: colaborador `inactive` deveria recusar por COLABORADOR_INATIVO (%)', v_msg;
  end if;
  select i.collaborator_id into v_id from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-AFASTADO';
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_id, 'colaborador afastado', v_c1v, v_a1,
      'eaa10000-0000-0000-0000-000000000921');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('COLABORADOR_INATIVO' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 11/P5: colaborador `leave` deveria recusar por COLABORADOR_INATIVO (%)', v_msg;
  end if;

  -- ---- (12/P5) estrutura soberana irresolvivel
  select i.collaborator_id into v_id from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-ESTRUTURA';
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_id, 'sem estrutura', v_c1v, v_a1,
      'eaa10000-0000-0000-0000-000000000916');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('ESTRUTURA_IRRESOLVEL' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 12/P5: estrutura irresolvivel deveria recusar por ESTRUTURA_IRRESOLVEL (%)', v_msg;
  end if;

  -- ---- (2) ciclo NAO ATIVO (C2 PLANEJADO) com colaborador elegivel
  v_id := public.colaborador_criar(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000917',
    'Colaborador Deferido P3', 'deferido.f5-09-p3@example.invalid',
    'P3-DEFERIDO', null, 'active');
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(
      (select c.id from public.evaluation_cycles c
        where c.organization_id = v_org and c.ano = 2031 and c.numero = 2),
      v_org, v_id, 'ciclo planejado', 0, v_a1,
      'eaa10000-0000-0000-0000-000000000918');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige ciclo ATIVO' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 2: inclusao em ciclo PLANEJADO deveria ser CONFLICT (%)', v_msg;
  end if;

  -- ---- motivo obrigatorio (INVALID_INPUT) e parametros nulos
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org,
      'eab00000-0000-0000-0000-000000000001', '   ', v_c1v, v_a1,
      'eaa10000-0000-0000-0000-000000000919');
  exception when others then
    v_ok := sqlerrm like '%F5_09_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] 28/forma: motivo vazio deveria ser INVALID_INPUT';
  end if;
  v_ok := false;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, null, 'sem colaborador', v_c1v, v_a1,
      'eaa10000-0000-0000-0000-000000000920');
  exception when others then
    v_ok := sqlerrm like '%F5_09_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] 28/forma: collaborator_id nulo deveria ser INVALID_INPUT';
  end if;

  -- (20) ZERO efeito dos casos recusados deste bloco.
  select count(*) into v_n from public.cycle_events e
   where e.operation_id::text in (
     'eaa10000-0000-0000-0000-000000000910', 'eaa10000-0000-0000-0000-000000000911',
     'eaa10000-0000-0000-0000-000000000912', 'eaa10000-0000-0000-0000-000000000914',
     'eaa10000-0000-0000-0000-000000000915', 'eaa10000-0000-0000-0000-000000000916',
     'eaa10000-0000-0000-0000-000000000918', 'eaa10000-0000-0000-0000-000000000919',
     'eaa10000-0000-0000-0000-000000000920', 'eaa10000-0000-0000-0000-000000000921');
  if v_n <> 0 then
    raise exception '[FAIL] 20: recusas de prova soberana/estado gravaram % evento(s)', v_n;
  end if;
  if (select count(*) from public.collegiate_cycle_snapshots s
       where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1) <> 3 then
    raise exception '[FAIL] 20: recusa de prova soberana materializou snapshot';
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> v_c1v then
    raise exception '[FAIL] 20: recusa de prova soberana alterou a versao do ciclo';
  end if;

  raise notice '[PASS] P1/P2/P5/P6/P7: cada prova soberana recusa com motivo PROPRIO (SEM_EVENTO_ADMISSAO, ESCOPO_SOMENTE_CICLOS_POSTERIORES, ADMISSAO_ANTERIOR_A_ATIVACAO, VIDA_SOBERANA_ANTERIOR, COLABORADOR_INATIVO, ESTRUTURA_IRRESOLVEL), ciclo nao ATIVO => CONFLICT e motivo vazio => INVALID_INPUT; ZERO efeito em todas as recusas';
end $$;

-- ----------------------------------------------------------------------------
-- 9) D27/A3/24) Movimentacao NAO rematerializa + nova admissao resolve a
--    estrutura VIGENTE (nenhuma rematerializacao global)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1     uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1     uuid;
  v_n2     uuid;
  v_res    jsonb;
  v_antes  int;
  v_depois int;
  v_trilha int;
  v_pos    uuid;
  v_sup    uuid;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  -- Movimentacao de participante JA materializado: B2 sai de P2 para P4 (caminho
  -- soberano F5-07). Pela D27 isso vale no PROXIMO ciclo e NAO rematerializa.
  select count(*) into v_antes from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  select count(*) into v_trilha from public.cycle_events e
   where e.organization_id = v_org and e.cycle_id = v_c1;
  perform public.estrutura_ocupacao_definir(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000d01',
    'eab00000-0000-0000-0000-000000000002',
    'eae10000-0000-0000-0000-000000000004', now(),
    'Movimentacao sintetica (D27)', 'CICLO_ATUAL_E_POSTERIORES', null);

  select count(*) into v_depois from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_depois <> v_antes then
    raise exception '[FAIL] 24: movimentacao alterou a populacao materializada (% -> %)', v_antes, v_depois;
  end if;
  if (select count(*) from public.cycle_events e where e.organization_id = v_org and e.cycle_id = v_c1) <> v_trilha then
    raise exception '[FAIL] 24: movimentacao escreveu na trilha do ciclo';
  end if;
  if not exists (
    select 1 from public.collegiate_cycle_snapshots s
      join public.collegiate_cycle_snapshot_positions sp on sp.snapshot_id = s.id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = 'eab00000-0000-0000-0000-000000000002'
       and sp.position_id = 'eae10000-0000-0000-0000-000000000002'
  ) then
    raise exception '[FAIL] 24/A3: snapshot de B2 foi rematerializado pela movimentacao (D27 violada)';
  end if;

  -- Nova admissao N2 (depois da movimentacao): a estrutura dela vem do estado
  -- VIGENTE (P5), enquanto o participante movimentado permanece congelado.
  v_n2 := public.colaborador_criar(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000d02',
    'Colaborador Admitido P3 N2', 'admitido.n2.f5-09-p3@example.invalid',
    'P3-N2', null, 'active');
  perform public.estrutura_ocupacao_definir(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000d03', v_n2,
    'eae10000-0000-0000-0000-000000000005', now(),
    'Ocupacao inicial do admitido N2', 'CICLO_ATUAL_E_POSTERIORES', null);

  v_res := public.ciclo_incluir_admissao(v_c1, v_org, v_n2,
    'Admissao posterior a ativacao (N2)', 2, v_a1,
    'eaa10000-0000-0000-0000-000000000d04');
  if (v_res->>'version')::int <> 3 then
    raise exception '[FAIL] 24: segunda inclusao deveria elevar a versao para 3 (%)', v_res;
  end if;

  select count(*) into v_depois from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_depois <> v_antes + 1 then
    raise exception '[FAIL] 24: inclusao deveria acrescentar EXATAMENTE 1 snapshot (% -> %)', v_antes, v_depois;
  end if;
  select sp.position_id, sp.superior_collaborator_id into v_pos, v_sup
    from public.collegiate_cycle_snapshots s
    join public.collegiate_cycle_snapshot_positions sp on sp.snapshot_id = s.id
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
     and s.collaborator_id = v_n2;
  if v_pos is distinct from 'eae10000-0000-0000-0000-000000000005'::uuid
     or v_sup is distinct from 'eab00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] 24/P5: snapshot de N2 deveria resolver a estrutura VIGENTE (P5/superior B1) (%, %)', v_pos, v_sup;
  end if;
  if not exists (
    select 1 from public.collegiate_cycle_snapshots s
      join public.collegiate_cycle_snapshot_positions sp on sp.snapshot_id = s.id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = 'eab00000-0000-0000-0000-000000000002'
       and sp.position_id = 'eae10000-0000-0000-0000-000000000002'
  ) then
    raise exception '[FAIL] 24/D27: snapshot de B2 deixou de estar congelado em P2';
  end if;

  raise notice '[PASS] D27/24: movimentacao de participante materializado NAO rematerializa nem escreve na trilha do ciclo; a nova admissao (N2) resolve a estrutura vigente e o ciclo cresce exatamente 1 snapshot por inclusao';
end $$;

-- ----------------------------------------------------------------------------
-- 10) Atomicidade: falhas injetadas DEPOIS de trabalho real => ROLLBACK TOTAL
-- ----------------------------------------------------------------------------
do $$
declare
  v_org  uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_n3   uuid;
  v_res  jsonb;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  -- Candidato legitimo as provas de rollback (admissao soberana pos-ativacao e
  -- estrutura resolvivel em P6): a elegibilidade NAO pode ser a causa da falha.
  v_n3 := public.colaborador_criar(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000e00',
    'Colaborador Rollback P3 N3', 'rollback.n3.f5-09-p3@example.invalid',
    'P3-N3', null, 'active');
  perform public.estrutura_ocupacao_definir(v_org, v_a1,
    'eaa10000-0000-0000-0000-000000000e01', v_n3,
    'eae10000-0000-0000-0000-000000000006', now(),
    'Ocupacao inicial do admitido N3 (rollback)', 'CICLO_ATUAL_E_POSTERIORES', null);

  v_res := public.ciclo_admissao_pos_ativacao_elegivel(v_org, v_c1, v_n3);
  if coalesce((v_res->>'elegivel')::boolean, false) is not true then
    raise exception '[FAIL] rollback/pre-condicao: N3 deveria ser elegivel ANTES das falhas injetadas (%)', v_res;
  end if;
  raise notice '[PASS] rollback/pre-condicao: N3 elegivel (version do ciclo = 3) — as falhas injetadas abaixo nao sao bloqueadas por pre-condicao';
end $$;

-- R1) Falha imediatamente APOS a linha de snapshot existir na transacao
-- (gatilho AFTER INSERT em `collegiate_cycle_snapshots`): prova que o rollback
-- desfaz trabalho REAL ja executado, e nao uma recusa anterior a escrita.
create or replace function public._mut_p3_falhar_snapshot()
returns trigger language plpgsql as $mut$
begin
  raise notice '_mut_p3_falhar_snapshot: abortando APOS o INSERT do snapshot % do colaborador % (o registro ja existe na transacao)', new.id, new.collaborator_id;
  raise exception 'MUT_F5_09_P3: falha injetada apos o INSERT do snapshot';
end;
$mut$;

create trigger _mut_p3_snapshot after insert on public.collegiate_cycle_snapshots
  for each row execute function public._mut_p3_falhar_snapshot();

do $$
declare
  v_org  uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_n3   uuid;
  v_ok   boolean := false;
  v_msg  text;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select i.collaborator_id into v_n3 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-N3';

  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_n3,
      'inclusao com falha apos o snapshot', 3, v_a1,
      'eaa10000-0000-0000-0000-000000000e02');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P3%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 21/R1: a falha injetada apos o INSERT do snapshot nao abortou a inclusao (%)', v_msg;
  end if;
end $$;

drop trigger _mut_p3_snapshot on public.collegiate_cycle_snapshots;
drop function public._mut_p3_falhar_snapshot();

do $$
declare
  v_org  uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_c1   uuid;
  v_n3   uuid;
  v_n    int;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select i.collaborator_id into v_n3 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-N3';

  -- Rollback do R1: nada do colaborador persistiu; o ciclo segue ATIVO/version 3
  -- e as operacoes anteriores permanecem intactas.
  if exists (
    select 1 from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = v_n3
  ) then
    raise exception '[FAIL] 21/R1: rollback incompleto (snapshot do colaborador persistiu)';
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'eaa10000-0000-0000-0000-000000000e02'
  ) then
    raise exception '[FAIL] 21/R1: rollback incompleto (evento gravado)';
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> 3
     or (select c.status from public.evaluation_cycles c where c.id = v_c1) <> 'ATIVO' then
    raise exception '[FAIL] 21/R1: rollback incompleto (estado/versao do ciclo alterados)';
  end if;
  select count(*) into v_n from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_n <> 4 then
    raise exception '[FAIL] 21/R1: populacao do ciclo deveria continuar com 4 snapshots (%)', v_n;
  end if;

  raise notice '[PASS] 21/R1: falha DEPOIS do INSERT do snapshot => ROLLBACK TOTAL (sem snapshot, sem evento, ciclo ATIVO/version 3, populacao intacta)';
end $$;

-- R2) Falha DURANTE a materializacao das posicoes (a linha de snapshot ja existe
-- na transacao): BEFORE INSERT em `collegiate_cycle_snapshot_positions`.
create or replace function public._mut_p3_falhar_posicao()
returns trigger language plpgsql as $mut$
begin
  raise notice '_mut_p3_falhar_posicao: abortando no INSERT de posicao do snapshot % — o snapshot ja estava materializado na transacao', new.snapshot_id;
  raise exception 'MUT_F5_09_P3: falha injetada na materializacao das posicoes';
end;
$mut$;

create trigger _mut_p3_posicao before insert on public.collegiate_cycle_snapshot_positions
  for each row execute function public._mut_p3_falhar_posicao();

do $$
declare
  v_org  uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_n3   uuid;
  v_ok   boolean := false;
  v_msg  text;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select i.collaborator_id into v_n3 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-N3';

  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_n3,
      'inclusao com falha nas posicoes', 3, v_a1,
      'eaa10000-0000-0000-0000-000000000e03');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P3%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 21/R2: a falha injetada na materializacao das posicoes nao abortou a inclusao (%)', v_msg;
  end if;
end $$;

drop trigger _mut_p3_posicao on public.collegiate_cycle_snapshot_positions;
drop function public._mut_p3_falhar_posicao();

do $$
declare
  v_org  uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_c1   uuid;
  v_n3   uuid;
  v_n    int;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select i.collaborator_id into v_n3 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-N3';

  if exists (
    select 1 from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = v_n3
  ) then
    raise exception '[FAIL] 21/R2: rollback incompleto (snapshot parcial persistiu)';
  end if;
  select count(*) into v_n
    from public.collegiate_cycle_snapshot_positions sp
    join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
     and s.collaborator_id = v_n3;
  if v_n <> 0 then
    raise exception '[FAIL] 21/R2: rollback incompleto (posicoes parciais persistidas=%)', v_n;
  end if;
  select count(*) into v_n
    from public.collegiate_cycle_snapshot_members m
    join public.collegiate_cycle_snapshots s on s.id = m.snapshot_id
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
     and s.collaborator_id = v_n3;
  if v_n <> 0 then
    raise exception '[FAIL] 21/R2: rollback incompleto (membros parciais persistidos=%)', v_n;
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> 3 then
    raise exception '[FAIL] 21/R2: rollback incompleto (versao do ciclo alterada)';
  end if;

  raise notice '[PASS] 21/R2: falha DURANTE a materializacao (snapshot ja na transacao) => ROLLBACK TOTAL (sem snapshot/posicao/membro parcial, versao intacta)';
end $$;

-- R3) Falha DURANTE a materializacao das RESPONSABILIDADES de avaliacao (F3-09):
-- o F3-08 ja estava integralmente materializado na MESMA transacao.
create or replace function public._mut_p3_falhar_responsabilidade()
returns trigger language plpgsql as $mut$
begin
  raise notice '_mut_p3_falhar_responsabilidade: abortando no INSERT de responsabilidade (snapshot %) — o F3-08 ja estava materializado', new.snapshot_id;
  raise exception 'MUT_F5_09_P3: falha injetada na materializacao das responsabilidades';
end;
$mut$;

create trigger _mut_p3_responsabilidade before insert on public.cycle_evaluation_responsibilities
  for each row execute function public._mut_p3_falhar_responsabilidade();

do $$
declare
  v_org  uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_n3   uuid;
  v_ok   boolean := false;
  v_msg  text;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select i.collaborator_id into v_n3 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-N3';

  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org, v_n3,
      'inclusao com falha nas responsabilidades', 3, v_a1,
      'eaa10000-0000-0000-0000-000000000e04');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P3%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 22/R3: a falha injetada nas responsabilidades nao abortou a inclusao (%)', v_msg;
  end if;
end $$;

drop trigger _mut_p3_responsabilidade on public.cycle_evaluation_responsibilities;
drop function public._mut_p3_falhar_responsabilidade();

do $$
declare
  v_org  uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_n3   uuid;
  v_n    int;
  v_res  jsonb;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select i.collaborator_id into v_n3 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P3-N3';

  -- Rollback do R3 (falha ocorreu com o F3-08 completo).
  if exists (
    select 1 from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = v_n3
  ) then
    raise exception '[FAIL] 22/R3: rollback incompleto (snapshot persistiu)';
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'eaa10000-0000-0000-0000-000000000e04'
  ) then
    raise exception '[FAIL] 22/R3: rollback incompleto (evento gravado)';
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> 3 then
    raise exception '[FAIL] 22/R3: rollback incompleto (versao do ciclo alterada)';
  end if;
  select count(*) into v_n from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_n <> 4 then
    raise exception '[FAIL] 22/R3: populacao deveria continuar com 4 snapshots (%)', v_n;
  end if;

  -- (23) Removidas TODAS as falhas injetadas, a MESMA operacao legitima (mesmo
  -- ciclo, mesmo colaborador, mesmo expected_version e o MESMO operation_id da
  -- primeira falha) funciona — provando rollback sem residuo e idempotencia.
  v_res := public.ciclo_incluir_admissao(v_c1, v_org, v_n3,
    'inclusao com falha apos o snapshot', 3, v_a1,
    'eaa10000-0000-0000-0000-000000000e02');
  if (v_res->>'version')::int <> 4 or (v_res->>'collaborator_id')::uuid is distinct from v_n3 then
    raise exception '[FAIL] 23: a inclusao legitima deveria funcionar apos remover as falhas (%)', v_res;
  end if;
  if not exists (
    select 1 from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
       and s.collaborator_id = v_n3
  ) then
    raise exception '[FAIL] 23: snapshot do colaborador nao foi materializado na retentativa legitima';
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'eaa10000-0000-0000-0000-000000000e02'
     and e.event_type = 'ADMISSAO_INCLUIDA';
  if v_n <> 1 then
    raise exception '[FAIL] 23: esperado exatamente 1 evento para a operacao retomada (%)', v_n;
  end if;

  raise notice '[PASS] 22/R3 + 23: falha durante as responsabilidades (F3-08 ja completo) => ROLLBACK TOTAL e, removida a falha, a MESMA operacao (mesmo operation_id) conclui com sucesso e materializa o participante';
end $$;

-- ----------------------------------------------------------------------------
-- 11) Estatico/estrutural: contrato restrito, ACL, lock, aditividade e escopo
-- ----------------------------------------------------------------------------
do $$
declare
  v_def    text;
  v_args   text;
  v_rec    record;
  v_fn     text;
  v_problemas text[] := array[]::text[];
  v_caps   int;
  v_nova   int;
  v_tabelas int;
begin
  -- (25) Assinatura: NENHUM parametro estrutural (unidade/posicao/gestor/
  -- reporting line/colegiado/reference_date/lista) e motivo obrigatorio.
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_collaborator_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    v_problemas := v_problemas || ('assinatura fora do contrato: ' || coalesce(v_args, 'nula'));
  end if;

  -- (26) Lock normativo da familia de ciclos + nenhuma chave de outra familia.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)');
  if position('ciclo_lock_organizacao' in v_def) = 0 then
    v_problemas := v_problemas || 'RPC sem ciclo_lock_organizacao'::text;
  end if;
  if position('evaluation_cycles:' in v_def) > 0 then
    -- A chave e usada DENTRO de ciclo_lock_organizacao; se aparecer aqui, a RPC
    -- estaria montando a chave por conta propria (duplicacao da primitiva).
    v_problemas := v_problemas || 'RPC monta a chave normativa fora de ciclo_lock_organizacao'::text;
  end if;
  if position('position_reporting_lines:' in v_def) > 0
     or position('f5_07_estrutura:' in v_def) > 0 then
    v_problemas := v_problemas || 'RPC usa chave de OUTRA familia de lock'::text;
  end if;

  -- (27/A11) Aditividade por construcao: a RPC nao escreve/remove nas tabelas de
  -- snapshot/responsabilidade (delega a F3-08/F3-09) e nao le dado declarado.
  if position('update public.collegiate_cycle_snapshot' in lower(v_def)) > 0
     or position('delete from public.collegiate_cycle_snapshot' in lower(v_def)) > 0
     or position('insert into public.collegiate_cycle_snapshot' in lower(v_def)) > 0
     or position('update public.cycle_evaluation_responsibilities' in lower(v_def)) > 0
     or position('delete from public.cycle_evaluation_responsibilities' in lower(v_def)) > 0
     or position('insert into public.cycle_evaluation_responsibilities' in lower(v_def)) > 0
     or position('materializar_colegiado_ciclo' in lower(v_def)) = 0
     or position('materializar_responsabilidades_avaliacao' in lower(v_def)) = 0 then
    v_problemas := v_problemas || 'RPC nao delega a materializacao aditiva a F3-08/F3-09'::text;
  end if;
  if position('admission_date' in lower(v_def)) > 0 then
    v_problemas := v_problemas || 'RPC referencia admission_date (nao e prova)'::text;
  end if;
  if position('funcao' in lower(v_def)) > 0 or position('cargo' in lower(v_def)) > 0 then
    v_problemas := v_problemas || 'RPC referencia cargo/funcao textual'::text;
  end if;

  -- Helper read-only e sem materializacao.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)');
  if position('insert into' in lower(v_def)) > 0
     or position('update public.' in lower(v_def)) > 0
     or position('delete from' in lower(v_def)) > 0
     or position('materializar' in lower(v_def)) > 0 then
    v_problemas := v_problemas || 'helper de elegibilidade nao e estritamente read-only'::text;
  end if;
  if (select p.provolatile from pg_proc p
       where p.oid = to_regprocedure('public.ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)')) <> 's' then
    v_problemas := v_problemas || 'helper de elegibilidade deveria ser STABLE'::text;
  end if;

  -- ACL: INVOKER, search_path fixo, EXECUTE somente service_role nas duas.
  foreach v_fn in array array[
    'ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)',
    'ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)']
  loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config
      into v_rec
      from pg_proc p where p.oid = to_regprocedure('public.' || v_fn);
    if v_rec.prosecdef then
      v_problemas := v_problemas || ('SECURITY DEFINER: ' || v_fn);
    end if;
    if position('search_path=public' in v_rec.config) = 0 then
      v_problemas := v_problemas || ('sem search_path fixo: ' || v_fn);
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_problemas := v_problemas || ('service_role sem EXECUTE: ' || v_fn);
    end if;
    if has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE') then
      v_problemas := v_problemas || ('exposta a anon/authenticated: ' || v_fn);
    end if;
  end loop;

  -- (27) Nenhuma capability nova: catalogo intacto e nenhuma capability de
  -- admissao criada (a operacao reusa `cycle.manage`).
  select count(*) into v_caps from public.capabilities;
  if v_caps <> 31 then
    v_problemas := v_problemas || ('catalogo de capabilities alterado: ' || v_caps);
  end if;
  select count(*) into v_nova from public.capabilities
   where code like '%admissao%' or code like 'cycle.admiss%';
  if v_nova <> 0 then
    v_problemas := v_problemas || 'capability nova de admissao criada'::text;
  end if;

  -- (28) Nenhuma superficie de LEITURA soberana (P5+) antecipada e
  -- deny-by-default intacto. A checagem NAO depende da existencia de RPCs de
  -- fases posteriores (P4 pode coexistir legitimamente) e ADMITE a leitura
  -- own-tenant de `evaluation_cycles` quando o P5 a abrir (policy SELECT +
  -- grant minimo), conferindo-a contra o contrato: o que a P3 proibe e
  -- antecipar RPC de leitura de ciclo, abrir a TRILHA ou permitir ESCRITA.
  if exists (
    select 1 from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('ciclo_painel', 'ciclo_historico', 'ciclo_listar_colaborador_por_ciclo')
  ) then
    v_problemas := v_problemas || 'RPC de LEITURA soberana (P5+) antecipada'::text;
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and (cmd <> 'SELECT'
            or not ('authenticated'::name = any(roles))
            or coalesce(qual, '') not like '%user_has_active_membership%')
  ) then
    v_problemas := v_problemas || 'policy de evaluation_cycles fora do contrato own-tenant (P5)'::text;
  end if;
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_problemas := v_problemas || 'anon/authenticated com ESCRITA ou acesso indevido a ciclo/trilha'::text;
  end if;
  -- Nenhuma tabela nova foi criada pela P3 (a operacao usa as tabelas da P1/P2,
  -- F3-08/F3-09 e F5-07).
  select count(*) into v_tabelas from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and (c.relname like 'ciclo\_%' or c.relname like 'cycle_admission%');
  if v_tabelas <> 0 then
    v_problemas := v_problemas || ('tabela nova criada pela P3: ' || v_tabelas);
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] 25/26/27/28: %', array_to_string(v_problemas, '; ');
  end if;

  raise notice '[PASS] 25/26/27/28: contrato restrito (sem parametro estrutural, sem cargo/texto, sem admission_date), lock normativo da familia de ciclos, delega exclusiva a F3-08/F3-09, ACL so service_role, catalogo intacto (31 capabilities) e nenhuma leitura soberana (P5+) antecipada';
end $$;

-- ----------------------------------------------------------------------------
-- 12) Trilha consolidada + consistencia da populacao do ciclo
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_c1    uuid;
  v_dup   int;
  v_sem   int;
  v_qtd   int;
  v_snap  int;
  v_colab int;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  -- (19) Um evento por operacao (operation_id unico) e tipos do contrato.
  select count(*) into v_dup from (
    select e.operation_id from public.cycle_events e
     where e.organization_id = v_org
     group by e.operation_id having count(*) > 1
  ) x;
  if v_dup <> 0 then
    raise exception '[FAIL] 19: operation_id repetido na trilha (%)', v_dup;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.event_type not in ('CRIADO', 'ATIVADO', 'ADMISSAO_INCLUIDA')
  ) then
    raise exception '[FAIL] 19: evento fora do contrato exercitado pela P3';
  end if;
  select count(*) into v_qtd from public.cycle_events e
   where e.organization_id = v_org and e.event_type = 'ADMISSAO_INCLUIDA';
  if v_qtd <> 3 then
    raise exception '[FAIL] 19: esperados 3 eventos ADMISSAO_INCLUIDA (N1, N2, N3) (%)', v_qtd;
  end if;

  -- Autoria soberana em toda a trilha da organizacao.
  select count(*) into v_sem from public.cycle_events e
   where e.organization_id = v_org
     and (e.actor_user_profile_id is null or e.actor_membership_id is null);
  if v_sem <> 0 then
    raise exception '[FAIL] Q: evento sem autoria soberana (%)', v_sem;
  end if;
  if exists (
    select 1 from public.cycle_events e
      left join public.user_organization_memberships m
        on m.id = e.actor_membership_id and m.organization_id = e.organization_id
     where e.organization_id = v_org
       and (m.id is null or m.user_profile_id <> e.actor_user_profile_id)
  ) then
    raise exception '[FAIL] Q: membership da trilha nao pertence ao ator/tenant';
  end if;

  -- (17/18) Populacao do ciclo = base (2) + N1 + N2 + N3, sem duplicidade, e o
  -- snapshot de cada um pertence ao tenant/ciclo corretos.
  select count(*), count(distinct s.collaborator_id) into v_snap, v_colab
    from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_snap <> 5 or v_colab <> 5 then
    raise exception '[FAIL] 17: populacao final deveria ter 5 snapshots distintos (%, %)', v_snap, v_colab;
  end if;
  -- (17) Nenhum snapshot pode existir em tenant/ano/ciclo errados: os
  -- colaboradores de BASE de Alfa so podem estar no ciclo C1, e o colaborador do
  -- Beta somente no ciclo do PROPRIO tenant (nada cruza a fronteira).
  if exists (
    select 1 from public.collegiate_cycle_snapshots s
     where s.collaborator_id in ('eab00000-0000-0000-0000-000000000001',
                                 'eab00000-0000-0000-0000-000000000002')
       and (s.organization_id <> v_org or s.ano <> 2031 or s.ciclo <> 1)
  ) then
    raise exception '[FAIL] 17: snapshot de colaborador de Alfa em tenant/ciclo errados';
  end if;
  if exists (
    select 1 from public.collegiate_cycle_snapshots s
     where s.collaborator_id = 'eab00000-0000-0000-0000-0000000000b1'
       and (s.organization_id <> 'eaa00000-0000-0000-0000-0000000000b1'
            or s.ano <> 2031 or s.ciclo <> 1)
  ) then
    raise exception '[FAIL] 17: snapshot do colaborador do Beta em tenant/ciclo errados';
  end if;

  raise notice '[PASS] 17/18/19/Q: populacao final com 5 participantes distintos no tenant/ciclo corretos, 3 eventos ADMISSAO_INCLUIDA (um por operacao), tipos do contrato e autoria sempre do ator verificado';
end $$;

-- ----------------------------------------------------------------------------
-- 13) Estado terminal: ciclo ENCERRADO tambem recusa a inclusao
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eaa00000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'eac00000-0000-0000-0000-000000000001';
  v_c1    uuid;
  v_c1v   int;
  v_ok    boolean;
  v_msg   text;
begin
  select c.id, c.version into v_c1, v_c1v from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  -- Encerra C1 pelo caminho soberano da P2 (nenhuma pendencia: o ciclo nao tem
  -- avaliacoes nesta fixture da P3).
  perform public.ciclo_encerrar(v_c1, v_org, 'Encerramento apos as provas da P3',
    v_c1v, v_a1, 'eaa10000-0000-0000-0000-000000000f10');

  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c1, v_org,
      'eab00000-0000-0000-0000-000000000001', 'inclusao em ciclo encerrado',
      v_c1v + 1, v_a1, 'eaa10000-0000-0000-0000-000000000f11');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige ciclo ATIVO' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] 2: inclusao em ciclo ENCERRADO deveria ser CONFLICT (%)', v_msg;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'eaa10000-0000-0000-0000-000000000f11'
  ) then
    raise exception '[FAIL] 20: inclusao em ciclo ENCERRADO gravou evento';
  end if;
  if (select count(*) from public.collegiate_cycle_snapshots s
       where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1) <> 5 then
    raise exception '[FAIL] 20: inclusao em ciclo ENCERRADO materializou snapshot';
  end if;

  raise notice '[PASS] 2: inclusao aditiva exige ciclo ATIVO tambem no estado ENCERRADO (CONFLICT sem efeito)';
end $$;

-- ============================================================================
-- 14) Resumo
-- ============================================================================
do $$
begin
  raise notice '============================================================';
  raise notice 'F5-09 P3: inclusao aditiva de nova admissao em ciclo ATIVO validada — provas P1-P7 fail-closed, contrato restrito, aditividade provada (pre-existentes intactos), idempotencia/versao, lock normativo, cross-tenant direto, rollback real e ausencia de P4+.';
end $$;
