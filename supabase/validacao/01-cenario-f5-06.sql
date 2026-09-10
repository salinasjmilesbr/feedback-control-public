-- ============================================================================
-- F5-06 (Issue #103): cenário sintético de validação — avaliações no PostgreSQL
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Prepara, de forma determinística e idempotente:
--   - 2 organizações sintéticas (Alfa/Beta F5-06);
--   - perfis/memberships sintéticos: ATOR (membership ativa em Alfa);
--   - 4 colaboradores em Alfa (Gestor de cadeia, Avaliado, 2 membros de colegiado);
--   - ciclo ATIVO com configuração baseline (evaluation_config_bootstrap);
--   - avaliação com participantes (GESTAO_CADEIA + 2 COLEGIADO) e notas.
--
-- Executar como superuser local (as funções são SECURITY INVOKER e o ator é
-- verificado por perfil+membership ativos; nenhuma policy é alterada).
-- Apenas dados sintéticos; nenhum dado real.
-- ============================================================================

-- Limpeza do cenário (somente prefixo d6; ordem respeita FKs RESTRICT)
delete from public.evaluation_events where organization_id::text like 'd6a00000%';
delete from public.evaluation_pendencies where organization_id::text like 'd6a00000%';
delete from public.evaluation_aggregates where organization_id::text like 'd6a00000%';
delete from public.evaluation_comments where organization_id::text like 'd6a00000%';
delete from public.evaluation_scores where organization_id::text like 'd6a00000%';
delete from public.evaluation_participants where organization_id::text like 'd6a00000%';
delete from public.evaluations where organization_id::text like 'd6a00000%';
delete from public.evaluation_cycles where organization_id::text like 'd6a00000%';
delete from public.evaluation_config_participant_roles where organization_id::text like 'd6a00000%';
delete from public.evaluation_config_scale_bands where organization_id::text like 'd6a00000%';
delete from public.evaluation_config_subcriteria where organization_id::text like 'd6a00000%';
delete from public.evaluation_config_criteria where organization_id::text like 'd6a00000%';
delete from public.evaluation_config_versions where organization_id::text like 'd6a00000%';
delete from public.membership_collaborator_links where organization_id::text like 'd6a00000%';
delete from public.user_organization_memberships where organization_id::text like 'd6a00000%';
delete from public.collaborators where organization_id::text like 'd6a00000%';
delete from public.user_profiles where id::text like 'd6b00000%';
delete from auth.users where id::text like 'd6b00000%';
delete from public.organizations where id::text like 'd6a00000%';

-- Organizações
insert into public.organizations (id, name) values
  ('d6a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-06 Alfa'),
  ('d6a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-06 Beta');

-- auth.users + perfis
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d6b00000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-06.ator@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('d6b00000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-06.beta@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now());

insert into public.user_profiles (id, status) values
  ('d6b00000-0000-0000-0000-0000000000a1','active'),
  ('d6b00000-0000-0000-0000-0000000000a2','active');

insert into public.user_organization_memberships (id, user_profile_id, organization_id, status) values
  ('d6d00000-0000-0000-0000-0000000000a1','d6b00000-0000-0000-0000-0000000000a1','d6a00000-0000-0000-0000-0000000000a1','active'),
  ('d6d00000-0000-0000-0000-0000000000b1','d6b00000-0000-0000-0000-0000000000a2','d6a00000-0000-0000-0000-0000000000b1','active');

-- Colaboradores (identidade interna = UUID)
insert into public.collaborators (id, organization_id, status) values
  ('d6c00000-0000-0000-0000-0000000000c1','d6a00000-0000-0000-0000-0000000000a1','active'),
  ('d6c00000-0000-0000-0000-0000000000c2','d6a00000-0000-0000-0000-0000000000a1','active'),
  ('d6c00000-0000-0000-0000-0000000000c3','d6a00000-0000-0000-0000-0000000000a1','active'),
  ('d6c00000-0000-0000-0000-0000000000c4','d6a00000-0000-0000-0000-0000000000a1','active');

-- Vínculo do avaliado com a membership do ATOR (para a leitura de transparência)
insert into public.membership_collaborator_links
  (id, membership_id, organization_id, collaborator_id, status)
values
  ('d6e00000-0000-0000-0000-0000000000a1','d6d00000-0000-0000-0000-0000000000a1',
   'd6a00000-0000-0000-0000-0000000000a1','d6c00000-0000-0000-0000-0000000000c2','active');

-- Ciclo ATIVO
insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim)
values
  ('d6f00000-0000-0000-0000-0000000000a1','d6a00000-0000-0000-0000-0000000000a1',
   2026, 1, 'ATIVO', date '2026-01-01', date '2026-06-30');

-- Configuração baseline versionada (8 critérios / 25 subcritérios / escala / papéis)
do $$
declare
  v_config uuid;
begin
  v_config := public.evaluation_config_bootstrap(
    'd6a00000-0000-0000-0000-0000000000a1',
    'd6b00000-0000-0000-0000-0000000000a1'
  );
  update public.evaluation_cycles
     set config_version_id = v_config
   where id = 'd6f00000-0000-0000-0000-0000000000a1';
end $$;

-- Avaliação com snapshot de participantes (GESTAO_CADEIA + 2 COLEGIADO)
do $$
declare
  v_config uuid;
  v_eval uuid;
  v_part_gestao uuid;
  v_part_col1 uuid;
  v_part_col2 uuid;
  v_notas_4 jsonb;
  v_notas_2 jsonb;
  v_notas_4b jsonb;
begin
  select config_version_id into v_config from public.evaluation_cycles
   where id = 'd6f00000-0000-0000-0000-0000000000a1';

  v_eval := public.evaluation_criar(
    'd6a00000-0000-0000-0000-0000000000a1',
    'd6f00000-0000-0000-0000-0000000000a1',
    'd6c00000-0000-0000-0000-0000000000c2',
    v_config,
    jsonb_build_array(
      jsonb_build_object('role_type','GESTAO_CADEIA','collaborator_id','d6c00000-0000-0000-0000-0000000000c1','origem','ESTRUTURA'),
      jsonb_build_object('role_type','COLEGIADO','collaborator_id','d6c00000-0000-0000-0000-0000000000c3','origem','SNAPSHOT_CICLO'),
      jsonb_build_object('role_type','COLEGIADO','collaborator_id','d6c00000-0000-0000-0000-0000000000c4','origem','SNAPSHOT_CICLO')
    ),
    'd6b00000-0000-0000-0000-0000000000a1'
  );

  select id into v_part_gestao from public.evaluation_participants
   where evaluation_id = v_eval and role_type = 'GESTAO_CADEIA';
  select id into v_part_col1 from public.evaluation_participants
   where evaluation_id = v_eval and role_type = 'COLEGIADO'
     and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c3';
  select id into v_part_col2 from public.evaluation_participants
   where evaluation_id = v_eval and role_type = 'COLEGIADO'
     and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c4';

  -- parcelas: GESTAO_CADEIA = 4 ; COLEGIADO = média(2, 4) = 3  => sub = 3.5
  select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 4))
    into v_notas_4
    from public.evaluation_config_subcriteria sc
   where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1';
  select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 2))
    into v_notas_2
    from public.evaluation_config_subcriteria sc
   where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1';
  select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 4))
    into v_notas_4b
    from public.evaluation_config_subcriteria sc
   where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1';

  perform public.evaluation_gravar_notas(v_eval, v_part_gestao, v_notas_4, 'd6b00000-0000-0000-0000-0000000000a1');
  perform public.evaluation_gravar_notas(v_eval, v_part_col1, v_notas_2, 'd6b00000-0000-0000-0000-0000000000a1');
  perform public.evaluation_gravar_notas(v_eval, v_part_col2, v_notas_4b, 'd6b00000-0000-0000-0000-0000000000a1');

  -- feedback final obrigatório do papel de cadeia (requires_final_comment = true)
  perform public.evaluation_gravar_comentario(
    v_eval, v_part_gestao, 'FINAL', null, 'Feedback final sintetico do gestor.',
    'd6b00000-0000-0000-0000-0000000000a1');
end $$;
