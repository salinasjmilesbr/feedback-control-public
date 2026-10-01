# F6 — Revisão do contrato soberano de Avaliações (Incremento 0)

> **Estado:** FECHADO quanto às decisões funcionais; formalização documental para
> revisão independente e integração em `main` antes dos incrementos de código.
> **Base:** `origin/main` em `d7c3191b1de33be0d13afa1507fc7b8ce518d29a`.
> **Motivo:** auditoria arquitetural da jornada UUID anterior à retomada da #421.
> Esta revisão emenda F5-06 e F6-AVALIACOES-05 apenas nos pontos indicados;
> não declara que o runtime atual já cumpra o novo contrato.

## 1. Precedência, evidência e invariantes

As decisões R1–R9 abaixo prevalecem sobre trechos conflitantes de
`F5-06-desenho-tecnico.md` (especialmente D8, D14, D18–D20 e §7/§9) e de
`F6-AVALIACOES-05-desenho-tecnico.md` (D4/D8). O restante desses contratos
permanece vigente. Não há mudança de capability, scope, bundle, `role_type`,
ponderação oficial, identidade ou autoridade de tenant. Implementação futura
usa migrations aditivas; não edita migrations históricas.

O F5-06 §5.1 e D17, desde o desenho original (`1fef718`), estabelecem
`GESTAO_CADEIA` = **gerente funcional**, responsável pela raiz estrutural da
cadeia, e `GESTAO_DIRETA` = **coordenador direto funcional**, gestor formal
direto. A migration F5-06 (`f540f0f`) materializa a raiz como CADEIA e o
gestor direto como DIRETA somente se distinto da raiz. São relações do snapshot
vigente ao ciclo, nunca inferências de cargo, `funcao`, nome ou matrícula.

## 2. Decisões fechadas

### R1 — Participantes e escrita

Gerente (`GESTAO_CADEIA`) obrigatório, coordenador (`GESTAO_DIRETA`) opcional
e colegiado (`COLEGIADO`) opcional com 0..N membros. Só ocorrências
materializadas e vigentes participam. Cada participante altera apenas suas
próprias notas, e o servidor deriva a ocorrência do ator autenticado. Apenas
gerente/coordenador têm comentários por critério e Feedback Final; cada um
edita somente os próprios. Colegiado não comenta nem altera status.

### R2 — Leitura coletiva dos participantes

Todo avaliador participante vê, em RASCUNHO, PRONTA_PARA_FEEDBACK e CONCLUIDA,
identidades e papéis dos demais, progresso/pendências por ocorrência, todas as
notas individuais já preenchidas (inclusive cada colegiado), comentários por
critério e Feedbacks Finais existentes. A projeção server-side é específica
para participantes. Seu ALLOW exige **simultaneamente**: (a) ator autenticado,
membership ativa e tenant da avaliação; (b) ao menos uma ocorrência do ator
materializada e vigente nessa avaliação, resolvida no servidor; e (c) decisão
do Policy Engine sobre o alvo avaliação, com relação/scope válidos, por **um**
dos entitlements existentes: `evaluation.write` nos scopes de F6-AVALIACOES-05
D4 (`DESCENDANTS`, `DIRECT_REPORTS` ou `ASSIGNED`, conforme o papel), **ou**
`evaluation.read + ASSIGNED`. Este segundo caminho atende o participante com
papel `evaluator` de #306, que possui somente `evaluation.read + ASSIGNED`;
`evaluation.read` isolado, SELF, scope administrativo ou acesso excepcional sem
ASSIGNED não basta. Mesmo com capability e scope válidos, leitor administrativo
ou excepcional sem ocorrência vigente, ex-participante e ator cross-tenant
recebem DENY. Ambiguidade de identidade/vínculo ou erro de resolução gera
DENY; múltiplas ocorrências vigentes legítimas do mesmo ator, em papéis
distintos, não são ambiguidade para esta leitura.

A operação de leitura coletiva usa probe de domínio **próprio**, derivado no
servidor e aplicado no Policy Engine, que admite RASCUNHO,
PRONTA_PARA_FEEDBACK e CONCLUIDA para os entitlements acima. No caminho
`evaluation.write`, a concessão comprova elegibilidade para esta **leitura**;
o probe atual de mutação, que nega `evaluation.write` em CONCLUIDA, permanece
obrigatório para qualquer escrita. A Edge/RPC revalidam operação, tenant e
ocorrência antes de devolver a projeção, sem confiar em papel/ID do payload.
O avaliado SELF usa exclusivamente sua projeção após CONCLUIDA. Nenhum bundle,
scope ou capability é ampliado por esta regra.

### R3 — Transparência do colaborador (emenda F5-06 D20)

Antes de CONCLUIDA, o avaliado não recebe resultado, status nem conteúdo da
avaliação por `evaluation.transparencia`, `evaluation.ler`, descoberta ou outra
rota `evaluation.read/SELF`. Após CONCLUIDA, uma projeção server-side própria
entrega notas individuais, comentários por critério e Feedback Final do
gerente e do coordenador materializado, além de agregados oficiais. Do
colegiado entrega somente a parcela agregada, inclusive quando N=1: nenhum
voto individual, identidade/`participant_id`/ocorrência correlacionados ao
voto. A aceitação do agregado N=1 é decisão explícita de produto; não se
suprime nem altera a média por causa da cardinalidade. Coordenador/colegiado
ausentes não viram zero.

Esta decisão substitui **somente** a proibição geral de notas individuais do
avaliado em D20. Preserva a proibição de votos individuais do colegiado, a
janela pós-conclusão e a necessidade de projeção/RLS server-side. A lista
histórica de membros do colegiado não integra a projeção de resultados do
colaborador quando puder correlacionar identidade e agregado N=1.

### R4 — Máquina de estados e autores (emenda F5-06 D8/D18; F6 D4)

Fluxo normal obrigatório:

`RASCUNHO → PRONTA_PARA_FEEDBACK → CONCLUIDA`.

Somente gerente ou coordenador **com ocorrência vigente**, capability
`evaluation.write`, scope/relação/tenant válidos e pré-condições do estado
podem promover ou concluir. Colegiado nunca muda status. Não há salto normal
RASCUNHO→CONCLUIDA. PRONTA significa preenchimento completo, pronto para
comunicação e ainda invisível ao avaliado. CONCLUIDA registra feedback
comunicado/finalizado e abre transparência. CONCLUIDA permanece imutável no
fluxo normal; reabertura/cancelamento excepcionais mantêm capabilities,
motivos e auditoria próprios.

### R5 — Completude por ocorrência (emenda F5-06 D18/D19)

Promover RASCUNHO→PRONTA exige **todas** as notas obrigatórias de **cada**
ocorrência materializada e vigente em **todos** os subcritérios obrigatórios
do catálogo congelado, Feedback Final do gerente e do coordenador quando
presente. Comentários por critério são opcionais e não contam. Com N=0 não há
pendência colegiada; com N=1/N>1, cada membro tem pendências próprias. Nota
de outro membro do mesmo papel não satisfaz a ocorrência pendente; ausência
de voto não vira zero. A conclusão revalida a mesma completude na transação.
Fechamento de ciclo com avaliação incompleta conserva a exceção de D18: não
converte automaticamente a avaliação em CONCLUIDA.

### R6 — Edição em PRONTA e regressão atômica

Participantes podem continuar editando o que lhes pertence em PRONTA. Toda
**alteração efetiva** de nota ou Feedback Final grava o novo valor e regressa
PRONTA→RASCUNHO na mesma transação, com evento e recálculo oficial pertinente;
falha reverte todos os efeitos. Alteração de comentário opcional por critério
mantém PRONTA. Reenvio idêntico não é alteração efetiva nem gera regressão.

### R7 — Autorização e projeções sem legado

`auth.uid()` → perfil/membership ativos → tenant → capability → alvo/scope/
relação/estado no Policy Engine; RPC revalida invariantes antes de usar
`service_role`. Não se amplia bundle, nem se usa `can()`/UI como enforcement.
O cliente não escolhe a ocorrência editável e não calcula completude,
transição, duplicidade ou nota oficial. RLS/grants seguem fechados; nada de
`localStorage`, `feedbackStorage` ou matrícula como autoridade. O contrato
CREATE-only de F6 permanece: existência de avaliação não cancelada pode ser
informada, mas sem ID, status ou conteúdo.

### R8 — Concorrência, idempotência e trilha

Promoção, conclusão, regressão e escrita bloqueiam/validam a avaliação e a
versão esperada na mesma transação, com ordem de bloqueio coerente com
realinhamento de participantes. Pendências são reavaliadas no estado bloqueado.
Requisição obsoleta/repetida recebe conflito determinístico sem segundo evento
ou efeito; não se promete replay de sucesso sem chave persistida. Eventos
append-only registram ator soberano, ocorrência/entidade e delta estruturado;
status e evento são atômicos. Eventos/constraint precisam representar
promoção e regressão. Histórico e cálculo F5-06 D23–D26 permanecem intactos.

### R9 — Dependência da #421

A #421 é reconciliação de UX e explicitamente exclui backend/RPC/contrato.
Sua UI não pode suprir estas regras no cliente. Ela só retoma a jornada
funcional completa após integração do desenho em `main`, implementação e
validação dos incrementos 1–3. O incremento 4 adapta repository/service/UI aos
novos DTOs, preservando o trabalho visual já realizado na branch própria.

## 3. Matriz ator × informação × status

| Ator/informação ou ação | RASCUNHO | PRONTA_PARA_FEEDBACK | CONCLUIDA |
| --- | --- | --- | --- |
| Participante: identidades, papéis, progresso e pendências de todos | Ler | Ler | Ler |
| Participante: notas individuais de todos, inclusive colegiados | Ler | Ler | Ler |
| Participante: comentários e Feedbacks Finais existentes | Ler | Ler | Ler |
| Participante: próprias notas | Editar | Editar; mudança efetiva regride | Somente ler |
| Gerente/coordenador: próprios comentários por critério | Editar | Editar; não regride | Somente ler |
| Gerente/coordenador: próprio Feedback Final | Editar | Editar; mudança efetiva regride | Somente ler |
| Colegiado: comentários, Feedback Final ou status | Negado | Negado | Negado |
| Gerente/coordenador: transição normal | Promover se completo | Concluir se completo | Negado |
| Avaliado: status, resultados e conteúdo por SELF | Negado | Negado | Projeção própria |
| Avaliado: individuais do gerente/coordenador | Negado | Negado | Ler |
| Avaliado: colegiado | Negado | Negado | Somente agregado, inclusive N=1 |

Todos os `Ler`/`Editar` da matriz pressupõem autorização e relação materializada
server-side. `CONCLUIDA` não concede escrita por si; qualquer DENY/erro,
ambiguidade ou cross-tenant falha fechado.

## 4. Contratos de payload e camadas

- **Participante:** catálogo congelado, status/versão, participantes vigentes
  identificados, notas individuais existentes e pendências por ocorrência,
  comentários/Feedback Final dos papéis que os possuem. A ocorrência própria
  pode ser identificada para renderização; não concede escrita por payload.
- **Avaliado:** somente após CONCLUIDA, resultados gerais, bloco individual do
  gerente e do coordenador quando houver, cada qual com notas, comentários e
  Feedback Final; agregado colegiado separado por subcritério, sem voto/ID
  correlacionável. Não reutilizar o DTO do participante.
- **Mutação:** RPC aditiva de promoção, conclusão restrita a PRONTA, pendências
  por ocorrência, escrita de comentário restrita a CADEIA/DIRETA e regressão
  transacional em escrita de nota/Feedback Final. Edge/repository declaram
  operações e DTOs distintos; Policy Engine aplica relação/estado sem grant
  novo; UI apenas consome.

## 5. Incrementos e gates

| Incremento | Entrega | Gates obrigatórios além dos gerais |
| --- | --- | --- |
| 1 — leituras | Fechar bypass SELF pré-CONCLUIDA; projeções separadas | HTTP/payload ALLOW/DENY por ator/status, IDOR/tenant, ausência recursiva de votos colegiados na projeção SELF, SQL real |
| 2 — escrita/completude | Comentários só CADEIA/DIRETA; pendências por ocorrência | Coordenador 0/1, colegiado 0/1/N, cada ocorrência incompleta, escrita alheia DENY, catálogo congelado, SQL real |
| 3 — estados/concorrência | Promoção, conclusão sem salto, regressão, eventos e versão | Corridas escrita×transição/realinhamento, retry/conflito, rollback, trilha, SQL real e smoke Edge |
| 4 — consumo UUID | DTOs/repository/service/UI para #421 e consulta SELF | Testes de retomada/mode/status, build/lint, homologação visual e E2E descartável autorizado |

Cada incremento de implementação usa branch própria, migration aditiva quando
necessária, testes dirigidos, `npm test`, `npm run build`, `npm run lint`,
`git diff --check`, CI no SHA e auditoria independente. SQL real é obrigatório
para mudanças de banco quando disponível; não resetar runtime compartilhado.
Incremento 0 é apenas documentação: revisão de coerência/escopo e diff-check.

## 6. Rastreabilidade e preservações

| Fonte anterior | Estado nesta revisão |
| --- | --- |
| F5-06 D8 | Emendada por R4/R6; sequência obrigatória e regressão atômica |
| F5-06 D14 | Preservada a proteção server-side do colegiado; a lista de membros não integra o resultado SELF quando correlacionável ao agregado N=1 |
| F5-06 D18 | Emendada por R4/R5; completude por ocorrência e atores de transição; exceção de fechamento preservada |
| F5-06 D19 | Precisada por R5; voto ausente não é zero, mas membro materializado tem pendência individual |
| F5-06 D20/§9 | Emendada por R3; indivíduos da gestão após conclusão, colegiado só agregado |
| F6-AVALIACOES-05 D4/D8 | Precisadas por R2/R4/R7; leitura coletiva distinta da escrita, sem ampliar capabilities |
| F5-06 D1/D2/D6/D9–D13/D15–D17/D21–D27; F6 D1–D3/D5–D7 | Preservadas salvo texto dependente expressamente emendado acima |

As divergências são motivadas pela auditoria do runtime: painel atual contém
somente `minhas_notas`/`meus_comentarios`; transparência atual oculta também
individuais da gestão; `evaluation_concluir` aceita RASCUNHO diretamente;
pendências atuais são por papel, não por ocorrência. Esta documentação não
afirma correção operacional desses fatos. Contratos históricos permanecem
consultáveis para rastreabilidade; as emendas deste documento são a fonte
normativa futura para os pontos conflitantes após integração em `main`.
