# F4-02 — Desenho técnico: escopos de autorização (Issue #89)

> **Status:** revisão arquitetural **concluída**; decisões D1–D18 **fechadas**
> na seção 20 (D5, D6, D9, D13 e D14 com ajustes registrados). Nenhuma
> migration, schema, código funcional, teste final ou PR de implementação é
> criado nesta entrega — somente este documento, em branch exclusiva de docs.
> Conteúdo 100% conceitual e sintético (sem dados reais).

## 1. Objetivo e escopo

### 1.1 Interpretação da Issue #89

A Issue #89 pede os **tipos de escopo** necessários para que a **mesma
capability** tenha **alcance diferente** conforme a relação organizacional e a
atribuição explícita, mantendo capability (o quê) separada de scope (sobre
quem/onde). Os escopos iniciais são **SELF, DIRECT_REPORTS, DESCENDANTS,
ORGANIZATIONAL_UNIT, ORGANIZATION e ASSIGNED**, mais a **preparação** para o
escopo temporário derivado de substituição (F3-06), sem duplicar hierarquia.

### 1.2 O que entra na F4-02

- Definição semântica dos seis tipos de scope e de suas fontes de dados
  (resolução estrutural F3, ocupações, reporting lines, colegiado/snapshots);
- modelo de dados para **atribuir capability/role + scope em nível de
  membership/usuário**, evoluindo o `membership_access_role_assignments` da
  F4-01 de forma aditiva (sem colunas mortas);
- cardinalidade/composição, temporalidade, tenant isolation e baseline de RLS;
- análise do vínculo `user_profile → collaborator` (necessário aos scopes
  estruturais), com decisão registrada (D1 = A — tabela própria);
- preparação conceitual para o scope derivado de `temporary_responsibilities`
  (implementação funcional completa na F4-05) e para o ASSIGNED de colegiado/
  responsabilidades avaliativas (F3-08/F3-09).

### 1.3 O que fica para F4-03+ (fora desta etapa)

- **Policy engine** funcional que decide operações combinando capability+scope+
  relação+alvo+data+estado (F4-03) — aqui apenas o desenho da integração;
- **policies finais por tabela** e liberação ampla de leitura/escrita (etapa
  que a autorizar; citada no roadmap como F4-08);
- **acesso excepcional auditado** (F4-06);
- **implementação funcional completa do scope de substituição temporária**
  (F4-05);
- UI de administração, dados reais e migração das allowlists provisórias.

## 2. Estado atual após F4-01

### 2.1 Modelo de autorização (F4-01, Issue #88)

- `public.capabilities` — catálogo **global** da unidade explícita de
  permissão (`code` único `domínio.verbo`, `status` `active`/`disabled`); 21
  capabilities de sistema (administração de acesso/org/config, ciclos,
  avaliações, metas, observações, relatórios); **sem** capability confidencial
  genérica.
- `public.access_roles` — papel de **acesso**: de sistema (`is_system`,
  `organization_id NULL`) ou customizado por organização (`organization_id
  NOT NULL`); `status` sem exclusão física.
- `public.access_role_capabilities` — N:N role→capability (capabilities são
  globais).
- `public.membership_access_role_assignments` — atribuição **membership →
  access_role**: uma linha por par (unique), `organization_id` denormalizado
  garantido igual ao da membership (FK composta), `status` `active`/`revoked`,
  `created_by` (autor); revogação por estado, reativação no lugar.
- Funções server-side (`SECURITY DEFINER`, `EXECUTE` só `service_role`):
  `conceder_acesso_role`, `revogar_acesso_role`,
  `resolver_capabilities_efetivas(user_profile_id, organization_id)` — que
  retorna **somente códigos de capability** (união das roles ativas da
  membership ativa, com perfil ativo), **sem noção de alcance**.
- RLS deny-by-default nas quatro tabelas; nenhuma policy nova; allowlists
  provisórias F2 mantidas.

### 2.2 Estrutura organizacional e resolução (F3)

- `collaborators` + `collaborator_identifiers` + `collaborator_status_periods`
  (F3-01); `job_roles`/`seniority_levels` como catálogos (F3-02);
  `organizational_units`/`organizational_unit_parent_periods`/
  `organizational_positions` (F3-03); `position_reporting_lines` (F3-04, sem
  ciclos, superior único, raiz por ausência); `occupations` (F3-05,
  colaborador↔posição temporal, múltiplas simultâneas por colaborador);
  `temporary_responsibilities` (F3-06, período **fechado**, tipos
  `operational`/`evaluative`/`operational_evaluative`).
- **Resolvers F3-07** (`SECURITY INVOKER`, `STABLE`, data como parâmetro):
  - `organizacao_resolver_responsavel_posicao(position, data)` →
    (position_id, titular, substitute, **responsible** = substituto >
    titular);
  - `organizacao_resolver_gestor_direto(collaborator, data)` → por posição
    ocupada, gestor formal (reporting line + responsável da posição superior);
  - `organizacao_resolver_subordinados_diretos(collaborator, data)`;
  - `organizacao_resolver_descendentes(collaborator, data)` → posições
    transitivas sob as posições ocupadas (com profundidade e responsável);
  - `organizacao_resolver_cadeia(collaborator, data)` → cadeia ascendente;
  - `organizacao_resolver_escopo_posicoes(collaborator, data)` → união das
    posições próprias ocupadas + descendentes (com `unit_id`);
  - `organizacao_resolver_escopo_unidades(collaborator, data)` → unidades
    distintas do escopo de posições.
  Todos resolvem **na data** e já tratam substituto temporário
  (operacional/operacional-avaliativo) como responsável efetivo.

### 2.3 Colegiado e responsabilidade avaliativa (F3-08/F3-09)

- `collegiate_configurations`(+`_members`) — config temporal por avaliado;
  `collegiate_cycle_snapshots`(+`_positions`/+`_members`) — **snapshot
  imutável** por `(organization_id, ano, ciclo, collaborator_id)`, com posições
  ocupadas e superior congelados; `materializar_colegiado_ciclo(org, ano,
  ciclo, reference_date, avaliados[])`.
- F3-09: `cycle_evaluation_responsibilities` (responsabilidade por
  `(snapshot, posição)` congelando o titular) e `evaluation_succession_events`
  (append-only, com autor), mais os resolvers
  `organizacao_resolver_responsavel_avaliativo_posicao` (substituto
  `evaluative` > titular), `organizacao_resolver_avaliador_avaliado` e
  `resolver_responsavel_avaliacao_vigente(org, ano, ciclo, data)`.

### 2.4 Limitações intencionais da F4-01

- `resolver_capabilities_efetivas` retorna **capability sem alcance**: saber
  que alguém pode "ler avaliações" não diz **sobre quem/onde**;
- nenhum vínculo `user_profile → collaborator` (sem "self" estrutural);
- nenhum conceito de scope; nenhum alvo; nenhuma distinção de temporalidade de
  escopo; nenhum consumo de F3-08/F3-09 para autorização;
- RLS deny-by-default: nada é exposto a `authenticated`.

## 3. Conceito de scope

### 3.1 Fórmula

```
membership (usuário na organização)
+ access_role (bundle)
+ capability (o quê)
+ scope (sobre quem/onde a capability vale)
+ contexto/alvo (recurso concreto, data)
= autorização potencial
```

- **capability** responde "o que pode ser feito" (`evaluation.write`,
  `observation.read`, ...);
- **scope** responde "sobre quem/onde" (eu mesmo, meus subordinados diretos,
  meus descendentes, uma unidade, a organização inteira, um alvo explicitamente
  atribuído);
- **contexto/alvo** é o objeto concreto avaliado na hora da decisão (qual
  avaliação, qual colaborador, qual ciclo/data);
- a **data** é parte do contexto: a estrutura é temporal (F3) e deve ser
  resolvida na data relevante.

### 3.2 Scope não substitui capability

- Possuir `scope` sem a capability correspondente **não autoriza nada**
  (ex.: ORGANIZATION + nenhuma capability de leitura de avaliação ⇒ nada de
  avaliações);
- Possuir a capability sem alcance efetivo sobre o alvo também não autoriza
  (ex.: `evaluation.read` + SELF ⇒ somente as próprias avaliações);
- A autorização de uma operação = capability **e** o alvo pertence ao conjunto
  resolvido pelos scopes da atribuição **e** as regras de domínio permitem
  (estado do ciclo, imutabilidade etc. — soberanas, F4-10).

## 4. Tipos de scope

| Scope | Significado | Origem dos dados | Alvo esperado | Regra temporal | Sem collaborator/occupation | Multi-position | Casos negativos |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `SELF` | Somente o próprio colaborador vinculado | Vínculo membership→collaborator (seção 5) | O collaborator do ator (todas as posições ocupadas) | Vínculo e occupations na data de contexto | Sem vínculo/occupation ⇒ conjunto vazio (fail-closed) | SELF cobre o collaborator inteiro, com suas N posições | Tentar agir sobre terceiro |
| `DIRECT_REPORTS` | Subordinados diretos (reporting line imediata) | occupations + position_reporting_lines + resolvers F3-07 | Colaboradores responsáveis das posições subordinadas diretas | Resolvido na data de contexto (reporting/occupation vigentes) | Ator sem position ⇒ vazio | União por cada position ocupada | Coordenador par não entra (não é subordinado) |
| `DESCENDANTS` | Toda a árvore abaixo de cada position autorizadora | `organizacao_resolver_descendentes`/`_escopo_posicoes` | Posições e colaboradores descendentes transitivos | Resolvido na data; ciclo bloqueado pela F3-04 | Ator sem position ⇒ vazio | União das árvores de cada position ocupada | Posição de outra árvore; gestor não-descendente de mim |
| `ORGANIZATIONAL_UNIT` | **Somente a unidade explicitamente atribuída** (sem subunidades na F4-02 — D5) | `organizational_units` + target `unit_id` explícito (FK composta de tenant) | Colaboradores/posições da unidade alvo | Unidade na data de contexto | Unidade sem colaboradores ⇒ vazio | Alvo é a unidade (independente de positions do ator) | Unidade de outra org (cross-tenant) |
| `ORGANIZATION` | Todo o tenant (alcance, não permissão) | `organization_id` da membership | Todos os colaboradores/recursos da organização | N/A (tenant fixo) | Válido mesmo sem collaborator (ex.: ADMIN) | N/A | Só é alcance: capability decide o conteúdo |
| `ASSIGNED` | Alvos explícitos (pontuais ou derivados de F3-08/09) | Atribuição explícita; ou `collegiate_*`/F3-09 | Collaborator, position, unit ou recurso (seção 10) | Por ciclo/quando materializado; ou vigência do alvo | Alvo sem sentido ⇒ sem linha | Alvos múltiplos por scope | Colegiado só sobre o avaliado atribuído |

### 4.1 Comportamento transversal

- **União**: um ator pode combinar scopes; o conjunto autorizado é a **união**
  dos alvos de todos os scopes de todas as suas atribuições ativas (seção 13);
- **Falha fechada**: ator sem membership ativa, sem collaborator quando o
  scope exige, sem attribute vigente ou com alvo inexistente ⇒ conjunto vazio;
- **Data**: todo scope estrutural é resolvido na **data de contexto** — nunca
  com "estrutura de hoje" quando se avalia algo do passado (ciclo), nem
  congelado no passado para o presente (estado vivo usa a data atual).

### 4.2 Contexto organizacional vivo × contexto histórico de ciclo (D9)

Separação **obrigatória** registrada na revisão (D9 = A ajustada):

- **Contexto vivo/operacional** (decisões sobre o presente, sem ciclo
  envolvido): DIRECT_REPORTS e DESCENDANTS usam o **responsável efetivo** da
  posição na data — incluindo o **substituto operacional vigente**
  (`operational`/`operational_evaluative`), coerente com os resolvers F3-07;
- **Contexto histórico de ciclo/avaliação**: os **snapshots e responsabilidades
  congeladas** da F3-08/F3-09 permanecem **soberanos** — uma substituição
  atual **nunca reescreve retrospectivamente** quem era o responsável
  histórico; o acesso avaliativo segue a F3-08/09 materializada.

Essa separação evita que a operação corrente contamine decisões históricas e
vice-versa.

## 5. SELF — vínculo membership → collaborator

### 5.1 Separação atual

`user_profile` (identidade de acesso, 1:1 com `auth.users`) e `collaborator`
(pessoa na estrutura, por organização) são **conceitos distintos** e hoje **não
há vínculo** entre eles: a F2 manteve o usuário sem colaborador (ADMIN sem
collaborator é suportado e desejado), e a F3 criou o colaborador sem usuário.
Isto é **intencional**: nem todo usuário precisa ser colaborador, e nem todo
colaborador tem acesso.

### 5.2 Necessidade para SELF (e scopes estruturais)

Para um scope SELF (e para a "raiz" de DIRECT_REPORTS/DESCENDANTS/UNIT
derivados), a resolução precisa saber **qual colaborador é "o próprio"** do
usuário na organização. Sem esse vínculo não há como responder "minhas
avaliações", "meus subordinados".

### 5.3 Onde deve viver o vínculo (D1 = A — fechada)

**Decisão (D1 = A):** o vínculo membership → collaborator vive em uma **tabela
própria** (ex.: `membership_collaborator_links` ou
`user_collaborator_bindings`) ligando `user_profile` + `organization` (colunas
ancoradas) ao `collaborator` (FK composta `(collaborator_id, organization_id)`),
com `valid_from`/`valid_to` se histórico de vínculo for necessário, e no máximo
**um vínculo ativo por (usuário, organização)**. Rejeitadas as alternativas de
coluna em `user_organization_memberships` (acopla membership a estrutura) e de
derivar "self" de occupation única (inseguro: o colaborador pode ter N
positions e não é derivável do usuário). O vínculo não faz parte da F4-01; ele
entra quando os scopes estruturais forem efetivos (implementação dos scopes),
sem exigir vínculo para ADMIN/usuários sem collaborator.

## 6. DIRECT_REPORTS

- **Significado**: colaboradores cujas **positions** reportam diretamente às
  positions ocupadas pelo ator (gestão de primeiro nível).
- **Origem dos dados** (nunca `job_role`):
  1. occupations vigentes do ator na data ⇒ positions "autorizadoras";
  2. `position_reporting_lines` vigentes com `manager_position_id` = position
     autorizadora;
  3. para cada posição subordinada, no **contexto vivo/operacional**, o
     **responsável efetivo** na data (`organizacao_resolver_responsavel_posicao`
     — titular, ou substituto operacional vigente; D9 = A ajustada, ver
     seção 4.2); no **contexto histórico de ciclo/avaliação**, a F3-08/F3-09
     congelada permanece soberana (nenhuma reescrita retroativa);
- **Alvo**: os colaboradores (responsáveis) das posições subordinadas diretas;
  a posição em si também pode ser alvo para ações estruturais.
- **Regra temporal**: reporting line e occupation vigentes na data de contexto.
- **Pessoa com múltiplas positions**: resolver por **cada** position ocupada
  (o `organizacao_resolver_subordinados_diretos` já itera as occupations) e
  **unir**; um subordinado alcançado por duas positions não duplica.
- **Casos negativos**: posição raiz (sem superior → não há "gestor direto"
  disso para o scope de terceiros), par (coordenador irmão), posição fora da
  árvore do ator, subordinado de outra organização (impossível por FK).

## 7. DESCENDANTS

- **Significado**: toda a árvore abaixo de cada position autorizadora do ator
  (transitivo).
- **Origem**: `organizacao_resolver_descendentes(collaborator, data)` e
  `organizacao_resolver_escopo_posicoes` (F3-07), que já retornam posições +
  responsável + profundidade; **não usar `job_role`**.
- **União em múltiplas positions**: a resolução parte de todas as occupations
  do ator (base do resolver), portanto múltiplas positions produzem uma árvore
  unida com `distinct on (position)`; posições repetidas por caminhos
  diferentes são deduplicadas.
- **Ciclos**: a F3-04 já impede ciclos multi-nível temporais na reporting line
  (triggers com `pg_advisory_xact_lock`) — a recursão é segura.
- **Posições vagas**: a posição vaga entra como alvo estrutural (posição sem
  colaborador responsável); não há "colaborador alvo", mas a posição pode ser
  alvo de gestão (ex.: abrir occupation, movimento); para alvos de conteúdo
  (avaliações de pessoas) a vaga não gera alvo de pessoa.
- **Mudanças históricas/temporais**: a árvore é resolvida **na data de
  contexto**; um colaborador promovido depois da data não altera o escopo
  daquele contexto (o mesmo vale para o uso vivo com a data atual).

## 8. ORGANIZATIONAL_UNIT (D5 = ajustada — fechada)

- **Significado**: escopo restrito a **uma unidade organizacional
  explicitamente atribuída**.
- **Decisão (D5 = A ajustada):** na F4-02, ORGANIZATIONAL_UNIT alcança
  **somente a unidade** atribuída — **não inclui subunidades** automaticamente.
  Motivos registrados:
  - menor privilégio por padrão (não amplia alcance implicitamente);
  - semântica simples e previsível;
  - "unidade + subunidades" poderá ser adicionada futuramente como
    **comportamento explícito** ou como **novo tipo de scope**, se surgir
    necessidade concreta.
- **Target principal**: explícito por `unit_id` (alvo na atribuição do scope),
  protegido por **integridade de tenant** (FK composta `(unit_id,
  organization_id)` → `organizational_units`).
- **Alvo**: colaboradores cujas positions pertencem à unidade alvo (sem
  subunidades) na data de contexto.
- **Comportamento temporal**: a unidade e a composição de positions são
  temporais (F3-03); resolve-se na data de contexto.
- **Casos negativos**: unidade de outra organização (cross-tenant, bloqueado
  por FK), unidade sem colaboradores ⇒ conjunto vazio, subunidade da unidade
  alvo **não** alcançada automaticamente (D5).

## 9. ORGANIZATION

- **Significado**: alcance de **todo o tenant** (a organização da membership).
- **Regra central: ORGANIZATION é alcance, não permissão.**

  Exemplo: `org.structure.manage` + `collaborator.manage` + ORGANIZATION ⇒ o
  ator pode administrar a estrutura/colaboradores da organização inteira.
  Porém, ORGANIZATION **não implica** `evaluation.read`/conteúdo confidencial:
  administração organizacional + ORGANIZATION não autoriza ler avaliações,
  metas ou observações de terceiros — isso exigiria a capability específica
  (e, quando existirem, as capabilities confidenciais separáveis por domínio da
  F4-01/D18).

- **Válido sem collaborator**: ADMIN com ORGANIZATION não precisa de
  collaborator/occupation (coerente com F2-10/F4-01).
- **Scope EXPLÍCITO (D14 = A ajustada)**: o ORGANIZATION do ADMIN — e de
  qualquer atribuição — é uma linha de scope **explícita** criada na
  atribuição/bootstrap; **não existe default implícito** do tipo "role admin
  sem scope = ORGANIZATION" (regra geral: assignment sem scope = fail-closed).
- **Casos negativos**: ORGANIZATION fora do próprio tenant (impossível: a
  âncora é a membership); ORGANIZATION sem capability ⇒ nada; ORGANIZATION +
  capability de conteúdo ⇒ só se a capability existir (nunca automático).

## 10. ASSIGNED

- **Significado**: escopo **explícito por recurso/alvo**, atribuído
  pontualmente, para suportar:
  - **colegiado** (F3-08): membro do colegiado atua somente sobre o avaliado
    atribuído;
  - **responsabilidades avaliativas** (F3-09): avaliador atua sobre o avaliado/
    posição cuja responsabilidade lhe é atribuída;
  - outras atribuições futuras (F4-05+), sempre com alvo tipado.

- **O que é o alvo** (D6 = híbrida ajustada — fechada): candidatos —
  `collaborator`, `position`, `organizational_unit` ou recurso específico
  (avaliação/ciclo). **Decisão:** em F4-02, alvos **tipados** por entidade
  (FK composta de tenant), abrindo tabelas de target **somente quando houver
  consumidor concreto** dos casos da Issue #89 — **sem polimorfismo genérico
  `target_type` + `target_id` sem integridade referencial**.

- **Relação com colegiado/snapshots (não duplicar — D6)**: quando já existe
  **fonte soberana de atribuição no domínio**, NÃO duplicar:
  - **colegiado**: derivar de `collegiate_cycle_snapshot_members` (F3-08);
  - **responsabilidade avaliativa**: derivar das estruturas F3-09
    (`cycle_evaluation_responsibilities`/eventos).
  O **ASSIGNED de colegiado/avaliação é derivado** dessas estruturas na
  resolução (join capability/scope × snapshot), e **não** copiado para uma
  tabela de targets — evita duplicação e mantém a F3-08/09 como fonte
  (imutável por ciclo). Targets **explícitos gravados** ficam para atribuições
  ad hoc **sem fonte própria**, e somente quando houver consumidor concreto.

- **Integridade**: qualquer target persistido deve ser **tipado** e referenciar
  a mesma organização (seção 15); alvo derivado herda a integridade da
  estrutura de origem.

## 11. Substituição temporária (preparação para F4-05)

- **Princípio**: `temporary_responsibilities` **não duplica hierarquia** e não
  altera occupation/reporting line (F3-06). Logo, **não gravar um scope
  permanente** quando ele pode ser **resolvido da responsabilidade temporária**.
- **Representação**: o escopo derivado de substituição é **computado na data**:
  - quando o substituto atua por uma position (`operational`/
    `operational_evaluative`), ele exerce, **durante `[valid_from, valid_to)`**,
    os escopos estruturais baseados naquela position (SELF da position? —
    cuidadoso: SELF continua sendo o próprio collaborator; o que muda é o
    alcance DIR/descendentes/unit da position assumida e as responsabilidades
    operacionais da posição);
  - os resolvers F3-07 já retornam o **responsável efetivo** (substituto >
    titular) na data: a autorização que depende da posição passa naturalmente
    pelo substituto **sem estado novo**;
  - **acesso expira junto com `valid_to`** (resolução por data; sem registro
    persistido, nada a expirar).
- **Tipos operational/evaluative limitam capabilities** (D13 = A ajustada —
  fechada): a F4-02 apenas **prepara a resolução** para que a F4-05 aplique a
  regra:
  - `operational` afeta somente capabilities **operacionalmente elegíveis**;
  - `evaluative` afeta somente capabilities **avaliativas elegíveis**;
  - `operational_evaluative` combina ambas.
  O **mapa exato capability/domínio** (e a validação de que o substituto também
  possui as capabilities necessárias) pertence à **F4-05** — **não** se define
  agora uma lista ampla e definitiva de capabilities "operacionais".
- **Caso negativo**: sem `temporary_responsibilities` vigente o substituto não
  herda nada; após `valid_to` o titular reassume (resolvers já reverteram).
- **Histórico × vivo (D9)**: no contexto de ciclo/avaliação, uma substituição
  vigente **não** altera snapshots/responsabilidades congelados da F3-08/09
  (seção 4.2) — o efeito de substituição é apenas no contexto
  vivo/operacional.

## 12. Modelo de dados proposto

Evolução **aditiva** de `membership_access_role_assignments` (F4-01/D12).
Alternativas analisadas:

| Alternativa | Descrição | Vantagens | Riscos |
| --- | --- | --- | --- |
| (A) scope em coluna única na assignment | adicionar `scope_type` na própria tabela de atribuição | simples | não suporta N scopes nem alvos; quebra o unique (membership, role); coluna fixa pouco extensível |
| (B) tabela de scopes ligada à assignment | nova tabela filha (1:N) referenciando `membership_access_role_assignments` | preserva a âncora (membership, role) e o unique da F4-01; N scopes por atribuição; extensível; revogação por status no pai/filho | mais uma tabela; definir cardinalidade e alvos |
| (C) assignment role+scope (linhas repetidas) | cada linha da atribuição carrega role+scope (par composto) | alvos por linha | muda o unique da F4-01; repetição de role; revogação por linha; histórico mais ruidoso |
| (D) target tables auxiliares | tabelas de targets por tipo (collaborator/position/unit/...) | integridade referencial tipada; tenant por FK composta | mais tabelas; sobrespecifica antes do consumidor |

**Decisão (D2 = B):** (B) como **âncora de scopes**, com target tipado apenas
quando necessário (D6 = híbrida ajustada):

```
membership_access_role_assignments  (F4-01 — inalterada; âncora membership→role)
        │ 1:N
        ▼
access_role_assignment_scopes (nova, F4-02)
   id, assignment_id (FK), organization_id (denormalizado, = membership),
   scope_type (SELF | DIRECT_REPORTS | DESCENDANTS |
               ORGANIZATIONAL_UNIT | ORGANIZATION | ASSIGNED),
   status (active | revoked), created_by, created_at, updated_at, version
```

- Para `SELF`/`DIRECT_REPORTS`/`DESCENDANTS`/`ORGANIZATION`: **sem coluna de
  alvo** (a "raiz" vem do vínculo membership→collaborator / do tenant da
  membership — seção 5); único por `(assignment_id, scope_type)`.
- Para `ORGANIZATIONAL_UNIT` explícito e `ASSIGNED`: targets em tabelas
  tipadas por entidade (ex.: `access_role_assignment_unit_targets`,
  `access_role_assignment_collaborator_targets`, ...) com FK composta
  `(scope_id?/target_id, organization_id)` — ou, se a revisão preferir, um
  modelo minimal de targets com CHECK de tipo e validação por função
  (D6/D12). Evita polimorfismo inseguro sem integridade.
- **Sem colunas mortas**: colunas de target só entram quando o tipo de scope
  as consumir (F4-02 abre apenas os tipos com consumidor concreto declarado na
  seção 4).

### 12.1 Por que não coluna única nem linhas repetidas

Coluna única impede múltiplos scopes/união. Linhas repetidas (C) exigiriam
alterar o unique `(membership_id, access_role_id)` da F4-01 e complicam a
revogação em bloco. A âncora (B) mantém F4-01 intacta e a F4-02 evolui
aditivamente (D12 da F4-01).

## 13. Cardinalidade e composição

- **Uma role pode possuir múltiplos scopes?** Sim — via múltiplas linhas de
  scope na mesma atribuição (role não se repete; scopes se multiplicam).
- **Uma membership pode possuir a mesma role com scopes diferentes?** Sim, e é
  isso que (B) expressa: a mesma role em escopos distintos (ex.: role
  `collaborator` com SELF **e** ASSIGNED ao avaliado X do colegiado).
- **União dos scopes**: o conjunto autorizado de um ator = **união** dos alvos
  de todos os scopes ativos de todas as suas atribuições ativas. Não há
  precedência entre scopes (nenhum scope "vence" outro; todos somam).
- **Deduplicação**: alvos resolvidos por caminhos diferentes são
  deduplicados (por position/collaborator) antes da decisão.
- **Sobreposição**: dois scopes que alcançam o mesmo alvo com a mesma
  capability não se anulam nem escalam (a capability precisa existir uma única
  vez na união das roles).
- **Regra de revogação**: revogar a atribuição (status `revoked` na âncora)
  inativa **todos** os scopes filhos; cada scope pode também ser revogado
  individualmente (status próprio) quando a granularidade for necessária
  (D11). Revogação nunca exclui fisicamente.

## 14. Temporalidade

- **Regra fixa**: a hierarquia/estrutura é sempre resolvida na **data de
  contexto** (F3 é temporal); nenhum scope estrutural usa "estrutura de hoje"
  para decisões sobre outro contexto.
- **Scopes atribuídos precisam de valid_from/valid_to?** **Não na F4-02**
  (D7 = A) — a atribuição já tem ciclo de vida por status (F4-01); vigência
  explícita com janela/motivo pertence ao **acesso excepcional auditado**
  (F4-06). Exceção conceitual: o scope **derivado de substituição** é temporal
  por natureza, mas **não é gravado** — expira com `valid_to` da F3-06
  (seção 11).
- **Permanentes × temporários**: as atribuições persistentes (membership→role)
  e os efeitos temporários (substituição; colegiado por ciclo) devem ser
  **separados**: uns vivem em tabelas de atribuição/scope; os outros são
  resolvidos das estruturas F3 no momento da decisão. Não misturar na mesma
  linha.
- **Ciclos**: scopes ASSIGNED derivados de colegiado/responsabilidade seguem o
  snapshot do ciclo (F3-08/09) — a materialização congela a data; o acesso é
  válido enquanto o snapshot/membro/responsabilidade existir.

## 15. Tenant isolation

Constraints/FKs para impedir:

- **assignment da Org A atingir position/unit/collaborator da Org B**:
  - toda tabela nova de scope carrega `organization_id` NOT NULL garantido
    igual ao da membership (FK composta `(assignment_id, organization_id)` →
    `membership_access_role_assignments(id, organization_id)`, com referência
    aditiva na F4-01, padrão já usado);
  - alvos (UNIT/ASSIGNED) usam **FKs compostas** `(target_id,
    organization_id)` → tabela-alvo (padrão F3/F4-01); nenhum target solto.
- **ASSIGNED cross-tenant**: alvo de outra organização é impossível por FK
  composta + coluna de tenant (mesmo padrão).
- **unit scope cross-tenant**: idem (unit target referencia `organizational_
  units (id, organization_id)`).
- **membership desabilitada produzir escopo**: qualquer resolução exige
  membership `active` (+ perfil ativo) — mesma porta da F4-01
  (`resolver_capabilities_efetivas`); escopos de atribuição `revoked` ou de
  role/capability `disabled` não produzem efeito.
- Onde FK composta não cobrir (alvos tipados por scope/ASSIGNED), usar
  **função/trigger de validação** documentada (precedente F3/F4-01) — D12 = A.

## 16. RLS baseline

- **RLS habilitada** nas tabelas novas (scopes e targets), **deny-by-default**
  (zero policies, zero grants a `authenticated`/`anon`);
- **sem policy ampla** e **sem service_role no frontend** (inalterado);
- **sem bypass**: funções de resolução de escopo `SECURITY INVOKER`
  (consumindo o que a RLS permitir quando houver policies); `SECURITY
  DEFINER` **apenas** no caminho server-side de atribuição/bootstrap,
  restrito a `service_role` (D18 = A); o bootstrap/atribuição permanece no
  padrão F4-01;
- a exposição ao `authenticated` fica para a etapa que autorizar leitura
  (F4-08+), nunca nesta etapa.

## 17. Integração futura com o policy engine (F4-03)

A F4-03 poderá consumir, de forma **única** (sem duplicar regras):

- **capability** — da união das roles ativas da membership (F4-01);
- **scope** — das linhas de scope da atribuição (F4-02);
- **relação organizacional** — via resolvers F3-07 (gestor/subordinados/
  descendentes/escopo de posições e unidades) na data de contexto;
- **alvo** — o recurso concreto (collaborator/position/unit/avaliação/ciclo),
  tipado e do mesmo tenant;
- **data/contexto** — parâmetro obrigatório (hoje ou a data do ciclo/snapshot);
- **estado do domínio** — ciclo ATIVO/ENCERRADO, avaliação CONCLUÍDA etc.
  permanecem soberanos (F4-10).

Forma esperada (proposta, não implementar): uma porta canônica do tipo
`autorizar(user_profile, organization, capability, alvo, data) →
boolean`/`lista de alvos autorizados` que compõe os pontos acima — permitindo
que policies finais por tabela (F4-08) sejam **predicados restritos** sobre
essa porta, e não regras duplicadas.

## 18. Matriz de exemplos (sintéticos)

Cenários a validar na implementação (nomenclatura ilustrativa; dados 100%
sintéticos):

| # | Caso | Atribuição (membership+role+scope) | Resultado esperado |
| --- | --- | --- | --- |
| 1 | Colaborador SELF | `collaborator` + SELF | Lê/escreve somente os próprios recursos (metas próprias, própria avaliação) |
| 2 | Coordenador com DESCENDANTS | role de coordenação + DESCENDANTS | Alcança os analistas sob sua árvore; **não** a coordenação par |
| 3 | Gerente com DESCENDANTS | role de gestão + DESCENDANTS | Alcança toda a árvore abaixo de suas positions |
| 4 | Gerente sênior/Diretor pela árvore | mesmas capabilities/roles + DESCENDANTS | Alcança mais pessoas **somente por ocupar posição mais alta na reporting line** — sem regra por cargo |
| 5 | Coordenador com ASSIGNED fora da própria estrutura | role + ASSIGNED (target colaborador Y de outra coordenação) | Acesso somente a Y (ex.: movimento excepcional pontual), sem ganhar a árvore de Y |
| 6 | Colegiado com ASSIGNED só sobre o avaliado atribuído | role de colegiado + ASSIGNED (derivado do snapshot F3-08: membro do avaliado X) | Atua somente na avaliação de X, mesmo que tenha capabilities sobre avaliações |
| 7 | ADMIN com ORGANIZATION sem leitura confidencial | `admin` + ORGANIZATION (bundle sem `evaluation.read` etc.) | Administra a organização; não lê conteúdo confidencial de ninguém |
| 8 | Pessoa com múltiplas positions | role + DESCENDANTS | União das árvores das N positions ocupadas (resolver F3-07) |
| 9 | Position vaga | role + DESCENDANTS cobrindo a vaga | Posição vaga é alvo estrutural; sem alvo de pessoa/conteúdo |
| 10 | Usuário sem membership | — | Nenhuma capability/scope resolvido (conjunto vazio) |
| 11 | Membership disabled | atribuições existentes, membership `disabled` | Resolução vazia (porta F4-01) |
| 12 | Tentativa cross-tenant | scope/target da Org A aplicado a recurso da Org B | Bloqueado por FK composta/constraint (nenhum registro) |

## 19. Riscos e invariantes

Invariantes de segurança **reforçadas na revisão arquitetural**:

1. **Capability define a ação; scope define alcance** — nunca o contrário;
   ter scope sem capability não autoriza nada.
2. **job_role/cargo nunca concede scope** — scope nasce de atribuição
   (membership→role→scope); cargo/senioridade não participa da concessão.
3. **Scopes estruturais partem de collaborator/positions, nunca do nome do
   cargo** — a raiz é o collaborator vinculado e as positions ocupadas
   (resolução F3-07); nenhum scope estrutural usa `job_role`.
4. **Membership ativa é obrigatória** — âncora da autorização no tenant;
   perfil desabilitado também barra; membership/atribuição desabilitadas não
   produzem escopo efetivo.
5. **ADMIN sem collaborator usa ORGANIZATION, não scopes estruturais** — sem
   vínculo/positions não há alvos estruturais; ADMIN opera pelo alcance
   **explícito** de ORGANIZATION (D14).
6. **ORGANIZATION não concede nenhuma capability por si só** — é alcance;
   conteúdo (inclusive confidencial) exige a capability específica.
7. **Colegiado nunca cria hierarquia** — ASSIGNED derivado de F3-08/09 é
   escopo sobre o avaliado atribuído, não reporting line.
8. **ASSIGNED derivado não duplica snapshots/responsabilidades existentes** —
   a F3-08/09 materializada é a fonte (D6).
9. **Estrutura viva usa o responsável efetivo na data** — inclusive substituto
   operacional vigente (D9).
10. **Histórico de ciclo usa snapshot/responsabilidade congelada** — a
    F3-08/09 é soberana; nada é reescrito retroativamente (D9).
11. **Substituição nunca reescreve reporting line/occupation** — efeitos
    resolvidos na data e expiram em `valid_to` (F3-06; D13).
12. **Sem scope explícito = fail-closed** — assignment sem linha de scope não
    produz alvo efetivo; nenhum default implícito amplo (D14/D15).
13. **Cross-tenant impossível por construção** — colunas de tenant + FKs
    compostas (scopes e targets), nunca por convenção.
14. **RLS continua deny-by-default** — sem policy ampla, sem service_role no
    frontend, sem bypass (funções INVOKER; DEFINER só no bootstrap restrito —
    D18).

Riscos a vigiar:

- duplicar dados de F3-08/09 ou da hierarquia em tabelas de scope (mitigação:
  derivar onde há estrutura própria — D6/D13);
- polimorfismo de alvo sem integridade (mitigação: targets tipados — D6/D12);
- antecipar temporalidade/policies (mitigação: seções 14/16);
- romper o unique/âncora da F4-01 (mitigação: modelo B da seção 12 — D2);
- vínculo user↔collaborator inconsistente com D1 (mitigação: tabela própria,
  sem heurística — seção 5).

## 20. Decisões fechadas (D1–D18)

Registro final da revisão arquitetural: cada decisão indica a alternativa
**fechada** e o impacto correspondente. **D5, D6, D9, D13 e D14 incorporam
ajustes obrigatórios** da revisão.

**Resumo dos fechamentos:** D1 = A · D2 = B · D3 = A · D4 = A · D5 = **A
ajustada** · D6 = **híbrida ajustada** · D7 = A · D8 = A · D9 = **A ajustada** ·
D10 = A · D11 = A · D12 = A · D13 = **A ajustada** · D14 = **A ajustada** ·
D15 = A · D16 = A · D17 = A · D18 = A.

### D1 — Onde vive o vínculo membership → collaborator (SELF) — **FECHADA (A)**

- **Pergunta:** onde modelar "qual colaborador é o próprio usuário na
  organização" (necessário a SELF e à raiz dos scopes estruturais)?
- **Alternativas:** (A) tabela própria de vínculo (ex.:
  `membership_collaborator_links`), 1 vínculo ativo por (usuário, organização),
  com validade temporal se necessário; (B) coluna `collaborator_id` em
  `user_organization_memberships` (com FK composta para `collaborators`); (C)
  sem vínculo (SELF derivado por heurística/occupation única).
- **Decisão (fechada): A** — vínculo em **tabela própria** ligando
  `user_profile` + `organization` ao `collaborator` (FK composta), 1 vínculo
  ativo por (usuário, organização), mantendo membership e estrutura
  desacopladas e permitindo ADMIN sem vínculo.
- **Impacto:** mais uma tabela, porém limpa e extensível; ADMIN/usuários sem
  collaborator seguem sem vínculo (D17).

### D2 — Shape dos scope assignments — **FECHADA (B)**

- **Pergunta:** como evoluir `membership_access_role_assignments` para carregar
  scopes?
- **Alternativas:** (A) coluna `scope_type` na própria atribuição; (B) tabela
  filha 1:N (linhas de scope por atribuição); (C) linhas repetidas de
  atribuição com role+scope (alterando o unique F4-01).
- **Decisão (fechada): B** — **tabela filha de scopes** por atribuição:
  preserva a âncora (membership, role) e o unique da F4-01, admite N scopes
  por atribuição e revogação em bloco no pai (seção 12).
- **Impacto:** evolução aditiva (F4-01/D12), sem colunas mortas; sem mudar o
  unique da F4-01.

### D3 — Scope fixo na role vs por atribuição — **FECHADA (A)**

- **Pergunta:** a role pode declarar um scope padrão no catálogo, ou todo scope
  é definido por atribuição?
- **Alternativas:** (A) somente por atribuição; (B) role declara "scope típico"
  como conveniência/documentação (não efetivo); (C) role declara scope efetivo
  herdado por toda atribuição.
- **Decisão (fechada): A** — **scope é propriedade da atribuição** (a mesma
  role em pessoas/contextos diferentes exige alcances diferentes); (B) só como
  documentação, nunca efetivo.
- **Impacto:** explícito e sem surpresa; nenhuma herança automática de alcance
  por role.

### D4 — Mesma role repetida com scopes diferentes — **FECHADA (A)**

- **Pergunta:** uma membership pode ter a **mesma role** com scopes diferentes
  simultaneamente?
- **Alternativas:** (A) sim, via múltiplas linhas de scope na mesma atribuição;
  (B) não (uma combinação por role); (C) sim, duplicando a linha de atribuição.
- **Decisão (fechada): A** — role **única na âncora** + **N linhas de scope**
  (união de alcances) — ex.: role com SELF **e** ASSIGNED ao avaliado X.
- **Impacto:** expressa composição sem duplicar role; revogação coerente.

### D5 — ORGANIZATIONAL_UNIT: somente a unidade atribuída — **FECHADA (A ajustada)**

- **Pergunta:** o UNIT alcança só a unidade ou também subunidades; o alvo é
  derivado ou explícito?
- **Alternativas:** (i.a) só a unidade; (i.b) unidade + subunidades; (ii.a)
  alvo derivado; (ii.b) alvo explícito (`unit_id`).
- **Decisão (fechada): A ajustada** — na F4-02, ORGANIZATIONAL_UNIT alcança
  **somente a unidade explicitamente atribuída**, **sem subunidades
  automáticas**, por menor privilégio, sem ampliação implícita de alcance e
  com semântica simples; "unidade + subunidades" poderá entrar futuramente
  como **comportamento explícito ou novo scope** se houver necessidade
  concreta. Target principal **explícito por `unit_id`**, protegido por
  integridade de tenant (FK composta). Refletido nas seções 4 e 8.
- **Impacto:** controle administrativo pontual; alcance previsível e
  verificável; subunidades exigiriam nova decisão explícita no futuro.

### D6 — Formato do ASSIGNED e relação com colegiado — **FECHADA (híbrida ajustada)**

- **Pergunta:** como modelar o alvo do ASSIGNED sem polimorfismo inseguro e sem
  duplicar fontes existentes?
- **Alternativas:** (A) targets tipados por tabela (FK composta por entidade);
  (B) polimorfismo controlado; (C) ASSIGNED exclusivamente derivado.
- **Decisão (fechada): híbrida ajustada** —
  1. quando existe **fonte soberana de atribuição no domínio**, NÃO duplicar:
     **colegiado** deriva de `collegiate_cycle_snapshot_members` (F3-08);
     **responsabilidade avaliativa** deriva das estruturas F3-09;
  2. para atribuições ad hoc **sem fonte própria**, usar **targets tipados**,
     criando tabelas de target **somente quando houver consumidor concreto** —
     sem polimorfismo genérico `target_type` + `target_id` sem integridade
     referencial.
  Na F4-02, implementar **apenas o mínimo exigido pelos casos concretos da
  Issue #89** (seções 4 e 10).
- **Impacto:** sem duplicação de snapshots/responsabilidades; integridade e
  tenant por construção nos alvos persistidos; sem abstração prematura.

### D7 — Temporalidade dos scopes atribuídos — **FECHADA (A)**

- **Pergunta:** linhas de scope precisam de `valid_from`/`valid_to` na F4-02?
- **Alternativas:** (A) sem vigência (revogação por status), como F4-01;
  (B) com vigência desde já.
- **Decisão (fechada): A** — **sem vigência na F4-02** (revogação por status);
  vigência com janela/motivo pertence ao acesso excepcional (F4-06); o efeito
  derivado de substituição é temporal **sem ser gravado** (F3-06).
- **Impacto:** modelo enxuto e aditivo; sem exclusion/sobreposição prematura.

### D8 — Múltiplas positions do colaborador — **FECHADA (A)**

- **Pergunta:** como os scopes estruturais tratam colaborador com N positions?
- **Alternativas:** (A) união sobre todas as positions ocupadas na data
  (padrão F3-07); (B) position "principal" configurada.
- **Decisão (fechada): A** — **união** sobre todas as positions ocupadas na
  data, como os resolvers F3-07 já fazem; sem campo "principal".
- **Impacto:** consistente com a F3, sem dado novo nem hierarquia implícita.

### D9 — Alvo de DIRECT_REPORTS/DESCENDANTS: responsável efetivo × histórico — **FECHADA (A ajustada)**

- **Pergunta:** "sobre quem" vale a capability: titular ou responsável efetivo
  da posição?
- **Alternativas:** (A) responsável efetivo (F3-07); (B) titular estrito.
- **Decisão (fechada): A ajustada** — separação registrada (seção 4.2):
  - **contexto vivo/operacional**: DIRECT_REPORTS e DESCENDANTS usam o
    **responsável efetivo** na data, incluindo o **substituto operacional
    vigente** (F3-07);
  - **contexto histórico de ciclo/avaliação**: snapshots e responsabilidades
    congeladas da **F3-08/F3-09 permanecem soberanos** — uma substituição atual
    **nunca reescreve retrospectivamente** quem era o responsável histórico.
- **Impacto:** gestão flui com substituto ativo e reverte sozinha; histórico
  de ciclo imutável e consistente.

### D10 — União e precedência de scopes — **FECHADA (A)**

- **Pergunta:** como compor scopes de múltiplas atribuições/roles?
- **Alternativas:** (A) união sem precedência + deduplicação de alvos; (B)
  precedência (ex.: escopo mais específico vence).
- **Decisão (fechada): A** — **união deduplicada, sem precedência** entre
  scopes.
- **Impacto:** previsível; precedência só entraria com caso concreto
  documentado (nenhum hoje).

### D11 — Revogação (granularidade) — **FECHADA (A)**

- **Pergunta:** a revogação opera na atribuição inteira ou por scope?
- **Alternativas:** (A) revogar a atribuição inativa todos os scopes filhos e
  cada scope tem status próprio; (B) só em bloco.
- **Decisão (fechada): A** — **status em ambos os níveis**: revogar a
  atribuição inativa os scopes filhos; cada scope pode ser revogado
  individualmente; sem exclusão física.
- **Impacto:** permite remover um escopo pontual (ex.: ASSIGNED) sem perder a
  role; histórico preservado.

### D12 — Integridade cross-tenant dos targets/scopes — **FECHADA (A)**

- **Pergunta:** como garantir tenant nos scopes e targets?
- **Alternativas:** (A) coluna `organization_id` em tudo + FKs compostas para
  membership e alvos (padrão F3/F4-01); (B) triggers/funções como mecanismo
  primário.
- **Decisão (fechada): A** — **FKs compostas** com coluna de tenant (padrão
  F3/F4-01); trigger/função de validação apenas onde a FK composta não cobre
  (precedente F4-01).
- **Impacto:** cross-tenant impossível por construção; sem bypass.

### D13 — Scope derivado de substituição — **FECHADA (A ajustada)**

- **Pergunta:** como tratar o efeito de `temporary_responsibilities` nos
  escopos?
- **Alternativas:** (A) derivado, resolvido por data, nunca persistido como
  scope; (B) persistir linhas de scope com vigência = período da substituição.
- **Decisão (fechada): A ajustada** — scope de substituição **derivado de
  `temporary_responsibilities`, nunca persistido como scope permanente**. A
  F4-02 apenas **prepara a resolução** para que a F4-05 aplique a regra:
  `operational` afeta somente capabilities operacionalmente elegíveis;
  `evaluative` afeta somente avaliativas elegíveis; `operational_evaluative`
  combina ambas. O **mapa exato capability/domínio pertence à F4-05** — não se
  define agora uma lista ampla e definitiva de capabilities "operacionais".
  Acesso expira com `valid_to` (seção 11).
- **Impacto:** sem duplicação e sem estado a expirar; nenhuma lista ampla
  prematura.

### D14 — ORGANIZATION para ADMIN (scope explícito) — **FECHADA (A ajustada)**

- **Pergunta:** qual o tratamento de ORGANIZATION nas atribuições de ADMIN?
- **Alternativas:** (A) ADMIN recebe ORGANIZATION como scope padrão; (B) ADMIN
  sem scope.
- **Decisão (fechada): A ajustada** — ADMIN recebe **ORGANIZATION como scope
  EXPLÍCITO** da sua assignment/bootstrap (o bootstrap/migration pode criar
  explicitamente `admin` + ORGANIZATION). **Não existe default implícito** do
  tipo "role admin sem scope = ORGANIZATION"; a **regra geral continua:
  assignment sem scope = fail-closed** (D15). Isso preserva auditabilidade e
  evita defaults amplos escondidos.
- **Impacto:** auditável e seguro; o bundle `admin` da F4-01 segue sem
  capabilities de conteúdo (invariantes 5/6/12).

### D15 — Assignment sem linhas de scope (transição com F4-01) — **FECHADA (A)**

- **Pergunta:** o que significa uma atribuição F4-01 sem nenhuma linha de scope
  quando a F4-02 entra em vigor?
- **Alternativas:** (A) fail-closed: sem scope não há alvo efetivo; (B) herdar
  ORGANIZATION como default implícito.
- **Decisão (fechada): A** — **fail-closed**, com a F4-02 migrando as
  atribuições existentes para scope **explícito** (ex.: ADMIN→ORGANIZATION) de
  forma determinística e validada.
- **Impacto:** sem defaults amplos; backfill explícito e documentado.

### D16 — Resolução na data de contexto (viva × ciclo) — **FECHADA (A)**

- **Pergunta:** a resolução estrutural usa sempre data explícita; para decisões
  do "agora" usa-se a data atual, e para contexto de ciclo usa-se o snapshot
  F3-08/09?
- **Alternativas:** (A) sempre resolver na data pedida (hoje ⇒ now(); ciclo ⇒
  reference_date do snapshot/do ciclo), preferindo snapshots materializados
  (imutáveis); (B) misturar estruturas vivas com snapshots.
- **Decisão (fechada): A** — **resolução sempre na data pedida**: snapshots
  F3-08/09 para contexto de ciclo; estrutura viva na data para o contexto
  corrente (seção 14).
- **Impacto:** histórico imutável e consistente; sem inconsistência retroativa.

### D17 — Vínculo × ADMIN/usuários sem collaborator — **FECHADA (A)**

- **Pergunta:** usuários sem colaborator (ADMIN de acesso, usuário
  administrativo) usam scopes estruturais?
- **Alternativas:** (A) scopes SELF/DR/DESCENDANTS/UNIT exigem vínculo e
  positions; sem vínculo resolvem vazio; ADMIN usa ORGANIZATION; (B) scopes
  estruturais "virtuais" sem colaborator.
- **Decisão (fechada): A** — scopes estruturais **exigem collaborator
  vinculado**; sem vínculo resolvem vazio; ADMIN/usuários sem collaborator
  usam **ORGANIZATION** (invariante 5).
- **Impacto:** semântica limpa; sem colaborador virtual.

### D18 — Funções/grants: INVOKER × DEFINER — **FECHADA (A)**

- **Pergunta:** como expor as resoluções de escopo e onde usar DEFINER?
- **Alternativas:** (A) resolvers `SECURITY INVOKER` (consumirão o que a RLS
  permitir quando houver policies); atribuição/bootstrap DEFINER restrito a
  `service_role` (padrão F4-01); (B) DEFINER generalizado.
- **Decisão (fechada): A** — resolvers **INVOKER**; **DEFINER somente** no
  caminho server-side de atribuição/bootstrap, `EXECUTE` só `service_role`.
- **Impacto:** sem bypass; alinhado a F3-07/F4-01 e ao deny-by-default.

## 21. Proposta de validação futura

Como a implementação da F4-02 poderá provar os critérios da Issue #89
(estilo `supabase/validacao/`, dados sintéticos, dois `db reset`):

- **Mesma capability com escopos diferentes**: atribuir a mesma role em duas
  memberships com scopes distintos e provar conjuntos de alvos diferentes;
- **coordenação par**: coordenador com DESCENDANTS não alcança a coordenação
  par (assert negativo de alvos);
- **gerente e diretor pela árvore**: alcance crescente apenas por positions na
  reporting line (sem `job_role` envolvido; asserts semânticos de
  profundidade);
- **coordenador com ASSIGNED fora da estrutura**: alcança somente o alvo
  atribuído (não a árvore do alvo);
- **colegiado com ASSIGNED derivado do snapshot**: membro do colegiado de X
  resolve alvo somente em X; deixar de ser membro cessa o alvo (sem estado
  duplicado);
- **múltiplas positions**: união das árvores; position vaga como alvo
  estrutural sem alvo de pessoa;
- **sem membership / membership disabled**: resolução vazia;
- **cross-tenant**: tentativa de scope/target da Org A em B falha por
  constraint (assert negativo);
- **substituição temporária**: durante `[valid_from, valid_to)` o substituto
  resolve o alcance da posição (conforme tipo, no contexto vivo — D9/D13) e
  após `valid_to` não resolve mais — sem linha persistida de scope; no
  histórico de ciclo, a F3-08/09 congelada permanece inalterada;
- **ADMIN + ORGANIZATION (scope explícito)**: a atribuição de `admin` carrega
  uma linha de scope ORGANIZATION **explícita** (D14); resolve administração
  em todo o tenant e **não** resolve leitura de conteúdo confidencial;
  atribuição **sem** linha de scope resolve vazio (fail-closed — D15);
- **ORGANIZATIONAL_UNIT**: alcance somente da unidade atribuída, sem
  subunidades (D5), com target `unit_id` validado por tenant;
- **união/deduplicação**: dois scopes sobrepostos produzem alvos únicos;
- **revogação**: revogar a atribuição inativa os scopes filhos (linhas
  preservadas, `status` coerente);
- **regressão**: F4-01 e F3 intactas (constraints/policies/RLS), rebuild
  reproduzível.

Nada disso é implementado nesta entrega; fica como contrato de validação para
as próximas etapas da Fase 4.
