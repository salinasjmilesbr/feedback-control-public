# F2-10 — Validação integrada: múltiplas contas e isolamento de identidade

Etapa final da Fase 2 (Issue #77). Valida, contra o **Supabase local**, que
autenticação, perfis, memberships, organizações, RLS, revogação e isolamento de
identidade funcionam em conjunto com múltiplas contas **sintéticas** — sem
alterar a arquitetura (esta etapa é de validação/evidência, não de redesenho).

## Contas e organizações sintéticas do cenário

| Identidade | UUID (fixo/local) | E-mail (sintético) | Perfil | Membership inicial |
| --- | --- | --- | --- | --- |
| ADMIN | `b0000000-…-0001` | `admin.f2-10@example.invalid` | active | Alfa (active) |
| A | `b0000000-…-000a` | `conta.a.f2-10@example.invalid` | active | Alfa (active) |
| B | `b0000000-…-000b` | `conta.b.f2-10@example.invalid` | active | Beta (active) |
| C | `b0000000-…-000c` | `conta.c.f2-10@example.invalid` | active | *(nenhuma)* |
| D | `b0000000-…-000d` | `conta.d.f2-10@example.invalid` | active → passo 8 | Beta (active) |
| E | `b0000000-…-000e` | `conta.e.f2-10@example.invalid` | active | Alfa (active → passo 9) |

Organizações: `Org Sintetica Alfa (F2-10)` (`c0000000-…-00a1`) e
`Org Sintetica Beta (F2-10)` (`c0000000-…-00b1`). Senha local de teste:
`virtus-senha-f2-10-local` (somente banco local; nenhuma credencial real).

## Como reproduzir

Requisitos: Docker Desktop, Node 18+ e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f2-10.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) exportar as variáveis locais (valores do `supabase status -o env`, sem aspas)
$envOut = npx --yes supabase@2.116.0 status -o env
$vars = @{}
foreach ($l in ($envOut -split "`n")) { if ($l -match '^([A-Z_]+)=(.*)$') { $vars[$matches[1]] = $matches[2].Trim('"') } }
$env:SUPABASE_URL              = $vars['API_URL']
$env:SUPABASE_ANON_KEY         = $vars['ANON_KEY']
$env:SUPABASE_SERVICE_ROLE_KEY = $vars['SERVICE_ROLE_KEY']

# 4) executar a validação (exit code 0 = todas as verificações passaram)
node supabase/validacao/02-validar-f2-10.mjs
```

Observações:

- o script de validação **não imprime segredos** e **não toca projeto remoto**;
- `01-cenario-f2-10.sql` insere via superuser local (equivalente a
  service_role) **sem alterar nenhuma policy RLS** — o isolamento é comprovado
  pelas consultas autenticadas do passo 4;
- ao final, o runner restaura `E` (membership active) e reativa `D`, permitindo
  reexecução sem reaplicar o SQL.

## Matriz automatizada (runner 02-validar-f2-10.mjs)

Registro da execução desta Issue (Supabase local, CLI 2.116.0, gotrue
v2.196.0): **36 verificações, 0 falhas**.

1. **ADMIN** — autentica com identidade própria (`auth.uid`/sub do JWT) e, sem
   conceito de collaborator (ainda inexistente), resolve somente o próprio
   perfil ativo; consegue invocar as Edge Functions administrativas (passos 8).
2. **Conta A** — `auth.uid` = A; resolve apenas o próprio perfil; apenas a
   membership de A (Alfa); enxerga somente Alfa; **não** enxerga Beta nem lê o
   perfil de B.
3. **Conta B** (simétrica) — `auth.uid` = B; perfil próprio; membership Beta;
   somente Beta; **não** lê perfil/memberships de A nem Alfa.
4. **C (sem membership)** — autentica como identidade válida, sem memberships
   nem organizações (nenhuma organização inventada).
5. **Estado local/impersonação DEV** — header de identidade local extra com o
   token de A não altera o que o servidor enxerga (A segue vendo apenas Alfa):
   a identidade é exclusivamente o JWT/`auth.uid`.
6. **Refresh/restauração** — refresh preserva o mesmo `auth.uid` (sub) e a
   mesma visão (Alfa) após a restauração da sessão.
7. **Logout/troca** — logout global (204) revoga o refresh token (uso posterior
   falha); login seguinte de B não herda estado/visão de A (B vê somente Beta).
8. **Usuário desabilitado (D)** — Edge Function `gerenciar-usuario` (disable)
   bane D e desativa o perfil: sign-in bloqueado, `getUser` do JWT antigo
   rejeitado, RLS impede a resolução do próprio perfil (status `active`
   exigido); B permanece intacto; `enable` restaura e novo login resolve Beta.
9. **Membership desabilitada (E)** — com perfil ativo, a desativação da
   membership remove o acesso à organização (orgs = []), a própria membership
   desabilitada permanece visível (histórico preservado) e a reexecução é
   segura (baseline restaurada).
10. **Signup público** — continua desabilitado (sem `access_token`).

## Matriz da Fase 2 (manual + automatizada, resumo)

| Etapa | Issue | Entregue por | Cobertura automatizada |
| --- | --- | --- | --- |
| F2-01 organizations/user_profiles | #68 | migrations + RLS deny-by-default | suíte Vitest + rebuild local |
| F2-02 memberships | #69 | migrations aditivas + unique por par | suíte Vitest |
| F2-03 login/logout real + policies de leitura | #70 | `src/auth/*`, migrations de policies | unit (controlador/serviço/rotas) |
| F2-04 guard de rotas | #71 | `LayoutAutenticado`/`rotasProtegidas` | unit de guard/roteamento |
| F2-05 recuperação/redefinição | #72 | fluxo oficial Supabase + mailpit | unit F2-05 + validação manual local |
| F2-06 convite administrativo | #73 | Edge Function + RPC | unit convite + validação local |
| F2-07 desativação/revogação | #74 | Edge Function + RLS status | unit F2-07 + validação local |
| F2-08 sessão/expiração | #75 | política central + marcador | unit temporal controlado |
| F2-09 impersonação DEV | #76 | gate `simulacaoDevPermitida` | unit DEV/HOMOLOG/PROD |
| F2-10 validação integrada | #77 | este diretório | runner integrado (36/36) |

## F3-01 — Colaboradores e lifecycle temporal (Issue #78)

Validação estrutural contra o **Supabase local** das migrations da F3-01
(`20260907103000_enable_btree_gist.sql` e
`20260907103100_collaborators_identifiers_status_periods.sql`): identidade
técnica UUID, identificadores de negócio com validade temporal e períodos de
status sem sobreposição.

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-01.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-01.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-01.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `f3`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado pelo passo 6 de `02-validar-f3-01.sql`
  (`set role authenticated`: leituras retornam 0 linhas, INSERT é negado e
  UPDATE/DELETE afetam zero linhas).

### O que é verificado (02-validar-f3-01.sql)

1. **Estrutura**: schema `public` contém somente as tabelas esperadas
   (identidade/membership da F2 + F3-01); nenhuma tabela/coluna de
   gestor/área/posição/ocupação/hierarquia/função/senioridade antecipada.
2. **Colunas exatas** das tabelas F3-01 (núcleo mínimo; sem nome/e-mail).
3. **UUID técnico**: `id` com default `gen_random_uuid()`; PKs compostas apenas
   por `id`; `business_code` (matrícula/código) **não** compõe PK.
4. **Constraints/triggers**: PKs, unique `(organization_id, business_code)`,
   checks de domínio/validade, exclusion constraints de não-sobreposição
   (btree_gist/tstzrange), FKs todas `ON DELETE RESTRICT` e triggers de
   `updated_at` presentes.
5. **Isolamento por organização**: contagem por org; mesmo `business_code`
   permitido em organizações diferentes; duplicidade na mesma org rejeitada.
6. **Identificadores**: troca histórica de código não troca `collaborator.id`
   (2 linhas, vigente correto).
7. **Lifecycle**: histórico ACTIVE → LEAVE → ACTIVE preservado; um único período
   aberto por colaborador; LEAVE vigente não remove vínculo/identificador e não
   cria/encerra ocupação.
8. **Rejeições no banco**: período inválido (`valid_to <= valid_from`), status
   fora do domínio, sobreposição de período, código duplicado na mesma org,
   código com espaços, FK composta com org inconsistente e exclusão física de
   org/colaborador com histórico (RESTRICT).
9. **Timestamps/version**: trigger `set_updated_at` redefine `updated_at`;
   `version` default 0 e incrementável.
10. **RLS deny-by-default**: habilitado nas três tabelas, zero policies,
    RLS das tabelas F2 intacto e comportamento negado comprovado como
    `authenticated`.
11. **Limpeza**: cenário sintético removido ao final.

Execução registrada nesta Issue: **45 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-01)" do
`supabase/README.md`.

## F3-02 — Catálogos de funções e senioridades (Issue #79)

Validação estrutural contra o **Supabase local** da migration
`20260907120000_job_roles_seniority_levels.sql`: catálogos configuráveis por
organização (`job_roles` e `seniority_levels`) independentes entre si, da
hierarquia e da autorização.

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-02.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-02.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-02.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `f4`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado pelo passo 6 de `02-validar-f3-02.sql`
  (`set role authenticated`: leituras retornam 0 linhas, INSERT é negado e
  UPDATE/DELETE afetam zero linhas).

### O que é verificado (02-validar-f3-02.sql)

1. **Estrutura**: schema `public` contém somente as tabelas esperadas (F2 +
   F3-01 + F3-02); nenhuma tabela de posição/reporting line/capability/junção
   antecipada.
2. **Colunas exatas** dos catálogos (núcleo mínimo: id/organization_id/name/
   status/created_at/updated_at/version); nenhuma coluna de
   ordem/rank/hierarquia/code/capability.
3. **UUID técnico** com `gen_random_uuid()`; PKs somente por `id`; `name` não é
   identidade técnica.
4. **Constraints/triggers**: PKs, uniques por `(organization_id, name)`, checks
   de trim/status, FKs somente para `organizations` com `ON DELETE RESTRICT`,
   zero FKs referenciando os catálogos e triggers de `updated_at` presentes.
5. **Isolamento por organização**: configurações independentes (Alfa com os oito
   conceitos do piloto + item desativado; Beta com subconjunto diferente);
   mesmo nome permitido em organizações diferentes; duplicidade na mesma org
   rejeitada.
6. **Função × senioridade**: catálogos independentes; Analista + Junior/Pleno/
   Senior representável sem degraus/nomes compostos; Especialista e Estagiário
   representáveis sem liderança/ocorrência piloto.
7. **Ausência de hierarquia implícita**: nenhuma coluna/tabela de ancoragem,
   rank ou auto-referência; nada de Auth/membership vinculado.
8. **Rejeições no banco**: nome duplicado na mesma org, nome com espaços,
   status fora do domínio, organização inexistente e exclusão física de org com
   catálogos (RESTRICT).
9. **Timestamps/version**: trigger `set_updated_at` redefine `updated_at`;
   `version` default 0 e incrementável.
10. **RLS deny-by-default**: habilitado nos dois catálogos, zero policies, RLS
    das tabelas F2/F3-01 intacto e comportamento negado comprovado como
    `authenticated`.
11. **F3-01 intacta**: `collaborators` preservada; constraints de lifecycle/
    identificadores presentes; 3 policies inalteradas.
12. **Limpeza**: cenário sintético removido ao final.

Execução registrada nesta Issue: **43 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-02)" do
`supabase/README.md`.

## F3-03 — Unidades e posições da estrutura formal (Issue #80)

Validação estrutural contra o **Supabase local** da migration
`20260907130000_organizational_units_positions.sql`: unidades com existência e
composição temporal (árvore formal) e posições vinculadas a unidade + função +
senioridade opcional, todas independentes de ocupantes.

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-03.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-03.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-03.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `f5`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado pelo passo 5 de `02-validar-f3-03.sql`
  (`set role authenticated`: leituras retornam 0 linhas, INSERT é negado e
  UPDATE/DELETE afetam zero linhas).

### O que é verificado (02-validar-f3-03.sql)

1. **Estrutura**: schema `public` contém somente as tabelas esperadas (F2 +
   F3-01 + F3-02 + F3-03); nenhuma tabela/coluna de occupation/reporting line/
   gestor/rank/colegiado/dotted line antecipada.
2. **Colunas exatas** de `organizational_units`, `organizational_unit_parent_periods`
   e `organizational_positions` (sem name/code/collaborator_id/occupation).
3. **UUID técnico** com `gen_random_uuid()`; PKs somente por `id`; posições sem
   unique natural (ocorrências idênticas válidas); unidades com unique por
   `(org, name)` e de referência `(id, org)`.
4. **Constraints/triggers**: 18 constraints esperadas (pk/unique/fk/check/
   exclusion), FKs todas `ON DELETE RESTRICT`, FKs de posição restritas ao
   escopo estrutural, unique de referência aditiva em `job_roles`/
   `seniority_levels`, zero dependências referenciando posições e triggers de
   `updated_at` presentes.
5. **Cenário**: unidades e posições por organização; unidade sem posições e
   unidade encerrada preservada; posições vagas (sem ocupante); posição
   encerrada preservada; parent temporal com histórico (mudança de parent sem
   recriar unidade; raiz por parent null; expansão acima e nível intermediário
   posterior); Especialista sem equipe; Gerente + Analista na mesma unidade sem
   Coordenador; mesmo job_role em alturas diferentes; posições idênticas como
   ocorrências distintas; seniority null válido.
6. **Rejeições/integridade**: tenant integrity (FKs compostas rejeitam unidade/
   função/senioridade/parent de outra organização), sobreposição de parent,
   auto-parent, nome duplicado de unidade na mesma org (mesmo nome entre orgs
   permitido), nomes com espaços, períodos inválidos e exclusão física de org
   com estrutura (RESTRICT).
7. **Timestamps/version**: trigger `set_updated_at` redefine `updated_at`;
   `version` default 0 e incrementável.
8. **RLS deny-by-default**: habilitado nas três tabelas, zero policies, RLS das
   tabelas F2/F3-01/F3-02 intacto e comportamento negado comprovado como
   `authenticated`.
9. **F3-01/F3-02 intactas**: colunas preservadas (alterações apenas aditivas),
   constraints anteriores presentes e 3 policies inalteradas.
10. **Limpeza**: cenário sintético removido ao final.

Execução registrada nesta Issue: **56 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-03)" do
`supabase/README.md`.

## F3-04 — Reporting lines temporais entre posições (Issue #81)

Validação estrutural contra o **Supabase local** da migration
`20260907140000_position_reporting_lines.sql`: hierarquia formal temporal entre
`organizational_positions`, sem inferir hierarquia por cargo/senioridade/unidade
e sem ocupação.

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-04.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-04.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-04.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `f6`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado pelo passo 5 de `02-validar-f3-04.sql`
  (`set role authenticated`: leituras retornam 0 linhas, INSERT é negado e
  UPDATE/DELETE afetam zero linhas).

### O que é verificado (02-validar-f3-04.sql)

1. **Estrutura**: schema `public` contém somente as tabelas esperadas (F2 +
   F3-01/02/03 + F3-04); colunas exatas de `position_reporting_lines` (sem
   collaborator_id/occupation/autor); `manager_position_id`/`reason`/`valid_from`
   NOT NULL; nenhuma tabela de occupation/dotted line/colegiado/substituição.
2. **Constraints/triggers**: PK, FKs compostas + RESTRICT, checks (reason,
   valid_to, not_self), exclusion por subordinado; unique de referência aditiva
   em `organizational_positions`; funções/triggers de validade de posições,
   ciclos e fechamento de posição presentes.
3. **Cenário**: raiz por ausência de linha; um superior vigente por subordinado;
   troca de superior fechando + abrindo (histórico preservado); reconstrução da
   cadeia para datas diferentes; Analista→Gerente direto sem Coordenador;
   Gerente→Gerente, Gerente→Gerente Sênior, Diretor→Diretor; mesmo job_role em
   alturas diferentes; Especialista sem subordinados; `reason` não vazio.
4. **Rejeições/integridade**: dois superiores simultâneos, self-reporting, ciclo
   multi-nível (trigger temporal), cross-organization (subordinate/manager),
   `reason` vazio, período antes da existência das posições, linha aberta além
   do encerramento e encerramento de posição com linhas abertas (fail-closed).
5. **RLS deny-by-default**: habilitado na tabela nova, zero policies, RLS das
   tabelas F2/F3-01/02/03 intacto e comportamento negado comprovado como
   `authenticated`.
6. **F3-01/F3-02/F3-03 intactas**: colunas preservadas (alterações apenas
   aditivas), constraints anteriores presentes e 3 policies inalteradas.
7. **Limpeza**: cenário sintético removido ao final.

Execução registrada nesta Issue: **42 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-04)" do
`supabase/README.md`.

## F3-05 — Occupations: ocupações temporais de colaboradores em posições (Issue #82)

Validação estrutural contra o **Supabase local** da migration
`20260907150000_occupations.sql`: vínculo temporal colaborador ↔ posição
formal, com um ocupante por posição por instante, múltiplas posições
simultâneas por colaborador, transferências, vacância, licença independente e
desligamento com fechamento explícito.

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-05.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-05.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-05.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `f7`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado pelo passo 5 de `02-validar-f3-05.sql`
  (`set role authenticated`: leituras retornam 0 linhas, INSERT é negado e
  UPDATE/DELETE afetam zero linhas).

### O que é verificado (02-validar-f3-05.sql)

1. **Estrutura**: schema `public` contém somente as tabelas esperadas (F2 +
   F3-01/02/03/04 + F3-05); colunas exatas de `occupations` (sem
   author/substituição/reporting); `collaborator_id`/`organizational_position_id`/
   `reason`/`valid_from` NOT NULL (vacância = ausência; sem occupation com NULL).
2. **Constraints/triggers**: PK, FKs compostas + RESTRICT, checks (reason,
   valid_to), exclusion por posição (um ocupante por instante); funções/triggers
   de validade na posição e de desligamento (inactive) fail-closed presentes.
3. **Cenário**: posição ocupada e posição vaga por data; troca de ocupante na
   mesma posição (histórico preservado, posição não recriada); colaborador com
   duas occupations simultâneas; licença (leave) sem encerrar/recriar
   occupation; histórico consultável por data; reporting line P2→P1
   independente do ocupante; `reason` não vazio.
4. **Rejeições/integridade**: dois ocupantes simultâneos na mesma posição,
   occupation antes/`além` da validade da posição, cross-organization
   (collaborator e posição), `reason` vazio, período inválido e desligamento
   com occupation vigente (bloqueado — fail-closed; nenhum estado persistido).
5. **Desligamento coerente**: sem occupations vigentes, o desligamento é
   permitido após fechamento explícito (validado e revertido para manter o
   cenário).
6. **RLS deny-by-default**: habilitado na tabela nova, zero policies, RLS das
   tabelas F2/F3-01/02/03/04 intacto e comportamento negado comprovado como
   `authenticated`.
7. **F3-01/F3-02/F3-03/F3-04 intactas**: colunas preservadas, constraints
   anteriores presentes e 3 policies inalteradas.
8. **Limpeza**: cenário sintético removido ao final.

Execução registrada nesta Issue: **42 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-05)" do
`supabase/README.md`.

## F3-06 — Temporary responsibilities: substituições temporárias (Issue #83)

Validação estrutural contra o **Supabase local** da migration
`20260907160000_temporary_responsibilities.sql`: substituições temporárias
sobre uma posição formal, sem alterar occupation, reporting line, status ou
estrutura.

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-06.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-06.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-06.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `f8`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado pelo passo 5 de `02-validar-f3-06.sql`
  (`set role authenticated`: leituras retornam 0 linhas, INSERT é negado e
  UPDATE/DELETE afetam zero linhas).

### O que é verificado (02-validar-f3-06.sql)

1. **Estrutura**: schema `public` contém somente as tabelas esperadas (F2 +
   F3-01/02/03/04/05 + F3-06); colunas exatas de `temporary_responsibilities`
   (sem titular explícito/autor/reporting/unit); `valid_to` NOT NULL (período
   fechado); nenhuma tabela de colegiado/avaliação/capability/snapshot.
2. **Constraints/triggers**: PK, FKs compostas + RESTRICT, checks (tipo, reason,
   valid_to), exclusion por posição; funções/triggers de validade na posição e
   anti-auto-substituição presentes.
3. **Cenário**: titular mantém occupation; substituto resolvido sem occupation
   artificial; reporting line inalterada; reconstrução antes/durante/depois
   (titular reassume sem recriar occupation); mesmo substituto em duas posições;
   tipo `evaluative` presente; período fechado; `reason` não vazio.
4. **Rejeições/integridade**: sobreposição na mesma posição, período sem fim
   (NULL), auto-substituição, cross-organization (substituto e posição), período
   além do encerramento da posição, tipo inválido e `reason` vazio.
5. **RLS deny-by-default**: habilitado na tabela nova, zero policies, RLS das
   tabelas F2/F3-01..05 intacto e comportamento negado comprovado como
   `authenticated`.
6. **F3-01..F3-05 intactas**: colunas preservadas, constraints anteriores
   presentes e 3 policies inalteradas.
7. **Limpeza**: cenário sintético removido ao final.

Execução registrada nesta Issue: **36 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-06)" do
`supabase/README.md`.

## F3-07 — Resolução organizacional por data (Issue #84)

Validação estrutural contra o **Supabase local** da migration
`20260907170000_organization_resolution.sql`: funções SQL que resolvem, por
data, gestor direto, subordinados, descendentes, cadeia e escopo estrutural,
sem campos redundantes de gestor.

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-07.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-07.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-07.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `f9`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado pelo passo 7 de `02-validar-f3-07.sql`
  (`set role authenticated`: a resolução retorna responsável NULL).

### O que é verificado (02-validar-f3-07.sql)

1. **Estrutura**: schema `public` inalterado (14 tabelas; F3-07 adiciona apenas
   funções); 7 funções presentes, SQL/STABLE/SECURITY INVOKER, sem grants
   explícitos; 3 policies inalteradas.
2. **Responsável por posição**: titular/substituto/efetivo (vaga com substituto;
   ocupada sem substituto; vaga sem substituto → NULL).
3. **Gestor direto**: derivado da reporting line + occupation; gerência sem
   Coordenador (Consultor/Analista resolvem o Gerente); multi-positions com dois
   gestores; licença não exclui.
4. **Subordinados/descendentes**: conjuntos e profundidades corretos.
5. **Cadeia**: ascendente com posições vagas preservadas (responsável NULL antes
   do substituto; C_SUB durante).
6. **Escopo**: união coerente de múltiplas positions (posições + unidades).
7. **RLS deny-by-default**: authenticated não resolve ocupante.
8. **F3-01..F3-06 intactas** e **limpeza** do cenário.

Execução registrada nesta Issue: **20 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-07)" do
`supabase/README.md`.

## F3-08 — Colegiado padrão e snapshot por ciclo (Issue #85)

Validação estrutural contra o **Supabase local** da migration
`20260907180000_collegiate_configuration_snapshot.sql`: configuração temporal
do colegiado por avaliado (0..N) e snapshot imutável por ciclo.

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-08.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-08.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-08.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `fa`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado pelo passo 8 de `02-validar-f3-08.sql`
  (`set role authenticated`).

### O que é verificado (02-validar-f3-08.sql)

1. **Estrutura**: schema `public` com 19 tabelas (5 novas da F3-08); 28
   constraints esperadas; FKs `ON DELETE RESTRICT`; RLS habilitado nas 5
   tabelas com zero policies; funções `materializar_colegiado_ciclo` e
   `enforce_collegiate_configuration_member_not_self` (SECURITY INVOKER).
2. **Configuração padrão**: multi-membros (EVAL1 = {M1,M2}); configuração
   explicitamente vazia (EVAL3); self bloqueado; membro duplicado bloqueado;
   cross-organization bloqueado; mudança fecha v1 e abre v2 preservando
   histórico.
3. **Snapshot por ciclo**: um snapshot por avaliado; membros e superior
   resolvidos congelados (EVAL1 = {M1,M2} e C_GER no ciclo 1; {M1} no ciclo 2
   com v2 vigente); EVAL2/EVAL3 com 0 membros; EVAL4 (sem posição) com 0
   posições; EVAL5 (2 posições) com 2 posições e superiores por posição;
   posição sem superior com superior null.
4. **Idempotência**: repetição da materialização não duplica/substitui.
5. **Imutabilidade**: mudança posterior de occupation não altera snapshots;
   reexecução do ciclo não re-materializa.
6. **RPC**: rejeita avaliado de outra organização (sem snapshot criado).
7. **RLS deny-by-default** comprovado como `authenticated`.
8. **F3-01..F3-07 intactas** e **limpeza** do cenário.

Execução registrada nesta Issue: **29 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-08)" do
`supabase/README.md`.

## F3-09 — Responsabilidade avaliativa e sucessão de avaliador (Issue #86)

Validação estrutural contra o **Supabase local** da migration
`20260907190000_evaluator_responsibility_succession.sql`: resolução avaliativa
por posição/data, responsabilidade temporal por `(snapshot, posição)` e eventos
imutáveis de sucessão, sem alterar os snapshots F3-08.

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-09.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-09.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-09.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `fb`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado pelo passo 8 de `02-validar-f3-09.sql`
  (`set role authenticated`).

### O que é verificado (02-validar-f3-09.sql)

1. **Estrutura**: schema `public` com 21 tabelas (2 novas da F3-09); 15
   constraints esperadas; FKs `ON DELETE RESTRICT`; RLS habilitado nas 2
   tabelas com zero policies; 5 funções F3-09 (SECURITY INVOKER).
2. **Resolução avaliativa**: substituto `evaluative` > titular durante o
   período; titular reassume após o período; múltiplas posições resolvidas
   separadamente (2 linhas).
3. **Materialização**: uma responsabilidade original por `(snapshot, posição
   com superior)`; posição raiz não gera responsabilidade; responsável original
   = titular (nunca o substituto, mesmo ativo na data).
4. **Responsável vigente**: overlay do substituto por data; reversão ao titular;
   após sucessão, novo responsável.
5. **Sucessão**: 4 eventos (original → novo) com motivo/autor; responsável
   original preservado nas linhas fechadas; novas responsabilidades abertas.
6. **Idempotência/não-reabertura**: repetição não duplica eventos; ID de
   responsabilidade encerrada é rejeitado; superior vago sem novo responsável é
   rejeitado (fail-closed).
7. **Tenant integrity**: responsabilidade e evento cross-organization
   bloqueados (FKs compostas).
8. **RLS deny-by-default** comprovado como `authenticated`.
9. **F3-01..F3-08 intactas** (resoluções F3-07, policies e `materializar_
   colegiado_ciclo` presentes) e **limpeza** do cenário.

Execução registrada nesta Issue: **23 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-09)" do
`supabase/README.md`.

## F3-10 — Validação integrada da estrutura organizacional (Issue #87)

Validação de fechamento da Fase 3: uma organização 100% sintética, representativa
dos padrões do piloto, exercitando em conjunto F3-01..F3-09 (sem migration nem
alteração de schema).

### Como reproduzir

Requisitos: Docker Desktop em execução e o CLI Supabase da raiz
(`npx --yes supabase@2.116.0`).

```powershell
# 1) subir a stack local (rebuild limpo: migrations em ordem + seed)
npx --yes supabase@2.116.0 start

# 2) aplicar o cenário sintético no banco local (idempotente)
Get-Content supabase/validacao/01-cenario-f3-10.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1

# 3) executar a validação (exit code 0 = todas as verificações passaram)
Get-Content supabase/validacao/02-validar-f3-10.sql -Raw -Encoding UTF8 |
  docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Observações:

- os scripts **não tocam projeto remoto**, **não alteram nenhuma policy RLS** e
  removem ao final os dados sintéticos do cenário (banco local limpo);
- `01-cenario-f3-10.sql` insere via superuser local (equivalente a service_role)
  apenas UUIDs fixos com prefixo `fc`, sem colidir com os cenários anteriores;
- o deny-by-default é comprovado no passo 6 de `02-validar-f3-10.sql`
  (`set role authenticated`).

### O que é verificado (02-validar-f3-10.sql)

1. **Sem campos especiais por cargo**: 21 tabelas; nenhuma coluna
   rank/level/order/hierarchy em job_roles/seniority_levels/positions; catálogo
   com os 8 job_roles + Junior/Pleno/Senior.
2. **14 cenários** com asserts explícitos: Gerente + 3 Coordenadores; Consultor
   direto ao Gerente; Analistas Jr/Pl/Sr sob o mesmo Coordenador (mesma reporting
   line/gestor/profundidade); Estagiário sob Coordenador e sob Gerente (sem
   seniority); gerência menor sem Coordenador; Especialista no mesmo patamar do
   Gerente (mesmo superior, zero subordinados); posição vaga; troca definitiva de
   ocupante (+ sucessão F3-09); transferência entre coordenações; licença mantendo
   occupation; substituição temporária; pessoa com duas posições; Diretor→Diretor;
   colegiado ausente/vazio/com membros e histórico por ciclo.
3. **Reconstrução histórica** em 5 datas (2024-02-01, 05-01, 07-15, 09-15, 12-01).
4. **RLS deny-by-default** comprovado como `authenticated`; policies inalteradas.
5. **F3-01..F3-09 intactas** e **limpeza** do cenário.

Execução registrada nesta Issue: **29 verificações [PASS], 0 falhas** (Supabase
local, CLI 2.116.0, PostgreSQL 17.6; repetida após um segundo `db reset`, com o
mesmo resultado). Detalhes na seção "Validação executada (F3-10)" do
`supabase/README.md`.

## Limitações e notas registradas

- **JWT é stateless**: após logout, o refresh token é revogado, mas um access
  token copiado continua assinado até expirar (`auth.jwt_expiry` local = 1h). A
  revogação efetiva de sessões pré-existentes é feita por ban/desativação
  (F2-07), validada no passo 8; políticas de dados de domínio futuras poderão
  incorporar o status do usuário como condição adicional de RLS.
- As policies de `organizations` são escopadas por membership ativa (F2-03); a
  desativação de usuário **não** remove memberships (modelo F2-07): o bloqueio
  efetivo vem do ban (login/refresh/getUser) + RLS do perfil
  (`status = 'active'`), e a desativação de membership remove o acesso à
  organização (passo 9).
- Impersonação DEV (F2-09) é contexto local do frontend e nunca participa de
  autorização server-side (passo 5 + testes de F2-09).
- Fora do escopo: capabilities completas, RLS de avaliações/metas/observações,
  estrutura organizacional completa e dados reais.
