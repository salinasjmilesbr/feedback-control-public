# Virtus — Contexto persistente

> Contexto estável e de longa duração. Complementa AGENTS.md; não substitui Issue, desenho fechado nem handoff.

## Identidade
- Virtus (Vivo Virtus / feedback-control): gestão de avaliações, observações, metas e estrutura organizacional.
- Repositório público: GitHub salinasjmilesbr/feedback-control-public. GitHub é a fonte de verdade para Issues, requisitos, decisões de revisão e histórico.

## Stack e fronteiras
- Frontend: React, TypeScript, Vite, React Router, Vitest, ESLint e jsPDF.
- Persistência: Supabase Auth e PostgreSQL com RLS; desenvolvimento local usa Docker.
- auth.uid() é a raiz de identidade; tenant e autorização são validados server-side. Policy Engine é fronteira soberana; authorize() aplica enforcement e can() atende somente à UX.
- RLS é barreira de segurança; tabelas autorizativas têm acesso fechado; autorização é fail-closed e cross-tenant é DENY.
- Frontend, JWT, localStorage e payload não concedem autoridade. Não derive autoridade de nome, cargo ou matrícula.
- Separe autorização, workflow, cálculos, persistência e auditoria; preserve histórico e trilhas de auditoria.
- Não inclua dados pessoais ou corporativos reais em código, fixtures, testes, documentação, commits ou PRs.

## Domínios e contratos
- Estrutura organizacional soberana: unidades, posições, hierarquia, cargos, senioridades, colegiado, ocupações, responsabilidades temporárias e reporting line.
- Um colaborador ocupa no máximo uma posição por data, sem sobreposição temporal; responsabilidades temporárias não são ocupações.
- Avaliações e domínios migrados seguem contratos versionados em docs/ e suas Issues; não presuma dual-write nem autoridade local.
- Domínios ainda legados podem conservar dados em localStorage somente conforme contrato específico; isso não concede autoridade.
- Migrations, RPCs, RLS e contratos SQL exigem execução SQL real quando PostgreSQL/Supabase estiver disponível. Testes estáticos não provam execução SQL.

## Fontes e mapa
- AGENTS.md é o ponto de entrada; .ai/workflow.md define processo; .ai/architecture-rules.md define fronteiras permanentes; desenho fechado docs/Fx-XX é contrato da atividade.
- docs/ contém desenhos/matrizes; src/ contém frontend; src/authorization/ contém Policy Engine; supabase/ contém migrations/validações; .github/ contém CI/templates.
- Estado operacional (Issues em curso, branch, SHA, gates e host) pertence exclusivamente a .ai/handoff.md.
- Ao iniciar, leia AGENTS.md, fontes .ai, Issue e contrato. Ao retomar, leia primeiro .ai/handoff.md. Evite duplicar estado operacional.
