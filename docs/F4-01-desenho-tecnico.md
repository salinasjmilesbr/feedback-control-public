# F4-01 — Desenho técnico: catálogo de capabilities e roles de acesso (Issue #88)

> **Status:** desenho técnico da F4-01 **aguardando revisão**. Decisões D1–D18
> estão **abertas** (recomendação indicada em cada uma). Nenhuma migration,
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
- Decisões abertas (D1–D18) para toda ambiguidade relevante.

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

Evolução futura (não criar agora): marcador de confidencialidade (D18),
metadados de auditoria.

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
  se D3 decidir por concessão direta além de roles; recomendação preliminar:
  não criar nesta fase (manter roles como única via, reduzindo superfície).

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
| `ADMIN` | access_role de **plataforma/acesso** (bootstrap) | Papel de acesso, não posição da hierarquia; **não** confere conteúdo confidencial automaticamente e **não** é SUPER_ADMIN irrestrito |

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
| Avaliações | `evaluation.read`, `evaluation.create`, `evaluation.write`, `evaluation.cancel`, `evaluation.reopen` | Conteúdo de avaliações de terceiros é **confidencial** (D18); quem lê é combinação capability+escopo |
| Metas | `goal.read`, `goal.write` (criar/editar/progredir/finalizar próprias e de terceiros conforme escopo), `goal.approve` | O "próprio" do colaborador virá de escopo SELF + capability, não de capability `.own` |
| Observações | `observation.read`, `observation.write` (criar/editar/excluir em ciclo ATIVO) | Visibilidade de `Comunicado` para o colaborador é regra de conteúdo/escopo futura, não capability |
| Relatórios | `report.read` (gerenciais/equipe e histórico individual) | Histórico próprio = escopo SELF + `report.read` |
| Confidencial | capability dedicada de leitura de conteúdo confidencial (ex.: `confidential.read`) **ou** marcador nas capabilities — D18 | ADMIN **não** recebe por default |
| Auditoria | `audit.view` — **reservada**; trilha avançada e acesso excepcional auditado são etapas posteriores da F4 | Não ampliar agora |

Nota de mapeamento (para o corte futuro do frontend): capabilities legadas com
sufixo de papel/escopo (`cycle.cancel.manager`, `evaluation.edit.board`,
`goal.approve.coordinator`, `goal.create.own`, `evaluation.view.admin`) **não**
são replicadas como estão no banco: a F4 separa a capability (`cycle.cancel`) do
quem/onde (`manager`/`board`/escopo). O mapeamento 1:N do vocabulário antigo
para o novo será feito quando o domínio migrar (F5), sem quebrar a regra de não
duplicar autorização em páginas (a policy central `src/authorization` continua
a única porta no frontend até lá).

## 6. Access roles iniciais

Bundles de acesso propostos apenas como **configuração inicial razoável**
(bootstrap), com a ressalva de que o mapeamento exato capability↔papel dos
fluxos atuais será fechado na implementação/validação (F4-02/F4-10):

| Access role (código candidato) | Natureza | Capabilities típicas (rascunho) | Notas |
| --- | --- | --- | --- |
| `admin` | Sistema/bootstrap | `membership.read`, `membership.manage`, `access_role.manage`, `collaborator.read`, `collaborator.manage`, `org.structure.manage`, `org.catalog.manage`, `settings.manage`, `cycle.read` | **Sem** `evaluation.read`/`goal.read`/`observation.read`/`confidential.read`/`report.read` de conteúdo de terceiros: ADMIN comum não lê conteúdo confidencial por padrão; não é SUPER_ADMIN |
| `manager` (ver D14 sobre nome) | Sistema (atribuível por membro/org) | `evaluation.read`, `evaluation.create`, `evaluation.write`, `evaluation.cancel`, `evaluation.reopen`, `goal.read`, `goal.write`, `goal.approve`, `observation.read`, `observation.write`, `report.read`, `cycle.read` | Alcance real (DIRECT_REPORTS/DESCENDANTS) definido por escopo na F4-02; papel de **acesso**, não cargo "Gerente" |
| `collaborator` | Sistema | `goal.read`, `goal.write` (próprias), `evaluation.read` (própria), `observation.read` (`Comunicado`/própria), `cycle.read` | Fluxos "próprios" confirmados por escopo SELF na F4-02 |
| `auditor` | Futuro (se adequado; não criar agora) | `audit.view` etc. | Auditoria avançada é etapa posterior; deixar reservado, sem catálogo nesta fase |

Classificação proposta (detalhada nas decisões D2/D6/D14):

- **Sistema/bootstrap** (`is_system = true`, org null): `admin`, `collaborator`
  e, se aprovado, `manager` — criados por seed/migration, **não removíveis nem
  renomeáveis** (apenas inativáveis por migration), pois regras futuras e
  validações os referenciam;
- **Configuráveis/customizadas por organização**: organizações podem compor
  bundles próprios (ex.: "admin de RH restrito") a partir das capabilities;
- **Removíveis**: roles customizadas podem ser inativadas (nunca excluídas
  fisicamente — D6); roles de sistema só perdem capabilities por decisão
  explícita em migration;
- **Nunca** usar GERENTE/COORDENADOR/CONSULTOR/ANALISTA/ESTAGIARIO como
  access_roles "porque são cargos" (D14) — eles permanecem catálogo de
  `job_roles`.

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

Perguntas e posicionamento preliminar (decisões D5/D6/D7/D13):

- **Validade temporal dos assignments**: recomendação — **não** introduzir
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
  As linhas de atribuição preservadas (com timestamps e, se D13=A, autor)
  permitem reconstrução; trilha de auditoria formal/append-only e acesso
  excepcional são etapas posteriores da F4 (não inventar auditoria completa
  aqui).
- **Implementar agora ou preparar o modelo?** F4-01 implementa apenas o modelo
  com campos mínimos de evolução (`status`, `is_system`, timestamps/version,
  autor opcional por D13) — sem tabela de auditoria, sem vigência, sem escopo.

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

Invariantes de segurança que a implementação futura deve garantir:

1. **Capability é a única unidade de permissão**; nenhuma regra autoriza
   diretamente por cargo/senioridade/position/occupation/unidade.
2. **`job_roles`/`seniority_levels`/`occupations` não concedem acesso**: não
   pode existir FK, trigger, policy ou função que derive permissão da estrutura
   organizacional.
3. **Role agrupa capabilities** sem se confundir com cargo (catálogos
   separados, sem cruzamento).
4. **ADMIN é papel de acesso** independente de collaborator/occupation, **sem**
   leitura automática de conteúdo confidencial e **sem** SUPER_ADMIN
   irrestrito.
5. **Toda autorização organizacional parte de uma membership ativa** do
   usuário na organização (usuário sem membership ou com membership desabilitada
   = nenhuma capability efetiva); perfil desabilitado também barra (F2-07).
6. **Cross-organization é impossível por construção** (FKs compostas + checks),
   nunca apenas por convenção de aplicação.
7. **RLS deny-by-default preservado** em todas as tabelas novas e existentes;
   nenhuma policy ampla antes da etapa que a autorizar.
8. **Sem bypass**: funções futuras `SECURITY INVOKER`; nenhum caminho
   `SECURITY DEFINER` desnecessário; `service_role` nunca no cliente.
9. **Sem exclusão física** de catálogos/atribuições (histórico e reconstrução
   preservados).
10. **Regras não duplicadas**: enforcement futuro concentrado (policy central /
    resolução única), nunca espalhado por páginas/policies ad hoc.
11. **Vocabulário estável**: códigos de capability/role imutáveis após
    publicados (renomear = nova capability/migration + deprecação).
12. **Estado de domínio continua soberano**: capability válida não autoriza
    mutação em estado inválido do domínio (ex.: editar avaliação concluída,
    escrever observação fora de ciclo ATIVO) — regra de workflow permanece.

Riscos a vigiar durante a F4:

- confundir access_role com cargo (mitigação: seções 4 e 6 + nomes em D14);
- criar capability excessivamente específica (ex.: por ação de UI) e
  engessar a F4-02 — manter taxonomia enxuta (seção 5);
- antecipar escopo/policy na F4-01 e quebrar o deny-by-default;
- remover allowlists/regras legadas antes do substituto seguro (seção 10);
- "ADMIN vê tudo" acidental em bundles futuros (invariante 4 + D18).

## 12. Decisões pendentes (D1–D18)

Cada decisão apresenta pergunta objetiva, alternativas, recomendação e impacto.
Todas estão **abertas** para revisão do desenho.

### D1 — Capacidades: catálogo global ou por organização

- **Pergunta:** o catálogo de `capabilities` deve ser um conjunto global
  (códigos idênticos em todas as organizações) ou cada organização pode criar
  capabilities próprias?
- **Alternativas:** (A) catálogo global de capabilities (`organization_id`
  null) — organizações apenas compõem roles; (B) capabilities por organização;
  (C) híbrido.
- **Recomendação:** (A) catálogo global. Capability é o vocabulário de
  permissão do produto; por organização tende a fragmentar o significado e
  duplicar o catálogo.
- **Impacto:** (A) simplifica validação e auditoria e mantém roles
  customizadas como único ponto de variação por organização; (B)/(C) exigem
  unicidade composta e complicam "a mesma permissão" entre orgs.

### D2 — Access roles: sistema vs customizáveis vs por organização

- **Pergunta:** onde os access_roles vivem: roles de sistema globais
  (bootstrap), roles customizadas por organização, ou ambos?
- **Alternativas:** (A) somente roles por organização (sem sistema); (B)
  somente roles de sistema globais; (C) híbrido: roles de sistema globais +
  customizadas por organização.
- **Recomendação:** (C) híbrido, com `is_system` e `organization_id null` para
  sistema e `organization_id not null` para customizadas (mesmo padrão de
  catálogo `job_roles` por org, somado ao conjunto de sistema).
- **Impacto:** (C) atende ADMIN/bootstrap sem hardcodar e dá flexibilidade por
  organização sem multiplicar o catálogo base; (A) dificulta bootstrap seguro e
  consistente; (B) impede composições locais.

### D3 — Concessão direta de capability além de roles

- **Pergunta:** além da atribuição via access_role, uma membership pode receber
  capability diretamente?
- **Alternativas:** (A) somente via roles (sem concessão direta); (B) conceder
  diretamente com as mesmas regras de tenant.
- **Recomendação:** (A) na F4-01 (roles como única via), mantendo a porta para
  exceções auditadas na F4-09 se necessário.
- **Impacto:** (A) superfície menor, atribuição mais simples de auditar e de
  revogar; (B) flexibilidade pontual, porém dois caminhos de concessão e maior
  risco de acúmulo de permissões.

### D4 — Múltiplos access_roles por membership

- **Pergunta:** uma membership pode ter mais de uma access_role simultânea?
- **Alternativas:** (A) sim, múltiplas (união de capabilities); (B) uma única
  role por membership.
- **Recomendação:** (A) múltiplas — composição real (ex.: `collaborator` +
  role de gestão temporária; substituição F3-06 na F4-02).
- **Impacto:** (A) exige unicidade por par e união na resolução; (B) força
  roles "soma de tudo" e complica substituições temporárias.

### D5 — Lifecycle/status de roles e capabilities

- **Pergunta:** como evoluem roles/capabilities: exclusão ou estados?
- **Alternativas:** (A) `status` `active`/`disabled` + sem exclusão física
  (padrão das F2/F3); (B) exclusão física.
- **Recomendação:** (A) — consistente com `user_profiles`, memberships e
  catálogos F3-02.
- **Impacto:** (A) preserva histórico e referências; desativar capability/role
  revoga efeito sem quebrar FKs; (B) viola convenção e perde rastreabilidade.

### D6 — Role deletável vs inativável; mutabilidade das de sistema

- **Pergunta:** uma access_role (ou capability) pode ser apagada; roles de
  sistema podem ser editadas?
- **Alternativas:** (A) tudo inativável, inclusive sistema (sistema só muda por
  migration); (B) sistema imutável e customizadas inativáveis; (C) customizadas
  poderiam ser excluídas se sem atribuições.
- **Recomendação:** (B) — roles/capabilities de sistema inativáveis apenas via
  migration e nunca renomeáveis; customizadas inativáveis; sem exclusão física.
- **Impacto:** (B) garante referências estáveis para validações futuras e
  permite deprecação ordenada; (C) cria janela de exclusão física com risco de
  perda de histórico.

### D7 — Validade temporal dos assignments

- **Pergunta:** a atribuição membership→role precisa de `valid_from`/`valid_to`
  já na F4-01?
- **Alternativas:** (A) sem vigência na F4-01 (revogação por estado);
  (B) vigência temporal desde já.
- **Recomendação:** (A), mas com shape que não bloqueie adicionar vigência na
  F4-02/F4-09 (ver D12).
- **Impacto:** (A) mantém a F4-01 enxuta; escopo temporário de substituição e
  acesso excepcional por janela entram nas etapas certas; (B) antecipa
  complexidade (exclusion constraints, close+open) sem consumidor ainda.

### D8 — Unicidade de códigos/nomes

- **Pergunta:** quais regras de unicidade para `code`/`name` de capabilities e
  roles?
- **Alternativas:** (A) `code` único global (capabilities) e `name`/`code`
  único por escopo (roles de sistema global; customizadas por organização);
  (B) únicos somente por organização em tudo.
- **Recomendação:** (A) — capability: `code` único global (D1); role:
  unicidade por `(organization_id, name)` para customizadas (espelho
  `job_roles`) e `name` único global para as de sistema, com `code`/`name`
  normalizados (`btrim`, minúsculas) conforme F1-02/F3-02.
- **Impacto:** (A) dá endereço estável para capabilities e evita colisões entre
  roles de sistema e customizadas; (B) dificulta referência global.

### D9 — Bootstrap do ADMIN e do catálogo de sistema

- **Pergunta:** como nascem as roles/capabilities de sistema e a primeira
  atribuição ADMIN, sem hardcodar pessoas?
- **Alternativas:** (A) seed/migration determinística do catálogo de sistema +
  RPC/script de bootstrap que atribui ADMIN à membership do primeiro
  administrador (fluxo de convite); (B) catálogo criado manualmente em cada
  ambiente; (C) criação via Edge Function desde o início.
- **Recomendação:** (A) — catálogo de sistema versionado na migration
  (reproduzível, idêntico ao seed sintético local); atribuição inicial feita
  por caminho administrativo (convite) que escolhe a role, nunca por UUID fixo
  em código.
- **Impacto:** (A) garante rebuild reproduzível e ADMIN sem collaborator; (B)
  não reproduzível e propenso a divergência; (C) antecipa UI/fluxos que ainda
  não existem.

### D10 — Ownership tenant de roles customizadas (FKs compostas)

- **Pergunta:** como garantir no schema que uma role customizada da
  Organização A nunca seja usada na B?
- **Alternativas:** (A) FKs compostas `(id, organization_id)` com `uq` de
  referência aditiva (padrão F3-03/04/05); (B) apenas checagem em triggers;
  (C) apenas convenção de aplicação.
- **Recomendação:** (A) — integridade de tenant declarativa como na F3.
- **Impacto:** (A) impossibilita cross-org por construção; (B)/(C) dependem de
  código e são menos seguras.

### D11 — Tenant da associação role→capability

- **Pergunta:** uma role customizada da Organização A pode agregar capabilities
  "globais" (sim) e capabilities de outra organização (não existe, D1);
  como garantir que a associação nunca cruze tenant?
- **Alternativas:** (A) associar somente capabilities do catálogo global +
  capabilities da mesma organização; garantir por FK/check; (B) permitir
  qualquer combinação.
- **Recomendação:** (A) — com capabilities globais (D1) a associação é
  livre entre roles (sistema/org) e o catálogo global, e roles customizadas
  nunca referenciam capability de outra org (inexistente por D1).
- **Impacto:** (A) mantém o vocabulário único e o tenant fechado; (B) quebraria
  isolamento se capabilities fossem por org.

### D12 — Tabela-âncora da atribuição preparada para os escopos (F4-02)

- **Pergunta:** que formato dar à atribuição membership→role para que a F4-02
  adicione escopo (SELF, DIRECT_REPORTS, DESCENDANTS, ORGANIZATIONAL_UNIT,
  ORGANIZATION, ASSIGNED) sem remodelar?
- **Alternativas:** (A) atribuição simples (membership+role) e a F4-02 evolui a
  mesma tabela adicionando escopo; (B) já nascer com coluna de escopo
  reservada; (C) tabelas separadas por tipo.
- **Recomendação:** (A) — tabela-âncora própria e enxuta; a F4-02 adiciona o
  modelo de escopo como evolução aditiva (nova migration), sem criar colunas
  mortas na F4-01.
- **Impacto:** (A) evita antecipar a F4-02 e mantém migrations coesas; (C)
  fragmenta e dificulta a resolução conjunta.

### D13 — Metadados de autor (preparação de auditoria)

- **Pergunta:** a F4-01 grava `created_by`/`granted_by` (→ `user_profiles`) nas
  atribuições, ou deixa toda a trilha para as etapas de auditoria?
- **Alternativas:** (A) gravar autor mínimo `created_by` onde trivial
  (convenção já adotada em F3-09 com `author_user_profile_id`); (B) nada agora.
- **Recomendação:** (A) — custo baixo, sem criar trilha completa; prepara a
  reconstrução de "quem atribuiu" sem antecipar auditoria formal.
- **Impacto:** (A) alinha com F3-09 e facilita validação futura; (B) exigiria
  backfill posterior para perguntas simples de auditoria.

### D14 — Nomes dos access_roles iniciais (colisão com cargo)

- **Pergunta:** usar `admin`/`manager`/`collaborator` como codes de access_role
  — e como evitar confusão com os cargos organizacionais (Gerente etc.)?
- **Alternativas:** (A) codes curtos `admin`, `manager`, `collaborator` com
  documentação explícita de que são papéis de acesso; (B) nomes marcados
  (ex.: `access_manager`, `people_leader`); (C) sem role `manager` inicial.
- **Recomendação:** (A) com documentação e validação reforçando a separação
  (seções 4/6/11); alternativa (B) se a revisão julgar necessário evitar
  qualquer colisão semântica com o cargo "Gerente".
- **Impacto:** (A) vocabulário curto e reconhecível, porém exige disciplina de
  documentação; (B) mais explícito porém menos idiomático; (C) empurra
  decisões de bundle para a F4-02 sem ganho.

### D15 — Vocabulário dos códigos de capability (espelho do frontend)

- **Pergunta:** os `code` das capabilities devem espelhar a notação
  `domínio.verbo` de `src/authorization/Capability.ts` (ex.: `evaluation.write`)
  ou usar outro padrão (ex.: `evaluation_write` snake_case)?
- **Alternativas:** (A) manter notação com ponto espelhando o TS atual;
  (B) normalizar para snake_case puro no banco (convenção de identificadores
  F1-02) e mapear no futuro.
- **Recomendação:** (A) — `code` é **dado** (não identificador SQL); manter a
  mesma notação facilita o mapeamento 1:N futuro do frontend e evita dois
  vocabulários. (Reavaliar se a revisão preferir padronização estrita.)
- **Impacto:** (A) mapeamento direto com o catálogo TS; (B) mais "puro" quanto
  à convenção de identificadores, porém exige tabela de tradução e rompe a
  leitura comum com o código atual.

### D16 — Administração do catálogo/atribuições nesta fase (sem UI)

- **Pergunta:** como o catálogo de sistema e as atribuições serão gravados na
  implementação da F4-01 (que não tem UI)?
- **Alternativas:** (A) catálogo de sistema via migration; atribuições via
  RPC `SECURITY INVOKER` validada (ou fluxo de convite) executável por
  servidor; (B) tudo via SQL/service_role manual; (C) Edge Function de
  administração já nesta fase.
- **Recomendação:** (A) — migration para o catálogo (reproduzível) e RPC de
  atribuição com checks de tenant/perfil (sem policies novas), mantendo o
  deny-by-default; sem Edge Function nova na F4-01.
- **Impacto:** (A) permite validar o modelo sem UI nem ampliação de superfície;
  (B) não reproduzível e sem validação central; (C) antecipa fronteira de
  serviço sem necessidade.

### D17 — ADMIN por organização vs administração de plataforma

- **Pergunta:** `admin` é atribuído por membership (por organização) ou existe
  um papel de administração global de usuários/plataforma (as Edge Functions
  atuais convidam/desativam de forma global via allowlist)?
- **Alternativas:** (A) `admin` por organização (cada org tem seus admins; a
  administração de contas/convites de uma org exige `admin` naquela org);
  (B) papel global de plataforma separado; (C) híbrido com role de sistema
  "platform" mínima.
- **Recomendação:** (A) para a F4 (admin como access_role por membership),
  mantendo a discussão de "operação de plataforma" (desativar conta de
  usuário, recuperação) para quando as Edge Functions migrarem — sem inventar
  papel global agora.
- **Impacto:** (A) respeita tenant isolation e o princípio de não-SUPER_ADMIN;
  (B)/(C) reintroduzem conceito global que a F4 quer evitar sem necessidade
  demonstrada.

### D18 — Conteúdo confidencial e o ADMIN

- **Pergunta:** como expressar que conteúdo confidencial (avaliações, notas,
  metas/observações de terceiros, relatórios) exige permissão além do ADMIN, e
  como evitar que bundles comuns (inclusive `admin`) a incluam por engano?
- **Alternativas:** (A) capability dedicada de leitura confidencial
   (ex.: `confidential.read`) que `admin` não recebe; (B) marcador
  `is_confidential` por capability com regra de bundle; (C) sem distinção agora.
- **Recomendação:** (A) — capability explícita e ausente do bundle `admin`
  (e da maioria), deixando o conceito visível para a F4-02/F4-10; (B) fica como
  alternativa se a revisão preferir metadado estrutural.
- **Impacto:** (A) torna a regra "ADMIN não lê confidencial por padrão"
  verificável em validação; (C) deixaria a regra implícita e vulnerável a
  bundles futuros.

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
- **ADMIN não depende de collaborator:** perfil com membership e role `admin`
  **sem** linha em `collaborators` resolve as capabilities de administração.
- **`job_role` não concede acesso:** ocupar posição com qualquer cargo não
  altera capabilities efetivas (asserts antes/depois).
- **Cross-organization assignment é impossível:** tentativa de atribuir role da
  Organização A a membership da B falha por constraint/FK (assert negativo).
- **Membership desabilitada não concede acesso:** desabilitar a membership e
  provar que a resolução efetiva fica vazia (e perfil `disabled` idem).
- **ADMIN sem conteúdo confidencial:** resolução das capabilities de `admin`
  não contém leitura confidencial (assert de conjunto).
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
