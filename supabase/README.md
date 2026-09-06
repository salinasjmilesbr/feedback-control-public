# Supabase local — desenvolvimento (F1-01 a F1-06)

Infraestrutura local do Supabase para o Virtus Team, versionada e reconstruível
integralmente a partir do repositório — sem configuração manual no dashboard,
sem projeto remoto, sem credenciais e sem dados reais.

Estrutura inicial gerada com `npx --yes supabase@2.116.0 init` (F1-01), reduzida
aos serviços locais necessários: PostgreSQL 17, API e Studio. Auth, Realtime,
Storage, SMTP, Edge Runtime e Analytics permanecem desabilitados. As convenções
de migrations estão em [migrations/README.md](migrations/README.md).

A F1-03 adicionou a primeira migration de foundation (sem entidades funcionais);
a F1-05 habilitou o seed sintético de desenvolvimento (`seed.sql`); a F1-06
validou o rebuild completo e a reprodutibilidade a partir de estado limpo. O
schema `public` ainda não possui tabelas do domínio Virtus: migrations e seed não
criam entidades funcionais, e o frontend permanece independente (localStorage
segue como persistência funcional ativa).

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

Estado esperado ao final da Fase 1:

- uma migration registrada (`20260906185540`);
- nenhuma tabela no schema `public`;
- a função técnica `set_updated_at` presente (foundation da F1-03).

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
técnico. O seed atual não insere dados funcionais (o schema técnico ainda não
possui tabelas de domínio) e não cria entidades apenas para conter dados;
contém somente um invariante técnico que confirma a aplicação das migrations.

Para parar sem solicitar descarte dos dados locais:

```sh
npx --yes supabase@2.116.0 stop
```

Não use login, link, db push, deploy ou integração GitHub ↔ Supabase. Não há
vínculo com virtus-team-dev. O `project_id` é apenas um identificador local para
distinguir containers, não uma referência a projeto hospedado.

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

Referências: [CLI oficial](https://supabase.com/docs/guides/local-development/cli/getting-started),
[configuração](https://supabase.com/docs/guides/local-development/cli/config) e
[Docker Desktop no Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
