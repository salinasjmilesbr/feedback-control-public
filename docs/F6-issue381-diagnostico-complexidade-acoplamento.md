# F6 — Diagnóstico de complexidade e acoplamento arquitetural (#381)

## Escopo e conclusão

Diagnóstico somente por leitura do checkout `main` em `deb7cbb`. Nenhum
runtime, schema, migration ou dado foi alterado e nenhuma suíte foi executada.

O custo de mudança observado na #379 é real, mas concentrado: uma alteração de
bundle atravessa vários validadores históricos que repetem o estado corrente do
catálogo. O problema principal é a coexistência de três tipos de fonte:

1. contratos históricos de fase/migration;
2. invariantes correntes reescritas como listas fechadas em gates posteriores;
3. testes/fixtures específicos que usam contagens locais como se fossem
   inventário global.

A recomendação é incremental: manter provas históricas, explicitar seu ponto
temporal e extrair somente inventários correntes compartilháveis. Não há base
para redesign amplo ou reescrita de migrations já aplicadas.

## Mapa de fontes e duplicações

| Domínio | Fonte pretendida | Cópias encontradas | Classificação | Risco/custo |
|---|---|---|---|---|
| Capabilities canônicas | `public.capabilities` + `src/authorization/catalogoCapabilities.ts` | `Capability.ts`, catálogo TS, desenhos F4/F5, validadores F4-01/F5-09/F5-10/F5-11 e guards de migrations | Essencial: DB↔TS exige paridade. Acidental: listas literais repetidas em mensagens e gates | Alto custo de evolução; falso vermelho ou divergência |
| Bundle `admin` | migration/reconciliação do bundle + catálogo DB | `02-validar-f4-01.sql`, migrations F5-11, validadores F5-09/F5-10/F6-A03 e testes TS | Essencial para preservar fronteira administrativa; repetição histórica é parcialmente acidental | Alto risco de alterar autoridade por engano |
| Grants `observation.*` | `access_role_capabilities` e migrations de bundles | listas fechadas em `35`, `37`, `39`, `41`, `43-validar-f5-11-*`, migrations P1/P2/P3/P5.1 e certificação F5-11 | Histórico é essencial no ponto de aplicação; leitura como estado corrente é acidental | Foi o caso #379/#496: grants legítimos pareceram transitórios |
| Role `gestao_equipe` | `20261017000000_f6_issue379_gestao_equipe.sql` | `gestaoEquipeBundle.test.ts`, validadores F5-11, fixture F4-02 com role tenant-local homônima e UI com fallback | Migration/teste são essenciais; homonímia é contextual; fallback técnico é finding UX | Confusão global × tenant-local |
| Scopes | `access_role_assignment_scopes` + Policy Engine/provedores soberanos | `mundoFuncional.ts`, `providers/reais.ts`, páginas/testes, fixtures e validadores | Essencial haver fonte server-side; mundo DEV é adapter explícito, não autoridade | Risco de binding local virar autorização real |
| Advisory locks | contratos das famílias e RPCs | migrations F3/F5/F6, `03-validar-f5-08-cutover.sql`, testes textuais e catálogos P6-6 | Catálogo é essencial; listas paralelas são acidentais | Nova RPC exige manutenção manual e pode falhar CI |
| Temporalidade estrutural | tabelas `organizational_positions`, `occupations`, `position_reporting_lines` e RPCs | resolvers, RPCs, histórico, Policy Engine e testes | Repetição é parcialmente essencial; falta uma fronteira comum | Divergência de fronteiras e reinterpretação histórica |
| Identidade/tenant | `auth.uid()` → profile → membership → vínculo/posição | RLS, Policy Engine, RPCs, Edge Functions, fixtures e gates | Repetição é essencial em cada trust boundary | Uma cópia permissiva cria cross-tenant/IDOR |
| RLS/ACL | migrations F4-08 e estado PostgreSQL | cada migration declara RLS/ACL; validadores repetem inventários | Prova por tabela/fase é essencial; contagem global é frágil | Listas obsoletas ou falsa cobertura |

## Hotspots concretos

### Gates F5-11 como inventário corrente

Os validadores `35`, `37`, `39`, `41` e `43` mantêm listas e contagens de
roles/grants de observação. A #379 adicionou somente quatro relações ao bundle
`gestao_equipe`, mas o impacto atravessou D1/D6/A6 e mensagens de inventário.

Isso é acoplamento acidental quando o bloco pretende provar o estado atual; é
essencial quando prova explicitamente a fronteira histórica de uma fase. Hoje a
distinção depende principalmente de comentários, não do mecanismo.

Evidência: `supabase/validacao/35-validar-f5-11-p1.sql`,
`37-validar-f5-11-p1-1.sql`, `39-validar-f5-11-p2.sql`,
`41-validar-f5-11-p3.sql` e `43-validar-f5-11-p5-1.sql`.

### Migrations com guardas finais repetidas

As migrations F5-11 verificam catálogo `31`, bundle `admin = 9` e listas de
roles. Isso é necessário para impedir aplicação sobre estado incompatível, mas
não deve descrever o inventário final do produto. A autoridade da migration é o
estado no instante de sua aplicação; a autoridade corrente deve ser inventário
corrente separado.

Reescrever migrations históricas para acompanhar bundles futuros violaria a
semântica append-only e dificultaria upgrade incremental.

### Catálogo P6-6 de advisory locks

`supabase/validacao/03-validar-f5-08-cutover.sql` mantém arrays explícitos de
funções por família e chave. O catálogo estrutural inclui RPCs F5-07/F5-08,
`estrutura_ocupacao_trocar` e reporting; ciclos, responsabilidades e acesso
funcional usam famílias distintas.

Isso é essencial e deve permanecer fail-closed: RPC com
`pg_advisory_xact_lock` fora do catálogo precisa falhar. O acoplamento acidental
é manter função e chave em listas separadas, exigindo alteração manual em cada
nova RPC.

Evidência: bloco P6-6 de `03-validar-f5-08-cutover.sql` e migrations
`20260914020000_f5_08_lock_key_alignment.sql`,
`20261015000000_f6_issue375_troca_posicao_atomica.sql` e
`20261016000000_f6_provisionamento_gestores.sql`.

### Temporalidade e reporting

Predicados de vigência aparecem em `organization_resolution`, sucessão,
colegiado/snapshots, RPCs estruturais, histórico organizacional e Policy
Engine. A repetição é aceitável quando a consulta tem semântica própria, mas
deve ser equivalente a `[valid_from, valid_to)`.

O risco maior é usar ocupante atual em vez do ocupante resolvido no instante do
evento, ou aplicar a fronteira direita a `REPORTING_LINE_ENCERRADA`.

Evidência: `20260907170000_organization_resolution.sql`,
`20260907190000_evaluator_responsibility_succession.sql`,
`20260907180000_collegiate_configuration_snapshot.sql`,
`20261014000000_f6_issue365_historico_reporting.sql` e contratos #365/#366.

### Policy Engine local versus soberano

`src/authorization/mundoFuncional.ts` contém arrays de capabilities por gestão,
coordenação e colegiado, com scopes derivados da estrutura local. O módulo
marca isso como DEV/teste; sem binding, o caminho é fail-closed. Produção usa
`contextoAutorizacao.ts`, `providers/reais.ts` e RPCs/Edge Functions.

O binding local é essencial para testes legados e demonstrações, mas acidental
como fonte corrente. A duplicação entre mundo local, `Capability.ts`, catálogo
TS e banco é dívida de migração gradual, não uma autorização paralela válida.

### Identidade, membership, tenant e RLS

Profile ativo, membership ativa, vínculo coerente, organização do alvo e
`auth.uid()` aparecem em RLS, RPCs, Edge Functions, Policy Engine e fixtures
negativas. A repetição é essencial: cada fronteira deve negar
independentemente. Não se deve substituir essas guardas por uma única camada de
aplicação.

## Essencial versus acidental

### Deve permanecer intacto

- `auth.uid()` como raiz soberana;
- tenant, profile, membership e vínculo validados server-side;
- Policy Engine: `authorize()` como enforcement e `can()` somente UX;
- RLS deny-by-default e ACLs fechadas;
- UUIDs estruturais e autoridade posição → posição;
- trilhas append-only, idempotência e payload hashes;
- migrations históricas imutáveis;
- locks separados por família e catálogo P6-6 fail-closed;
- janelas `[valid_from, valid_to)` e fronteiras #365/#366;
- fixtures e gates negativos de ALLOW/DENY e cross-tenant DENY.

### Principal acoplamento acidental

- listas correntes copiadas em gates históricos;
- contagens globais fora do contexto da fase;
- mensagens de PASS que descrevem inventário corrente sem asserção;
- arrays separados de funções e chaves de lock;
- catálogos de capabilities duplicados entre DB, TS, mundo DEV, docs e SQL;
- predicados temporais reescritos sem uma fronteira documentada comum;
- identificadores técnicos exibidos pela UI quando o contrato pede linguagem de
  negócio.

## Recomendações incrementais

1. Separar explicitamente prova de migration, gate histórico e inventário
   corrente. Migrations continuam validando compatibilidade no ponto de
   aplicação; inventário corrente não deve ser inferido desses guards.
2. Manter listas históricas fechadas, rotuladas por fase/versão, e impedir que
   suas mensagens sejam interpretadas como inventário atual.
3. Introduzir uma representação declarativa de contratos de catálogo para
   validar DB↔TS e bundles correntes, começando por `gestao_equipe`.
4. Preservar P6-6 fail-closed, reduzindo a manutenção manual com um registro
   declarativo de família/chave, sem aceitar lock não catalogado.
5. Centralizar somente semântica temporal reutilizável; manter explícita no
   chamador a diferença entre evento iniciado e encerrado. Não criar snapshot
   paralelo.
6. Tratar `mundoFuncional.ts` como adapter DEV/legado e provar que nunca é
   usado como autorização soberana; remover somente após migração dos
   consumidores.
7. Usar na rotina de mudança a matriz `mudança → mecanismo → gate`; nova RPC
   com advisory lock exige P6-6, e novo bundle exige gates de catálogo,
   autorização e tenant.

## Sequência recomendada

1. Usar este mapa como referência da #364, sem alterar contratos F4/F5.
2. Fazer atividade pequena de inventário corrente DB↔TS/bundles, primeiro com
   evidência, sem centralização ampla.
3. Em atividade separada, reduzir manutenção do catálogo P6-6, preservando seu
   fechamento fail-closed e todas as famílias.
4. Só depois avaliar helpers temporais compartilhados, com provas de não
   reinterpretação histórica e regressão #365/#366.
5. Não bloquear a validação funcional #364 nem misturar este diagnóstico com
   provisionamento, redesign de UI ou migração de domínios legados.

## Fora de escopo e riscos

Este documento não autoriza refatoração, alteração de schema, migration,
runtime, RLS, Policy Engine ou gates. Centralização prematura pode remover
provas independentes e aumentar o blast radius de segurança. Toda simplificação
futura deve preservar fail-closed, isolamento de tenant, auditabilidade,
temporalidade soberana e provas históricas.
