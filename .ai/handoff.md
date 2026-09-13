# Virtus — Handoff (contexto operacional de retomada)

> Registro **operacional e estável** para retomada entre agentes/sessões.
> **Não copie** dados pessoais, segredos, credenciais, tokens, chaves ou
> informações corporativas sensíveis. Referencie Issues/PRs/documentos em vez de
> transcrever conteúdo. GitHub continua sendo a fonte de verdade do andamento.

## 1. Como retomar uma atividade interrompida

1. Leia `AGENTS.md` e `AGENTS.md` → `.ai/*` (ordem de `.ai/virtus-context.md`).
2. Leia **este arquivo** — seção 3 (registro de estado) — para saber onde a
   última entrega parou.
3. Confirme no GitHub (fonte de verdade) a Issue, o PR e o estado real da branch.
4. Em paralelo ao registro, verifique localmente com:

```bash
git status -sb        # branch atual, ahead/behind de origin
git log --oneline -3  # últimos commits locais
git diff --stat       # alterações não commitadas
```

5. Se um push falhou pela limitação conhecida (`.ai/git-rules.md`), o trabalho
   está **commitado localmente** e aguarda o usuário executar o push; não refaça
   e não tente contornar.

## 2. Instrução permanente de manutenção

A cada entrega (concluída ou interrompida), **atualize a seção 3** com o novo
estado e remova entradas obsoletas. Mantenha apenas contexto operacional:
branch, SHA, PR, atividade e próximos passos. **Nunca** adicione segredos,
credenciais, conteúdo real de pessoas/empresa ou trechos de documentos aqui.

## 3. Registro de estado (última entrega)

> Atualizar ao final de cada atividade.

- **Atividade (rodada atual):** F5-09 — **P7 (Edge Function `ciclos` + reconciliação
  do catálogo D28) IMPLEMENTADA** — **aguardando auditoria independente**. Issue
  **#202**. Contrato: `docs/F5-09-desenho-tecnico.md` (§8 tabela
  operação→capability, §13.1 contrato da Edge e regras 1–9, §13.2 assinaturas das
  RPCs, §13.3 reuso obrigatório, §13.5 cliente, §19 P7) e `docs/F5-09-duvidas.md`
  (**D25** uma Edge por domínio, **D26** admissão, **D28** bundle `admin`).
- **Base:** `main`/`origin/main` = `014a7b4303bdcb2887dc0342810e363e2e141527`
  (F5-09 P6 integrada em `main`).
- **Branch da P7:** `feat/f5-09-p7-cycle-edge` — **sem merge**; push/PR ficam com
  o usuário.
- **Entregue nesta rodada (P7):**
  - `src/infrastructure/supabase/ciclos/contrato.ts` (novo): fonte **única** do
    contrato transportável — as 8 operações, o mapa EXPLÍCITO operação → gate
    (`funcional`/`administrativo`) → capability (sem default e sem alias), e a
    validação de FORMA com **allowlist estrita** de chaves por operação;
  - `supabase/functions/ciclos/core.ts` (novo): núcleo testável da fronteira —
    método → JWT (`auth.getUser`) → forma → **tenant revalidado** contra
    membership ativa → **gate** (Policy Engine com recurso real ou plano
    administrativo D19) → **execução privilegiada**; erro de RPC mapeado por
    prefixo `F5_09_*` para código público, com `INTERNAL` como fallback;
  - `supabase/functions/ciclos/index.ts` (novo): wiring Deno — cliente
    `service_role` (executor), `DepsContextoAutorizacao` com
    `carregarRecurso` de **ciclo** (linha real de `evaluation_cycles` com o
    `status` soberano → `domainState` do P6), resolutores da fronteira e dispatch
    das 8 RPCs com o ator verificado e **sem** `p_payload_hash`;
  - `supabase/functions/ciclos/contrato.ts` (novo): reexport do contrato
    compartilhado (estrutura `index`/`core`/`contrato` como nas demais Edges);
  - `src/infrastructure/supabase/ciclos/edgeCiclos.ts` (novo): adapter de cliente
    (8 métodos) que envia apenas INTENÇÃO e é fail-closed (erro de transporte,
    `error` no corpo, 2xx fora do contrato e código desconhecido NÃO viram
    sucesso);
  - `supabase/migrations/20260921000000_f5_09_p7_catalog_admin_bundle.sql`
    (**D28**): `cycle.manage` entra **aditivamente** no bundle `admin`
    (`+1` exato, idempotente), com preflight/guarda final fail-closed provando
    catálogo intacto, `cycle.read` preservada e as três excepcionais fora de
    qualquer role;
  - `supabase/validacao/11-validar-f5-09-p7.sql` (novo): bundle `admin` = 9
    funcionais com `cycle.manage`, excepcionais fora, catálogo com 31 códigos,
    descrição de `cycle.cancel` (P6), RLS own-tenant + escrita fechada +
    `cycle_events` deny-by-default (P5) e as 8 RPCs `INVOKER` com `EXECUTE` só
    `service_role` (P2–P4);
  - testes: `src/authorization/ciclosEdge.test.ts` (cobertura A–R: happy path das
    8 operações, UUID real como alvo, cross-tenant/IDOR, membership/perfil/
    identidade, capability/scope, campos textuais de autoridade, alvo
    malformado/sintético, `service_role` só após o gate, ausência de matriz de
    lifecycle e idempotência por `operationId`),
    `src/authorization/ciclosContratoRpc.test.ts` (contrato Edge → RPC com nomes e
    argumentos EXATOS + guard de que **toda** função chamada existe no schema,
    D28 estrito e nenhuma capability nova) e
    `src/infrastructure/supabase/ciclos/edgeCiclos.test.ts` (adapter do cliente);
  - adaptações explícitas de contrato antigo (D28): `02-validar-f5-04.sql` e
    `02-validar-f4-01.sql` passam a esperar **9** capabilities no bundle `admin`
    (com `cycle.manage`), mantendo as proibições de controle/deprecado/
    confidencial;
  - `.github/workflows/ci.yml` (validador P7 no job `supabase-local`, após o par
    P5 e antes das regressões F5-06/F5-07), `supabase/migrations/README.md` e este
    arquivo.
- **Arquitetura final da Edge:** request → `OPTIONS`/`POST` (405 fora disso) →
  `Authorization` obrigatório (401) → `auth.getUser` (401) → forma da intenção
  (400, allowlist estrita) → tenant do corpo revalidado contra a identidade
  (403/401) → gate por operação → RPC `ciclo_*` com `service_role` e ator
  verificado → resposta `{ok, operacao, resultado}` com erro público.
  `service_role` **executa**, nunca decide: nenhum caminho alternativo existe e o
  JWT do usuário não é propagado.
- **Correção pós-auditoria Codex (D28, mesma rodada):** as guardas da migration
  `20260921000000` foram restringidas ao **tipo de role** — as três excepcionais
  ficam proibidas apenas em roles **DE SISTEMA** (`is_system = true`) e seguem
  **concedíveis** em roles **CUSTOMIZADAS** (contrato D28/Q-F5-09-3); a migration
  passou a ser **realmente idempotente** (`v_ja_existia`: +1 só na primeira
  execução, 0 na reexecução, com prova de relação única e bundle no tamanho
  esperado). Provas automatizadas: `12-cenario/13-validar-f5-09-p7-d28.sql`
  (A–H, incluindo role customizada aceita, role de sistema recusada pelo
  predicado, primeira execução +1, reexecução sem duplicata e catálogo intacto) e
  a reaplicação da migration (2×) no job `supabase-local` do CI.
- **Operações expostas (8) e RPC de cada uma:** `cycle.criar`→`ciclo_criar`
  (plano administrativo, sem alvo sintético — D21); `cycle.editar`→`ciclo_editar`;
  `cycle.ativar`→`ciclo_ativar`; `cycle.encerrar`→`ciclo_encerrar`;
  `cycle.cancelar`→`ciclo_cancelar`; `cycle.reabrir`→`ciclo_reabrir`;
  `cycle.corrigir_periodo`→`ciclo_corrigir_periodo`;
  `cycle.admissao.incluir`→`ciclo_incluir_admissao` (matrícula resolvida na
  fronteira pela ponte F3-01; campos estruturais recusados — §13.1 regra 9).
- **D28:** bundle `admin` = 9 capabilities funcionais (`collaborator.create/edit/
  read`, **`cycle.manage`**, `cycle.read`, `membership.read`,
  `org.catalog.manage`, `org.structure.manage`, `settings.manage`);
  `cycle.cancel`/`cycle.reopen`/`cycle.period.correct` **não** estão em nenhuma
  role (configuração explícita apenas).
- **Gates reais desta rodada:** `supabase db reset --local --yes` (migration D28
  aplicada) + **suíte SQL completa na ordem do CI, 25 arquivos, ZERO `[FAIL]`** +
  `npm test`, `npm run build`, `npm run lint`, `npx tsc -b tsconfig.app.json`,
  `git diff --check` e `git status --short` — todos exit 0.
- **Limitações/desvios declarados:** (a) a Edge expõe SOMENTE as 8 operações de
  MUTAÇÃO contratadas — a **leitura/listagem** continua no contrato soberano
  P5/P6 (PostgREST + RLS), porque **não existe RPC de leitura** (`ciclo_painel`/
  `ciclo_historico` não foram criadas em P2–P5) e criar RPC nova não é superfície
  da P7; a pendência da F5-07 (§13.6, `ciclo_listar_colaborador_por_ciclo`)
  permanece aberta; (b) `cycle.editar` exige o período COMPLETO (ano, número,
  datas) porque a RPC `ciclo_editar` não aceita edição parcial — a fronteira não
  faz merge de domínio (§13.1 marcava os campos como opcionais: o contrato real da
  RPC prevalece); (c) `p_payload_hash` não é enviado (hash derivado server-side,
  desvio já declarado em P2–P4); (d) o fluxo LOCAL legado de ciclo
  (`cicloAvaliacaoStorage`) segue intacto — a substituição pela Edge é o cutover
  P8.
- **Permanece para P8+:** cutover de páginas/consumidores e remoção da autoridade
  local de ciclo (P8), validação integrada/concorrência (P9), F5-10 metas e
  F5-11 observações.

### 3.12 F5-09 P6 (implementada; aguardando auditoria independente)

- **Atividade:** F5-09 — **P6 (fechamento do Policy Engine para
  ciclos soberanos) IMPLEMENTADA** — **aguardando auditoria independente**.
  Issue **#200**. Contrato: `docs/F5-09-desenho-tecnico.md` (§8 tabela
  operação→capability + fechamentos aditivos, §16 R13/R17, §19 P6) e
  `docs/F5-09-duvidas.md` (**D8/Q-F5-09-1**, D20, D21, D22 — D28 permanece **P7**).
- **Base:** `main`/`origin/main` = `79203c7fb4e45c9f9cf002e23633f2e4d4abdb5a`
  (F5-09 P5 integrada em `main`).
- **Branch da P6:** `feat/f5-09-p6-cycle-policy-engine` — **sem merge**; push/PR
  ficam com o usuário.
- **Entregue nesta rodada (P6):**
  - `src/authorization/estadoDominioCiclo.ts` (novo): fonte **ÚNICA** da matriz de
    estado do ciclo — `cycle.read` = ciclo real carregado (qualquer status);
    `cycle.manage`/`cycle.cancel` = `PLANEJADO` ou `ATIVO`; `cycle.reopen` =
    `ENCERRADO`; `cycle.period.correct` = `ATIVO`; `CANCELADO` nega as mutações e
    mantém a leitura; status ausente/fora do domínio nega tudo; capability fora
    da matriz é negada (fail-closed);
  - `src/authorization/authorizationPolicy.ts`: o `case "cycle"` passa a decidir
    as **cinco** capabilities (antes `cycle.read`/`cycle.manage` caíam em
    `default → null ⇒ DENY`) sobre o alvo real `{type:"cycle", id: UUID}` com a
    matriz compartilhada; `cycle.cancel` ampliado para `{PLANEJADO, ATIVO}` (D8);
    recurso sem identidade de ciclo é fail-closed; o caso `global` permanece
    apenas como compatibilidade de UX/navegação — **nenhuma** capability de ciclo
    é decidida sobre `{type:"cycle", id:"global"}`;
  - `src/authorization/ResourceContext.ts`: `CycleResource.cycle` passa a ser a
    projeção **mínima** `CicloParaAutorizacao` (`id` = UUID canônico + `status`),
    satisfeita estruturalmente por `CicloSoberano` (P5) **e** por
    `CicloAvaliacao` (legado) — sem entidade nova e sem campo de tenant/identidade
    inventado (o tenant, no enforcement, vem da linha soberana);
  - `src/authorization/resourceContextReal.ts`: `cycle` entra em
    `TIPOS_RECURSO_SOBERANOS` (a P5 deu persistência server-side + RLS),
    passa a exigir identificador **UUID canônico** (`IDENTIFICADOR_INVALIDO` /
    `TARGET_NAO_SOBERANO`) e o `cycleId` do contexto passa a ser o próprio ciclo;
    meta/observação permanecem fora do limite soberano;
  - `src/authorization/contextoAutorizacao.ts`: no alvo `cycle` o `domainState`
    vem **sempre** do status da LINHA SOBERANA carregada (`recurso.status`) —
    estado declarado pelo chamador é ignorado (o legado não suplanta o caminho
    soberano);
  - `supabase/migrations/20260920000000_f5_09_p6_cycle_cancel_description.sql`:
    atualização aditiva da descrição de `cycle.cancel` (D8), com preflight e
    guarda final fail-closed (sem capability nova, sem bundle/role, sem
    schema/RLS/RPC);
  - testes: `src/authorization/ciclosPolicyEngine.test.ts` (matriz
    capability × status × aliases, alvo real, guardas estáticos de fonte única e
    de alvo sintético) e `src/authorization/ciclosFronteiraSoberana.test.ts`
    (fronteira real: UUID canônico, tenant divergente, membership
    revogada/ausente, perfil inativo, ator inexistente, capability
    ausente/revogada, scope insuficiente, alvo sintético/inválido, estado
    soberano prevalecendo e cargo/função textual sem efeito);
  - adaptações explícitas de contrato antigo: `src/authorization/actorContext.test.ts`
    (ciclo agora soberano + UUID obrigatório), `src/authorization/authorizationPolicy.test.ts`
    (`cycle.cancel` em `PLANEJADO` **e** `ATIVO`; `ENCERRADO` negado),
    `src/pages/CiclosAvaliacaoPage.test.tsx` (o botão de cancelamento passa a
    aparecer para ciclo `PLANEJADO` — efeito direto de D8) e
    `src/services/cancelamentoCicloService.test.ts` (a recusa de `PLANEJADO`
    deixou de ser da autorização e passou a ser do domínio LOCAL legado);
  - `supabase/migrations/README.md` e este arquivo.
- **Matriz final das 5 capabilities (P6):** `cycle.read` — ciclo real do tenant,
  qualquer status (inclusive `CANCELADO`); `cycle.manage` — `PLANEJADO`/`ATIVO`
  (o recorte por operação — editar/ativar/encerrar/admitir — segue revalidado nas
  RPCs, §8); `cycle.cancel` — `PLANEJADO`/`ATIVO` (D8); `cycle.reopen` —
  `ENCERRADO`; `cycle.period.correct` — `ATIVO`; `CANCELADO` nega as quatro
  mutações.
- **Gates reais desta rodada:** `supabase db reset --local --yes` (migration P6
  aplicada) + **suíte SQL completa na ordem do CI (24 arquivos, ZERO `[FAIL]`**;
  F4-08 57+9, F5-04 26, F5-08 58+13, F5-09 P1 62, P2 22, P3 18, P4 22, P5 11,
  F5-06 27+14, F5-07 45+23) + `npm test`, `npm run build`, `npm run lint`,
  `npx tsc -b tsconfig.app.json`, `git diff --check` (todos exit 0).
- **Resíduo declarado (P8):** o persistidor **local** legado
  (`cicloAvaliacaoStorage`) ainda exige `ATIVO` para cancelar, então o botão de
  cancelamento exibido para ciclo `PLANEJADO` (autorização já conforme D8) só se
  torna efetivo no cutover P8, quando o fluxo passa a usar a RPC soberana
  `ciclo_cancelar`. O `excluirCiclo` físico local também permanece (D9 proíbe
  exclusão; a auditoria já o classifica como resíduo CRITICAL do P8).
- **Permanece para P7+:** Edge Function `ciclos` + contratos Edge +
  reconciliação aditiva do catálogo (D28: `cycle.manage` no bundle `admin`),
  cutover de páginas/remoção da autoridade local (P8), validação integrada (P9) e
  F5-10/F5-11.

### 3.11 F5-09 P5 (implementada; aguardando auditoria independente)

- **Atividade:** F5-09 — **P5 (leitura soberana de ciclos por RLS
  own-tenant + porta do cliente) IMPLEMENTADA** — **aguardando auditoria
  independente**. Issue **#198**. Contrato: `docs/F5-09-desenho-tecnico.md`
  (§9 policy de leitura, §13.5 superfícies do cliente, §19 P5) e
  `docs/F5-09-duvidas.md` (**D22**).
- **Base:** `main`/`origin/main` = `2e9c2012da8e24995a7ad1dc5e006dcb19475469`
  (F5-09 P4 integrada em `main`).
- **Branch da P5:** `feat/f5-09-p5-cycle-sovereign-read` — **sem merge**; o push do
  sandbox é bloqueado (`.ai/git-rules.md`), então push/PR ficam para o usuário.
- **Entregue nesta rodada (P5):**
  - `supabase/migrations/20260919000000_f5_09_cycle_read_rls.sql`: **RLS de
    leitura** — `enable row level security` em `evaluation_cycles`, policy
    `evaluation_cycles_select_same_tenant` (SELECT para `authenticated` com
    `public.user_has_active_membership(organization_id)`) e `grant select`
    **mínimo** (policy antes do grant). Escrita do cliente **fechada**, `anon` sem
    privilégio, `cycle_events` deny-by-default, nenhuma RPC/capability nova
    (catálogo segue em 31), preflight e guarda final fail-closed.
  - `supabase/validacao/09-cenario-f5-09-p5.sql` (fixture **ISOLADA**, prefixo
    `ec`) e `10-validar-f5-09-p5.sql` (seções **A–K**: own-tenant, cross-tenant e
    IDOR por UUID, sem membership, membership/perfil revogados, JWT fantasma,
    DML negado com `insufficient_privilege`, conformidade de policy/grant,
    `cycle_events` fechado e regressões P1–P4).
  - adaptações de regressão: `02-validar-f4-08.sql` (`evaluation_cycles` passa de
    tabela **fechada** a **legível own-tenant**: listas, contagens e mensagens
    atualizadas), `04-validar-f5-09-p2.sql`, `06-validar-f5-09-p3.sql` e
    `08-validar-f5-09-p4.sql` (admitem a policy do P5 quando **conforme**; seguem
    proibindo RPC de leitura, policy de escrita e leitura por `anon`) e
    `02-validar-f5-06.sql` (a checagem "zero policies nas tabelas F5-06" passa a
    admitir **apenas** a policy de SELECT own-tenant de `evaluation_cycles`; a
    deny-by-default das demais tabelas F5-06 e qualquer policy de escrita
    continuam falha).
  - cliente: `src/application/ports/CycleRepository.ts` (porta **assíncrona** e
    **UUID-first**, resultado discriminado com código público),
    `src/infrastructure/supabase/ciclos/repositorioCiclosSoberanos.ts` (adapter de
    RLS; sessão como **pré-condição** → `NOT_AUTHORIZED`, erro → `FORBIDDEN`/
    `INTERNAL`, linha fora do contrato — **ou de outro tenant** — descartada:
    defesa em profundidade na projeção, já que a RLS é quem isola o tenant),
    `src/services/acessoCiclosSoberanos.ts` (porta única + cache de UX por
    **geração monotônica**: troca de organização/unmount/logout descartam resposta
    em voo) e `src/infrastructure/localStorage/localCycleRepository.ts`
    (**LEGACY/transitório**, `version: 0`, explicitamente **não** é fallback).
  - testes do cliente: adapter, porta/serviço (fail-closed, resposta atrasada,
    organização errada) e **guarda estática** anti-fallback/anti-dual-read, com o
    teste legado reescrito para o contrato assíncrono.
  - `.github/workflows/ci.yml` (o job `supabase-local` executa 09/10 após 07/08 e
    antes das regressões F5-06/F5-07), `supabase/migrations/README.md` e este
    arquivo.
- **Comportamento entregue:** `evaluation_cycles` passa a ser a **fonte de verdade
  de leitura** para o tenant do usuário autenticado: a RLS devolve somente ciclos
  da organização com membership ativa e perfil ativo; o filtro por
  `organization_id` no cliente é apenas **defesa em profundidade** (intenção de
  UX); ausência é **explícita** (`null`/lista vazia) e falha tem **código
  público** — nunca fallback local, dual-read ou dado inventado; `(ano, numero)`
  seguem apenas como **rótulos** (bridge transitória documentada para o cutover do
  P8). **Nenhuma página/componente foi alterado** nesta fase.
- **Gates reais desta rodada:** `supabase db reset` + trio F4-08 + cenário 09 +
  validador 10 (**todas as seções A–K `[PASS]`, zero `[FAIL]`**) + suíte SQL
  completa na ordem do CI (24 arquivos, **ZERO `[FAIL]`**) + `npm test`/
  `npm run build`/`npm run lint`/`npx tsc -b tsconfig.app.json`/
  `git diff --check`, todos exit 0.
- **Permanece para P6+:** Policy Engine `cycle.read`/`cycle.manage` (P6), Edge
  `ciclos` + reconciliação de catálogo/bundle (P7), cutover do frontend e remoção
  do storage local (P8), validação integrada (P9) e soberania de metas/observações
  (F5-10/F5-11).

### 3.10 F5-09 P4 (implementada; aguardando auditoria independente)

- **Atividade:** F5-09 — **P4 (transições excepcionais soberanas:
  cancelar, reabrir e corrigir período) IMPLEMENTADA** — **aguardando auditoria
  independente**. Issue **#194**. Contrato: `docs/F5-09-desenho-tecnico.md`
  (§6 T4/T5/T6/T7, §8 autorização, §10 I7/I8/I11/I12/I19, §11, §12, §13.2/§13.3,
  §19 P4) e `docs/F5-09-duvidas.md` (D1–D28; **D8/D9**, D10–D15 e D20/D21 em
  especial).
- **Base:** `main`/`origin/main` = `c804903d84c5dd6def690137f0ec286bc06ad56e`
  (F5-09 P3 integrada pelo squash do PR #193).
- **Branch da P4:** `feat/f5-09-p4-cycle-exceptional-transitions` — **sem
  merge**; o push do sandbox é bloqueado (`.ai/git-rules.md`), então push/PR ficam
  para o usuário.
- **Entregue nesta rodada (P4) — 6 arquivos:**
  - `supabase/migrations/20260918000000_f5_09_cycle_exceptional_transitions.sql`:
    `ciclo_cancelar` (T4/T5, `cycle.cancel`), `ciclo_reabrir` (T6,
    `cycle.reopen`) e `ciclo_corrigir_periodo` (T7, `cycle.period.correct`),
    todas `SECURITY INVOKER`, `search_path` fixo, `EXECUTE` só `service_role`,
    ACL revogada de `public`/`anon`/`authenticated`, preflight fail-closed do
    baseline e guarda final fail-closed;
  - `supabase/validacao/07-cenario-f5-09-p4.sql` (fixture **ISOLADA**, prefixo
    `eb`, insert-once) e `08-validar-f5-09-p4.sql` (todos os casos obrigatórios da
    P4, incluindo **4 probes cross-tenant diretos** por RPC e **rollback real em
    quatro fases**);
  - `.github/workflows/ci.yml` (o job `supabase-local` executa 07/08 após 05/06 e
    antes das regressões F5-06/F5-07);
  - `supabase/migrations/README.md` (registro da migration) e `.ai/handoff.md`.
- **Comportamento entregue:**
  - **cancelar** — `PLANEJADO`|`ATIVO` → `CANCELADO` (terminal; D8). Em `ATIVO`
    resolve na MESMA transação as avaliações **não concluídas** reusando
    `evaluation_cancelar` (F5-06) e **preserva** as `CONCLUIDA` (e as já
    `CANCELADA`, sem reescrever motivo/data). Em `PLANEJADO` exige que as
    avaliações tenham sido resolvidas antes (fail-closed) e não cria nada.
    Retorno: `cycle_id`, `status`, `version`, `avaliacoes_canceladas`,
    `avaliacoes_concluidas_preservadas`; evento `CANCELADO` com before/after e
    contagens. Nenhum `DELETE` (D9) e snapshots intocados.
  - **reabrir** — somente `ENCERRADO` → `ATIVO`, com motivo, sem outro `ATIVO`
    (I5/D14) e sem sobreposição com ciclos não cancelados (I6/D15). **Sem
    rematerialização**: nenhuma escrita em snapshots/posições/membros/
    responsabilidades/participantes e nenhuma chamada a F3-08/F3-09; **não cria
    avaliações**. Altera apenas `status`, `data_encerramento=null` e `version+1`,
    **preservando** `data_ativacao` e os contadores de pendência (histórico
    íntegro na trilha); evento `REABERTO`.
  - **corrigir período** — só `ATIVO`; `data_inicio <= data_fim`, período
    diferente do atual, `justificativa` obrigatória e sem sobreposição. Não toca
    estrutura/gestores/colegiado/participantes/responsabilidades. **Impacto
    calculado server-side** (o cliente não declara impacto): datas anterior/nova,
    `dias_antes`/`dias_depois`/`dias_delta`, `avaliacoes_no_ciclo`,
    `avaliacoes_concluidas`, `avaliacoes_nao_concluidas`,
    `avaliacoes_concluidas_fora_do_novo_periodo` e `participantes_materializados`;
    evento `PERIODO_CORRIGIDO` com before/after + `impacto` + justificativa.
- **Auditoria do ponto crítico de `version` (double increment):**
  `evaluation_cancelar` (F5-06) incrementa apenas `evaluations.version` e **não**
  toca `evaluation_cycles.version`; `evaluation_fechar_ciclo_pendencias` (que
  incrementa a versão do ciclo) **não** é usada por nenhuma RPC da P4 (a guarda
  final da migration reprova se for). Logo cada RPC incrementa a versão do ciclo
  exatamente uma vez (`expected_version + 1`), como na P2/P3.
- **Desvios mínimos declarados (documentados no header da migration):**
  (a) `p_payload_hash` **não** é parâmetro (mesmo desvio aceito na P2/P3: hash
  canônico derivado server-side); (b) o evento da correção é **`PERIODO_CORRIGIDO`**
  (e não `CORRECAO_PERIODO`): o §12 fixa esse tipo e o CHECK **fechado** de
  `cycle_events.event_type` (P1) só aceita esse nome — usar outro reabriria
  contrato congelado; (c) `ciclo_reabrir` limpa `data_encerramento` (T6) e
  **preserva** os contadores de pendência, com o histórico do encerramento
  integral na trilha append-only.
- **Nota de implementação (fail-closed defensivo):** o ramo "ciclo `PLANEJADO`
  com avaliações" do cancelamento é **inalcançável pelo caminho soberano** (a
  F3-08 só materializa na ativação e a F5-06 exige o snapshot do ciclo); ele é
  exercitado no validador por **estado sintético explícito** (materialização
  direta da estrutura) para provar que a RPC recusa mesmo assim.
- **Gates reais desta rodada (Docker Desktop acessível):** `supabase db reset` +
  cenário 07 + validador 08 (**16 `[PASS]`, 0 `[FAIL]`**) + suíte SQL completa na
  ordem do CI (22 arquivos, **ZERO `[FAIL]`**) + `npm test`/`npm run build`/
  `npm run lint`/`npx tsc -b tsconfig.app.json`/`git diff --check`, todos exit 0.
- **Limitações reais:** a contenção entre DUAS sessões segue não provável no
  validador de sessão única (coberta por lock estrutural + `expected_version`);
  o cenário é **insert-once** e exige `db reset` para nova execução limpa; o
  estado "ENCERRADO sobreposto" é **inalcançável por construção** (a exclusion I6
  recusa a criação sobreposta, provado no validador), então o ramo de
  sobreposição da reabertura é defesa em profundidade; a transição para
  `CONCLUIDA`/`PRONTA_PARA_FEEDBACK` das avaliações de fixture é feita por
  `UPDATE` direto (a completude de notas da F5-06 não é o objeto da P4).
- **Permanece para P5+:** leitura RLS + porta do cliente (P5), Policy Engine
  `cycle.read`/`cycle.manage` + `cycle.cancel`/`cycle.reopen`/
  `cycle.period.correct` (P6), Edge `ciclos` + reconciliação do bundle `admin`
  (P7), cutover do frontend (P8) e validação integrada (P9).

### 3.9 F5-09 P3 (integrada pelo squash do PR #193)

- **Atividade:** F5-09 — **P3 (inclusão aditiva soberana de nova
  admissão em ciclo `ATIVO`) IMPLEMENTADA** — **aguardando auditoria
  independente**. Contrato: `docs/F5-09-desenho-tecnico.md` (§6 nota da inclusão
  aditiva, §7.2 provas P1–P7, §7.3 contrato restrito, §10 I17–I19, §11/§12,
  §13.2/§13.3, §15.1 A1–A12, §19 P3) e `docs/F5-09-duvidas.md` (D1–D28
  ratificadas; **D26/D27** em especial).
- **Base:** `main`/`origin/main` = `c0b9375bc54d58a815e78ed6f332735e3f530d83`
  (F5-09 P2 integrada pelo squash do PR #191).
- **Branch da P3:** `feat/f5-09-p3-cycle-admission` — **sem merge**; o push do
  sandbox é bloqueado (`.ai/git-rules.md`), então push/PR ficam para o usuário.
- **Entregue nesta rodada (P3) — 6 arquivos:**
  - `supabase/migrations/20260917000000_f5_09_cycle_admission.sql`: helper
    **read-only** `ciclo_admissao_pos_ativacao_elegivel` (provas **P1–P7**
    fail-closed, com **motivo de recusa por prova** e evidências da estrutura
    resolvida) + RPC `ciclo_incluir_admissao` (contrato restrito, **sem** nenhum
    parâmetro estrutural), ACL `EXECUTE` só `service_role`, preflight de baseline
    e guarda final fail-closed;
  - `supabase/validacao/05-cenario-f5-09-p3.sql` (fixture **ISOLADA**, prefixo
    `ea`, insert-once, com atores/organizações/estrutura próprios) e
    `06-validar-f5-09-p3.sql` (28 casos obrigatórios + A1–A12, incluindo **4
    probes cross-tenant DIRETOS** na nova RPC e **rollback real em 3 fases**);
  - `.github/workflows/ci.yml` (job `supabase-local` executa 05/06 **após** 03/04
    e **antes** das regressões F5-06/F5-07);
  - `supabase/migrations/README.md` (registro da migration) e `.ai/handoff.md`.
- **Invariantes centrais da P3 (D26/D27):** a operação é a **única** ampliação de
  população depois da ativação e é **exclusivamente aditiva** — nenhum
  snapshot/posição/membro/responsabilidade existente é alterado ou removido (a
  RPC delega a F3-08/F3-09, que só inserem, e não aceita parâmetro estrutural);
  prova soberana de admissão revalidada server-side e **fail-closed**
  (`collaborators.admission_date` **não** é prova; legado/importado sem evento
  `ADMISSAO` é **recusado** — a correção é no caminho de importação); autorização
  e tenant sempre do ator verificado (`cycle.manage` **reusada**, nenhuma
  capability nova; `service_role` executa e não decide); lock normativo
  `evaluation_cycles:<organization_id>` (`ciclo_lock_organizacao`) +
  `expected_version` + idempotência por `(organization_id, operation_id)` com
  hash **derivado server-side**; **um** evento append-only `ADMISSAO_INCLUIDA`
  por mutação, com o **id do evento `ADMISSAO`** que autorizou; movimentação
  posterior **não** rematerializa o ciclo (D27).
- **Desvios mínimos declarados (vs §13.2, documentados no header da migration):**
  (a) `p_payload_hash` **não** é parâmetro (mesmo desvio já aceito na P2: o hash
  é derivado server-side dos parâmetros validados; aceitá-lo permitiria replay
  com hash forjado); (b) a inclusão incrementa `evaluation_cycles.version` **uma
  vez** — o §6 registra que a inclusão **não** é transição de estado, e é o que se
  cumpre (status, datas e contadores de pendência inalterados), mas a população
  materializada muda: sem o incremento o `expected_version` do §13.2 e o campo
  `version` do `after_value` (§12) ficariam degenerados; (c) **nenhum** helper
  novo de materialização — a F3-08 já aceita a menor granularidade segura
  (`array[collaborator_id]`, `on conflict do nothing`) e a F3-09 é idempotente por
  `(snapshot, posição)`; (d) **P6 aplicado de forma estrita**: a presença de
  qualquer evento `ADMISSAO` com `SOMENTE_CICLOS_POSTERIORES` recusa a inclusão
  no ciclo corrente (a operação não escolhe entre evidências conflitantes).
- **Gates reais desta rodada (Docker Desktop acessível):** `supabase db reset` +
  cenário 05 + validador 06 (**19 `[PASS]`, 0 `[FAIL]`**) + suíte SQL completa na
  ordem do CI + `npm test`/`npm run build`/`npm run lint`/`npx tsc -b
  tsconfig.app.json`/`git diff --check`, todos exit 0 (detalhes no PR).
- **Limitações reais:** a contenção entre DUAS sessões segue não provável no
  validador de sessão única (coberta por lock estrutural + `expected_version` +
  P3 de aditividade); o cenário é **insert-once** (trilha append-only) e exige
  `db reset` para nova execução limpa; o colegiado do colaborador admitido é
  **autorado como fixture** no validador, porque o caminho soberano da F5-08 para
  colegiado exige a capability `org.structure.manage` **com scope ativo** — fora
  do escopo da P3.
- **Permanece para P4+:** cancelar (T4/T5), reabrir (T6), corrigir período (T7),
  leitura RLS + porta do cliente (P5), Policy Engine `cycle.read`/`cycle.manage`
  (P6), Edge `ciclos` + reconciliação do bundle `admin` (P7), cutover (P8) e
  validação integrada (P9).

### 3.8 F5-09 P2 (integrada pelo squash do PR #191)

- **Atividade:** F5-09 — **P2 (RPCs soberanas de gestão de ciclo)
  IMPLEMENTADA** — **aguardando auditoria independente**. Contrato:
  `docs/F5-09-desenho-tecnico.md` (§6 T0–T3, §8, §10–§13, §19 P2; D1–D28
  ratificadas) e `docs/F5-09-duvidas.md`.
- **Base:** `main`/`origin/main` = `ccc10b8a468ae2ceee8121634bdca38141df81b6`
  (F5-09 P1 integrada pelo squash do PR #190).
- **Branch da P2:** `feat/f5-09-p2-cycle-management-rpcs` — **sem merge**; o
  push/PR do sandbox é bloqueado (`.ai/git-rules.md`), então o push/PR fica para
  o usuário.
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Entregue nesta rodada (P2) — 6 arquivos:**
  - `supabase/migrations/20260916000000_f5_09_cycle_rpc.sql`: RPCs
    `ciclo_criar` (T0), `ciclo_editar` (T1), `ciclo_ativar` (T2) e
    `ciclo_encerrar` (T3), todas `SECURITY INVOKER`, `search_path = public`,
    `EXECUTE` só `service_role`; preflight fail-closed das primitivas da P1 e dos
    contratos F3-08/F3-09/F5-06; guarda final fail-closed;
  - `supabase/validacao/03-cenario-f5-09-p2.sql` (fixture insert-once, prefixo
    `e9`: 2 orgs, 4 atores, estrutura relacional, colegiado do avaliado) e
    `04-validar-f5-09-p2.sql` (testes A–W do §11 da rodada);
  - `.github/workflows/ci.yml` (job `supabase-local` executa 03/04 após 01/02);
  - `supabase/migrations/README.md` (registro da migration; **heading
    `## Plataforma e ferramentas` restaurado** — havia sido perdido no commit da
    P1) e `.ai/handoff.md` (este registro).
- **Invariantes da P2:** autorização sempre server-side
  (`ciclo_ator_valido` = ator + membership ativa + `cycle.manage` efetiva);
  idempotência por `(organization_id, operation_id)` + hash canônico **derivado
  server-side** (`cycle_events.payload_hash`); serialização pela chave normativa
  `evaluation_cycles:<organization_id>` (`ciclo_lock_organizacao`, P1);
  `expected_version` com CONFLICT; um único `ATIVO` por organização (I5) e
  não sobreposição (I6) da P1 como barreira final; materialização inicial
  **F3-08 + F3-09** na ativação (população elegível = colaboradores com status
  `active` vigente no instante; hierarquia sempre relacional); encerramento
  **reusa** `evaluation_fechar_ciclo_pendencias` (F5-06) sem duplicar lógica;
  **um evento append-only por mutação** (`CRIADO`/`EDITADO`/`ATIVADO`/
  `ENCERRADO`) com autoria soberana; atomicidade total (falha ⇒ rollback).
- **Desvios mínimos declarados (vs §13.2/§6/T2, documentados na migration):**
  (a) `p_payload_hash` **não** é parâmetro — o padrão soberano do projeto deriva
  o hash dos parâmetros validados (aceitá-lo permitiria replay com hash forjado);
  (b) `ciclo_encerrar` incrementa `version` **uma vez** (a F5-06 já incrementa ao
  gravar pendências) ⇒ resultado = `expected_version + 1`;
  (c) `reference_date` da materialização é o **instante** da ativação (o
  parâmetro da F3-08 é `timestamptz`; o §6/T2 escrevia `data_ativacao::date`).
- **Correção pós-CI #204 (somente no validador):** o teste **J** falhava com
  `[FAIL] J: a falha injetada na materializacao nao abortou a ativacao` porque
  rodava com **C1 ainda ATIVO**: `ciclo_ativar` recusava por I5/D14 (um único
  `ATIVO` por organização) **antes** da materialização, de modo que o gatilho
  injetado nunca era atingido — o teste não maquiava o erro (assertava a mensagem
  `MUT_F5_09_P2`), por isso falhava corretamente em vez de passar em falso.
  Correção **restrita a `supabase/validacao/04-validar-f5-09-p2.sql`**: as 4 RPCs,
  a regra de ciclo único ATIVO, a ordem validação→materialização, a migration e
  D1–D28 **não** foram tocadas. A prova de rollback do **encerramento** (O) passou
  a rodar sobre **C1** (o ciclo legitimamente ATIVO/version 2 da fixture), M/N
  encerra C1 e, **só então**, **J** roda sobre **C3** (2030/3), quando a
  organização já não tem ciclo ATIVO — a única pré-condição legítima para a
  ativação alcançar a materialização. J ganhou duas fases de falha injetada:
  **J.1** aborta na **2ª linha** do `INSERT` em `collegiate_cycle_snapshots`
  (contador por `SEQUENCE` não transacional, lido **depois** do rollback: prova de
  que havia trabalho parcial realmente executado) e **J.2** aborta no `INSERT` de
  `cycle_evaluation_responsibilities`, com o F3-08 já materializado; em seguida
  prova-se o rollback total (`PLANEJADO`, `data_ativacao` nula, version 0, zero
  snapshot/posição/membro/responsabilidade, zero evento) e a ativação legítima
  posterior (4 snapshots + responsabilidades + evento `ATIVADO`). Revisão
  preventiva da **mesma classe de pré-condição**: O e M/N dependiam de C3 estar
  ATIVO (que J, quebrado, nunca ativava) e agora operam sobre C1 com guarda de
  pré-condição explícita; R, P/Q, U, S/T e W foram conferidos e são independentes
  de ordem/estado `ATIVO`.
- **Limitações reais da rodada:** com o Docker Desktop disponível, a suíte SQL
  local completa foi executada neste host (`db reset` + os 18 arquivos de
  `supabase/validacao/` na ordem do CI, incluindo P1 e P2): **0 `[FAIL]`**, todos
  os arquivos com exit 0, e o validador P2 com 16 `[PASS]` (J.1 abortando na 2ª
  linha do `INSERT` de snapshots e J.2 no `INSERT` de responsabilidades); a
  **contenção real entre DUAS sessões** continua não provável no validador de
  sessão única (provado por lock estrutural + `expected_version` + I5, com a
  limitação registrada no §U); o cenário é **insert-once** (a trilha é append-only
  protegida) e o validador exige `db reset` para nova execução limpa.
- **Permanece para P3+:** admissão durante ciclo ativo (P3), cancelar/reabrir/
  corrigir período (P4), leitura RLS + porta do cliente (P5), Policy Engine
  `cycle.read`/`cycle.manage` (P6), Edge `ciclos` + reconciliação do bundle
  `admin` (P7), cutover do frontend/localStorage (P8) e validação integrada (P9).

### 3.7 F5-09 P1 (integrada pelo squash do PR #190)

- **Entregue na P1 — 5 arquivos:**
  - `supabase/migrations/20260915000000_f5_09_cycle_sovereign.sql`: **I5** índice
    único parcial `uq_evaluation_cycles_org_ativo` (um ciclo `ATIVO` por
    organização); **I6** exclusion parcial
    `ex_evaluation_cycles_periodo_no_overlap`
    (`daterange(data_inicio, data_fim + 1, '[)')` — `data_fim` inclusiva para o
    produto —, com `CANCELADO` e linhas sem período fora do índice); `DELETE` e
    `TRUNCATE` de `evaluation_cycles` revogados de
    `public`/`anon`/`authenticated`/`service_role` (**D8/D9** — exclusão física
    proibida em todos os estados); trilha append-only **`cycle_events`** (FK
    composta `(cycle_id, organization_id)`, FK composta de autoria, `unique
    (organization_id, operation_id)` para idempotência, `payload_hash` SHA-256
    hex, CHECKs de `entity_type`/`event_type` — já contemplando
    `ADMISSAO_INCLUIDA` do P3 —, trigger de UPDATE negado, RLS deny-by-default
    integral com `service_role` recebendo só `SELECT`/`INSERT`); helpers
    `ciclo_ator_valido` (perfil + membership ativa + allowlist FECHADA das
    capabilities de ciclo, reusando `evaluation_ator_valido` e
    `resolver_capabilities_efetivas`) e `ciclo_lock_organizacao` (chave
    **normativa** única da família: `evaluation_cycles:<organization_id>`);
    pre-flight de baseline fail-closed (não corrige dados) e guarda final
    fail-closed. **Sem RPCs `ciclo_*`** (P2+) e **sem policy de leitura** (P5).
  - `supabase/validacao/01-cenario-f5-09.sql`: fixture determinística e
    reexecutável (2 orgs; 7 ciclos — adjacência de período, `CANCELADO`
    sobreposto, ciclo sem período e o mesmo período em outro tenant; atores com e
    sem capability, membership e perfil desabilitados; 1 evento de trilha).
  - `supabase/validacao/02-validar-f5-09.sql`: validador do P1 (schema do
    contrato, I5/I6 por comportamento, `data_fim` inclusiva por adjacência,
    exclusão física negada por ACL **e** por comportamento, `cycle_events`
    completo — incluindo idempotência e FKs de tenant —, append-only em duas
    camadas, helpers, lock e regressão F5-06/F5-07/F5-08).
  - `.github/workflows/ci.yml`: o job `supabase-local` passou a executar
    `01-cenario-f5-09.sql` + `02-validar-f5-09.sql` **antes** da regressão
    F5-06/F5-07.
  - `supabase/migrations/README.md`: registro da migration da P1.
- **NÃO entregue (fora do P1, por contrato — nada antecipado):**
  `ciclo_criar`/`ciclo_editar`/`ciclo_ativar`/`ciclo_encerrar` (P2),
  `ciclo_incluir_admissao` + helper de elegibilidade da admissão (P3),
  `ciclo_cancelar`/`ciclo_reabrir`/`ciclo_corrigir_periodo` (P4), leitura RLS +
  porta/projeção do cliente (P5), Policy Engine (P6), Edge `ciclos` +
  reconciliação do bundle `admin` (P7), cutover (P8) e validação integrada (P9).
  Nenhuma capability nova e nenhum arquivo de `src/` alterado.
- **Gates desta rodada:** `npm test` (**108 arquivos / 1677 testes**, exit 0),
  `npm run build` (exit 0), `npm run lint` (exit 0),
  `npx tsc -b tsconfig.app.json` (exit 0) e `git diff --check` (exit 0). Os
  **validadores SQL NÃO foram executados neste host**: o daemon do Docker Desktop
  está inacessível (`permission denied ... npipe:////./pipe/dockerDesktopLinuxEngine`,
  com timeout inclusive sob elevação), então `supabase db reset` + `01/02` rodam
  no job `supabase-local` do CI — limitação registrada, nunca mascarada como
  verde.
- **Próxima atividade:** auditoria GPT do P1; depois **P2** (RPCs de gestão do
  ciclo), sem decisão arquitetural aberta.
- **Correção pós-CI (PR #190, mesma branch):** o job `supabase-local` falhava no
  validador **legado** `supabase/validacao/02-validar-f4-08.sql` **antes** dos
  validadores da F5-09, com
  `[FAIL] tabela public nao classificada (D16 — catalogacao explicita
  obrigatoria): cycle_events` — o schema guard global do F4-08 exige catalogação
  explícita de toda tabela `public` e ainda não conhecia a tabela nova. Correção
  **mínima e sem relaxar contrato**: `cycle_events` foi classificada como
  **tabela fechada** (RLS habilitada, **sem policy**, **sem SELECT/INSERT/UPDATE/
  DELETE** para `authenticated`/`anon`, `service_role` apenas `SELECT`/`INSERT`,
  append-only) em todas as listas/contadores do F4-08 — `v_closed` (policy, 22→23),
  `v_closed` (SELECT, 22→23), anon `v_todos` (44→45), DML `v_todos` (44→45), schema
  guard (44→45) e a lista comportamental de tabelas fechadas invisíveis (22→23) —
  e nas **duas cópias** da lista de classificação do
  `03-validar-f4-08-mutacoes.sql` (mutação B). `collaborator_events` permanece na
  categoria especial dele (policy SELECT own-tenant sem grant). A migration da P1
  **não** foi alterada e nenhuma regra da F5-09/P1 foi relaxada (contagem total de
  policies segue 22: `cycle_events` não tem policy no P1).
- **Correção pós-CI #2 (PR #190, mesma branch):** o passo
  `Run F5-08 cutover validation (P6)` falhava com
  `[FAIL] P6-6: funcao com advisory lock fora da chave normativa: ciclo_lock_organizacao`.
  O P6-6 fazia uma **varredura global** de funções com `pg_advisory_xact_lock` e
  pressupunha que toda função com lock pertencia à família estrutural da F5-08.
  Correção **mínima e sem relaxar D24**: o P6-6 passou a ser uma **classificação
  explícita por família** — catálogo fechado da **família estrutural** (15 RPCs da
  F5-08 + as 4 RPCs estruturais da F5-07 alinhadas pela `20260914020000` + os 2
  triggers anti-ciclo da F3-04/F5-08), cada uma provada **por função** como usuária
  **exclusiva** de `position_reporting_lines:<org>` (e de nenhuma chave alheia), e
  catálogo fechado das **demais famílias** com a sua chave normativa própria —
  hoje `ciclo_lock_organizacao` → `evaluation_cycles:` (F5-09, família de ciclos).
  Um **fechamento** reprova qualquer função com advisory lock fora dos dois
  catálogos (família nova exige catalogação explícita), a proibição de
  `SECURITY DEFINER` com lock continua global e a não vacuidade passou a exigir
  ≥ 15 funções **estruturais** com a chave D24. `ciclo_lock_organizacao` e a
  migration da F5-09/P1 **não** foram alteradas (a F5-09 **não** reutiliza
  `position_reporting_lines:` nem `f5_07_estrutura:`).
- **Correção pós-auditoria Codex (PR #190, mesma branch):** o bloqueante era
  `cycle_events` não ser append-only contra **privilege drift** (o trigger cobria
  só `UPDATE`; `DELETE`/`TRUNCATE` dependiam de revokes). Correção **na P1**:
  `enforce_cycle_events_append_only()` passou a levantar exceção para as três
  operações (`TG_OP` no motivo) e a trilha ganhou `trg_cycle_events_no_delete`
  (`BEFORE DELETE` row-level) e `trg_cycle_events_no_truncate` (`BEFORE TRUNCATE`
  statement-level) — proteção no banco **inclusive para o owner e para
  `service_role`**, mantidos os revokes como primeira camada; a guarda final da
  migration passou a exigir os três triggers. O validador
  `02-validar-f5-09.sql` ganhou a seção §4.3: probes de `UPDATE`/`DELETE`/
  `TRUNCATE` negados **para o owner** e sob **privilege drift simulado** (grant
  temporário de `DELETE`/`TRUNCATE` a `service_role`, revertido ao final, com
  conferência de ACL e de que a trilha continua com 1 linha). Consequência
  necessária: o cenário `01-cenario-f5-09.sql` deixou de apagar/recriar a fixture
  (a trilha é protegida e as FKs são `ON DELETE RESTRICT`) e passou a ser
  **INSERT-ONCE** (guarda `\gset`/`\if` + reexecução no-op). `evaluation_cycles`
  **não** foi alterada e nenhuma P2+ foi antecipada.

### 3.6 F5-09 — desenho técnico (rodada anterior, integrada pelo PR #189)

> Histórico do contrato; **não** é o estado atual da atividade (ver §3 acima).

- **Atividade:** F5-09 — **Ciclos soberanos** — **DESENHO
  TÉCNICO revisado** (`docs/F5-09-desenho-tecnico.md`, D1–D28 e fases P1–P9) com o
  registro de ratificação em `docs/F5-09-duvidas.md`
  (Q-F5-09-1..3 **RATIFICADAS**; nenhuma dúvida aberta).
- **Base:** `main`/`origin/main` = `6550c81d14a9d3e61b3c1b4f49471948f880bbc8`
  (F5-08 P6 integrado, PR #188; baseline esperado da F5-09 conferido).
- **Branch do desenho:** `docs/f5-09-ciclos-soberanos` — **sem PR** nesta rodada;
  **somente documentação**: nenhuma migration, RPC, Edge Function, capability,
  policy, teste de runtime ou alteração de frontend entrou nesta rodada.
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Entregue nesta rodada (desenho F5-09):**
  - autoridade soberana do ciclo reusa `public.evaluation_cycles` (F5-06 D15) de
    forma **aditiva** — nenhuma tabela concorrente de ciclo/estrutura/versão;
  - identidade canônica = `evaluation_cycles.id` (UUID); `(ano, numero)` é apenas
    rótulo humano e regra de unicidade (`uq_evaluation_cycles_org_ano_numero`); a
    ponte `(ano, numero) → UUID` (`evaluation_resolver_ciclo` e o mapa de
    `assignedSupabase.ts`) permanece só como INTENÇÃO na fronteira confiável, com
    condição de remoção registrada;
  - máquina de estados sobre os quatro estados já existentes, com origem,
    destino, capability, pré-condições, efeitos transacionais e reversibilidade
    por transição; `CANCELADO` terminal; encerramento **reusa**
    `evaluation_fechar_ciclo_pendencias`; cancelamento resolve as avaliações não
    concluídas na mesma transação;
  - estrutura por ciclo = snapshot F3-08 + responsabilidades F3-09 + congelamento
    de participantes da F5-06 (congelada na ativação; hierarquia sempre relacional,
    nunca texto);
  - integridade nova no banco: índice único parcial de ciclo `ATIVO` por
    organização, exclusion de sobreposição de períodos (meio-aberto), trilha
    append-only `cycle_events` com `unique (organization_id, operation_id)` +
    `payload_hash`, chave normativa de advisory lock por organização;
  - autorização **sem capability nova** (`cycle.read`, `cycle.manage`,
    `cycle.cancel`, `cycle.reopen`, `cycle.period.correct`), Edge nova
    `supabase/functions/ciclos` (namespace `cycle.*`) e RPCs `ciclo_*`
    (SECURITY INVOKER, EXECUTE só `service_role`);
  - leitura soberana por RLS own-tenant (`user_has_active_membership`) + grant de
    SELECT a `authenticated`; escrita do cliente permanece fechada (deny-by-default);
  - cutover do cliente classificado A/B/C/D para os **21 arquivos** que hoje leem
    ou escrevem ciclo local;
  - fecha a pendência declarada da F5-07 (filtro de histórico do colaborador por
    ciclo) usando `collaborator_events.reference_cycle_id`;
  - **duas lacunas de contrato identificadas e endereçadas de forma aditiva:**
    `cycle.read`/`cycle.manage` caem hoje no `default → null` do
    `authorizationPolicy.ts` (⇒ DENY) e nenhuma role de sistema concede
    `cycle.manage` (o bundle `admin` tem só `cycle.read`) — resolvida pela **D28**
    (reconciliação aditiva do catálogo no P7).
- **Revisão 2 desta rodada (RATIFICAÇÃO incorporada):** a auditoria GPT do desenho
  ratificou as três dúvidas e o contrato foi revisado de ponta a ponta — **zero
  dúvida bloqueante aberta**:
  - **Q-F5-09-1 (alternativa A)** — `PLANEJADO→CANCELADO` permitido com
    `cycle.cancel`, motivo obrigatório, autoria soberana, trilha append-only,
    `expected_version` e idempotência; `CANCELADO` terminal; **exclusão física
    proibida em todos os estados** (D8/D9; ampliação aditiva do `domainState` e da
    descrição da capability, sem capability nova);
  - **Q-F5-09-2 (regra híbrida)** — a estrutura do ciclo **não** é "congelamento
    absoluto" nem rematerialização genérica: população inicial materializada na
    ativação, **admissões posteriores elegíveis podem ser acrescentadas** por
    operação soberana, explícita, auditada e **exclusivamente aditiva** (D26), com
    snapshots existentes **imutáveis** e movimentações de posição/unidade/gestor/
    reporting line/colegiado valendo **no próximo ciclo** (D27);
  - **Q-F5-09-3 (alternativa A)** — `cycle.manage` entra **aditivamente** no bundle
    `admin`; `cycle.cancel`/`cycle.reopen`/`cycle.period.correct` permanecem fora
    do bundle, só por configuração explícita (D28, executada no P7).
- **Inclusão aditiva de nova admissão (D26) — onde ficou:** operação restrita
  `cycle.admissao.incluir` / RPC `ciclo_incluir_admissao` + helper read-only
  `ciclo_admissao_pos_ativacao_elegivel`, na fase **P3**. A prova de "nova
  admissão" é **soberana** (nunca flag do cliente): evento append-only
  `collaborator_events.event_type = 'ADMISSAO'` com
  `cycle_scope = 'CICLO_ATUAL_E_POSTERIORES'` e `effective_date > data_ativacao`,
  mais ausência de período de status anterior à ativação em
  `collaborator_status_periods`; a coluna declarada
  `collaborators.admission_date` **não** é prova. Sem prova ⇒ **recusa**
  (fail-closed), registrada como requisito técnico da implementação (§7.2/R15) —
  a regra não é flexibilizada. O contrato **não** tem parâmetro estrutural algum e
  impede por construção sobrescrever snapshot, trocar posição, recalcular gestor
  ou colegiado, inclusão cross-tenant e uso genérico como "atualizar estrutura".
- **Plano revisado:** **P1–P9** (a fase nova **P3** existe para a inclusão aditiva
  e a reconciliação do catálogo ficou no **P7**); D1–D28. **(Estado atual: P1
  implementada — ver §3.)**
- **`.ai/current-task.md`:** não existe neste repositório (nem no histórico). A
  ausência é registrada aqui conforme `AGENTS.md` §1; o estado operacional de
  retomada continua sendo este arquivo.

### 3.5 F5-08 (concluída e integrada)

- **Atividade:** F5-08 — Estrutura organizacional e catálogos soberanos (contrato
  em `docs/F5-08-desenho-tecnico.md`, D1–D25). P1–P6 integrados em `main`; o
  squash do P6 (cutover estrutural) é `6550c81` (PR #188) — a antiga branch
  `feat/f5-08-p6-cutover-estrutura` está encerrada e **nada da F5-08 foi
  transferido para a F5-09** (a F5-09 só assumiu o domínio de ciclos).
- **Entregue (P1–P5, na base):** migrations `20260914000000`
  (`structure_events` append-only + triggers I1–I3 + grants), `20260914010000`
  (15 RPCs `estrutura_*`/`catalogo_*`) e `20260914020000` (chave única de advisory
  lock, D24); contrato/Edge `supabase/functions/colaboradores`; porta/serviço do
  cliente (`services/colaboradoresSoberanos/acessoColaboradoresSoberanos.ts`),
  leitura soberana por RLS
  (`infrastructure/supabase/estrutura/repositorioEstruturaSoberana.ts`); telas
  Unidades/Posições/Catálogos/Colegiado e alocação do colaborador (ocupação +
  reporting line).
- **Entregue nesta rodada (P6 — cutover estrutural):**
  - `authorizationPolicy.ts`: fallback do mundo funcional para o cadastro local
    **removido**; resta apenas sob barreira explícita de DEV
    (`simulacaoDevPermitida`) ⇒ produção fail-closed;
  - `mundoFuncional.ts`: `SEM_BINDINGS_DEV` — a derivação local de bindings deixou
    de ser implícita; sem binding explícito (teste) ou da projeção soberana, a
    capability é NEGADA (inclusive o fluxo SELF);
  - `historicoOrganizacionalStorage.ts`: sem promoção de texto `respondePara` a
    relação de gestão (escrita local é barreira desde a F5-07);
  - `src/data/evaluationTeam.ts` removido (código morto, sem consumidores);
  - guardas do cutover: bloco P6 em
    `src/authorization/estruturaUiSeguranca.test.ts` (sweep global de `src/`) e
    `src/authorization/cutoverEstrutural.test.ts` (runtime, produção × DEV);
  - `supabase/validacao/03-validar-f5-08-cutover.sql` (leitura RLS own-tenant
    positiva/negativa, fail-closed sem membership ativa, superfície de escrita do
    cliente fechada, capability negada, RPC como única autoridade, chave única de
    serialização, idempotência e histórico preservado);
  - `.github/workflows/ci.yml`: o job `supabase-local` passa a executar os **três**
    validadores da F5-08 e a regressão F5-06/F5-07 (§13.7/§23.4); timeout 40 min.
- **Blockers da auditoria RESOLVIDOS (correção nesta branch):** o §19.1 do
  contrato exige que as decisões de elegibilidade/papel de `progressoAvaliacao`,
  `cicloEquipeService` e `metaStorage` usem estrutura SOBERANA — não era decisão
  futura da F5-09. Duas rodadas de correção, sem criar fonte nova (sem
  migration/RPC/Edge/capability):
  - **1ª rodada:** `src/services/projecaoEstruturalSoberana.ts` como fronteira; os
    três módulos + `permissaoAvaliacao.ts` + `MinhaAvaliacaoDetalhePage.tsx`
    deixaram de ler `funcao`, `gestorDiretoMatricula`,
    `avaliadoresColegiadoMatriculas` e `getColaboradoresVisiveis`;
    `authorization/providers/localWorld.ts` virou DEV-only (fora do gate ⇒ mundo
    vazio ⇒ DENY); fail-closed em todas as decisões.
  - **2ª rodada (blockers finais):** a projeção passou a ser **UUID-first** —
    `collaboratorId`, `gestorSoberanoPositionId`, `cadeiaDeGestaoPositionIds`,
    `cadeiaDeGestaoCollaboratorIds`, `colegiadoSoberanoCollaboratorIds` — e o
    modelo **não conhece matrícula**; o campo textual `papel`
    (GERENTE/COORDENADOR/OUTRO) foi **eliminado** e substituído por fatos
    relacionais soberanos (`temCadeiaDeGestaoSoberana`,
    `gestorSoberanoTemSuperior`, `raizDaCadeiaSoberana`, `colegiadoSoberano`);
  - **PRODUTOR conectado:** `src/services/estruturaSoberanaCliente.ts` carrega a
    estrutura pelo caminho normal já existente (`lerEstrutura` RLS/P4 +
    `listarColaboradores` F5-07), publica a projeção e mantém a **ponte de
    compatibilidade** matrícula ↔ UUID (fronteira, nunca chave estrutural);
    `src/pages/useEstruturaSoberanaDoCliente.ts` é acionado pelo shell
    autenticado (`LayoutFuncional` em `src/routes/AppRoutes.tsx`) — nenhum
    consumidor injeta projeção manualmente e a ausência de injeção deixou de ser
    "modo DENY";
  - **Blocker final (corrida/multi-tenant) RESOLVIDO:** o produtor deixou de
    deduplicar A e B como se fossem a mesma solicitação. Agora há **geração
    monotônica** (`let geracao = 0`) + organização vigente: uma carga só publica
    se ainda for a vigente (`publicarSeVigente`); iniciar uma carga publica
    imediatamente `carregando` com estrutura VAZIA (a estrutura do tenant anterior
    deixa de ser acessível na troca); a dedupe é **por organização**; e
    `invalidarEstruturaSoberana()` (usada pelo hook quando a organização ativa
    vira `null`/`undefined`) incrementa a geração, limpa a carga em curso e
    publica estado inválido/vazio — resposta antiga nunca republica;
  - **Residual final (unmount/logout) RESOLVIDO:** o hook ganhou um cleanup de
    **dependência VAZIA** (`useEffect(() => () => invalidarEstruturaSoberana(), [])`)
    que roda **apenas no unmount** do shell — o `LayoutAutenticado` pode parar de
    renderizar o `LayoutFuncional` sem passar por `organizacaoAtivaId == null`;
    sem ele, a estrutura do tenant A permanecia em memória após o logout e um
    login posterior em B podia observá-la antes do novo efeito executar. Não roda
    em re-render nem na troca A → B (que tem caminho próprio);
  - provas: `projecaoEstruturalSoberana.test.ts` (8), `estruturaSoberanaCliente.test.ts`
    (19 — corrida A→B determinística nos dois sentidos, dedupe por org, `null`
    invalidando contexto, falha real sem vazar outro tenant e lifecycle do shell:
    unmount invalida + assinatura removida, carga em voo não publica, novo login
    em B nunca vê A, A→B sem unmount segue funcionando),
    `cutoverEstruturalServicos.test.ts` (4) e o bloco estático
    `estruturaUiSeguranca.test.ts` (39 no arquivo), que reprova modelo com
    matrícula, consumidores lendo campos locais, produtor não acionado, produtor
    sem proteção de troca de tenant e hook sem cleanup de unmount;
  - `docs/F5-08-p6-duvida-mundo-funcional.md` documenta os blockers resolvidos, a
    identidade UUID, a segurança multi-tenant (§2.3), o fail-closed e o que resta
    à F5-09 (apenas o domínio de ciclos: persistência e estrutura POR CICLO) — sem
    autoridade estrutural local.
- **Residual declarado (fora do blocker, não silencioso):** `relatorioService`
  (filtros por `gestorDiretoMatricula`), `exportarAvaliacaoPdf` (identificação de
  avaliadores), `visibilidadeColaboradores` (sem chamador de produção) e
  `historicoOrganizacionalStorage` (snapshots/efetivos). Registrado na §6 do
  documento acima; exige atividade própria (relatórios/PDF).
- **Consequência do cutover (verificada):** em produção a estrutura de
  ciclo/metas é obtida da leitura soberana (RLS) pelo produtor publicado no shell
  autenticado, sempre correspondendo à **organização ativa** (troca de tenant
  segura); falha real do Supabase ⇒ fail-closed, e a decisão real de autorização
  permanece server-side (Edge + Policy Engine + RLS). Coberto por
  `cutoverEstrutural.test.ts`, `cutoverEstruturalServicos.test.ts`,
  `projecaoEstruturalSoberana.test.ts` e `estruturaSoberanaCliente.test.ts`.
- **Validação então registrada (branch do P6):** `npm test` (**108 arquivos /
  1677 testes** verdes), `npm run build`, `npm run lint`,
  `npx tsc -b tsconfig.app.json` e `git diff --check` executados localmente
  (todos verdes). Os **validadores SQL não foram executados** naquele host
  (Docker/Supabase indisponível) — rodam no job `supabase-local` do CI; a
  limitação está registrada no relatório da atividade. Nenhuma
  migration/RPC/Edge/capability nova foi criada no P6.

### 3.1 F5-07 (concluída e integrada)

- **Atividade:** F5-07 — Colaboradores e histórico organizacional soberanos
  (contrato em `docs/F5-07-desenho-tecnico.md`, D1–D20); integrada em `main` como
  `7137f1f`.
- **Entregue:** migrations `20260913000000`/`20260913010000` (extensões aditivas em
  `collaborators`, `job_roles.code`, log append-only `collaborator_events`, helper
  de ator e 16 funções/RPCs), Edge `colaboradores` (15 operações, com gate
  funcional no Policy Engine e gate administrativo da F5-04 **separados**), porta
  única `acessoColaboradoresSoberanos`, barreiras fail-closed em
  `colaboradorStorage`/`historicoOrganizacionalStorage`, telas migradas para UUID
  com matrícula resolvida no servidor e remoção do código morto.
- **Validação então registrada:** `npm test` 94 arquivos / 1346 testes; `build`,
  `lint` e `git diff --check` verdes; validadores SQL após `db reset` — F5-07
  (44 PASS + 22 PASS de cutover), F4-08 (56 + 8) e F5-06 (25 + 13).
- **Limites assumidos:** alocação/estrutura (cargo, área, função, senioridade,
  gestor, colegiado) é **F5-08** — a F5-07 não fabrica estrutura sintética e as
  telas exibem "sem alocação". Ciclos/metas/observações seguem legados.
- **Defeito PREEXISTENTE em `main`, não corrigido (fora de escopo):** a Edge
  `supabase/functions/avaliacoes/index.ts:8` importa
  `src/authorization/catalogoCapacidades.ts` (inexistente; o módulo real é
  `catalogoCapabilities.ts`), o que impede o bundle da função F5-06. Não afeta
  `npm test`/`build`/`lint`/`tsc` (apenas o bundle Deno da Edge).

### 3.2 BUG #170 (concluída e integrada)

- **Atividade:** BUG #170 — item "Ciclos" duplicado no menu para Gerente e
  Coordenador (Issue #170). Correção de **navegação/UX**, integrada em `main`.
- **Branch:** `fix/170-ciclos-menu-duplicado`.
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Causa raiz:** `NavegacaoPrincipal` tinha DOIS gates de menu para o MESMO
  assunto — `cycle.management.view` (`/ciclos`) e `cycle.coordinator.list`
  (`/painel-ciclos`). Ambos são **aliases da mesma capability canônica**
  (`cycle.read`, colapso Q1 da F4-09 em `authorization/canonical.ts`), e Gerente e
  Coordenador possuem `cycle.read`: as duas condições ficavam verdadeiras ao mesmo
  tempo e o menu renderizava dois itens consecutivos rotulados "Ciclos" (ambos com
  `IconCalendar`). Antes da centralização F4 os gates eram
  `funcao === "GERENTE"` / `funcao === "COORDENADOR"` — mutuamente exclusivos —,
  por isso o rótulo repetido nunca aparecia.
- **Correção:** UM ÚNICO item "Ciclos" → `/ciclos`, gated pela capability canônica
  `cycle.read` (visibilidade de menu é UX; o resource `{ kind: "global" }` é
  transitório e nunca prova de autorização). Rotas, capabilities, roles, RLS e
  contratos F4/F5 intactos. `/painel-ciclos` permanece rota autorizada e
  alcançável por "Minha equipe" (Início → `ColaboradoresPage`, botão do
  COORDENADOR). Teste novo `src/components/NavegacaoPrincipal.test.tsx` (13 casos)
  fixa o invariante de UM item por contexto e o menu completo de Gerente,
  Coordenador, Analista, Consultor, Estagiário e colaborador sem função.
- **Validação desta rodada (todo exit 0):** `npm test` (85 arquivos, 1082 testes),
  `npm run build`, `npm run lint`, `git diff --check origin/main...HEAD`.

### 3.3 DEV-02 (concluída e integrada)

- **Atividade:** DEV-02 — reduzir interrupções por elevação de acesso dos agentes
  (Issue #177). Somente camada de contexto; sem alteração funcional.
- **Integração:** `main` no SHA `e098754…` (PR #178).
- **Regra registrada:** `.ai/workflow.md` **§6**, com síntese permanente em
  `AGENTS.md` **§4**: aprovação técnica/arquitetural ≠ autorização de elevação de
  acesso; com desenho FECHADO não se repete pedido de aprovação; trabalho em lote
  com autoauditoria estática antes dos comandos privilegiados; comandos que exigem
  elevação agrupados em um ou poucos gates; proibido alterar PAT/credenciais/
  configurações ou reduzir controles.
- **Limitação do ambiente (registrada):** neste host o sandbox exige elevação
  (`danger-full-access`) até para comandos triviais (`git status`, `npm test`,
  `lint`) e para Docker/Supabase — agrupar operações por gate e registrar a
  limitação, nunca contornar a proteção (`.ai/git-rules.md` §3;
  `.ai/workflow.md` §6.4).

### 3.4 F5-06 (concluída e integrada)

- **Atividade:** F5-06 — Avaliações no PostgreSQL (Issue #103).
- **Branch:** `feat/f5-06-avaliacoes-postgresql` — **squash merge em `main`** como
  `f540f0f5d16a4b3f33a99f7e4f0e8fb7c5c30584` (PR #176, `Closes #103`); a cabeça do
  PR auditada foi `a11687e…`, com a correção final de whitespace em `c38de2b…`.
- **PR:** #176 — fechado e integrado. Este agente **não** declara a atividade
  aprovada: a aprovação é da auditoria independente.
- **Estado — SQL, fronteira e caminho TS (completo e validado):** migrations
  F5-06 (schema, funções e `20260911020000_f5_06_cutover_leitura_e_ciclo.sql`),
  Edge Function `avaliacoes`, policy/capabilities, ponte matrícula → UUID,
  resolução ano+ciclo, painel do participante e `cutoverAvaliacoesService`.
- **Estado — CUTOVER DAS TELAS (concluído nesta rodada):** nenhuma avaliação
  NOVA é criada/editada/cancelada/reaberta em `localStorage`; a autoridade é o
  PostgreSQL pelo caminho soberano.
  - Telas migradas: `NovoFeedbackPage` (criação + notas/observações/comentário
    final), `EditarFeedbackPage` (leitura do painel + gravação soberana +
    conclusão), `FeedbackDetalhePage` (cancelar/reabrir soberanos),
    `CiclosAvaliacaoPage` (ativação e encerramento).
  - Serviços migrados: `cancelamentoAvaliacaoService`,
    `reaberturaAvaliacaoService`, `cicloEquipeService`
    (`criarAvaliacoesDoCicloAtivado` e `concluirAvaliacoesNoEncerramentoDoCiclo`
    agora **async** e soberanos).
  - Novos módulos: `src/services/acessoAvaliacoesSoberanas.ts` (porta única das
    telas; nenhuma página importa Supabase) e `src/services/origemAvaliacaoTela.ts`
    (FONTE ÚNICA da decisão de origem, por EVIDÊNCIA de cutover).
  - Síncrono → assíncrono: `criarAvaliacoesDoCicloAtivado`,
    `concluirAvaliacoesNoEncerramentoDoCiclo`, `cancelarAvaliacao`,
    `reabrirAvaliacao` e os handlers das quatro telas (com estados de
    processamento/erro preservados).
  - `feedbackStorage` é **somente leitura** para o legado: `saveFeedback` foi
    removida; `updateFeedback`, `persistirCancelamentoAuditadoInterno`,
    `persistirReaberturaAuditadaInterno` e `removerAvaliacaoVaziaNoCleanupInterno`
    existem apenas como barreiras que lançam (fail-closed). Exclusão de ciclo com
    avaliação vazia no legado agora é recusada — a limpeza do legado pertence à
    atividade de importação (fora do escopo, §1.3).
- **Estado — CORREÇÕES PÓS-AUDITORIA GPT (rodada 1):**
  1. **Origem POSTGRES exige EVIDÊNCIA, nunca formato.** `ehIdTecnicoPostgres`
     passou a ser usado SOMENTE como validação de formato, nunca como
     classificação de origem; id legado numérico, textual ou **em formato de
     UUID** não é promovido por isso; nenhuma heurística de data.
  2. **Navegação das avaliações novas.** O livro-caixa de cutover ganhou índices
     de NAVEGAÇÃO (`CHAVE_CICLO_AVALIACOES`) e as telas passaram a abrir a
     avaliação nova pelo painel soberano.
- **Estado — CORREÇÕES PÓS-AUDITORIA GPT (rodada 2, FINAL):**
  1. **Descoberta SOBERANA (localStorage é opcional).** A prova de existência vem
     do SERVIDOR: `resolverLeituraAvaliacao` (`origemAvaliacaoTela.ts`) consulta a
     fronteira confiável para qualquer id candidato e só usa o acervo local quando
     o servidor responde `NOT_FOUND` (o código público do erro é exposto em
     `ResultadoCutover.codigo` para essa distinção — sem inspeção de texto).
     Consequências: `localStorage` apagado, outro navegador/dispositivo,
     livro-caixa ausente/corrompido e **URL soberana aberta diretamente** não
     escondem uma avaliação real; falha de backend/indeterminação é fail-closed e
     nunca vira leitura local silenciosa; `NOT_FOUND` e negação permanecem
     indistinguíveis (sem vazar existência cross-tenant).
     No SQL, ausência de ocorrência vigente do ator no painel passou a devolver
     `NULL` (resultado "sem painel") em vez de exceção, permitindo distinguir
     "não existe/não acessível" de "falha real".
  2. **Índices de navegação ISOLADOS por organização.** `chaveAnoCiclo` e
     `chaveCicloColaborador` passaram a incluir `organizationId`
     (`org|ano-ciclo`), e `registrarAvaliacoesDoCiclo`/`lerAvaliacoesDoCiclo`/
     `lerAvaliacaoNovaDoColaboradorNoCiclo`/`esquecerAvaliacaoNovaDoColaboradorNoCiclo`
     recebem a organização. Mesma matrícula/ano/ciclo em orgs diferentes não
     colide; trocar de organização ativa não reutiliza índice alheio. A
     organização ali é apenas NAMESPACE DE CACHE — não é prova de tenant nem
     autorização (toda operação revalida server-side).
  3. **Preflight de duplicidade validado no servidor.** `NovoFeedbackPage` não
     bloqueia mais só pelo cache: confirma a existência na fronteira confiável e,
     se a entrada estiver obsoleta, esquece o cache e segue com a criação
     legítima. A autoridade da unicidade continua sendo o índice único parcial do
     banco, e nada é criado localmente.
- **Estado — CORREÇÕES DA AUDITORIA GPT-5.6 TERRA (rodada 3, FINAL):**
  1. **BLOCKER 1 — assinatura de `evaluation_resolver_ciclo`.** A Edge enviava
     `p_matricula_avaliado`, argumento que NUNCA existiu na RPC; com PostgREST a
     divergência quebra a chamada e impedia toda criação nova. A Edge passou a
     enviar EXATAMENTE a assinatura real:
     `evaluation_resolver_ciclo(p_organization_id uuid, p_ano integer,
     p_numero integer, p_actor_user_profile_id uuid) returns uuid`.
     A matrícula continua sendo INTENÇÃO resolvida pela ponte F3-01 **antes** do
     Policy Engine (para o alvo autorizável) e não trafega de novo. Nenhum
     overload foi criado. Teste novo `avaliacoesContratoRpc.test.ts` lê o código
     real da Edge e falha se algum argumento voltar a divergir do contrato.
  2. **BLOCKER 2 — IDOR em `participant_id`.** As RPCs `evaluation_gravar_notas`
     e `evaluation_gravar_comentario` aceitavam `p_participant_id` do chamador e
     só validavam que a ocorrência pertencia à avaliação e estava vigente: um ator
     autorizado podia forjar o id da ocorrência de TERCEIRO. Agora a ocorrência
     editável é derivada SOBERANAMENTE do ator, por
     `evaluation_ocorrencia_do_ator(organization_id, evaluation_id, actor)`:
     `auth.uid()` → perfil → membership ativa no tenant do RECURSO → vínculo
     F5-02 → ocorrência VIGENTE pertencente a ele. **`participant_id` foi
     REMOVIDO do contrato externo** (Edge, `core.ts`, `contrato.ts`, repositório,
     controlador e serviço) e a validação de forma RECUSA o campo
     (`INVALID_INPUT`); as assinaturas antigas foram dropadas. Defesas em
     profundidade nas RPCs: ator revalidado, tenant do recurso revalidado,
     ocorrência vinculada ao ator, vigência respeitada e fail-closed em ausência
     **ou ambiguidade** (duas ocorrências vigentes ⇒ recusa).
     O `painel_participante` continua devolvendo SOMENTE a ocorrência própria
     (usada como catálogo/identidade da tela) e D20 permanece intacta.
- **Telas que ainda leem SOMENTE o legado (justificativa):**
  - `CiclosAvaliacaoPage`/`PainelCicloPage`/`relatorioService`: o painel é
    montado pelo domínio de **ciclos**, que ainda vive em `localStorage`
    (migração de ciclos é outra atividade — D15). Enquanto o ciclo não existir no
    banco, não há avaliação nova daquele ciclo a listar; quando existir, o índice
    de navegação é o caminho. Nenhuma autoridade local é exercida.
  - `ColaboradorDetalhePage`: lista o histórico administrativo do acervo legado;
    a avaliação nova é alcançável pelo índice/painel. Adotar a leitura soberana
    nessa listagem é aditivo.
- **Pendências/limitações conhecidas (não bloqueiam o critério de conclusão):**
  1. **Gravação de ciclo (entidade `evaluation_cycles`) é de outra atividade**
     (D15). Sem o ciclo correspondente no banco, `evaluation.criar` é recusado e
     a tela reporta quantas avaliações ficaram **bloqueadas** (nunca cria local).
  2. **Remoção de nota**: `evaluation_gravar_notas` aceita notas `1..5`; limpar
     uma nota já gravada não a apaga (não há API de exclusão). O valor anterior
     permanece — alteração de contrato exigiria nova `Q#`.
  3. **Listagem administrativa do legado** (item acima) permanece legado.
  4. **Descoberta de id fora da URL**: sem estado local, o produto alcança a
     avaliação pela URL/painel; uma listagem soberana "por ciclo/colaborador"
     (Edge + Policy Engine) é evolução aditiva e depende da migração de ciclos.
  5. **Ator com duas ocorrências vigentes** na mesma avaliação (ex.: o mesmo
     colaborador como responsável direto E membro do colegiado) é recusado por
     ambiguidade (fail-closed, coberto pelo validador). O cenário sintético
     encerra a ocorrência redundante para exercitar o fluxo positivo. Resolver a
     escrita nesse caso exigiria papel explícito na intenção ⇒ nova `Q#`.
- **Validação da F5-06 (todo exit 0):** `npm test` (84 arquivos,
  1069 testes), `npm run build`, `npm run lint`, `git diff --check`;
  validadores SQL no Supabase local — `01-cenario-f5-06.sql`,
  `02-validar-f5-06.sql` (25 PASS), `03-validar-f5-06-cutover.sql` (13 PASS,
  incluindo os testes negativos de IDOR), `01-cenario-f4-08.sql`,
  `02-validar-f4-08.sql` (56 PASS), `03-validar-f4-08-mutacoes.sql` (8 PASS).
- **Contexto do repositório:** `main` contém F4, F5-01..F5-06 e a DEV-02 já
  integradas (F5-06 em `f540f0f…`, DEV-02 em `e098754…`); o BUG #170 é a atividade
  em curso nesta branch, sem alteração funcional fora da navegação.
- **Próximos passos:** auditoria independente sobre o novo SHA do BUG #170; abrir
  PR quando solicitado; a Issue #170 **não** deve ser fechada por este agente.
  Nenhum agente declara a própria entrega aprovada (`.ai/workflow.md` §6.3,
  item 8).
