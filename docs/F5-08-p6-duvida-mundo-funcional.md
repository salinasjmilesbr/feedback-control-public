# F5-08 P6 — estrutura soberana por UUID no caminho de ciclo/metas

> **Status:** **blockers da auditoria RESOLVIDOS** (identidade UUID e produtor
> conectado). Este arquivo **não** transfere mais nada do cutover estrutural para
> a F5-09: a F5-09 continua responsável **apenas** pelo domínio de ciclos
> (persistência e estrutura por ciclo), nunca por "ligar o produtor" da F5-08.
>
> Referenciado por `src/authorization/cutoverEstrutural.test.ts`.

## 1. Os dois blockers (auditoria GPT)

| # | Blocker | Correção |
| --- | --- | --- |
| 1 | A projeção estrutural era indexada por **matrícula** (`gestorSoberanoMatricula`, `cadeiaDeGestaoMatriculas`, `colegiadoSoberanoMatriculas`), violando §19.3 ("nenhuma matrícula como identidade funcional") e a F5-07 (identidade canônica = UUID) | O **modelo** passou a ser UUID-first (`collaboratorId`, `gestorSoberanoPositionId`, `cadeiaDeGestaoPositionIds`, `cadeiaDeGestaoCollaboratorIds`, `colegiadoSoberanoCollaboratorIds`) e **não conhece matrícula**. A matrícula vive apenas na **ponte de compatibilidade** da fronteira |
| 2 | O produtor soberano existia como interface, mas **ninguém o alimentava** em produção: sem parâmetro manual ⇒ projeção vazia ⇒ DENY geral ("ligar na F5-09") | O produtor passou a carregar a estrutura pelo **caminho normal já existente** (leitura RLS do P4 + porta de colaboradores F5-07) e é acionado pelo **shell autenticado**; os consumidores leem a projeção publicada, sem injeção manual |

## 2. Solução adotada (reuso integral; nenhuma fonte nova)

### 2.1 Modelo estrutural — `src/services/projecaoEstruturalSoberana.ts`

ADAPTADOR de leitura sobre a fotografia soberana do P4. Fontes (todas já
existentes): `organizational_positions`, `occupations` vigentes,
`position_reporting_lines` vigentes e `collegiate_configurations` + membros.

A hierarquia é percorrida **por posições** (reporting lines) e cada elo é
resolvido no **ocupante** da posição (UUID). O modelo não conhece texto, cargo,
nome, função nem matrícula: o que existem são **fatos relacionais** —

- `temCadeiaDeGestaoSoberana` — há responsável resolvido acima (antes: "existe
  GERENTE na cadeia" por `funcao`);
- `gestorSoberanoTemSuperior` — o gestor direto é **nível intermediário**
  (antes: `gestor.funcao === "COORDENADOR"`);
- `raizDaCadeiaSoberana` — "gerente responsável" = **raiz da cadeia** (F4-09
  D2/D3, já era relacional);
- `colegiadoSoberano` — membros da configuração **vigente** (UUID).

Vigência: meio-aberto `[validFrom, validTo)` com referência injetável
(`vigenteNaReferencia`, com teste de equivalência a `estaVigente` do P4).
Inconsistência (duas vigências simultâneas, ciclo de reporting, posição de gestor
vaga, ocupação ausente) ⇒ vínculo **não confiável** ⇒ fail-closed.

> O campo `papel: "GERENTE" | "COORDENADOR" | "OUTRO"` foi **eliminado**: papel
> textual era hierarquia paralela. As regras de domínio passaram a ser
> consequência explícita das relações contratadas (§ acima).

### 2.2 Produtor e ponte — `src/services/estruturaSoberanaCliente.ts`

- **PRODUTOR**: `carregarEstruturaSoberana({ organizationId }, deps)` chama, em
  paralelo, `lerEstrutura` (RLS/own-tenant, D16 — **sem RPC de listagem**) e
  `listarColaboradores` (F5-07, que traz a ponte de matrícula e o gestor
  derivado server-side da ocupação vigente), monta a projeção por UUID e
  **publica** o estado (`ocioso`/`carregando`/`pronta`/`indisponivel`).
- **PONTE de compatibilidade**: `ponteMatriculas` (matrícula → UUID) e
  `matriculaLegada` (UUID → matrícula numérica) permitem que os domínios legados
  que ainda indexam por matrícula (ciclo/meta) alcancem os fatos por UUID. A
  ponte é **fronteira**, não chave: o modelo estrutural permanece UUID-first.
- **FIXTURE de DEV**: `estruturaDeFixtureLocal` converte o mundo local em
  estrutura usando identificadores **de fixture** (`fixture:<matrícula>`),
  atrás do gate `simulacaoDevPermitida` — nem em DEV a matrícula é a chave.
- **Wiring**: `src/pages/useEstruturaSoberanaDoCliente.ts` (hook) é chamado pelo
  shell autenticado (`LayoutFuncional` em `src/routes/AppRoutes.tsx`) com a
  organização ativa do `useAuth()`. Nenhum consumidor precisa injetar nada.

## 3. Identidade: onde a matrícula ainda aparece (e por quê)

| Lugar | Uso | Natureza |
| --- | --- | --- |
| `estruturaSoberanaCliente.ponteMatriculas/matriculaLegada` | tradução matrícula ↔ UUID | **ponte** explícita de compatibilidade |
| `visaoEstruturalLegada` / `alcanceLegado` | devolvem os fatos em matrícula | **view legada** para telas/serviços que ainda indexam por matrícula |
| payloads legados (`feedbackStorage`, `metaStorage`, `votosColegiado[...][matricula]`) | identificação do colaborador | contrato legado do domínio (F5-09/F5-10 migram) |
| `estruturaDeFixtureLocal` | id de fixture derivado da matrícula | DEV/teste, gated, namespaced |
| `historicoOrganizacionalStorage`, `colaboradorStorage` | cadastro local (leitura) | classificação B — só exibição/aptidão |

**Prova de que a matrícula não é identidade estrutural (guarda estática):** o
arquivo do modelo não contém a palavra `matricula` (nem `Matricula`); a ponte só
existe em um módulo; e um consumidor novo que citar `ponteMatriculas` fora da
fronteira reprova o CI (`estruturaUiSeguranca.test.ts`).

**Prova comportamental:** duas pessoas com o mesmo rótulo humano permanecem
distintas na projeção (chaves UUID) e uma matrícula **não numérica** não é
endereçável pelo domínio legado, enquanto o vínculo estrutural continua existindo
por UUID — nenhum fato é inventado.

## 4. Fail-closed (o que continua obrigatório)

| Situação | Resultado |
| --- | --- |
| Supabase/serviço falhou (`lerEstrutura`/`listarColaboradores` com erro) | estado `indisponivel`; decisões NEGATIVAS (nunca `localStorage`/seed) |
| Sem sessão/organização ativa (inclusive **perder** a organização no meio do uso) | contexto INVALIDADO: `indisponivel` (`FORBIDDEN`) com estrutura VAZIA — a do tenant anterior deixa de ser acessível |
| Troca de organização com carga em voo | a estrutura anterior é descartada IMEDIATAMENTE e uma resposta antiga **nunca** publica (§2.3) |
| Colaborador não resolvido (sem ocupação vigente / sem ponte) | vínculo inexistente ⇒ papel/elegibilidade negados |
| Estrutura inconsistente (2 ocupações, ciclo, posição de gestor vaga) | cadeia não confiável ⇒ papéis falsos e ninguém aprova |
| Sem evidência estrutural | `progressoAvaliacao` NUNCA declara completo; painel vazio; pendência `Estrutura`; mutação de meta negada |
| Nada carregado ainda (transiente de boot) | mesma negativa — e o carregamento é automático pelo shell, não uma injeção manual |

### 2.3 Segurança multi-tenant do produtor (corrida A → B)

`carregarEstruturaSoberana` mantém uma **geração monotônica** de solicitações
(`let geracao = 0`) e a **organização vigente** do contexto:

- cada solicitação (ou invalidação) incrementa a geração e registra a organização;
- uma carga captura `minhaGeracao` + `minhaOrganizacaoId` e **só publica** via
  `publicarSeVigente` — isto é, apenas se `minhaGeracao === geracao` **e**
  `organizacaoVigente === minhaOrganizacaoId`. Uma resposta de A que chega depois
  de B é **descartada** (devolve o estado corrente, sem efeito);
- iniciar uma carga publica imediatamente `carregando` com a organização nova e
  estrutura **VAZIA**: a estrutura do tenant anterior deixa de ser acessível no
  mesmo instante da troca;
- a **deduplicação é por organização** (`carregamentoEmCurso.organizacaoId ===
  organizationId` + mesma geração): duas chamadas simultâneas da MESMA
  organização compartilham a promessa; **A e B nunca** são tratadas como a mesma
  solicitação;
- `invalidarEstruturaSoberana()` (usada quando a organização ativa vira
  `null`/`undefined` — seleção removida, logout, unmount do shell) incrementa a
  geração, limpa a carga em curso e publica o estado inválido com estrutura VAZIA.
  É idempotente (não notifica assinantes duas vezes pelo mesmo estado);
- o hook `useEstruturaSoberanaDoCliente` chama a invalidação quando perde a
  organização ativa (antes ele apenas retornava, mantendo a estrutura anterior).

Consequência: **a estrutura publicada sempre corresponde à organização ativa
solicitada**, e nenhuma resposta assíncrona antiga republica estrutura depois que
o contexto que a originou deixou de ser vigente.

## 5. Provas (testes)

| Arquivo | O que prova |
| --- | --- |
| `src/services/projecaoEstruturalSoberana.test.ts` (8) | adaptador por UUID; cadeia por posições/reporting lines; raiz/intermediário; colegiado vigente; equivalência de vigência com o P4; posição vaga, ciclo, ambiguidade e ocupação ausente ⇒ fail-closed |
| `src/services/estruturaSoberanaCliente.test.ts` (15) | carregamento pelas portas existentes (**sem injeção manual**); ciclo/metas/painel/permissões funcionando em produção; soberano vence o cadastro local; falha real ⇒ fail-closed sem `localStorage`; DEV isolado; ponte (matrícula não numérica); **corrida multi-tenant** determinística: A lenta/B rápida e A rápida/B lenta (A nunca publica), dedupe só da mesma organização, A e B nunca deduplicadas, `null` invalida o contexto e carga em voo é descartada |
| `src/services/cutoverEstruturalServicos.test.ts` (4) | consumidores com estrutura soberana explícita: decisões funcionam; soberano vence o local; sem estrutura é fail-closed; DEV preservado |
| `src/authorization/estruturaUiSeguranca.test.ts` (38) | guardas estáticas: modelo sem matrícula; nenhum consumidor lê `funcao`/`gestorDiretoMatricula`/`avaliadoresColegiadoMatriculas`; `funcaoUsaEstruturaAvaliacaoAnalista` sem consumidor produtivo; produtor usa as portas soberanas, é acionado pelo shell e é seguro na troca de tenant (geração + dedupe por org + invalidação); `localWorld` só em DEV; sem RPC/Edge/credencial nova |
| SQL | inalterado: a correção não cria superfície de banco (o validador de cutover do P6 segue no CI) |

## 6. O que permanece para a F5-09 (apenas domínio de ciclos)

1. **Persistência** de ciclos/metas (hoje `localStorage`, §19.2/§21.3).
2. **Estrutura POR CICLO**: a projeção usa a vigência ATUAL das posições/
   ocupações/reporting lines. O snapshot por ciclo (F3-08) e a composição de
   equipe/colegiado por ciclo são do domínio de ciclos (F5-09) — quando existirem
   sovereignemente, basta injetar a fotografia da referência do ciclo na MESMA
   projeção (o adaptador já aceita `referencia`).
3. **Aptidão por status** (`getAplicabilidadeNoCiclo`, snapshot local) segue como
   leitura de **estreitamento**: só EXCLUI de um conjunto já derivado da
   estrutura soberana; nunca concede papel, alcance ou hierarquia.

## 7. Residual declarado (fora deste blocker, não silencioso)

| Arquivo | Uso local | Observação |
| --- | --- | --- |
| `src/services/relatorioService.ts` | filtros/alcance de relatório por `gestorDiretoMatricula` | domínio de relatórios; não concede papel de avaliação/aprovação |
| `src/services/exportarAvaliacaoPdf.ts` | identificação de gestor/colegiado no PDF | exibição documental |
| `src/services/visibilidadeColaboradores.ts` | alcance por cadeia/colegiado | único consumidor de produção restante é `authorizationPolicy.scopeCollaborators` (sem chamador de produção) |
| `src/services/historicoOrganizacionalStorage.ts` | snapshots/efetivos do ciclo | leitura legada de exibição + aptidão (item 6.3) |

Tratar esses pontos exige atividade própria (relatórios/PDF).
