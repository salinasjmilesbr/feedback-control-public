# Virtus — Handoff operacional

Registro curto para retomada entre agentes. O GitHub é a fonte de verdade para
Issues, PRs e estado das branches; decisões arquiteturais vivem nos desenhos e
em `.ai/*`, não são duplicadas aqui.

## 1. Regras vigentes

- Antes de agir: ler `AGENTS.md`, `.ai/*` na ordem normativa, a Issue/PR e o
  desenho técnico aplicável.
- Preservar `auth.uid()` como raiz de identidade, tenant validado no servidor,
  Policy Engine, RLS, fail-closed, ALLOW/DENY e isolamento entre tenants.
- Autoridade estrutural permanece no PostgreSQL: posição, ocupação, reporting
  line e eventos soberanos; identidade estrutural é UUID. Não inferir autoridade
  por nome, cargo ou matrícula.
- Migrations/RPC/RLS/SQL exigem execução SQL real quando PostgreSQL/Supabase
  estiver disponível. Teste textual ou static contract não prova SQL executável.
  Se indisponível, declarar `SQL execution: NOT AVAILABLE`.
- Toda entrega Codex separa explicitamente: `Static tests`, `SQL execution`,
  `Build` e `Diff-check`.
- Não resetar runtime compartilhado, não alterar dados reais, não enviar
  convites/memberships e não editar migrations históricas; correções entram em
  migrations aditivas.
- Esta regra permanece válida para próximas etapas/conversas até substituição
  formal.

## 2. Estado atual

> **Checkpoint de infraestrutura (runner descartável — modo CandidateWorktree):**
> worktree `feedback-control/node_modules/.infra-cw`, branch
> `feat/f6-runner-candidate-worktree`, base `origin/main` em
> `15b2f26b338c8698f2457c1195297c14154df06d`. Adiciona `-CandidateWorktree`
> (opt-in com `-Interactive`, exclusivo com `-TargetCommit`) para certificar
> worktree **não commitado** com `src/**` e `supabase/**`, inclusive migrations
> novas: baseline de `origin/main`, inventário Git NUL-safe, cópia dos bytes
> finais sem tocar index/staging, verificação integral + manifesto + fingerprint
> antes de Docker/Supabase, migrations históricas imutáveis, `#404` obrigatória e
> `#414` proibida. Auditoria independente: PASS — apto para versionamento.
> **Pendência registrada (não bloqueante):** M1 — a captura NUL-safe passa pelo
> pipeline de texto do PowerShell, então nomes de arquivo não-ASCII (ou com
> quebra de linha) podem ser mal-decodificados e produzir certificação
> incompleta; não afeta o repo atual (paths ASCII).
>
> **Checkpoint documental de Avaliações (Incremento 0):** worktree isolado
> `feedback-control-docs-avaliacoes-i0`, branch
> `docs/f6-avaliacoes-contrato-soberano-i0`, base `origin/main` em
> `d7c3191b1de33be0d13afa1507fc7b8ce518d29a`. A revisão normativa
> proposta está em `docs/F6-avaliacoes-contrato-soberano-revisao.md`;
> **sem código, commit, push ou PR** nesta etapa. Os incrementos 1–4 e a
> retomada funcional da #421 dependem da revisão/integração do desenho.
> A árvore original da #421 e `auditoria-v21.txt` não foram transportados.

- **Baseline local deste checkpoint:** `main` / `origin/main` em
  `d7c3191b1de33be0d13afa1507fc7b8ce518d29a`; o CI desse SHA não foi
  verificado nesta atividade documental.
- **Etapa 6:** #364, #404, #410, #412 e #413 concluídas; #413 merged. #293 e #310 permanecem abertas.
  F6-COLAB-03 e F6-A18 são itens planejados sem Issue própria identificada.
- **#414:** adiada por decisão de produto, fora do escopo imediato; Issue fechada como adiada e PR #415 fechado
  sem merge. R3-09 continua pendente na #310. Não retomar implementação nem considerar cardinalidade 1–4 entregue
  sem nova decisão explícita.
- **Próxima atividade operacional recomendada:** #293/F6-A15, consultando o estado vigente dos findings UX; depois
  reavaliar a sequência F6-COLAB-03/F6-A18 e o fechamento da Etapa 6. A #310 permanece aberta para os requisitos
  R3-09 ainda não concluídos.
- **Supabase local persistente:** há evidência registrada de migrations #414 `20261019000000` a
  `20261025000000` aplicadas; `20261026000000` não aplicada. O estado Supabase cloud é desconhecido. Não presumir que
  o banco local corresponde à `main` e não executar rollback/reset destrutivo sem diagnóstico/autorização próprios.
- **Working tree no checkpoint:** limpo em `main` no baseline acima. A branch #414 tinha uma edição não publicada em
  `supabase/validacao/01-cenario-f5-08.sql`; ela não deve ser publicada nem incorporada automaticamente. Confirmar
  `git status` ao retomar.

## 3. Protocolo de retomada e entrega

1. Confirmar `git status -sb`, `git log --oneline -3`, branch, base e
   sincronização com `origin`.
2. Confirmar Issue, PR, desenho fechado e dependências; registrar qualquer
   blocker antes de ampliar escopo.
3. Diagnosticar antes de implementar quando a causa não estiver provada. Para
   falha observável em runtime, provar primeiro o comportamento real. Distinguir
   defeito de produto, estado transitório de runtime e problema de ambiente;
   após falha inesperada, diagnosticar antes de iniciar novo ciclo `fix → push →
   CI`.
4. Implementar em branch própria, preservando mudanças do usuário e sem merge.
   Antes de editar, fazer reverse search obrigatório dos consumidores,
   invariantes, catálogos e listas fechadas afetados. Antes dos gates, registrar
   o mapa `mudança → mecanismos afetados → gates normativos correspondentes`.
5. Executar somente validações proporcionais ao risco e impacto. O preflight
   local deve espelhar os gates relevantes do CI, incluindo lint quando
   aplicável; TypeScript de produção exige build antes do commit. Mudança de
   runtime/Edge exige smoke real quando o defeito só puder aparecer em
   execução. Mudança técnica/cutover não autoriza regressão da UX aprovada;
   remoção ou degradação funcional/visual exige escopo ou decisão explícita.
   Para novas funções/RPCs com `pg_advisory_xact_lock`, verificar o catálogo de
   família/chave e executar o gate P6-6.
6. Aplicar esta matriz: documentação = coerência + Diff-check; desenho sem
   runtime = revisão de contrato/arquitetura + Diff-check; frontend/TS = testes
   dirigidos e build/lint quando aplicável; migration/RPC/RLS/SQL = preflight,
   testes dirigidos e SQL real quando disponível; segurança/autorização/tenant
   = provas ALLOW/DENY/negativas e banco quando aplicável; mudança
   transversal/crítica = gates ampliados conforme o risco. Reutilizar evidências
   válidas quando nenhuma mudança relevante as invalidou. CI é confirmação final,
   não mecanismo de descoberta.
7. Para mudanças transversais, auditar antes do push. Em auditorias pre-commit
   grandes, gerar pacote temporário `audit-<issue>.md` ou `.txt` fora do
   repositório; mudanças pequenas podem entregar o diff diretamente. Registrar,
   quando aplicável, `Static tests`, `SQL execution`, `Build` e `Diff-check`.
8. Atualizar este arquivo ao final, mantendo apenas estado operacional vigente;
   mover fatos encerrados para o histórico referenciado abaixo.
9. Fazer commit/push conforme `.ai/workflow.md` e `.ai/git-rules.md`; não
   declarar aprovação própria nem abrir PR sem mecanismo autorizado.

## 4. Histórico e rastreabilidade

- Decisões e evolução da Etapa 6: `docs/plano-mestre.md` e Issues/PRs #293,
  #310, #327, #333, #337, #338, #344, #351/#353, #355, #357/#358, #359, #360,
  #362, #364, #365, #366, #369, #371, #404, #410, #412/#413 e #414/#415.
- Contratos F3/F4/F5: desenhos técnicos correspondentes em `docs/` e regras
  permanentes em `.ai/architecture-rules.md`.
- Dúvidas técnicas abertas: `docs/dividas-tecnicas.md`.
- O Plano Mestre é história, roadmap e manual; este arquivo é somente o estado
  operacional de retomada. Em divergência, prevalece a fonte normativa do
  desenho/`.ai/*`, com a divergência registrada no Plano Mestre.
