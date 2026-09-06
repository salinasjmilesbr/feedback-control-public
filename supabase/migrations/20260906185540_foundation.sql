-- ============================================================================
-- Foundation técnica — F1-03 (Issue #64)
-- ----------------------------------------------------------------------------
-- Propósito: criar a primeira migration técnica do Virtus Team, seguindo as
-- convenções da F1-02 (supabase/migrations/README.md). Esta migration prepara
-- fundações reutilizáveis para UUID, timestamps e versionamento sem criar
-- nenhuma entidade funcional.
--
-- Fora do escopo desta migration (e desta fase):
--   - nenhuma tabela de domínio (organizations, users, collaborators, cycles,
--     evaluations, goals, observations ou equivalentes);
--   - nenhum schema de domínio, Auth, RLS, policy, role, seed ou procedure de
--     negócio;
--   - nenhuma alteração no runtime da aplicação.
--
-- Comportamento:
--   - aplica em banco vazio (fluxo local de rebuild/`supabase db reset`);
--   - é segura para reexecução (apenas objetos idempotentes são criados);
--   - não depende de estado manual nem de projeto hospedado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Extensões
-- ----------------------------------------------------------------------------
-- Nenhuma extensão é habilitada nesta migration: não há necessidade concreta
-- documentada. `gen_random_uuid()` é nativo do PostgreSQL 17 (UUID padrão da
-- F1-02). Extensões só entram em migrations dedicadas, quando uma necessidade
-- real e compatível com Supabase existir (convenção F1-02).
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- Helper técnico: public.set_updated_at()
-- ----------------------------------------------------------------------------
-- Função de trigger técnica e reutilizável que mantém `updated_at` na
-- atualização, conforme o padrão de timestamps da F1-02 ("trigger técnico
-- padrão da foundation"). As migrations de domínio futuras anexam esta função
-- às tabelas que possuem `updated_at`; nenhum trigger é criado aqui, pois não
-- há tabelas nesta fase. `updated_at` nunca é escrito manualmente pelo cliente.
-- ----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Trigger tecnico da foundation (F1-03): define updated_at = now() em updates '
  'das tabelas que possuem a coluna updated_at, conforme convencao da F1-02.';

-- ----------------------------------------------------------------------------
-- Padrões reutilizáveis (documentação — nada é criado aqui)
-- ----------------------------------------------------------------------------
-- Colunas técnicas padronizadas a aplicar nas migrations de domínio futuras
-- (F1-02), reproduzidas como referência; nenhuma entidade é criada nesta fase:
--
--   id            uuid primary key default gen_random_uuid()  -- PK técnica
--   created_at    timestamptz not null default now()          -- sempre
--   updated_at    timestamptz not null default now()          -- quando houver
--                 atualização, com trigger set_updated_at
--   version       integer not null default 0                  -- somente quando
--                 a entidade admitir edição concorrente
--   organization_id uuid                                       -- somente em
--                 entidades multi-organização futuras (FK entra com a entidade
--                 organizacional; RLS/Auth pertencem a fases posteriores)
-- ----------------------------------------------------------------------------
