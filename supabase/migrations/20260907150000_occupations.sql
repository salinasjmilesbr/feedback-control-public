-- ============================================================================
-- F3-05 (Issue #82): ocupações temporais de colaboradores em posições
-- ----------------------------------------------------------------------------
-- Propósito: representar quem ocupa cada organizational_position ao longo do
-- tempo, preservando transferências, posições vagas e múltiplas
-- responsabilidades simultâneas de um colaborador. Mantém rigorosamente
-- separados: collaborator (pessoa organizacional), organizational_position
-- (posição formal), occupation (vínculo temporal entre ambos),
-- collaborator_status_period (situação do colaborador) e
-- position_reporting_line (hierarquia entre posições).
--
--   - public.occupations — vínculo temporal colaborador ↔ posição formal da
--     MESMA organização, com motivo obrigatório e período meio-aberto.
--
-- Decisões técnicas registradas (Issue #82 e revisão de escopo desta etapa):
--   - cardinalidade por posição: NO MÁXIMO um ocupante por instante
--     (exclusion constraint temporal por organizational_position_id — linha do
--     tempo única por posição; períodos de occupations diferentes na mesma
--     posição não se sobrepõem); troca de ocupante encerra a anterior e cria
--     nova, preservando a mesma posição; posição vaga = ausência de occupation
--     válida naquele instante; co-ocupação NÃO é usada para substituição
--     temporária (fora do escopo);
--   - lado do colaborador: NENHUMA constraint limita múltiplas posições
--     simultâneas (sem exclusion por collaborator_id); um colaborador pode
--     ocupar posições diferentes ao mesmo tempo;
--   - temporalidade: `valid_from` obrigatório, `valid_to` null = vigente,
--     `check (valid_to > valid_from)`, meio-aberto `[valid_from, valid_to)`;
--     períodos consecutivos na mesma posição são permitidos;
--   - integridade temporal com a posição: trigger de escrita valida que a
--     occupation está INTEGRALMENTE contida no período de existência da
--     organizational_position (não começa antes nem termina depois); para o
--     collaborator NÃO há validade própria (F3-01): garantia por FK + mesma
--     organização; NÃO é inventado valid_from/valid_to em collaborator;
--   - occupation × collaborator_status_period: conceitos INDEPENDENTES —
--     status `leave` não encerra nem invalida occupation; retorno de leave não
--     recria occupation; NÃO é exigido status `active` durante a occupation;
--   - desligamento (status `inactive`): o banco REJEITA (fail-closed) iniciar
--     um período inactive enquanto existirem occupations vigentes que
--     ultrapassem a data de início do desligamento — o fluxo de domínio deve
--     encerrar explicitamente as occupations (com a data adequada) antes;
--     NÃO há trigger de fechamento automático; regra específica de
--     inactive/desligamento, não de licença;
--   - motivo/auditoria (baseline F3-04): `reason text not null` (trim, não
--     vazio), texto livre; `created_at`/`updated_at`/`version`; SEM coluna de
--     autor (modelo transversal de auditoria é pendência futura — limitação
--     documentada); reason pertence ao registro histórico e não é sobrescrito
--     (transferência = fechar + nova linha com novo reason);
--   - exclusão/correção: FKs `ON DELETE RESTRICT`, RLS deny-by-default (sem
--     delete físico); mudanças normais = fechar + nova linha; correção
--     retroativa excepcional fica fora do escopo (fluxo futuro explícito,
--     autorizado e auditado);
--   - tenant integrity declarativa: FKs compostas
--     (colaborador, organization_id) → collaborators(id, organization_id) e
--     (posição, organization_id) → organizational_positions(id,
--     organization_id); cross-organization impossível no banco.
--
-- Fora do escopo (não antecipar): temporary responsibility/substituição
-- temporária, colegiado, evaluation panel, avaliação, snapshot de ciclo,
-- autorização/capabilities, dotted line, alteração de reporting line causada
-- pelo ocupante, estrutura/dados reais da Vivo.
--
-- Dependências: public.organizations (F2-01), public.collaborators (F3-01),
-- public.organizational_positions (F3-03), extensão btree_gist (F3-01).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.occupations
-- ----------------------------------------------------------------------------
create table public.occupations (
  id                        uuid        not null default gen_random_uuid(),
  organization_id           uuid        not null,
  collaborator_id           uuid        not null,
  organizational_position_id uuid       not null,
  reason                    text        not null,
  valid_from                timestamptz not null,
  valid_to                  timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  version                   integer     not null default 0,
  constraint pk_occupations primary key (id),
  constraint fk_occupations_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint fk_occupations_collaborators foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint fk_occupations_positions foreign key (organizational_position_id, organization_id)
    references public.organizational_positions (id, organization_id)
    on delete restrict,
  constraint ck_occupations_reason
    check (reason <> '' and reason = btrim(reason)),
  constraint ck_occupations_valid_to
    check (valid_to is null or valid_to > valid_from),
  constraint ex_occupations_position_no_overlap
    exclude using gist (
      organizational_position_id with =,
      tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&
    )
);

comment on table public.occupations is
  'Ocupacao temporal colaborador ↔ posicao formal - F3-05 (Issue #82). No '
  'maximo um ocupante por instante por posicao; vacancia = ausencia de '
  'ocupacao valida.';

comment on column public.occupations.collaborator_id is
  'Colaborador (public.collaborators) que ocupa a posicao. Sem exclusion por '
  'colaborador: multiplas posicoes simultaneas sao validas.';

comment on column public.occupations.organizational_position_id is
  'Posicao formal (public.organizational_positions). Exclusion constraint '
  'garante no maximo uma occupation vigente por instante (um ocupante por '
  'posicao); troca de ocupante fecha a anterior e abre a nova.';

comment on column public.occupations.reason is
  'Motivo/justificativa de negocio da ocupacao naquele periodo (baseline '
  'F3-04): obrigatorio, texto livre normalizado (trim, nao vazio); nao e '
  'sobrescrito (transferencia = fechar + nova linha com novo reason).';

comment on column public.occupations.valid_to is
  'Fim do periodo (meio-aberto [valid_from, valid_to)); null = ocupacao '
  'vigente. Encerramento preserva a linha/UUID (historico nao destrutivo).';

comment on constraint fk_occupations_collaborators
  on public.occupations is
  'FK composta (collaborator_id, organization_id): colaborador e ocupacao '
  'pertencem a mesma organizacao; ON DELETE RESTRICT.';

comment on constraint fk_occupations_positions
  on public.occupations is
  'FK composta (organizational_position_id, organization_id): posicao e '
  'ocupacao pertencem a mesma organizacao; ON DELETE RESTRICT.';

comment on constraint ck_occupations_reason
  on public.occupations is
  'Motivo obrigatorio, nao vazio e sem espacos nas bordas (normalizacao por '
  'check).';

comment on constraint ex_occupations_position_no_overlap
  on public.occupations is
  'Linha do tempo unica por posicao: periodos de occupations da mesma posicao '
  'nao podem se sobrepor (um ocupante por instante; tstzrange meio-aberto). '
  'Nao restringe multiplas posicoes simultaneas do mesmo colaborador.';

create index ix_occupations_organization_id
  on public.occupations (organization_id);

create index ix_occupations_collaborator_id
  on public.occupations (collaborator_id);

create index ix_occupations_organizational_position_id
  on public.occupations (organizational_position_id);

create trigger trg_occupations_updated_at
  before update on public.occupations
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Trigger 1: occupation contida na validade da posição
-- ----------------------------------------------------------------------------
-- Write-time: o período da occupation precisa estar integralmente dentro do
-- valid_from/valid_to da organizational_position (posições abertas tratam
-- valid_to null como vigente). Nada é fechado automaticamente.
create or replace function public.enforce_occupation_within_position()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_pos_from timestamptz;
  v_pos_to   timestamptz;
begin
  select valid_from, valid_to
    into v_pos_from, v_pos_to
  from public.organizational_positions
  where id = new.organizational_position_id;

  if new.valid_from < v_pos_from then
    raise exception
      'occupations: periodo inicia antes da existencia da posicao';
  end if;

  if new.valid_to is null then
    if v_pos_to is not null then
      raise exception
        'occupations: ocupacao aberta alem do encerramento da posicao';
    end if;
  else
    if v_pos_to is not null and new.valid_to > v_pos_to then
      raise exception
        'occupations: periodo termina depois do encerramento da posicao';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_occupation_within_position() is
  'F3-05: garante que o periodo da occupation esta contido na validade da '
  'posicao formal (integralidade temporal na gravacao; fail-closed, sem '
  'fechamento automatico).';

create trigger trg_occupations_within_position
  before insert or update on public.occupations
  for each row
  execute function public.enforce_occupation_within_position();

-- ----------------------------------------------------------------------------
-- Trigger 2: desligamento (inactive) exige occupations encerradas
-- ----------------------------------------------------------------------------
-- Fail-closed: iniciar/alterar um collaborator_status_period com status
-- 'inactive' é rejeitado enquanto existirem occupations vigentes que
-- ultrapassem a data de início do desligamento. O fluxo de domínio deve
-- encerrar explicitamente as occupations antes (não há fechamento automático).
-- Licença (leave) permanece independente — a regra vale somente para inactive.
create or replace function public.enforce_collaborator_inactive_requires_closed_occupations()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'inactive' then
    if exists (
      select 1
      from public.occupations o
      where o.collaborator_id = new.collaborator_id
        and (o.valid_to is null or o.valid_to > new.valid_from)
    ) then
      raise exception
        'collaborator_status_periods: desligamento com occupations vigentes — encerre-as explicitamente antes';
    end if;
  end if;
  return new;
end;
$$;

comment on function public.enforce_collaborator_inactive_requires_closed_occupations() is
  'F3-05: impede iniciar periodo inactive (desligamento) com occupations '
  'vigentes que ultrapassem a data de inicio (fail-closed, sem auto-cascade); '
  'licenca (leave) nao e afetada.';

create trigger trg_collaborator_status_periods_inactive_occupations
  before insert or update on public.collaborator_status_periods
  for each row
  execute function public.enforce_collaborator_inactive_requires_closed_occupations();

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
-- RLS é habilitada na tabela nova. NENHUMA policy é criada nesta migration, no
-- mesmo padrão das fases anteriores: deny-by-default integral; RLS de escopo
-- organizacional é da Fase 4. Nenhum grant é concedido; policies/grants das
-- F2-03/F2-07 e o estado das tabelas F3-01/F3-02/F3-03/F3-04 permanecem
-- inalterados.
alter table public.occupations enable row level security;
