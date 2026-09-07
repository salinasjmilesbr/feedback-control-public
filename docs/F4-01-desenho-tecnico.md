# F4-01 — Desenho técnico: catálogo de capabilities e roles de acesso (Issue #88)

> **Status:** revisão arquitetural **concluída**; decisões D1–D18 **fechadas**
> na seção 12 (D14, D16 e D18 com ajustes registrados). Nenhuma migration,
> schema, código funcional, teste final ou PR de implementação é criado nesta
> entrega — somente este documento, em branch exclusiva de docs.
> Conteúdo 100% conceitual e sintético (sem dados reais).

## 1. Objetivo e escopo

### 1.1 Interpretação da Issue #88

A Issue #88 pede o **modelo explícito de autorização no banco** para o Virtus,
sem derivar permissões de cargo/função organizacional. Concretamente, a F4-01
deve estabelecer o **catálogo de `capabilities`** (unidade explícita de
permissão) e os **`access_roles`** (agrupadores configuráveis de capabilities),
e a **associação desses roles/capabilities às memberships** de organização,
mantendo:

- **ADMIN** como papel de plataforma/acesso, separado da hierarquia
  organizacional e **independente de collaborator/occupation**;
- **ADMIN sem leitura automática de conteúdo confidencial**;
- tenant isolation e RLS **deny-by-default** preservados;
- preparação para auditoria e acesso excepcional **sem hardcodar pessoas**;
- `job_role`/cargo **nunca** como fonte permanente de autorização.

### 1.2 O que entra na F4-01

- Desenho do modelo conceitual: capabilities, access_roles, associação
  role→capability e membership→access_role (e avaliação de concessão direta).
- Taxonomia inicial de capabilities e bundle inicial de access_roles.
- Regras de multi-organização, histórico/mutabilidade, RLS baseline e
  transição dos mecanismos provisórios (allowlists das Fases 2).
- Decisões D1–D18 **fechadas** após revisão arquitetural (registro na seção 12).

### 1.3 O que NÃO entra na F4-01 (fora do escopo, reafirmado da Issue #88)

- **Escopo hierárquico** (SELF, DIRECT_REPORTS, DESCENDANTS,
  ORGANIZATIONAL_UNIT, ORGANIZATION, ASSIGNED e escopo temporário de
  substituição): modelado na **F4-02**, que também consumirá a resolução
  estrutural da F3-07 e as substituições da F3-06;
- **autorização por recurso** (policies finais por tabela) e liberação ampla de
  leitura/escrita: etapas posteriores da Fase 4 (a leitura/escrita ampla não
  será liberada antes da etapa que a autorizar explicitamente);
- **UI final de administração** de roles/capabilities;
- **dados reais** (somente conceitos e, na implementação futura, dados
  sintéticos);
- neste documento: **nenhuma** migration, alteração de schema/RLS/policies,
  alteração de Edge Functions/frontend, remoção de allowlist provisória,
  criação de testes finais, PR de implementação ou merge.

## 2. Estado atual relevante

### 2.1 Identidade e autenticação (F2-01, F2-03..F2-10)

- `auth.users` (Supabase Auth) é a identidade de autenticação; o signup público
  está desabilitado e o acesso é por convite/recuperação (F2-05/F2-06).
- `public.user_profiles` é o perfil interno **1:1 com `auth.users`**
  (`id` = mesmo UUID, `status` `active`/`disabled`), sem credenciais.
- O usuário autenticado resolve a própria identidade por `auth.uid()`; um
  perfil `disabled` deixa de ser legível pelo próprio usuário (F2-07).
- F2-10 comprovou isolamento de identidade: resolução exclusivamente por
  `auth.uid()`, nunca por e-mail/estado local.

### 2.2 Memberships e organizações (F2-02, F2-03)

- `public.organizations` — organização como raiz do tenant (id/name/timestamps/
  version; sem slug/identidade legal nesta fase).
- `public.user_organization_memberships` — vínculo de acesso
  usuário→organização, **uma linha por par** (unique em qualquer status),
  `status` `active`/`disabled`; a desabilitação/reativação ocorre no lugar,
  preservando `created_at`.
- RLS atual (F2-03 + F2-07) — **única policies existentes no banco**:
  1. `user_profiles_select_own` (próprio perfil, `status='active'`);
  2. `user_organization_memberships_select_own` (próprias memberships);
  3. `organizations_select_via_membership` (organizações alcançáveis por
     membership **ativa**).
- Não há policies de escrita para `authenticated`; grants de SELECT apenas
  para essas três tabelas.

### 2.3 Colaborador e estrutura organizacional (F3)

A Fase 3 modelou a estrutura **formal e temporal**:

- `collaborators` (+ `collaborator_identifiers`, `collaborator_status_periods`)
  — identidade técnica por organização, códigos de negócio e lifecycle
  `active`/`leave`/`inactive`; **sem cargo armazenado no colaborador**.
- `job_roles` e `seniority_levels` — catálogos configuráveis **por organização**
  (`name` único por org, `status` `active`/`disabled`, sem ordenação/nível),
  conceitualmente **independentes da hierarquia e da autorização**.
- `organizational_units`, `organizational_unit_parent_periods`,
  `organizational_positions` — unidades/posições formais com existência
  temporal e FKs compostas `(ref_id, organization_id)` para integridade de
  tenant declarativa.
- `position_reporting_lines` — hierarquia formal temporal (superior único por
  posição; raiz por ausência de linha; ciclos bloqueados).
- `occupations` — ocupação temporal colaborador↔posição (mesma org); vacância =
  ausência de occupation.
- `temporary_responsibilities` — substituição temporária
  (`operational`/`evaluative`/`operational_evaluative`, período fechado).
- Resolução estrutural (F3-07), 7 funções `SECURITY INVOKER`/`STABLE` sem
  grants adicionais: `organizacao_resolver_responsavel_posicao`,
  `gestor_direto`, `subordinados_diretos`, `descendentes`, `cadeia`,
  `escopo_posicoes`, `escopo_unidades`.
- F3-08/F3-09: `collegiate_configurations`(+membros), snapshots imutáveis por
  ciclo, `cycle_evaluation_responsibilities`,
  `evaluation_succession_events` (com `author_user_profile_id` → `user_profiles`
  como autor canônico), RPCs `materializar_*`/`registrar_sucessao_avaliador`/
  `resolver_responsavel_avaliacao_vigente` — todas `SECURITY INVOKER`.
- **RLS deny-by-default em todas as tabelas da F3**: RLS habilitada, nenhuma
  policy, nenhum grant a `authenticated` — nenhum usuário autenticado lê ou
  escreve estrutura/catálogo/ocupações hoje via API.

### 2.4 Mecanismos provisórios de autorização existentes (a substituir na F4)

1. **Allowlist administrativa server-side** (`INVITE_ADMIN_USER_IDS`, variável
   de ambiente; default local com UUID sintético fixo) usada pelas Edge
   Functions `convidar-usuario` (F2-06) e `gerenciar-usuario` (F2-07), sempre
   **fail-closed**, somada ao requisito de perfil ativo do chamador. Os
   comentários das próprias funções declaram o caráter provisório: "Autorização
   (mínima, até a Fase 4)".
2. **`verify_jwt = false`** nas duas Edge Functions locais: a autenticação é
   feita internamente via `auth.getUser()` do JWT (não há bypass real), mas o
   gate do gateway não é usado — conveniência local a reavaliar.
3. **RPC `criar_perfil_membership`** (`SECURITY DEFINER`, `set search_path`,
   EXECUTE **somente** `service_role`) — fronteira server-side do convite.
4. **Frontend/localStorage**: o domínio funcional ainda persiste em
   `localStorage` (Fase B); `src/authorization` concentra a policy central
   (`can`/`authorize`/`scopeCollaborators`) e o catálogo TS de capabilities
   (`src/authorization/Capability.ts`). Parte das decisões dessa policy ainda
   usa **cargo/função organizacional** (`actor.funcao` — GERENTE/COORDENADOR/
   ANALISTA/ESTAGIARIO) e regras relacionais de avaliação/metas
   (`permissaoAvaliacao`, `visibilidadeColaboradores`, `relatorioService`,
   `metaStorage`). Esse é o ponto atual que ainda deriva autorização de
   cargo — será substituído quando o domínio migrar (F5) consumindo o modelo
   da F4 no servidor.
5. Identidade de visão DEV por **impersonação** sobre o seed sintético
   (`src/contexts/impersonacaoDev.ts`), restrita a development e nunca
   participando de autorização server-side (F2-09).

### 2.5 Pontos hardcoded/temporários que futuramente serão substituídos

- A allowlist `INVITE_ADMIN_USER_IDS` e o conceito implícito de "administrador
  global de usuários" das Edge Functions (→ capabilities/roles + RLS).
- Ausência de qualquer representação de ADMIN no banco (hoje é só variável de
  ambiente + UUID local).
- O catálogo TS `Capability` e as regras por `actor.funcao` no frontend (→
  catálogo canônico no banco + mapeamento de vocabulário, ver D15).
- A inexistência do vínculo `user_profile → collaborator` (futuro; relevante
  para os escopos SELF/DESCENDANTS da F4-02 e para a resolução por ocupação).
- RLS sem nenhuma policy nas tabelas de domínio (intencional até a etapa que
  autorizar leitura/escrita).

## 3. Modelo conceitual proposto

Entidades candidatas (nomes segundo as convenções F1-02; **decisões de forma
finais nas decisões D**):

### 3.1 `capabilities`

Catálogo da **unidade explícita de permissão**. Colunas candidatas:

- `id uuid pk default gen_random_uuid()`;
- `code text not null` — código estável e único (vocabulário em D15);
- `name text not null` + `description text` — apresentação/documentação;
- `status text not null default 'active'` — `active`/`disabled`
  (inativação sem exclusão física; conjunto ampliável por migration);
- grupo/área (coluna ou convenção de prefixo no `code`) — organização da
  taxonomia (ver seção 5);
- `organization_id uuid null` — **catálogo global** (null) vs por organização
  (D1);
- timestamps `created_at`/`updated_at` e `version`, conforme F1-02.

Evolução futura (não criar agora): capabilities de confidencialidade
separáveis por domínio/recurso quando houver necessidade concreta (D18 — sem
capability genérica única nesta fase) e metadados de auditoria.

### 3.2 `access_roles`

Agrupadores **configuráveis** de capabilities — papel de **acesso**, jamais de
cargo. Colunas candidatas:

- `id uuid pk`;
- `name text not null` (ou `code` + `name`, D8);
- `status text not null default 'active'`;
- `is_system boolean not null default false` (D2/D6) — role de sistema
  (bootstrap) vs customizável;
- `organization_id uuid null` — roles de sistema (null, globais) vs
  customizadas por organização (D2/D10);
- timestamps/version conforme F1-02.

### 3.3 Associação `access_roles` → `capabilities` (N:N)

- `id`, `access_role_id`, `capability_id`, timestamps;
- unicidade `(access_role_id, capability_id)`;
- a associação deve respeitar o tenant da role/capability (D11).

### 3.4 Associação `membership` → `access_roles` (atribuição)

- Tabela-âncora de atribuição por membership, preparada para receber escopo na
  F4-02 sem quebra (D12): mínimo `id`, `user_organization_membership_id`
  (ou FK composta membership/org), `access_role_id`, timestamps;
- alternativas de shape em D4/D12 (uma linha por role; ou linhas
  role+escopo futuras);
- revogação por inativação/preservação de linha (D6/D7/D13).

### 3.5 Concessão direta de capability (avaliar)

- Alternativa opcional `membership_capabilities` (idem atribuição) **somente**
  se houver concessão direta além de roles; **D3 = A**: não criar nesta fase
  (roles como única via, reduzindo superfície).

### 3.6 Status, tenant e metadados

- Todos os catálogos com `status` `active`/`disabled` e sem exclusão física.
- Ownership de organização conforme D2/D10, com **FKs compostas**
  `(id, organization_id)` (padrão F3) sempre que o tenant precisar ser
  garantido declarativamente.
- Metadados para evolução: `is_system`, timestamps/`version`, e campos de
  autor mínimo (D13); descrições ajudam documentação sem código.

### 3.7 Relacionamentos conceituais (resumo)

```
auth.users ─1:1─ user_profiles ─1:N─ user_organization_memberships
                                          │ (status ativa)
                                          └─N:M─ access_roles ─N:M─ capabilities
collaborators/job_roles/positions/...  ⇏  NENHUM vínculo de autorização
```

Nenhuma tabela da F3 referencia access_roles/capabilities; a autorização só
existe no plano membership/role/capability (regra de ouro da seção 11).

## 4. Separação obrigatória de conceitos

| Conceito | O que é | Por que não pode ser fundido |
| --- | --- | --- |
| `user_profile` (auth user) | Identidade de acesso (1:1 `auth.users`); global, sem organização | É quem autentica; existe antes/independente de qualquer organização e de qualquer colaborador |
| `membership` | Vínculo de acesso do perfil a **uma** organização (`active`/`disabled`) | É a âncora de tenant da autorização; sem ela não existe autorização organizacional; desabilitar a membership remove o acesso sem tocar identidade |
| `collaborator` | Pessoa na estrutura organizacional (matrícula, lifecycle), por organização | Colaborador é entidade de domínio; **não é usuário de acesso**; o vínculo auth→collaborator ainda não existe (futuro, para SELF/escopos) |
| `job_role` (cargo) | Catálogo de função organizacional (ex.: Analista, Coordenador) | Descreve o **papel no trabalho**, não o que a pessoa pode fazer no sistema; cargo **não concede** capability |
| `access_role` | Bundle configurável de capabilities atribuído a uma membership | É a unidade de **atribuição de permissão**; pode ser dado a quem ocupa qualquer cargo (ou a quem não tem cargo, ex.: ADMIN sem colaborador) |
| `capability` | Permissão atômica explícita (ex.: criar avaliação) | É o **menor enunciado de permissão**; independe de quem pede e de onde (escopo vem da F4-02) |
| `ADMIN` | access_role de sistema **de acesso**, atribuído por membership/organização (D17) | Papel de acesso, não posição da hierarquia; **não** confere conteúdo confidencial automaticamente e **não** é SUPER_ADMIN irrestrito |

Regras decorrentes:

- um colaborador com cargo "Gerente" **não ganha** permissão alguma por isso;
  se quiser agir como gestor de pessoas, recebe um access_role (ex.: com
  escopo DESCENDANTS na F4-02);
- um usuário pode ter membership sem ser colaborador (ex.: ADMIN/administrador
  de acesso), e um colaborador pode não ter usuário (pessoa cadastrada sem
  acesso);
- `seniority_levels`, `positions`, `occupations`, `organizational_units` e
  `temporary_responsibilities` **não participam** da concessão de capabilities
  (a substituição temporária afetará escopo na F4-02, não capability).

## 5. Capabilities iniciais

Taxonomia proposta em grupos, com códigos candidatos em notação `domínio.verbo`
(espelhando o vocabulário atual de `src/authorization/Capability.ts`, ver D15).
A lista é **inicial e propositalmente não excessiva**: cada capability é a
unidade mínima de permissão; o **alcance** (quantos colaboradores/recursos) é
decisão de **escopo na F4-02**, nunca desta capability.

| Grupo | Capabilities candidatas | Observações |
| --- | --- | --- |
| Administração de acesso (usuários/memberships/roles) | `membership.read`, `membership.manage`, `access_role.manage` (configurar roles/capabilities da organização e atribuí-las) | Administração de contas/convites/desativação pode ser capability de plataforma — D17 |
| Administração organizacional | `collaborator.read`, `collaborator.manage` (cadastro), `org.structure.manage` (unidades, posições, reporting lines, occupations, movimentações), `org.catalog.manage` (job_roles/seniority_levels) | Leitura de colaboradores **não** implica ler conteúdo confidencial; quem vê quem é escopo |
| Administração de configurações | `settings.manage` (escala, expectativas de cargo, regras de ciclo/config geral) | Mantém o nome já usado no frontend |
| Ciclos | `cycle.read`, `cycle.manage` (criar, ativar, encerrar; cancelar/reabrir/corrigir período são operações excepcionais auditáveis — a capability existe, o fluxo auditado permanece regra de domínio) | Estado do domínio continua barrando mutação inválida mesmo com capability (F4-10) |
| Avaliações | `evaluation.read`, `evaluation.create`, `evaluation.write`, `evaluation.cancel`, `evaluation.reopen` | Conteúdo de avaliações de terceiros é **confidencial** (D18): acesso por capabilities explícitas separáveis por domínio (a definir quando houver necessidade concreta) + escopo (F4-02); nunca automático por ADMIN |
| Metas | `goal.read`, `goal.write` (criar/editar/progredir/finalizar próprias e de terceiros conforme escopo), `goal.approve` | O "próprio" do colaborador virá de escopo SELF + capability, não de capability `.own` |
| Observações | `observation.read`, `observation.write` (criar/editar/excluir em ciclo ATIVO) | Visibilidade de `Comunicado` para o colaborador é regra de conteúdo/escopo futura, não capability |
| Relatórios | `report.read` (gerenciais/equipe e histórico individual) | Histórico próprio = escopo SELF + `report.read` |
| Confidencial | **Nenhuma capability genérica única de confidencialidade é catalogada nesta fase** (D18): o princípio modelado é que conteúdo confidencial exige capability explícita, separável por domínio/recurso quando a necessidade concreta surgir (ex.: acesso excepcional a avaliações não implica acesso a todo conteúdo confidencial) | ADMIN **nunca** recebe capabilities confidenciais automaticamente |
| Auditoria | Sem capability de auditoria nesta fase (reservada conceitualmente) | Trilha avançada e acesso excepcional auditado são etapas posteriores da F4 |

Nota de mapeamento (para o corte futuro do frontend): capabilities legadas com
sufixo de papel/escopo (`cycle.cancel.manager`, `evaluation.edit.board`,
`goal.approve.coordinator`, `goal.create.own`, `evaluation.view.admin`) **não**
são replicadas como estão no banco: a F4 separa a capability (`cycle.cancel`) do
quem/onde (`manager`/`board`/escopo). O mapeamento 1:N do vocabulário antigo
para o novo será feito quando o domínio migrar (F5), sem quebrar a regra de não
duplicar autorização em páginas (a policy central `src/authorization` continua
a única porta no frontend até lá).

## 6. Access roles iniciais (conjunto mínimo — D14)

A revisão arquitetural fechou a F4-01 com um **conjunto mínimo** de
access_roles: **um único access_role de sistema — `admin`** — atribuído por
membership/organização, como papel de **acesso** (nunca posição hierárquica).

| Access role (código candidato) | Natureza | Capabilities típicas (rascunho) | Notas |
| --- | --- | --- | --- |
| `admin` | Sistema/bootstrap, atribuído **por membership** (por organização) | Administração da organização: `membership.read`, `membership.manage`, `access_role.manage`, `collaborator.read`, `collaborator.manage`, `org.structure.manage`, `org.catalog.manage`, `settings.manage`, `cycle.read` | Não exige collaborator/occupation; **sem** capabilities de conteúdo confidencial e **sem** SUPER_ADMIN; escopo administrativo é a organização da membership (D17) |

Regras (D14, com D2/D6/D9):

- **Nenhum bundle espelha cargo organizacional**: GERENTE/COORDENADOR/
  CONSULTOR/ANALISTA/ESTAGIARIO permanecem apenas no catálogo `job_roles` e
  jamais concedem acesso;
- **não existe access_role genérica `manager`/`collaborator` nesta fase**;
  bundles de gestão/colaborador surgirão somente quando houver necessidade
  concreta de autorização, no contexto dos escopos da F4-02+, e com
  nomenclatura que não colida com cargos;
- roles **customizadas por organização** podem ser criadas quando houver
  necessidade (composições a partir das capabilities), sempre inativáveis e sem
  exclusão física (D6);
- roles de sistema são inativáveis apenas por migration e nunca renomeáveis
  (D6); o catálogo de sistema nasce versionado por migration (D9/D16).

O catálogo de capabilities da seção 5 existe desde a F4-01 mesmo sem bundles
que as consumam: capability sem role atribuída **não produz efeito** (não há
atribuições além do necessário e a RLS permanece deny-by-default); os bundles
serão fechados quando cada necessidade concreta surgir (F4-02+).

## 7. Multi-organização

Invariantes de tenant para o modelo:

1. **Roles/capabilities da Organização A não podem ser atribuídas na
   Organização B**:
   - roles customizadas com `organization_id`; capabilities com escopo de
     tenant conforme D1/D11;
   - atribuição sempre **ancorada na membership** (usuário+organização): a FK
     composta garante que a role atribuída pertença à mesma organização da
     membership (padrão de FKs compostas da F3, ex.: `(id, organization_id)`
     com `uq` de referência);
   - validação declarativa preferida a triggers (padrão F3-03/F3-05), com
     triggers apenas quando necessário.
2. **Membership desabilitada não obtém autorização**: qualquer resolução futura
   exige membership `active` (mesma lógica que já rege
   `organizations_select_via_membership` na F2-03). Desabilitar a membership é
   a revogação limpa de tudo que ela atribuía.
3. **Usuário sem membership não obtém autorização organizacional**: não existe
   atribuição sem linha de membership; usuário com perfil `disabled` também é
   barrado (F2-07).
4. Leitura multi-org continua restrita: a F4-01 **não cria** policies novas; a
   exposição futura será por policies restritivas ancoradas em membership ativa
   (etapa posterior autorizada), preservando o deny-by-default atual.

## 8. Histórico e mutabilidade

Posicionamento consolidado na revisão (decisões fechadas D5/D6/D7/D13):

- **Validade temporal dos assignments** (D7 = A): **não** introduzir
  `valid_from`/`valid_to` na F4-01. A F4-02 modelará o escopo (incluindo escopo
  temporário derivado de substituição F3-06, que expira com a própria
  substituição); acesso excepcional com janela/motivo é F4-09. A F4-01 deve
  apenas **não bloquear** essa evolução (D12), ex.: mantendo a atribuição em
  tabela própria e evitando colunas/checks que impeçam adicionar vigência.
- **Remoção apaga ou preserva?** Convenção F1-02 e histórico: **sem exclusão
  física**. Roles/capabilities/atribuições seguem o padrão das Fases 2/3
  (desativação `status`/preservação de linha com `created_at` original).
  Revogar uma atribuição = inativar/registrar revogação na linha (shape exato
  em D6/D13), preservando quem tinha o quê.
- **Como auditorias futuras reconstroem "quem tinha qual role/capability"?**
  As linhas de atribuição preservadas (com timestamps e autor — D13 = A)
  permitem reconstrução; trilha de auditoria formal/append-only e acesso
  excepcional são etapas posteriores da F4 (não inventar auditoria completa
  aqui).
- **Implementar agora ou preparar o modelo?** F4-01 implementa apenas o modelo
  com campos mínimos de evolução (`status`, `is_system`, timestamps/version,
  autor por D13) — sem tabela de auditoria, sem vigência, sem escopo.

## 9. RLS e exposição

Baseline apropriado à F4-01 (não é liberação de acesso):

- **RLS habilitado** em toda tabela nova do modelo de autorização;
- **deny-by-default**: nenhuma policy criada nesta etapa; nenhum grant novo a
  `authenticated`/`anon`; as tabelas de autorização ficam inacessíveis via API
  (mesmo padrão aplicado a todas as tabelas da F3), **até** a etapa da F4 que
  autorizar explicitamente leitura/escrita;
- **SECURITY INVOKER** em funções futuras do modelo (padrão F3-07/F3-08): o
  chamador enxerga somente o que a RLS permitir — nenhum bypass;
- **sem `service_role` no cliente**: acesso privilegiado restrito a Edge
  Functions/server-side, como hoje (RPC `criar_perfil_membership` é o único
  precedente e é exclusivo `service_role`);
- **qualquer mecanismo técnico mínimo de atribuição/bootstrap (D16)** é
  exclusivamente server-side, valida membership e tenant, **não amplia RLS**
  (sem policies novas), não substitui prematuramente as allowlists existentes e
  **não cria bypass de autorização** (SECURITY INVOKER; sem `SECURITY DEFINER`
  desnecessário);
- **sem liberar leitura/escrita ampla antes da etapa da F4 que a autorizar**
  (mencionada pelo roadmap como "F4-08"): catálogos de capabilities/roles
  precisarão de leitura segura para o cliente **somente** quando a UI e as
  policies finais existirem;
- regras de autorização **não são duplicadas** em policies por tabela enquanto
  o modelo efetivo (capability+escopo) não estiver completo (F4-02+): qualquer
  enforcement intermediário permanece centralizado (server-side/policy única),
  conforme AGENTS.md.

## 10. Migração dos mecanismos provisórios

| Mecanismo provisório | Onde | Substituição futura | Ação na F4-01 |
| --- | --- | --- | --- |
| Allowlist `INVITE_ADMIN_USER_IDS` nas Edge Functions | `supabase/config.toml` + `functions/*/index.ts` | Capacidade/role de administração de acesso resolvida no banco por `auth.uid()` + membership + role (com RLS), nas etapas que migrarem essas funções | **Não remover**; nenhuma alteração em Edge Functions agora |
| `verify_jwt = false` local | `supabase/config.toml` | Reavaliar quando houver autorização server-side por capability | Manter (sem mudança) |
| `user_profiles.status` como piso mínimo nas funções | Edge Functions | Já espelhado por RLS (F2-07); continuará como pré-condição | Manter |
| ADMIN implícito em variável de ambiente (sem linha no banco) | config local + seeds sintéticos | `access_role` de sistema `admin` + atribuição por membership (bootstrap D9) | Preparar o modelo; seed/atribuição na implementação da F4 |
| Catálogo TS `Capability` + regras por `actor.funcao` no frontend | `src/authorization` + serviços de visibilidade | Catálogo canônico no banco + mapeamento de vocabulário; policy central passa a consumir o servidor quando o domínio migrar (F5) | Nenhuma alteração de código; documento registra o mapeamento futuro (D15) |
| RLS sem policies nas tabelas de domínio | F3 (todas) | Policies restritivas por capability+escopo em etapas autorizadas | Manter deny-by-default |

Princípio: **nada é removido antes de existir autorização equivalente e
segura**; a F4-01 apenas estabelece o modelo no qual essas substituições vão
acontecer.

## 11. Riscos e invariantes

Invariantes de segurança **reforçadas na revisão arquitetural** (a
implementação futura deve garantir):

1. **Cargo, senioridade, position e occupation nunca concedem capability**:
   nenhuma FK, trigger, policy ou função pode derivar permissão da estrutura
   organizacional — os catálogos de estrutura e o modelo de autorização não
   possuem nenhum vínculo.
2. **ADMIN é por membership/organização e não exige collaborator**: é um
   access_role de acesso atribuído a uma membership ativa; existe sem linha em
   `collaborators`/`occupations`.
3. **ADMIN não é SUPER_ADMIN e não recebe conteúdo confidencial
   automaticamente**: capabilities de conteúdo confidencial (separáveis por
   domínio, D18) nunca entram no bundle `admin` por padrão.
4. **Usuário sem membership ativa não possui autorização organizacional**:
   toda capability efetiva parte de membership `active`; perfil `disabled`
   também barra (F2-07).
5. **Cross-tenant é impossível por construção**: FKs compostas/checks impedem
   atribuir role/capability da Organização A a membership da B — nunca apenas
   por convenção de aplicação.
6. **Nenhuma allowlist provisória é removida antes de existir substituto
   seguro** (allowlist `INVITE_ADMIN_USER_IDS`, `verify_jwt=false` local e
   demais mecanismos da seção 10 permanecem até a migração equivalente
   validada).
7. **RLS permanece deny-by-default nesta etapa**: tabelas novas do modelo sem
   policies e sem grants; nenhuma leitura/escrita ampla antes da etapa da F4
   que a autorizar (F4-08 e posteriores).
8. **Scope continua fora da F4-01**: SELF, DIRECT_REPORTS, DESCENDANTS,
   ORGANIZATIONAL_UNIT, ORGANIZATION, ASSIGNED e o escopo temporário de
   substituição pertencem à **F4-02**; a F4-01 apenas não bloqueia essa
   evolução (D12).

Invariantes complementares (mantidas do desenho original):

- **Capability é a única unidade de permissão**; concessão direta fora de role
  não existe na F4-01 (D3).
- **Role agrupa capabilities** sem se confundir com cargo (catálogos
  separados, sem cruzamento).
- **Sem bypass**: funções futuras `SECURITY INVOKER`; nenhum `SECURITY
  DEFINER` desnecessário; `service_role` nunca no cliente.
- **Sem exclusão física** de catálogos/atribuições (histórico e reconstrução
  preservados).
- **Regras não duplicadas**: enforcement futuro concentrado (policy central /
  resolução única), nunca espalhado por páginas/policies ad hoc.
- **Vocabulário estável**: códigos de capability/role imutáveis após
  publicados (renomear = nova capability/migration + deprecação).
- **Estado de domínio continua soberano**: capability válida não autoriza
  mutação em estado inválido do domínio (ex.: editar avaliação concluída,
  escrever observação fora de ciclo ATIVO) — regra de workflow permanece.

Riscos a vigiar durante a F4:

- confundir access_role com cargo (mitigação: seções 4 e 6 + nomes em D14);
- criar capability excessivamente específica (ex.: por ação de UI) e
  engessar a F4-02 — manter taxonomia enxuta (seção 5);
- antecipar escopo/policy na F4-01 e quebrar o deny-by-default;
- remover allowlists/regras legadas antes do substituto seguro (seção 10);
- "ADMIN vê tudo" acidental em bundles futuros (invariantes 2 e 3 + D18).

## 12. Decisões fechadas (D1–D18)

Registro final da revisão arquitetural: cada decisão indica a alternativa
**fechada** e o impacto correspondente. **D14, D16 e D18 incorporam ajustes
obrigatórios** da revisão.

**Resumo dos fechamentos:** D1 = A · D2 = C · D3 = A · D4 = A · D5 = A ·
D6 = B · D7 = A · D8 = A · D9 = A · D10 = A · D11 = A · D12 = A · D13 = A ·
D14 = **B (ajustada)** · D15 = A · D16 = **A (ajustada)** · D17 = A ·
D18 = **A (ajustada)**.

### D1 — Capacidades: catálogo global ou por organização — **FECHADA (A)**

- **Pergunta:** o catálogo de `capabilities` deve ser um conjunto global
  (códigos idênticos em todas as organizações) ou cada organização pode criar
  capabilities próprias?
- **Alternativas:** (A) catálogo global de capabilities (`organization_id`
  null) — organizações apenas compõem roles; (B) capabilities por organização;
  (C) híbrido.
- **Decisão (fechada): A** — catálogo **global** de capabilities. Capability é
  o vocabulário de permissão do produto; por organização tende a fragmentar o
  significado e duplicar o catálogo.
- **Impacto:** validação e auditoria simplificadas; roles customizadas são o
  único ponto de variação por organização.

### D2 — Access roles: sistema vs customizáveis vs por organização — **FECHADA (C)**

- **Pergunta:** onde os access_roles vivem: roles de sistema globais
  (bootstrap), roles customizadas por organização, ou ambos?
- **Alternativas:** (A) somente roles por organização (sem sistema); (B)
  somente roles de sistema globais; (C) híbrido: roles de sistema globais +
  customizadas por organização.
- **Decisão (fechada): C** — híbrido, com `is_system` e `organization_id null`
  para roles de sistema e `organization_id not null` para customizadas (mesmo
  padrão de catálogo `job_roles` por org, somado ao conjunto de sistema).
- **Impacto:** atende ADMIN/bootstrap sem hardcodar e dá flexibilidade por
  organização sem multiplicar o catálogo base.

### D3 — Concessão direta de capability além de roles — **FECHADA (A)**

- **Pergunta:** além da atribuição via access_role, uma membership pode receber
  capability diretamente?
- **Alternativas:** (A) somente via roles (sem concessão direta); (B) conceder
  diretamente com as mesmas regras de tenant.
- **Decisão (fechada): A** — roles como **única via** de concessão na F4-01,
  mantendo a porta para exceções auditadas na F4-09 se necessário.
- **Impacto:** superfície menor; atribuição mais simples de auditar e de
  revogar; sem dois caminhos de concessão.

### D4 — Múltiplos access_roles por membership — **FECHADA (A)**

- **Pergunta:** uma membership pode ter mais de uma access_role simultânea?
- **Alternativas:** (A) sim, múltiplas (união de capabilities); (B) uma única
  role por membership.
- **Decisão (fechada): A** — múltiplas roles por membership (união de
  capabilities), habilitando composição real (ex.: `admin` + role customizada;
  no futuro, papel de gestão com escopo de substituição F3-06 na F4-02).
- **Impacto:** exige unicidade por par e união na resolução; evita roles
  "soma de tudo" e prepara substituições temporárias.

### D5 — Lifecycle/status de roles e capabilities — **FECHADA (A)**

- **Pergunta:** como evoluem roles/capabilities: exclusão ou estados?
- **Alternativas:** (A) `status` `active`/`disabled` + sem exclusão física
  (padrão das F2/F3); (B) exclusão física.
- **Decisão (fechada): A** — `status` `active`/`disabled`, sem exclusão física,
  consistente com `user_profiles`, memberships e catálogos F3-02.
- **Impacto:** preserva histórico e referências; desativar capability/role
  revoga o efeito sem quebrar FKs.

### D6 — Role deletável vs inativável; mutabilidade das de sistema — **FECHADA (B)**

- **Pergunta:** uma access_role (ou capability) pode ser apagada; roles de
  sistema podem ser editadas?
- **Alternativas:** (A) tudo inativável, inclusive sistema (sistema só muda por
  migration); (B) sistema imutável e customizadas inativáveis; (C) customizadas
  poderiam ser excluídas se sem atribuições.
- **Decisão (fechada): B** — roles/capabilities de **sistema imutáveis e
  inativáveis apenas via migration** (nunca renomeáveis); customizadas
  inativáveis; **sem exclusão física**.
- **Impacto:** referências estáveis para validações futuras e deprecação
  ordenada, sem janela de exclusão física.

### D7 — Validade temporal dos assignments — **FECHADA (A)**

- **Pergunta:** a atribuição membership→role precisa de `valid_from`/`valid_to`
  já na F4-01?
- **Alternativas:** (A) sem vigência na F4-01 (revogação por estado);
  (B) vigência temporal desde já.
- **Decisão (fechada): A** — **sem vigência na F4-01** (revogação por estado),
  com shape que não bloqueie adicionar vigência na F4-02/F4-09 (ver D12).
- **Impacto:** F4-01 enxuta; escopo temporário de substituição (F3-06) e acesso
  excepcional por janela entram nas etapas certas.

### D8 — Unicidade de códigos/nomes — **FECHADA (A)**

- **Pergunta:** quais regras de unicidade para `code`/`name` de capabilities e
  roles?
- **Alternativas:** (A) `code` único global (capabilities) e `name`/`code`
  único por escopo (roles de sistema global; customizadas por organização);
  (B) únicos somente por organização em tudo.
- **Decisão (fechada): A** — capability: `code` único global (D1); role:
  unicidade por `(organization_id, name)` para customizadas (espelho
  `job_roles`) e `name` único global para as de sistema, com `code`/`name`
  normalizados (`btrim`, minúsculas) conforme F1-02/F3-02.
- **Impacto:** endereço estável para capabilities; sem colisões entre roles de
  sistema e customizadas.

### D9 — Bootstrap do ADMIN e do catálogo de sistema — **FECHADA (A)**

- **Pergunta:** como nascem as roles/capabilities de sistema e a primeira
  atribuição ADMIN, sem hardcodar pessoas?
- **Alternativas:** (A) seed/migration determinística do catálogo de sistema +
  RPC/script de bootstrap que atribui ADMIN à membership do primeiro
  administrador (fluxo de convite); (B) catálogo criado manualmente em cada
  ambiente; (C) criação via Edge Function desde o início.
- **Decisão (fechada): A** — catálogo de sistema **versionado na migration**
  (reproduzível, idêntico ao seed sintético local); atribuição inicial feita
  por caminho administrativo (convite) que escolhe a role, **nunca por UUID
  fixo em código**.
- **Impacto:** rebuild reproduzível e ADMIN sem collaborator; sem divergência
  entre ambientes.

### D10 — Ownership tenant de roles customizadas (FKs compostas) — **FECHADA (A)**

- **Pergunta:** como garantir no schema que uma role customizada da
  Organização A nunca seja usada na B?
- **Alternativas:** (A) FKs compostas `(id, organization_id)` com `uq` de
  referência aditiva (padrão F3-03/04/05); (B) apenas checagem em triggers;
  (C) apenas convenção de aplicação.
- **Decisão (fechada): A** — integridade de tenant **declarativa** por FKs
  compostas, como na F3.
- **Impacto:** cross-org impossível por construção, não por disciplina de
  código.

### D11 — Tenant da associação role→capability — **FECHADA (A)**

- **Pergunta:** uma role customizada da Organização A pode agregar capabilities
  "globais" (sim) e capabilities de outra organização (não existe, D1);
  como garantir que a associação nunca cruze tenant?
- **Alternativas:** (A) associar somente capabilities do catálogo global +
  capabilities da mesma organização; garantir por FK/check; (B) permitir
  qualquer combinação.
- **Decisão (fechada): A** — com capabilities **globais** (D1), a associação é
  livre entre roles (sistema/org) e o catálogo global; roles customizadas nunca
  referenciam capability de outra org (inexistente por D1).
- **Impacto:** vocabulário único e tenant fechado por construção.

### D12 — Tabela-âncora da atribuição preparada para os escopos (F4-02) — **FECHADA (A)**

- **Pergunta:** que formato dar à atribuição membership→role para que a F4-02
  adicione escopo (SELF, DIRECT_REPORTS, DESCENDANTS, ORGANIZATIONAL_UNIT,
  ORGANIZATION, ASSIGNED) sem remodelar?
- **Alternativas:** (A) atribuição simples (membership+role) e a F4-02 evolui a
  mesma tabela adicionando escopo; (B) já nascer com coluna de escopo
  reservada; (C) tabelas separadas por tipo.
- **Decisão (fechada): A** — tabela-âncora própria e **enxuta**; a F4-02 adiciona
  o modelo de escopo como **evolução aditiva** (nova migration), sem colunas
  mortas na F4-01.
- **Impacto:** evita antecipar a F4-02 e mantém migrations coesas.

### D13 — Metadados de autor (preparação de auditoria) — **FECHADA (A)**

- **Pergunta:** a F4-01 grava `created_by`/`granted_by` (→ `user_profiles`) nas
  atribuições, ou deixa toda a trilha para as etapas de auditoria?
- **Alternativas:** (A) gravar autor mínimo `created_by` onde trivial
  (convenção já adotada em F3-09 com `author_user_profile_id`); (B) nada agora.
- **Decisão (fechada): A** — gravar autor mínimo `created_by` nas atribuições
  (custo baixo), sem criar trilha completa de auditoria.
- **Impacto:** alinha com F3-09 e permite reconstruir "quem atribuiu" sem
  backfill posterior.

### D14 — Access roles iniciais: conjunto mínimo sem colidir com cargo — **FECHADA (B ajustada)**

- **Pergunta:** como estruturar os access_roles iniciais sem criar bundle que
  possa ser confundido com cargo organizacional?
- **Alternativas:** (A) codes curtos `admin`/`manager`/`collaborator`; (B)
  conjunto mínimo apenas com `admin` (por organização), sem bundle espelhando
  cargo; (C) roles de gestão já nesta fase, com nomes marcados
  (ex.: `people_leader`).
- **Decisão (fechada): B ajustada** — **não criar access_role genérica
  `manager` (nem `collaborator`) nesta fase**, nem qualquer bundle que possa ser
  confundido com Gerente/Coordenador ou outro cargo organizacional. A F4-01
  parte de um **conjunto mínimo**: o access_role de sistema `admin`, atribuído
  por membership/organização, como papel de **acesso** (não posição
  hierárquica). Demais bundles existirão **somente quando houver necessidade
  concreta de autorização** (no contexto dos escopos da F4-02+), com
  nomenclatura que não espelhe cargos. Refletido na seção 6.
- **Impacto:** evita espelhar a hierarquia organizacional e mantém o modelo
  verificável; os bundles de gestão/colaborador entram com a necessidade
  concreta de escopo, sem antecipação.

### D15 — Vocabulário dos códigos de capability (espelho do frontend) — **FECHADA (A)**

- **Pergunta:** os `code` das capabilities devem espelhar a notação
  `domínio.verbo` de `src/authorization/Capability.ts` (ex.: `evaluation.write`)
  ou usar outro padrão (ex.: `evaluation_write` snake_case)?
- **Alternativas:** (A) manter notação com ponto espelhando o TS atual;
  (B) normalizar para snake_case puro no banco (convenção de identificadores
  F1-02) e mapear no futuro.
- **Decisão (fechada): A** — `code` é **dado** (não identificador SQL); manter a
  mesma notação (ponto) do catálogo TS atual facilita o mapeamento 1:N futuro
  do frontend e evita dois vocabulários.
- **Impacto:** mapeamento direto com o catálogo `src/authorization/Capability.ts`
  no corte futuro; sem tabela de tradução.

### D16 — Administração do catálogo/atribuições nesta fase (sem UI) — **FECHADA (A ajustada)**

- **Pergunta:** como gravar o catálogo de sistema e as atribuições na
  implementação da F4-01 (que não tem UI)?
- **Alternativas:** (A) catálogo de sistema versionado por migration + mecanismo
  técnico mínimo server-side para atribuições/bootstrap/testes; (B) tudo via
  SQL/service_role manual; (C) Edge Function de administração já nesta fase.
- **Decisão (fechada): A ajustada** — o catálogo de sistema é criado de forma
  **determinística/versionada por migration**, **sem criar superfície
  administrativa desnecessária ou ampla** nesta etapa. Se um mecanismo técnico
  mínimo for necessário para atribuições/bootstrap e testes, ele deve:
  - permanecer **server-side**;
  - **validar membership e tenant**;
  - **não ampliar RLS** (sem policies novas);
  - **não substituir prematuramente as allowlists existentes** (seção 10);
  - **não criar bypass de autorização** (SECURITY INVOKER; sem `SECURITY
    DEFINER` desnecessário).
  Sem Edge Function nova de administração na F4-01.
- **Impacto:** modelo validável sem UI e sem ampliação de superfície; as
  allowlists provisórias seguem vigentes até substituto seguro (invariante 6).

### D17 — ADMIN por organização vs administração de plataforma — **FECHADA (A)**

- **Pergunta:** `admin` é atribuído por membership (por organização) ou existe
  um papel de administração global de usuários/plataforma (as Edge Functions
  atuais convidam/desativam de forma global via allowlist)?
- **Alternativas:** (A) `admin` por organização (cada org tem seus admins; a
  administração de contas/convites de uma org exige `admin` naquela org);
  (B) papel global de plataforma separado; (C) híbrido com role de sistema
  "platform" mínima.
- **Decisão (fechada): A** — `admin` como access_role **por membership/**
  **organização**, mantendo a discussão de "operação de plataforma" (desativar
  conta de usuário, recuperação) para quando as Edge Functions migrarem — sem
  inventar papel global agora.
- **Impacto:** respeita tenant isolation e o princípio de não-SUPER_ADMIN.

### D18 — Conteúdo confidencial e o ADMIN — **FECHADA (A ajustada)**

- **Pergunta:** como garantir que conteúdo confidencial exija permissão além do
  ADMIN, sem que uma permissão única abra todos os domínios confidenciais?
- **Alternativas:** (A) capability genérica única de leitura confidencial
  (ex.: `confidential.read`) ausente do ADMIN; (B) capabilities confidenciais
  **separáveis por domínio/recurso**, criadas quando houver necessidade
  concreta; (C) marcador `is_confidential` por capability.
- **Decisão (fechada): A ajustada** — mantém-se o princípio de **capabilities
  explícitas** para acesso confidencial, **nunca incluídas automaticamente no
  ADMIN**, mas **sem depender de uma capability genérica única** (como
  `confidential.read`) que pudesse abrir todos os domínios confidenciais.
  Preferir **capabilities de confidencialidade separáveis por domínio/recurso**
  quando a necessidade concreta surgir — por exemplo, acesso excepcional a
  avaliações não implica acesso a todo o conteúdo confidencial do Virtus. Na
  F4-01, modela-se apenas o necessário para tornar essa separação **possível e
  verificável**, sem antecipar a taxonomia das fases posteriores (seções 5 e 13;
  invariante 3).
- **Impacto:** a regra "ADMIN não lê conteúdo confidencial por padrão" fica
  verificável, e o desenho não cria um caminho único que abra todos os domínios
  confidenciais no futuro.

## 13. Proposta de validação futura

Como a implementação da F4-01 (e sua validação integrada posterior) poderá
provar os critérios da Issue #88 e os invariantes da seção 11, no estilo dos
runners sintéticos já usados (`supabase/validacao/`):

- **Capability é independente de cargo:** criar colaborador/job_role sem
  nenhuma capability/role e provar que a resolução de permissões retorna vazio;
  e criar capability sem nenhuma relação com `job_roles`/`occupations`
  (asserts de schema: nenhuma FK entre catálogos de estrutura e autorização).
- **Role agrupa capability:** atribuir role com N capabilities e provar que a
  resolução efetiva = união exata das capabilities da role.
- **Conjunto mínimo de roles (D14):** o catálogo de sistema contém apenas o
  access_role `admin` (por organização); nenhuma role espelha cargo
  organizacional; capability sem role atribuída não concede acesso.
- **ADMIN não depende de collaborator:** perfil com membership e role `admin`
  **sem** linha em `collaborators` resolve as capabilities de administração.
- **`job_role` não concede acesso:** ocupar posição com qualquer cargo não
  altera capabilities efetivas (asserts antes/depois).
- **Cross-organization assignment é impossível:** tentativa de atribuir role da
  Organização A a membership da B falha por constraint/FK (assert negativo).
- **Membership desabilitada não concede acesso:** desabilitar a membership e
  provar que a resolução efetiva fica vazia (e perfil `disabled` idem).
- **ADMIN sem conteúdo confidencial:** a resolução das capabilities de `admin`
  não contém nenhuma capability de conteúdo confidencial (assert de conjunto);
  quando capabilities confidenciais por domínio existirem, verificar também a
  separação por domínio/recurso (D18).
- **Catálogo de sistema reproduzível:** rebuild limpo (`supabase db reset`)
  duas vezes produz catálogo de sistema idêntico (determinismo do seed/
  migration).
- **RLS deny-by-default preservado:** como `authenticated`, nenhuma leitura/
  escrita nas tabelas novas retorna linhas/sucesso antes das policies
  autorizadas das etapas seguintes.
- **Regras de domínio seguem soberanas** (F4-10): estado de ciclo/avaliação
  inválido bloqueia mutação mesmo com capability válida (ex.: reabrir avaliação
  CONCLUÍDA fora de reabertura excepcional autorizada).

Nada disso é implementado nesta entrega; fica registrado como contrato de
validação para as próximas etapas da Fase 4.
