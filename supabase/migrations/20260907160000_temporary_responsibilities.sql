-- ============================================================================
-- F3-06 (Issue #83): responsabilidades temporárias e substituições
-- ----------------------------------------------------------------------------
-- Propósito: modelar substituições temporárias sem falsificar mudanças
-- permanentes na estrutura organizacional formal. Uma temporary
-- responsibility NÃO é occupation e NÃO é reporting line: representa que,
-- durante um período explícito, um colaborador substituto assume
-- responsabilidades relacionadas a uma organizational_position, enquanto a
-- estrutura formal e seu histórico permanecem intactos.
--
--   - public.temporary_responsibilities — vínculo temporal substituto ↔
--     posição alvo, com tipo de responsabilidade, motivo e período fechado.
--
-- Decisões técnicas registradas (Issue #83 e revisão de escopo desta etapa):
--   - alvo canônico = organizational_position (a unidade é derivada da
--     posição; sem referência polimórfica position/unit; sem alterar a
--     occupation nem a reporting line da posição);
--   - titular formal NÃO é armazenado: é DERIVADO da occupation vigente da
--     posição alvo (fonte canônica = occupations); a temporary responsibility
--     registra apenas o substituto; não há exigência de titular durante todo o
--     período sem decisão específica sobre esse caso;
--   - responsibility_type = text + check em
--     ('operational','evaluative','operational_evaluative'); é dado de domínio,
--     NÃO capability/autorização; nenhum valor concede acesso/permissão e não
--     altera RLS; o domínio futuro de avaliações resolverá explicitamente como
--     os tipos evaluative/operational_evaluative participam da determinação do
--     avaliador (nada de avaliação é implementado aqui);
--   - cardinalidade: NO MÁXIMO uma temporary responsibility por posição por
--     instante, INDEPENDENTE do tipo (exclusion por organizational_position_id
--     e período — operational e evaluative não coexistem na mesma posição;
--     operacional+evaluative usa o tipo operational_evaluative); o lado do
--     substituto é LIVRE (um colaborador pode substituir múltiplas posições
--     simultaneamente, sem exclusion por substituto);
--   - auto-substituição proibida (temporal): o substituto não pode ser o
--     ocupante formal da própria posição alvo em período sobreposto (trigger
--     compara com occupations); a mesma pessoa pode ser titular em um período e
--     substituta em outro não sobreposto; posição vaga é caso distinto;
--   - temporalidade: período OBRIGATORIAMENTE fechado — `valid_from` e
--     `valid_to` NOT NULL, `valid_to > valid_from`, meio-aberto
--     `[valid_from, valid_to)`; prorrogação/mudança de tipo ou substituto =
--     encerrar + novo registro (com reason próprio), preservando ambos;
--   - integridade temporal com a posição: trigger de escrita valida que o
--     período está INTEGRALMENTE contido na validade da posição alvo
--     (rejeita gravação em vez de ajustar datas); colaborador substituto via FK
--     composta (existe e pertence à mesma organização); sem exigência de
--     occupation do substituto;
--   - occupation e status INDEPENDENTES: sem FK para occupations (titular
--     resolvido pela occupation; substituto não recebe occupation) e sem
--     constraint com collaborator_status_periods (leave não cria, retorno não
--     encerra, inactive não é substituição);
--   - motivo/auditoria (baseline F3-04/F3-05): `reason text not null` (trim,
--     não vazio), texto livre; `created_at`/`updated_at`/`version`; SEM coluna
--     de autor (auditoria transversal futura — limitação documentada);
--   - exclusão/correção: FKs `ON DELETE RESTRICT`, RLS deny-by-default (sem
--     delete físico); histórico imutável no fluxo normal; correção retroativa
--     excepcional fora do escopo (fluxo futuro explícito/auditado);
--   - tenant integrity declarativa: FKs compostas
--     (posição/substituto, organization_id) (uniques de referência já
--     existentes) — cross-organization impossível no banco.
--
-- Fora do escopo (não antecipar): colegiado, evaluation panel, snapshot de
-- ciclo, avaliação propriamente dita, capabilities/RBAC, dotted line,
-- notificações, UI administrativa completa, dados/estrutura real da Vivo.
--
-- Dependências: public.organizations (F2-01), public.collaborators (F3-01),
-- public.organizational_positions (F3-03), public.occupations (F3-05),
-- extensão btree_gist (F3-01).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.temporary_responsibilities
-- ----------------------------------------------------------------------------
create table public.temporary_responsibilities (
  id                        uuid        not null default gen_random_uuid(),
  organization_id           uuid        not null,
  organizational_position_id uuid       not null,
  substitute_collaborator_id uuid       not null,
  responsibility_type       text        not null,
  reason                    text        not null,
  valid_from                timestamptz not null,
  valid_to                  timestamptz not null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  version                   integer     not null default 0,
  constraint pk_temporary_responsibilities primary key (id),
  constraint fk_temporary_responsibilities_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint fk_temporary_responsibilities_positions foreign key (organizational_position_id, organization_id)
    references public.organizational_positions (id, organization_id)
    on delete restrict,
  constraint fk_temporary_responsibilities_substitute foreign key (substitute_collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint ck_temporary_responsibilities_type
    check (responsibility_type in ('operational', 'evaluative', 'operational_evaluative')),
  constraint ck_temporary_responsibilities_reason
    check (reason <> '' and reason = btrim(reason)),
  constraint ck_temporary_responsibilities_valid_to
    check (valid_to > valid_from),
  constraint ex_temporary_responsibilities_position_no_overlap
    exclude using gist (
      organizational_position_id with =,
      tstzrange(valid_from, valid_to, '[)') with &&
    )
);

comment on table public.temporary_responsibilities is
  'Responsabilidade temporaria (substituicao) sobre uma posicao formal - F3-06 '
  '(Issue #83). NAO e occupation nem reporting line.';

comment on column public.temporary_responsibilities.organizational_position_id is
  'Posicao formal alvo da responsabilidade. No maximo uma temporary '
  'responsibility por instante por posicao (exclusion). A unidade e derivada '
  'da posicao.';

comment on column public.temporary_responsibilities.substitute_collaborator_id is
  'Colaborador substituto que assume a responsabilidade no periodo. Sem '
  'exclusion por substituto: multiplas posicoes simultaneas sao validas; nao '
  'pode ser o ocupante formal da propria posicao no mesmo periodo (trigger).';

comment on column public.temporary_responsibilities.responsibility_type is
  'Tipo da responsabilidade: operational, evaluative ou operational_evaluative. '
  'Dado de dominio — nao concede capability/autorizacao e nao altera RLS.';

comment on column public.temporary_responsibilities.reason is
  'Motivo/justificativa de negocio da concessao (baseline F3-04/F3-05): '
  'obrigatorio, texto livre normalizado (trim, nao vazio); cada periodo tem seu '
  'proprio reason.';

comment on column public.temporary_responsibilities.valid_to is
  'Fim do periodo (obrigatorio): substituicao sempre com inicio/fim explicitos '
  '(meio-aberto [valid_from, valid_to)); prorrogacao = fechar + novo registro.';

comment on constraint fk_temporary_responsibilities_positions
  on public.temporary_responsibilities is
  'FK composta (organizational_position_id, organization_id): posicao alvo e '
  'responsabilidade pertencem a mesma organizacao; ON DELETE RESTRICT.';

comment on constraint fk_temporary_responsibilities_substitute
  on public.temporary_responsibilities is
  'FK composta (substitute_collaborator_id, organization_id): substituto e '
  'responsabilidade pertencem a mesma organizacao; ON DELETE RESTRICT.';

comment on constraint ck_temporary_responsibilities_type
  on public.temporary_responsibilities is
  'Dominio do tipo (operational/evaluative/operational_evaluative); text+check '
  '(sem enum nativo). Nao concede autorizacao.';

comment on constraint ck_temporary_responsibilities_valid_to
  on public.temporary_responsibilities is
  'Periodo obrigatoriamente fechado e valido: valid_to > valid_from '
  '(meio-aberto nao degenerado).';

comment on constraint ex_temporary_responsibilities_position_no_overlap
  on public.temporary_responsibilities is
  'No maximo uma temporary responsibility por posicao por instante, '
  'independente do tipo (tstzrange meio-aberto; tipos nao coexistem na mesma '
  'posicao). Nao restringe multiplas posicoes do mesmo substituto.';

create index ix_temporary_responsibilities_organization_id
  on public.temporary_responsibilities (organization_id);

create index ix_temporary_responsibilities_organizational_position_id
  on public.temporary_responsibilities (organizational_position_id);

create index ix_temporary_responsibilities_substitute_collaborator_id
  on public.temporary_responsibilities (substitute_collaborator_id);

create trigger trg_temporary_responsibilities_updated_at
  before update on public.temporary_responsibilities
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Trigger 1: responsabilidade contida na validade da posição
-- ----------------------------------------------------------------------------
-- Write-time: o período [valid_from, valid_to) precisa estar integralmente
-- contido na validade da posição alvo (posições abertas tratam valid_to null
-- como vigente). Rejeita a gravação em vez de ajustar datas.
create or replace function public.enforce_temporary_responsibility_within_position()
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
      'temporary_responsibilities: periodo inicia antes da existencia da posicao';
  end if;

  if v_pos_to is not null and new.valid_to > v_pos_to then
    raise exception
      'temporary_responsibilities: periodo termina depois do encerramento da posicao';
  end if;

  return new;
end;
$$;

comment on function public.enforce_temporary_responsibility_within_position() is
  'F3-06: garante que o periodo da temporary responsibility esta contido na '
  'validade da posicao alvo (integralidade temporal na gravacao; fail-closed).';

create trigger trg_temporary_responsibilities_within_position
  before insert or update on public.temporary_responsibilities
  for each row
  execute function public.enforce_temporary_responsibility_within_position();

-- ----------------------------------------------------------------------------
-- Trigger 2: proibição de auto-substituição (temporal)
-- ----------------------------------------------------------------------------
-- O substituto não pode ser o ocupante formal da própria posição alvo em
-- período sobreposto. Compara com occupations (fonte canônica do titular);
-- posição vaga não é auto-substituição.
create or replace function public.enforce_temporary_responsibility_not_self()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.occupations o
    where o.organizational_position_id = new.organizational_position_id
      and o.collaborator_id = new.substitute_collaborator_id
      and o.valid_from < new.valid_to
      and (o.valid_to is null or o.valid_to > new.valid_from)
  ) then
    raise exception
      'temporary_responsibilities: substituto nao pode ser o ocupante formal da posicao no periodo';
  end if;

  return new;
end;
$$;

comment on function public.enforce_temporary_responsibility_not_self() is
  'F3-06: proibe auto-substituicao temporal — o substituto nao pode ser o '
  'ocupante formal da posicao alvo em periodo sobreposto (titular derivado de '
  'occupations).';

create trigger trg_temporary_responsibilities_not_self
  before insert or update on public.temporary_responsibilities
  for each row
  execute function public.enforce_temporary_responsibility_not_self();

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
-- RLS é habilitada na tabela nova. NENHUMA policy é criada nesta migration, no
-- mesmo padrão das fases anteriores: deny-by-default integral; RLS de escopo
-- organizacional é da Fase 4. Nenhum grant é concedido; policies/grants das
-- F2-03/F2-07 e o estado das tabelas F3-01..F3-05 permanecem inalterados.
alter table public.temporary_responsibilities enable row level security;
