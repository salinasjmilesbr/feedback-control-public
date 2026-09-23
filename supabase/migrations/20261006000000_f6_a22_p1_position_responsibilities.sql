-- F6-A22 P1 (Issue #338)
-- Responsabilidades temporais de posição: schema, allowlist, auditoria e RLS.
-- P2/P3/P4/P5 (resolver, RPC/Edge, UI e runtime) permanecem fora desta migration.

create table public.organizational_position_responsibilities (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  position_id uuid not null,
  responsibility_code text not null,
  valid_from timestamptz not null,
  valid_to timestamptz,
  status text not null default 'active',
  version integer not null default 0,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pk_organizational_position_responsibilities primary key (id),
  constraint fk_opr_organization foreign key (organization_id)
    references public.organizations (id) on delete restrict,
  constraint fk_opr_position foreign key (position_id, organization_id)
    references public.organizational_positions (id, organization_id) on delete restrict,
  constraint fk_opr_created_by foreign key (created_by)
    references public.user_profiles (id) on delete restrict,
  constraint ck_opr_code check (responsibility_code in ('PEOPLE_MANAGEMENT')),
  constraint ck_opr_status check (status in ('active', 'revoked')),
  constraint ck_opr_valid_to check (valid_to is null or valid_to > valid_from),
  constraint ck_opr_version check (version >= 0),
  constraint ex_opr_no_overlap exclude using gist (
    organization_id with =,
    position_id with =,
    responsibility_code with =,
    tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&
  )
);

comment on table public.organizational_position_responsibilities is
  'F6-A22 P1: responsabilidade temporal pertencente a uma posicao; nao e role '
  'nem concede autorizacao antes da integracao P2.';

create index ix_opr_organization_position
  on public.organizational_position_responsibilities (organization_id, position_id);
create index ix_opr_position_temporal
  on public.organizational_position_responsibilities (position_id, valid_from, valid_to);
create index ix_opr_active_temporal
  on public.organizational_position_responsibilities (organization_id, position_id, responsibility_code, valid_from)
  where status = 'active';

create trigger trg_opr_updated_at
  before update on public.organizational_position_responsibilities
  for each row execute function public.set_updated_at();

-- Catalogo fechado localmente para nao criar capability/role nova.
create table public.organizational_position_responsibilities_catalog (
  code text primary key,
  constraint ck_oprc_code check (code in ('PEOPLE_MANAGEMENT'))
);
insert into public.organizational_position_responsibilities_catalog (code)
values ('PEOPLE_MANAGEMENT');

-- Allowlist server-side versionada. O bundle e deliberadamente exato:
-- collaborator.read + collaborator.create; collaborator.edit nao e incluido.
create table public.organizational_position_responsibility_bundle (
  responsibility_code text not null,
  capability_code text not null,
  constraint pk_opr_bundle primary key (responsibility_code, capability_code),
  constraint fk_opr_bundle_code foreign key (responsibility_code)
    references public.organizational_position_responsibilities_catalog (code) on delete restrict,
  constraint fk_opr_bundle_capability foreign key (capability_code)
    references public.capabilities (code) on delete restrict
);

insert into public.organizational_position_responsibility_bundle (responsibility_code, capability_code)
values
  ('PEOPLE_MANAGEMENT', 'collaborator.read'),
  ('PEOPLE_MANAGEMENT', 'collaborator.create');

create table public.organizational_position_responsibility_events (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  responsibility_id uuid not null,
  event_type text not null,
  actor_user_profile_id uuid not null,
  event_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  constraint pk_opr_events primary key (id),
  constraint fk_opr_events_organization foreign key (organization_id)
    references public.organizations (id) on delete restrict,
  constraint fk_opr_events_responsibility foreign key (responsibility_id)
    references public.organizational_position_responsibilities (id) on delete restrict,
  constraint fk_opr_events_actor foreign key (actor_user_profile_id)
    references public.user_profiles (id) on delete restrict,
  constraint ck_opr_events_type check (event_type in ('CREATED', 'UPDATED', 'REVOKED'))
);

create index ix_opr_events_organization on public.organizational_position_responsibility_events (organization_id);
create index ix_opr_events_responsibility on public.organizational_position_responsibility_events (responsibility_id, event_at);

create or replace function public.enforce_opr_events_append_only()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'F6-A22: organizational_position_responsibility_events e append-only';
end;
$$;
create trigger trg_opr_events_append_only
  before update or delete on public.organizational_position_responsibility_events
  for each row execute function public.enforce_opr_events_append_only();

-- A trilha nasce na mesma transacao do fato. O autor e validado pelo FK e a
-- fronteira administrativa (P3) continua sendo responsavel pela autorizacao.
create or replace function public.audit_opr_change()
returns trigger language plpgsql set search_path = public as $$
declare v_actor uuid;
begin
  v_actor := coalesce(nullif(current_setting('request.jwt.claim.sub', true), '')::uuid, new.created_by);
  insert into public.organizational_position_responsibility_events
    (organization_id, responsibility_id, event_type, actor_user_profile_id, payload)
  values (
    new.organization_id, new.id,
    case when tg_op = 'INSERT' then 'CREATED' when new.status = 'revoked' then 'REVOKED' else 'UPDATED' end,
    v_actor, jsonb_build_object('version', new.version, 'status', new.status)
  );
  return new;
end;
$$;
create trigger trg_opr_audit_change
  after insert or update on public.organizational_position_responsibilities
  for each row execute function public.audit_opr_change();

alter table public.organizational_position_responsibilities enable row level security;
alter table public.organizational_position_responsibility_bundle enable row level security;
alter table public.organizational_position_responsibilities_catalog enable row level security;
alter table public.organizational_position_responsibility_events enable row level security;

revoke all on public.organizational_position_responsibilities from anon, authenticated;
revoke all on public.organizational_position_responsibility_bundle from anon, authenticated;
revoke all on public.organizational_position_responsibilities_catalog from anon, authenticated;
revoke all on public.organizational_position_responsibility_events from anon, authenticated;

-- Explicit guard: P1 nao publica collaborator.edit nem grants diretos.
do $$
declare v_count integer;
begin
  select count(*) into v_count
    from public.organizational_position_responsibility_bundle
   where responsibility_code = 'PEOPLE_MANAGEMENT';
  if v_count <> 2 or exists (
    select 1 from public.organizational_position_responsibility_bundle
     where capability_code = 'collaborator.edit') then
    raise exception 'F6-A22 P1: bundle PEOPLE_MANAGEMENT divergente';
  end if;
end $$;
