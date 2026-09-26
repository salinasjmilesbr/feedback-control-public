-- F6 / Issue #366 — contrato temporal estrutural.
-- Migration aditiva: a migration F5-08 histórica não é reescrita.
--
-- Os quatro RPCs são redefinidos a partir do contrato já instalado. A entrada
-- continua sendo timestamptz, mas a vigência estrutural é normalizada para o
-- início do dia civil UTC. A guarda de segunda transição ocorre depois do
-- advisory lock e antes de qualquer mutação ou evento.

create or replace function public.f6_vigencia_civil_utc(p_vigencia timestamptz)
returns timestamptz
language sql
immutable
strict
set search_path = public
as $$
  select date_trunc('day', p_vigencia at time zone 'UTC') at time zone 'UTC'
$$;

do $$
declare
  v_name text;
  v_signature text;
  v_source text;
  v_guard text;
  v_norm_marker text := '  p_vigencia := public.f6_vigencia_civil_utc(p_vigencia);';
  v_lock_marker text;
  v_guard_count integer;
  v_lock_count integer;
  v_norm_count integer;
  v_lock_pos integer;
  v_guard_pos integer;
  v_dml_pos integer;
  v_lock text := '  perform pg_advisory_xact_lock(hashtext(''position_reporting_lines:'' || ';
begin
  foreach v_name in array array['estrutura_ocupacao_definir', 'estrutura_ocupacao_encerrar',
                                'estrutura_reporting_definir', 'estrutura_reporting_encerrar'] loop
    select pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid)
      into v_signature, v_source
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = v_name
     order by p.oid desc
     limit 1;

    if v_source is null then
      raise exception 'F6_366: RPC % ausente', v_name;
    end if;

    if (length(v_source) - length(replace(v_source,
        '  if p_vigencia is null then' || chr(10) ||
        '    raise exception ''F5_07_INVALID_INPUT: vigencia obrigatoria'';' || chr(10) ||
        '  end if;', ''))) /
       length('  if p_vigencia is null then' || chr(10) ||
              '    raise exception ''F5_07_INVALID_INPUT: vigencia obrigatoria'';' || chr(10) ||
              '  end if;') <> 1 then
      raise exception 'F6_366: marcador de normalizacao ausente ou ambiguo em %', v_name;
    end if;

    v_source := replace(v_source,
      '  if p_vigencia is null then' || chr(10) ||
      '    raise exception ''F5_07_INVALID_INPUT: vigencia obrigatoria'';' || chr(10) ||
      '  end if;',
      '  if p_vigencia is null then' || chr(10) ||
      '    raise exception ''F5_07_INVALID_INPUT: vigencia obrigatoria'';' || chr(10) ||
      '  end if;' || chr(10) ||
      '  p_vigencia := public.f6_vigencia_civil_utc(p_vigencia);');

    v_norm_count := (length(v_source) - length(replace(v_source, v_norm_marker, ''))) /
                    length(v_norm_marker);
    if v_norm_count <> 1 then
      raise exception 'F6_366: normalizacao UTC nao aplicada exatamente uma vez em %', v_name;
    end if;

    if v_name = 'estrutura_ocupacao_definir' then
      v_guard :=
        '  if exists (' || chr(10) ||
        '    select 1 from public.collaborator_events e' || chr(10) ||
        '     where e.organization_id = p_organization_id' || chr(10) ||
        '       and e.collaborator_id = p_collaborator_id' || chr(10) ||
        '       and e.position_id = p_position_id' || chr(10) ||
        '       and e.event_type in (''OCUPACAO_INICIADA'', ''OCUPACAO_ENCERRADA'')' || chr(10) ||
        '       and e.effective_date = p_vigencia' || chr(10) ||
        '  ) then' || chr(10) ||
        '    raise exception ''F5_07_CONFLICT: segunda transicao de ocupacao na mesma relacao e data civil'';' || chr(10) ||
        '  end if;';
    elsif v_name like 'estrutura_reporting_%' then
      v_guard :=
        '  if exists (' || chr(10) ||
        '    select 1 from public.collaborator_events e' || chr(10) ||
        '     where e.organization_id = p_organization_id' || chr(10) ||
        '       and e.position_id = p_subordinate_position_id' || chr(10) ||
        '       and e.event_type in (''REPORTING_LINE_INICIADA'', ''REPORTING_LINE_ENCERRADA'')' || chr(10) ||
        '       and e.effective_date = p_vigencia' || chr(10) ||
        '  ) then' || chr(10) ||
        '    raise exception ''F5_07_CONFLICT: segunda transicao de reporting line na mesma relacao e data civil'';' || chr(10) ||
        '  end if;';
    else
      v_guard := null;
    end if;

    if v_guard is not null then
      if v_name = 'estrutura_ocupacao_definir' or v_name = 'estrutura_ocupacao_encerrar' then
        v_lock_marker := v_lock || 'v_org::text));';
      else
        v_lock_marker := v_lock || 'p_organization_id::text));';
      end if;

      v_lock_count := (length(v_source) - length(replace(v_source, v_lock_marker, ''))) /
                      length(v_lock_marker);
      if v_lock_count <> 1 then
        raise exception 'F6_366: marcador de lock ausente ou ambiguo em %', v_name;
      end if;

      v_source := replace(v_source, v_lock_marker, v_lock_marker || chr(10) || v_guard);
      v_guard_count := (length(v_source) - length(replace(v_source, v_guard, ''))) /
                       length(v_guard);
      if v_guard_count <> 1 then
        raise exception 'F6_366: guarda temporal nao inserida exatamente uma vez em %', v_name;
      end if;

      v_lock_pos := position(v_lock_marker in v_source);
      v_guard_pos := position(v_guard in v_source);
      v_dml_pos := least(nullif(position('  update public.' in v_source), 0),
                         nullif(position('  insert into public.' in v_source), 0));
      if v_dml_pos is null or not (v_lock_pos < v_guard_pos and v_guard_pos < v_dml_pos) then
        raise exception 'F6_366: ordem lock -> guarda -> DML invalida em %', v_name;
      end if;
    else
      v_lock_marker := v_lock || 'v_org::text));';
      v_lock_count := (length(v_source) - length(replace(v_source, v_lock_marker, ''))) /
                      length(v_lock_marker);
      if v_lock_count <> 1 then
        raise exception 'F6_366: lock de occupation encerrar ausente ou ambiguo';
      end if;
    end if;

    execute v_source;
  end loop;
end;
$$;

comment on function public.f6_vigencia_civil_utc(timestamptz) is
  'Issue #366: normaliza vigencia estrutural civil para 00:00:00Z.';
