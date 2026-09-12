# Virtus — Contexto persistente

> Contexto **estável** e de longa duração do projeto, para reduzir prompts
> repetitivos e inconsistência entre agentes (DeepSeek Flash, DeepSeek Pro,
> Codex/GPT e outros). Complemento de `AGENTS.md`; não substitui a Issue nem o
> contrato da atividade. Sem segredos, credenciais ou dados sensíveis.

## 1. Identidade do projeto

- **Produto:** Virtus (Vivo Virtus / `feedback-control`) — gestão de avaliações,
  observações, metas e estrutura organizacional.
- **Repositório público (origem):** GitHub `salinasjmilesbr/feedback-control-public`.
- **GitHub é a fonte de verdade** para Issues, requisitos, decisões registradas
  em revisões de PR e histórico de mudanças.

## 2. Stack e infraestrutura

- Frontend: React, TypeScript, Vite, React Router, Vitest, ESLint, jsPDF.
- Persistência/identidade: Supabase (Supabase Auth, Postgres com RLS; stack
  local via Docker); `@supabase/supabase-js`.
- Domínios funcionais legados ainda em `localStorage` (pré-migração F5);
  compatibilidade com dados antigos de `localStorage` é obrigatória **para os
  domínios ainda não migrados** (metas e observações). **Autoridade
  estrutural** (unidades, posições, hierarquia, cargos, senioridades, colegiado,
  ocupação e reporting line), **cadastro de colaboradores** e **avaliações** já são
  soberanos no PostgreSQL (F5-06/F5-07/F5-08): `localStorage` não é fonte de
  verdade, não há dual-write e a leitura do cliente é RLS own-tenant
  (`docs/F5-08-p6-duvida-mundo-funcional.md` registra o residual de elegibilidade
  dos domínios de ciclo/metas). **Ciclos** continuam em `localStorage` **até a
  implementação da F5-09**: o desenho técnico está fechado
  (`docs/F5-09-desenho-tecnico.md`, com dúvidas em `docs/F5-09-duvidas.md`) e
  define `public.evaluation_cycles` (F5-06 D15, já existente) como a entidade
  soberana — nenhuma autoridade local nova foi criada nesta rodada.
- CI (`.github/workflows/ci.yml`): `npm test`, `npm run build`, `npm run lint`,
  `git diff --check` e validação Supabase local (RLS/policies) quando aplicável.

## 3. Fases (roadmap) e contratos

Documentos de desenho por fase em `docs/Fx-XX-desenho-tecnico.md`. O arquivo
`docs/Fx-XX-desenho-tecnico.md` da atividade é o **contrato específico** dela;
não existe contrato sem documento fechado correspondente.

- **F1** — infraestrutura/ambiente (ex.: Supabase local, convenções, GitHub
  Actions). Contratos em `docs/` quando aplicável.
- **F2** — contas, organização e autenticação Supabase.
- **F3** — estrutura organizacional (colaboradores, job roles, unidades,
  posições, ocupações, responsabilidades temporárias, colegiado, sucessão).
  Encerrada e validada (`F3-10`).
- **F4** — autorização e segurança (catálogo de capabilities/roles, scopes,
  Policy Engine, hierarquia, temporárias, acesso excepcional C, Pilot D, RLS
  F4-08, aplicação funcional F4-09, validação integrada F4-10). **Encerrada**
  com matriz de rastreabilidade (`F4-10-matriz-rastreabilidade.md`).
- **F5** — identidade e multiusuário em runtime real: F5-01 (identidade
  autenticada), F5-02 (vínculo usuário↔colaborador), F5-03 (organização ativa),
  F5-04 (access roles/capabilities reais), F5-05, F5-06 (avaliações no PostgreSQL),
  F5-07 (colaboradores e histórico organizacional soberanos) e F5-08 (estrutura e
  catálogos soberanos). F5-09 (ciclos soberanos) tem **desenho técnico fechado**
  (`docs/F5-09-desenho-tecnico.md`, fases P1–P8) e **implementação não iniciada**.
  As atividades seguintes da fase seguem o roadmap do GitHub.
- **F6+** — hardening geral e trabalhos futuros (fora de escopo das fases
  anteriores).
- **DEV-\*** — atividades de **infraestrutura de processo** (ex.: DEV-01, esta
  camada de contexto persistente), sem alteração funcional do produto.

Regras de rastreabilidade de decisões: ver `.ai/workflow.md`.

## 4. Mapa do repositório

| Caminho | Conteúdo |
| --- | --- |
| `AGENTS.md` | Ponto de entrada obrigatório (ordem de leitura) |
| `.ai/` | Contexto persistente e regras de operação dos agentes (esta camada) |
| `docs/` | Contratos de desenho `Fx-XX-desenho-tecnico.md` e matrizes por fase |
| `src/` | Frontend React/TS (inclui `src/auth` e `src/authorization`) |
| `src/authorization/` | Policy Engine central e capabilities (não duplicar fora daqui) |
| `supabase/` | Migrations, validações SQL e seed local (ver `supabase/README.md`) |
| `.github/` | Workflows de CI, Dependabot, template de PR |
| `.env.example` | Exemplo de variáveis de ambiente (nunca valores reais) |

## 5. Regras de uso

- Ao iniciar atividade: leia `AGENTS.md` → `.ai/*` → Issue → contrato `docs/Fx-XX`.
- Ao retomar trabalho interrompido: leia primeiro `.ai/handoff.md`.
- Atualize `.ai/handoff.md` ao final de cada entrega (estado operacional, sem
  dados sensíveis).
- Referencie documentos em vez de copiar conteúdo entre arquivos; mantenha esta
  camada objetiva e sem duplicação excessiva.
