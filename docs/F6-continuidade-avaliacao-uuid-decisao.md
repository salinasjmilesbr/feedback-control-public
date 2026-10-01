# F6 — Continuidade soberana da avaliação por UUID: decisão de descoberta

> Decisão arquitetural FECHADA pelo responsável nesta atividade. Complementa a
> integração F6 de `evaluation.do_colaborador_no_ciclo`; não altera os contratos
> F4/F5 nem o catálogo de capabilities ou bundles.

## D1 — Visibilidade da existência para CREATE

A existência de uma avaliação **não cancelada** para o mesmo colaborador e ciclo
não é confidencial perante um ator com `evaluation.create` validamente autorizado
para esse alvo pelo Policy Engine. A mera revelação desse bit não é finding de
existence disclosure. `CREATE` não concede `evaluationId`, status, conteúdo,
notas, participantes, leitura ou edição. Ciclo e colaborador devem pertencer ao
tenant ativo do ator, revalidados no servidor; erro e ambiguidade falham fechado.

| Estado e autorização | Resposta da descoberta | Ficha |
| --- | --- | --- |
| Ausente (ou só cancelada) + CREATE | 200: `evaluationId:null`, `status:null`, `podeEditar:false` | Nova avaliação |
| Existente + WRITE | 200: UUID/status reais; `podeEditar:true` apenas em RASCUNHO ou PRONTA_PARA_FEEDBACK | Editar nesses estados; consultar em CONCLUIDA |
| Existente + READ, sem WRITE | 200: UUID/status reais; `podeEditar:false` | Consultar avaliação |
| Existente + somente CREATE | 200: `existeSemAcesso:true`, `podeEditar:false`; **sem chaves** `evaluationId` e `status` | Estado neutro, sem link |
| Nenhuma autorização | 403 genérico | Nenhuma ação |
| Cross-tenant, erro ou ambiguidade | Recusa genérica, sem dados da avaliação | Nenhuma ação |

A consulta interna com `service_role` pode localizar a avaliação para avaliar
READ/WRITE; somente a projeção pública define o limite de informação. A ordem é:
validar identidade/membership/tenant/ciclo; localizar de forma cardinalmente
estrita; avaliar CREATE contra colaborador e WRITE/READ contra a avaliação
localizada; projetar conteúdo apenas com WRITE/READ, existência somente com
CREATE, ou DENY. A criação real revalida autorização e unicidade no banco.

Testes de regressão devem verificar o JSON HTTP **completo** do ramo CREATE-only:
o UUID, o status e qualquer dado da avaliação estão ausentes; o estado da ficha
não contém link. Também devem cobrir ausência, cancelada, READ, WRITE,
cross-tenant, erro e ambiguidade.
