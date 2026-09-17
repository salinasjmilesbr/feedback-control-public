# F6-A04 — Acesso do Admin Virtus à superfície de plataforma (desenho técnico curto)

> **Status:** desenho **fechado para implementação** (nenhum código funcional nesta atividade).
> **Atividade:** F6-A04 — Issue **#269**.
> **Base:** `main` = `ccf7948` (`feat(F6-A03): bootstrap minimo seguro do GREENFIELD (#266)` — **já
> integrado**, incluindo a correção do replay idempotente).
> **Reutiliza:** `docs/F6-A03-desenho-tecnico.md` (D1–D21 e Q1–Q3 FECHADAS) e o Auth/F2 existente.
> **Natureza:** documento de desenho. **Zero** arquivo de código, SQL, CI ou teste alterado aqui.

## 1. Objetivo e não-escopo

### 1.1 Percurso-alvo (o que precisa ser *permitido* pelo produto)

```text
Admin Virtus
  → login Supabase Auth por e-mail/senha
    → sessão válida
      → /plataforma/nova-organizacao
```

### 1.2 Não-escopo (explícito)

| Fora de escopo | Motivo |
| --- | --- |
| Cadastro público / autoatendimento de conta | `enable_signup = false` (`supabase/config.toml:40`); a criação de identidade é ato de raiz de confiança |
| SSO, MFA, novo provedor de identidade, novo sistema de identidade | Determinado pela Issue #269; o Auth existente é reutilizado |
| Portal SaaS, listagem de tenants, gestão de operadores/roles/planos | F6-A03 D21 |
| Criar/provisionar a identidade do **operador** (Auth + allowlist) | Raiz de confiança do plano de plataforma — **F6-A03 Q1=A/D14**; registrado aqui como **pré-requisito operacional** (§3.3) |
| Alterar a autorização do provisionamento | Continua **exclusivamente server-side** (Edge + RPC); este desenho não toca autoridade |
| Alterar guard de rota, Edge, RPC, RLS, grants, capabilities ou a navegação funcional | Fora do escopo; qualquer mudança aí seria reabertura de decisão fechada |
| Pós-provisionamento (levar o founder ao tenant novo) | F6-A03 §6.5.2 já orienta o login do primeiro Admin |

## 2. Estado atual auditado (evidência arquivo:linha)

### 2.1 O que **já funciona** (não precisa de correção)

| Peça | Evidência | Estado |
| --- | --- | --- |
| Login por e-mail/senha (Supabase Auth) | `src/auth/adaptadores.ts:70-71` (`signInWithPassword`), acionado por `src/auth/LoginPage.tsx:18-30` | **OK** |
| Sessão válida e resolução de identidade | `src/auth/controladorSessao.ts:318-328` (`entrar`) e `:213-246` (`resolver`) | **OK** |
| Perfil ausente ⇒ estado `acessoNegado` | `src/auth/servico.ts:99-101` (`AccessNotProvisionedError`) → `controladorSessao.ts:241-245` | **OK** |
| Rota de plataforma **fora** do shell funcional (D19) | `src/routes/AppRoutes.tsx:112-116` (`LayoutPlataforma` + `ROTA_PLATAFORMA_NOVA_ORGANIZACAO`) | **OK** |
| Guard admite sessão viva sem tenant | `src/routes/plataformaRotas.ts:37-49` (`autenticado`, `semOrganizacao`, `aguardandoSelecao`, `acessoNegado` ⇒ `permitir`) | **OK** |
| Entrada existente — **só** no estado `semOrganizacao` | `src/auth/SemOrganizacao.tsx:23-33` (sonda `souOperadorDaPlataforma`) e `:60-63` (link condicional) | **parcial** |
| Self-check e provisionamento | `src/pages/plataforma/NovaOrganizacaoPlataformaPage.tsx` + `src/services/plataforma/controladorProvisionamento.ts` + Edge `provisionar-organizacao` | **OK** (F6-A03) |

**Conclusão parcial:** autenticação, sessão e a rota **já existem**; o que falta é o **caminho de
produto** até a rota.

### 2.2 O que **bloqueia** o percurso

#### B1 (bloqueante do percurso) — `acessoNegado` é um beco sem saída

`src/auth/LoginPage.tsx:114-134`: no estado `acessoNegado` a tela exibe o título "Acesso negado", a
mensagem da taxonomia e **apenas o botão "Sair"** — nenhum caminho para
`/plataforma/nova-organizacao`.

Esse é **exatamente** o estado do operador em ambiente virgem: sem `user_profiles`, o estado é
`acessoNegado` — situação que o **D17** da F6-A03 reconhece como **admissível** (o operador de
plataforma pode não ter perfil ainda) e que o **D19** já mandou o guard admitir. Ou seja: o guard
admite, mas a UI não oferece a porta.

#### B2 (descoberta) — sessão válida **com** tenant também não tem entrada

- `src/auth/LoginPage.tsx:73-112` — estado `autenticado` ("Sessão iniciada"): oferece apenas
  "Acessar o Virtus" (`/`) e "Sair";
- `src/auth/LoginPage.tsx:65-67` → `src/auth/AguardandoSelecao.tsx:46-52` — estado
  `aguardandoSelecao` (N>1): oferece organizações e "Sair".

É o caso do operador sintético local: a fixture F2-10 dá a ele **perfil ativo + membership em uma
organização** (`supabase/validacao/README.md:10-21`), logo ele cai em `autenticado` e **não** vê a
superfície. Hoje ele só chega digitando a URL.

#### B3 (pré-requisito de ambiente — não é defeito de código) — sem configuração não existe login

`src/config/ambiente.ts:65-70` exige `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` **juntas**;
`src/auth/cliente.ts:20-24` devolve `null` quando faltam; `src/auth/AuthProvider.tsx:32` propaga e o
estado vira `indisponivel` ⇒ `src/auth/LoginPage.tsx:45-59` mostra "A autenticação não está
configurada neste ambiente" e **não renderiza o formulário**. Neste workspace **não existe
`.env.local`**. Sem isso, nenhum login é possível — porém é **configuração**, não correção de código.

#### B4 (pré-requisito de identidade) — o operador precisa existir no Auth e estar na allowlist

A autoridade de plataforma é `auth.uid()` **na allowlist** + perfil ausente/ativo
(`supabase/config.toml:63-66`; Edge `provisionar-organizacao`: `operadorAutorizado`). A fixture
sintética `supabase/validacao/01-cenario-f2-10.sql:103-107,156-162,170-175` já provê uma identidade
de operador com senha local e organização — **criá-la é ato de raiz de confiança** e permanece
**fora de escopo** (F6-A03 Q1=A/D14).

## 3. A menor correção segura

### 3.1 C1 — uma entrada **condicionada** ao self-check, reutilizada nas telas de sessão

**Um** componente novo, `src/auth/EntradaPlataforma.tsx`:

- faz o **self-check de UX** já existente (`souOperadorDaPlataforma()`, D20) — fail-closed: qualquer
  falha resolve `false` e a entrada **não** aparece;
- quando `true`, renderiza um `Link` para `ROTA_PLATAFORMA_NOVA_ORGANIZACAO`
  (`src/routes/plataformaRotas.ts:23`);
- não decide autorização, não lê/escreve storage, não chama RPC e não carrega dado de tenant.

**Call sites (4, sendo 1 refatoração):**

| Onde | Estado | Por quê |
| --- | --- | --- |
| `src/auth/LoginPage.tsx` — ramo `acessoNegado` (`:114-134`) | **essencial (B1)** | hoje beco sem saída; é o operador de ambiente virgem |
| `src/auth/LoginPage.tsx` — ramo `autenticado` (`:73-112`) | **essencial (B2)** | é a tela imediatamente posterior ao login do operador com tenant |
| `src/auth/LoginPage.tsx` — ramo `aguardandoSelecao` (`:65-67`) → `src/auth/AguardandoSelecao.tsx` | coerência | mesmo componente, **zero** superfície nova |
| `src/auth/SemOrganizacao.tsx:23-33,60-63` | **refatoração** | passa a usar o componente único (hoje o bloco é inline) |

**Nada mais muda:** nenhuma rota nova, nenhum item em `NavegacaoPrincipal` (D21 preservado),
nenhuma alteração em guard, Edge, RPC, RLS, grants ou capabilities.

### 3.2 Por que é a menor correção **segura**

1. **A autoridade continua exclusivamente server-side.** A entrada só aparece com o self-check
   positivo, e o provisionamento continua decidido pela Edge (`operadorAutorizado` = allowlist +
   piso de perfil) e pela RPC soberana. A UI **não** ganha nenhum poder novo.
2. **Zero superfície de autorização nova:** nenhuma policy, grant, capability, role, rota ou Edge;
   nenhuma regra de autorização replicada no React (`.ai/architecture-rules.md` §3).
3. **Ocultar/mostrar é UX, nunca autorização** (§1.7 das regras permanentes): remover o link não
   altera veredito — a prova negativa já é exigida pela F6-A03 (critério 22).
4. **Nenhum dado de tenant na tela pública:** o `acessoNegado` sequer carrega `sessao`
   (`controladorSessao.ts:72`), e o componente não lê identidade.
5. **Fail-closed preservado:** sem sessão (`naoAutenticado`/`sessaoExpirada`) o guard manda ao login;
   `sessaoIndisponivel`/`indisponivel` seguem **bloqueados** (`plataformaRotas.ts:54-57`).

### 3.3 Pré-requisitos verificáveis (operacionais — **não** são código desta atividade)

1. `.env.local` com `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` obtidas de
   `npx supabase status -o env` (**nunca** versionadas; `.env.example` documenta as duas chaves,
   vazias);
2. stack local no ar (`npx supabase start`) com as migrations/seed aplicadas;
3. identidade sintética **com senha** e o respectivo UUID na allowlist
   (`supabase/config.toml:63-66`) — a fixture F2-10 já atende (`supabase/validacao/README.md:10-21`).

## 4. Decisões fechadas deste desenho

| # | Decisão | Racional | Alternativa rejeitada |
| --- | --- | --- | --- |
| **D1** | A correção é de **navegação/descoberta**; **nada** muda em autenticação ou autorização | Login, sessão, guard, Edge e RPC já funcionam (§2.1); o que falta é a porta | Criar rota "pós-login" dedicada ou redirecionar automaticamente — inventaria fluxo de autenticação |
| **D2** | A entrada vive na **tela de login** (estado imediatamente posterior ao login) e **nunca** na navegação funcional | F6-A03 **D21**/§6.5.4: a superfície de plataforma não entra na navegação do produto | Item em `NavegacaoPrincipal` — reabriria D21 e exporia a superfície a todo usuário |
| **D3** | **Um** componente único (sonda + link), reutilizado por `SemOrganizacao` e pelos ramos do login | Uma sonda, um link, um lugar para o fail-closed; evita duplicar a regra de UX | Copiar o bloco inline em cada ramo — duplicação de comportamento e deriva |
| **D4** | A **mensagem** do `acessoNegado` **não** é alterada (taxonomia F0-05 compartilhada); a tela ganha apenas a entrada | A frase vem de `publicErrors` (`src/errors/applicationErrors.ts:4`) e é usada por outros fluxos; alterá-la é mudança transversal fora do escopo | Reescrever a mensagem da taxonomia — impacto em fluxos alheios à plataforma |
| **D5** | `aguardandoSelecao` recebe a mesma entrada | Custo zero (mesmo componente) e uniformidade dos estados de sessão viva | Deixar de fora — o operador com N>1 continuaria sem porta |

## 5. Ameaças relevantes e mitigações

| # | Ameaça | Mitigação |
| --- | --- | --- |
| T1 | Expor a superfície a quem não é operador | A entrada só aparece com o self-check **fail-closed** e a própria página/Edge continuam negando (`plataforma.operador_atual` ⇒ `{ operador: false }`) |
| T2 | Alguém tratar a UI como autorização | D1/D2 + invariante: a decisão é server-side; a prova negativa é exigida na implementação (F6-A03 §9.4 critério 22) |
| T3 | Loop de redirecionamento após login | A rota de plataforma está **fora** de `LayoutAutenticado` e não redireciona; `acessoNegado` hoje **não** navega (§2.2 B1) |
| T4 | Vazamento do `acessoNegado` para quem tem perfil **inativo** | Sonda server-side: perfil existente e não ativo ⇒ `operador: false` (Edge `operadorAutorizado`) ⇒ entrada oculta |

## 6. Critérios de aceite (curtos e verificáveis)

1. **`acessoNegado`** (sessão válida, perfil ausente): o operador autorizado chega a
   `/plataforma/nova-organizacao` **por link**, sem digitar URL.
2. **`autenticado`** (sessão válida com tenant): idem.
3. **`aguardandoSelecao`** (N>1): idem.
4. **Negativa visível a não-operador:** a entrada **não** é renderizada; por URL, a negativa
   permanece (guard + self-check + Edge).
5. **Nada além:** `git diff` restrito a `EntradaPlataforma.tsx`, `LoginPage.tsx` (3 ramos),
   `AguardandoSelecao.tsx`, `SemOrganizacao.tsx` e os testes correspondentes; **nenhuma** alteração
   em `plataformaRotas.ts`, `LayoutPlataforma.tsx`, `AppRoutes.tsx`, Edge, RPC e SQL.
6. **Gates proporcionais:** `npm test` (com teste novo do componente: entrada oculta com self-check
   `false`, visível com `true`), `npm run build`, `npm run lint` e `git diff --check` verdes.
7. **Pré-requisitos de §3.3** documentados na evidência de execução local (sem transcrever segredos).

## 7. Registros (não corrigidos aqui)

| # | Item | Evidência | Classificação |
| --- | --- | --- | --- |
| R1 | Sem `.env.local` neste workspace, o login local é impossível (estado `indisponivel`, sem formulário) | `src/auth/cliente.ts:20-24`, `src/auth/LoginPage.tsx:45-59` | **Pré-requisito operacional** (§3.3) — não é defeito de código |
| R2 | Criar a identidade do operador (Auth + allowlist) é ato de raiz de confiança | F6-A03 D14/Q1=A | Fora de escopo por decisão |
| R3 | Inventário de rotas da F6-01 não inclui `/plataforma/nova-organizacao` | `docs/F6-01-desenho-tecnico.md:28-80`; F6-A03 §13 F8 | Dívida documental já registrada |
| R4 | Em `acessoNegado` a sessão não é "operante": `verificarLimitesDeSessao` devolve `null` (sem expiração por inatividade local) | `src/auth/controladorSessao.ts:182-184,243` | Observação; sem autoridade associada (a Edge revalida o JWT em toda chamada) — **fora** desta correção |

## 8. Dúvidas realmente bloqueantes

**Nenhuma.** O desenho acima fecha o percurso sem tocar autorização e sem reabrir D1–D21/Q1–Q3.

Observações que **não** bloqueiam a implementação (registradas para o orquestrador):

1. **Ordem de integração:** esta correção depende da F6-A03 **já integrada** — satisfeito nesta base
   (`main` = `ccf7948`). Se um PR de F6-A03 anterior à correção do replay fosse usado como base, os
   call sites seriam os mesmos, mas a superfície teria o defeito já corrigido em `main`.
2. **Ambiente de execução:** a verificação de ponta a ponta exige `.env.local` + stack local +
   identidade sintética (§3.3); sem isso, a evidência possível é a de testes de componente/render.

## 9. Autoauditoria deste documento

- [x] **Nenhum código funcional** foi escrito: zero arquivo de código, SQL, CI ou teste alterado.
- [x] Toda afirmação sobre o estado atual é **rastreável** a arquivo:linha da `main` `ccf7948`.
- [x] Reutiliza o **Auth existente** (F2) e a **F6-A03** integrada; **nenhuma** decisão fechada foi
      reaberta (D19/D20/D21 e Q1–Q3 preservados — §4, D2 e §3.2).
- [x] A autoridade de plataforma permanece **exclusivamente server-side** (§3.2, item 1) e a entrada
      é **UX** (§3.2, item 3).
- [x] Fora de escopo explícito: cadastro público, SSO/MFA, novo sistema de identidade e portal SaaS
      (§1.2).
- [x] Correção **mínima**: um componente + 4 call sites (1 refatoração), nenhuma rota/guarda/Edge/SQL.
- [x] Dúvidas bloqueantes: **nenhuma** (§8), com as duas observações não bloqueantes registradas.
