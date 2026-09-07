# Supabase local — desenvolvimento (F1-01 a F2-10)

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
por UUID, sem exigir colaborador), a F2-03 introduziu login/logout reais com
Supabase Auth (policies mínimas de leitura via `auth.uid()`), a F2-04 protegeu as
rotas funcionais, a F2-05 adicionou recuperação/redefinição de senha, a F2-06
adicionou o convite administrativo via Edge Function (Auth Admin server-side) e
a F2-07 adicionou desativação/reativação de usuário com revogação de sessão.
O auto-cadastro público permanece desabilitado; o seed segue sem inserir dados
funcionais, e o frontend mantém o localStorage como persistência funcional dos
domínios (as F2-03 a F2-07 alteram somente identidade/sessão).

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

Estado esperado ao final da F2-07:

- seis migrations registradas (`20260906185540`, `20260906201856`,
  `20260906203358`, `20260906205425`, `20260906230400` e `20260907000250`);
- no schema `public`, somente as tabelas da F2-01/F2-02 — `organizations`,
  `user_profiles` e `user_organization_memberships` — com RLS habilitado; as
  policies de leitura da F2-03 (`user_organization_memberships_select_own`,
  `organizations_select_via_membership`) e `user_profiles_select_own` agora
  exigindo `status = 'active'` (F2-07); nenhuma policy de escrita;
- a função técnica `set_updated_at` (F1-03) e a RPC `criar_perfil_membership`
  (F2-06, SECURITY DEFINER, EXECUTE só para `service_role`) presentes;
- o serviço Auth local habilitado com auto-cadastro público desabilitado
  (`enable_signup = false`) e provedor de e-mail ativo: `auth.users` existe e é
  referenciado por `user_profiles` (FK `fk_user_profiles_auth_users`);
- captura local de e-mail habilitada (`[local_smtp] enabled = true`, mailpit na
  porta 54324) para recuperação de senha e convites;
- Edge Runtime habilitado (`[edge_runtime] enabled = true`) com as funções
  `convidar-usuario` (F2-06) e `gerenciar-usuario` (F2-07) — Auth Admin
  server-side; `service_role` só no runtime das funções, nunca no frontend;
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

## Autenticação real (F2-03)

A F2-03 (Issue #70) introduz login/logout reais com Supabase Auth, sem migrar
os domínios do localStorage:

- login por e-mail e senha via `signInWithPassword` e logout explícito via
  `signOut`; sessão centralizada no contexto `AuthProvider` (bootstrap/
  restauração/assinatura de `onAuthStateChange` em um único ponto);
- resolução de identidade estritamente por `auth.uid()`: `user_profiles` → o
  próprio perfil; `user_organization_memberships` → as próprias memberships
  ativas; `organizations` → somente as alcançáveis por membership ativa;
- auth user sem perfil interno válido é erro de acesso seguro (F0-05); sem
  membership ativa, o usuário autentica mas fica sem acesso organizacional;
  múltiplas memberships são preservadas sem seleção arbitrária;
- credencial inválida é convertida para `INVALID_CREDENTIALS` (taxonomia
  F0-05), sem expor mensagens internas do Supabase; nenhuma senha é persistida
  ou logada pelo Virtus;
- policies mínimas de leitura (`user_profiles_select_own`,
  `user_organization_memberships_select_own`,
  `organizations_select_via_membership`) com grants de SELECT apenas a
  `authenticated`; nenhuma escrita via RLS nesta etapa; auto-cadastro público
  desabilitado (`enable_signup = false`);
- a simulação DEV existente NÃO é removida nesta etapa; fora de DEV não há
  fallback silencioso para identidade simulada. Configuração Supabase ausente
  deixa a autenticação indisponível (em DEV a simulação segue funcionando).

## Recuperação de senha (F2-05)

A F2-05 adiciona recuperação/redefinição de senha com o mecanismo oficial do
Supabase Auth (`resetPasswordForEmail` + `getSessionFromUrl` + `updateUser`),
sem duplicar o sistema de autenticação nem armazenar tokens/senhas no Virtus:

- rotas públicas `/recuperar-senha` (solicitação) e `/redefinir-senha`
  (processamento do link e definição da nova senha), fora do guard F2-04;
- mensagem de solicitação sempre neutra (não revela se o e-mail possui conta);
- token de recuperação processado exclusivamente pelo SDK (`getSessionFromUrl`),
  nunca persistido ou logado;
- captura local de e-mail habilitada via `[local_smtp] enabled = true`
  (mailpit/inbucket na porta 54324) para validar o fluxo real;
- correção de configuração: o provedor de e-mail NÃO é desabilitado (removido
  `[auth.email] enable_signup = false`); apenas `enable_signup = false` global
  mantém o auto-cadastro público desligado sem quebrar login/recuperação;
- `additional_redirect_urls` inclui a origem local do app (Vite, porta 5173)
  para os links de redefinição.

## Convite administrativo (F2-06)

A F2-06 implementa o fluxo inicial de criação/convite de usuários por e-mail
sem signup público, com Supabase Auth Admin exclusivamente server-side:

- Edge Function `supabase/functions/convidar-usuario` (Edge Runtime habilitado)
  é a única fronteira privilegiada: usa `SUPABASE_SERVICE_ROLE_KEY` do runtime
  (nunca versionada, nunca no frontend) para `inviteUserByEmail`;
- autorização server-side mínima: JWT válido (`auth.getUser`) + `auth.uid()` no
  allowlist `INVITE_ADMIN_USER_IDS` (fail-closed) + `user_profiles` ativo; a
  Fase 4 substituirá esse "seam" por capabilities;
- consistência: perfil + membership criados atomicamente pela RPC
  `criar_perfil_membership` (SECURITY DEFINER, EXECUTE só para `service_role`);
  em falha, a função compensa removendo o usuário recém-criado no Auth;
- `user_profile` continua 1:1 com `auth.users`; ADMIN pode existir sem
  colaborador (nenhum collaborator artificial); duplicidade de membership é
  rejeitada pela constraint unique;
- formulário mínimo em `/convidar-usuario` (rota protegida) apenas invoca a
  função com o JWT do usuário; a autorização real é server-side;
- auditoria: a infraestrutura de auditoria ainda não existe — contrato/pendência
  explícito para a etapa correspondente (nenhum log local/pseudo-auditoria).

## Desativação e revogação de acesso (F2-07)

A F2-07 garante que um usuário desabilitado perca acesso efetivo mesmo com uma
sessão/JWT emitida antes da desativação:

- Edge Function `gerenciar-usuario` (mesma autorização allowlist da F2-06) com
  ações `disable`/`enable`:
  - `disable` → `user_profiles.status = 'disabled'` + ban no Auth
    (`banned_until`) que invalida refresh, `getUser` e sign-in; em falha,
    compensa revertendo o status;
  - `enable` → desbane (`ban_duration = 'none'`) + `status = 'active'`; sessões
    antigas não são restauradas — exige nova autenticação;
  - nenhuma linha de perfil/membership/histórico é excluída fisicamente;
- RLS: `user_profiles_select_own` passa a exigir `status = 'active'` — um perfil
  desabilitado deixa de ser resolvido pelo próprio usuário (enforcement no
  banco, independente do frontend);
- membership desabilitada já era respeitada (resolução filtra `status='active'`
  e `organizations_select_via_membership` exige membership ativa): a
  desativação de uma membership remove o acesso àquela organização sem apagar
  outras memberships;
- frontend: `AuthProvider` revalida a sessão periodicamente (~60s) e ao focar a
  janela (`getUser` + re-resolução), entrando em estado seguro (não autenticado
  ou acesso negado) e fazendo o guard redirecionar — sem depender da expiração
  natural do JWT;
- usuário ≠ colaborador: a desativação do usuário NÃO desativa o colaborador
  vinculado (lifecycles independentes).

## Regras de sessão e expiração (F2-08)

A F2-08 aplica as regras iniciais de sessão do Virtus sem criar um segundo
sistema de autenticação — o Supabase Auth permanece o gestor da sessão
(persistência, refresh e `signOut` oficiais):

- timeout por inatividade de 60 minutos: o `AuthProvider` observa atividade
  real do usuário na janela (teclado, ponteiro, toque, rolagem) e, na cadência
  da revalidação da F2-07 (~60s) ou ao focar a janela, encerra a sessão quando
  o usuário fica inativo além do limite — exige nova autenticação;
- duração máxima persistente de 1 dia: o início da sessão deste dispositivo é
  marcado por usuário (chave `virtus.auth.inicioSessao` no `localStorage` —
  metadado de política, NUNCA credencial). Na restauração (refresh/reabertura)
  e durante o uso, sessões com mais de 1 dia não são restauradas: o
  `AuthProvider` encerra e o guard direciona ao login;
- o marcador é gravado na primeira vez que a sessão aparece no dispositivo e
  removido no logout/expiração; um novo login (ou link de recuperação) reinicia
  a janela; sem `localStorage` (modo privado/falha) a política segue em memória;
- logout explícito continua disponível (botão "Sair") e a expiração automática
  usa o mesmo `signOut` global do Supabase, de forma tolerante: se a revogação
  remota falhar (offline), o estado local ainda cai para a tela de login;
- UX: a sessão expirada vira o estado `sessaoExpirada` (motivo inatividade ou
  duração máxima), o guard redireciona a `/login` e a tela explica o motivo;
  a primeira interação no formulário reconhece o aviso e volta ao login comum;
- barreiras da F2-07 preservadas: a política roda ANTES da revalidação do
  servidor, mas nunca substitui o `getUser`/RLS — uma sessão tecnicamente
  válida continua sem contornar `user_profiles.status`/membership desabilitados;
- nenhuma senha é armazenada e não existe mecanismo próprio de
  remember-password; o `auth.jwt_expiry` local permanece o padrão (1h) e o
  refresh de token do SDK segue responsável pela renovação dentro dos limites.

## Impersonação DEV (F2-09)

A F2-09 garante que o mecanismo de simulação/impersonação (seletor de
colaboradores sintéticos do seed local) exista somente em DEV explícito e
nunca se confunda com autenticação:

- o gate central é `simulacaoDevPermitida` (DEV do Vite + ambiente
  `development`), reutilizado por `UsuarioAtualProvider`/`UsuarioAtualBar`
  (frontend) e pelo guard (F2-04); não há inferência de DEV por localhost;
- em HOMOLOG/PROD o provider não carrega colaborador simulado como identidade,
  não lê/grava o marcador local e bloqueia a troca; o seletor não é renderizado
  (a barra rotula a simulação como "Usuário atual — simulação DEV" apenas em
  DEV) — fail-closed, sem fallback simulado;
- separação conceitual: a impersonação DEV é um contexto local de visão sobre o
  seed sintético; o Supabase Auth permanece soberano — ela não altera
  `auth.uid()`, JWT ou sessão, não participa de chamadas server-side como
  autorização e não contorna RLS/segurança do servidor (nenhuma alteração de
  RLS foi necessária);
- nenhum dado real é usado no mecanismo (somente seed sintético) e nenhuma
  credencial/secret novo entrou no frontend; login/logout, recuperação,
  redefinição, guard, convite (F2-06), desativação/revogação (F2-07) e a
  política de sessão (F2-08) permanecem intactos.

## Validação integrada com múltiplas contas (F2-10)

A F2-10 encerra a Fase 2 com evidência reproduzível (somente Supabase local,
dados sintéticos) de que autenticação, perfis, memberships, organizações, RLS,
revogação e isolamento de identidade funcionam em conjunto. Artefatos em
`supabase/validacao/` (cenário SQL idempotente + runner + matriz documentada):

- ADMIN, A, B, C (sem membership), D (desabilitado no passo 8) e E (membership
  desabilitada no passo 9) com perfis/memberships/organizações sintéticas;
- runner valida `auth.uid`/sub por conta, resolução restrita ao próprio
  perfil/memberships/organizações, isolamento A↔B, usuário sem membership,
  refresh/restauração, logout/troca sem vazamento, impersonação DEV sem efeito
  server-side, desativação/reativação via Edge Function, membership desabilitada
  e signup público bloqueado;
- execução registrada nesta Issue: 36 verificações, 0 falhas (instruções e
  matriz completas no README da pasta de validação).

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

## Validação executada (F2-03)

Autenticação, resolução de identidade e RLS validados em 2026-09-06 nesta
máquina (Docker Desktop 29.7.2; CLI Supabase 2.116.0 via npx; PostgreSQL 17.6;
Node 24):

- rebuild do zero (`stop --no-backup` + `start`) e `db reset`: quatro migrations
  aplicadas em ordem — foundation, F2-01, F2-02 e F2-03
  (`20260906205425_auth_read_policies.sql`) — e seed reaplicado automaticamente
  (duas reconstruções limpas);
- RLS: três policies SELECT restritas a `authenticated`
  (`user_profiles_select_own`, `user_organization_memberships_select_own`,
  `organizations_select_via_membership`); comprovado com `request.jwt.claims`:
  o usuário lê somente o próprio perfil, as próprias memberships e as
  organizações de membership ativa; membership de outro usuário e organização
  sem membership ficam invisíveis; sem claims nada é visível; INSERT é rejeitado
  e UPDATE/DELETE afetam zero linhas (nenhuma policy de escrita);
- auto-cadastro público desabilitado: `GOTRUE_DISABLE_SIGNUP=true` no serviço
  local e chamada real a `/auth/v1/signup` retorna 422 `signup_disabled`;
- suíte local: `npm test` (470 testes em 40 arquivos, incluindo os 26 testes
  novos do módulo de auth), `npm run build` e `npm run lint` aprovados;
  `git diff --check` aprovado;
- nenhuma senha/secret/service_role no código do frontend; dados sintéticos
  removidos ao final; nenhuma conexão remota, credencial ou dado real envolvido.

Referências: [CLI oficial](https://supabase.com/docs/guides/local-development/cli/getting-started),
[configuração](https://supabase.com/docs/guides/local-development/cli/config) e
[Docker Desktop no Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
