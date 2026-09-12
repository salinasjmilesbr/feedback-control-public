# F5-08 P6 — papel/elegibilidade sem estrutura local (blocker da auditoria **resolvido**)

> **Status:** **RESOLVIDO no P6.** Este arquivo **não** registra mais uma "dúvida para a
> F5-09": o contrato F5-08 §19.1 é fechado e passou a ser cumprido no cutover. O que
> permanece para a F5-09 é apenas o **domínio de ciclos/metas** (persistência e o produtor da
> projeção), **sem** autoridade estrutural local.
>
> Referenciado por `src/authorization/cutoverEstrutural.test.ts`.

## 1. O blocker (auditoria GPT)

A rodada anterior do P6 havia registrado como "decisão futura da F5-09" o uso de estrutura
local em três caminhos produtivos:

| Caminho | O que decidia por estrutura local |
| --- | --- |
| `progressoAvaliacao.ts` | papéis exigidos da avaliação (gerente/coordenador/colegiado) por `funcao` textual + cadeia `gestorDiretoMatricula` |
| `cicloEquipeService.ts` | elegibilidade para abrir avaliação, alcance do painel do ciclo e papéis por `funcao` + cadeia local |
| `metaStorage.ts` | "quem aprova quem" (coordenador direto/gerente responsável) por `funcao` + cadeia local, e autorização com o **mundo local sintético** como provider |

Isso conflita com `docs/F5-08-desenho-tecnico.md` §19.1: `funcao` textual **não** decide
hierarquia, e `localWorld` existe "apenas para DEV/teste, atrás do gate de modo DEV já
existente; **nunca** em produção". Decisão da auditoria: **não** é escopo de F5-09; o P6 não
podia ser considerado concluído com esses caminhos decidindo papel/elegibilidade localmente.

## 2. Solução adotada (reuso, sem fonte nova)

Nenhum mecanismo novo foi criado (sem migration, RPC, Edge operation, capability, allowlist ou
porta). A correção introduz **uma fronteira** entre a estrutura e essas decisões:

**`src/services/projecaoEstruturalSoberana.ts`** (novo módulo de fronteira):

- `VinculoEstruturalSoberano` / `ProjecaoEstruturalSoberana`: fatos estruturais **já
  resolvidos** na origem (papel, gestor direto, cadeia, colegiado, aplicabilidade da estrutura
  de avaliação). Os fatos soberanos têm nomes PRÓPRIOS (`gestorSoberanoMatricula`,
  `colegiadoSoberanoMatriculas`), distintos dos campos do cadastro local;
- `resolverProjecaoEstrutural(explicita, mundoLocalDev)`: a projeção **explícita (soberana)
  sempre vence**; só o contexto DEV do Vite (`simulacaoDevPermitida`) pode cair na fixture
  local; fora dele devolve `PROJECAO_ESTRUTURAL_VAZIA` (**fail-closed**);
- `projecaoDeFixtureLocal`: **único** ponto do caminho de ciclo/metas onde `funcao` textual e
  `gestorDiretoMatricula` local podem virar papel/cadeia — e só atrás do gate de DEV;
- consultas soberanas usadas pelos consumidores: `vinculoEstrutural`, `gestorSoberano`,
  `papelDoGestorDireto`, `temPapelNaCadeia`, `raizDaCadeiaSoberana`,
  `usaEstruturaAvaliacaoSoberana`, `avaliadoresColegiadoSoberanos`, `alcanceSoberano`;
- `ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL`: mensagem única da barreira.

**Consumidores convertidos** (nenhum deles lê mais `funcao`, `gestorDiretoMatricula`,
`avaliadoresColegiadoMatriculas` nem `getColaboradoresVisiveis`):

| Arquivo | Mudança |
| --- | --- |
| `src/services/progressoAvaliacao.ts` | papéis vêm da projeção; sem evidência ⇒ `completo: false` + pendência explícita (nunca "completo" por dado local) |
| `src/services/cicloEquipeService.ts` | elegibilidade, alcance do painel e papéis vêm da projeção; sem evidência ⇒ `criarAvaliacoesDoCicloAtivado` **recusa** e o painel fica vazio; pendências ganham o papel `Estrutura` |
| `src/services/metaStorage.ts` | "quem aprova quem" e "exige coordenador" vêm da projeção; sem evidência ⇒ ninguém aprova e a aprovação do coordenador é exigida |
| `src/services/permissaoAvaliacao.ts` | permissões de avaliação (gerente/coordenador/colegiado) vêm da projeção; sem evidência ⇒ `podeAvaliar: false` |
| `src/pages/MinhaAvaliacaoDetalhePage.tsx` | seções de papel e identificação dos avaliadores vêm da projeção (antes: `funcao` + cadeia local) |
| `src/authorization/providers/localWorld.ts` | `criarProvidersMundoLocal` passa a ser **DEV-only**: fora do gate devolve o mundo soberano VAZIO (`criarProvidersMundoFuncional({ actor, colaboradores: [] })`) ⇒ nenhuma capability ⇒ DENY |
| `src/pages/CiclosAvaliacaoPage.tsx` | exibe a pendência de `Estrutura` (fail-closed) no encerramento do ciclo |

## 3. Comportamento fail-closed (sem evidência soberana)

| Decisão | Antes (local) | Agora (produção) |
| --- | --- | --- |
| Papéis exigidos da avaliação | derivados de `funcao`/cadeia | `necessario: false` **e** `completo: false` com pendência de estrutura |
| Abrir avaliações na ativação do ciclo | lista derivada do cadastro local | **recusa** (`ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL`), nada é criado |
| Alcance do painel do ciclo | `getColaboradoresVisiveis` local | **vazio** (nenhuma linha exibida) |
| Pendências do encerramento | lista local | pendência `Estrutura` (nunca "tudo completo") |
| Aprovar meta | relação local | `podeAprovarMetaNoCiclo` = `false`; `metaExigeAprovacaoCoordenador` = `true`; `metaEstaAprovada` = `false` |
| Mutação de meta própria | provider do mundo local sintético | `authorize()` nega (mundo vazio), nada é gravado |
| Permissões de avaliação | papéis por `funcao`/cadeia local | `podeAvaliar: false`, `papeisPermitidos: []` |

Sentido do fail-closed: **não conceder**. Sempre que a estrutura não puder ser provada, a
resposta é a negativa (não aplicável/sem alcance/negado/exige aprovação) — nunca um fallback
local.

## 4. Provas

- `src/services/cutoverEstruturalServicos.test.ts` (novo, 8 testes): produção × DEV; inclui
  projeções **contraditórias** ao cadastro local (prova que a decisão segue o soberano, não o
  `funcao`), recusa de criação de avaliações sem evidência, ausência de escrita local e DEV
  preservado atrás do gate.
- `src/authorization/estruturaUiSeguranca.test.ts` (bloco novo, 4 testes): guarda estática que
  **detecta a reintrodução** dos caminhos (campos estruturais locais proibidos nos quatro
  módulos; `funcaoUsaEstruturaAvaliacaoAnalista` só no adaptador de fixture; `localWorld` só
  sob o gate DEV; sem `.rpc(`/`functions.invoke`/`service_role`).
- `src/authorization/cutoverEstrutural.test.ts`: política/mundo funcional fail-closed (P6).
- SQL: `supabase/validacao/03-validar-f5-08-cutover.sql` (inalterado nesta correção — não há
  superfície de banco nova).

## 5. O que permanece para a F5-09 (sem autoridade estrutural local)

1. **Persistência do domínio de ciclos/metas** continua em `localStorage` (legado) — o P6 não
   migra persistência (§19.2/§21.3).
2. **Produtor da projeção soberana**: ligar a leitura RLS/portas do P4/P5 (posições, ocupações,
   reporting lines, colegiado) ao `resolverProjecaoEstrutural(projecao, …)` das telas, de modo
   que a decisão deixe de ser fail-closed. A regra "qual cargo/posição ⇒ qual papel" pertence
   ao domínio (não é inventada aqui e não existe no contrato da F5-08).
3. **Aptidão por status** (`getAplicabilidadeNoCiclo`, snapshot F3-08 local) permanece como
   leitura de **estreitamento**: ela só pode EXCLUIR alguém de um conjunto já derivado da
   projeção soberana; nunca concede papel, alcance ou hierarquia. Migrá-la para
   `collaborator_status_periods` soberano é evolução do mesmo domínio.

## 6. Residual declarado (fora deste blocker, não silencioso)

Estes caminhos ainda leem campos estruturais locais e **não** estão entre os três módulos do
blocker; ficam registrados para não serem esquecidos:

| Arquivo | Uso local | Observação |
| --- | --- | --- |
| `src/services/relatorioService.ts:84,154-157,195` | filtros/alcance de relatório por `gestorDiretoMatricula` | domínio de relatórios; não concede papel de avaliação/aprovação |
| `src/services/exportarAvaliacaoPdf.ts:49-73` | identificação de gestor/colegiado no PDF | exibição documental |
| `src/services/visibilidadeColaboradores.ts` | alcance por cadeia/colegiado | único consumidor de produção restante é `authorizationPolicy.scopeCollaborators` (sem chamador de produção; usado por testes) |
| `src/services/historicoOrganizacionalStorage.ts` | snapshots/efetivos do ciclo | leitura legada de exibição + aptidão (item 5.3), sem autoridade de papel |

Tratar esses pontos exige atividade própria (relatórios/PDF) e não foi feito aqui para não
ampliar o escopo do blocker.
