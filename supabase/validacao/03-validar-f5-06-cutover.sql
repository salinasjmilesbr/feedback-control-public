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
  -- desta avaliação. Esta leitura é de PARTICIPANTE (edição), não do avaliado:
  -- o resultado é "sem painel" (NULL), nunca erro de backend — assim a
  -- fronteira distingue "não existe/não é acessível" de falha real.
  v_painel := public.evaluation_painel_participante(
    v_eval, 'd6b00000-0000-0000-0000-0000000000a1');

  if v_painel is not null then
    raise exception '[FAIL] avaliado obteve a leitura de EDICAO do participante';
  end if;
  raise notice '[PASS] leitura de edicao devolve NULL para quem nao tem ocorrencia vigente';
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
-- 3) CORREÇÃO DE AUDITORIA (IDOR): a ocorrência editável é do ATOR
-- ----------------------------------------------------------------------------
-- evaluation_gravar_notas / evaluation_gravar_comentario NÃO aceitam mais
-- participant_id: a ocorrência vem de auth.uid -> membership -> vínculo F5-02 ->
-- ocorrência vigente. Um ator autorizado a escrever NÃO consegue atingir a
-- ocorrência de terceiro, porque o payload nem possui esse campo.
-- ============================================================================
do $$
declare
  v_eval uuid;
  v_part_c1 uuid;
  v_part_c4 uuid;
  v_notas_5 jsonb;
  v_c4_antes int;
  v_c4_depois int;
begin
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id = 'd6c00000-0000-0000-0000-0000000000c2'
     and status <> 'CANCELADA'
   order by created_at limit 1;

  select id into v_part_c1 from public.evaluation_participants
   where evaluation_id = v_eval and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c1';
  select id into v_part_c4 from public.evaluation_participants
   where evaluation_id = v_eval and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c4';

  if v_part_c1 is null or v_part_c4 is null then
    raise exception '[FAIL] cenario sem ocorrencias esperadas (c1/c4)';
  end if;

  select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 5))
    into v_notas_5
    from public.evaluation_config_subcriteria sc
   where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1';

  select coalesce(sum(nota), 0)::int into v_c4_antes
    from public.evaluation_scores where participant_id = v_part_c4;
  if v_c4_antes = 0 then
    raise exception '[FAIL] cenario invalido: ocorrencia de terceiro (c4) sem notas';
  end if;

  -- (1) O ator a3 (vinculado a c1) grava as PRÓPRIAS notas.
  perform public.evaluation_gravar_notas(
    v_eval, v_notas_5, 'd6b00000-0000-0000-0000-0000000000a3');

  -- (2) A ocorrência de TERCEIRO permanece intacta (prova de isolamento).
  select coalesce(sum(nota), 0)::int into v_c4_depois
    from public.evaluation_scores where participant_id = v_part_c4;
  if v_c4_depois <> v_c4_antes then
    raise exception '[FAIL] IDOR: gravacao do ator alterou a ocorrencia de terceiro (c4)';
  end if;

  -- (3) As notas estão na ocorrência DO ATOR e com a autoria soberana dele.
  if not exists (
    select 1 from public.evaluation_scores sc
     where sc.evaluation_id = v_eval
       and sc.participant_id = v_part_c1
       and sc.nota = 5
       and sc.autor_user_profile_id = 'd6b00000-0000-0000-0000-0000000000a3'
  ) then
    raise exception '[FAIL] o ator nao gravou as PROPRIA notas com sua autoria';
  end if;

  -- (4) Comentário: com escopo válido, vai para a ocorrência do ATOR (c1) e
  --     nunca para a de terceiro (c4).
  perform public.evaluation_gravar_comentario(
    v_eval, 'FINAL', null,
    'Comentario final do proprio ator (IDOR).',
    'd6b00000-0000-0000-0000-0000000000a3');

  if exists (
    select 1 from public.evaluation_comments cm
     where cm.evaluation_id = v_eval
       and cm.participant_id = v_part_c4
       and cm.escopo = 'FINAL'
       and cm.texto like '%proprio ator%'
  ) then
    raise exception '[FAIL] IDOR: comentario do ator gravado na ocorrencia de terceiro (c4)';
  end if;
  if not exists (
    select 1 from public.evaluation_comments cm
     where cm.evaluation_id = v_eval
       and cm.participant_id = v_part_c1
       and cm.escopo = 'FINAL'
       and cm.texto like '%proprio ator%'
  ) then
    raise exception '[FAIL] comentario do proprio ator nao foi gravado na sua ocorrencia';
  end if;

  raise notice '[PASS] IDOR: notas e comentario caem SEMPRE na ocorrencia do ator (terceiro intacto)';
end $$;

do $$
declare
  v_eval uuid;
  v_part_c4 uuid;
  v_notas_4 jsonb;
begin
  -- Ator do COLEGIADO (a5, vinculado a c4 no cenário): grava nas PRÓPRIAS notas.
  -- O papel efetivo (e a proibição de escrever "como outro papel") é decidido
  -- pelo Policy Engine na fronteira; no banco, o limite é a ocorrência do ator.
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id = 'd6c00000-0000-0000-0000-0000000000c2'
     and status <> 'CANCELADA'
   order by created_at limit 1;

  select id into v_part_c4 from public.evaluation_participants
   where evaluation_id = v_eval and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c4';

  select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 3))
    into v_notas_4
    from public.evaluation_config_subcriteria sc
   where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1';

  perform public.evaluation_gravar_notas(
    v_eval, v_notas_4, 'd6b00000-0000-0000-0000-0000000000a5');

  -- Nenhuma nota do ator do colegiado escapou para outra ocorrência.
  if exists (
    select 1 from public.evaluation_scores sc
     where sc.evaluation_id = v_eval
       and sc.nota = 3
       and sc.participant_id <> v_part_c4
  ) then
    raise exception '[FAIL] IDOR: notas do colegiado alcancaram ocorrencia de terceiro';
  end if;
  -- E nenhuma nota de terceiro recebeu a autoria dele.
  if exists (
    select 1 from public.evaluation_scores sc
     where sc.evaluation_id = v_eval
       and sc.participant_id <> v_part_c4
       and sc.autor_user_profile_id = 'd6b00000-0000-0000-0000-0000000000a5'
  ) then
    raise exception '[FAIL] IDOR: autoria do colegiado em ocorrencia de terceiro';
  end if;

  raise notice '[PASS] IDOR: ator do colegiado grava somente na propria ocorrencia';
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

  -- Ator SEM ocorrência vigente (a1, vinculado ao AVALIADO) não grava nada.
  begin
    perform public.evaluation_gravar_notas(
      v_eval, '[]'::jsonb, 'd6b00000-0000-0000-0000-0000000000a1');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] ator sem ocorrencia vigente gravou notas';
  end if;

  v_ok := false;
  begin
    perform public.evaluation_gravar_comentario(
      v_eval, 'FINAL', null, 'tentativa', 'd6b00000-0000-0000-0000-0000000000a1');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] ator sem ocorrencia vigente gravou comentario';
  end if;

  -- Cross-tenant continua impossível.
  v_ok := false;
  begin
    perform public.evaluation_gravar_notas(
      v_eval,
      (select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 5))
         from public.evaluation_config_subcriteria sc
        where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1'),
      'd6b00000-0000-0000-0000-0000000000a2');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] ator de outro tenant gravou notas (D27 violado)';
  end if;

  raise notice '[PASS] IDOR: gravacao recusada para ator sem ocorrencia e para ator de outro tenant';
end $$;

do $$
declare
  v_n int;
  v_old int;
begin
  -- A assinatura ANTIGA (com participant_id) deve ter sido REMOVIDA: sem ela,
  -- nenhum caminho do browser consegue escolher a ocorrência.
  select count(*) into v_old from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'evaluation_gravar_notas'
     and pg_get_function_identity_arguments(p.oid) like '%participant_id%';
  if v_old <> 0 then
    raise exception '[FAIL] assinatura antiga com participant_id ainda existe (%)', v_old;
  end if;

  select count(*) into v_n from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'evaluation_gravar_notas';
  if v_n <> 1 then
    raise exception '[FAIL] evaluation_gravar_notas deveria ter exatamente 1 assinatura (%)', v_n;
  end if;

  select count(*) into v_old from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'evaluation_gravar_comentario'
     and pg_get_function_identity_arguments(p.oid) like '%participant_id%';
  if v_old <> 0 then
    raise exception '[FAIL] assinatura antiga com participant_id ainda existe (%)', v_old;
  end if;

  select count(*) into v_n from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'evaluation_gravar_comentario';
  if v_n <> 1 then
    raise exception '[FAIL] evaluation_gravar_comentario deveria ter exatamente 1 assinatura (%)', v_n;
  end if;

  raise notice '[PASS] IDOR: assinaturas antigas com participant_id removidas (1 assinatura cada)';
end $$;

do $$
declare
  v_ok boolean := false;
  v_eval uuid;
  v_notas_5 jsonb;
begin
  -- Ocorrência ENCERRADA (valid_to no passado) não pode ser usada: mesmo com o
  -- ator correto, a resolução server-side não encontra ocorrência vigente.
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id = 'd6c00000-0000-0000-0000-0000000000c2'
     and status <> 'CANCELADA'
   order by created_at limit 1;

  select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 5))
    into v_notas_5
    from public.evaluation_config_subcriteria sc
   where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1';

  update public.evaluation_participants
     set valid_from = now() - interval '10 days',
         valid_to = now() - interval '1 day',
         status = 'ended'
   where evaluation_id = v_eval
     and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c1';

  begin
    perform public.evaluation_gravar_notas(
      v_eval, v_notas_5, 'd6b00000-0000-0000-0000-0000000000a3');
  exception when raise_exception then v_ok := true;
  end;

  -- Restaura a vigência para não interferir nas verificações seguintes.
  update public.evaluation_participants
     set valid_to = null,
         status = 'active'
   where evaluation_id = v_eval
     and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c1';

  if not v_ok then
    raise exception '[FAIL] ocorrencia ENCERRADA aceitou gravacao';
  end if;
  raise notice '[PASS] IDOR: ocorrencia encerrada (fora da vigencia) nao aceita gravacao';
end $$;

do $$
declare
  v_ok boolean := false;
  v_eval uuid;
  v_notas_5 jsonb;
  v_media_antes numeric(12,8);
  v_media_depois numeric(12,8);
begin
  -- (6) OCORRÊNCIA AMBÍGUA: o colaborador c3 acumula DUAS ocorrências vigentes
  --     (COLEGIADO e GESTAO_DIRETA). A resolução soberana recusa em vez de
  --     escolher arbitrariamente — nenhuma gravação acontece.
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id = 'd6c00000-0000-0000-0000-0000000000c2'
     and status <> 'CANCELADA'
   order by created_at limit 1;

  select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 5))
    into v_notas_5
    from public.evaluation_config_subcriteria sc
   where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1';

  select nota_media into v_media_antes from public.evaluations where id = v_eval;

  -- Reabre a ocorrência de GESTAO_DIRETA (encerrada pelo cenário) para criar a
  -- ambiguidade de forma controlada.
  update public.evaluation_participants
     set valid_from = now() - interval '10 days',
         valid_to = null,
         status = 'active'
   where evaluation_id = v_eval
     and role_type = 'GESTAO_DIRETA';

  begin
    perform public.evaluation_gravar_notas(
      v_eval, v_notas_5, 'd6b00000-0000-0000-0000-0000000000a4');
  exception when raise_exception then v_ok := true;
  end;

  -- Restaura o estado do cenário (GESTAO_DIRETA encerrada).
  update public.evaluation_participants
     set valid_to = now() - interval '1 day',
         status = 'ended'
   where evaluation_id = v_eval
     and role_type = 'GESTAO_DIRETA';

  if not v_ok then
    raise exception '[FAIL] ocorrencia AMBIGUA (2 vigentes) aceitou gravacao';
  end if;

  -- (10) O CÁLCULO OFICIAL não é alterado por tentativa recusada.
  select nota_media into v_media_depois from public.evaluations where id = v_eval;
  if v_media_depois <> v_media_antes then
    raise exception '[FAIL] tentativa IDOR alterou o calculo oficial (% -> %)',
      v_media_antes, v_media_depois;
  end if;

  raise notice '[PASS] IDOR: ocorrencia ambigua recusada e calculo oficial inalterado';
end $$;

-- ============================================================================
-- 4) Superfície fechada: EXECUTE somente service_role
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
-- 5) Limpeza dos atores sintéticos criados por esta validação
-- ----------------------------------------------------------------------------
-- Os atores a3/a4/a5 do CENÁRIO permanecem (o cenário é reaplicado a cada
-- execução). Esta validação não cria novos atores; apenas garante que nenhum
-- resíduo de execuções anteriores permaneça quando o cenário é reaplicado.
-- ============================================================================
do $$
declare
  v_residuo int;
begin
  select count(*) into v_residuo
    from public.user_profiles
   where id::text like 'd6b00000%'
     and id not in ('d6b00000-0000-0000-0000-0000000000a1',
                    'd6b00000-0000-0000-0000-0000000000a2',
                    'd6b00000-0000-0000-0000-0000000000a3',
                    'd6b00000-0000-0000-0000-0000000000a4',
                    'd6b00000-0000-0000-0000-0000000000a5');
  if v_residuo <> 0 then
    raise exception '[FAIL] residuo de atores sinteticos desta validacao (%)', v_residuo;
  end if;
  raise notice '[PASS] nenhum ator residual criado por esta validacao';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-06 (cutover): todas as verificacoes passaram (resolucao de ciclo + leitura da propria ocorrencia + anti-IDOR + superficie fechada).';
end $$;
