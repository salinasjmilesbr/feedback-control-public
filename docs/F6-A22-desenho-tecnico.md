# F6-A22 — Responsabilidade de gestão por posição (Issue #338)

> **Status:** desenho P0 **FECHADO — pronto para implementação**.
> **Base:** `main` em `7e2efa9181cf259c47cf4e01f1ebd57fc78a7043`.
> **Natureza:** contrato técnico; esta entrega altera somente este documento.
> **Escopo:** responsabilidade temporal de gestão de pessoas atribuída à posição,
> integrada ao Policy Engine e ao resolvedor soberano de capabilities/scopes.

## 1. Objetivo e limites

O cargo descreve o trabalho; a posição representa o lugar organizacional; a
ocupação vigente liga uma pessoa à posição; e a reporting line limita os alvos
alcançáveis. Nenhum desses fatos, isoladamente, concede autorização.

Esta atividade introduz a responsabilidade explícita `PEOPLE_MANAGEMENT` na
posição. O ocupante vigente recebe o bundle definido neste contrato enquanto a
ocupação e a responsabilidade forem vigentes.

Ficam fora deste P0: nova role nominal, capability nova, alteração do catálogo
canônico, alteração de `org.structure.manage`, administração de membership/roles,
conteúdo confidencial de avaliações/metas/observações, redesign de UX e qualquer
decisão por cargo, nome ou matrícula.

## 2. Contratos preservados

- `auth.uid()` continua sendo a raiz da identidade.
- Membership ativa, perfil ativo e tenant são revalidados server-side.
- O Policy Engine continua sendo o enforcement; `can()` é apenas UX.
- Capabilities continuam respondendo **o quê**; scopes respondem **sobre quem**.
- `DIRECT_REPORTS` e `DESCENDANTS` continuam sendo resolvidos por posições,
  ocupações e `position_reporting_lines`, na data do contexto.
- O #327 continua controlando a leitura administrativa pela view
  `estrutura_administrativa` e pela capability `org.structure.manage`.
- RLS permanece barreira; tabelas autorizativas não são expostas ao cliente.
- Histórico e auditoria são append-only; fatos temporais não são reescritos.

## 3. Modelo soberano

### 3.1 Responsabilidade da posição

Criar a tabela tenant-scoped `organizational_position_responsibilities`:

| Campo | Regra |
| --- | --- |
| `id` | UUID soberano |
| `organization_id` | obrigatório; FK composta para o tenant |
| `position_id` | obrigatório; FK composta `(position_id, organization_id)` |
| `responsibility_code` | catálogo fechado; P0 contém somente `PEOPLE_MANAGEMENT` |
| `valid_from` | instante/data civil efetivo, obrigatório |
| `valid_to` | nulo ou posterior a `valid_from`; intervalo `[valid_from, valid_to)` |
| `status` | `active`/`revoked`; revogação não apaga o fato |
| `version` | controle otimista |
| `created_by` | `user_profile` do autor validado |
| timestamps | auditoria técnica |

Deve existir no máximo uma responsabilidade vigente do mesmo código para a
posição em qualquer instante. Responsabilidades encerradas permanecem para
rastreabilidade.

### 3.2 Bundle inicial fechado

`PEOPLE_MANAGEMENT` concede exatamente:

1. `collaborator.read`;
2. `collaborator.create`.

O bundle não concede `org.structure.manage`, `org.catalog.manage`,
`membership.*`, `access_role.manage`, `report.read`, `evaluation.*`, `goal.*`,
`observation.*`, `cycle.*` ou qualquer capability futura.

Assim, o gestor pode consultar e administrar o cadastro de pessoas dentro do
seu alcance estrutural, sem administrar unidades, posições, reporting lines,
roles, memberships ou conteúdo funcional confidencial.

O mapeamento do bundle deve ser uma allowlist server-side versionada na mesma
fronteira do resolvedor. Não haverá configuração livre pelo frontend nem
capability coringa.

## 4. Origem e composição dos grants

O grant efetivo de responsabilidade é derivado pela composição:

```text
auth.uid()
  → user_profile ativo
  → membership ativa no organization_id
  → membership_collaborator_links ativo
  → occupation vigente do collaborator
  → position vigente
  → organizational_position_responsibilities vigente
  → bundle PEOPLE_MANAGEMENT
  → scope estrutural da posição
  → Policy Engine
```

`resolver_capabilities_escopos_efetivas` passa a incluir a origem do grant e a
capability efetiva derivada, sem materializar uma assignment de role na
membership. A origem deve ser identificável como
`position_responsibility:<responsibility_id>` para diagnóstico e auditoria.

Grants de roles e grants de responsabilidade são unidos por capability e
scope. Uma origem não amplia a outra e não remove uma permissão já concedida.
Ambiguidade na resolução de identidade, tenant, ocupação ou vigência resulta
em conjunto vazio e DENY.

## 5. Scopes e hierarquia

Para `PEOPLE_MANAGEMENT`, o scope estrutural é derivado da posição ocupada:

- `DIRECT_REPORTS`: posições diretamente subordinadas pela reporting line;
- `DESCENDANTS`: toda a árvore transitiva abaixo da posição.

O P0 não cria um scope novo. A posição com responsabilidade não passa a
alcançar a própria organização inteira. Posições múltiplas geram a união
deduplicada dos alcances; cross-tenant é impossível por FK e revalidação.

O Policy Engine deve exigir simultaneamente:

```text
capability ∈ bundle PEOPLE_MANAGEMENT
AND target ∈ DIRECT_REPORTS ou DESCENDANTS
AND target/tenant/estado válidos
```

Uma posição sem responsabilidade não recebe essas capabilities, mesmo que
esteja abaixo de outra posição gestora. Hierarquia delimita alcance; nunca
cria a capability.

## 6. Temporalidade e estados estruturais

- **Posição vaga:** a responsabilidade existe como fato da posição, mas não há
  grant efetivo para usuário algum.
- **Nova ocupação:** o novo ocupante herda o bundle a partir do início da
  ocupação, respeitada a vigência da responsabilidade.
- **Ocupação encerrada:** o grant deixa de ser resolvido imediatamente; não há
  revogação manual de role.
- **Troca de ocupante:** o ocupante anterior perde o efeito e o novo ocupante
  recebe-o somente no intervalo vigente de cada fato.
- **Responsabilidade futura/encerrada:** não é efetiva fora do intervalo
  `[valid_from, valid_to)`.
- **Sobreposição incoerente:** a escrita deve ser recusada ou a resolução deve
  falhar fechada; nunca escolher silenciosamente um registro.
- **Histórico:** decisões sobre contexto vivo usam a data atual; nenhum grant
  atual reescreve snapshots históricos de ciclos.

## 7. Administração

Criar, encerrar ou alterar responsabilidades de posição pertence ao domínio de
estrutura e exige `org.structure.manage`, validado:

1. na Edge `colaboradores`/fronteira estrutural;
2. na RPC transacional, com ator derivado de `auth.uid()`;
3. com tenant, posição e vigência revalidados;
4. com `expected_version`, idempotência e trilha append-only.

`org.structure.manage` autoriza administrar a responsabilidade; não é concedida
ao ocupante apenas porque ele recebeu `PEOPLE_MANAGEMENT`.

As mutações devem reutilizar o padrão estrutural do F5-08: sem INSERT direto
do cliente, sem `SECURITY DEFINER` novo sem necessidade, sem bypass de RLS e
sem escrever na tabela de roles para simular o efeito.

## 8. Posição sem gestão e administração de colaboradores

`collaborator.create` pertence ao bundle `PEOPLE_MANAGEMENT`, mas continua
sujeito a:

- target de colaborador validado server-side;
- `DIRECT_REPORTS`/`DESCENDANTS` apropriado;
- tenant e membership válidos;
- estado de domínio permitido;
- auditoria da operação.

O gestor não pode, por essa responsabilidade, criar uma posição, alterar cargo,
unidade, reporting line, role, membership ou capability. Para essas ações, o
gate continua sendo `org.structure.manage` ou o contrato administrativo
específico existente.

## 9. Impacto por camada

### 9.1 Schema e migrations

- migration aditiva para a tabela de responsabilidades;
- constraints compostas de tenant, vigência e status;
- índices para posição, organização e resolução temporal;
- trilha append-only de criação/encerramento/alteração;
- nenhum catálogo de capability novo e nenhuma alteração destrutiva.

### 9.2 RPCs e Edge

- RPC administrativa para abrir/encerrar responsabilidade;
- extensão do contrato da Edge `colaboradores` somente para operações
  estruturais autorizadas;
- extensão do resolvedor `resolver_capabilities_escopos_efetivas` para compor
  grants de posição;
- operações de cadastro continuam revalidando a capability efetiva no momento
  da mutação;
- `collaborator.edit` permanece fora deste P0 e exige auditoria específica antes
  de qualquer inclusão futura.

### 9.3 Policy Engine

- nenhuma segunda engine;
- nenhuma decisão por `funcao`, cargo, nome ou matrícula;
- `TargetRef`, `ResourceContext`, scopes e domain state existentes permanecem;
- diagnóstico identifica a origem do grant;
- ausência, conflito ou indeterminação produz DENY.

### 9.4 RLS

- tabela nova deny-by-default para `authenticated`/`anon`;
- leitura por views/RPCs soberanas já aprovadas;
- FKs compostas e tenant revalidado pelo servidor;
- sem exposição direta das tabelas autorizativas.

### 9.5 Frontend

- consumir somente projeção soberana de capabilities/estrutura;
- “Minha equipe” pode ser exibida com base em capability efetiva, mas isso é UX;
- URL direta e toda mutação continuam protegidas server-side;
- nenhum campo de responsabilidade vindo de localStorage ou estado React pode
  conceder acesso.

## 10. Fases P1–P5

### P1 — Migration/schema, auditoria e RLS

Entregar tabela, constraints, índices, allowlist de `PEOPLE_MANAGEMENT`,
auditoria e RLS deny-by-default. Provar tenant isolation, vigência,
unicidade temporal e ausência de DELETE físico.

### P2 — Resolver, Policy Engine e provas server-side

Integrar responsabilidades temporais ao
`resolver_capabilities_escopos_efetivas`, com origem do grant, ocupação vigente
e composição dos scopes existentes. Provar vaga, troca, encerramento,
ambiguidade e cross-tenant.

### P3 — Configuração administrativa da responsabilidade na posição

Adicionar RPC/Edge para criar, encerrar e consultar responsabilidades, gated por
`org.structure.manage`, com autoria, `expected_version`, idempotência e
auditoria. Provar que `PEOPLE_MANAGEMENT` não administra a própria responsabilidade.

### P4 — Superfície “Minha equipe” e cadastro limitado ao scope

Atualizar a superfície e o cadastro para consumir o resolver efetivo e
revalidar `collaborator.read/create` + scope no servidor. Provar ALLOW em
direto/descendente e DENY sem responsabilidade, fora da árvore, vaga,
ocupação encerrada e cross-tenant. `collaborator.edit` não entra nesta fase.

### P5 — Runtime R3 completo

Validar o cenário Ricardo → Mariana → Felipe → Analista sem gestão, sem derivar
autorização por nome de cargo. A superfície usa a projeção soberana, diferencia
`DIRECT_REPORTS`/`DESCENDANTS`, limita o cadastro ao scope e mantém fail-closed
em ausência de capability. Validar navegação direta, troca de tenant, stale
state e regressão do #327.

## 11. Critérios de aceite do desenho

- O mesmo cargo pode ter posições com e sem `PEOPLE_MANAGEMENT`.
- Uma posição sem responsabilidade não autoriza cadastro de pessoas.
- Posição vaga não produz grant de usuário.
- Troca/encerramento de ocupação altera o efeito sem copiar/revogar role.
- `DIRECT_REPORTS` e `DESCENDANTS` permanecem os únicos alcances estruturais
  desta responsabilidade.
- `org.structure.manage` administra a configuração; não é concedida por ela.
- `auth.uid()`, tenant isolation, Policy Engine, RLS e audit trail permanecem
  soberanos.
- Nenhum frontend, JWT, URL, localStorage ou nome de cargo concede autoridade.

## 12. Decisões fechadas

| ID | Decisão |
| --- | --- |
| D1 | A responsabilidade pertence à **posição**, não ao cargo, colaborador ou usuário. |
| D2 | O catálogo inicial contém somente `PEOPLE_MANAGEMENT`. |
| D3 | O bundle exato é `collaborator.read` e `collaborator.create`; `collaborator.edit` fica fora do P0. |
| D4 | A responsabilidade é uma origem adicional de grant dentro do resolver existente; não cria role nova. |
| D5 | A ocupação vigente é a ponte entre posição e identidade do usuário. |
| D6 | `DIRECT_REPORTS` e `DESCENDANTS` continuam sendo resolvidos pelos dados estruturais existentes. |
| D7 | Hierarquia sem capability não autoriza; capability sem target em scope também não autoriza. |
| D8 | Posição vaga não produz grant efetivo. |
| D9 | Encerramento de ocupação ou responsabilidade revoga o efeito por resolução temporal, sem mutar roles. |
| D10 | Administração de responsabilidades exige `org.structure.manage`. |
| D11 | `org.structure.manage` não é incluída no bundle de gestão de pessoas. |
| D12 | O bundle não inclui capabilities de conteúdo confidencial nem administração de acesso. |
| D13 | A resolução é fail-closed em ausência, conflito, ambiguidade, stale state ou cross-tenant. |
| D14 | A integração preserva #327, F4, F5, RLS, Policy Engine e trilha append-only. |
| D15 | A implementação será entregue em P1–P5, nesta ordem; nenhuma fase posterior antecipa enforcement. |

## 13. Pendências

Nenhuma decisão de produto permanece aberta para o P0. O contrato da
implementação deve seguir exatamente D1–D15. Questões de UX visual ou de
detalhamento operacional de cada formulário pertencem à P5 e não reabrem este
desenho.

## 14. Autoauditoria documental

- [x] Somente documentação foi alterada.
- [x] Nenhuma migration, RPC, Edge, capability, role, RLS ou frontend foi implementado.
- [x] O cargo não participa da autorização.
- [x] O bundle inicial é fechado e explícito.
- [x] Temporalidade, posição vaga, troca de ocupante e fail-closed estão definidos.
- [x] #327 e os contratos F4/F5 foram preservados.
