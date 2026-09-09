# F5-03 — Organização ativa / seleção de organização (desenho técnico)

> Documento de desenho técnico — **etapa de auditoria e desenho, sem código funcional**.
> Estado: **PROPOSTA para revisão** — decisões D1–D13 propostas e questões Q1–Q5
> registradas para validação (podem permanecer abertas no PR).
>
> Fase: 5 — Identidade e Multiusuário · Atividade: F5-03 · Base: `main` (F5-01 e F5-02 concluídas)

---

## 1. Objetivo

Desenhar como o Virtus **determina, representa, troca e invalida a ORGANIZAÇÃO
ATIVA** de um usuário autenticado quando ele possui uma ou mais memberships
ativas — sem jamais transformar essa seleção em autoridade de tenant.

O documento define fronteiras, invariantes, fluxos (seleção inicial, switch,
refresh/relogin, revogação mid-session), estratégia fail-closed, impacto em RLS,
relação com F5-02/F5-04/F5-05 e a análise explícita de **TOCTOU** (por que uma
seleção previamente validada nunca substitui a revalidação no momento da
operação).

### 1.1 Princípios herdados (não redesenhados)

- `auth.uid()` é a raiz soberana da identidade autenticada (F5-01);
- `user_profile.id = auth.uid()`; `organization_id` **não** é claim soberano de
  JWT/sessão; organização enviada pelo cliente = **intenção**, confirmada contra
  membership **ativa** do `auth.uid()` (F5-01);
- vínculo usuário↔colaborador ocorre no contexto da membership
  (`membership_collaborator_links`, F5-02), com no máx. 1 link `active` por
  membership e no máx. 1 membership ativa por colaborador+organização (Q3 F5-02);
  `resolver_collaborador_vinculado` permanece fechado a `authenticated` (Q1 F5-02);
- Policy Engine é o **único gate** de decisão funcional; `authorize()` =
  enforcement; `can()` = UX; tenant mismatch = DENY; fail-closed;
- RLS F4-08 = isolamento real entre tenants; helper único
  `user_has_active_membership(org)`; sem abertura genérica de SELECT/DML para
  `authenticated`; nenhum `SECURITY DEFINER` novo sem necessidade arquitetural;
- ADMIN **não** é superusuário de conteúdo confidencial; acessos C/D e contratos
  de confidencialidade da F4 intactos; cargo/job_role/nome não participam de
  autorização.

---

## 2. Estado atual relevante (verificado em `main`)

### 2.1 Máquina de sessão e estados (F5-01 — `src/auth/controladorSessao.ts`)

O controlador de sessão já resolve a identidade (`resolverIdentidade`) e decide
o estado conforme o número de memberships ativas:

| Memberships ativas | Estado | Área funcional |
| --- | --- | --- |
| 0 | `semOrganizacao` | bloqueada (tela dedicada `SemOrganizacao.tsx`) |
| **1** | `autenticado` | liberada (tenant único) |
| **>1** | `aguardandoSelecao` | bloqueada (tela `AguardandoSelecao.tsx`, hoje informativa) |
| revalidação não confirmada (rede/5xx) | `sessaoIndisponivel` | bloqueada até revalidar |

- `rotasProtegidas.ts` devolve decisões dedicadas (`semOrganizacao`,
  `aguardandoSelecao`, `indisponivelTemporaria`, `permitir`,
  `redirecionarLogin`); `LayoutAutenticado.tsx` renderiza as telas.
- `AuthProvider` revalida a sessão a cada 60 s e no foco/visibilidade
  (`revalidar()` → `getUser` + re-resolução da identidade), aplicando também os
  limites F2-08 (inatividade/duração) e a distinção Q1 F5-01
  (transitória × revogada).
- O snapshot `IdentidadeResolvida` (`AuthIdentity`) contém `memberships`
  (ativas) e `organizacoes` (derivadas) — **sem nenhuma “organização ativa”**
  persistida ou representada hoje.

### 2.2 Disponibilidade soberana de organizações (F2-03/F4-08)

- `user_organization_memberships` lida pelo próprio usuário (policy own-rows
  F2-03); `organizations` visível somente onde `user_has_active_membership(org)`
  (F4-08 D1: profile ativo + membership ativa).
- Ou seja: **a lista de organizações disponíveis já é soberana (servidor/RLS)**;
  o frontend a recebe do snapshot e nunca a fabrica.

### 2.3 Vínculo (F5-02) e a organização

- Cada membership → 0..1 link `active` → colaborador do mesmo tenant; histórico
  em linhas `disabled`.
- Um colaborador tem no máx. 1 membership ativa por organização; ADMIN pode
  existir sem colaborador.
- `resolver_collaborador_vinculado` (hardened Q4 F5-02) é **interno/server-side**
  e permanece fechado a `authenticated`; o consumo em runtime (SELF/hierarquia/
  ActorContext) é posterior (F5-05).

### 2.4 Frontend DEV × real

- O mundo DEV (`UsuarioAtualProvider`, matrícula, `feedback-control-usuario-atual`)
  continua **isolado** e não participa de autorização server-side. Nada na F5-03
  altera esse gate.

---

## 3. Invariantes

1. **Autoridade:** o tenant efetivo de qualquer operação é **sempre derivado da
   membership ativa do `auth.uid()`** no banco no momento da operação — nunca de
   uma seleção prévia, claim, URL, localStorage ou JWT metadata.
2. **Intenção ≠ autoridade:** “organização ativa” é contexto de UX
   (intenção/“lente”); o servidor revalida em cada autorização/operação.
3. **Disponibilidade soberana:** só aparecem como selecionáveis organizações com
   membership ativa (profile ativo + membership ativa — F4-08 D1).
4. **Sem escolha silenciosa:** com N>1 não há default arbitrário; a seleção é
   explícita e, se a escolha persistida não estiver mais disponível, cai para
   “exige seleção”.
5. **N=1 não é escolha:** com exatamente 1 membership, o tenant é o único valor
   válido — não há ambiguidade a resolver.
6. **Deny no presente:** uma seleção validada em T0 **não** autoriza em T2> T0;
   a revogação entre T0 e T2 é capturada pela revalidação server-side da
   operação (RLS + Policy Engine + resolvers), jamais por confiança no cliente.
7. **Dados por tenant:** dados funcionais carregados são válidos somente para a
   organização em que foram carregados; troca de organização invalida/descarta o
   dataset anterior antes de carregar o novo.
8. **ADMIN sem colaborador:** a seleção de organização é independente do vínculo;
   scopes estruturais (SELF/DR/DESCENDANTS/UNIT) ficam vazios sem vínculo (D17
   F4-02), mas a organização selecionada segue válida para capabilities de nível
   organizacional (membership → role → capability).
9. **Fail-closed:** qualquer dúvida (sem membership, seleção obsoleta, mismatch,
   indisponibilidade de revalidação) ⇒ bloqueio, nunca default de tenant.

---

## 4. Modelo proposto

### 4.1 Conceitos: solicitada × validada × efetiva

| Conceito | Onde vive | Papel | Autoridade? |
| --- | --- | --- | --- |
| **Organização solicitada (intenção)** | Cliente: estado de sessão, localStorage, URL/query (se usada), corpo de requisição | Expressa em qual tenant o usuário quer operar | **Não** |
| **Organização disponível** | Servidor/RLS: memberships ativas do `auth.uid()` (snapshot F5-01) | Define o conjunto selecionável e o que o servidor aceita | Soberana (fonte) |
| **Organização validada** | Servidor: `user_has_active_membership(org)` / resolução da identidade por `(auth.uid(), org)` | Confirma a intenção contra membership ativa | Soberana (resultado) |
| **Organização efetiva** | Servidor (autorização): Policy Engine `ActorRef.organizationId` + RLS | Tenant usado na decisão e nas queries | **= validada**; divergência ⇒ DENY |

Regra: **efetiva = validada**. A “solicitada” só vira “efetiva” depois de
confirmada no servidor no momento do uso. Não existe “cachê de validação” que
sobreviva entre operações.

### 4.2 Representação no cliente (contrato, sem implementação nesta atividade)

- Estado de sessão do frontend: `organizacaoSolicitada` (id) + o snapshot
  soberano `identidade.organizacoes` (disponíveis).
- Marcador persistido opcional (conveniência): última organização escolhida, por
  usuário, em `localStorage` (ex.: `virtus.auth.ultimaOrganizacao`, mapa
  userId→org), **somente como pré-seleção de intenção** — nunca como prova.
- Rota funcional pode, no máximo, **sugerir** intenção via parâmetro opcional;
  o servidor ignora como autoridade.

### 4.3 Derivando o estado funcional (composição)

```
estado = f(identidade, intenção)
  0 memberships ativas        ⇒ semOrganizacao (bloqueado)
  1 membership ativa          ⇒ autenticado — organização efetiva = única (implícita)
  N>1 memberships ativas      ⇒
      intenção válida (∈ disponíveis e confirmada server-side ao usar)
          ⇒ autenticado (contexto = organização validada)
      intenção ausente/inválida
          ⇒ aguardandoSelecao (bloqueado; seleção explícita obrigatória)
```

Nota: a confirmação “server-side ao usar” acontece na **operação** (RLS + engine);
no frontend, o estado `autenticado` apenas indica que há uma intenção coerente com
o snapshot — o servidor decide de fato.

---

## 5. Fluxos

### 5.1 Seleção inicial (N>1)

1. Login/restauração resolve a identidade ⇒ `aguardandoSelecao` (snapshot com N
   organizações disponíveis).
2. Frontend restaura a última escolha (localStorage), se existir **e** ainda
   pertencer às disponíveis; senão, nenhuma pré-seleção.
3. Usuário escolhe explicitamente (lista soberana); a intenção passa a compor o
   contexto; a área funcional é liberada apenas como UX, com todas as operações
   revalidadas no servidor.
4. Se a escolha for de organização sem membership ativa (ex.: estado antigo),
   ela é descartada e o usuário permanece em `aguardandoSelecao`.

### 5.2 Switch de organização

1. Usuário troca a intenção (seletor no shell/header — UX a definir, Q2).
2. **Invalidação local:** qualquer cache/estado de domínio carregado para a
   organização anterior é descartado/limpo (memória, repositórios, dados por
   tenant) antes de carregar a nova.
3. Novo snapshot é revalidado no servidor na próxima operação; nenhum “endpoint
   de ativação” confere autoridade persistente.
4. Se a nova organização não estiver disponível ⇒ bloqueio
   (`aguardandoSelecao`), nunca fallback para a anterior.

### 5.3 Refresh / relogin

1. Refresh: sessão restaurada; `revalidar()` re-resolve identidade (memberships
   atuais); intenção pré-preenchida da última escolha **se** ainda disponível;
   senão, re-deriva (N=0/1/>1).
2. Relogin: novo `sign-in`; identidade re-resolvida do zero; o marcador local de
   última escolha pode reaproveitar (conveniência), sempre revalidado contra as
   memberships atuais.

### 5.4 Revogação mid-session (membership desabilitada / removida)

1. Revalidação periódica (60 s / foco) re-resolve ⇒ o conjunto de memberships
   muda: a organização ativa deixa de existir ⇒ o estado transiciona
   (`autenticado` → `aguardandoSelecao`/`semOrganizacao` conforme restante) e a
   intenção é limpa.
2. Independentemente do estado do cliente, **toda operação é negada no servidor**
   enquanto não houver membership ativa no tenant solicitado (helper + RLS +
   engine) — ver §6 (TOCTOU).
3. Nenhum dado carregado sob a organização revogada continua sendo exibido como
   autorizado após a detecção; a UI reflete o bloqueio na próxima revalidação.

### 5.5 Organização deixa de estar disponível

Disponibilidade = membership ativa (modelo atual não tem status de organização).
Portanto “deixou de estar disponível” é sempre via membership
desabilitada/removida → tratado por 5.4. (Futuro: se `organizations` ganhar
lifecycle, a mesma revalidação cobre.)

---

## 6. TOCTOU — por que a seleção validada não substitui a revalidação

**Cenário:** em T0 o usuário seleciona a organização O (membership ativa
confirmada); em T1 a membership é desabilitada; em T2 o usuário dispara uma
operação funcional em O.

O desenho **não** pode aceitar a validação de T0 como “ticket” para T2, porque:

1. **Autorização é função do estado presente:** cada `authorize()`/consulta
   avalia `auth.uid()` + profile ativo + membership ativa **naquele momento**
   (F4-08 D1). Uma concessão prévia é irrelevante se o predicado falhar em T2.
2. **RLS reavalia por linha/consulta:** qualquer SELECT/mutação futura em tabela
   funcional own-tenant usará `user_has_active_membership(organization_id)` na
   hora da query — se a membership foi revogada, a leitura retorna vazio e a
   mutação não encontra a linha.
3. **Policy Engine revalida no request:** o provider `identity.isMembershipActive
   (actorId, organizationId)` é consultado por requisição; o engine é fail-closed
   e não persiste ALLOW.
4. **A seleção é um ponteiro, não uma permissão:** a intenção escolhida apenas
   diz “o usuário quer operar em O”; o servidor revalida O contra a membership
   ativa atual em cada fronteira (resolver/helper, RLS, engine, RPC transacional).
5. **Erro seguro:** revogação entre T0 e T2 resulta em DENY/`semOrganizacao`/
   `aguardandoSelecao`, nunca em operação parcial ou “vista fantasma” do tenant.

Consequência de desenho: **nenhum componente pode cachear “organização validada”
entre operações**; o máximo cacheado é o snapshot de identidade (curto, já
existente na F5-01) e a intenção de UX, ambos revalidados no uso.

---

## 7. Trust boundaries

| Camada | Mantém | Nunca decide |
| --- | --- | --- |
| Cliente (UI) | Intenção de organização; lista disponível (display); dados por tenant; último selecionado (localStorage) | Se a organização é válida/autorizada |
| Fronteira de aplicação (serviço) | Resolve identidade; chama autorização com `(actorId, org)` | Origem da identidade (vem da sessão) |
| Servidor/banco (RLS + resolvers + RPC) | Membership ativa; tenant dos recursos; vínculo; capabilities | — |
| Policy Engine | Decisão ALLOW/DENY por requisição | — |

Fronteira de confiança: `organization_id` atravessa a fronteira **apenas como
intenção**; toda validação é server-side e por operação. JWT metadata/claims não
carregam tenant.

---

## 8. Persistência

- **Servidor:** nenhuma coluna/tabela/estado de “organização ativa” nesta etapa
  (ver D5/D11; alternativa de persistência server-side discutida em Q1).
- **Cliente (localStorage):** marcador opcional da última organização escolhida,
  por usuário (`virtus.auth.ultimaOrganizacao`), no padrão do marcador
  `virtus.auth.inicioSessao`; removido no logout; tratado exclusivamente como
  pré-seleção de intenção; validado contra o snapshot soberano ao carregar.
- **Sessão do provedor (Supabase):** não é alterada; nada de org em claims.
- **DEV:** o marcador de impersonação (`feedback-control-usuario-atual`) permanece
  isolado e exclusivo de DEV.

### 8.1 Cache/session/localStorage — impactos

- Snapshot de identidade: curto, por resolução (F5-01) — nunca usado como prova
  de tenant após uma mudança de membership.
- Dados funcionais: **chaves de cache por organização** ou limpeza completa no
  switch (invariante 7); nenhum dataset é compartilhado entre tenants.
- Multi-tab: eventos de `storage`/visibilidade podem sincronizar a intenção e
  forçar revalidação (foco já dispara `revalidar()`); decisão de UX em Q6/Q4.

---

## 9. Revogação e invalidação (resumo operacional)

| Evento | Ação no cliente | Ação no servidor |
| --- | --- | --- |
| Membership da org ativa desabilitada | Revalidação detecta; estado re-deriva; intenção limpa; dados da org descartados | DENY em qualquer operação; RLS vazio |
| Seleção persistida não disponível no refresh | Pré-seleção ignorada; `aguardandoSelecao` | Revalidação de identidade |
| Switch de organização | Limpa cache/dados do tenant anterior; carrega sob o novo | Operações revalidam o novo tenant |
| Logout | Remove marcador de última org | — (sem estado server-side) |
| Falha transitória de revalidação | `sessaoIndisponivel` (F5-01) — sem conteúdo | — |

---

## 10. Segurança

- **Tenant spoofing:** a intenção pode ser falsificada; a autoridade nunca é
  falsificável (membership no banco). Testes obrigatórios de IDOR e spoofing.
- **Nenhuma prova em claims/URL/localStorage:** proibido usar qualquer um como
  fonte de tenant; JWT metadata não carrega org.
- **Sem endpoint de autoridade:** “ativar organização” é mudança de contexto de
  UX; não existe endpoint que persista autorização por org.
- **Fail-closed:** ausência de membership ⇒ DENY, estado bloqueado, sem default.
- **Menor privilégio:** nenhum novo grant genérico a `authenticated`; nenhum novo
  `SECURITY DEFINER` sem necessidade (não há necessidade nesta etapa — validação
  usa helpers/resolvers existentes e RLS).
- **C/D e confidencialidade:** intactos — a seleção de org não altera
  classificação de confidencialidade nem grants excepcionais.

---

## 11. Impacto em RLS

- Nenhuma policy/tabela nova nesta atividade (a seleção é contexto de UX).
- As políticas F2-03/F4-08 já entregam: própria membership legível; organizações
  somente com membership ativa; future tabelas funcionais seguirão o padrão
  F4-08 D16 (own-tenant via `user_has_active_membership(organization_id)`).
- **Recomendação de contrato:** qualquer consulta funcional futura não recebe
  “org ativa” como filtro confiável do cliente — o tenant vem da linha do
  recurso sob RLS; o parâmetro de intenção pode no máximo restringir a
  apresentação, nunca ampliar.

---

## 12. Integração com F5-02 / F5-04 / F5-05

- **F5-02:** a organização (validada) escolhe qual membership → vínculo →
  colaborador é o contexto (SELF/estrutural). Colaborador por organização já é
  único (1 membership ativa por colaborador+org — Q3 F5-02). ADMIN sem vínculo:
  seleção normal; scopes estruturais vazios (D17 F4-02), capabilities de nível
  organizacional válidas por membership → role.
- **F5-04 (futuro):** capability efetiva é resolvida por `(user_profile_id,
  organization_id)` — a organização validada é o parâmetro; a seleção não altera
  a resolução de roles.
- **F5-05 (futuro):** ActorContext consumirá a **organização validada**
  (`ActorRef.organizationId`) montada pelo serviço a partir da intenção
  confirmada contra membership ativa — nunca direto da UI. F5-03 deixa o seam:
  interface de “intenção de organização” no contexto de sessão e contrato de
  validação server-side; ResourceContext dos domínios usará o mesmo princípio.

---

## 13. Migrations previstas

**Nesta etapa: NENHUMA** — não há tabela/coluna/índice/função nova necessária
para representar a organização ativa (D5/D11). A validação reutiliza
`user_has_active_membership`, a RLS F2-03/F4-08 e o snapshot de identidade.

Condicional (somente se uma questão aberta decidir diferente):
- **Q1 = persistência server-side da última organização** ⇒ migration aditiva
  (coluna opcional em `user_profiles` ou tabela própria de preferências por
  usuário), justificada apenas por requisito multidispositivo — não recomendada
  nesta fase.

---

## 14. Estratégia de testes (segurança/isolamento)

**Unitário (TS):**
- derivar estado por N (0/1/>1); transições de revalidação
  (`autenticado`→`semOrganizacao`, `autenticado`→`aguardandoSelecao` quando a org
  ativa é revogada); intenção ausente/inválida ⇒ bloqueio; regressão F5-01/F5-02.

**Integração/validação SQL (Supabase local — padrão `supabase/validacao`):**
- revogação de membership **durante** uma sessão: usuário perde a org e passa a
  não resolver organização (reuso dos cenários F4-08/f2-10);
- cross-tenant: selecionar/solicitar organização de outro usuário/tenant ⇒
  DENY/vazio (RLS e resolvers);
- **IDOR/spoofing:** forjar `organization_id` em chamadas/rotas ⇒ servidor não
  entrega nada sem membership ativa; intenção nunca amplia;
- ADMIN sem colaborador: seleção de org válida; scopes estruturais vazios;
  capabilities organizacionais resolvem (F4-01/02).
- **TOCTOU (simulado):** validar T0, desabilitar membership (T1), operar em T2 ⇒
  DENY (nenhum ALLOW cacheado) — cenário em `02-validar-*.sql`.

---

## 15. Riscos

| Risco | Mitigação |
| --- | --- |
| Transformar seleção em autoridade | Invariantes 1/2; revalidação por operação |
| Vazamento entre tenants via cache | Cache por tenant/limpeza no switch (invariante 7) |
| Revogação mid-session com estado obsoleto | Revalidação 60 s/foco + DENY server-side (TOCTOU §6) |
| Persistir org em claims/JWT/localStorage como prova | Proibido; marcador é só intenção |
| UX confusa com N>1 (default silencioso) | Sem default; seleção explícita; estado `aguardandoSelecao` |
| Regressão de F5-01 (estados) / F5-02 (vínculo) | Contratos preservados; testes de regressão |

---

## 16. Fora de escopo (F5-03)

- Implementação funcional (documento apenas);
- vínculo usuário↔colaborador (F5-02 — concluída);
- roles/capabilities efetivas em runtime (F5-04);
- ActorContext/ResourceContext (F5-05);
- persistência remota dos domínios funcionais; migração de `localStorage`;
- hardening geral (F6); hosting/observabilidade/backup;
- mudanças no Policy Engine, em RLS de domínios ou em estrutura organizacional.

---

## 17. Decisões arquiteturais (D1–D13 — PROPOSTAS para revisão)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | Organização ativa = contexto de UX (intenção/lente) | Nunca autoridade; tenant efetivo sempre derivado da membership ativa do `auth.uid()` na operação | PROPOSTA |
| D2 | Fonte soberana de disponibilidade | Memberships ativas do `auth.uid()` (profile ativo + membership ativa), refletidas no snapshot F5-01/RLS | PROPOSTA |
| D3 | Comportamento por cardinalidade | 0 ⇒ `semOrganizacao`; 1 ⇒ `autenticado` com tenant único implícito (sem tela de seleção — não é escolha); >1 ⇒ `aguardandoSelecao` + seleção explícita | PROPOSTA |
| D4 | Representação da intenção | Estado de sessão do frontend + marcador localStorage por usuário (última escolha), como conveniência validada ao carregar | PROPOSTA |
| D5 | Sem estado server-side de org ativa | Nenhum endpoint/coluna que confira autoridade; “ativar” é contexto de UX; validação por operação | PROPOSTA |
| D6 | Revalidação por operação | Toda fronteira (helper/resolver, RLS, engine, RPC) revalida (auth.uid, org) contra membership ativa; DENY se ausente | PROPOSTA |
| D7 | Revogação mid-session | Revalidação periódica re-deriva estado; intenção limpa; servidor nega qualquer operação no tenant revogado (§6) | PROPOSTA |
| D8 | Anti-spoofing | Claims/JWT metadata/URL/localStorage nunca provam tenant; cross-tenant DENY; testes IDOR | PROPOSTA |
| D9 | Switch = invalidação | Troca de org descarta cache/dados do tenant anterior antes de carregar o novo | PROPOSTA |
| D10 | ADMIN sem colaborador | Seleção normal; scopes estruturais vazios; capabilities organizacionais válidas (D17 F4-02) | PROPOSTA |
| D11 | Sem migration nesta etapa | Nenhuma estrutura nova; reuso de helper/RLS/snapshot (condição Q1 documentada) | PROPOSTA |
| D12 | Fail-closed de estado | Sem default de tenant; dúvida/ausência ⇒ bloqueio com tela dedicada (estados F5-01) | PROPOSTA |
| D13 | Seam para F5-05 | F5-03 entrega a “intenção de organização” + validação server-side; ActorContext consumirá `(auth.uid, org validada)` | PROPOSTA |

---

## 18. Questões para validação

### Q1 — Persistência da última organização: só cliente ou também servidor?

- **Contexto:** a restauração após refresh usa localStorage (por dispositivo). A
  F5-03 decide se deve também persistir no servidor para restaurar em outros
  dispositivos.
- **Por que:** define se há migration/estado server-side (contraria D5/D11) e a
  superfície de privacidade/dados.
- **Alternativas:** (A) apenas cliente (localStorage por usuário) —
  recomendado; (B) servidor (coluna/tabela de preferência + endpoint) —
  consistência multidispositivo.
- **Recomendação:** (A) nesta fase; (B) apenas se produto exigir
  multidispositivo.
- **Impacto/risco:** (A) sem migration/estado; (B) migration + sincronização +
  mais superfície (segurança/privacidade).
- **Seções dependentes:** 8, 13, D5, D11.

### Q2 — UX de seleção inicial e switcher (escopo F5-03)

- **Contexto:** hoje `AguardandoSelecao` bloqueia com mensagem; o switcher no
  shell ainda não existe.
- **Por que:** F5-03 precisa fechar onde/p como o usuário seleciona (tela de
  primeira escolha + seletor no header) e o que acontece com N=1 (indicador de
  tenant).
- **Alternativas:** (A) tela dedicada na primeira entrada (N>1) + seletor no
  header; (B) apenas seletor no header; (C) lista modal central.
- **Recomendação:** (A) — tela de entrada explícita e seletor persistente.
- **Impacto/risco:** decisão de UX/IA; sem impacto de segurança (independe).
- **Seções dependentes:** 5, 8, D3, D4.

### Q3 — Latência de detecção de revogação: 60 s/foco é suficiente?

- **Contexto:** a revalidação periódica (60 s + foco) limita a “janela” de UI
  obsoleta após revogação.
- **Por que:** produto pode exigir detecção mais rápida (SSE/websocket/polling
  curto).
- **Alternativas:** (A) manter 60 s+foco (recomendado — fail-closed no servidor
  torna a latência de UX aceitável e sem custo); (B) polling agressivo/SSE.
- **Recomendação:** (A).
- **Impacto/risco:** latência de UX de até ~60 s na UI, mas zero risco de acesso
  (servidor nega antes).
- **Seções dependentes:** 5.4, 6, 14.

### Q4 — Rotas/URLs devem transportar `organizationId`?

- **Contexto:** deep-links/URLs poderiam carregar org; o contrato proíbe URL como
  autoridade.
- **Por que:** decidir se rotas funcionais levam org (ex.: `/org/:orgId/...`) ou
  permanecem sem tenant na URL.
- **Alternativas:** (A) sem org na URL (recomendado — RLS + contexto);
  (B) org na URL só como intenção/deep-link, revalidada.
- **Recomendação:** (A); se (B), documentar que nunca amplia.
- **Impacto/risco:** (B) aumenta superfície de interpretação e testes.
- **Seções dependentes:** 4, 10, 14.

### Q5 — Apresentação da identidade por organização (nome/avatar do colaborador)

- **Contexto:** com vínculo F5-02, cada organização pode ter um colaborador (e um
  perfil de apresentação) diferente para o mesmo usuário.
- **Por que:** a barra/UX por tenant pode precisar exibir o colaborador vinculado
  à organização ativa (ex.: “você está operando como Fulano na Org X”).
- **Alternativas:** (A) exibir identidade organizacional (colaborador vinculado)
  somente na organização ativa, quando existir vínculo; (B) manter apenas
  identidade de conta nesta fase.
- **Recomendação:** (A) futuramente, quando F5-05 expor a resolução; nesta F5-03
  registrar o requisito de UI sem implementar.
- **Impacto/risco:** depende de exposição server-side da F5-05 (Q1/Q2 F5-02 =
  manter fechado por enquanto).
- **Seções dependentes:** 12, D10, F5-02 Q1/Q2.

---

## 19. Confirmações desta atividade

- **Nenhuma implementação funcional** foi feita; **somente** este documento.
- Base: `main` com F5-01 (#159/#160) e F5-02 (#161/#162) mergeadas — estado do
  código verificado (estados de sessão, guard, RLS F2-03/F4-08, vínculo F5-02).
- Decisões D1–D13 **propostas**; questões Q1–Q5 registradas e podem permanecer
  abertas no PR.
- Próximos passos: revisar D1–D13 e responder Q1–Q5; só então implementar a
  seleção/switcher da F5-03 (PR próprio).
