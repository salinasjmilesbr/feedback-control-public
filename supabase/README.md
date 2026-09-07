# Supabase local — desenvolvimento (F1-01 a F3-04)

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
A F3-01 criou o núcleo persistente de colaboradores (`collaborators`) com
identificadores de negócio temporais (`collaborator_identifiers`) e lifecycle de
status (`collaborator_status_periods`), sem estrutura hierárquica nem posições.
A F3-02 criou os catálogos configuráveis por organização de funções
(`job_roles`) e senioridades (`seniority_levels`), independentes entre si, da
hierarquia e da autorização.
A F3-03 criou a estrutura organizacional formal — `organizational_units` (com
composição temporal pai/filho e existência própria) e `organizational_positions`
(unidade + função + senioridade opcional) — independente das pessoas que
futuramente as ocuparão e sem reporting lines.
A F3-04 criou a hierarquia formal temporal — `position_reporting_lines` — como
relações temporais entre posições (superior formal único por instante, histórico
reconstruível por data, motivo obrigatório, sem ocupante e sem inferir
hierarquia por cargo/senioridade/unidade).
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

Estado esperado ao final da F3-04 (após rebuild limpo):

- onze migrations registradas (`20260906185540`, `20260906201856`,
  `20260906203358`, `20260906205425`, `20260906230400`, `20260907000250`,
  `20260907103000`, `20260907103100`, `20260907120000`, `20260907130000` e
  `20260907140000`);
- no schema `public`, as tabelas de identidade/membership da Fase 2 —
  `organizations`, `user_profiles` e `user_organization_memberships` — as três
  tabelas de colaboradores da F3-01 — `collaborators`,
  `collaborator_identifiers` e `collaborator_status_periods` — os dois
  catálogos da F3-02 — `job_roles` e `seniority_levels` — as três tabelas da
  F3-03 — `organizational_units`, `organizational_unit_parent_periods` e
  `organizational_positions` — e a tabela da F3-04 —
  `position_reporting_lines` — todas com RLS habilitado; policies apenas nas
  tabelas de identidade (F2-03/F2-07), nenhuma policy nas demais
  (deny-by-default); nenhuma policy de escrita;
- a função técnica `set_updated_at` (F1-03), a RPC `criar_perfil_membership`
  (F2-06, SECURITY DEFINER, EXECUTE só para `service_role`) e as funções de
  integridade da F3-04
  (`enforce_position_reporting_lines_within_positions`,
  `enforce_position_reporting_lines_no_cycle` e
  `enforce_positions_close_without_open_reporting_lines`) presentes;
- a extensão `btree_gist` habilitada (F3-01) e as exclusion constraints
  `ex_collaborator_status_periods_no_overlap`,
  `ex_collaborator_identifiers_no_overlap`,
  `ex_organizational_unit_parent_periods_no_overlap` e
  `ex_position_reporting_lines_no_overlap` presentes;
- o serviço Auth local habilitado com auto-cadastro público desabilitado
  (`enable_signup = false`) e provedor de e-mail ativo: `auth.users` existe e é
  referenciado por `user_profiles` (FK `fk_user_profiles_auth_users`);
- captura local de e-mail habilitada (`[local_smtp] enabled = true`, mailpit na
  porta 54324) para recuperação de senha e convites;
- Edge Runtime habilitado (`[edge_runtime] enabled = true`) com as funções
  `convidar-usuario` (F2-06) e `gerenciar-usuario` (F2-07) — Auth Admin
  server-side; `service_role` só no runtime das funções, nunca no frontend;
- `user_organization_memberships` relaciona `user_profiles` e `organizations`
  por UUID (FKs `ON DELETE RESTRICT`) com unique por par usuário/organização;
- `collaborators` referencia `organizations` (`ON DELETE RESTRICT`);
  `collaborator_identifiers` referencia o par (id, organization_id) de
  `collaborators` via FK composta e `collaborator_status_periods` referencia
  `collaborators`;
- `job_roles` e `seniority_levels` referenciam apenas `organizations` (`ON
  DELETE RESTRICT`) com unique por `(organization_id, name)`, `status`
  `active`/`disabled`, sem coluna de ordenação/rank; recebem (aditivo) o unique
  de referência `(id, organization_id)` usado pelas FKs compostas da F3-03;
- `organizational_units` referencia `organizations` e carrega `valid_from`/
  `valid_to` (existência temporal); `organizational_unit_parent_periods`
  referencia `organizational_units` (filho e pai opcional/raiz) via FKs
  compostas com exclusão de um parent vigente por unidade;
  `organizational_positions` referencia `organizations`,
  `organizational_units`, `job_roles` e `seniority_levels` (opcional) via FKs
  compostas;
- `position_reporting_lines` referencia `organizations` e o par
  (subordinado/manager, organization_id) de `organizational_positions` via FKs
  compostas `ON DELETE RESTRICT`; `manager_position_id NOT NULL` (raiz por
  ausência de linha); `reason` obrigatório; período meio-aberto com exclusion
  de um superior vigente por subordinado; self-reporting proibido; triggers de
  validade das posições, de ciclos multi-nível (temporal, com advisory lock por
  org) e de fechamento de posição fail-closed — nenhuma FK para colaboradores/
  ocupação/reporting line futura (inexistentes).

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

## Colaboradores e lifecycle temporal (F3-01)

A F3-01 (Issue #78) criou o núcleo persistente de colaboradores da organização
sem embutir hierarquia, área, gestor direto, posição ou ocupação no cadastro da
pessoa (duas migrations aditivas sobre o estado da Fase 2):

- `public.collaborators` — identidade técnica do colaborador: UUID interno
  imutável (`gen_random_uuid()`) e `organization_id` (FK `ON DELETE RESTRICT`
  para `organizations`); núcleo mínimo (sem nome/e-mail/CPF e sem
  gestor/área/função/posição — atributos de pessoa e estrutura pertencem a
  issues futuras); timestamps/version e trigger `set_updated_at` conforme
  F1-02/F1-03;
- `public.collaborator_identifiers` — identificadores de negócio (ex.:
  matrícula/código, `business_code text`) com `valid_from`/`valid_to` (null =
  vigente). O código atual é a linha aberta; trocar código = fechar a linha e
  abrir outra, preservando histórico **sem trocar `collaborators.id`**.
  `business_code` nunca é PK; é único por organização
  (`unique (organization_id, business_code)`, sem reutilização na mesma
  organização; reuso entre organizações permitido) e não pode ter espaços nas
  bordas; a consistência entre o `organization_id` do identificador e o do
  colaborador é garantida por FK composta
  `(collaborator_id, organization_id) → collaborators(id, organization_id)`;
- `public.collaborator_status_periods` — lifecycle temporal do colaborador com
  `status text + check` (`active`/`leave`/`inactive`, mapeando
  ATIVO/LICENCA/DESLIGADO do domínio; `terminated` não usado e ESTAGIARIO é
  função da F3-02, não status), `valid_from`/`valid_to` (meio-aberto
  `[valid_from, valid_to)`, null = vigente) e check `valid_to > valid_from`;
  uma **linha do tempo única por colaborador** é garantida no banco por
  exclusion constraints (`tstzrange` + `btree_gist`): nenhuma sobreposição de
  períodos do mesmo colaborador (um único status por instante; no máximo um
  período aberto), o que torna impossíveis estados simultâneos incompatíveis
  (ex.: `active` + `leave`) e mantém o histórico não destrutivo;
- licença (`leave`) é estado do colaborador e **não** encerra posição/ocupação:
  não existe tabela de posição/ocupação nesta issue e nenhuma FK aponta para
  estrutura organizacional (F3-02/F3-03 criarão funções/senioridades e
  unidades/posições formais em issues próprias);
- exclusão física: todas as FKs com `ON DELETE RESTRICT` (padrão F1-02) —
  mudanças de lifecycle ocorrem por novos períodos/status, nunca por exclusão
  de histórico; nenhuma política de escrita existe;
- RLS habilitado e deny-by-default nas três tabelas, sem policies e sem grants
  nesta etapa (mesmo padrão das F2-01/F2-02); nenhuma policy existente foi
  alterada e Auth/membership não foram tocados (o vínculo opcional
  `collaborator_id` em `user_organization_memberships` permanece para migration
  aditiva futura);
- dados: somente sintéticos, via cenário de validação
  `supabase/validacao/01-cenario-f3-01.sql` (o `seed.sql` continua sem inserir
  dados funcionais); rebuild e validação descritos no README de `validacao/` e
  registrados na seção "Validação executada (F3-01)".

## Catálogos de funções e senioridades (F3-02)

A F3-02 (Issue #79) criou os catálogos organizacionais configuráveis de
função/cargo e senioridade, mantendo esses conceitos independentes entre si, da
posição organizacional, da hierarquia e da autorização (uma migration aditiva
sobre o estado da F3-01):

- `public.job_roles` e `public.seniority_levels` — catálogos pertencentes à
  organização (`organization_id` com FK `ON DELETE RESTRICT` para
  `organizations`), identidade técnica UUID (`gen_random_uuid()`), `name`
  (atributo mínimo de identificação/configuração; check de trim) único por
  organização (`unique (organization_id, name)`), `status`
  `active`/`disabled` (padrão F2; desativação/evolução no lugar, sem exclusão
  física), timestamps/version e trigger `set_updated_at` conforme
  F1-02/F1-03;
- separação função × senioridade: catálogos independentes, sem tabela de
  junção/restrição e sem FKs cruzadas entre eles; senioridade não é obrigatória
  e não é embutida em `job_role`; a validade de combinações (ex.: Analista +
  Pleno) será definida quando posições (F3-03) usarem os conceitos;
- ausência de hierarquia implícita: nenhuma coluna de ordenação/rank
  (`order`/`display_order`), nenhuma auto-referência/parent e nenhuma sequência
  Vivo (C-Level → VP → Diretor → Gerente Sênior etc.) codificada; Especialista
  não implica equipe/liderança e Estagiário é função válida mesmo sem
  ocorrência nos dados do piloto;
- independência de autorização: função/senioridade não concedem capability e
  não há vínculo com Auth/membership (capabilities/scopes são da Fase 4);
- multi-organização: cada organização configura seus próprios catálogos
  (subconjuntos e combinações diferentes); o mesmo nome pode existir em
  organizações diferentes;
- RLS habilitado e deny-by-default nas duas tabelas, sem policies e sem grants
  (mesmo padrão F2-01/F2-02/F3-01); nenhuma policy existente foi alterada;
- dados: somente sintéticos, via cenário de validação
  `supabase/validacao/01-cenario-f3-02.sql` (os oito conceitos do piloto entram
  apenas como categorias sintéticas de validação; o `seed.sql` continua sem
  inserir dados funcionais); rebuild e validação descritos no README de
  `validacao/` e registrados na seção "Validação executada (F3-02)".

## Estrutura organizacional formal — unidades e posições (F3-03)

A F3-03 (Issue #80) modelou unidades e posições formais independentemente das
pessoas que futuramente as ocuparão, sem depender de sequência fixa de cargos
ou níveis (uma migration aditiva sobre o estado da F3-02):

- `public.organizational_units` — unidade formal da organização (`name` único
  por organização, UUID técnico, sem níveis/cargos codificados); existência
  temporal na própria entidade (`valid_from` obrigatório, `valid_to` null =
  vigente, `valid_to > valid_from` quando encerrada; encerramento preserva a
  linha/UUID — reativação após encerramento = nova unidade, decisão
  documentada);
- `public.organizational_unit_parent_periods` — relação temporal de composição
  pai/filho entre unidades (filho, pai null = raiz, `valid_from`/`valid_to`);
  exclusion constraint garante no máximo um parent vigente por unidade em cada
  instante; mudança de parent não recria a unidade e o histórico de
  reestruturações é integral; auto-parent proibido; ciclos multi-nível são
  validados pela aplicação (limitação documentada, sem trigger recursivo nesta
  fase); NÃO é reporting line entre posições;
- `public.organizational_positions` — posição formal vinculada a unidade +
  `job_role` + `seniority_level` opcional (null válido), com existência temporal
  própria (`valid_from`/`valid_to`); posição existe sem ocupante (posição vaga
  é o estado natural; occupation/reporting line são issues posteriores);
  múltiplas posições com a mesma combinação são ocorrências formais distintas
  (sem unique natural); sem `collaborator_id`, sem name/code próprios;
- integridade multi-organização declarativa: FKs compostas
  `(ref_id, organization_id) → (id, organization_id)` para unidades (filho/pai),
  posições→unidade/função/senioridade, com unique de referência aditiva em
  `job_roles`/`seniority_levels` (ALTER aditivo; sem mudança de semântica);
- independência de cargo e hierarquia: função/senioridade não determinam a
  posição na árvore; sem rank/sequência fixa; duas posições com o mesmo
  `job_role` podem existir em partes/alturas diferentes; Especialista sem
  equipe e Gerente → Analista sem Coordenador intermediário são representáveis;
- RLS habilitado e deny-by-default nas três tabelas, sem policies e sem grants
  (mesmo padrão das fases anteriores); nenhuma policy existente foi alterada;
- dados: somente sintéticos, via cenário de validação
  `supabase/validacao/01-cenario-f3-03.sql` (o `seed.sql` continua sem inserir
  dados funcionais); rebuild e validação descritos no README de `validacao/` e
  registrados na seção "Validação executada (F3-03)".

## Hierarquia formal temporal — reporting lines entre posições (F3-04)

A F3-04 (Issue #81) representou a cadeia hierárquica formal por relações
temporais entre `organizational_positions`, sem inferir hierarquia por
collaborator, cargo, senioridade, unidade, nome, rank ou sequência fixa (uma
migration aditiva sobre o estado da F3-03):

- `public.position_reporting_lines` — relação "subordinado → superior formal"
  entre posições da MESMA organização; `manager_position_id NOT NULL` (posição
  sem superior/raiz = AUSÊNCIA de linha vigente; gaps são permitidos);
  `reason` obrigatório (texto livre normalizado) e `valid_from`/`valid_to`
  meio-aberto (null = vigente; `valid_to > valid_from`); mudanças fecham a
  relação anterior e criam nova, nunca reescrevem o passado;
- superior único: exclusion constraint por subordinado impede dois superiores
  simultâneos; self-reporting proibido por check;
- integridade temporal: trigger valida que o período da linha está contido na
  validade de subordinate e manager (write-time); o encerramento de posição é
  fail-closed (exige fechar antes as linhas que a envolvam; trigger em
  `organizational_positions` rejeita deixar linhas fora da nova validade, sem
  correção automática);
- ciclos: trigger recursivo temporal (analisa as relações que se sobrepõem ao
  período da linha) + `pg_advisory_xact_lock` por organização para serializar
  escritas do mesmo tenant (estratégia de concorrência documentada);
- tenant integrity declarativa: FKs compostas
  `(posição, organization_id) → organizational_positions(id, organization_id)`
  (unique de referência aditiva) — nenhuma relação cross-organization;
- auditoria/autor: sem coluna de autor nesta fase (apenas metadados técnicos +
  `reason`); a autoria será registrada pelo modelo transversal de auditoria
  quando existir (limitação documentada);
- RLS habilitado e deny-by-default na tabela nova, sem policies e sem grants;
  nenhuma policy existente alterada;
- dados: somente sintéticos, via cenário de validação
  `supabase/validacao/01-cenario-f3-04.sql` (o `seed.sql` continua sem inserir
  dados funcionais); rebuild e validação descritos no README de `validacao/` e
  registrados na seção "Validação executada (F3-04)".

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

## Validação executada (F3-01)

Migrations, schema, constraints, triggers e RLS validados em 2026-09-06 nesta
máquina (Docker Desktop 29.7.2; CLI Supabase 2.116.0 via npx; PostgreSQL 17.6;
Node 24):

- rebuild limpo: `supabase start` a partir de estado limpo e duas execuções
  adicionais de `db reset` — as oito migrations aplicadas em ordem (foundation,
  F2-01, F2-02, F2-03, F2-06, F2-07, `20260907103000_enable_btree_gist` e
  `20260907103100_collaborators_identifiers_status_periods`) e o seed
  reaplicado automaticamente, sem intervenção (três reconstruções limpas);
- schema verificado: somente as seis tabelas esperadas no schema `public`
  (`organizations`, `user_profiles`, `user_organization_memberships`,
  `collaborators`, `collaborator_identifiers`, `collaborator_status_periods`);
  extensão `btree_gist` presente; colunas, tipos e defaults conforme F1-02;
  triggers `trg_*_updated_at` presentes;
- constraints verificadas: PKs por `id` (uuid com `gen_random_uuid()`),
  `uq_collaborators_id_organization` (alvo da FK composta),
  `uq_collaborator_identifiers_organization_code` (código de negócio único por
  organização), checks de domínio (`active`/`leave`/`inactive`) e de validade
  temporal (`valid_to > valid_from`), exclusion constraints
  `ex_collaborator_status_periods_no_overlap` e
  `ex_collaborator_identifiers_no_overlap` (gist/`tstzrange`), FKs todas
  `ON DELETE RESTRICT` (incluindo a FK composta
  `(collaborator_id, organization_id) → collaborators(id, organization_id)`
  que garante consistência de organização entre identificador e colaborador);
- comportamento comprovado (cenário + asserts em
  `supabase/validacao/01-cenario-f3-01.sql` e `02-validar-f3-01.sql`): UUID
  interno recebido; `business_code` não é PK; troca histórica de código não
  troca `collaborator.id`; isolamento por `organization_id`; mesmo código em
  organizações diferentes permitido e duplicidade na mesma organização
  rejeitada; histórico ACTIVE → LEAVE → ACTIVE preservado; um único período
  aberto por colaborador; licença (`leave`) sem efeito sobre posição/ocupação
  (inexistentes); períodos inválidos, status fora do domínio, sobreposições,
  código com espaços e inconsistência de organização rejeitados no banco;
  exclusão física de org/colaborador com histórico bloqueada (RESTRICT);
  `version`/`updated_at` mantidos pelo trigger técnico; **45 verificações
  [PASS], 0 falhas** (execução repetida após o segundo `db reset`, mesmo
  resultado);
- RLS: habilitado nas três tabelas F3-01 com zero policies e zero grants;
  deny-by-default comprovado como `authenticated` (leituras retornam 0 linhas,
  INSERT negado por row-level security, UPDATE/DELETE afetam zero linhas); RLS
  das tabelas F2 e policies existentes (3) inalterados; nenhuma policy de
  escrita adicionada;
- ausência de entidades/campos antecipados confirmada (nada de
  gestor/área/posição/ocupação/hierarquia/função/senioridade); dados
  sintéticos do cenário removidos ao final (banco local limpo); varredura sem
  colunas secret-like e sem credenciais novas;
- suíte completa local: `npm test` (556 testes em 50 arquivos — aprovados),
  `npm run build` (tsc + vite) aprovado, `npm run lint` aprovado e
  `git diff --check` aprovado;
- nenhuma conexão ao Supabase remoto, credencial ou dado real envolvido.

## Validação executada (F3-02)

Migrations, schema, constraints, triggers e RLS validados em 2026-09-06 nesta
máquina (Docker Desktop 29.7.2; CLI Supabase 2.116.0 via npx; PostgreSQL 17.6;
Node 24):

- rebuild limpo: `supabase start` a partir de estado limpo e duas execuções
  adicionais de `db reset` — as nove migrations aplicadas em ordem (foundation,
  F2-01, F2-02, F2-03, F2-06, F2-07, `20260907103000_enable_btree_gist`,
  `20260907103100_collaborators_identifiers_status_periods` e
  `20260907120000_job_roles_seniority_levels`) e o seed reaplicado
  automaticamente, sem intervenção (três reconstruções limpas);
- schema verificado: somente as oito tabelas esperadas no schema `public`
  (identidade/membership da F2 + F3-01 + `job_roles` e `seniority_levels`);
  colunas, tipos e defaults conforme F1-02; triggers `trg_*_updated_at`
  presentes;
- constraints verificadas: PKs por `id` (uuid com `gen_random_uuid()`), uniques
  `uq_job_roles_organization_name` e `uq_seniority_levels_organization_name`
  (nome único por organização), checks de trim e de status
  (`active`/`disabled`), FKs `fk_job_roles_organizations` e
  `fk_seniority_levels_organizations` com `ON DELETE RESTRICT`, zero FKs
  referenciando os catálogos e zero FKs cruzadas entre eles;
- comportamento comprovado (cenário + asserts em
  `supabase/validacao/01-cenario-f3-02.sql` e `02-validar-f3-02.sql`):
  job_role e senioridade são entidades distintas; catálogos pertencem à
  organização correta com configurações independentes (Alfa: oito conceitos do
  piloto + item desativado e senioridades Junior/Pleno/Senior; Beta: subconjunto
  diferente e somente Senior); mesmo nome permitido entre organizações e
  duplicidade na mesma organização rejeitada; Analista + Junior/Pleno/Senior
  representável como função + senioridades independentes (sem degraus/nomes
  compostos); Especialista sem equipe/liderança; Estagiário representável sem
  ocorrência piloto; desativação (`disabled`) preserva registro; nome com
  espaços, status fora do domínio, organização inexistente e exclusão física de
  org com catálogos rejeitados no banco; `version`/`updated_at` mantidos pelo
  trigger técnico; **43 verificações [PASS], 0 falhas** (execução repetida após
  o segundo `db reset`, mesmo resultado);
- ausência de hierarquia implícita confirmada: nenhuma coluna de
  ordenação/rank/code/parent nos catálogos, nenhuma auto-referência, nenhuma
  sequência Vivo codificada e nenhum vínculo com Auth/membership/autorização;
- RLS: habilitado em `job_roles` e `seniority_levels` com zero policies e zero
  grants; deny-by-default comprovado como `authenticated` (leituras retornam 0
  linhas, INSERT negado por row-level security, UPDATE/DELETE afetam zero
  linhas); RLS das tabelas F2/F3-01 e policies existentes (3) inalterados;
- F3-01 intacta: `collaborators` preservada (núcleo mínimo), constraints de
  lifecycle/identificadores presentes e nenhuma tabela/coluna de posição/
  reporting line/capability antecipada; dados sintéticos do cenário removidos
  ao final (banco local limpo); varredura sem colunas secret-like e sem
  credenciais novas;
- suíte completa local: `npm test` (556 testes em 50 arquivos — aprovados),
  `npm run build` (tsc + vite) aprovado, `npm run lint` aprovado e
  `git diff --check` aprovado;
- nenhuma conexão ao Supabase remoto, credencial ou dado real envolvido.

## Validação executada (F3-03)

Migrations, schema, constraints, triggers e RLS validados em 2026-09-07 nesta
máquina (Docker Desktop 29.7.2; CLI Supabase 2.116.0 via npx; PostgreSQL 17.6;
Node 24):

- rebuild limpo: `supabase start` a partir de estado limpo e duas execuções
  adicionais de `db reset` — as dez migrations aplicadas em ordem (foundation,
  F2-01, F2-02, F2-03, F2-06, F2-07, `20260907103000_enable_btree_gist`,
  `20260907103100_collaborators_identifiers_status_periods`,
  `20260907120000_job_roles_seniority_levels` e
  `20260907130000_organizational_units_positions`) e o seed reaplicado
  automaticamente, sem intervenção (três reconstruções limpas);
- schema verificado: somente as onze tabelas esperadas no schema `public`
  (identidade/membership da F2 + F3-01 + F3-02 + `organizational_units`,
  `organizational_unit_parent_periods` e `organizational_positions`); colunas,
  tipos e defaults conforme F1-02; triggers `trg_*_updated_at` presentes;
- constraints verificadas: 18 constraints nas tabelas F3-03 (PKs por UUID,
  uniques de unidade por nome e de referência `(id, organization_id)`, checks
  de trim/validade, FKs compostas com `ON DELETE RESTRICT` e exclusion
  `ex_organizational_unit_parent_periods_no_overlap`); unique de referência
  aditiva `(id, organization_id)` em `job_roles`/`seniority_levels`;
  zero dependências referenciando `organizational_positions` (sem occupation/
  reporting line);
- comportamento comprovado (cenário + asserts em
  `supabase/validacao/01-cenario-f3-03.sql` e `02-validar-f3-03.sql`): unidade
  e posição existem sem ocupante; posições vagas válidas; posição referencia
  unidade/job_role/seniority (null válido); unidade sem posições e unidade/
  posição encerradas preservadas (`valid_to`); parent temporal com histórico
  (mudança de parent sem recriar unidade; raiz por parent null; expansão acima
  e nível intermediário posterior); Especialista sem equipe; Gerente + Analista
  na mesma unidade sem Coordenador; mesmo job_role em alturas diferentes;
  posições idênticas como ocorrências distintas; **56 verificações [PASS],
  0 falhas** (execução repetida após o segundo `db reset`, mesmo resultado);
- integridade/tenant: FKs compostas rejeitam unidade/função/senioridade e
  parents de outra organização; sobreposição de parent, auto-parent, nome
  duplicado de unidade na mesma org (mesmo nome entre orgs permitido), nomes
  com espaços, períodos inválidos e exclusão física de org com estrutura são
  rejeitados no banco; `version`/`updated_at` mantidos pelo trigger técnico;
- RLS: habilitado nas três tabelas F3-03 com zero policies e zero grants;
  deny-by-default comprovado como `authenticated` (leituras retornam 0 linhas,
  INSERT negado por row-level security, UPDATE/DELETE afetam zero linhas); RLS
  das tabelas F2/F3-01/F3-02 e policies existentes (3) inalterados;
- F3-01 e F3-02 intactas (colunas preservadas; alterações apenas aditivas);
  nenhuma tabela/coluna de occupation/reporting line/gestor/rank/colegiado/
  dotted line antecipada; dados sintéticos do cenário removidos ao final (banco
  local limpo); varredura sem colunas secret-like e sem credenciais novas;
- suíte completa local: `npm test` (556 testes em 50 arquivos — aprovados),
  `npm run build` (tsc + vite) aprovado, `npm run lint` aprovado e
  `git diff --check` aprovado;
- limitação documentada: ciclos multi-nível na árvore de unidades não são
  detectados por trigger recursivo nesta issue (validação pela aplicação;
  auto-parent e sobreposição de parent são impedidos no banco);
- nenhuma conexão ao Supabase remoto, credencial ou dado real envolvido.

## Validação executada (F3-04)

Migrations, schema, constraints, triggers e RLS validados em 2026-09-07 nesta
máquina (Docker Desktop 29.7.2; CLI Supabase 2.116.0 via npx; PostgreSQL 17.6;
Node 24):

- rebuild limpo: `supabase start` a partir de estado limpo e duas execuções
  adicionais de `db reset` — as onze migrations aplicadas em ordem (foundation,
  F2-01, F2-02, F2-03, F2-06, F2-07, `20260907103000_enable_btree_gist`,
  `20260907103100_collaborators_identifiers_status_periods`,
  `20260907120000_job_roles_seniority_levels`,
  `20260907130000_organizational_units_positions` e
  `20260907140000_position_reporting_lines`) e o seed reaplicado
  automaticamente, sem intervenção (três reconstruções limpas);
- schema verificado: somente as doze tabelas esperadas no schema `public`
  (identidade/membership da F2 + F3-01 + F3-02 + F3-03 + F3-04); colunas, tipos
  e defaults conforme F1-02; colunas de `position_reporting_lines` exatas
  (sem collaborator_id/occupation/autor);
- constraints verificadas: PK por UUID, FKs compostas `ON DELETE RESTRICT`
  (organizations e o par posição/organização), checks de `reason`, `valid_to` e
  `not_self`, exclusion `ex_position_reporting_lines_no_overlap` (um superior
  vigente por subordinado); unique de referência aditiva
  `uq_organizational_positions_id_organization`; zero dependências referenciando
  `position_reporting_lines`;
- triggers/funções: `set_updated_at`, `enforce_position_reporting_lines_
  within_positions` (período contido na validade das posições),
  `enforce_position_reporting_lines_no_cycle` (ciclos multi-nível recursivos
  temporais com `pg_advisory_xact_lock` por organização) e
  `enforce_positions_close_without_open_reporting_lines` (fechamento de posição
  fail-closed) presentes e exercitados;
- comportamento comprovado (cenário + asserts em
  `supabase/validacao/01-cenario-f3-04.sql` e `02-validar-f3-04.sql`): raiz por
  ausência de linha (manager nunca null); um superior vigente por subordinado;
  troca de superior fecha + abre (histórico preservado); reconstrução da cadeia
  para datas históricas diferentes; Analista→Gerente direto sem Coordenador;
  Gerente→Gerente, Gerente→Gerente Sênior, Diretor→Diretor; mesmo job_role em
  alturas diferentes; Especialista sem subordinados; `reason` não vazio; **42
  verificações [PASS], 0 falhas** (execução repetida após o segundo `db reset`,
  mesmo resultado);
- rejeições comprovadas: dois superiores simultâneos, self-reporting, ciclo
  multi-nível, cross-organization (subordinate e manager), `reason` vazio,
  período antes da existência das posições, linha aberta além do encerramento e
  encerramento de posição com linhas abertas (fail-closed, sem auto-correção);
- RLS: habilitado em `position_reporting_lines` com zero policies e zero grants;
  deny-by-default comprovado como `authenticated` (leituras retornam 0 linhas,
  INSERT negado, UPDATE/DELETE afetam zero linhas); RLS das tabelas
  F2/F3-01/02/03 e policies existentes (3) inalterados;
- F3-01/F3-02/F3-03 intactas (colunas preservadas; alterações apenas aditivas);
  nenhuma tabela/coluna de occupation/dotted line/colegiado/substituição
  antecipada; dados sintéticos do cenário removidos ao final (banco local
  limpo); varredura sem colunas secret-like e sem credenciais novas;
- suíte completa local: `npm test` (556 testes em 50 arquivos — aprovados),
  `npm run build` (tsc + vite) aprovado, `npm run lint` aprovado e
  `git diff --check` aprovado;
- limitações documentadas: (a) sem coluna de autor nesta fase (auditoria de
  negócio virá com o modelo transversal de auditoria); (b) ciclos usam trigger
  temporal com advisory lock por organização — o caminho de escrita futuro deve
  manter o mesmo lock ou isolamento SERIALIZABLE; (c) correção retroativa
  excepcional de histórico não é implementada nesta issue;
- nenhuma conexão ao Supabase remoto, credencial ou dado real envolvido.
