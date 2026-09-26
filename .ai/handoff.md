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

- **Base vigente:** `main` em `b3399488e9413aa995055f91658509a6a1c94019` no início da
  Issue #371.
- **Próxima atividade funcional:** Issue **#364**, validação funcional integrada
  da Etapa 6 com a fotografia Acme; não repetir certificações F4/F5.
- **#365:** histórico individual projeta eventos de reporting pela ocupação
  subordinada e resolve o ocupante gestor pela fronteira temporal do evento;
  PR/CI permanecem conforme estado do GitHub.
- **#366:** contrato estrutural por data civil UTC, normalização server-side e
  conflito para segunda transição da mesma relação/data; migration aditiva.
- **#369:** preflight estático de migrations antes do `db reset` existente no
  job `supabase-local`; fixtures comportamentais cobrem versão duplicada e nome
  inválido. Não há job pesado novo.
- **Ambiente conhecido:** Docker/Supabase local pode estar indisponível no host;
  isso não prova indisponibilidade do runtime compartilhado nem defeito do
  produto.

## 3. Protocolo de retomada e entrega

1. Confirmar `git status -sb`, `git log --oneline -3`, branch, base e
   sincronização com `origin`.
2. Confirmar Issue, PR, desenho fechado e dependências; registrar qualquer
   blocker antes de ampliar escopo.
3. Implementar em branch própria, preservando mudanças do usuário e sem merge.
4. Validar proporcionalmente ao risco e registrar os quatro estados padronizados:
   Static tests, SQL execution, Build, Diff-check.
5. Atualizar este arquivo ao final, mantendo apenas estado operacional vigente;
   mover fatos encerrados para o histórico referenciado abaixo.
6. Fazer commit/push conforme `.ai/workflow.md` e `.ai/git-rules.md`; não
   declarar aprovação própria nem abrir PR sem mecanismo autorizado.

## 4. Histórico e rastreabilidade

- Decisões e evolução da Etapa 6: `docs/plano-mestre.md` e Issues/PRs #293,
  #310, #327, #333, #337, #338, #344, #351/#353, #355, #357/#358, #359, #360,
  #362, #364, #365, #366, #369 e #371.
- Contratos F3/F4/F5: desenhos técnicos correspondentes em `docs/` e regras
  permanentes em `.ai/architecture-rules.md`.
- Dúvidas técnicas abertas: `docs/dividas-tecnicas.md`.
- O Plano Mestre é história, roadmap e manual; este arquivo é somente o estado
  operacional de retomada. Em divergência, prevalece a fonte normativa do
  desenho/`.ai/*`, com a divergência registrada no Plano Mestre.
