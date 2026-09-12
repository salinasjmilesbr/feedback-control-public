-- ============================================================================
-- F5-09 P3: inclusao aditiva soberana de nova admissao em ciclo ATIVO (D26)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md (§6 nota "a inclusao aditiva nao e
-- transicao de estado", §7.2 provas P1–P7, §7.3 contrato restrito, §10
-- I17/I18/I19, §11 concorrencia/idempotencia, §12 auditoria,
-- §13.2 RPCs (`ciclo_admissao_pos_ativacao_elegivel` e `ciclo_incluir_admissao`),
-- §13.3 reuso obrigatorio, §15.1 A1–A12, §19 P3) e docs/F5-09-duvidas.md
-- (D1–D28 ratificadas; D26/D27 em especial).
-- Pre-requisitos: P1 (`20260915000000_f5_09_cycle_sovereign.sql`) e P2
-- (`20260916000000_f5_09_cycle_rpc.sql`).
--
-- Entregue AQUI (e somente isto):
--   1) `ciclo_admissao_pos_ativacao_elegivel` — helper READ-ONLY que aplica as
--      provas P1–P7 do §7.2 e devolve elegibilidade + motivo da recusa +
--      evidencias da estrutura resolvida (usado pela inclusao e pelo validador);
--   2) `ciclo_incluir_admissao` — RPC restrita (D26) que ACRESCENTA ao ciclo
--      corrente, de forma EXCLUSIVAMENTE ADITIVA, um colaborador admitido depois
--      da ativacao.
--
-- Fora do escopo (P4+), deliberadamente NAO implementado aqui: cancelar (T4/T5),
-- reabrir (T6), corrigir periodo (T7), policy de LEITURA para `authenticated`
-- (P5), Policy Engine cycle.read/manage (P6), Edge `ciclos` + bundle (P7),
-- cutover do cliente (P8) e validacao integrada (P9). Nenhuma capability nova,
-- nenhum bundle alterado, nenhuma tabela nova, nenhuma coluna nova.
--
-- Invariantes preservadas (D1–D28), em especial:
--   - a operacao NAO e refresh/rematerializacao/sincronizacao: NENHUMA linha
--     existente de `collegiate_cycle_snapshots`,
--     `collegiate_cycle_snapshot_positions`, `collegiate_cycle_snapshot_members`
--     ou `cycle_evaluation_responsibilities` e alterada ou removida — a operacao
--     so INSERE (via F3-08/F3-09, que sao `on conflict do nothing`/`not exists`),
--     e NAO aceita NENHUM parametro estrutural (unidade, posicao, gestor,
--     reporting line, colegiado, reference_date, lista de colaboradores);
--   - prova soberana de admissao (P1–P7) revalidada SERVER-SIDE, FAIL-CLOSED:
--     `collaborators.admission_date` e dado declarado de cadastro e NAO e prova;
--     colaborador legado/importado sem evento soberano `ADMISSAO` e RECUSADO (a
--     correcao e no caminho de importacao, nunca relaxar a prova);
--   - tenant, ator, membership e capability vem SEMPRE do ator verificado:
--     `service_role` executa e NUNCA decide (auth.uid() resolvido server-side);
--   - serializacao pela chave normativa da familia de CICLOS
--     (`ciclo_lock_organizacao`, P1) + `expected_version` (CONFLICT) +
--     idempotencia por `(organization_id, operation_id)` com hash canonico
--     DERIVADO server-side;
--   - UM evento append-only por mutacao (`ADMISSAO_INCLUIDA`), na MESMA
--     transacao, com autoria soberana, sem dados pessoais desnecessarios
--     (§12.2/§12.3);
--   - atomicidade total: qualquer falha (inclusive DENTRO da materializacao
--     F3-08/F3-09) produz ROLLBACK TOTAL — zero snapshot/responsabilidade
--     parcial e zero evento.
--
-- DESVIOS MINIMOS E EXPLICITOS em relacao ao §13.2 (documentados para auditoria):
--   (a) `p_payload_hash` NAO e parametro — MESMO desvio ja declarado e aceito na
--       P2. O §11/§12 definem o hash como o do PAYLOAD CANONICO DA INTENCAO e o
--       padrao soberano do projeto (F5-06/F5-07/F5-08/P2) DERIVA o hash dos
--       parametros ja validados; aceita-lo do cliente permitiria replay com hash
--       forjado. O hash continua gravado em `cycle_events.payload_hash`
--       (SHA-256 hex do payload canonico derivado server-side), preservando
--       `unique (organization_id, operation_id)`.
--   (b) a inclusao incrementa `evaluation_cycles.version` UMA vez. O §6 registra
--       que a inclusao NAO e transicao de estado — e o que se cumpre: `status`,
--       `data_inicio`/`data_fim`/`data_ativacao`/`data_encerramento` e as
--       contagens de pendencia NAO mudam. Mas a POPULACAO materializada do ciclo
--       muda; sem o incremento, o parametro `p_expected_version` do §13.2 e o
--       campo `version` do `after_value` do §12 seriam degenerados (nao
--       detectariam alteracao concorrente da populacao). Mantem-se a convencao
--       da P2 "uma operacao oficial = um incremento" (resultado =
--       expected_version + 1), com o resultado devolvido no retorno e na trilha.
--   (c) a inclusao NAO cria helper novo de materializacao: a primitiva F3-08 ja
--       aceita a MENOR granularidade segura (`p_evaluated_collaborator_ids` com
--       UM id, `on conflict do nothing` + guardas `not exists`), e a F3-09 e
--       idempotente por `(snapshot, posicao)`. Nenhuma funcao F3-08/F3-09 foi
--       alterada (proibido transforma-las em refresh global).
--   (d) P6 e aplicado de forma ESTRITA (fail-closed): a presenca de QUALQUER
--       evento `ADMISSAO` do colaborador com
--       `cycle_scope = 'SOMENTE_CICLOS_POSTERIORES'` recusa a inclusao no ciclo
--       corrente. A operacao nao "escolhe" entre evidencias conflitantes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed, sem ajuste silencioso)
-- ----------------------------------------------------------------------------
-- A P3 depende das primitivas da P1/P2 e dos contratos F3-07/F3-08/F3-09/F5-07.
-- Se o baseline nao for exatamente o esperado, a migration ABORTA.
do $$
declare
  v_faltando text[] := array[]::text[];
  v_fn       text;
  v_check    text;
begin
  -- P1/P2: RPCs e helpers da familia de ciclos.
  foreach v_fn in array array[
    'public.ciclo_ator_valido(uuid, uuid, text)',
    'public.ciclo_lock_organizacao(uuid)',
    'public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)',
    'public.ciclo_ativar(uuid, uuid, integer, uuid, uuid)']
  loop
    if to_regprocedure(v_fn) is null then
      v_faltando := v_faltando || ('ausente: ' || v_fn);
    end if;
  end loop;

  -- F3-07/F3-08/F3-09: insumos relacionais da materializacao (reuso obrigatorio).
  foreach v_fn in array array[
    'public.materializar_colegiado_ciclo(uuid, integer, integer, timestamp with time zone, uuid[])',
    'public.materializar_responsabilidades_avaliacao(uuid, integer, integer)',
    'public.organizacao_resolver_responsavel_posicao(uuid, timestamp with time zone)']
  loop
    if to_regprocedure(v_fn) is null then
      v_faltando := v_faltando || ('ausente: ' || v_fn);
    end if;
  end loop;

  -- P1: a trilha ja contempla `ADMISSAO_INCLUIDA` no CHECK de event_type. A
  -- verificacao e por CONTEUDO do CHECK (agnostica ao nome da constraint), para
  -- nao depender de rotulo interno do contrato fechado da P1.
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.cycle_events'::regclass
       and c.contype = 'c'
       and position('ADMISSAO_INCLUIDA' in pg_get_constraintdef(c.oid)) > 0
  ) then
    v_faltando := v_faltando || 'cycle_events sem CHECK que aceite ADMISSAO_INCLUIDA'::text;
  end if;

  -- P1: idempotencia e append-only completo na trilha de ciclos.
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.cycle_events'::regclass
       and conname = 'uq_cycle_events_org_operation' and contype = 'u'
  ) then
    v_faltando := v_faltando || 'cycle_events.uq_cycle_events_org_operation'::text;
  end if;
  foreach v_fn in array array[
    'trg_cycle_events_append_only', 'trg_cycle_events_no_delete',
    'trg_cycle_events_no_truncate']
  loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid = 'public.cycle_events'::regclass
         and tgname = v_fn and not tgisinternal
    ) then
      v_faltando := v_faltando || ('trigger ' || v_fn);
    end if;
  end loop;

  -- F5-07: prova soberana de admissao (evento + periodo de status). Verificacao
  -- por CONTEUDO dos CHECKs (agnostica aos nomes internos das constraints).
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.collaborator_events'::regclass
       and c.contype = 'c'
       and position('ADMISSAO' in pg_get_constraintdef(c.oid)) > 0
  ) then
    v_faltando := v_faltando || 'collaborator_events sem CHECK que aceite ADMISSAO'::text;
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.collaborator_events'::regclass
       and c.contype = 'c'
       and position('CICLO_ATUAL_E_POSTERIORES' in pg_get_constraintdef(c.oid)) > 0
       and position('SOMENTE_CICLOS_POSTERIORES' in pg_get_constraintdef(c.oid)) > 0
  ) then
    v_faltando := v_faltando || 'collaborator_events sem CHECK de cycle_scope completo'::text;
  end if;
  if to_regclass('public.collaborator_status_periods') is null then
    v_faltando := v_faltando || 'ausente: public.collaborator_status_periods'::text;
  end if;

  -- F3-08: os insumos relacionais que P5 exige (ocupacao vigente e reporting line).
  if to_regclass('public.occupations') is null
     or to_regclass('public.position_reporting_lines') is null then
    v_faltando := v_faltando || 'ausente: occupations/position_reporting_lines'::text;
  end if;

  -- `service_role` mantem EXECUTE nas primitivas reusadas (sem grant novo).
  if has_function_privilege(
       'service_role',
       'public.materializar_colegiado_ciclo(uuid, integer, integer, timestamp with time zone, uuid[])',
       'EXECUTE') is not true then
    v_faltando := v_faltando || 'service_role sem EXECUTE em materializar_colegiado_ciclo'::text;
  end if;
  if has_function_privilege(
       'service_role',
       'public.materializar_responsabilidades_avaliacao(uuid, integer, integer)',
       'EXECUTE') is not true then
    v_faltando := v_faltando || 'service_role sem EXECUTE em materializar_responsabilidades_avaliacao'::text;
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception 'F5_09_P3_PREFLIGHT: baseline incompativel: %',
      array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-09 P3: preflight OK (P1/P2, F3-07/F3-08/F3-09 e F5-07 presentes; trilha ja aceita ADMISSAO_INCLUIDA)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) `ciclo_admissao_pos_ativacao_elegivel` — prova soberana P1–P7 (read-only)
-- ----------------------------------------------------------------------------
-- Contrato §13.2/§7.2: aplica as provas P1–P7 e devolve `elegivel` + `motivo` da
-- recusa + as EVIDENCIAS que a inclusao usa na trilha (§12: collaborator_id, o id
-- do evento `ADMISSAO` que autorizou, o `reference_date` e a posicao resolvida).
--
-- REGRA DE PRECEDENCIA (deterministica, fail-closed; o primeiro motivo que
-- dispara e o reportado) e o que cada prova usa:
--   1. `CICLO_NAO_ENCONTRADO` .... ciclo inexistente ou de outro tenant (P4);
--   2. `CICLO_NAO_ATIVO` ......... status <> 'ATIVO' (P4);
--   3. `ATIVACAO_NAO_REGISTRADA`.. ATIVO sem `data_ativacao` (defensivo);
--   4. `COLABORADOR_NAO_ENCONTRADO` colaborador inexistente/outro tenant (P5);
--   5. `JA_MATERIALIZADO_NO_CICLO` ja existe snapshot do colaborador (P3);
--   6. `ESCOPO_SOMENTE_CICLOS_POSTERIORES` existe evento ADMISSAO com escopo
--      SOMENTE_CICLOS_POSTERIORES (P6, estrito — desvio (d));
--   7. `SEM_EVENTO_ADMISSAO` ..... nenhum evento ADMISSAO (P7 — legado/import);
--   8. `ADMISSAO_ANTERIOR_A_ATIVACAO` evento ADMISSAO compativel com o ciclo
--      corrente inexistente (effective_date <= data_ativacao) (P1);
--   9. `VIDA_SOBERANA_ANTERIOR` .. periodo de status com valid_from <
--      data_ativacao: a pessoa JA pertencia a populacao antes da ativacao (P2);
--  10. `COLABORADOR_INATIVO` ..... status vigente no instante da inclusao nao e
--      `active` (P5);
--  11. `ESTRUTURA_IRRESOLVEL` ... sem ocupacao vigente no instante (P5);
--  12. `ELEGIVEL` ............... todas as provas satisfeitas.
--
-- `reference_date` = `now()` (instante da inclusao, §13.2): e o mesmo valor usado
-- pela materializacao F3-08/F3-09 chamada pela inclusao (§7.3).
create or replace function public.ciclo_admissao_pos_ativacao_elegivel(
  p_organization_id uuid,
  p_cycle_id uuid,
  p_collaborator_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_org        uuid := p_organization_id;
  v_instante   timestamptz := now();
  v_ciclo      record;
  v_material   boolean := false;
  v_somente    boolean := false;
  v_adm_evt    uuid;
  v_adm_data   timestamptz;
  v_adm_scope  text;
  v_vida_ant   boolean := false;
  v_status     text;
  v_status_ok  boolean := false;
  v_posicao    uuid;
  v_unidade    uuid;
  v_sup_pos    uuid;
  v_sup_colab  uuid;
  v_motivo     text;
  v_elegivel   boolean := false;
begin
  -- Forma minima (fail-closed: sem argumentos nao ha elegibilidade).
  if v_org is null or p_cycle_id is null or p_collaborator_id is null then
    return jsonb_build_object(
      'elegivel', false, 'motivo', 'ARGUMENTOS_INCOMPLETOS',
      'reference_date', v_instante);
  end if;

  -- (P4) Ciclo do MESMO tenant.
  select c.id, c.ano, c.numero, c.status, c.version, c.data_ativacao
    into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org;
  if not found then
    return jsonb_build_object(
      'elegivel', false, 'motivo', 'CICLO_NAO_ENCONTRADO',
      'organization_id', v_org, 'cycle_id', p_cycle_id,
      'collaborator_id', p_collaborator_id, 'reference_date', v_instante);
  end if;
  if v_ciclo.status <> 'ATIVO' then
    return jsonb_build_object(
      'elegivel', false, 'motivo', 'CICLO_NAO_ATIVO',
      'organization_id', v_org, 'cycle_id', p_cycle_id,
      'collaborator_id', p_collaborator_id, 'cycle_status', v_ciclo.status,
      'reference_date', v_instante);
  end if;
  if v_ciclo.data_ativacao is null then
    return jsonb_build_object(
      'elegivel', false, 'motivo', 'ATIVACAO_NAO_REGISTRADA',
      'organization_id', v_org, 'cycle_id', p_cycle_id,
      'collaborator_id', p_collaborator_id, 'cycle_status', v_ciclo.status,
      'reference_date', v_instante);
  end if;

  -- (P5) Colaborador do tenant (cross-tenant e indistinguivel de inexistente).
  if not exists (
    select 1 from public.collaborators c
     where c.id = p_collaborator_id and c.organization_id = v_org
  ) then
    return jsonb_build_object(
      'elegivel', false, 'motivo', 'COLABORADOR_NAO_ENCONTRADO',
      'organization_id', v_org, 'cycle_id', p_cycle_id,
      'collaborator_id', p_collaborator_id, 'reference_date', v_instante);
  end if;

  -- (P3) Aditividade: ja materializado => recusa (nunca sobrescrita).
  select exists (
    select 1 from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org
       and s.ano = v_ciclo.ano
       and s.ciclo = v_ciclo.numero
       and s.collaborator_id = p_collaborator_id
  ) into v_material;

  -- (P6) Escopo do evento: SOMENTE_CICLOS_POSTERIORES recusa o ciclo corrente
  -- (aplicacao estrita e fail-closed — desvio (d) no header).
  select exists (
    select 1 from public.collaborator_events e
     where e.organization_id = v_org
       and e.collaborator_id = p_collaborator_id
       and e.event_type = 'ADMISSAO'
       and e.cycle_scope = 'SOMENTE_CICLOS_POSTERIORES'
  ) into v_somente;

  -- (P1) Evento soberano de ADMISSAO COMPATIVEL com o ciclo corrente: escopo
  -- CICLO_ATUAL_E_POSTERIORES e effective_date POSTERIOR a ativacao. O evento que
  -- autoriza e o mais recente compativel (desempate deterministico).
  select e.id, e.effective_date, e.cycle_scope
    into v_adm_evt, v_adm_data, v_adm_scope
    from public.collaborator_events e
   where e.organization_id = v_org
     and e.collaborator_id = p_collaborator_id
     and e.event_type = 'ADMISSAO'
     and e.cycle_scope = 'CICLO_ATUAL_E_POSTERIORES'
     and e.effective_date > v_ciclo.data_ativacao
   order by e.effective_date desc, e.created_at desc, e.id desc
   limit 1;

  -- (P2) Vida soberana anterior: qualquer periodo de status iniciado ANTES da
  -- ativacao prova que a pessoa ja existia na populacao do ciclo.
  select exists (
    select 1
      from public.collaborator_status_periods sp
     where sp.collaborator_id = p_collaborator_id
       and sp.valid_from < v_ciclo.data_ativacao
  ) into v_vida_ant;

  -- (P5) Status vigente no instante da inclusao (meio-aberto [valid_from, valid_to)).
  select sp.status into v_status
    from public.collaborator_status_periods sp
   where sp.collaborator_id = p_collaborator_id
     and sp.valid_from <= v_instante
     and (sp.valid_to is null or sp.valid_to > v_instante)
   order by sp.valid_from desc, sp.created_at desc
   limit 1;
  v_status_ok := coalesce(v_status = 'active', false);

  -- (P5) Estrutura soberana resolvivel SOMENTE nas fontes relacionais: ocupacao
  -- vigente no instante (posicao do tenant, garantida por FK composta) e o
  -- superior formal resolvido pela MESMA primitiva da F3-08 (F3-07), quando
  -- houver reporting line vigente. Nenhum insumo textual/cargo e lido.
  select o.organizational_position_id, p.unit_id
    into v_posicao, v_unidade
    from public.occupations o
    join public.organizational_positions p
      on p.id = o.organizational_position_id
     and p.organization_id = o.organization_id
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from <= v_instante
     and (o.valid_to is null or o.valid_to > v_instante)
   order by o.valid_from desc, o.created_at desc
   limit 1;

  if v_posicao is not null then
    select rl.manager_position_id into v_sup_pos
      from public.position_reporting_lines rl
     where rl.subordinate_position_id = v_posicao
       and rl.organization_id = v_org
       and rl.valid_from <= v_instante
       and (rl.valid_to is null or rl.valid_to > v_instante)
     order by rl.valid_from desc, rl.created_at desc
     limit 1;
    if v_sup_pos is not null then
      select r.responsible_collaborator_id into v_sup_colab
        from public.organizacao_resolver_responsavel_posicao(v_sup_pos, v_instante) r
       limit 1;
    end if;
  end if;

  -- Precedencia fail-closed: o PRIMEIRO motivo aplicavel e o reportado.
  if v_material then
    v_motivo := 'JA_MATERIALIZADO_NO_CICLO';
  elsif v_somente then
    v_motivo := 'ESCOPO_SOMENTE_CICLOS_POSTERIORES';
  elsif v_adm_evt is null then
    if exists (
      select 1 from public.collaborator_events e
       where e.organization_id = v_org
         and e.collaborator_id = p_collaborator_id
         and e.event_type = 'ADMISSAO'
    ) then
      v_motivo := 'ADMISSAO_ANTERIOR_A_ATIVACAO';
    else
      v_motivo := 'SEM_EVENTO_ADMISSAO';
    end if;
  elsif v_vida_ant then
    v_motivo := 'VIDA_SOBERANA_ANTERIOR';
  elsif not v_status_ok then
    v_motivo := 'COLABORADOR_INATIVO';
  elsif v_posicao is null then
    v_motivo := 'ESTRUTURA_IRRESOLVEL';
  else
    v_motivo := 'ELEGIVEL';
    v_elegivel := true;
  end if;

  return jsonb_build_object(
    'elegivel', v_elegivel,
    'motivo', v_motivo,
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'collaborator_id', p_collaborator_id,
    'ano', v_ciclo.ano,
    'numero', v_ciclo.numero,
    'cycle_status', v_ciclo.status,
    'cycle_version', v_ciclo.version,
    'data_ativacao', v_ciclo.data_ativacao,
    'reference_date', v_instante,
    'ja_materializado', v_material,
    'admissao_event_id', v_adm_evt,
    'admissao_effective_date', v_adm_data,
    'admissao_cycle_scope', v_adm_scope,
    'status_vigente', v_status,
    'posicao_id', v_posicao,
    'unidade_id', v_unidade,
    'superior_position_id', v_sup_pos,
    'superior_collaborator_id', v_sup_colab);
end;
$$;

comment on function public.ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid) is
  'F5-09 P3 (D26 §7.2): helper READ-ONLY da prova soberana de admissao posterior '
  'a ativacao. Aplica P1 (evento ADMISSAO com cycle_scope '
  'CICLO_ATUAL_E_POSTERIORES e effective_date > data_ativacao), P2 (ausencia de '
  'periodo de status anterior a ativacao), P3 (aditividade: recusa se ja '
  'materializado), P4 (ciclo ATIVO do tenant), P5 (status active vigente + '
  'estrutura resolvida SO nas fontes relacionais), P6 (escopo '
  'SOMENTE_CICLOS_POSTERIORES recusa, de forma estrita) e P7 (sem prova => '
  'recusa; admission_date NAO e prova). Devolve elegibilidade, motivo da recusa '
  'e evidencias (evento de admissao, posicao/unidade/superior resolvidos). '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 2) `ciclo_incluir_admissao` — inclusao aditiva restrita (D26)
-- ----------------------------------------------------------------------------
create or replace function public.ciclo_incluir_admissao(
  p_cycle_id uuid,
  p_organization_id uuid,
  p_collaborator_id uuid,
  p_motivo text,
  p_expected_version integer,
  p_actor_user_profile_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org          uuid := p_organization_id;
  v_motivo       text := btrim(coalesce(p_motivo, ''));
  v_hash         text;
  v_evento       record;
  v_membership   uuid;
  v_ciclo        record;
  v_eleg         jsonb;
  v_instante     timestamptz := now();
  v_snap_id      uuid;
  v_qtd_snap     int;
  v_qtd_pos      int;
  v_qtd_memb     int;
  v_qtd_resp     int;
  v_posicao      uuid;
  v_unidade      uuid;
  v_sup_pos      uuid;
  v_sup_colab    uuid;
  v_adm_evt      uuid;
  v_adm_data     timestamptz;
  v_nova_versao  integer;
begin
  -- (1) Forma: nada aqui e autoridade.
  if p_cycle_id is null or p_organization_id is null or p_collaborator_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_09_INVALID_INPUT: cycle_id, organization_id, collaborator_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_09_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_09_INVALID_INPUT: motivo da inclusao da admissao obrigatorio';
  end if;

  -- (2) Hash canonico do payload da INTENCAO, DERIVADO server-side (desvio (a)).
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'ciclo_incluir_admissao',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'collaborator_id', p_collaborator_id,
    'motivo', v_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  -- (3) Ator soberano: membership ativa + capability efetiva `cycle.manage`
  -- (capability REUSADA; nenhuma capability nova — D26/D20).
  if not public.ciclo_ator_valido(p_actor_user_profile_id, v_org, 'cycle.manage') then
    raise exception 'F5_09_FORBIDDEN: ator sem perfil/membership ativa e capability cycle.manage na organizacao';
  end if;

  -- (4) Idempotencia ANTES do lock (replay nao bloqueia nem reexecuta).
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', p_cycle_id,
      'collaborator_id', (v_evento.after_value->>'collaborator_id')::uuid,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status',
      'snapshot_id', v_evento.result_entity_id,
      'admissao_event_id', (v_evento.after_value->>'admissao_event_id')::uuid,
      'reference_date', (v_evento.after_value->>'reference_date')::timestamptz,
      'posicoes_materializadas', coalesce((v_evento.after_value->>'posicoes_materializadas')::integer, 0),
      'membros_materializados', coalesce((v_evento.after_value->>'membros_materializados')::integer, 0),
      'responsabilidades_materializadas', coalesce((v_evento.after_value->>'responsabilidades_materializadas')::integer, 0));
  end if;

  -- (5) Membership ativa do ator (autoria soberana — §12.1).
  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_09_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (6) Lock normativo da familia de CICLOS (§11) — mesma chave da P2.
  perform public.ciclo_lock_organizacao(v_org);

  -- (7) Idempotencia DEPOIS do lock (corrida entre duas chamadas identicas).
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', p_cycle_id,
      'collaborator_id', (v_evento.after_value->>'collaborator_id')::uuid,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status',
      'snapshot_id', v_evento.result_entity_id,
      'admissao_event_id', (v_evento.after_value->>'admissao_event_id')::uuid,
      'reference_date', (v_evento.after_value->>'reference_date')::timestamptz,
      'posicoes_materializadas', coalesce((v_evento.after_value->>'posicoes_materializadas')::integer, 0),
      'membros_materializados', coalesce((v_evento.after_value->>'membros_materializados')::integer, 0),
      'responsabilidades_materializadas', coalesce((v_evento.after_value->>'responsabilidades_materializadas')::integer, 0));
  end if;

  -- (8) Ciclo do tenant, travado para a decisao.
  select c.id, c.ano, c.numero, c.status, c.version, c.data_ativacao
    into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_09_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;

  -- (§6/D26) A inclusao NAO e transicao de estado: exige ciclo ATIVO e nada muda
  -- em status/data_*; a versao e o token otimista (desvio (b) no header).
  if v_ciclo.status <> 'ATIVO' then
    raise exception 'F5_09_CONFLICT: inclusao de admissao exige ciclo ATIVO (status atual %)',
      v_ciclo.status;
  end if;
  if v_ciclo.version <> p_expected_version then
    raise exception 'F5_09_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- (9) Colaborador do MESMO tenant (cross-tenant indistinguivel de inexistente:
  -- a recusa nunca revela a existencia de recurso de outro tenant).
  if not exists (
    select 1 from public.collaborators c
     where c.id = p_collaborator_id and c.organization_id = v_org
  ) then
    raise exception 'F5_09_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  -- (10) Prova soberana de admissao P1–P7 (fail-closed). O helper revalida
  -- tenant/estado; a mensagem carrega o motivo para auditoria e para o validador.
  v_eleg := public.ciclo_admissao_pos_ativacao_elegivel(
    v_org, p_cycle_id, p_collaborator_id);
  if coalesce((v_eleg->>'elegivel')::boolean, false) is not true then
    raise exception 'F5_09_CONFLICT: inclusao aditiva recusada fail-closed (P1-P7): %',
      coalesce(v_eleg->>'motivo', 'MOTIVO_NAO_INFORMADO');
  end if;
  v_adm_evt   := (v_eleg->>'admissao_event_id')::uuid;
  v_adm_data  := (v_eleg->>'admissao_effective_date')::timestamptz;
  v_posicao   := (v_eleg->>'posicao_id')::uuid;
  v_unidade   := (v_eleg->>'unidade_id')::uuid;
  v_sup_pos   := (v_eleg->>'superior_position_id')::uuid;
  v_sup_colab := (v_eleg->>'superior_collaborator_id')::uuid;

  -- (11) Materializacao ADITIVA na MENOR granularidade segura (§7.3/§13.3):
  -- SOMENTE este colaborador na F3-08 (que so faz INSERT) e a F3-09 idempotente
  -- por (snapshot, posicao). Nenhuma linha existente e sobrescrita/removida.
  perform public.materializar_colegiado_ciclo(
    v_org, v_ciclo.ano, v_ciclo.numero, v_instante, array[p_collaborator_id]);
  perform public.materializar_responsabilidades_avaliacao(
    v_org, v_ciclo.ano, v_ciclo.numero);

  -- (12) Fail-closed: a primitiva TEM de ter materializado exatamente o snapshot
  -- do colaborador incluido; caso contrario a operacao aborta (rollback total).
  select count(*) into v_qtd_snap
    from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org
     and s.ano = v_ciclo.ano
     and s.ciclo = v_ciclo.numero
     and s.collaborator_id = p_collaborator_id;
  if v_qtd_snap <> 1 then
    raise exception 'F5_09_INTERNAL: snapshot do colaborador incluido nao materializado (linhas=%)',
      v_qtd_snap;
  end if;
  select s.id into v_snap_id
    from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org
     and s.ano = v_ciclo.ano
     and s.ciclo = v_ciclo.numero
     and s.collaborator_id = p_collaborator_id;

  select count(*) into v_qtd_pos
    from public.collegiate_cycle_snapshot_positions sp
   where sp.snapshot_id = v_snap_id and sp.organization_id = v_org;
  select count(*) into v_qtd_memb
    from public.collegiate_cycle_snapshot_members m
   where m.snapshot_id = v_snap_id and m.organization_id = v_org;
  select count(*) into v_qtd_resp
    from public.cycle_evaluation_responsibilities r
   where r.snapshot_id = v_snap_id and r.organization_id = v_org;

  -- (13) Version+1 (token otimista da populacao; desvio (b) no header).
  update public.evaluation_cycles
     set version = version + 1
   where id = p_cycle_id
     and organization_id = v_org
  returning version into v_nova_versao;

  -- (14) Trilha: exatamente UM evento append-only, na MESMA transacao, com
  -- autoria soberana e SEM dados pessoais (§12.2/§12.3).
  insert into public.cycle_events (
    organization_id, cycle_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_cycle_id, 'evaluation_cycle', 'ADMISSAO_INCLUIDA', v_instante,
    v_motivo,
    jsonb_build_object(
      'status', v_ciclo.status, 'ano', v_ciclo.ano, 'numero', v_ciclo.numero,
      'version', v_ciclo.version, 'data_ativacao', v_ciclo.data_ativacao),
    jsonb_build_object(
      'status', 'ATIVO', 'version', v_nova_versao,
      'collaborator_id', p_collaborator_id,
      'admissao_event_id', v_adm_evt,
      'admissao_effective_date', v_adm_data,
      'reference_date', v_instante,
      'posicao_id', v_posicao,
      'unidade_id', v_unidade,
      'superior_position_id', v_sup_pos,
      'superior_collaborator_id', v_sup_colab,
      'snapshot_id', v_snap_id,
      'posicoes_materializadas', v_qtd_pos,
      'membros_materializados', v_qtd_memb,
      'responsabilidades_materializadas', v_qtd_resp),
    v_hash, v_snap_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'cycle_id', p_cycle_id,
    'collaborator_id', p_collaborator_id,
    'version', v_nova_versao,
    'status', 'ATIVO',
    'snapshot_id', v_snap_id,
    'admissao_event_id', v_adm_evt,
    'reference_date', v_instante,
    'posicoes_materializadas', v_qtd_pos,
    'membros_materializados', v_qtd_memb,
    'responsabilidades_materializadas', v_qtd_resp);
end;
$$;

comment on function public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid) is
  'F5-09 P3 (D26/§7.3/§13.2): UNICA ampliacao de populacao permitida depois da '
  'ativacao. Exige ciclo ATIVO do tenant, ator com membership ativa e capability '
  'efetiva cycle.manage, expected_version, motivo e a prova soberana P1-P7 do '
  'helper. Exclusivamente ADITIVA: nao aceita parametro estrutural algum, recusa '
  'colaborador ja materializado e so INSERE via materializar_colegiado_ciclo '
  '(F3-08, um unico collaborator_id) + materializar_responsabilidades_avaliacao '
  '(F3-09, idempotente). Idempotente por (organization_id, operation_id) com hash '
  'canonico derivado server-side; serializada por ciclo_lock_organizacao; grava '
  'UM evento ADMISSAO_INCLUIDA com o id do evento ADMISSAO que autorizou. Nao '
  'rematerializa estrutura, nao corrige legado e nao movimenta participantes. '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 3) ACL: EXECUTE somente service_role (nenhuma superficie nova ao cliente)
-- ----------------------------------------------------------------------------
revoke all on function public.ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)
  to service_role;
grant execute on function public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 4) Guarda final FAIL-CLOSED (§19 P3)
-- ----------------------------------------------------------------------------
-- A migration so termina se: as duas funcoes existirem com a assinatura do
-- contrato (SEM parametro estrutural), forem SECURITY INVOKER com search_path
-- fixo e EXECUTE restrito; a RPC adquirir a chave normativa da familia de ciclos
-- e NAO conter escrita/remocao nas tabelas de snapshot/responsabilidade (prova
-- estatica da aditividade) nem depender de `admission_date`; e as fundacoes da
-- P1/P2 e o deny-by-default continuarem intactos.
do $$
declare
  v_fns text[] := array[
    'ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)',
    'ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)'];
  v_fn      text;
  v_rec     record;
  v_def     text;
  v_args    text;
  v_problemas text[] := array[]::text[];
begin
  foreach v_fn in array v_fns loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config,
           pg_get_functiondef(p.oid) as def,
           pg_get_function_arguments(p.oid) as args
      into v_rec
      from pg_proc p
     where p.oid = to_regprocedure('public.' || v_fn);
    if not found then
      v_problemas := v_problemas || ('ausente: ' || v_fn);
      continue;
    end if;
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

  -- Assinatura congelada do contrato (§13.2): NENHUM parametro estrutural.
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_collaborator_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    v_problemas := v_problemas || ('assinatura fora do contrato: ' || coalesce(v_args, 'nula'));
  end if;

  -- Aditividade por construcao (A11): a RPC nao escreve/remove nada nas tabelas
  -- de snapshot nem nas responsabilidades (a materializacao e delegada a F3-08).
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)');
  if v_def is null then
    v_problemas := v_problemas || 'definicao de ciclo_incluir_admissao ilegivel'::text;
  else
    if position('ciclo_lock_organizacao' in v_def) = 0 then
      v_problemas := v_problemas || 'ciclo_incluir_admissao sem a chave normativa de ciclos'::text;
    end if;
    if position('position_reporting_lines:' in v_def) > 0
       or position('f5_07_estrutura:' in v_def) > 0 then
      v_problemas := v_problemas || 'ciclo_incluir_admissao usa chave de OUTRA familia de lock'::text;
    end if;
    if position('update public.collegiate_cycle_snapshots' in lower(v_def)) > 0
       or position('delete from public.collegiate_cycle_snapshots' in lower(v_def)) > 0
       or position('update public.collegiate_cycle_snapshot_positions' in lower(v_def)) > 0
       or position('update public.collegiate_cycle_snapshot_members' in lower(v_def)) > 0
       or position('delete from public.collegiate_cycle_snapshot_positions' in lower(v_def)) > 0
       or position('delete from public.collegiate_cycle_snapshot_members' in lower(v_def)) > 0
       or position('update public.cycle_evaluation_responsibilities' in lower(v_def)) > 0
       or position('delete from public.cycle_evaluation_responsibilities' in lower(v_def)) > 0
       or position('insert into public.collegiate_cycle_snapshots' in lower(v_def)) > 0 then
      v_problemas := v_problemas || 'ciclo_incluir_admissao escreve direto em snapshot/responsabilidade (deveria delegar a F3-08/F3-09)'::text;
    end if;
    if position('admission_date' in lower(v_def)) > 0 then
      v_problemas := $q$ciclo_incluir_admissao referencia admission_date (dado declarado NAO e prova — P7)$q$;
    end if;
    if position('funcao' in lower(v_def)) > 0 or position('cargo' in lower(v_def)) > 0 then
      v_problemas := v_problemas || 'ciclo_incluir_admissao referencia cargo/funcao textual (hierarquia e relacional)'::text;
    end if;
  end if;

  -- Helper read-only: nao pode escrever nada.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)');
  if v_def is null then
    v_problemas := v_problemas || 'definicao do helper ilegivel'::text;
  else
    if position('insert into' in lower(v_def)) > 0
       or position('update public.' in lower(v_def)) > 0
       or position('delete from' in lower(v_def)) > 0
       or position('admission_date' in lower(v_def)) > 0 then
      v_problemas := v_problemas || 'helper de elegibilidade nao e estritamente read-only/sem admission_date'::text;
    end if;
    if position('materializar_colegiado_ciclo' in lower(v_def)) > 0 then
      v_problemas := v_problemas || 'helper de elegibilidade materializa estrutura (deveria ser read-only)'::text;
    end if;
  end if;

  -- P1/P2 intactas: I5, I6, trilha append-only, idempotencia e deny-by-default.
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    v_problemas := v_problemas || 'I5 ausente'::text;
  end if;
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_cycles'::regclass
       and conname = 'ex_evaluation_cycles_periodo_no_overlap' and contype = 'x'
  ) then
    v_problemas := v_problemas || 'I6 ausente'::text;
  end if;
  foreach v_fn in array array[
    'trg_cycle_events_append_only', 'trg_cycle_events_no_delete',
    'trg_cycle_events_no_truncate']
  loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid = 'public.cycle_events'::regclass
         and tgname = v_fn and not tgisinternal
    ) then
      v_problemas := v_problemas || ('trigger ausente: ' || v_fn);
    end if;
  end loop;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('evaluation_cycles', 'cycle_events')
  ) then
    v_problemas := v_problemas || 'policy antecipada (leitura de ciclo e do P5)'::text;
  end if;
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_problemas := v_problemas || 'anon/authenticated com acesso antecipado'::text;
  end if;

  -- P4+ NAO antecipado: nenhuma RPC excepcional do P4 pode existir aqui.
  if exists (
    select 1 from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('ciclo_cancelar', 'ciclo_reabrir', 'ciclo_corrigir_periodo')
  ) then
    v_problemas := v_problemas || 'P4 antecipado (RPC excepcional presente)'::text;
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception 'F5_09_P3_GUARD: fundacao da P3 inconsistente: %',
      array_to_string(v_problemas, '; ');
  end if;

  raise notice 'F5-09 P3: guarda final OK (helper read-only + RPC aditiva INVOKER com EXECUTE so service_role; P1/P2 e deny-by-default intactos; nenhum P4+ antecipado)';
end $$;
