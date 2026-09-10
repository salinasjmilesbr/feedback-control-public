# Virtus — Regras de arquitetura e trust boundaries (permanentes)

> Regras permanentes herdadas dos contratos fechados F4-01…F4-10 e F5-01…F5-03.
> Nenhuma implementação pode violá-las; mudança só por nova `Q#` com evidência
> técnica (`.ai/workflow.md`). Sem segredos ou dados sensíveis neste arquivo.

## 1. Trust boundaries (fronteiras de confiança)

1. `auth.uid()` é a **raiz soberana** de identidade; perfil/membership ativos
   derivados no servidor.
2. **Tenant sempre validado server-side** contra a membership ativa; o
   `organization_id` vindo do cliente é apenas **intenção**, nunca autoridade.
3. Frontend, JWT, `localStorage`, payloads e estado React **não concedem
   autoridade** — nada que vem do cliente aumenta roles/capabilities.
4. **Fail-closed**: na dúvida, na ausência de evidência ou em erro, o acesso é
   **negado**.
5. **Cross-tenant = DENY**; identificadores de outra organização são rejeitados.
6. **Policy Engine é o gate soberano** da autorização na camada de aplicação.
7. `authorize()` é **enforcement**; `can()` serve **somente à UX**; ocultar
   elemento na interface **não é** autorização efetiva.
8. **RLS é barreira de segurança** (última barreira quando há tabela): tabelas
   nascem com `ENABLE RLS`, tenant ownership explícito e policy pronta antes de
   conceder acesso (F4-08). Sem FORCE RLS genérico; `SECURITY DEFINER` somente
   com necessidade explícita e grants restritos (service_role).

## 2. Modelo de autorização (não reescrever)

- **Capability = ação; scope = alcance.** Role → capability → (capability ×
  scope). Sem role/capability informada pelo cliente.
- Role é a única via de concessão de capabilities; múltiplas roles por membership
  = união; **nenhuma autorização runtime por cargo/job_role/função**.
- Origem **A** (membership → role → capability) e origens independentes **B**
  (substituição temporária), **C** (acesso excepcional) e **D** (Pilot Full
  Access, dev-only) permanecem separadas no Policy Engine (F4-05/06/07).
- **ADMIN não é superuser de conteúdo confidencial**; ADMIN sem vínculo de
  colaborador não ganha escopos estruturais.
- Plano funcional (roles concedem capabilities funcionais) é distinto do plano
  administrativo de controle (gestão de acesso, C/D) — sem self-escalation.

## 3. Regras de implementação

- Não duplicar regras de autorização em páginas ou componentes: use a policy e
  as capabilities centrais em `src/authorization`.
- Preservar a separação entre autorização, workflow, cálculos, persistência e
  auditoria.
- Preservar históricos e trilhas de auditoria; mutações de privilégio são
  rastreáveis (append-only/equivalente) com autoria soberana.
- Preservar compatibilidade com dados antigos persistidos em `localStorage`.
- Notas sempre com uma casa decimal, reutilizando os formatadores existentes.
- Preferir APIs públicas e padrões já adotados pelo projeto; evitar refactors
  oportunistas e mudanças fora do escopo da Issue.

## 4. Proibições permanentes

- Gravar PAT, tokens, senhas, API keys, chaves privadas ou credenciais em
  código, fixtures, testes, documentação, commits, PRs ou nestes arquivos `.ai/`.
- Incluir dados pessoais ou corporativos reais (usar somente dados fictícios).
- Reduzir controles de segurança (RLS, grants, fail-closed) para facilitar
  entrega ou push.
- Tratar ocultação de interface como autorização.
- Reabrir decisão fechada sem evidência técnica nova (`.ai/workflow.md`).
