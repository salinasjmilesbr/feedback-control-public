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

    v_source := replace(v_source,
      '  if p_vigencia is null then' || chr(10) ||
      '    raise exception ''F5_07_INVALID_INPUT: vigencia obrigatoria'';' || chr(10) ||
      '  end if;',
      '  if p_vigencia is null then' || chr(10) ||
      '    raise exception ''F5_07_INVALID_INPUT: vigencia obrigatoria'';' || chr(10) ||
      '  end if;' || chr(10) ||
      '  p_vigencia := public.f6_vigencia_civil_utc(p_vigencia);');

    if v_name like 'estrutura_ocupacao_%' then
      v_guard :=
        '  if exists (' || chr(10) ||
        '    select 1 from public.collaborator_events e' || chr(10) ||
        '     where e.organization_id = p_organization_id' || chr(10) ||
        '       and e.collaborator_id = p_collaborator_id' || chr(10) ||
        '       and e.event_type in (''OCUPACAO_INICIADA'', ''OCUPACAO_ENCERRADA'')' || chr(10) ||
        '       and e.effective_date = p_vigencia' || chr(10) ||
        '  ) then' || chr(10) ||
        '    raise exception ''F5_07_CONFLICT: segunda transicao de ocupacao na mesma relacao e data civil'';' || chr(10) ||
        '  end if;';
    else
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
    end if;

    v_source := replace(v_source,
      v_lock || 'v_org::text));',
      v_lock || 'v_org::text));' || chr(10) || v_guard);
    v_source := replace(v_source,
      v_lock || 'p_organization_id::text));',
      v_lock || 'p_organization_id::text));' || chr(10) || v_guard);

    execute v_source;
  end loop;
end;
$$;

comment on function public.f6_vigencia_civil_utc(timestamptz) is
  'Issue #366: normaliza vigencia estrutural civil para 00:00:00Z.';
