-- ============================================================================
-- F6 / Issue #427 — CARDINALIDADE SOBERANA DE OCUPAÇÕES
-- ----------------------------------------------------------------------------
-- Contrato: Issue #427 + comentário "Desenho técnico fechado para implementação"
-- (registrado na própria Issue). Esta migration é ADITIVA: nenhuma migration
-- histórica é editada; as definições anteriores permanecem como história.
--
-- Invariante nova (§1): no máximo UMA ocupação organizacional por colaborador em
-- qualquer instante. A exclusão temporal existente por POSIÇÃO
-- (`ex_occupations_position_no_overlap`, 20260907150000) é PRESERVADA; esta
-- migration acrescenta a exclusão temporal por COLLABORATOR_ID. Períodos
-- consecutivos (fim de A exatamente no início de B) permanecem válidos pelo
-- modelo meio-aberto `[valid_from, valid_to)`.
--
-- Substituições/responsabilidades temporárias (`temporary_responsibilities`)
-- NÃO são ocupações, ficam FORA desta constraint e continuam podendo ser
-- múltiplas (§7).
--
-- Regra server-side de cardinalidade (§3):
--   0  = ausência;            1 = origem válida;   >1 = inconsistência.
-- `>1` NUNCA pode autorizar união de ocupações, escolha por ordenação,
-- `LIMIT 1` ou retorno parcial. Fluxos que exigem colaborador ativo posicionado
-- falham antes de qualquer efeito.
--
-- Dados funcionais atuais são massa de teste descartável: NÃO há plano de
-- migração/reconciliação. A pré-checagem abaixo é apenas fail-closed explícito
-- (nenhum dado é alterado por esta migration).
--
-- Supersede, nos pontos indicados: o comentário histórico da F3-07
-- ("múltiplas occupations de um colaborador produzem UNIÃO coerente de escopo")
-- e os trechos das F3-05/F3-07/F3-08/F3-09/F5-06/F5-09 que escolhiam a ocupação
-- do colaborador com `order by ... limit 1`.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Barreira final do banco: exclusão temporal por colaborador
-- ----------------------------------------------------------------------------
do $pre$
declare
  v_n integer;
begin
  select count(*) into v_n
    from public.occupations a
    join public.occupations b
      on b.collaborator_id = a.collaborator_id
     and b.id > a.id
     and tstzrange(a.valid_from, coalesce(a.valid_to, 'infinity'::timestamptz), '[)')
      && tstzrange(b.valid_from, coalesce(b.valid_to, 'infinity'::timestamptz), '[)');

  if v_n > 0 then
    raise exception
      'F6_427: % sobreposicoes de ocupacao por colaborador impedem a nova exclusion constraint. Os dados funcionais atuais sao massa descartavel e a Issue #427 nao define reconciliacao: reconstrua o ambiente (db reset) em vez de normalizar dados.',
      v_n;
  end if;
end
$pre$;

alter table public.occupations
  add constraint ex_occupations_collaborator_no_overlap
  exclude using gist (
    collaborator_id with =,
    tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&
  );

comment on constraint ex_occupations_collaborator_no_overlap
  on public.occupations is
  'F6 / #427: cardinalidade soberana — no maximo UMA ocupacao por colaborador em '
  'qualquer instante, inclusive entre posicoes diferentes. Periodos consecutivos '
  '(fim de A = inicio de B) permanecem validos (tstzrange meio-aberto). '
  'Substituicoes/responsabilidades temporarias nao sao occupations e nao sao '
  'afetadas.';

-- ----------------------------------------------------------------------------
-- 2) Primitivas server-side de cardinalidade (§3)
-- ----------------------------------------------------------------------------
create or replace function public.colaborador_ocupacoes_cardinalidade(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns integer
language sql
stable
set search_path = public
as $$
  select count(*)::int
    from public.occupations o
   where o.collaborator_id = p_collaborator_id
     and o.valid_from <= p_data
     and (o.valid_to is null or o.valid_to > p_data)
$$;

comment on function public.colaborador_ocupacoes_cardinalidade(uuid, timestamptz) is
  'F6 / #427 §3: cardinalidade de ocupacoes do colaborador na data soberana '
  '(meio-aberto [valid_from, valid_to)). 0 = ausencia, 1 = origem valida, '
  '>1 = inconsistencia (fail-closed no consumidor).';

create or replace function public.colaborador_posicao_soberana(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns uuid
language sql
stable
set search_path = public
as $$
  select case
           when count(*) = 1 then (array_agg(o.organizational_position_id))[1]
           else null
         end
    from public.occupations o
   where o.collaborator_id = p_collaborator_id
     and o.valid_from <= p_data
     and (o.valid_to is null or o.valid_to > p_data)
$$;

comment on function public.colaborador_posicao_soberana(uuid, timestamptz) is
  'F6 / #427 §3: posicao soberana do colaborador na data. Devolve a posicao '
  'quando a cardinalidade e exatamente 1; devolve NULL tanto para 0 (ausencia) '
  'quanto para >1 (ambiguidade) — fail-closed: NUNCA escolhe por ordenacao, '
  'NUNCA une e NUNCA devolve resultado parcial. Consumidores que exigem '
  'colaborador ativo posicionado usam colaborador_ocupacoes_cardinalidade para '
  'distinguir 0 de >1.';

revoke all on function public.colaborador_ocupacoes_cardinalidade(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.colaborador_ocupacoes_cardinalidade(uuid, timestamptz)
  to service_role;

revoke all on function public.colaborador_posicao_soberana(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.colaborador_posicao_soberana(uuid, timestamptz)
  to service_role;

-- ----------------------------------------------------------------------------
-- 3) Escrita de ocupações (§2) — definir
-- ----------------------------------------------------------------------------
-- Conserva transação, lock, idempotência, auditoria e a semântica de fechar a
-- ocupação anterior e abrir a nova. Acrescenta:
--   - normalização da vigência para a data civil UTC e a guarda de "segunda
--     transição na mesma relação e data civil" (contrato temporal da #366,
--     preservado literalmente);
--   - cardinalidade explícita: `>1` atravessando a data efetiva é CONFLITO,
--     sem fechamento em lote;
--   - recusa de ocupação existente do mesmo colaborador que inicie na vigência
--     ou depois dela (a nova ocupação nasce aberta em [p_vigencia, infinity)).
create or replace function public.estrutura_ocupacao_definir(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_position_id uuid,
  p_vigencia timestamptz,
  p_motivo text,
  p_cycle_scope text,
  p_reference_cycle_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org           uuid;
  v_motivo        text := btrim(coalesce(p_motivo, ''));
  v_scope         text := coalesce(nullif(btrim(coalesce(p_cycle_scope, '')), ''),
                                   'CICLO_ATUAL_E_POSTERIORES');
  v_hash          text;
  v_evento        record;
  v_membership    uuid;
  v_collab        record;
  v_status        text;
  v_vigentes_qtd  int;
  v_fechadas_qtd  int;
  v_fechadas_list jsonb;
  v_fech_pos      uuid;
  v_id            uuid;
  v_op_encerr     uuid;
  v_agora         timestamptz := now();
begin
  if p_operation_id is null or p_collaborator_id is null or p_position_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id, collaborator_id e position_id obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  p_vigencia := public.f6_vigencia_civil_utc(p_vigencia);

  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;
  if v_scope not in ('CICLO_ATUAL_E_POSTERIORES', 'SOMENTE_CICLOS_POSTERIORES') then
    raise exception 'F5_07_INVALID_INPUT: cycle_scope invalido';
  end if;
  if p_reference_cycle_id is not null then
    if not exists (
      select 1
        from public.evaluation_cycles ec
       where ec.id = p_reference_cycle_id
         and ec.organization_id = p_organization_id
    ) then
      raise exception 'F5_07_NOT_FOUND: ciclo de referencia inexistente ou de outro tenant';
    end if;
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_ocupacao_definir',
    'organization_id', p_organization_id,
    'collaborator_id', p_collaborator_id,
    'position_id', p_position_id,
    'vigencia', p_vigencia,
    'motivo', v_motivo,
    'cycle_scope', v_scope,
    'reference_cycle_id', p_reference_cycle_id
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash, e.result_entity_id
    into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select c.organization_id into v_collab
    from public.collaborators c
   where c.id = p_collaborator_id
     for update;
  if not found then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;
  v_org := v_collab.organization_id;
  if v_org is distinct from p_organization_id then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  if not exists (
    select 1
      from public.organizational_positions p
     where p.id = p_position_id
       and p.organization_id = v_org
  ) then
    raise exception 'F5_07_NOT_FOUND: posicao inexistente ou de outro tenant';
  end if;

  -- Predicado de dominio (§9.4): colaborador desligado nao recebe alocacao.
  select sp.status into v_status
    from public.collaborator_status_periods sp
   where sp.collaborator_id = p_collaborator_id
     and sp.valid_from <= v_agora
     and (sp.valid_to is null or sp.valid_to > v_agora)
   order by sp.valid_from desc, sp.id
   limit 1;
  if v_status = 'inactive' then
    raise exception 'F5_07_CONFLICT: colaborador inativo nao pode receber ocupacao';
  end if;

  -- Lock de transacao por organizacao (mesmo padrao da F3-04): serializa
  -- leitura-antes-de-escrever da estrutura do tenant.
  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  if exists (
    select 1 from public.collaborator_events e
     where e.organization_id = p_organization_id
       and e.collaborator_id = p_collaborator_id
       and e.position_id = p_position_id
       and e.event_type in ('OCUPACAO_INICIADA', 'OCUPACAO_ENCERRADA')
       and e.effective_date = p_vigencia
  ) then
    raise exception 'F5_07_CONFLICT: segunda transicao de ocupacao na mesma relacao e data civil';
  end if;

  -- F6 / #427 §2: cardinalidade explicita. Fechar em LOTE deixa de ser aceito:
  -- mais de uma ocupacao atravessando a data efetiva e estado AMBIGUO.
  select count(*)::int into v_vigentes_qtd
    from public.occupations o
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from <= p_vigencia
     and (o.valid_to is null or o.valid_to > p_vigencia);
  if v_vigentes_qtd > 1 then
    raise exception 'F5_07_CONFLICT: cardinalidade de ocupacao ambigua (>1 vigentes na data) — sem fechamento em lote';
  end if;

  -- F6 / #427 §2: a nova ocupacao nasce ABERTA em [p_vigencia, infinity):
  -- qualquer ocupacao do mesmo colaborador que inicie na vigencia ou depois
  -- dela se sobreporia a nova (a exclusion constraint e a barreira final; aqui
  -- o erro sai com codigo publico estavel e sem efeito parcial).
  if exists (
    select 1
      from public.occupations o
     where o.collaborator_id = p_collaborator_id
       and o.organization_id = v_org
       and o.valid_from >= p_vigencia
  ) then
    raise exception 'F5_07_CONFLICT: ocupacao existente inicia na vigencia ou depois dela e se sobreporia a nova ocupacao';
  end if;

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'occupation_id', o.id,
           'position_id', o.organizational_position_id,
           'valid_from', o.valid_from) order by o.valid_from, o.id), '[]'::jsonb),
         (array_agg(o.organizational_position_id order by o.valid_from, o.id))[1]
    into v_fechadas_qtd, v_fechadas_list, v_fech_pos
    from public.occupations o
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from < p_vigencia
     and (o.valid_to is null or o.valid_to > p_vigencia);

  update public.occupations o
     set valid_to = p_vigencia,
         version = version + 1
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from < p_vigencia
     and (o.valid_to is null or o.valid_to > p_vigencia);

  -- A posicao alvo precisa estar VAGA na vigencia (a exclusion constraint e a
  -- ultima barreira; aqui o erro sai com codigo publico estavel).
  if exists (
    select 1
      from public.occupations o
     where o.organizational_position_id = p_position_id
       and o.valid_from <= p_vigencia
       and (o.valid_to is null or o.valid_to > p_vigencia)
  ) then
    raise exception 'F5_07_CONFLICT: posicao ja possui ocupante vigente nessa data (encerre antes)';
  end if;

  insert into public.occupations
    (organization_id, collaborator_id, organizational_position_id, reason, valid_from)
  values (v_org, p_collaborator_id, p_position_id, v_motivo, p_vigencia)
  returning id into v_id;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, collaborator_id, position_id, event_type, effective_date,
    cycle_scope, reference_cycle_id, reason, before_value, after_value,
    payload_hash, result_entity_id, actor_user_profile_id, actor_membership_id,
    operation_id
  ) values (
    v_org, p_collaborator_id, p_position_id, 'OCUPACAO_INICIADA', p_vigencia,
    v_scope, p_reference_cycle_id, v_motivo,
    jsonb_build_object('ocupacoes_encerradas', v_fechadas_list),
    jsonb_build_object('occupation_id', v_id, 'position_id', p_position_id,
                       'valid_from', p_vigencia),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  -- Encerramento registrado na MESMA transacao. A chave de idempotencia e
  -- `(organization_id, operation_id)` (unica), portanto o evento secundario usa
  -- um operation_id DERIVADO deterministico do principal — repetir o pedido
  -- devolve o resultado sem gravar nada novo.
  if v_fechadas_qtd > 0 then
    v_op_encerr := md5(p_operation_id::text || ':OCUPACAO_ENCERRADA')::uuid;

    insert into public.collaborator_events (
      organization_id, collaborator_id, position_id, event_type, effective_date,
      cycle_scope, reference_cycle_id, reason, before_value, after_value,
      payload_hash, result_entity_id, actor_user_profile_id, actor_membership_id,
      operation_id
    ) values (
      v_org, p_collaborator_id,
      case when v_fechadas_qtd = 1 then v_fech_pos else null end,
      'OCUPACAO_ENCERRADA', p_vigencia, v_scope, p_reference_cycle_id, v_motivo,
      jsonb_build_object('ocupacoes', v_fechadas_list),
      jsonb_build_object('valid_to', p_vigencia),
      v_hash,
      case when v_fechadas_qtd = 1 then v_fech_pos else null end,
      p_actor_user_profile_id, v_membership, v_op_encerr
    );
  end if;

  return v_id;
end;
$$;

comment on function public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid) is
  'F5-07/F6 #427: define a ocupacao do colaborador fechando a anterior e abrindo '
  'a nova na MESMA transacao. Exige ZERO ou UMA ocupacao atravessando a data '
  'efetiva (>1 = CONFLICT, sem fechamento em lote) e recusa ocupacao existente do '
  'mesmo colaborador que inicie na vigencia ou depois dela. Idempotente por '
  '(organization_id, operation_id) e auditada em collaborator_events.';

revoke all on function public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 4) Escrita de ocupações (§2) — trocar
-- ----------------------------------------------------------------------------
-- Exige EXATAMENTE UMA ocupacao atravessando a data, comprova que ela
-- corresponde a `p_current_position_id`, fecha A e abre B atomicamente e recusa
-- sobreposicao futura. Conserva lock, idempotencia, auditoria e o contrato
-- temporal da #366.
create or replace function public.estrutura_ocupacao_trocar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_current_position_id uuid,
  p_new_position_id uuid,
  p_vigencia timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_vigencia      timestamptz;
  v_motivo        text := btrim(coalesce(p_motivo, ''));
  v_hash          text;
  v_evento        record;
  v_org           uuid;
  v_membership    uuid;
  v_old           record;
  v_new_id        uuid;
  v_op_close      uuid;
  v_vigentes_qtd  int;
begin
  if p_operation_id is null or p_collaborator_id is null
     or p_current_position_id is null or p_new_position_id is null then
    raise exception 'F5_07_INVALID_INPUT: ids obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if p_current_position_id = p_new_position_id then
    raise exception 'F5_07_INVALID_INPUT: posicao atual e nova devem ser diferentes';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_vigencia := public.f6_vigencia_civil_utc(p_vigencia);
  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_ocupacao_trocar',
    'organization_id', p_organization_id,
    'collaborator_id', p_collaborator_id,
    'current_position_id', p_current_position_id,
    'new_position_id', p_new_position_id,
    'vigencia', v_vigencia,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash, e.result_entity_id into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || p_organization_id::text));

  if exists (
    select 1 from public.collaborator_events e
     where e.organization_id = p_organization_id
       and e.collaborator_id = p_collaborator_id
  and e.position_id in (p_current_position_id, p_new_position_id)
       and e.event_type in ('OCUPACAO_INICIADA', 'OCUPACAO_ENCERRADA')
       and e.effective_date = v_vigencia
  ) then
    raise exception 'F5_07_CONFLICT: segunda transicao de ocupacao na mesma relacao e data civil';
  end if;

  select c.organization_id into v_org from public.collaborators c
   where c.id = p_collaborator_id for update;
  if not found or v_org is distinct from p_organization_id then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  -- F6 / #427 §2: EXATAMENTE UMA ocupacao atravessando a data efetiva.
  select count(*)::int into v_vigentes_qtd
    from public.occupations o
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from <= v_vigencia
     and (o.valid_to is null or o.valid_to > v_vigencia);
  if v_vigentes_qtd = 0 then
    raise exception 'F5_07_NOT_FOUND: colaborador sem ocupacao vigente na data';
  end if;
  if v_vigentes_qtd > 1 then
    raise exception 'F5_07_CONFLICT: cardinalidade de ocupacao ambigua (>1 vigentes na data)';
  end if;

  select o.id, o.organizational_position_id, o.valid_from, o.valid_to
    into v_old from public.occupations o
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from <= v_vigencia
     and (o.valid_to is null or o.valid_to > v_vigencia);
  if not found then
    raise exception 'F5_07_NOT_FOUND: ocupacao atual inexistente ou nao vigente na data';
  end if;
  if v_old.organizational_position_id is distinct from p_current_position_id then
    raise exception 'F5_07_CONFLICT: ocupacao vigente nao corresponde a posicao atual informada';
  end if;
  if v_old.valid_from >= v_vigencia then
    raise exception 'F5_07_CONFLICT: ocupacao vigente inicia na propria vigencia — nao ha intervalo anterior a fechar';
  end if;

  if not exists (
    select 1 from public.organizational_positions p
     where p.id = p_new_position_id and p.organization_id = v_org
       and p.valid_from <= v_vigencia
       and (p.valid_to is null or p.valid_to > v_vigencia)
  ) then
    raise exception 'F5_07_CONFLICT: nova posicao inexistente ou nao vigente na data';
  end if;
  if exists (
    select 1 from public.occupations o
     where o.organization_id = v_org
       and o.organizational_position_id = p_new_position_id
       and o.valid_from <= v_vigencia
       and (o.valid_to is null or o.valid_to > v_vigencia)
  ) then
    raise exception 'F5_07_CONFLICT: nova posicao ja possui ocupante vigente nessa data';
  end if;

  -- F6 / #427 §2: a nova ocupacao nasce ABERTA em [v_vigencia, infinity);
  -- qualquer outra ocupacao do colaborador iniciando na vigencia ou depois dela
  -- se sobreporia a ela.
  if exists (
    select 1 from public.occupations o
     where o.collaborator_id = p_collaborator_id
       and o.organization_id = v_org
       and o.id <> v_old.id
       and o.valid_from >= v_vigencia
  ) then
    raise exception 'F5_07_CONFLICT: ocupacao existente do colaborador inicia na vigencia ou depois dela';
  end if;

  update public.occupations set valid_to = v_vigencia, version = version + 1
   where id = v_old.id;
  insert into public.occupations
    (organization_id, collaborator_id, organizational_position_id, reason, valid_from)
  values (v_org, p_collaborator_id, p_new_position_id, v_motivo, v_vigencia)
  returning id into v_new_id;

  select m.id into v_membership from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, collaborator_id, position_id, event_type, effective_date,
    cycle_scope, reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_collaborator_id, p_new_position_id, 'OCUPACAO_INICIADA', v_vigencia,
    'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    jsonb_build_object('occupation_id', v_old.id, 'position_id', p_current_position_id,
                       'valid_to', v_vigencia),
    jsonb_build_object('occupation_id', v_new_id, 'position_id', p_new_position_id,
                       'valid_from', v_vigencia), v_hash, v_new_id,
    p_actor_user_profile_id, v_membership, p_operation_id
  );

  v_op_close := md5(p_operation_id::text || ':OCUPACAO_ENCERRADA')::uuid;
  insert into public.collaborator_events (
    organization_id, collaborator_id, position_id, event_type, effective_date,
    cycle_scope, reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_collaborator_id, p_current_position_id, 'OCUPACAO_ENCERRADA', v_vigencia,
    'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    jsonb_build_object('occupation_id', v_old.id, 'position_id', p_current_position_id,
                       'valid_from', v_old.valid_from),
    jsonb_build_object('valid_to', v_vigencia, 'replaced_by', v_new_id), v_hash, v_old.id,
    p_actor_user_profile_id, v_membership, v_op_close
  );
  return v_new_id;
end;
$$;

comment on function public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text) is
  'F6 #375/#427: troca ATOMICA de posicao. Exige EXATAMENTE UMA ocupacao '
  'atravessando a data efetiva, comprova que ela corresponde a '
  'p_current_position_id, fecha A e abre B na mesma transacao e recusa '
  'sobreposicao futura. Falha nao deixa efeito parcial.';

revoke all on function public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- 5) Resolvers estruturais F3-07 (§3/§4) — origem ambígua deixa de produzir união
-- ----------------------------------------------------------------------------
-- Todos partiam de TODAS as ocupações do colaborador e produziam UNIÃO de
-- escopo. Passam a exigir origem ÚNICA: com `>1` devolvem ZERO linhas
-- (DENY/fail-closed) — nunca união, nunca escolha por ordenação, nunca
-- `LIMIT 1`. Com origem única, a travessia da árvore de reporting lines é
-- preservada integralmente. Múltiplos descendentes legítimos não são
-- ambiguidade.

create or replace function public.organizacao_resolver_gestor_direto(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  occupied_position_id uuid,
  manager_position_id uuid,
  manager_titular_collaborator_id uuid,
  manager_substitute_collaborator_id uuid,
  manager_responsible_collaborator_id uuid
)
language sql
stable
set search_path = public
as $$
  with origem as (
    select occ.organizational_position_id
      from public.occupations occ
     where occ.collaborator_id = p_collaborator_id
       and occ.valid_from <= p_data
       and (occ.valid_to is null or occ.valid_to > p_data)
  ),
  cardinalidade as (
    select count(*)::int as qtd from origem
  )
  select
    occ.organizational_position_id,
    rl.manager_position_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id
  from origem occ
  join public.position_reporting_lines rl
    on rl.subordinate_position_id = occ.organizational_position_id
   and rl.valid_from <= p_data
   and (rl.valid_to is null or rl.valid_to > p_data)
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    rl.manager_position_id, p_data
  ) r
  cross join cardinalidade c
  where c.qtd <= 1
$$;

comment on function public.organizacao_resolver_gestor_direto(uuid, timestamptz) is
  'F3-07 / F6 #427 §4: resolve o gestor formal direto do colaborador em uma '
  'data. EXIGE origem de ocupacao unica: com >1 ocupacoes vigentes devolve ZERO '
  'linhas (DENY) — nao une escopo nem escolhe por ordenacao.';

create or replace function public.organizacao_resolver_subordinados_diretos(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  subordinate_position_id uuid,
  subordinate_titular_collaborator_id uuid,
  subordinate_substitute_collaborator_id uuid,
  subordinate_responsible_collaborator_id uuid
)
language sql
stable
set search_path = public
as $$
  with origem as (
    select distinct occ.organizational_position_id as pos_id
      from public.occupations occ
     where occ.collaborator_id = p_collaborator_id
       and occ.valid_from <= p_data
       and (occ.valid_to is null or occ.valid_to > p_data)
  ),
  cardinalidade as (
    select count(*)::int as qtd from origem
  )
  select distinct
    rl.subordinate_position_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id
  from public.position_reporting_lines rl
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    rl.subordinate_position_id, p_data
  ) r
  cross join cardinalidade c
  where c.qtd <= 1
    and rl.valid_from <= p_data
    and (rl.valid_to is null or rl.valid_to > p_data)
    and exists (
      select 1 from origem o
       where o.pos_id = rl.manager_position_id
    )
$$;

comment on function public.organizacao_resolver_subordinados_diretos(uuid, timestamptz) is
  'F3-07 / F6 #427 §4: resolve as posicoes que reportam diretamente a posicao '
  'ocupada pelo colaborador. EXIGE origem de ocupacao unica: com >1 ocupacoes '
  'vigentes devolve ZERO linhas (DENY), sem uniao de escopo.';

create or replace function public.organizacao_resolver_descendentes(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  position_id uuid,
  titular_collaborator_id uuid,
  substitute_collaborator_id uuid,
  responsible_collaborator_id uuid,
  depth integer
)
language sql
stable
set search_path = public
as $$
  with recursive base as (
    select occ.organizational_position_id as pos_id, 0::int as depth
    from public.occupations occ
    where occ.collaborator_id = p_collaborator_id
      and occ.valid_from <= p_data
      and (occ.valid_to is null or occ.valid_to > p_data)
  ),
  cardinalidade as (
    select count(*)::int as qtd from base
  ),
  descend as (
    select rl.subordinate_position_id as pos_id, b.depth + 1 as depth
    from base b
    join public.position_reporting_lines rl
      on rl.manager_position_id = b.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
    union
    select rl.subordinate_position_id, d.depth + 1
    from descend d
    join public.position_reporting_lines rl
      on rl.manager_position_id = d.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
  )
  select distinct on (d.pos_id)
    d.pos_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id,
    d.depth
  from descend d
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    d.pos_id, p_data
  ) r
  cross join cardinalidade c
  where c.qtd <= 1
  order by d.pos_id, d.depth
$$;

comment on function public.organizacao_resolver_descendentes(uuid, timestamptz) is
  'F3-07 / F6 #427 §4: resolve as posicoes descendentes (transitivas) sob as '
  'posicoes ocupadas pelo colaborador. EXIGE origem de ocupacao unica: com >1 '
  'ocupacoes vigentes devolve ZERO linhas (DENY), sem uniao de subarvores.';

create or replace function public.organizacao_resolver_cadeia(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  position_id uuid,
  titular_collaborator_id uuid,
  substitute_collaborator_id uuid,
  responsible_collaborator_id uuid,
  depth integer
)
language sql
stable
set search_path = public
as $$
  with recursive base as (
    select occ.organizational_position_id as pos_id, 0::int as depth
    from public.occupations occ
    where occ.collaborator_id = p_collaborator_id
      and occ.valid_from <= p_data
      and (occ.valid_to is null or occ.valid_to > p_data)
  ),
  cardinalidade as (
    select count(*)::int as qtd from base
  ),
  upstream as (
    select b.pos_id, b.depth from base b
    union
    select rl.manager_position_id, u.depth + 1
    from upstream u
    join public.position_reporting_lines rl
      on rl.subordinate_position_id = u.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
  )
  select distinct on (u.pos_id)
    u.pos_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id,
    u.depth
  from upstream u
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    u.pos_id, p_data
  ) r
  cross join cardinalidade c
  where c.qtd <= 1
  order by u.pos_id, u.depth
$$;

comment on function public.organizacao_resolver_cadeia(uuid, timestamptz) is
  'F3-07 / F6 #427 §4: resolve a cadeia hierarquica ascendente (posicoes '
  'ocupadas + ancestrais pela reporting line). EXIGE origem de ocupacao unica: '
  'com >1 ocupacoes vigentes devolve ZERO linhas (DENY), sem uniao de cadeias.';

create or replace function public.organizacao_resolver_escopo_posicoes(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  position_id uuid,
  unit_id uuid,
  titular_collaborator_id uuid,
  substitute_collaborator_id uuid,
  responsible_collaborator_id uuid,
  is_own_position boolean
)
language sql
stable
set search_path = public
as $$
  with recursive own as (
    select occ.organizational_position_id as pos_id
    from public.occupations occ
    where occ.collaborator_id = p_collaborator_id
      and occ.valid_from <= p_data
      and (occ.valid_to is null or occ.valid_to > p_data)
  ),
  cardinalidade as (
    select count(*)::int as qtd from own
  ),
  descend as (
    select rl.subordinate_position_id as pos_id
    from own o
    join public.position_reporting_lines rl
      on rl.manager_position_id = o.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
    union
    select rl.subordinate_position_id
    from descend d
    join public.position_reporting_lines rl
      on rl.manager_position_id = d.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
  ),
  escopo as (
    select pos_id, true as propria from own
    union
    select pos_id, false as propria from descend
  )
  select distinct on (e.pos_id)
    e.pos_id,
    p.unit_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id,
    e.propria
  from escopo e
  join public.organizational_positions p on p.id = e.pos_id
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    e.pos_id, p_data
  ) r
  cross join cardinalidade c
  where c.qtd <= 1
  order by e.pos_id, e.propria desc
$$;

comment on function public.organizacao_resolver_escopo_posicoes(uuid, timestamptz) is
  'F3-07 / F6 #427 §4: escopo estrutural (posicoes proprias + descendentes) do '
  'colaborador. EXIGE origem de ocupacao unica: com >1 ocupacoes vigentes '
  'devolve ZERO linhas (DENY) — a ambiguidade NUNCA amplia autorizacao por '
  'uniao de posicoes. Substitui a expectativa historica de "uniao coerente de '
  'multiplas ocupacoes".';

-- ----------------------------------------------------------------------------
-- 6) Resolver avaliativo F3-09 (§4) — mesma regra de origem única
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_avaliador_avaliado(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  occupied_position_id uuid,
  manager_position_id uuid,
  manager_collaborator_id uuid
)
language sql
stable
set search_path = public
as $$
  with origem as (
    select occ.organizational_position_id
      from public.occupations occ
     where occ.collaborator_id = p_collaborator_id
       and occ.valid_from <= p_data
       and (occ.valid_to is null or occ.valid_to > p_data)
  ),
  cardinalidade as (
    select count(*)::int as qtd from origem
  )
  select
    occ.organizational_position_id,
    rl.manager_position_id,
    r.responsible_collaborator_id
  from origem occ
  join public.position_reporting_lines rl
    on rl.subordinate_position_id = occ.organizational_position_id
   and rl.valid_from <= p_data
   and (rl.valid_to is null or rl.valid_to > p_data)
  cross join lateral public.organizacao_resolver_responsavel_avaliativo_posicao(
    rl.manager_position_id, p_data
  ) r
  cross join cardinalidade c
  where c.qtd <= 1
$$;

comment on function public.organizacao_resolver_avaliador_avaliado(uuid, timestamptz) is
  'F3-09 / F6 #427 §4: resolve, por posicao ocupada do avaliado, a posicao '
  'superior e o responsavel avaliativo. EXIGE origem de ocupacao unica: com >1 '
  'ocupacoes vigentes devolve ZERO linhas (DENY) — multiplas posicoes do mesmo '
  'avaliado deixam de produzir multiplas linhas de resolucao (D3 revisto pela '
  '#427).';

-- ----------------------------------------------------------------------------
-- 7) Snapshots/materializações (§5)
-- ----------------------------------------------------------------------------
-- Nenhum avaliado pode materializar DUAS posicoes. A prova ocorre ANTES de
-- qualquer escrita (fail-closed, sem materializacao parcial). `0` preserva a
-- semantica existente de snapshot sem posicao (posicao vaga = ausencia de
-- ocupacao); os fluxos que EXIGEM ativo posicionado (ativacao/inclusao de ciclo
-- e abertura de avaliacao) comprovam cardinalidade nos proprios caminhos.
create or replace function public.materializar_colegiado_ciclo(
  p_organization_id uuid,
  p_ano integer,
  p_ciclo integer,
  p_reference_date timestamptz,
  p_evaluated_collaborator_ids uuid[]
)
returns void
language plpgsql
set search_path = public
as $$
begin
  if p_ano <= 0 then
    raise exception 'materializar_colegiado_ciclo: ano invalido';
  end if;
  if p_ciclo not in (1, 2, 3) then
    raise exception 'materializar_colegiado_ciclo: ciclo invalido (1..3)';
  end if;

  -- Valida a lista de avaliados: todos existentes e da mesma organização.
  if exists (
    select 1
    from unnest(p_evaluated_collaborator_ids) as x(cid)
    left join public.collaborators c
      on c.id = x.cid and c.organization_id = p_organization_id
    where x.cid is null or c.id is null
  ) then
    raise exception
      'materializar_colegiado_ciclo: avaliado inexistente ou de outra organizacao';
  end if;

  -- F6 / #427 §5: cardinalidade soberana ANTES de qualquer escrita. Um avaliado
  -- com >1 ocupacoes vigentes na reference_date e estado inconsistente: recusa
  -- sem gravacao parcial (a constraint e a barreira final).
  if exists (
    select 1
    from unnest(p_evaluated_collaborator_ids) as x(cid)
    where public.colaborador_ocupacoes_cardinalidade(x.cid, p_reference_date) > 1
  ) then
    raise exception
      'F6_427: avaliado com cardinalidade de ocupacao ambigua (>1 vigentes na reference_date) — materializacao recusada';
  end if;

  -- Cabeçalho do snapshot (idempotente: repetição não duplica/substitui).
  insert into public.collegiate_cycle_snapshots (
    id, organization_id, ano, ciclo, collaborator_id, reference_date
  )
  select
    gen_random_uuid(),
    p_organization_id,
    p_ano,
    p_ciclo,
    x.cid,
    p_reference_date
  from (
    select distinct cid
    from unnest(p_evaluated_collaborator_ids) as u(cid)
    where u.cid is not null
  ) x
  on conflict (organization_id, ano, ciclo, collaborator_id) do nothing;

  -- Posições ocupadas na data + superior formal direto resolvido por posição.
  insert into public.collegiate_cycle_snapshot_positions (
    id, snapshot_id, organization_id, position_id,
    superior_position_id, superior_collaborator_id
  )
  select
    gen_random_uuid(),
    s.id,
    s.organization_id,
    occ.organizational_position_id,
    rl.manager_position_id,
    r.responsible_collaborator_id
  from public.collegiate_cycle_snapshots s
  join (
    select distinct cid
    from unnest(p_evaluated_collaborator_ids) as u(cid)
    where u.cid is not null
  ) x on x.cid = s.collaborator_id
  cross join lateral (
    select occ.organizational_position_id
    from public.occupations occ
    where occ.collaborator_id = s.collaborator_id
      and occ.organization_id = s.organization_id
      and occ.valid_from <= p_reference_date
      and (occ.valid_to is null or occ.valid_to > p_reference_date)
  ) occ
  left join lateral (
    select rl.manager_position_id
    from public.position_reporting_lines rl
    where rl.subordinate_position_id = occ.organizational_position_id
      and rl.organization_id = s.organization_id
      and rl.valid_from <= p_reference_date
      and (rl.valid_to is null or rl.valid_to > p_reference_date)
  ) rl on true
  left join lateral public.organizacao_resolver_responsavel_posicao(
    rl.manager_position_id, p_reference_date
  ) r on true
  where s.organization_id = p_organization_id
    and s.ano = p_ano
    and s.ciclo = p_ciclo
    and not exists (
      select 1
      from public.collegiate_cycle_snapshot_positions sp
      where sp.snapshot_id = s.id
    );

  -- Membros do colegiado congelados da configuração vigente na data.
  insert into public.collegiate_cycle_snapshot_members (
    id, snapshot_id, organization_id, member_collaborator_id
  )
  select
    gen_random_uuid(),
    s.id,
    s.organization_id,
    m.member_collaborator_id
  from public.collegiate_cycle_snapshots s
  join (
    select distinct cid
    from unnest(p_evaluated_collaborator_ids) as u(cid)
    where u.cid is not null
  ) x on x.cid = s.collaborator_id
  cross join lateral (
    select cm.member_collaborator_id
    from public.collegiate_configuration_members cm
    join public.collegiate_configurations c
      on c.id = cm.configuration_id
     and c.organization_id = cm.organization_id
    where c.collaborator_id = s.collaborator_id
      and c.organization_id = s.organization_id
      and c.valid_from <= p_reference_date
      and (c.valid_to is null or c.valid_to > p_reference_date)
  ) m
  where s.organization_id = p_organization_id
    and s.ano = p_ano
    and s.ciclo = p_ciclo
    and not exists (
      select 1
      from public.collegiate_cycle_snapshot_members sm
      where sm.snapshot_id = s.id
    );
end;
$$;

comment on function public.materializar_colegiado_ciclo(uuid, integer, integer, timestamptz, uuid[]) is
  'F3-08 / F6 #427 §5: materializa (na ativacao do ciclo) o snapshot imutavel de '
  'colegiado por avaliado, com posicoes ocupadas e superior formal direto '
  'resolvido na data de referencia. Recusa (fail-closed, sem escrita parcial) '
  'avaliado com >1 ocupacoes vigentes na reference_date. Transacional e '
  'idempotente; SECURITY INVOKER.';

-- ----------------------------------------------------------------------------
-- 8) Avaliações (§6) — materialização de participantes
-- ----------------------------------------------------------------------------
-- Antes de derivar responsaveis, comprova a cardinalidade da OCUPACAO DO
-- AVALIADO na data soberana. O `LIMIT 1` existente deixa de poder mascarar duas
-- ocupacoes de origem: com >1 o snapshot e recusado antes de qualquer insercao.
-- `0` preserva a semantica existente (sem gestor derivado ⇒ pendencia de
-- completude, nunca linha artificial). Nao altera a selecao legitima de elos
-- dentro de uma unica cadeia estrutural.
create or replace function public.evaluation_snapshot_participantes(
  p_organization_id uuid,
  p_evaluation_id uuid,
  p_evaluated_collaborator_id uuid,
  p_cycle_id uuid,
  p_instante timestamptz,
  p_actor_user_profile_id uuid
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_ano integer;
  v_numero integer;
  v_snapshot uuid;
  v_ref timestamptz;
  v_qtd integer := 0;
  v_direta uuid;
  v_direta_origem text;
  v_direta_ref uuid;
  v_cadeia uuid;
  v_cadeia_origem text;
  v_cadeia_ref uuid;
  v_ocup_qtd integer;
begin
  if not public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;

  -- Fonte soberana do ciclo: a própria linha evaluation_cycles (D15).
  select c.ano, c.numero into v_ano, v_numero
    from public.evaluation_cycles c
   where c.id = p_cycle_id and c.organization_id = p_organization_id;
  if not found then
    raise exception 'F5-06: ciclo inexistente ou de outro tenant';
  end if;

  -- Snapshot F3-08 congelado do avaliado (fonte do colegiado e da data de
  -- referência). Sem snapshot materializado não há derivação possível.
  select s.id, s.reference_date into v_snapshot, v_ref
    from public.collegiate_cycle_snapshots s
   where s.organization_id = p_organization_id
     and s.ano = v_ano
     and s.ciclo = v_numero
     and s.collaborator_id = p_evaluated_collaborator_id;

  if v_snapshot is null then
    raise exception 'F5-06 D16/D23: snapshot de ciclo (F3-08) inexistente para '
      'o avaliado — materialize o colegiado/responsabilidades do ciclo antes de '
      'abrir a avaliacao';
  end if;

  -- F6 / #427 §6: cardinalidade da ocupacao do AVALIADO na data soberana antes
  -- de derivar responsaveis. >1 e inconsistencia: recusa sem efeito parcial.
  select public.colaborador_ocupacoes_cardinalidade(
           p_evaluated_collaborator_id, coalesce(v_ref, p_instante)
         ) into v_ocup_qtd;
  if v_ocup_qtd > 1 then
    raise exception 'F6_427: cardinalidade de ocupacao ambigua do avaliado (>1 vigentes na data soberana) — snapshot de participantes recusado';
  end if;

  -- GESTAO_DIRETA e GESTAO_CADEIA derivam da MESMA fonte soberana F3-07/F3-09
  -- (responsável avaliativo vigente por posição). A distinção é a posição na
  -- cadeia: CADEIA = raiz (maior profundidade); DIRETA = gestor formal direto
  -- (menor profundidade). Nenhuma consulta a cargo/job_role/seniority/funcao
  -- (D16/D17) e nenhuma decisão vem do payload do chamador. Com a cardinalidade
  -- já comprovada acima, a origem é única e o LIMIT 1 nao mascara ambiguidade.
  select g.manager_responsible_collaborator_id,
         case when g.manager_substitute_collaborator_id is not null
              then 'SUBSTITUICAO_TEMPORARIA' else 'ESTRUTURA' end,
         g.manager_position_id
    into v_direta, v_direta_origem, v_direta_ref
    from public.organizacao_resolver_gestor_direto(
      p_evaluated_collaborator_id, coalesce(v_ref, p_instante)
    ) g
   where g.manager_responsible_collaborator_id is not null
   order by g.occupied_position_id
   limit 1;

  select ch.responsible_collaborator_id,
         case when ch.substitute_collaborator_id is not null
              then 'SUBSTITUICAO_TEMPORARIA' else 'ESTRUTURA' end,
         ch.position_id
    into v_cadeia, v_cadeia_origem, v_cadeia_ref
    from public.organizacao_resolver_cadeia(
      p_evaluated_collaborator_id, coalesce(v_ref, p_instante)
    ) ch
   where ch.depth >= 1
     and ch.responsible_collaborator_id is not null
   order by ch.depth desc, ch.position_id
   limit 1;

  -- GESTAO_CADEIA (obrigatória na configuração baseline). A ocorrência sempre
  -- tem vigência explícita; ausência de responsável vira PENDÊNCIA de
  -- completude — nunca linha artificial em branco.
  if v_cadeia is not null then
    insert into public.evaluation_participants
      (organization_id, evaluation_id, role_type, collaborator_id,
       origem, origem_ref_id, valid_from, status)
    values (p_organization_id, p_evaluation_id, 'GESTAO_CADEIA', v_cadeia,
            v_cadeia_origem, v_cadeia_ref, coalesce(v_ref, p_instante), 'active');
    v_qtd := v_qtd + 1;
  end if;

  -- GESTAO_DIRETA: apenas quando o gestor formal direto NÃO for o mesmo
  -- responsável de cadeia (evita contar a mesma pessoa como duas parcelas).
  if v_direta is not null and v_direta is distinct from v_cadeia then
    insert into public.evaluation_participants
      (organization_id, evaluation_id, role_type, collaborator_id,
       origem, origem_ref_id, valid_from, status)
    values (p_organization_id, p_evaluation_id, 'GESTAO_DIRETA', v_direta,
            v_direta_origem, v_direta_ref, coalesce(v_ref, p_instante), 'active');
    v_qtd := v_qtd + 1;
  end if;

  -- COLEGIADO: snapshot soberano 0..N congelado no ciclo (F3-08).
  insert into public.evaluation_participants
    (organization_id, evaluation_id, role_type, collaborator_id,
     origem, origem_ref_id, valid_from, status)
  select p_organization_id, p_evaluation_id, 'COLEGIADO', m.member_collaborator_id,
         'SNAPSHOT_CICLO', m.snapshot_id, coalesce(v_ref, p_instante), 'active'
    from public.collegiate_cycle_snapshot_members m
   where m.snapshot_id = v_snapshot
     and m.organization_id = p_organization_id
     and m.member_collaborator_id <> p_evaluated_collaborator_id
   order by m.member_collaborator_id;

  v_qtd := v_qtd + coalesce((
    select count(*)::int from public.collegiate_cycle_snapshot_members m
     where m.snapshot_id = v_snapshot
       and m.organization_id = p_organization_id
       and m.member_collaborator_id <> p_evaluated_collaborator_id
  ), 0);

  return v_qtd;
end;
$$;

comment on function public.evaluation_snapshot_participantes(uuid, uuid, uuid, uuid, timestamptz, uuid) is
  'F5-06 D16/D17/D23 / F6 #427 §6: deriva SERVER-SIDE o snapshot de ocorrencias '
  'de participante das fontes soberanas do ciclo. Comprova a cardinalidade da '
  'ocupacao do AVALIADO na data soberana ANTES de derivar responsaveis: >1 e '
  'fail-closed sem efeito parcial, de modo que o LIMIT 1 da derivacao nao '
  'mascara duas ocupacoes de origem. Nenhum collaborator_id/role_type/vigencia '
  'vem do cliente. EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 9) Admissão pós-ativação F5-09 (§5) — prova P5 com cardinalidade explícita
-- ----------------------------------------------------------------------------
-- O helper READ-ONLY de P1–P7 escolhia a ocupação ordenando por
-- `valid_from`/`created_at` e aplicando `limit 1`. Passa a COMPROVAR a
-- cardinalidade: 0 continua `ESTRUTURA_IRRESOLVEL` (semântica preservada) e >1
-- vira `ESTRUTURA_AMBIGUA` — em ambos os casos `elegivel = false`, portanto a
-- RPC de inclusão recusa ANTES de materializar qualquer snapshot.
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
  v_ocup_qtd   integer := 0;
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
  --
  -- F6 / #427 §3/§5: a origem de ocupacao precisa ser UNICA. A contagem e
  -- explicita (sem ordenacao/limit 1): 0 => ESTRUTURA_IRRESOLVEL e >1 =>
  -- ESTRUTURA_AMBIGUA, ambos fail-closed antes de qualquer materializacao.
  select count(*)::int into v_ocup_qtd
    from public.occupations o
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from <= v_instante
     and (o.valid_to is null or o.valid_to > v_instante);

  if v_ocup_qtd = 1 then
    select o.organizational_position_id, p.unit_id
      into v_posicao, v_unidade
      from public.occupations o
      join public.organizational_positions p
        on p.id = o.organizational_position_id
       and p.organization_id = o.organization_id
     where o.collaborator_id = p_collaborator_id
       and o.organization_id = v_org
       and o.valid_from <= v_instante
       and (o.valid_to is null or o.valid_to > v_instante);
  end if;

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
  elsif v_ocup_qtd > 1 then
    v_motivo := 'ESTRUTURA_AMBIGUA';
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
  'F5-09 P3 (D26 §7.2) / F6 #427 §5: helper READ-ONLY da prova soberana de '
  'admissao posterior a ativacao (P1–P7). A prova P5 de estrutura comprova '
  'cardinalidade EXPLICITA da ocupacao: 0 => ESTRUTURA_IRRESOLVEL e >1 => '
  'ESTRUTURA_AMBIGUA, ambos elegivel=false (fail-closed, sem materializacao '
  'parcial). Nenhuma ocupacao e escolhida por ordenacao ou LIMIT 1.';

-- ----------------------------------------------------------------------------
-- 10) Guarda final fail-closed desta migration
-- ----------------------------------------------------------------------------
do $guarda$
declare
  v_nome text;
  v_def text;
  v_n integer;
begin
  -- A exclusão por POSIÇÃO permanece (nenhum contrato histórico é removido).
  if not exists (
    select 1 from pg_constraint
     where conname = 'ex_occupations_position_no_overlap'
       and conrelid = 'public.occupations'::regclass
  ) then
    raise exception 'F6_427: exclusao por posicao ausente apos a migration';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'ex_occupations_collaborator_no_overlap'
       and conrelid = 'public.occupations'::regclass
  ) then
    raise exception 'F6_427: exclusao por colaborador ausente apos a migration';
  end if;

  -- Os dois caminhos de escrita comprovam cardinalidade (>1 = conflito).
  foreach v_nome in array array[
    'estrutura_ocupacao_definir', 'estrutura_ocupacao_trocar'
  ] loop
    v_def := null;
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_nome
     order by p.oid desc
     limit 1;
    if v_def is null then
      raise exception 'F6_427: funcao de escrita ausente: %', v_nome;
    end if;
    if position('cardinalidade de ocupacao ambigua' in v_def) = 0 then
      raise exception 'F6_427: guarda de cardinalidade ausente em %', v_nome;
    end if;
  end loop;

  select count(*) into v_n
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('colaborador_ocupacoes_cardinalidade',
                       'colaborador_posicao_soberana');
  if v_n <> 2 then
    raise exception 'F6_427: primitivas de cardinalidade ausentes (encontradas %)', v_n;
  end if;

  -- Nenhum SECURITY DEFINER novo é introduzido por esta migration.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_n <> 4 then
    raise exception 'F6_427: DEFINER esperado=4, encontrado=%', v_n;
  end if;

  raise notice '[PASS] F6 #427: cardinalidade soberana de ocupacoes instalada (posicao + colaborador), guardas de escrita e de materializacao fail-closed, 4 DEFINER intactos';
end
$guarda$;
