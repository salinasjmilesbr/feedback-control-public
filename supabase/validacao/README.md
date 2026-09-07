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
