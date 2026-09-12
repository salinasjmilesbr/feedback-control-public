# F5-08 P6 — dúvida arquitetural REAL registrada (mundo funcional do cliente e leituras de elegibilidade)

> **Status:** ABERTA — registrada para decisão em atividade própria (F5-09 e/ou atividade de
> integração do mundo funcional soberano). **Nenhuma decisão nova foi inventada no P6.**
>
> **Por que existe este arquivo:** o enunciado do P6 determina que, se surgir dúvida
> arquitetural real não resolvida pelo contrato F5-08, ela deve ser registrada em `.md` em vez
> de decidida unilateralmente. Este arquivo é essa parada. Ele é citado por
> `src/authorization/cutoverEstrutural.test.ts:21`.

## 1. O que o P6 entregou (fatos verificados)

| Fato | Evidência |
| --- | --- |
| O fallback do Policy Engine funcional para o cadastro legado deixou de existir em produção | `src/authorization/authorizationPolicy.ts:74-83` (único call site de `getColaboradores()`, dentro de `if (simulacaoDevPermitida)`) |
| O mundo funcional não deriva mais bindings de gestão/coordenação/colegiado fora do gate DEV | `src/authorization/mundoFuncional.ts:183,197-199` (`SEM_BINDINGS_DEV`; o fallback `?? derivarBindingsDev(...)` foi removido) |
| `historicoOrganizacionalStorage` deixou de promover texto local (`respondePara`) a relação de gestão | `src/services/historicoOrganizacionalStorage.ts:89-92` |
| A fixture morta de equipe de avaliação foi removida | `src/data/evaluationTeam.ts` (ausente; guarda em `estruturaUiSeguranca.test.ts`) |
| Guardas estáticas e de runtime do cutover | `src/authorization/estruturaUiSeguranca.test.ts` (bloco P6), `src/authorization/cutoverEstrutural.test.ts` |
| Validador SQL de cutover no CI | `supabase/validacao/03-validar-f5-08-cutover.sql`, `.github/workflows/ci.yml` (job `supabase-local`) |

Consequência **intencional e verificada**: fora do contexto DEV do Vite, o mundo/bindings do
cliente passam a vir apenas da projeção soberana (ainda não ligada no cliente). Logo `can()` e
`authorize()` do cliente ficam **fail-closed (DENY)** em produção, e a decisão real permanece
server-side (Policy Engine administrativo/`authorize()` na Edge + RLS). Ver
`cutoverEstrutural.test.ts` (produção ⇒ DENY inclusive com mundo explícito; ALLOW só com binding
explícito, que representa o que a projeção soberana deverá fornecer).

## 2. A dúvida (uma frase)

**O contrato F5-08 §19.1 (`docs/F5-08-desenho-tecnico.md:1024`) exige que as decisões de
elegibilidade/papel hoje tomadas por estrutura LOCAL (`progressoAvaliacao.ts`,
`cicloEquipeService.ts`, `metaStorage.ts`) passem a usar a estrutura soberana — mas o P6 está
proibido de criar funcionalidade estrutural nova (RPC/Edge/porta/UI) e de iniciar F5-09..F5-12,
e o contrato NÃO define qual fonte soberana alimenta essas decisões, nem em qual atividade isso
deve acontecer.**

## 3. Por que o contrato não resolve (evidência)

1. §19.1:1024 manda trocar a **fonte** das decisões de elegibilidade/papel, mas não diz para
   onde: a única leitura soberana de estrutura definida pela F5-08 é **RLS/PostgREST** (`D16`,
   §21.3:1125 — "RPC de leitura administrativa: **não** — leitura é RLS F4-08") + as portas do
   cliente do P4/P5 (`lerEstrutura`, `acessoColaboradoresSoberanos`). Nenhuma delas responde
   "quem avalia quem neste ciclo" / "quais metas este ator enxerga".
2. §21.3:1126 atribui o **snapshot de colegiado por ciclo** à **F5-09**, e §26.3:1322 registra
   que os ciclos são da F5-09 — a composição de equipe/colegiado por ciclo é, portanto, domínio
   futuro, não da F5-08.
3. §27:1337 define o P6 como "remoção da autoridade estrutural local (§19) + CI", com gate
   `03-validar-f5-08-cutover.sql` + regressão F4/F5 — **sem** novo contrato de elegibilidade.
4. O escopo dado ao P6 proíbe: nova migration, nova RPC/Edge, nova capability, nova UI e o
   início de F5-09..F5-12. Qualquer implementação aqui seria **invenção de decisão estrutural**.

## 4. Estado real do legado após o P6 (classificação B do §3 do enunciado)

Nenhum destes caminhos autoriza a **administração de estrutura** (unidades, posições, catálogos,
colegiado, ocupação, reporting line) — essa superfície é soberana e está fechada
(`03-validar-f5-08-cutover.sql` §3/§5). Eles permanecem como **leitura legada de domínios de
ciclo/metas/feedback** (F5-09/F5-10/F5-11) e ainda decidem **elegibilidade/papel** por dados
locais:

| Arquivo | Uso local remanescente | Linhas |
| --- | --- | --- |
| `src/services/progressoAvaliacao.ts` | papel por `funcao` textual e `gestorDiretoMatricula` local | 55-61, 82-96 |
| `src/services/cicloEquipeService.ts` | equipe/elegibilidade por `getColaboradores()` + `funcao` + cadeia local | 6, 119-120, 130, 269-270, 288, 328-338, 454, 500-501 |
| `src/services/metaStorage.ts` | provedores de mundo local (`providers/localWorld`) para metas | 5-6, 11 |
| `src/services/permissaoAvaliacao.ts` | efetividade por histórico local | 5 |
| `src/pages/{PainelCicloPage,MinhasMetasPage,AcompanhamentoMetasPage,NovoFeedbackPage,EditarFeedbackPage,FeedbackDetalhePage,MinhaAvaliacaoDetalhePage,RelatoriosPage}.tsx` | telas que consomem o cadastro local | ver guarda `CAMINHOS_LEGADO_LEITURA` em `estruturaUiSeguranca.test.ts` |
| `src/contexts/UsuarioAtualProvider.tsx` | resolve o usuário atual pelo cadastro local | 3 |
| `src/infrastructure/localStorage/localCollaboratorRepository.ts` | adapter DEV/teste (escrita é barreira) | 2-7 |

Achado adicional (mesmo problema de fronteira, ainda **não** DEV-gated):
`src/services/colaboradorStorage.ts:31-39` devolve a fixture `src/data/colaboradores` quando a
chave local **não existe**, em qualquer ambiente. Hoje isso não alcança autorização estrutural
(o único consumidor no caminho de autorização é DEV-gated, §1), mas alcança os consumidores
legados acima — ou seja, uma fixture de DEV pode virar "dado" de tela em produção.

`src/authorization/providers/localWorld.ts` (`organization_id` sintético,
`isMembershipActive: () => true`) segue atrás do gate de modo DEV conforme §19.1:1022, com
consumidores de produção pinados pela guarda estática: `src/services/metaStorage.ts` e
`src/pages/MinhasMetasPage.tsx`.

## 5. Alternativas (NÃO decididas aqui)

| Alternativa | Descrição | Risco/impacto |
| --- | --- | --- |
| **A. Elegibilidade 100% server-side (F5-09/F5-10)** | O cliente deixa de decidir equipe/elegibilidade: recebe do servidor a lista de alvos (participantes/responsáveis já resolvidos) e apenas exibe | Elimina a classe de risco; exige novas operações server-side (fora do contrato F5-08) |
| **B. Projeção soberana no cliente** | O cliente passa a alimentar `mundoFuncional`/`progressoAvaliacao`/`cicloEquipeService` a partir de leitura RLS (posições/ocupações/reporting lines/colegiado) + portas do P4/P5 | Depende de um novo contrato de projeção (mapeamento estrutura → mundo funcional) e de invalidação correta |
| **C. Manter leitura legada com barreira explícita de DEV (como no P6)** | Os domínios de ciclo/metas/feedback continuam em modo legado, mas com gate DEV + fail-closed em produção (telas sem mundo ⇒ sem dados, nunca dado local antigo) | Mantém dívida aberta; exige decidir o que a UI mostra em produção até F5-09 |

## 6. Onde decidir e o que NÃO fazer

- **Decidir em:** desenho da **F5-09** (ciclos/equipe/colegiado por ciclo) ou em atividade de
  integração explicitamente destinada a isso; se a decisão tocar o contrato F5-08, abrir a `Q#`
  correspondente no desenho daquela atividade (não reabrir D1–D25 deste documento).
- **Não fazer no P6 (feito):** não criar RPC/Edge/porta/UI/migration nova, não alterar allowlist
  nem capabilities, não introduzir estrutura sintética, não promover texto local a hierarquia.
- **Se nenhuma decisão for tomada:** os domínios de ciclo/metas/feedback permanecem com leitura
  local e o cliente permanece fail-closed para o mundo funcional em produção — estado
  **consistente com o cutover** (nenhuma autoridade estrutural local), porém com funcionalidade
  reduzida até a projeção soberana existir.
