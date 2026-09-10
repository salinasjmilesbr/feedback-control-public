-- ============================================================================
-- F5-06 (Issue #103): cenário sintético de validação — avaliações no PostgreSQL
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Prepara, de forma determinística e idempotente:
--   - 2 organizações sintéticas (Alfa/Beta F5-06);
--   - perfis/memberships sintéticos: ATOR (membership ativa em Alfa);
--   - 4 colaboradores em Alfa (gestor de cadeia, avaliado, 2 membros de colegiado);
--   - estrutura F3 mínima (função, unidades, posições, reporting line, occupations)
--     porque o SNAPSHOT de participantes da F5-06 é derivado SERVER-SIDE das
--     fontes soberanas F3-07/F3-08 (nunca do payload do chamador);
--   - snapshots F3-08 do ciclo (avaliado + gestor) e responsabilidades F3-09;
--   - ciclo ATIVO com configuração baseline (evaluation_config_bootstrap);
--   - avaliação com participantes derivados (GESTAO_CADEIA + 2 COLEGIADO)
--     e notas que produzem nota_media = 3.5 (colegiado como UMA parcela).
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
delete from public.cycle_evaluation_responsibilities where organization_id::text like 'd6a00000%';
delete from public.evaluation_succession_events where organization_id::text like 'd6a00000%';
delete from public.collegiate_cycle_snapshot_members where organization_id::text like 'd6a00000%';
delete from public.collegiate_cycle_snapshot_positions where organization_id::text like 'd6a00000%';
delete from public.collegiate_cycle_snapshots where organization_id::text like 'd6a00000%';
delete from public.occupations where organization_id::text like 'd6a00000%';
delete from public.position_reporting_lines where organization_id::text like 'd6a00000%';
delete from public.organizational_positions where organization_id::text like 'd6a00000%';
delete from public.organizational_unit_parent_periods where organization_id::text like 'd6a00000%';
delete from public.organizational_units where organization_id::text like 'd6a00000%';
delete from public.collaborator_status_periods
 where collaborator_id in (
   select id from public.collaborators where organization_id::text like 'd6a00000%'
 );
delete from public.job_roles where organization_id::text like 'd6a00000%';
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

-- Colaboradores (identidade interna = UUID; nunca matrícula)
insert into public.collaborators (id, organization_id) values
  ('d6c00000-0000-0000-0000-0000000000c1','d6a00000-0000-0000-0000-0000000000a1'),
  ('d6c00000-0000-0000-0000-0000000000c2','d6a00000-0000-0000-0000-0000000000a1'),
  ('d6c00000-0000-0000-0000-0000000000c3','d6a00000-0000-0000-0000-0000000000a1'),
  ('d6c00000-0000-0000-0000-0000000000c4','d6a00000-0000-0000-0000-0000000000a1');

-- Lifecycle vigente (F3-01): periodo ACTIVE aberto por colaborador.
insert into public.collaborator_status_periods
  (collaborator_id, status, valid_from) values
  ('d6c00000-0000-0000-0000-0000000000c1','active','2025-01-01T00:00:00Z'),
  ('d6c00000-0000-0000-0000-0000000000c2','active','2025-01-01T00:00:00Z'),
  ('d6c00000-0000-0000-0000-0000000000c3','active','2025-01-01T00:00:00Z'),
  ('d6c00000-0000-0000-0000-0000000000c4','active','2025-01-01T00:00:00Z');

-- Vínculo do avaliado com a membership do ATOR (para a leitura de transparência)
insert into public.membership_collaborator_links
  (id, membership_id, organization_id, collaborator_id, status)
values
  ('d6e00000-0000-0000-0000-0000000000a1','d6d00000-0000-0000-0000-0000000000a1',
   'd6a00000-0000-0000-0000-0000000000a1','d6c00000-0000-0000-0000-0000000000c2','active');

-- ----------------------------------------------------------------------------
-- Estrutura F3 (fonte soberana do snapshot de participantes — D16/D17)
--   c1 = responsável da CADEIA (posição mais alta ocupada)
--   c3 = gestor formal DIRETO do avaliado
--   c4 = membro do colegiado (via snapshot F3-08)
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, status) values
  ('d6c00000-0000-0000-0000-0000000000e1','d6a00000-0000-0000-0000-0000000000a1','Funcao Sintetica F5-06','active');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('d6e00000-0000-0000-0000-0000000000f1','d6a00000-0000-0000-0000-0000000000a1',
   'Unidade Sintetica F5-06', '2025-01-01T00:00:00Z');

insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, valid_from) values
  ('d6e00000-0000-0000-0000-0000000000f1','d6a00000-0000-0000-0000-0000000000a1',
   'd6e00000-0000-0000-0000-0000000000f1','d6c00000-0000-0000-0000-0000000000e1','2025-01-01T00:00:00Z'),
  ('d6e00000-0000-0000-0000-0000000000f2','d6a00000-0000-0000-0000-0000000000a1',
   'd6e00000-0000-0000-0000-0000000000f1','d6c00000-0000-0000-0000-0000000000e1','2025-01-01T00:00:00Z'),
  ('d6e00000-0000-0000-0000-0000000000f3','d6a00000-0000-0000-0000-0000000000a1',
   'd6e00000-0000-0000-0000-0000000000f1','d6c00000-0000-0000-0000-0000000000e1','2025-01-01T00:00:00Z');

insert into public.position_reporting_lines
  (organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('d6a00000-0000-0000-0000-0000000000a1','d6e00000-0000-0000-0000-0000000000f3',
   'd6e00000-0000-0000-0000-0000000000f2','estrutura sintetica','2025-01-01T00:00:00Z'),
  ('d6a00000-0000-0000-0000-0000000000a1','d6e00000-0000-0000-0000-0000000000f2',
   'd6e00000-0000-0000-0000-0000000000f1','estrutura sintetica','2025-01-01T00:00:00Z');

insert into public.occupations
  (organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to) values
  ('d6a00000-0000-0000-0000-0000000000a1','d6c00000-0000-0000-0000-0000000000c2',
   'd6e00000-0000-0000-0000-0000000000f3','ocupacao sintetica','2025-01-01T00:00:00Z', null),
  ('d6a00000-0000-0000-0000-0000000000a1','d6c00000-0000-0000-0000-0000000000c3',
   'd6e00000-0000-0000-0000-0000000000f2','ocupacao sintetica','2025-01-01T00:00:00Z', null),
  ('d6a00000-0000-0000-0000-0000000000a1','d6c00000-0000-0000-0000-0000000000c1',
   'd6e00000-0000-0000-0000-0000000000f1','ocupacao sintetica','2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Snapshots F3-08 do ciclo (congelam colegiado e data de referência)
-- ----------------------------------------------------------------------------
insert into public.collegiate_cycle_snapshots
  (id, organization_id, ano, ciclo, collaborator_id, reference_date) values
  ('d6f00000-0000-0000-0000-0000000000b1','d6a00000-0000-0000-0000-0000000000a1',
   2026, 1, 'd6c00000-0000-0000-0000-0000000000c2','2025-01-01T00:00:00Z'),
  ('d6f00000-0000-0000-0000-0000000000b2','d6a00000-0000-0000-0000-0000000000a1',
   2026, 1, 'd6c00000-0000-0000-0000-0000000000c3','2025-01-01T00:00:00Z');

-- Snapshots dos demais avaliados exercitados pelo validador (c1 e c3).
insert into public.collegiate_cycle_snapshots
  (id, organization_id, ano, ciclo, collaborator_id, reference_date) values
  ('d6f00000-0000-0000-0000-0000000000b3','d6a00000-0000-0000-0000-0000000000a1',
   2026, 1, 'd6c00000-0000-0000-0000-0000000000c1','2025-01-01T00:00:00Z');

insert into public.collegiate_cycle_snapshot_positions
  (id, snapshot_id, organization_id, position_id, superior_position_id, superior_collaborator_id) values
  ('d6f00000-0000-0000-0000-0000000000c1','d6f00000-0000-0000-0000-0000000000b1',
   'd6a00000-0000-0000-0000-0000000000a1','d6e00000-0000-0000-0000-0000000000f3',
   'd6e00000-0000-0000-0000-0000000000f2','d6c00000-0000-0000-0000-0000000000c3'),
  ('d6f00000-0000-0000-0000-0000000000c2','d6f00000-0000-0000-0000-0000000000b2',
   'd6a00000-0000-0000-0000-0000000000a1','d6e00000-0000-0000-0000-0000000000f2',
   'd6e00000-0000-0000-0000-0000000000f1','d6c00000-0000-0000-0000-0000000000c1'),
  ('d6f00000-0000-0000-0000-0000000000c3','d6f00000-0000-0000-0000-0000000000b3',
   'd6a00000-0000-0000-0000-0000000000a1','d6e00000-0000-0000-0000-0000000000f1',
   null, null);

insert into public.collegiate_cycle_snapshot_members
  (id, snapshot_id, organization_id, member_collaborator_id) values
  ('d6f00000-0000-0000-0000-0000000000d1','d6f00000-0000-0000-0000-0000000000b1',
   'd6a00000-0000-0000-0000-0000000000a1','d6c00000-0000-0000-0000-0000000000c4'),
  ('d6f00000-0000-0000-0000-0000000000d2','d6f00000-0000-0000-0000-0000000000b1',
   'd6a00000-0000-0000-0000-0000000000a1','d6c00000-0000-0000-0000-0000000000c3');

-- Responsabilidades avaliativas F3-09 (titular por posição)
insert into public.cycle_evaluation_responsibilities
  (id, organization_id, snapshot_id, position_id, responsible_collaborator_id, valid_from) values
  ('d6f00000-0000-0000-0000-0000000000e1','d6a00000-0000-0000-0000-0000000000a1',
   'd6f00000-0000-0000-0000-0000000000b1','d6e00000-0000-0000-0000-0000000000f3',
   'd6c00000-0000-0000-0000-0000000000c3','2025-01-01T00:00:00Z'),
  ('d6f00000-0000-0000-0000-0000000000e2','d6a00000-0000-0000-0000-0000000000a1',
   'd6f00000-0000-0000-0000-0000000000b2','d6e00000-0000-0000-0000-0000000000f2',
   'd6c00000-0000-0000-0000-0000000000c1','2025-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Ciclo ATIVO + configuração baseline versionada
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim)
values
  ('d6f00000-0000-0000-0000-0000000000a1','d6a00000-0000-0000-0000-0000000000a1',
   2026, 1, 'ATIVO', date '2026-01-01', date '2026-06-30');

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

-- ----------------------------------------------------------------------------
-- Avaliação do avaliado c2 com SNAPSHOT SOBERANO de participantes.
-- Nenhum participante vem do payload: a RPC deriva das fontes F3.
-- Parcelas: GESTAO_CADEIA (c1) = 4 ; COLEGIADO (c4) = 2  => sub = 3.0
-- (o cenário usa notas 4/2 para deixar o coeficiente explícito; o validador
-- de colegiado agregado ajusta as notas do colegiado para 2 e 4.)
-- ----------------------------------------------------------------------------
do $$
declare
  v_eval uuid;
  v_part_cadeia uuid;
  v_part_direta uuid;
  v_part_col_2 uuid;
  v_part_col_4 uuid;
  v_notas_4 jsonb;
  v_notas_2 jsonb;
  v_qtd int;
begin
  v_eval := public.evaluation_criar(
    'd6a00000-0000-0000-0000-0000000000a1',
    'd6f00000-0000-0000-0000-0000000000a1',
    'd6c00000-0000-0000-0000-0000000000c2',
    'd6b00000-0000-0000-0000-0000000000a1'
  );

  select count(*) into v_qtd from public.evaluation_participants
   where evaluation_id = v_eval;
  if v_qtd < 2 then
    raise exception 'Cenario F5-06: snapshot derivado incompleto (% participantes)', v_qtd;
  end if;

  if not exists (
    select 1 from public.evaluation_participants
     where evaluation_id = v_eval and role_type = 'GESTAO_CADEIA'
       and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c1'
  ) then
    raise exception 'Cenario F5-06: GESTAO_CADEIA nao derivada da cadeia F3';
  end if;

  select count(*) into v_qtd from public.evaluation_participants
   where evaluation_id = v_eval and role_type = 'COLEGIADO';
  if v_qtd <> 2 then
    raise exception 'Cenario F5-06: COLEGIADO nao derivado do snapshot F3-08 (%)', v_qtd;
  end if;

  select id into v_part_cadeia from public.evaluation_participants
   where evaluation_id = v_eval and role_type = 'GESTAO_CADEIA';

  -- Responsabilidade DIRETA (derivada do gestor formal direto): tambem
  -- contribui para o score, portanto precisa das notas do subcriterio.
  select id into v_part_direta from public.evaluation_participants
   where evaluation_id = v_eval and role_type = 'GESTAO_DIRETA';

  -- Feedback final obrigatorio do papel de cadeia (requires_final_comment),
  -- de ocorrencia VIGENTE: sem ele a conclusao normal nao passa na completude.
  perform public.evaluation_gravar_comentario(
    v_eval, v_part_cadeia, 'FINAL', null,
    'Feedback final sintetico do responsavel de cadeia.',
    'd6b00000-0000-0000-0000-0000000000a1');
  if v_part_direta is not null then
    perform public.evaluation_gravar_comentario(
      v_eval, v_part_direta, 'FINAL', null,
      'Feedback final sintetico do gestor direto.',
      'd6b00000-0000-0000-0000-0000000000a1');
  end if;

  select id into v_part_col_2 from public.evaluation_participants
   where evaluation_id = v_eval and role_type = 'COLEGIADO'
     and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c3';
  select id into v_part_col_4 from public.evaluation_participants
   where evaluation_id = v_eval and role_type = 'COLEGIADO'
     and collaborator_id = 'd6c00000-0000-0000-0000-0000000000c4';

  select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 4))
    into v_notas_4
    from public.evaluation_config_subcriteria sc
   where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1';
  select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 2))
    into v_notas_2
    from public.evaluation_config_subcriteria sc
   where sc.organization_id = 'd6a00000-0000-0000-0000-0000000000a1';

  -- Parcelas: GESTAO_CADEIA (c1) = 4 ; GESTAO_DIRETA (c3) = 4 ;
  -- COLEGIADO = media(2, 4) = 3  => subcriterio = (4 + 4 + 3) / 3 = 11/3.
  -- O colegiado e UMA parcela (D25): se cada membro pesasse individualmente
  -- seriam 4 parcelas e o resultado mudaria.
  perform public.evaluation_gravar_notas(v_eval, v_part_cadeia, v_notas_4,
    'd6b00000-0000-0000-0000-0000000000a1');
  perform public.evaluation_gravar_notas(v_eval, v_part_col_2, v_notas_2,
    'd6b00000-0000-0000-0000-0000000000a1');
  perform public.evaluation_gravar_notas(v_eval, v_part_col_4, v_notas_4,
    'd6b00000-0000-0000-0000-0000000000a1');
  if v_part_direta is not null then
    perform public.evaluation_gravar_notas(v_eval, v_part_direta, v_notas_4,
      'd6b00000-0000-0000-0000-0000000000a1');
  end if;

  -- feedback final obrigatório do papel de cadeia (requires_final_comment = true)
  perform public.evaluation_gravar_comentario(
    v_eval, v_part_cadeia, 'FINAL', null, 'Feedback final sintetico do gestor.',
    'd6b00000-0000-0000-0000-0000000000a1');
end $$;
