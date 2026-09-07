-- ============================================================================
-- F3-04 (Issue #81): reporting lines temporais entre posições
-- ----------------------------------------------------------------------------
-- Propósito: representar a cadeia hierárquica formal por relações temporais
-- entre organizational_positions, sem inferir hierarquia por collaborator,
-- job_role, seniority_level, organizational_unit, nome, rank ou sequência fixa
-- de cargos. Segue as convenções da F1-02 e o padrão temporal das F3-01/F3-03
-- (períodos meio-abertos `[valid_from, valid_to)`, `valid_to null` = vigente,
-- exclusion constraint por subordinado, histórico não destrutivo).
--
--   - public.position_reporting_lines — relação temporal "subordinado →
--     superior formal" entre posições da MESMA organização.
--
-- Decisões técnicas registradas (Issue #81 e revisão de escopo desta etapa):
--   - raiz/sem superior = AUSÊNCIA de linha vigente na data (gaps temporais são
--     permitidos e significam explicitamente ausência de superior formal no
--     intervalo); portanto `manager_position_id` é NOT NULL — nunca se cria
--     linha artificial com manager null; a reconstrução histórica interpreta a
--     ausência de linha válida na data como "posição sem superior";
--   - cada linha carrega `valid_from` (obrigatório), `valid_to` (null =
--     vigente) e `check (valid_to > valid_from)`; mudanças de superior fecham a
--     relação anterior e criam outra — nunca reescrevem o passado;
--   - superior único: exclusion constraint por `subordinate_position_id`
--     (tstzrange meio-aberto) impede DOIS superiores simultâneos para a mesma
--     posição (e impede sobreposições incompatíveis), sem exigir contiguidade
--     (gaps permitidos);
--   - self-reporting proibido declarativamente (check);
--   - ciclos multi-nível: trigger recursivo no banco (`WITH RECURSIVE`) valida
--     a cadeia APLICÁVEL NO PERÍODO da relação sendo criada/alterada (relações
--     que se sobrepõem ao período), não apenas o estado vigente hoje;
--     concorrência: `pg_advisory_xact_lock` por organização serializa escritas
--     do mesmo tenant no banco (o caminho de escrita futuro deve manter o mesmo
--     lock ou isolamento SERIALIZABLE — limitação residual documentada);
--   - integridade temporal com as posições: trigger de escrita valida que TODO
--     o intervalo da relação está contido simultaneamente na validade de
--     subordinate e manager (não pode começar antes da criação nem terminar
--     depois do encerramento de qualquer posição); `valid_to null` das posições
--     é tratado como vigente;
--   - encerramento de posição: exige fechamento EXPLÍCITO prévio das reporting
--     lines que a envolvam (regra da aplicação, sem auto-cascade); o banco
--     falha (fail-closed) se uma atualização direta da validade da posição
--     deixar reporting lines fora do novo período (trigger em
--     organizational_positions) — nunca corrige dados automaticamente;
--   - motivo: `reason text not null` (trim, não vazio), texto livre (sem enum/
--     taxonomia antecipada), parte do registro histórico da relação;
--   - auditoria/autor: SEM coluna de autor nesta fase — apenas metadados
--     técnicos (`created_at`/`updated_at`/`version`) + `reason` de negócio;
--     a autoria das operações será registrada pelo modelo transversal de
--     auditoria quando existir (precedente F2-06/F1-02); a ausência de autor é
--     limitação temporária, não ausência de requisito de auditoria;
--   - exclusão/correção: FKs `ON DELETE RESTRICT`, RLS deny-by-default (sem
--     delete físico); mudanças normais = fechar período + criar novo; uma
--     eventual correção retroativa excepcional será tratada futuramente por
--     fluxo explícito, autorizado e auditado (NÃO implementado nesta issue);
--   - tenant integrity declarativa: FKs compostas
--     `(posição, organization_id) → organizational_positions(id,
--     organization_id)` (unique de referência aditiva em
--     organizational_positions) garantem que subordinate, manager e a linha
--     pertencem à MESMA organização; nenhuma relação cross-organization;
--   - dotted line/colegiado NÃO pertence a esta relação (fora do escopo).
--
-- Fora do escopo (não antecipar): occupation/collaborator_id, ocupante da
-- posição, substituição temporária, colegiado, painel de avaliação, snapshot
-- de ciclo, capabilities, RLS de escopo organizacional, estrutura real da Vivo.
--
-- Dependências: public.organizations (F2-01), public.organizational_positions
-- (F3-03), extensão btree_gist (F3-01).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Unique de referência aditiva para as FKs compostas (tenant integrity)
-- ----------------------------------------------------------------------------
alter table public.organizational_positions
  add constraint uq_organizational_positions_id_organization
    unique (id, organization_id);

comment on constraint uq_organizational_positions_id_organization
  on public.organizational_positions is
  'Unique de referencia (F3-04, Issue #81) para as FKs compostas de '
  'position_reporting_lines: garante no banco que subordinate, manager e a '
  'relacao pertencem a mesma organizacao. Aditiva; nao altera a semantica da '
  'posicao.';

-- ----------------------------------------------------------------------------
-- public.position_reporting_lines
-- ----------------------------------------------------------------------------
create table public.position_reporting_lines (
  id                      uuid        not null default gen_random_uuid(),
  organization_id         uuid        not null,
  subordinate_position_id uuid        not null,
  manager_position_id     uuid        not null,
  reason                  text        not null,
  valid_from              timestamptz not null,
  valid_to                timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  version                 integer     not null default 0,
  constraint pk_position_reporting_lines primary key (id),
  constraint fk_position_reporting_lines_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint fk_position_reporting_lines_subordinate
    foreign key (subordinate_position_id, organization_id)
    references public.organizational_positions (id, organization_id)
    on delete restrict,
  constraint fk_position_reporting_lines_manager
    foreign key (manager_position_id, organization_id)
    references public.organizational_positions (id, organization_id)
    on delete restrict,
  constraint ck_position_reporting_lines_reason
    check (reason <> '' and reason = btrim(reason)),
  constraint ck_position_reporting_lines_valid_to
    check (valid_to is null or valid_to > valid_from),
  constraint ck_position_reporting_lines_not_self
    check (manager_position_id <> subordinate_position_id),
  constraint ex_position_reporting_lines_no_overlap
    exclude using gist (
      subordinate_position_id with =,
      tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&
    )
);

comment on table public.position_reporting_lines is
  'Reporting line formal temporal entre posicoes - F3-04 (Issue #81). '
  'Subordinado -> superior formal; ausencia de linha vigente = posicao sem '
  'superior (raiz).';

comment on column public.position_reporting_lines.subordinate_position_id is
  'Posicao subordinada (public.organizational_positions). No maximo um superior '
  'formal vigente por instante (exclusion constraint).';

comment on column public.position_reporting_lines.manager_position_id is
  'Posicao superior formal (public.organizational_positions). NOT NULL: raiz e '
  'representada por AUSENCIA de linha, nunca por manager null.';

comment on column public.position_reporting_lines.reason is
  'Motivo/justificativa de negocio da relacao naquele periodo. Obrigatorio, '
  'texto livre normalizado (trim, nao vazio); nao e sobrescrito para '
  'representar outra mudanca (historico preservado por fechamento + nova linha).';

comment on column public.position_reporting_lines.valid_to is
  'Fim do periodo (bound exclusivo, meio-aberto [valid_from, valid_to)); null = '
  'relacao vigente. Troca de superior fecha a linha anterior e cria nova, sem '
  'reescrever o passado; gaps (intervalos sem superior) sao permitidos.';

comment on constraint fk_position_reporting_lines_subordinate
  on public.position_reporting_lines is
  'FK composta (subordinate_position_id, organization_id): subordinado e '
  'relacao pertencem a mesma organizacao; ON DELETE RESTRICT.';

comment on constraint fk_position_reporting_lines_manager
  on public.position_reporting_lines is
  'FK composta (manager_position_id, organization_id): superior e relacao '
  'pertencem a mesma organizacao; ON DELETE RESTRICT.';

comment on constraint ck_position_reporting_lines_reason
  on public.position_reporting_lines is
  'Motivo obrigatorio, nao vazio e sem espacos nas bordas (normalizacao por '
  'check).';

comment on constraint ck_position_reporting_lines_not_self
  on public.position_reporting_lines is
  'Self-reporting proibido (uma posicao nao pode ser superior formal de si '
  'mesma).';

comment on constraint ex_position_reporting_lines_no_overlap
  on public.position_reporting_lines is
  'No maximo um superior formal por posicao em cada instante: periodos do mesmo '
  'subordinado nao podem se sobrepor (tstzrange meio-aberto + btree_gist). Gaps '
  'sao permitidos (sem contiguidade obrigatoria).';

create index ix_position_reporting_lines_organization_id
  on public.position_reporting_lines (organization_id);

create index ix_position_reporting_lines_subordinate_position_id
  on public.position_reporting_lines (subordinate_position_id);

create index ix_position_reporting_lines_manager_position_id
  on public.position_reporting_lines (manager_position_id);

create trigger trg_position_reporting_lines_updated_at
  before update on public.position_reporting_lines
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Trigger 1: integridade temporal com a validade das posições
-- ----------------------------------------------------------------------------
-- Ao criar/alterar uma reporting line, valida que TODO o intervalo da relação
-- está contido na validade de subordinate e manager (write-time). `valid_to
-- null` da posição é tratado como vigente (sem limite superior). Não faz
-- fechamento automático — apenas rejeita estados temporalmente incompatíveis.
create or replace function public.enforce_position_reporting_lines_within_positions()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_sub_from timestamptz;
  v_sub_to   timestamptz;
  v_man_from timestamptz;
  v_man_to   timestamptz;
begin
  select valid_from, valid_to
    into v_sub_from, v_sub_to
  from public.organizational_positions
  where id = new.subordinate_position_id;

  select valid_from, valid_to
    into v_man_from, v_man_to
  from public.organizational_positions
  where id = new.manager_position_id;

  if new.valid_from < v_sub_from or new.valid_from < v_man_from then
    raise exception
      'position_reporting_lines: periodo inicia antes da existencia das posicoes';
  end if;

  if new.valid_to is null then
    if v_sub_to is not null or v_man_to is not null then
      raise exception
        'position_reporting_lines: relacao aberta alem do encerramento de uma posicao';
    end if;
  else
    if (v_sub_to is not null and new.valid_to > v_sub_to)
       or (v_man_to is not null and new.valid_to > v_man_to) then
      raise exception
        'position_reporting_lines: periodo termina depois do encerramento de uma posicao';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_position_reporting_lines_within_positions() is
  'F3-04: garante que o periodo da reporting line esta contido na validade de '
  'subordinate e manager (integralidade temporal na gravacao; fail-closed, sem '
  'fechamento automatico).';

create trigger trg_position_reporting_lines_within_positions
  before insert or update on public.position_reporting_lines
  for each row
  execute function public.enforce_position_reporting_lines_within_positions();

-- ----------------------------------------------------------------------------
-- Trigger 2: prevenção de ciclos multi-nível (temporal, com lock por org)
-- ----------------------------------------------------------------------------
-- Antes de criar/alterar uma linha, valida recursivamente a cadeia APLICÁVEL
-- ao período da relação (relações que se sobrepõem ao novo período), rejeitando
-- qualquer operação que faça a posição subordinada tornar-se ancestral de si
-- mesma. Self-reporting é coberto pelo check (aqui retorna para não duplicar).
-- Concorrência: pg_advisory_xact_lock por organização serializa escritas do
-- mesmo tenant durante a transação; o caminho de escrita futuro deve manter o
-- mesmo lock (ou isolamento SERIALIZABLE) — limitação residual documentada.
create or replace function public.enforce_position_reporting_lines_no_cycle()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.manager_position_id = new.subordinate_position_id then
    return new; -- self-reporting e tratado pela check constraint
  end if;

  perform pg_advisory_xact_lock(
    hashtext('position_reporting_lines:' || new.organization_id::text)
  );

  if exists (
    with recursive upstream as (
      select rl.manager_position_id as mgr
      from public.position_reporting_lines rl
      where rl.id is distinct from new.id
        and rl.subordinate_position_id = new.manager_position_id
        and rl.valid_from < coalesce(new.valid_to, 'infinity'::timestamptz)
        and (rl.valid_to is null or rl.valid_to > new.valid_from)
      union
      select rl.manager_position_id
      from public.position_reporting_lines rl
      join upstream u on rl.subordinate_position_id = u.mgr
      where rl.id is distinct from new.id
        and rl.valid_from < coalesce(new.valid_to, 'infinity'::timestamptz)
        and (rl.valid_to is null or rl.valid_to > new.valid_from)
    )
    select 1 from upstream where mgr = new.subordinate_position_id
  ) then
    raise exception 'position_reporting_lines: ciclo hierarquico detectado';
  end if;

  return new;
end;
$$;

comment on function public.enforce_position_reporting_lines_no_cycle() is
  'F3-04: impede ciclos multi-nivel na cadeia formal, considerando as relacoes '
  'que se sobrepoem ao periodo da linha criada/alterada. Usa advisory xact '
  'lock por organizacao (concorrencia documentada).';

create trigger trg_position_reporting_lines_no_cycle
  before insert or update on public.position_reporting_lines
  for each row
  execute function public.enforce_position_reporting_lines_no_cycle();

-- ----------------------------------------------------------------------------
-- Trigger 3: encerramento de posição não deixa reporting lines inconsistentes
-- ----------------------------------------------------------------------------
-- Fail-closed: se uma atualização direta de valid_from/valid_to de uma posição
-- deixar alguma reporting line (como subordinate ou manager) fora do novo
-- período, a operação falha — nunca corrige dados automaticamente. O fluxo de
-- domínio deve encerrar explicitamente as reporting lines antes de encerrar a
-- posição (regra documentada).
create or replace function public.enforce_positions_close_without_open_reporting_lines()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.valid_from = old.valid_from
     and new.valid_to is not distinct from old.valid_to then
    return new;
  end if;

  if exists (
    select 1
    from public.position_reporting_lines rl
    where (rl.subordinate_position_id = new.id or rl.manager_position_id = new.id)
      and (
        rl.valid_from < new.valid_from
        or (new.valid_to is not null
            and (rl.valid_to is null or rl.valid_to > new.valid_to))
      )
  ) then
    raise exception
      'organizational_positions: encerramento deixaria reporting lines fora da nova validade (encerre-as antes)';
  end if;

  return new;
end;
$$;

comment on function public.enforce_positions_close_without_open_reporting_lines() is
  'F3-04: impede encerrar/alterar a validade de uma posicao enquanto houver '
  'reporting lines fora do novo periodo (fail-closed; o fechamento explicito '
  'das linhas e responsabilidade do fluxo de dominio).';

create trigger trg_organizational_positions_close_reporting_lines
  before update of valid_from, valid_to on public.organizational_positions
  for each row
  execute function public.enforce_positions_close_without_open_reporting_lines();

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
-- RLS é habilitada na tabela nova. NENHUMA policy é criada nesta migration, no
-- mesmo padrão das fases anteriores:
--   - deny-by-default integral (inclusive `authenticated`);
--   - esta issue não define modelo de acesso à hierarquia (RLS de escopo
--     organizacional é da Fase 4);
--   - policies restritivas entrarão como migrations aditivas futuras.
-- Nenhum grant é concedido; policies/grants das F2-03/F2-07 e o estado das
-- tabelas F3-01/F3-02/F3-03 permanecem inalterados.
alter table public.position_reporting_lines enable row level security;
