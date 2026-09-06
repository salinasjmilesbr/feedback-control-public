# Migrations e padrões do PostgreSQL — F1-02

Entrega documental que define e versiona as convenções que todas as migrations
do Virtus Team devem seguir. Esta fase não cria migration, tabela, schema de
domínio, Auth, RLS, seed, procedure ou transação de negócio: apenas fixa os
padrões técnicos que serão aplicados pela F1-03 (foundation) e pelas fases
seguintes. Nenhuma regra aqui substitui a Especificação v1.0 nem as regras de
negócio, autorização, workflow, persistência e auditoria da aplicação.

## Migrations atuais

| Migration | Propósito |
| --- | --- |
| `20260906185540_foundation.sql` | Foundation técnica (F1-03): helper de trigger `set_updated_at` e padrões documentados de UUID, timestamps e versionamento; sem entidades funcionais. |
| `20260906201856_organizations_user_profiles.sql` | F2-01 (Issue #68): entidades-base de identidade `organizations` e `user_profiles` (perfil interno ligado 1:1 a `auth.users`), timestamps/version conforme F1-02, RLS habilitado e deny-by-default, sem policies nesta etapa. |

## Plataforma e ferramentas

- Banco alvo: PostgreSQL 17 via Supabase (local primeiro, hospedado depois),
  conforme a estrutura local da F1-01.
- CLI Supabase fixada em **2.116.0**, sempre executada via `npx --yes`, sem
  instalação global e sem adicionar dependência ao package.json/lockfile.
- Migrations versionadas em `supabase/migrations/`, no formato de arquivo
  gerado pela CLI (`<timestamp>_<descricao>.sql`). Prefira criar arquivos com o
  comando oficial para manter nomes consistentes e o diff confiável.
- Aplicação local pelo fluxo oficial (`supabase start`/`db reset`/`db diff`);
  aplicação em ambiente remoto somente por fluxo versionado e aprovado. Não há
  vínculo com projeto hospedado nesta fase.

## Regras gerais de migration

- Uma migration por mudança coesa, aditiva e reversível por nova migration.
- Nunca editar uma migration já versionada e aplicada: correções entram como
  novas migrations.
- Migrations devem executar em ordem, tanto em banco vazio quanto sobre banco
  existente, e sobreviver ao fluxo de rebuild local sem depender de estado
  manual.
- Todo arquivo começa com um comentário curto indicando propósito e, quando
  aplicável, a Issue de origem. Sem valores reais, credenciais, tokens, chaves,
  e-mails ou nomes reais de pessoas/empresas em qualquer arquivo SQL.
- Apenas SQL declarativo e mudanças estruturais; sem lógica de negócio,
  procedures transacionais ou seeds nas migrations desta fase.

## Nomes de identificadores

- Identificadores em `lowercase` e `snake_case`, sem aspas desnecessárias e sem
  palavras reservadas do PostgreSQL.
- Tabelas no plural; colunas no singular.
- Nomes técnicos padronizados em inglês: `id`, `created_at`, `updated_at`,
  `version`, `organization_id`.
- Nomes de domínio derivam do termo já usado na aplicação (ex.: o tipo
  `Colaborador` em `src/types`), convertido para `snake_case`; quando o termo
  gerar ambiguidade de plural, o nome canônico da tabela é registrado em
  comentário na própria migration e na decisão técnica da Issue.
- Constraints e índices com prefixo e nome explícitos (exemplos ilustrativos,
  não criam nem antecipam tabelas):

| Tipo | Padrão | Exemplo |
| --- | --- | --- |
| primary key | `pk_<tabela>` | `pk_colaboradores` |
| unique | `uq_<tabela>_<colunas>` | `uq_colaboradores_email` |
| foreign key | `fk_<tabela>_<tabela_referenciada>` | `fk_avaliacoes_colaboradores` |
| check | `ck_<tabela>_<coluna>` | `ck_avaliacoes_nota` |
| index | `ix_<tabela>_<colunas>` | `ix_avaliacoes_ciclo_id` |

- Unicidade exige constraint `unique` própria (nunca índice avulso); índices
  comuns existem apenas para performance e são justificados em comentário.
- Limite de 63 bytes do PostgreSQL; sem abreviações, salvo decisão documentada.

## Identificador técnico (UUID)

- Toda tabela de domínio nova tem `id uuid primary key default gen_random_uuid()`.
- O `id` é identificador técnico imutável, nunca chave de negócio e nunca
  reutilizado após exclusão lógica. Chaves naturais de negócio, quando
  existirem, recebem `uq_` própria.
- `gen_random_uuid()` é nativo do PostgreSQL 17; nenhuma extensão extra é
  necessária apenas por causa do UUID.

## Timestamps e timezone

- Colunas de tempo sempre `timestamptz`; o PostgreSQL armazena UTC e a conversão
  para exibição fica na aplicação, nunca no banco.
- `created_at timestamptz not null default now()` em toda tabela de domínio.
- `updated_at timestamptz not null default now()` quando a linha admite
  atualização; manutenção automática por trigger técnico padrão da foundation
  (F1-03) quando existir, nunca escrita manualmente pelo cliente.
- Registros de histórico/auditoria preservam `created_at` original; a
  atualização nunca reescreve silenciosamente o passado. A modelagem concreta de
  histórico/auditoria pertence às fases de domínio correspondentes.

## Versionamento otimista

- `version integer not null default 0`, incrementado a cada atualização, quando
  a entidade admite edição concorrente; é controle técnico de concorrência, não
  dado de negócio nem informação exibida.
- Aplicável por tabela, decidido na criação; nem toda tabela precisa de
  `version`. Ausência ou presença fica documentada na migration.

## Escopo por organização

- Entidades que serão multi-organização incluem `organization_id` desde a
  criação, como `uuid` referenciando a entidade organizacional futura.
- Nesta fase e na F1-03 nenhuma tabela `organizations` é criada; a FK e os
  índices correspondentes entram na etapa que introduzir a entidade
  organizacional. Auth/RLS e o uso efetivo do `organization_id` pertencem a
  fases posteriores.
- Tabelas globais/técnicas não recebem `organization_id`; a decisão de escopo é
  registrada por tabela na migration.

## Foreign keys e exclusão

- Toda FK é nomeada (`fk_<tabela>_<tabela_referenciada>`) e acompanhada de
  índice na coluna que a compõe.
- Comportamento padrão de exclusão: `ON DELETE RESTRICT` (ou `NO ACTION`),
  preservando referências e históricos. `CASCADE` somente por decisão explícita
  de domínio documentada na Issue.
- Exclusão física de registros com valor histórico/auditoria é proibida por
  padrão; retenção e ciclo de vida são regras de domínio da aplicação, definidas
  nas fases correspondentes, e não devem ser duplicadas ou improvisadas em
  migrations.

## Enums e constraints

- Preferir `text` + `check` nomeado (`ck_...`) ou tabelas de referência
  pequenas quando o conjunto de valores puder evoluir ou precisar de metadados.
- Tipo `enum` nativo do PostgreSQL somente para conjuntos congelados e
  estáveis, pois `ALTER TYPE ... ADD VALUE` tem restrições transacionais e de
  lock que dificultam evolução segura.
- Valores em `lowercase` e `snake_case`; ampliar/alterar conjuntos sempre via
  nova migration.
- `check` para domínio de valor simples (ex.: faixa permitida). Validações de
  negócio, workflow e autorização permanecem na aplicação/policy central — o
  banco não duplica regra de negócio ou autorização.

## Extensões, schema e ambiente

- Somente extensões realmente necessárias e suportadas pelo Supabase, cada uma
  habilitada em migration dedicada e justificada.
- Schema padrão `public` (convenção Supabase); nenhum schema de domínio é criado
  nesta fase nem na F1-03.
- Configuração e migrations não contêm credenciais, secrets, URLs de projeto
  remoto ou dados reais; nada de `service_role` ou variáveis sensíveis.

## Limites desta fase

Este documento não autoriza, em nenhuma etapa desta Issue: tabelas de domínio;
migration SQL funcional; Auth/RLS/policies; seeds; procedures ou transações de
negócio; migração de localStorage; alteração do runtime da aplicação. A F1-03
criará a migration de foundation técnica seguindo estas convenções, sem criar
entidades funcionais.
