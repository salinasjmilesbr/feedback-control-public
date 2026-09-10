-- ============================================================================
-- F5-04 (Issue #165): trilha append-only de mutações de privilégio (D18)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-04-desenho-tecnico.md (D18 FECHADA).
--
-- Mutações de privilégio (conceder/revogar access_role de membership) geram
-- registro APPEND-ONLY com autoria SOBERANA (ator derivado de auth.uid() no
-- caminho server-side, nunca informado pelo cliente). Preserva a trilha mínima
-- existente (created_by/version em membership_access_role_assignments) e evolui
-- para uma tabela de eventos dedicada.
--
-- Segurança (D10/AC7/D18):
--   - RLS deny-by-default (zero policies, zero grants a authenticated);
--   - service_role (credencial do caminho aplicativo de D16) tem SOMENTE
--     SELECT + INSERT: grava (append) e lê a trilha, mas NÃO pode UPDATE nem
--     DELETE (imutabilidade append-only da trilha);
--   - higienização/limpeza fica FORA da credencial/runtime normal da aplicação:
--     exclusiva do proprietário/superuser (postgres/supabase_admin, credencial
--     de migração/operação local), nunca de service_role.
-- ============================================================================

create table public.privilege_mutation_audit (
  id                   uuid        not null default gen_random_uuid(),
  organization_id      uuid        not null,
  membership_id        uuid        not null,
  access_role_id       uuid        not null,
  action               text        not null,
  actor_user_profile_id uuid       not null,
  created_at           timestamptz not null default now(),
  constraint pk_privilege_mutation_audit primary key (id),
  constraint ck_privilege_mutation_audit_action
    check (action in ('grant', 'revoke'))
);

comment on table public.privilege_mutation_audit is
  'F5-04 (D18): trilha append-only de mutacoes de privilegio (grant/revoke de '
  'access_role a membership). Linhas imutaveis; autoria soberana '
  '(actor_user_profile_id derivado de auth.uid() server-side). Sem FK de '
  'historico: registro imutavel que nao bloqueia o ciclo de vida da origem.';

comment on column public.privilege_mutation_audit.action is
  'grant | revoke (mutacao de privilegio registrada).';

comment on column public.privilege_mutation_audit.actor_user_profile_id is
  'Autoria soberana da mutacao: user_profile do ator derivado de auth.uid() no '
  'caminho server-side (nunca informado pelo cliente).';

create index ix_privilege_mutation_audit_organization_id
  on public.privilege_mutation_audit (organization_id);

create index ix_privilege_mutation_audit_membership_id
  on public.privilege_mutation_audit (membership_id);

-- Append-only: nenhuma linha pode ser ATUALIZADA após a gravação (trigger).
-- DELETE é bloqueado no caminho de aplicação pela REVOGAÇÃO de privilégio de
-- service_role (abaixo): service_role só grava (INSERT) e lê (SELECT). A
-- higienização fica fora do runtime — exclusiva do proprietário/superuser.
create or replace function public.enforce_privilege_audit_append_only()
returns trigger
language plpgsql
as $$
begin
  raise exception 'F5-04: privilege_mutation_audit e append-only (UPDATE negado)';
end;
$$;

comment on function public.enforce_privilege_audit_append_only() is
  'F5-04 (D18): impede UPDATE de registros da trilha de mutacoes de privilegio '
  '(append-only). DELETE e bloqueado no caminho de aplicacao por revogacao de '
  'privilegio de service_role (somente SELECT+INSERT); a higienizacao pertence '
  'ao proprietario/superuser (postgres/supabase_admin), fora do runtime.';

create trigger trg_privilege_mutation_audit_append_only
  before update on public.privilege_mutation_audit
  for each row
  execute function public.enforce_privilege_audit_append_only();

-- RLS deny-by-default: zero policies; zero grants a authenticated/anon.
alter table public.privilege_mutation_audit enable row level security;

-- Imutabilidade no caminho de aplicação (D18): service_role perde UPDATE/DELETE
-- (e demais DML) e mantém SOMENTE SELECT + INSERT. O proprietário (postgres/
-- supabase_admin) preserva DELETE por ownership para a higienização explícita
-- de ambiente sintético (fora da credencial/runtime de produção).
revoke all on public.privilege_mutation_audit from anon, authenticated, service_role;
grant select, insert on public.privilege_mutation_audit to service_role;
