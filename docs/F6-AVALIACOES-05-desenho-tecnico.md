# F6-AVALIACOES-05 — Provisionamento funcional legítimo de Avaliações

> **Issue:** #404. **Base:** `main` em `a7b6b6c0d7b15d76490da58a4243f165032f0944`.
> **Natureza:** contrato arquitetural para implementação posterior. Nenhum código funcional,
> migration ou dado é alterado por este documento.
> **Estado:** FECHADO — decisões D1–D8 incorporadas após auditoria arquitetural.

> **Emenda normativa posterior — Incremento 0 de Avaliações:**
> `docs/F6-avaliacoes-contrato-soberano-revisao.md` precisa D4/D8 para a
> leitura coletiva dos participantes, autoria das transições e transparência
> SELF. Bundles, capabilities, scopes e demais decisões permanecem vigentes.
> Esta emenda documental não indica implementação no runtime atual.

## 1. Objetivo e limites

Conectar genericamente os atores relacionais de Avaliações às capabilities mutantes já previstas
por F5-06/F5-09, permitindo `evaluation.create` e `evaluation.write` sem autoridade derivada de
nome/cargo, sem grant específico da Acme e sem redefinir F5-06, F5-09 ou o papel read-only de
#306.

Fora de escopo: nova capability, novo scope, novo `role_type`, alteração de migrations históricas,
redefinição de snapshot, redesign de UX, observações DELETE/REVOKE e findings de #293.

## 2. Decisões fechadas

### D1 — capability e relação são dimensões independentes

`evaluation.create` e `evaluation.write` vêm exclusivamente de access roles persistidas. Relação
estrutural nunca gera capability dinamicamente. O Policy Engine decide na ordem identidade → tenant
→ capability → target → scope/relação → estado; ausência de qualquer dimensão é DENY.

### D2 — bundles funcionais genéricos

Serão provisionados, de forma genérica, dois access roles de sistema (roles de acesso, não cargos):

| Bundle | Capabilities | Scopes permitidos |
|---|---|---|
| Gestão avaliativa | `evaluation.create`, `evaluation.write` | `DIRECT_REPORTS`, `DESCENDANTS` |
| Contribuição avaliativa | `evaluation.write` | exclusivamente `ASSIGNED` |

O papel `evaluator` de #306 permanece exatamente `evaluation.read + ASSIGNED`. Quando o colegiado
precisar ler e escrever, o provisionamento pode combinar `evaluator` com o bundle de contribuição;
nenhuma capability é adicionada ao `evaluator`.

### D3 — autorização de CREATE

Antes de existir avaliação ou participante, o alvo é o colaborador avaliado. A autoridade é:

| Relação | Capability | Scope | Resultado |
|---|---|---|---|
| `GESTAO_DIRETA` | `evaluation.create` | `DIRECT_REPORTS` | ALLOW, se as pré-condições forem satisfeitas |
| `GESTAO_CADEIA` | `evaluation.create` | `DESCENDANTS` | ALLOW, se as pré-condições forem satisfeitas |
| `COLEGIADO` | — | — | DENY; não recebe `evaluation.create` |

A relação é resolvida pela fotografia soberana do ciclo, usando a mesma `reference_date` que
`evaluation_snapshot_participantes` usa na materialização. CREATE não exige `evaluation_participant`
prévio. Exige membership/perfil ativos, tenant do alvo, ciclo apto, avaliado elegível, snapshot de
ciclo existente e ausência de avaliação não cancelada duplicada.

COLEGIADO não cria porque seu bundle não contém `evaluation.create`; `ASSIGNED` é atribuição de
contribuição sobre avaliação materializada, não autorização de abertura do recurso.

### D4 — autorização de WRITE

WRITE exige simultaneamente:

`capability + scope/relação + participante materializado vigente + tenant + estado válido`.

| Relação | Capability | Scope | Participante exigido |
|---|---|---|---|
| `GESTAO_DIRETA` | `evaluation.write` | `DIRECT_REPORTS` | ocorrência vigente `GESTAO_DIRETA` |
| `GESTAO_CADEIA` | `evaluation.write` | `DESCENDANTS` | ocorrência vigente `GESTAO_CADEIA` |
| `COLEGIADO` | `evaluation.write` | `ASSIGNED` | ocorrência vigente `COLEGIADO` |

Para uma avaliação já criada, o resolver de relação usa as ocorrências materializadas em
`evaluation_participants`, não a estrutura viva. A RPC continua resolvendo a ocorrência pelo ator
autenticado; o cliente não escolhe `participant_id`.

### D5 — mudança estrutural e snapshot

Mudança estrutural posterior não altera silenciosamente uma avaliação. O snapshot/ocorrência
continua normativo até realinhamento ou sucessão auditada. Realinhamento encerra a ocorrência
anterior, cria a nova ocorrência conforme contrato e registra auditoria; não apaga histórico.

### D6 — provisionamento separado do enforcement

Provisionamento e reconciliação são operações genéricas, persistidas e auditadas, separadas do
request de autorização. Podem atribuir/revogar os bundles conforme relações soberanas e vigência,
mas o request sempre reavalia capability, tenant, target, scope, relação e estado no Policy Engine.

Nenhuma etapa usa nome, cargo, matrícula textual ou regra específica da Acme. Perda da relação
deve produzir scope vazio/DENY imediatamente; a reconciliação mantém a limpeza operacional e a
trilha de concessão/revogação.

### D7 — catálogos e compatibilidade

Não há capability, scope ou `role_type` novo. Permanecem os catálogos fechados existentes:

- capabilities: `evaluation.create`, `evaluation.write`, `evaluation.read`;
- scopes: `DIRECT_REPORTS`, `DESCENDANTS`, `ASSIGNED`;
- roles de participante: `GESTAO_CADEIA`, `GESTAO_DIRETA`, `COLEGIADO`.

Migrations históricas não são editadas. Qualquer alteração de schema/configuração é aditiva.
O guard de #306 continua exigindo que `evaluator` contenha exatamente `evaluation.read`.

### D8 — enforcement único

Edge, Policy Engine, RLS e RPCs preservam suas fronteiras atuais:

- Edge resolve `auth.uid()` e o recurso soberano;
- Policy Engine decide capability, scope, relação, tenant e estado;
- RPC executa privilegiadamente somente após ALLOW e revalida tenant/membership;
- RLS permanece barreira própria de tenant;
- criação, snapshot, mutações e eventos de auditoria permanecem transacionais.

Não será criada autorização paralela na UI, na RPC ou em provider de negócio.

## 3. Impact map e reverse search

| Área | Impacto dirigido |
|---|---|
| Roles/capabilities | adicionar aditivamente os dois bundles de acesso; não alterar catálogo de capabilities nem `evaluator` |
| Scopes | reutilizar somente `DIRECT_REPORTS`, `DESCENDANTS`, `ASSIGNED`; scope continua pertencendo à assignment |
| Policy Engine | manter capability e relação independentes; adicionar apenas resolução de relação temporal/avaliativa necessária |
| Edge `avaliacoes` | carregar a referência do ciclo para CREATE e o participante materializado para WRITE; manter decisão antes da RPC |
| RPCs | preservar assinaturas; manter snapshot, resolução server-side do ator, cálculo e auditoria |
| RLS | nenhuma nova autoridade; verificar own-tenant e cross-tenant |
| Closed lists | preservar capabilities, scopes e `role_type` fechados |
| Migrations/validators | migration aditiva, guards de #306/admin e preflight de catálogo; nenhuma migration histórica editada |
| Testes/gates | testes Policy Engine/Edge/RPC, SQL real descartável, smoke runtime CREATE→snapshot→WRITE, build, lint e diff-check |

Reverse search obrigatório antes da implementação: consumidores de `evaluation.create/write/read`,
resolvers de capabilities/scopes, `resolver_alvos_escopo`, `assignedSupabase`, `evaluation_criar`,
`evaluation_snapshot_participantes`, `evaluation_gravar_notas`, `evaluation_gravar_comentario`,
`evaluation_concluir`, tabelas de participantes/snapshots, guards históricos #306, testes ALLOW/DENY,
RLS e closed lists.

## 4. Provisionamento e reconciliação

1. Provisionar o bundle de gestão para memberships ativas que tenham relação estrutural elegível
   no ciclo, com scope correspondente (`DIRECT_REPORTS` e/ou `DESCENDANTS`).
2. Provisionar o bundle de contribuição para memberships que sejam membros avaliativos atribuídos,
   com `ASSIGNED` exclusivamente.
3. Para leitura do colegiado, preservar/combinar o `evaluator` de #306.
4. Registrar actor, tenant, membership, role, scope, motivo e resultado de cada concessão/revogação.
5. Reconciliar sem alterar snapshots existentes e sem transformar a reconciliação em bypass do
   Policy Engine.

O provisionador deve operar sobre UUIDs e relações soberanas. A validade final de cada request não
é inferida da existência histórica do bundle: o Policy Engine reavalia a relação e o estado atual
da fotografia aplicável.

## 5. Gates e validação dirigida

Gates mínimos:

- catálogo/role guard: bundles corretos, `admin` sem `evaluation.*`, #306 inalterado;
- ALLOW: CREATE de `GESTAO_DIRETA`/`DIRECT_REPORTS` e `GESTAO_CADEIA`/`DESCENDANTS`;
- DENY: colegiado CREATE, capability sem scope, relação fora do alvo, cross-tenant e estado inválido;
- ALLOW: WRITE para as três relações com participante materializado vigente;
- DENY: participante ausente/encerrado, mudança estrutural sem realinhamento, avaliação concluída/
  cancelada e tentativa de escolher participante de terceiro;
- transação: CREATE materializa snapshot e registra `CRIADA`;
- transação: WRITE registra nota/comentário e autoria;
- runtime: smoke real CREATE → participantes → WRITE por gestor e colegiado;
- SQL real em ambiente descartável, testes dirigidos, build, lint e `git diff --check`.

Não repetir certificações F4/F5 válidas sem mudança relevante; reutilizar evidências não invalidadas.

## 6. Riscos residuais

- CREATE e materialização divergirem na data de referência. O mesmo `reference_date` deve ser usado
  nas duas decisões.
- WRITE consultar estrutura viva e permitir ator que não está no snapshot. O resolver de WRITE deve
  usar ocorrência materializada.
- Bundle único misturar gestão e colegiado. As assignments devem permanecer separadas por scope e
  capacidade funcional.
- Role permanecer atribuída após perda estrutural. Isso não pode gerar ALLOW: a relação deve falhar
  fechado; a reconciliação trata a limpeza.
- Múltiplas posições produzirem relação ambígua. Ambiguidade deve resultar em DENY, nunca em escolha
  arbitrária.

Após esta atividade, a #364 retoma somente as provas runtime necessárias de Avaliações. Observações
DELETE/REVOKE continua pendência runtime da própria #364.
