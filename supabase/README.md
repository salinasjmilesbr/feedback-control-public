# Supabase local — desenvolvimento (F1-01 a F2-02)

Infraestrutura local do Supabase para o Virtus Team, versionada e reconstruível
integralmente a partir do repositório — sem configuração manual no dashboard,
sem projeto remoto, sem credenciais e sem dados reais.

Estrutura inicial gerada com `npx --yes supabase@2.116.0 init` (F1-01), reduzida
aos serviços locais necessários: PostgreSQL 17, API, Studio e Auth (Auth
habilitado na F2-01). Realtime, Storage, SMTP, Edge Runtime e Analytics
permanecem desabilitados. As convenções de migrations estão em
[migrations/README.md](migrations/README.md).

A F1-03 adicionou a primeira migration de foundation (sem entidades funcionais);
a F1-05 habilitou o seed sintético de desenvolvimento (`seed.sql`); a F1-06
validou o rebuild completo e a reprodutibilidade a partir de estado limpo. A
F2-01 habilitou o serviço Auth local e criou as primeiras entidades funcionais —
`organizations` e `user_profiles` (perfil interno ligado 1:1 a `auth.users`) — e
a F2-02 adicionou `user_organization_memberships` (membership usuário-organização
por UUID, sem exigir colaborador). Todas as tabelas têm RLS habilitado e
deny-by-default (nenhuma policy nesta etapa). O seed segue sem inserir dados
funcionais, e o frontend permanece independente (localStorage segue como
persistência funcional ativa).

## Pré-requisitos (onboarding técnico)

Em uma máquina compatível, é necessário apenas:

- **Docker Desktop** instalado e em execução, com containers Linux (no Windows,
  backend WSL 2 conforme os requisitos do Docker Desktop), ou runtime com API
  Docker compatível suportado pela CLI.
- **Node.js 24 LTS** (20 ou superior basta para a CLI; 24 LTS mantém
  compatibilidade com o React/Vite e o CI deste repositório) e **npm/npx**
  disponíveis, com acesso à internet no primeiro uso (download da CLI e das
  imagens oficiais).
- Portas locais livres: **54321** (API), **54322** (PostgreSQL) e **54323**
  (Studio). A configuração reserva **54320** para o banco temporário de diff.

Nada mais é pré-requisito: **não** é necessária conta no Supabase, login/link,
configuração manual de tabelas no dashboard, projeto remoto, credenciais ou
dados reais. Tudo que o rebuild precisa está versionado neste diretório
(`config.toml`, `migrations/` e `seed.sql`).

A CLI é fixada em **2.116.0** em todos os comandos. O npx usa seu cache de
ferramentas; não adiciona a CLI ou o cliente Supabase ao package.json/lockfile
da aplicação.

## Comandos oficiais mínimos

Execute na raiz do repositório, com Docker em execução. Em um clone existente,
não execute `init` novamente: a configuração já está versionada.

```sh
docker version
npx --yes supabase@2.116.0 --version
npx --yes supabase@2.116.0 start
npx --yes supabase@2.116.0 status
```

O primeiro start baixa imagens e pode demorar. Após sucesso, confira o `status`;
o Studio fica em http://127.0.0.1:54323 e a API em http://127.0.0.1:54321. São
serviços de desenvolvimento local; não publique essas portas na internet. O
PostgreSQL pode conter schemas internos da distribuição Supabase; isso não
representa criação de tabelas do domínio Virtus ou implementação de Auth/RLS.

### Verificar o estado final do PostgreSQL

```sh
docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -X \
  -c "select version from supabase_migrations.schema_migrations order by 1" \
  -c "select tablename from pg_tables where schemaname='public' order by 1" \
  -c "select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='set_updated_at'"
```

Estado esperado ao final da F2-02:

- três migrations registradas (`20260906185540`, `20260906201856` e
  `20260906203358`);
- no schema `public`, somente as tabelas da F2-01/F2-02 — `organizations`,
  `user_profiles` e `user_organization_memberships` — todas com RLS habilitado e
  sem policies (deny-by-default);
- a função técnica `set_updated_at` presente (foundation da F1-03);
- o serviço Auth local habilitado: `auth.users` existe e é referenciado por
  `user_profiles` (FK `fk_user_profiles_auth_users`, `ON DELETE RESTRICT`);
- `user_organization_memberships` relaciona `user_profiles` e `organizations`
  por UUID (FKs `ON DELETE RESTRICT`) com unique por par usuário/organização.

O nome do container deriva do `project_id` (`supabase_db_<project_id>`); para
descobri-lo, use `docker ps --format '{{.Names}}'`.

## Rebuild completo e reprodutibilidade (F1-06)

Fluxo oficial validado para destruir e recriar o ambiente local do zero usando
somente o conteúdo versionado:

```sh
# 1) destruir o ambiente local (containers + volumes de dados)
npx --yes supabase@2.116.0 stop --no-backup

# 2) recriar do zero: o start inicializa o banco e aplica migrations em ordem
#    e o seed automaticamente
npx --yes supabase@2.116.0 start

# 3) rebuild determinístico do banco (migrations + seed); pode ser repetido
npx --yes supabase@2.116.0 db reset

# 4) verificar o estado final (comando da seção anterior)
```

`stop --no-backup` remove containers e volumes de dados do projeto (a forma
oficial de apagar o estado local). `db reset` recria o banco do zero aplicando as
migrations em ordem e depois o seed, sem intervenção manual. Nenhum passo
depende de configuração manual no Supabase Dashboard, de dados reais ou de
segredos.

## Seed de desenvolvimento (F1-05)

O seed sintético (`supabase/seed.sql`) é reaplicado automaticamente a cada
rebuild do banco local (`start` a partir de estado limpo ou `db reset`). O
resultado é determinístico — reconstruções sucessivas produzem o mesmo estado
técnico. O seed atual não insere dados funcionais (as migrations da F2 criam
apenas estrutura; nenhum dado de domínio é inserido nesta fase) e não cria
entidades apenas para conter dados; contém somente um invariante técnico que
confirma a aplicação das migrations.

Para parar sem solicitar descarte dos dados locais:

```sh
npx --yes supabase@2.116.0 stop
```

Não use login, link, db push, deploy ou integração GitHub ↔ Supabase. Não há
vínculo com virtus-team-dev. O `project_id` é apenas um identificador local para
distinguir containers, não uma referência a projeto hospedado.

## Organizations e perfis de usuário (F2-01)

A F2-01 (Issue #68) criou as primeiras entidades funcionais do domínio sobre a
foundation da F1-03:

- `public.organizations` — organização, raiz do requisito multi-organização; UUID
  imutável, metadados mínimos (`name`) e colunas técnicas (`created_at`,
  `updated_at`, `version`); sem `organization_id` (é a própria raiz) e sem
  unicidade de negócio nesta etapa (decisão de domínio futura);
- `public.user_profiles` — perfil interno do usuário, ligado 1:1 a `auth.users`
  (`id` = mesmo uuid da identidade de autenticação); nenhuma senha/credencial é
  duplicada (permanecem no Supabase Auth); `status` interno (`active`/`disabled`)
  preparado para a evolução da F2-07, sem fluxo de desativação nesta etapa; sem
  `organization_id` (a participação em organizações virá via memberships, F2-02);
- RLS habilitado nas duas tabelas, deny-by-default: nenhuma policy é criada nesta
  etapa (não há fluxo autenticado nem membership que a justifique; policies
  restritivas entrarão em fases posteriores como novas migrations aditivas);
- Auth local habilitado no `config.toml` apenas para fornecer `auth.users`. O
  frontend permanece intacto: nenhum fluxo foi migrado e o localStorage segue
  como persistência funcional.

## Memberships usuário-organização (F2-02)

A F2-02 (Issue #69) criou `public.user_organization_memberships`, relacionando o
perfil interno (`user_profiles`) à organização (`organizations`) por UUID, sem
exigir colaborador:

- uma linha por par usuário/organização (constraint unique por par, em qualquer
  status): unicidade coerente do membership ativo; desativação/reativação no
  lugar, preservando `created_at` e histórico (F2-07);
- `status` (`active`/`disabled`) e colunas técnicas conforme F1-02; FKs com
  `ON DELETE RESTRICT` (padrão F1-02), índice por FK em `organization_id`;
- `collaborator_id` NÃO é criado nesta etapa: a tabela de colaboradores ainda
  não existe, e uma coluna uuid solta sem FK seria dependência artificial; o
  vínculo opcional entrará por migration aditiva quando Collaborator existir
  (registrado na própria migration);
- RLS habilitado e deny-by-default, sem policies — mesmo padrão da F2-01;
  nenhuma role/capability, estrutura organizacional ou fluxo de login/UI.

## Aplicação independente

O frontend continua iniciando com `npm run dev`, mesmo sem Docker ou Supabase.
localStorage permanece a única persistência funcional. Não há alteração de
adapters, configuração de URL da aplicação, autenticação, UI ou regras de
negócio. Não é necessário preencher VITE_PUBLIC_API_URL para usar esta
infraestrutura.

## Arquivos seguros

Versione somente configuração pública e documentação. `.branches` e `.temp` são
ignorados pela configuração oficial, assim como arquivos locais de ambiente.
Nunca copie saída de status, credenciais geradas, tokens, senhas ou arquivos de
chaves para commits, exemplos ou PRs. Nenhuma credencial real é necessária aqui.
Não habilite provedores externos ou adicione segredos a variáveis `VITE_*`.

## Validação executada (F1-06)

Rebuild completo e reprodutibilidade validados em 2026-09-06 nesta máquina
(Docker Desktop 29.7.2; CLI Supabase 2.116.0 via npx; PostgreSQL 17.6):

- `stop --no-backup`: containers parados e volumes de dados do projeto removidos
  (estado local limpo).
- `start` a partir do estado limpo: banco criado do zero; log registrou
  `Applying migration 20260906185540_foundation.sql...` e
  `Seeding data from supabase/seed.sql...` automaticamente.
- Duas execuções adicionais de `db reset`: migrations + seed reaplicados sem
  intervenção.
- Estado final idêntico nas três reconstruções: uma migration registrada, função
  técnica `set_updated_at` presente e zero tabelas no schema `public` (nenhuma
  entidade funcional do Virtus).
- Ambiente parado e removido ao final; nenhuma conexão remota, credencial ou
  dado real envolvido. A limitação de runtime registrada na F1-01 (Docker
  ausente no ambiente daquele agente) foi superada por estas validações.

## Validação executada (F2-01)

Migration e rebuild validados em 2026-09-06 nesta máquina (Docker Desktop
29.7.2; CLI Supabase 2.116.0 via npx; PostgreSQL 17.6):

- rebuild do zero (`stop --no-backup` + `start`) e `db reset`: migrations
  aplicadas em ordem — `20260906185540_foundation.sql` e depois
  `20260906201856_organizations_user_profiles.sql` — e seed reaplicado
  automaticamente, sem intervenção (duas reconstruções limpas);
- schema verificado: somente `organizations` e `user_profiles` no schema
  `public`; colunas, tipos e defaults conforme F1-02 (`uuid`, `timestamptz`,
  `version integer`); função `set_updated_at` e triggers presentes;
- vínculo com Auth: FK `fk_user_profiles_auth_users` → `auth.users(id)` com
  `ON DELETE RESTRICT`; perfil só é criado para uuid existente em `auth.users`
  (violação de FK rejeitada; delete de `auth.users` com perfil referenciando é
  bloqueado);
- RLS habilitado nas duas tabelas e zero policies; deny-by-default comprovado
  com privilégios concedidos a `authenticated`: SELECT retorna 0 linhas e INSERT
  é negado (`new row violates row-level security policy`);
- ausência de colunas de senha/secret/token confirmada por varredura; nenhuma
  entidade fora do escopo (memberships, colaboradores etc.) criada; dados
  sintéticos de validação removidos ao final; nenhuma conexão remota,
  credencial ou dado real envolvido.

## Validação executada (F2-02)

Migration e rebuild validados em 2026-09-06 nesta máquina (Docker Desktop
29.7.2; CLI Supabase 2.116.0 via npx; PostgreSQL 17.6):

- rebuild do zero (`stop --no-backup` + `start`) e `db reset`: as três
  migrations aplicadas em ordem — `20260906185540_foundation.sql`,
  `20260906201856_organizations_user_profiles.sql` e
  `20260906203358_user_organization_memberships.sql` — e seed reaplicado
  automaticamente, sem intervenção (duas reconstruções limpas);
- schema verificado: somente `organizations`, `user_profiles` e
  `user_organization_memberships` no schema `public`; colunas, tipos e defaults
  conforme F1-02 (`uuid`, `timestamptz`, `version integer`); trigger de
  `updated_at` presente;
- vínculos: FKs da membership para `user_profiles` e `organizations` com
  `ON DELETE RESTRICT`; índice por FK em `organization_id`; constraint unique
  por par usuário/organização (cobre a FK de `user_profile_id`);
- comportamentos comprovados: membership sem colaborador é válida; o mesmo
  usuário participa de duas organizações; duplicidade do par é rejeitada; FKs
  rejeitam uuids inexistentes; check de status rejeita valores fora do domínio;
  delete de organização/perfil com membership referenciando é bloqueado
  (RESTRICT); `updated_at` é movimentado na transição de status;
- RLS habilitado nas três tabelas e zero policies no schema `public`;
  deny-by-default comprovado com privilégios concedidos a `authenticated`:
  SELECT retorna 0 linhas e INSERT é negado (`new row violates row-level
  security policy`);
- sem coluna `collaborator_id` nesta etapa (tabela de colaboradores ainda não
  existe — decisão registrada na migration); varredura sem colunas
  secret-like; dados sintéticos de validação removidos ao final; nenhuma
  conexão remota, credencial ou dado real envolvido.

Referências: [CLI oficial](https://supabase.com/docs/guides/local-development/cli/getting-started),
[configuração](https://supabase.com/docs/guides/local-development/cli/config) e
[Docker Desktop no Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
