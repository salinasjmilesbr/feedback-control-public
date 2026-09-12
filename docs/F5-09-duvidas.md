# F5-09 — Dúvidas bloqueantes (ratificação necessária)

> **Status:** desenho técnico F5-09 entregue em `docs/F5-09-desenho-tecnico.md`;
> as três dúvidas abaixo **mudam comportamento** e **não estão cobertas** pelos
> contratos F4/F5 vigentes. Cada uma indica exatamente o que fica bloqueado.
> **Nenhuma fase foi iniciada** e nenhuma dessas decisões foi tomada em silêncio:
> o desenho registra a recomendação, e a implementação da parte afetada aguarda
> ratificação.
>
> **Regra de prosseguimento:** as partes independentes do plano (P1, P4, P5
> exceto criação, P6 parcial, P8) podem ser executadas antes da ratificação; as
> partes citadas em "Bloqueia" não.

## Q-F5-09-1 — Ciclo `PLANEJADO`: cancelar ou continuar excluindo fisicamente?

**Contexto.** Hoje o cliente permite **exclusão física** de ciclo `PLANEJADO`
(`excluirCiclo` em `src/services/cicloAvaliacaoStorage.ts`, que exige
`status === "PLANEJADO"`) e permite **cancelamento** apenas de ciclo `ATIVO`
(`persistirCancelamentoCicloAuditadoInterno` exige `ATIVO`). O catálogo F5-04
descreve a capability `cycle.cancel` como "Cancelar ciclo ATIVO (fluxo
excepcional auditavel)" e `src/authorization/authorizationPolicy.ts` codifica
`domainState = status === "ATIVO"`. Não existe RPC de ciclo: o banco nunca
decidiu esse fluxo. O desenho F5-09 propõe `CANCELADO` terminal e proibição de
`DELETE`.

**Alternativas.**

| # | Alternativa | Efeito |
| --- | --- | --- |
| A (recomendada) | `PLANEJADO→CANCELADO` permitido (motivo obrigatório, trilha) e **exclusão física proibida** em qualquer estado; ciclo `PLANEJADO` permanece editável (ano, número, período) | Nada se apaga; o ciclo sai da lista padrão porque `CANCELADO` já é filtrado (`getCiclosAdministrativos(incluirCancelados=false)`); exige ampliar o `domainState` de `cycle.cancel` para `{PLANEJADO, ATIVO}` e atualizar a descrição da capability no catálogo |
| B | Manter `cycle.cancel` só para `ATIVO` e permitir exclusão física de `PLANEJADO` sem avaliações | Mantém o catálogo F5-04 intacto, mas reintroduz `DELETE` em entidade soberana (contra "preserve históricos e trilhas de auditoria" e contra o padrão F5-06/F5-07/F5-08, que não apagam) |
| C | Manter `cycle.cancel` só para `ATIVO` e **proibir** exclusão física, sem transição para `PLANEJADO` | Ciclo planejado criado por engano só pode ser reaproveitado por edição; se as três vagas de `numero` do ano já estiverem ocupadas e o operador quiser "limpar", não há caminho |

**Impacto.** (i) muda quem pode o quê (`cycle.cancel` passa a valer sobre
`PLANEJADO`); (ii) remove uma operação existente do produto (`excluirCiclo`);
(iii) altera uma linha do catálogo de capabilities (`description`, sem remoção
física — F5-04 D14 permite); (iv) define se um ciclo pode desaparecer sem
trilha.

**Recomendação.** Alternativa **A**. Coerente com a proibição de exclusão física
já vigente nos domínios F5-06/F5-07/F5-08, com a exigência de trilha auditável, e
com efeito de UX equivalente (o ciclo cancelado não aparece na lista padrão).

**Decisão necessária.** Ratificar A, B ou C. Se A: autoriza ampliar
`domainState` de `cycle.cancel` e atualizar a descrição da capability.
Se B: a F5-09 mantém `DELETE` restrito a `PLANEJADO` **sem avaliações** e a
trilha registra a exclusão (contrariando I11/I12 do desenho, que precisariam ser
revisados).

**Bloqueia.** P3 (transição T5) e a parte de P6 referente a `cycle.cancel`.

---

## Q-F5-09-2 — Estrutura do ciclo: congelamento absoluto ou rematerialização autorizada?

**Contexto.** A estrutura por ciclo já existe e é soberana: snapshot de colegiado
F3-08 (`collegiate_cycle_snapshots` + `materializar_colegiado_ciclo`, idempotente
e sem sobrescrever linhas existentes), responsabilidades avaliativas F3-09
(temporais, com sucessão) e congelamento de participantes da avaliação pela
F5-06 (`evaluation_snapshot_participantes`, que resolve gestor direto e cadeia no
`reference_date` do ciclo). O que **não** está decidido é o comportamento quando a
organização muda **depois** da ativação: colaborador admitido no meio do ciclo,
movimentação de posição, troca de gestor, mudança de colegiado.

**Alternativas.**

| # | Alternativa | Efeito |
| --- | --- | --- |
| A (recomendada) | **Congelamento absoluto** na ativação: o snapshot do ciclo é imutável; quem ingressa/muda depois entra no próximo ciclo. Avaliações já criadas permanecem íntegras; o overlay F3-09 (sucessão de responsável) continua valendo para avaliações **ainda não criadas** | História nunca reinterpretada; determinístico; exige comunicar ao negócio que admissões no meio do ciclo não são avaliadas nele |
| B | **Rematerialização aditiva autorizada**: nova operação explícita (`cycle.estrutura.rematerializar`, capability `cycle.manage`, motivo obrigatório, trilha) que **insere** snapshots de colaboradores ainda ausentes, sem nunca sobrescrever os existentes | Atende admissões no meio do ciclo; aumenta superfície e exige regra de quem pode, quando e com que limite |
| C | **Estrutura viva**: recalcular o snapshot do ciclo a qualquer momento | Viola "não reinterpretar o passado com a estrutura atual" e reescreveria a base de avaliações já feitas; conflita com o determinismo do `reference_date` da F5-06 |

**Impacto.** Define se a ativação é um marco irreversível de estrutura, se existe
operação adicional na Edge/RPC, se o snapshot do ciclo pode crescer depois e como
o negócio lida com admissão/movimentação no meio do ciclo. Também decide se o
gestor de cadeia (resolvido no `reference_date`) e o responsável avaliativo F3-09
(por vigência) permanecem camadas distintas ou são unificados.

**Recomendação.** Alternativa **A**, com B disponível como evolução aditiva caso o
negócio exija avaliar admissões do ciclo corrente. Ambas preservam a imutabilidade
do passado; C está descartada por contrariar o determinismo já contratado na
F5-06.

**Decisão necessária.** Ratificar A ou B (e, se B, o gatilho, o autorizador e os
limites da rematerialização). Se B: a operação entra no contrato da Edge com
capability `cycle.manage`, motivo obrigatório e evento
`ESTRUTURA_REMATERIALIZADA` na trilha.

**Bloqueia.** A parte de estrutura de P2 (ativação/materialização) e de P3.

---

## Q-F5-09-3 — Quem recebe `cycle.manage` (e as capabilities excepcionais) em produção?

**Contexto.** As capabilities existem no catálogo desde F4-01/F5-04
(`cycle.read`, `cycle.manage`, `cycle.cancel`, `cycle.reopen`,
`cycle.period.correct`, todas `grantable_via_role = true`), mas **nenhuma role de
sistema as concede**: o bundle `admin`
(`20260908000001_authorization_system_catalog.sql`) contém apenas `cycle.read`, e
as três capabilities excepcionais foram criadas depois da formação do bundle. Hoje
a tela de ciclos é acessível a quem tem `cycle.read` (gate de navegação
`cycle.management.view` → alias de `cycle.read`), e o botão de gestão **não** é
verificado contra `cycle.manage`. Depois do cutover, a decisão passa a ser
server-side: sem uma role com `cycle.manage`, **ninguém** cria/ativa/encerra ciclo
em produção.

**Alternativas.**

| # | Alternativa | Efeito |
| --- | --- | --- |
| A (recomendada) | Incluir `cycle.manage` **aditivamente** no bundle `admin` (migration de reconciliação, padrão `20260910000000_f5_04_catalog_reconciliation.sql`); manter `cycle.cancel`, `cycle.reopen` e `cycle.period.correct` fora do bundle, concedíveis apenas por configuração explícita de role | Preserva a intenção do catálogo ("fluxo excepcional auditável") e mantém a operação viável após o cutover |
| B | Não alterar o catálogo: exigir que cada organização conceda `cycle.manage` por role customizada antes do cutover | Zero mudança de catálogo; risco operacional de o cutover publicar um produto onde ninguém consegue ativar ciclo |
| C | Incluir as quatro no bundle `admin` | Operação mais simples, mas transforma fluxos declaradamente excepcionais em default |

**Impacto.** Determina se a F5-09 inclui uma migration de catálogo (aditiva, sem
capability nova) e se o cutover tem pré-requisito de configuração em produção.
Não altera o mapa de gate nem a doutrina de autorização — apenas quem possui a
capability.

**Recomendação.** Alternativa **A**.

**Decisão necessária.** Ratificar A, B ou C e, se A, autorizar a migration de
reconciliação do bundle `admin` no escopo da F5-09.

**Bloqueia.** A viabilidade do cutover (P7) e a publicação da Edge (P5) em
produção; não bloqueia P1–P4 nem P6.
