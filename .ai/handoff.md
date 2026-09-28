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
- **#365 e #366:** concluídas/integradas; permanecem vigentes o histórico de
  reporting por posição/ocupação temporal e o contrato estrutural por data
  civil UTC.
- **#369:** concluída/integrada; o preflight de migrations permanece no job
  `supabase-local`, antes do `db reset` existente.
- **#371:** atividade documental atual.
- **Após #371:** a próxima atividade funcional continua sendo a Issue **#364**,
  validação integrada da Etapa 6 com a fotografia Acme; não repetir F4/F5.
- **Ambiente conhecido:** Docker/Supabase local pode estar indisponível no host;
  isso não prova indisponibilidade do runtime compartilhado nem defeito do
  produto.

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
  #362, #364, #365, #366, #369 e #371.
- Contratos F3/F4/F5: desenhos técnicos correspondentes em `docs/` e regras
  permanentes em `.ai/architecture-rules.md`.
- Dúvidas técnicas abertas: `docs/dividas-tecnicas.md`.
- O Plano Mestre é história, roadmap e manual; este arquivo é somente o estado
  operacional de retomada. Em divergência, prevalece a fonte normativa do
  desenho/`.ai/*`, com a divergência registrada no Plano Mestre.
