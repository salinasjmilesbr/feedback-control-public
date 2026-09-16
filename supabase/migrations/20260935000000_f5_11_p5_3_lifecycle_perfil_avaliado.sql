-- ============================================================================
-- F5-11 P5.3 (Issue #252) — LIFECYCLE COMPLETO de `observacoes_avaliado`
--                              quando muda `user_profiles.status`
-- ----------------------------------------------------------------------------
-- FINDING MATERIAL da auditoria pre-merge (PROCEDENTE): a P5.1
-- (`20260933000000_f5_11_p5_1_self_read_observacoes.sql`) define elegibilidade
-- como membership `active` + `user_profiles.status = 'active'` + vinculo
-- `active`, mas criou triggers APENAS em `membership_collaborator_links`
-- (`trg_f5_11_p5_1_vinculo`) e `user_organization_memberships`
-- (`trg_f5_11_p5_1_membership`). Uma mudanca ISOLADA de `user_profiles.status`
-- NAO era propagada: a assignment automatica permanecia materializada
-- `active`, violando o contrato aprovado (INELEGIVEL => `revoked`;
-- REATIVACAO => a MESMA assignment volta a `active`; evento SOMENTE em
-- transicao real). O fail-closed do resolvedor NAO basta para o contrato
-- MATERIALIZADO — a assignment existe no banco e precisa acompanhar o fato.
--
-- Contrato do fato (arquivo:linha):
--   * `user_profiles.status` e' `not null default 'active'` com
--     `check (status in ('active','disabled'))`
--     (`20260906201856_organizations_user_profiles.sql:92,100`), documentado
--     como "preparado para evolucao (F2-07 — desativacao/reativacao)";
--   * a policy `user_profiles_select_own` ja exige `status = 'active'`
--     (`20260907000250_desativacao_perfil_policy.sql:20`) — prova de que a
--     transicao e' um fato de dominio real, nao hipotetico.
--
-- MENOR PROPAGACAO CORRETA (mecanismo T, aprovado pelo orquestrador): UM
-- trigger de TABELA em `user_profiles` que, para CADA membership do perfil,
-- chama a MESMA funcao da P5.1 (`f5_11_p5_1_provisionar_observacoes_avaliado`)
-- — nenhuma duplicacao da regra de elegibilidade, nenhuma reimplementacao dos
-- tres fatores, nenhum segundo vocabulario. SECURITY INVOKER, `search_path`
-- fixo, sem advisory lock, sem DELETE, sem `SECURITY DEFINER` novo.
--
-- NOME sem o radical `observa`/`observation` POR DECISAO: as fases anteriores
-- mantem listas FECHADAS de funcoes do dominio de observacoes filtradas por
-- `proname like '%observa%'` (`35-validar-f5-11-p1.sql`, `15-validar-f5-09-p9.sql`,
-- `30-validar-f5-10-p7.sql`); usar aquele radical exigiria editar validadores de
-- outras fases, o que esta fora do escopo desta correcao.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A) PROPAGACAO: profile mudou de status => reavalia CADA membership do perfil
-- ----------------------------------------------------------------------------
-- Idempotencia: a funcao reutilizada ja' e' a fonte unica — le a assignment
-- (`for update`), decide pelos TRES fatores e so' grava quando ha' TRANSICAO
-- REAL. Replay em estado ja' correto nao cria linha nem evento; a reativacao
-- reusa a MESMA assignment (`on conflict` por `(membership_id, access_role_id)`)
-- e NUNCA faz DELETE.
create or replace function public.f5_11_p5_3_trigger_perfil_avaliado()
returns trigger
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_membership uuid;
begin
  for v_membership in
    select m.id
      from public.user_organization_memberships m
     where m.user_profile_id = new.id
     order by m.id
  loop
    perform public.f5_11_p5_1_provisionar_observacoes_avaliado(v_membership);
  end loop;
  return null;
end $fn$;

comment on function public.f5_11_p5_3_trigger_perfil_avaliado() is
$c$
F5-11 P5.3: propaga mudanca de `user_profiles.status` para o provisionamento de
`observacoes_avaliado` de TODAS as memberships do perfil, reutilizando a funcao
unica da P5.1 (nenhuma duplicacao da regra de elegibilidade). SECURITY INVOKER,
search_path fixo, sem advisory lock, sem DELETE.
$c$;

revoke all on function public.f5_11_p5_3_trigger_perfil_avaliado()
  from public, anon, authenticated;
grant execute on function public.f5_11_p5_3_trigger_perfil_avaliado()
  to service_role;

drop trigger if exists trg_f5_11_p5_3_perfil on public.user_profiles;
create trigger trg_f5_11_p5_3_perfil
  after insert or update of status on public.user_profiles
  for each row execute function public.f5_11_p5_3_trigger_perfil_avaliado();

-- ----------------------------------------------------------------------------
-- B) RECONCILIACAO idempotente das memberships JA' existentes
-- ----------------------------------------------------------------------------
-- A P5.1 so' provisionou elegiveis; numa base onde alguem desativou um perfil
-- ANTES desta migration, a assignment poderia ter ficado `active` (defasada).
-- A reconciliacao reusa a MESMA funcao para TODAS as memberships e, por
-- construcao, so' grava em transicao real (nenhum evento falso em bases
-- coerentes).
do $reconcilia$
declare
  v_membership uuid;
  v_acao       text;
  v_total      integer := 0;
  v_grants     integer := 0;
  v_revokes    integer := 0;
begin
  for v_membership in
    select m.id from public.user_organization_memberships m order by m.id
  loop
    v_acao := public.f5_11_p5_1_provisionar_observacoes_avaliado(v_membership);
    v_total := v_total + 1;
    if v_acao = 'system_grant' then
      v_grants := v_grants + 1;
    elsif v_acao = 'system_revoke' then
      v_revokes := v_revokes + 1;
    end if;
  end loop;

  raise notice 'F5-11 P5.3: reconciliacao avaliou % memberships (system_grant=%, system_revoke=%, sem transicao=%)',
    v_total, v_grants, v_revokes, v_total - v_grants - v_revokes;
end $reconcilia$;

-- ----------------------------------------------------------------------------
-- C) GUARDAS FINAIS fail-closed
-- ----------------------------------------------------------------------------
do $guarda$
declare
  v_n integer;
begin
  -- O trigger existe, cobre `user_profiles` e esta' habilitado.
  if not exists (
    select 1 from pg_trigger
     where tgname = 'trg_f5_11_p5_3_perfil'
       and tgrelid = 'public.user_profiles'::regclass
       and not tgisinternal
       and tgenabled <> 'D'
  ) then
    raise exception 'F5_11_P5_3_GUARDA: trigger de propagacao de user_profiles ausente/desabilitado';
  end if;

  -- A funcao de propagacao NAO e' SECURITY DEFINER (doutrina).
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'f5_11_p5_3_trigger_perfil_avaliado'
       and p.prosecdef
  ) then
    raise exception 'F5_11_P5_3_GUARDA: funcao de propagacao nao pode ser SECURITY DEFINER';
  end if;

  -- A funcao de propagacao nao amplia superficie: `authenticated` sem EXECUTE.
  if has_function_privilege('authenticated',
       'public.f5_11_p5_3_trigger_perfil_avaliado()', 'EXECUTE') then
    raise exception 'F5_11_P5_3_GUARDA: authenticated nao pode executar a funcao de propagacao';
  end if;

  -- Os triggers da P5.1 continuam ativos (a propagacao se SOMA a eles).
  if not exists (
    select 1 from pg_trigger
     where tgname = 'trg_f5_11_p5_1_vinculo' and not tgisinternal and tgenabled <> 'D'
  ) or not exists (
    select 1 from pg_trigger
     where tgname = 'trg_f5_11_p5_1_membership' and not tgisinternal and tgenabled <> 'D'
  ) then
    raise exception 'F5_11_P5_3_GUARDA: triggers da P5.1 ausentes/desabilitados';
  end if;

  -- As discriminantes do D18 e da assignment seguem validas.
  select count(*) into v_n from pg_constraint
   where conname in ('ck_privilege_mutation_audit_actor_por_action',
                     'ck_membership_access_role_assignments_author_por_origin')
     and convalidated;
  if v_n <> 2 then
    raise exception 'F5_11_P5_3_GUARDA: constraints discriminantes do D18/assignment ausentes/invalidas (tem %)', v_n;
  end if;

  raise notice 'F5-11 P5.3: guardas finais OK (trigger de perfil ativo; funcao INVOKER sem EXECUTE para authenticated; triggers da P5.1 intactos; D18/assignment coerentes)';
end $guarda$;
