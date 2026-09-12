# F5-09 — Dúvidas: registro de RATIFICAÇÃO (zero dúvida bloqueante)

> **Status desta rodada:** **ZERO dúvida bloqueante conhecida para iniciar P1.**
> As três dúvidas abertas na primeira rodada de desenho foram **RATIFICADAS** pela
> auditoria GPT do desenho.
>
> - **Desenho auditado:** commit `ae517ff578026f156a6ddc2e94c7cca2d23c6f17`
>   (`docs(F5-09): fechar desenho técnico de ciclos soberanos`), branch
>   `docs/f5-09-ciclos-soberanos`, base `main` =
>   `6550c81d14a9d3e61b3c1b4f49471948f880bbc8`.
> - **Data da ratificação:** **2026-09-12** (rodada de revisão exclusivamente
>   documental, sem implementação).
> - **Efeito:** decisões finais incorporadas ao contrato
>   `docs/F5-09-desenho-tecnico.md` (D8/D9, D15, D16/D17, D26, D27, D28, §7, §8,
>   §10–§16, §18, §19 = P1–P9, §20) e **nenhuma** fase permanece bloqueada.
> - **Nenhuma dúvida nova** surgiu na revisão transversal (§5).

## 1. Quadro de ratificação

| Dúvida | Alternativa escolhida | Decisão final (resumo) | Decisões do contrato | Desbloqueia |
| --- | --- | --- | --- | --- |
| **Q-F5-09-1** — ciclo `PLANEJADO`: cancelar × excluir fisicamente | **A** | `PLANEJADO→CANCELADO` permitido; `CANCELADO` terminal; `DELETE` físico proibido em todos os estados | **D8**, **D9** | P4 (T5) e P6 (`domainState` de `cycle.cancel`) |
| **Q-F5-09-2** — estrutura do ciclo (congelamento × rematerialização) | **Regra híbrida** (parte A + parte B) | população inicial materializada na ativação; admissões posteriores elegíveis **aditivas**; snapshots existentes imutáveis; movimentações **sem** rematerialização | **D16**, **D17**, **D26**, **D27** | P2 (materialização) e P3 (inclusão aditiva) |
| **Q-F5-09-3** — quem recebe `cycle.manage` em produção | **A** | `cycle.manage` entra aditivamente no bundle `admin`; `cycle.cancel`/`cycle.reopen`/`cycle.period.correct` permanecem fora do bundle | **D28** | P7 (habilitação de produção) e P8 (cutover) |

## 2. Q-F5-09-1 — RATIFICADA (alternativa A)

**Contexto original.** O cliente permite **exclusão física** de ciclo `PLANEJADO`
(`excluirCiclo`) e cancelamento apenas de ciclo `ATIVO`
(`persistirCancelamentoCicloAuditadoInterno`); o catálogo F5-04 descreve
`cycle.cancel` como "Cancelar ciclo ATIVO" e o `authorizationPolicy.ts` codifica
`domainState = status === "ATIVO"`. Não existia RPC de ciclo.

**Decisão final ratificada.**

1. `PLANEJADO → CANCELADO` é **permitido**, mediante: capability `cycle.cancel`;
   motivo **obrigatório**; autoria **soberana** (`auth.uid()` + membership, nunca
   do cliente); trilha **append-only** (`cycle_events`); `expected_version`;
   idempotência (`operation_id` + `payload_hash`).
2. `CANCELADO` é **terminal** (reativação proibida).
3. **Exclusão física** (`DELETE`) de `evaluation_cycles` é **proibida em todos os
   estados**, para todos os papéis de aplicação.

**Implementação derivada (P4 e P6).** Ampliar, de forma aditiva, o `domainState`
de `cycle.cancel` para `{PLANEJADO, ATIVO}` em
`src/authorization/authorizationPolicy.ts` e atualizar **aditivamente** a descrição
da capability no catálogo (`cycle.cancel`: "Cancelar ciclo ATIVO" → "Cancelar ciclo
PLANEJADO ou ATIVO (fluxo excepcional auditável)") — sem remoção física de
capability (F5-04 D14) e **sem capability nova**. O fluxo local `excluirCiclo` é
substituído pelo cancelamento, com efeito de UX equivalente (ciclos `CANCELADO` já
são filtrados por padrão).

## 3. Q-F5-09-2 — RATIFICADA com regra híbrida

**Contexto original.** A estrutura por ciclo já existe e é soberana (snapshot
F3-08, responsabilidades F3-09, congelamento de participantes F5-06), mas não
estava decidido o comportamento quando a organização muda **depois** da ativação
(admissão, movimentação de posição, troca de gestor, mudança de colegiado).

**Decisão final ratificada — não é congelamento absoluto puro, nem
rematerialização genérica.**

- **A) Colaborador já presente no ciclo.** A estrutura aplicável a ele fica
  **congelada** naquele ciclo. Mudanças posteriores de posição, unidade, gestor,
  reporting line ou colegiado **não** rematerializam sua estrutura no ciclo
  corrente: a nova estrutura vale **no próximo ciclo**. Os mecanismos
  excepcionais **já contratados** de sucessão (F3-09) e realinhamento de
  participante (F5-06) continuam existindo quando aplicáveis, mas **não**
  equivalem a recalcular o snapshot inteiro.
- **B) Nova admissão após a ativação.** O colaborador admitido **depois** da
  ativação **pode** ser incluído no ciclo corrente, por operação **explícita,
  soberana, server-side, auditada, exclusivamente ADITIVA**, baseada no
  **`collaborator_id` UUID** e na estrutura soberana vigente **no momento da
  inclusão**, incapaz de sobrescrever ou recalcular snapshots existentes.
- **Proibição de uso genérico.** A operação **não** pode ser usada como mecanismo
  de "atualizar estrutura do ciclo": serve apenas para incorporar colaborador
  elegível que não participava do ciclo por ter sido admitido após a ativação.
- **Prova soberana obrigatória (não confiar em flag do cliente).** A condição é
  provada server-side com os dados temporais já existentes (§7.2 do desenho):
  evento append-only `collaborator_events.event_type = 'ADMISSAO'` com
  `cycle_scope = 'CICLO_ATUAL_E_POSTERIORES'` e
  `effective_date > evaluation_cycles.data_ativacao`; **ausência** de período de
  status anterior à ativação em `collaborator_status_periods`; colaborador ainda
  **não** materializado no ciclo; elegibilidade vigente na data da inclusão. A
  coluna `collaborators.admission_date` é **dado declarado de cadastro** (F5-07
  D3/D6) e **não** é prova.
- **Requisito técnico (não flexibilização).** Se a infraestrutura atual não
  permitir provar server-side que se trata de nova admissão após a ativação (por
  exemplo colaborador importado sem evento `ADMISSAO`), a operação **recusa**
  (fail-closed). A correção pertence ao caminho de importação/legado (gravar o
  evento soberano), em atividade própria — a prova **não** é afrouxada e a
  operação **não** é usada para corrigir materialização indevida.

**Implementação derivada (P3).** Operação nomeada pela semântica restrita — Edge
`cycle.admissao.incluir`, RPC `ciclo_incluir_admissao`, helper read-only
`ciclo_admissao_pos_ativacao_elegivel` —, com contrato que impede por construção:
atualização de participante já materializado, mudança de posição, recálculo de
gestor, recálculo de colegiado existente, sobrescrita de snapshot, inclusão
cross-tenant e inclusão sem comprovação soberana. Capability **reusada**:
`cycle.manage` (compatível com o catálogo existente); **nenhuma** capability nova.
O desenho **não** define nenhuma operação genérica de "rematerializar estrutura".

## 4. Q-F5-09-3 — RATIFICADA (alternativa A)

**Contexto original.** As capabilities de ciclo existem no catálogo
(F4-01/F5-04), mas nenhuma role de sistema as concedia: o bundle `admin` contém
apenas `cycle.read`. Sem configuração, o cutover publicaria um produto no qual
ninguém cria/ativa/encerra ciclo.

**Decisão final ratificada.**

1. `cycle.manage` entra **aditivamente** no bundle `admin`
   (`access_role_capabilities`), por migration de reconciliação no padrão
   `20260910000000_f5_04_catalog_reconciliation.sql` — executada na fase **P7**,
   com validador SQL confirmando o bundle.
2. `cycle.cancel`, `cycle.reopen` e `cycle.period.correct` permanecem **fora** do
   bundle `admin`, concedíveis apenas por **configuração explícita de role**
   (capabilities excepcionais, coerente com a descrição do catálogo F5-04).
3. **Nenhuma capability nova.**

## 5. Dúvidas novas

**Nenhuma.** A revisão transversal do desenho (máquina de estados, estrutura e
snapshot, autorização, contrato Edge/RPC, concorrência, auditoria, cutover,
testes, riscos, D1–D28, P1–P9 e DoD) **não** identificou nova dúvida bloqueante.
As regras ratificadas são aplicáveis com os objetos temporais **já existentes** da
F5-07 (`collaborator_events`, `collaborator_status_periods`) e da F3-08
(`collegiate_cycle_snapshots` + `materializar_colegiado_ciclo`), sem alterar
contrato fechado de outra atividade e sem criar privilégio novo (verificado:
`service_role` mantém privilégios completos de tabela pela F4-08 §1 e o `EXECUTE`
da RPC da F3-08 já é concedido a `service_role`).

## 6. Itens que a ratificação converteu em requisito técnico (não são dúvidas)

| # | Requisito | Onde vive no contrato |
| --- | --- | --- |
| RT1 | Ausência de prova soberana de admissão ⇒ **recusa** (fail-closed), inclusive para colaborador legado/importado sem evento `ADMISSAO` | §7.2 (P7) do desenho |
| RT2 | O caminho de importação/legado que precise habilitar inclusão aditiva deve gravar o evento soberano — atividade própria, nunca relaxando a prova | §7.2, R15 |
| RT3 | Nenhuma operação genérica de rematerialização de estrutura existe no contrato | §7.3, §13.1 regra 9, D26 |
| RT4 | Snapshots existentes são imutáveis; a operação só insere e só para o `collaborator_id` solicitado | §7.3, I18, casos A3/A4/A11 |
| RT5 | `cycle.manage` no bundle `admin` é pré-requisito de produção do cutover | D28, P7, R9 |
