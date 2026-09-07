# F4-02 — Desenho técnico: escopos de autorização (Issue #89)

> **Status:** desenho técnico da F4-02 **aguardando revisão**. Decisões
> **D1–D18 abertas** (recomendação indicada em cada uma). Nenhuma migration,
> schema, código funcional, teste final ou PR de implementação é criado nesta
> entrega — somente este documento, em branch exclusiva de docs.
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
  estruturais) **sem assumir silenciosamente**;
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
| `ORGANIZATIONAL_UNIT` | Unidade (e, conforme D5, subunidades) | `organizational_units` + parent_periods; ou unit das positions | Colaboradores/posições da unidade alvo | Unidade na data de contexto | Unidade vazia ⇒ vazio | Define-se por unit target (derivado ou explícito) | Unidade de outra org (cross-tenant) |
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

### 5.3 Onde deve viver o vínculo (proposta — decisão D1)

Recomendação preliminar: **tabela própria** (ex.: `membership_collaborator_links`
ou `user_collaborator_bindings`) ligando `user_profile` + `organization`
(colunas ancoradas) ao `collaborator` (FK composta `(collaborator_id,
organization_id)`), com `valid_from`/`valid_to` se histórico de vínculo for
necessário, e no máximo **um vínculo ativo por (usuário, organização)**.
Alternativas: coluna em `user_organization_memberships` (menos histórica e
acopla membership a estrutura) ou derivar "self" de occupation única (inseguro:
colaborador pode ter N positions e não é derivável do usuário). **Não**
assumimos o vínculo como parte da F4-01; ele entra quando os scopes estruturais
forem efetivos (F4-02 ou a etapa que implementar SELF).

## 6. DIRECT_REPORTS

- **Significado**: colaboradores cujas **positions** reportam diretamente às
  positions ocupadas pelo ator (gestão de primeiro nível).
- **Origem dos dados** (nunca `job_role`):
  1. occupations vigentes do ator na data ⇒ positions "autorizadoras";
  2. `position_reporting_lines` vigentes com `manager_position_id` = position
     autorizadora;
  3. para cada posição subordinada, o **responsável efetivo** na data
     (`organizacao_resolver_responsavel_posicao` — titular, ou substituto
     operacional quando ativo; decidir titular vs responsável no D9);
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

## 8. ORGANIZATIONAL_UNIT

- **Significado**: escopo restrito a uma **unidade organizacional**.
- **Questões a decidir (D5)**:
  - alcança **apenas a unidade** ou **unidade + subunidades** (a F3-03 tem
    `organizational_unit_parent_periods`; "unidade + descendentes de unidade" é
    uma recursão própria — **registrar como decisão, não assumir**);
  - é **derivado** (unidade(s) das positions do ator/do escopo estrutural) ou
    **explícito** (target `unit_id` atribuído na atribuição do scope).
- **Alvo**: colaboradores cujas positions pertencem à unidade alvo (e
  subunidades se aprovado) na data.
- **Comportamento temporal**: hierarquia de unidades é temporal
  (`parent_periods`); resolve-se na data de contexto.
- **Caso "UNIT + descendentes"**: se aprovado, requer a recursão sobre
  `organizational_unit_parent_periods` na data — registrar separadamente (D5).

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

- **O que é o alvo** (D6): candidatos — `collaborator`, `position`,
  `organizational_unit` ou recurso específico (avaliação/ciclo). Recomendação:
  em F4-02, suportar alvo **collaborator** (o avaliado) e **position** (para
  responsabilidades por posição/estrutura), evoluindo para mais tipos quando
  houver consumidor concreto — **sem polimorfismo genérico inseguro**.

- **Relação com colegiado/snapshots (não duplicar)**: quem é membro do
  colegiado do avaliado X em um ciclo já está materializado em
  `collegiate_cycle_snapshot_members` (F3-08); quem é avaliador responsável já
  está em `cycle_evaluation_responsibilities`/eventos (F3-09). Recomendação:
  o **ASSIGNED de colegiado/avaliação é derivado** dessas estruturas na
  resolução (join capability/scope × snapshot), e **não** copiado para uma
  tabela de targets — evita duplicação e mantém a F3-08/09 como fonte
  (imutável por ciclo). O modelo de ASSIGNED **explícito** (targets gravados)
  fica para atribuições ad hoc que não têm estrutura própria (D6).
  *(Registrar como decisão D6 — não assumir.)*

- **Integridade**: qualquer target persistido deve ser tipado e referenciar a
  mesma organização (seção 15); alvo derivado herda a integridade da estrutura
  de origem.

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
- **Tipos operational/evaluative limitam capabilities**: o tipo define quais
  domínios o substituto exerce sobre a posição/titular:
  - `operational` ⇒ capabilities de gestão/operação da posição (estrutura,
    ciclo operacional, colaboradores subordinados...);
  - `evaluative` ⇒ capabilities avaliativas sobre o avaliado da posição
    (F3-09 já distingue substituto avaliativo);
  - `operational_evaluative` ⇒ ambos.
  A materialização desse mapeamento (tipo × domínio de capability) e a
  validação de que o substituto também possui as capabilities necessárias é
  implementação da **F4-05** (o desenho aqui só fixa as regras e deixa o mapa
  explícito como decisão D13).
- **Caso negativo**: sem `temporary_responsibilities` vigente o substituto não
  herda nada; após `valid_to` o titular reassume (resolvers já reverteram).

## 12. Modelo de dados proposto

Evolução **aditiva** de `membership_access_role_assignments` (F4-01/D12).
Alternativas analisadas:

| Alternativa | Descrição | Vantagens | Riscos |
| --- | --- | --- | --- |
| (A) scope em coluna única na assignment | adicionar `scope_type` na própria tabela de atribuição | simples | não suporta N scopes nem alvos; quebra o unique (membership, role); coluna fixa pouco extensível |
| (B) tabela de scopes ligada à assignment | nova tabela filha (1:N) referenciando `membership_access_role_assignments` | preserva a âncora (membership, role) e o unique da F4-01; N scopes por atribuição; extensível; revogação por status no pai/filho | mais uma tabela; definir cardinalidade e alvos |
| (C) assignment role+scope (linhas repetidas) | cada linha da atribuição carrega role+scope (par composto) | alvos por linha | muda o unique da F4-01; repetição de role; revogação por linha; histórico mais ruidoso |
| (D) target tables auxiliares | tabelas de targets por tipo (collaborator/position/unit/...) | integridade referencial tipada; tenant por FK composta | mais tabelas; sobrespecifica antes do consumidor |

**Recomendação preliminar (D2/D6):** (B) como **âncora de scopes**, com target
tipado apenas quando necessário:

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
- **Scopes atribuídos precisam de valid_from/valid_to?** Recomendação: **não
  na F4-02** — a atribuição já tem ciclo de vida por status (F4-01); vigência
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
- Onde FK composta não cobrir (alvos polimórficos, se aprovado), usar **função/
  trigger de validação** documentada (precedente F3/F4-01) — decisão D12.

## 16. RLS baseline

- **RLS habilitada** nas tabelas novas (scopes e targets), **deny-by-default**
  (zero policies, zero grants a `authenticated`/`anon`);
- **sem policy ampla** e **sem service_role no frontend** (inalterado);
- **sem bypass**: funções de resolução de escopo `SECURITY INVOKER`
  (consumindo o que a RLS permitir quando houver policies) ou `SECURITY
  DEFINER` **apenas** se estritamente necessário e restritas a `service_role`
  (decisão D18); o bootstrap/atribuição permanece no padrão F4-01;
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

Invariantes de segurança:

1. **Capability define o quê; scope define sobre quem/onde** — nunca o
   contrário; ter scope sem capability não autoriza nada.
2. **Cargo/seniority/position/occupation não concedem scope por si só** —
   scope nasce de atribuição (membership→role→scope), não da estrutura;
   a estrutura só alimenta a **resolução de alvos** de scopes já atribuídos.
3. **A hierarquia vem das positions/occupations/reporting lines (F3)** —
   nenhum scope estrutural usa `job_role`.
4. **Membership ativa continua a âncora** de autorização no tenant; perfil
   desabilitado também barra.
5. **ADMIN + ORGANIZATION não recebe conteúdo confidencial sem capability
   específica** (e as capabilities confidenciais separáveis por domínio só
   existirão quando necessárias — F4-01/D18).
6. **Colegiado não cria hierarquia**: ASSIGNED derivado de F3-08/09 é
   atribuição de escopo, não reporting line.
7. **Substituição temporária não altera reporting line nem occupation**; seus
   efeitos são resolvidos na data e expiram em `valid_to`.
8. **Cross-tenant impossível por construção** (FKs compostas/colunas de
   tenant), nunca por convenção.
9. **RLS deny-by-default** nesta etapa; sem policy ampla; sem service_role no
   frontend; sem bypass (funções INVOKER; DEFINER só bootstrap restrito).
10. **Sem exclusão física** de atribuições/scopes (revogação por estado;
    histórico preservado).
11. **Estado de domínio soberano**: scope válido não autoriza mutação em estado
    inválido (ciclo encerrado, avaliação concluída...).
12. **União sem precedência**: nenhum scope sobrepõe outro; o conjunto é a
    união deduplicada dos alvos.
13. **Sem SUPER_ADMIN**: ORGANIZATION é alcance; capabilities decidem o resto.

Riscos a vigiar:

- duplicar dados de F3-08/09 ou da hierarquia em tabelas de scope (mitigação:
  derivar onde há estrutura própria — D6/D13);
- polimorfismo de alvo sem integridade (mitigação: targets tipados — D6/D12);
- antecipar temporalidade/policies (mitigação: seções 14/16);
- romper o unique/âncora da F4-01 (mitigação: modelo B da seção 12);
- vínculo user↔collaborator "inventado" sem decisão (mitigação: D1 e seção 5).

## 20. Decisões pendentes (D1–D18)

Para cada decisão: pergunta objetiva, alternativas, recomendação e impacto.
Todas **abertas** para revisão do desenho.

### D1 — Onde vive o vínculo membership → collaborator (SELF)

- **Pergunta:** onde modelar "qual colaborador é o próprio usuário na
  organização" (necessário a SELF e à raiz dos scopes estruturais)?
- **Alternativas:** (A) tabela própria de vínculo (ex.:
  `membership_collaborator_links`), 1 vínculo ativo por (usuário, organização),
  com validade temporal se necessário; (B) coluna `collaborator_id` em
  `user_organization_memberships` (com FK composta para `collaborators`); (C)
  sem vínculo (SELF derivado por heurística/occupation única).
- **Recomendação:** (A) — tabela própria mantém membership e estrutura
  desacopladas, admite histórico e permite que ADMIN exista sem vínculo.
- **Impacto:** (A) mais uma tabela, porém limpa e extensível; (B) acopla e
  muda a F2-02; (C) inseguro (multi-position, ambiguidade) — rejeitado.

### D2 — Shape dos scope assignments

- **Pergunta:** como evoluir `membership_access_role_assignments` para carregar
  scopes?
- **Alternativas:** (A) coluna `scope_type` na própria atribuição; (B) tabela
  filha 1:N (linhas de scope por atribuição); (C) linhas repetidas de
  atribuição com role+scope (alterando o unique F4-01).
- **Recomendação:** (B) — âncora (membership, role) preservada; N scopes;
  revogação em bloco no pai; sem colunas mortas.
- **Impacto:** (A) limita a 1 scope e quebra extensibilidade; (C) muda o unique
  e duplica role; (B) aditiva e compatível com F4-01/D12.

### D3 — Scope fixo na role vs por atribuição

- **Pergunta:** a role pode declarar um scope padrão no catálogo, ou todo scope
  é definido por atribuição?
- **Alternativas:** (A) somente por atribuição; (B) role declara "scope típico"
  como conveniência/documentação (não efetivo); (C) role declara scope efetivo
  herdado por toda atribuição.
- **Recomendação:** (A) — scope é propriedade da atribuição (a mesma role em
  pessoas/contextos diferentes exige alcances diferentes); (B) opcional como
  documentação.
- **Impacto:** (A) explícito e sem surpresa; (C) herdaria alcance indevidamente
  para todas as atribuições da role.

### D4 — Mesma role repetida com scopes diferentes

- **Pergunta:** uma membership pode ter a **mesma role** com scopes diferentes
  simultaneamente?
- **Alternativas:** (A) sim, via múltiplas linhas de scope na mesma atribuição;
  (B) não (uma combinação por role); (C) sim, duplicando a linha de atribuição.
- **Recomendação:** (A) — role única na âncora + N scopes (união).
- **Impacto:** (A) expressa "colaborador + ASSIGNED pontual" sem repetir a
  role; (C) duplica e confunde revogação.

### D5 — ORGANIZATIONAL_UNIT: subunidades e origem do alvo

- **Pergunta:** (i) o UNIT alcança só a unidade ou também subunidades? (ii) o
  alvo é derivado (unidades do ator) ou explícito (unit_id atribuído)?
- **Alternativas:** (i.a) só a unidade; (i.b) unidade + subunidades
  (recursão em `organizational_unit_parent_periods`); (ii.a) derivado;
  (ii.b) explícito.
- **Recomendação:** (i) registrar como **decisão**: recomenda-se começar com
  "unidade + subunidades" **somente se houver consumidor**; caso contrário, só a
  unidade e evoluir aditivamente; (ii) **explícito** (target unit_id) como
  modelo primário, com o derivado disponível via F3-07 quando fizer sentido.
- **Impacto:** (i.b) exige nova recursão e define semântica mais ampla;
  (i.a) mais simples e segura; (ii.b) dá controle administrativo pontual;
  (ii.a) automático porém acoplado às positions do ator.

### D6 — Formato do ASSIGNED (alvo) e relação com colegiado

- **Pergunta:** como modelar o alvo do ASSIGNED (collaborator/position/unit/
  recurso) sem polimorfismo inseguro, e quando derivar de F3-08/09?
- **Alternativas:** (A) targets tipados por tabela (FK composta por entidade);
  (B) polimorfismo controlado (tabela genérica + CHECK + função de validação);
  (C) ASSIGNED exclusivamente derivado de F3-08/09 (sem targets próprios).
- **Recomendação:** híbrido: **derivar** o ASSIGNED de colegiado/responsabili-
  dade avaliativa das estruturas F3-08/09 (sem duplicar) e **tipar** os alvos
  explícitos ad hoc (A), abrindo tabelas de target somente para os tipos com
  consumidor concreto.
- **Impacto:** (A) integridade referencial e tenant por construção; (B) flexível
  porém exige validação cuidadosa; (C) não cobre atribuições ad hoc futuras.

### D7 — Temporalidade dos scopes atribuídos

- **Pergunta:** linhas de scope precisam de `valid_from`/`valid_to` na F4-02?
- **Alternativas:** (A) sem vigência (revogação por status), como F4-01;
  (B) com vigência desde já.
- **Recomendação:** (A) — vigência com janela/motivo é acesso excepcional
  (F4-06); o derivado de substituição é temporal **sem ser gravado**.
- **Impacto:** (A) mantém o modelo enxuto e aditivo; (B) antecipa exclusão/
  sobreposição sem consumidor.

### D8 — Múltiplas positions do colaborador (raiz dos scopes estruturais)

- **Pergunta:** como os scopes estruturais tratam colaborador com N positions?
- **Alternativas:** (A) união sobre todas as positions ocupadas na data
  (padrão F3-07); (B) position "principal" configurada.
- **Recomendação:** (A) — os resolvers F3-07 já unem por position; sem campo
  "principal".
- **Impacto:** (A) consistente com a F3 e sem dado novo; (B) inventaria
  hierarquia/ordem que a F3 rejeitou.

### D9 — Alvo de DIRECT_REPORTS/DESCENDANTS: titular ou responsável efetivo

- **Pergunta:** ao resolver "sobre quem" vale a capability, usamos o titular da
  posição ou o responsável efetivo (incluindo substituto operacional ativo)?
- **Alternativas:** (A) responsável efetivo (`responsible_collaborator_id` da
  F3-07), consistente com os resolvers; (B) titular estrito.
- **Recomendação:** (A) — substituto temporário assume a operação da posição
  (F3-06) e a F3-07 já prioriza substituto; manter coerência entre resolução e
  autorização.
- **Impacto:** (A) gestão continua fluindo com substituto ativo e reverte
  sozinha; (B) descontinuaria a gestão durante substituições (decisão de
  domínio se algum caso exigir).

### D10 — União e precedência de scopes

- **Pergunta:** como compor scopes de múltiplas atribuições/roles?
- **Alternativas:** (A) união sem precedência + deduplicação de alvos; (B)
  precedência (ex.: escopo mais específico vence).
- **Recomendação:** (A) — união deduplicada; precedência só com necessidade
  real documentada (nenhuma até aqui).
- **Impacto:** (A) previsível; (B) complexidade sem caso concreto na F4-02.

### D11 — Revogação (granularidade)

- **Pergunta:** a revogação opera na atribuição inteira ou por scope?
- **Alternativas:** (A) revogar a atribuição inativa todos os scopes filhos e
  cada scope tem status próprio para revogação granular; (B) só em bloco.
- **Recomendação:** (A) — status em ambos os níveis (pai herdado ao filho),
  sem exclusão física.
- **Impacto:** (A) permite tirar um escopo pontual (ex.: ASSIGNED) sem perder a
  role; (B) exigiria nova atribuição.

### D12 — Integridade cross-tenant dos targets/scopes

- **Pergunta:** como garantir tenant nos scopes e targets?
- **Alternativas:** (A) coluna `organization_id` em tudo + FKs compostas para
  membership e alvos (padrão F3/F4-01); (B) triggers/funções de validação como
  mecanismo primário.
- **Recomendação:** (A) com (B) apenas onde FK composta não cobre (padrão já
  usado no F4-01 para a role).
- **Impacto:** (A) cross-tenant impossível por construção; (B) defensivo.

### D13 — Scope derivado de substituição (tipos × domínios)

- **Pergunta:** como mapear `responsibility_type` da F3-06 em capacidades/
  domínios do substituto, e onde vive a regra?
- **Alternativas:** (A) mapa explícito tipo×domínio (operational ⇒ domínios
  operacionais; evaluative ⇒ domínios avaliativos; operacional_evaluative ⇒
  ambos) avaliado na resolução por data, sem persistir escopo; (B) persistir
  linhas de escopo com vigência = período da substituição.
- **Recomendação:** (A) — resolvido de F3-06 em tempo de decisão (expira com
  `valid_to`), validando também que o substituto possui a capability.
- **Impacto:** (A) sem duplicação e sem estado a expirar; (B) duplicaria o
  período e arriscaria dessincronia.

### D14 — ORGANIZATION para ADMIN (bootstrap e conteúdo)

- **Pergunta:** qual o tratamento de ORGANIZATION nas atribuições de ADMIN?
- **Alternativas:** (A) ADMIN recebe ORGANIZATION como scope padrão, mas sem
  capabilities de conteúdo (confidencial segue exigindo capability específica);
  (B) ADMIN sem scope (fail-closed até atribuir escopo por operação).
- **Recomendação:** (A) — ORGANIZATION é alcance do tenant; o bundle `admin` da
  F4-01 não contém capabilities de conteúdo, então não há vazamento; evita
  atribuições "vazias" sem sentido.
- **Impacto:** (A) simples e seguro enquanto o bundle não tiver conteúdo;
  (B) administrativamente custoso.

### D15 — Assignment sem linhas de scope (transição com F4-01)

- **Pergunta:** o que significa uma atribuição F4-01 sem nenhuma linha de scope
  quando a F4-02 entra em vigor?
- **Alternativas:** (A) fail-closed: sem scope não há alvo efetivo em recursos
  escopados (bootstrap exige adicionar scope); (B) herdar ORGANIZATION como
  default implícito.
- **Recomendação:** (A) fail-closed, com a F4-02 migrando as atribuições
  existentes para scope explícito (ex.: ADMIN→ORGANIZATION) de forma
  determinística e validada.
- **Impacto:** (A) seguro; exige backfill explícito documentado; (B) default
  amplo e implícito — rejeitado.

### D16 — Resolução na data de contexto (viva × ciclo)

- **Pergunta:** a resolução estrutural usa sempre data explícita; para decisões
  do "agora" usa-se a data atual, e para contexto de ciclo usa-se o snapshot
  F3-08/09 ou a estrutura reconstruída na data do ciclo?
- **Alternativas:** (A) sempre resolver na data pedida (hoje ⇒ now();
  ciclo ⇒ reference_date do snapshot/do ciclo), preferindo os snapshots já
  materializados quando existirem (imutáveis); (B) misturar estruturas vivas
  com snapshots.
- **Recomendação:** (A) — snapshots F3-08/09 são a fonte para o contexto de
  ciclo (congelado); estrutura viva na data para o contexto corrente.
- **Impacto:** (A) histórico imutável e consistente; (B) inconsistência
  retroativa (rejeitado).

### D17 — Vínculo × ADMIN/usuários sem collaborator

- **Pergunta:** usuários sem colaborator (ADMIN de acesso, usuário
  administrativo) usam scopes estruturais?
- **Alternativas:** (A) scopes SELF/DR/DESCENDANTS/UNIT exigem vínculo e
  positions; sem vínculo resolvem vazio; ADMIN usa ORGANIZATION; (B) permitir
  scopes estruturais "virtuais" sem colaborator.
- **Recomendação:** (A) — estrutura exige colaborator; quem não tem usa
  ORGANIZATION (alcance) com capabilities apropriadas.
- **Impacto:** (A) semântica limpa; (B) inventaria colaborador virtual —
  rejeitado.

### D18 — Funções/grants: INVOKER × DEFINER

- **Pergunta:** como expor as resoluções de escopo e onde usar DEFINER?
- **Alternativas:** (A) resolvers `SECURITY INVOKER` (consumirão o que a RLS
  permitir quando houver policies); atribuição/bootstrap DEFINER restrito a
  `service_role` (padrão F4-01); (B) DEFINER generalizado.
- **Recomendação:** (A) — sem bypass; DEFINER apenas para o caminho
  server-side de atribuição/bootstrap, `EXECUTE` só `service_role`.
- **Impacto:** (A) alinha com F3-07/F4-01 e com o deny-by-default; (B)
  superfície privilegiada ampla — rejeitado.

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
  resolve o alcance da posição (conforme tipo) e após `valid_to` não resolve
  mais — sem linha persistida de scope;
- **ADMIN + ORGANIZATION**: resolve administração em todo o tenant e **não**
  resolve leitura de conteúdo confidencial;
- **união/deduplicação**: dois scopes sobrepostos produzem alvos únicos;
- **revogação**: revogar a atribuição inativa os scopes filhos (linhas
  preservadas, `status` coerente);
- **regressão**: F4-01 e F3 intactas (constraints/policies/RLS), rebuild
  reproduzível.

Nada disso é implementado nesta entrega; fica como contrato de validação para
as próximas etapas da Fase 4.
