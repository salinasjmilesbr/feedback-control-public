-- ============================================================================
-- F5-11 P5.2 (Issues #252/#253) — AUTORIDADE ADMINISTRATIVA E A ROLE `admin`
-- ============================================================================
--
-- DEFEITO CORRIGIDO (detectado pelo pipeline completo depois da P5.1, no
-- validador da F5-07: `[FAIL] ator funcional reconhecido como administrador`):
-- `public.usuario_eh_administrador` (20260910020000_f5_04_admin_rpc_functions.sql
-- :39-63) classificava o ator como ADMINISTRADOR quando existia QUALQUER
-- assignment ativo de QUALQUER role de sistema (`r.is_system = true`), quando o
-- contrato documentado da propria funcao (:34) e a role `admin`
-- (identificador canonico `name = 'admin' and is_system = true`, UUID
-- c0000000-0000-4000-8000-0000000000f1, catalogo 20260908000001:69-70).
--
-- IMPACTO (escalada de privilegio amplificada pela P5.1): a P5.1 passou a
-- provisionar AUTOMATICAMENTE `observacoes_avaliado` (is_system = true) a toda
-- membership elegivel. Como `usuario_eh_administrador` e o UNICO gate de
-- `conceder_acesso_role_rpc` (20260910020000:123) e de `revogar_acesso_role_rpc`
-- (:191), todo avaliado elegivel passaria a conceder/revogar roles de acesso do
-- tenant (membership.manage/access_role.manage auto-servidos) — exatamente o
-- que D15/D16(Q3) proibem ("a autoridade administrativa nao e capability
-- auto-servida").
--
-- DECISAO (orquestrador): a autoridade administrativa exige a role de sistema
-- `admin` NOMINAL. Roles de sistema de dominio (`observacoes_gestor`,
-- `observacoes_avaliado`, `metas_dono`, `metas_aprovador`) NAO conferem
-- autoridade administrativa. Todo o restante da funcao e PRESERVADO:
-- assinatura, `returns boolean`, `language sql`, `stable`, `security invoker`,
-- `set search_path = public`, e o comportamento de tenant/membership/status.
-- `access_roles` NAO possui coluna `code`; o identificador e `name` (unique por
-- `(organization_id, name)`), combinado com `is_system = true`.
--
-- Esta migration e ADITIVA: nao altera a migration da P5.1, o role novo, os
-- triggers nem o backfill, e nao mexe em grants/revokes (o `create or replace`
-- preserva a ACL vigente — EXECUTE somente `service_role`).
-- ============================================================================

create or replace function public.usuario_eh_administrador(
  p_user_profile_id uuid,
  p_organization_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $fn$
  select exists (
    select 1
      from public.user_organization_memberships m
      join public.membership_access_role_assignments a
        on a.membership_id = m.id
       and a.status = 'active'
      join public.access_roles r
        on r.id = a.access_role_id
       and r.is_system = true
       and r.status = 'active'
       and r.name = 'admin'
     where m.user_profile_id = p_user_profile_id
       and m.organization_id = p_organization_id
       and m.status = 'active'
  );
$fn$;

comment on function public.usuario_eh_administrador(uuid, uuid) is
  'F5-04 (D16/Q3) + F5-11 P5.2: autoridade administrativa restrita a role de '
  'sistema `admin` (name = ''admin'' e is_system = true), validada server-side '
  'no tenant — membership ativa + atribuicao ativa. Roles de sistema de dominio '
  '(observacoes_gestor, observacoes_avaliado, metas_dono, metas_aprovador) NAO '
  'conferem autoridade administrativa. membership.manage/access_role.manage NAO '
  'sao concediveis por role (D15); a autoridade administrativa nao e capability '
  'auto-servida. SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- Guarda fail-closed da propria migration: o identificador nominal da role
-- administrativa deve existir (uma unica role de sistema `admin` ativa) e a
-- definicao resultante deve conter o discriminante por role.
-- ----------------------------------------------------------------------------
do $guarda$
declare
  v_admin_n int;
  v_def     text;
begin
  select count(*) into v_admin_n
    from public.access_roles
   where is_system = true
     and name = 'admin'
     and status = 'active';
  if v_admin_n <> 1 then
    raise exception
      'F5-11 P5.2: esperada EXATAMENTE 1 role de sistema `admin` ativa (encontradas %)', v_admin_n;
  end if;

  v_def := pg_get_functiondef('public.usuario_eh_administrador(uuid, uuid)'::regprocedure);
  if position('is_system' in v_def) = 0 or position('admin' in v_def) = 0 then
    raise exception
      'F5-11 P5.2: definicao da funcao sem o discriminante nominal da role admin';
  end if;

  raise notice
    '[PASS] F5-11 P5.2: autoridade administrativa discriminada pela role `admin` (nao por qualquer role de sistema)';
end $guarda$;
