# F3-09 — Desenho técnico (Issue #86)

> **Status:** proposta em fase de desenho — **não implementado**.
> Aguardando respostas às decisões **D1–D9** antes de qualquer branch/migration/commit/PR.
> Este documento não contém dados reais e não altera nenhum arquivo de implementação.

## 1. Objetivo e escopo da Issue #86

**F3-09 — Mudanças organizacionais durante ciclo.**

Aplicar as regras fechadas para **transferência, sucessão e substituição temporária**
sem perder o snapshot/histórico do ciclo.

Escopo obrigatório:

- ciclo usa snapshot organizacional/avaliativo na ativação;
- mudança definitiva de gestor durante ciclo transfere responsabilidade de avaliação
  pendente ao novo gestor;
- preservar responsável original e registrar evento de sucessão com data/motivo/autor;
- avaliação já concluída não é reaberta automaticamente por mudança estrutural;
- temporary responsibility permite substituto avaliar durante o período e titular
  reassumir no retorno;
- substituição temporária não transforma substituto em gestor histórico permanente;
- entrada de colaborador elegível não exige tempo mínimo de trabalho por regra global;
- desligamento/licença seguem outcomes e regras já definidos na Fase B;
- pessoa com duas posições/gerências deve ter relações estruturais resolvidas
  separadamente.

Fora do escopo: redesign visual, capabilities/RLS finais, dados reais.

## 2. Estado atual relevante (F3-01 → F3-08 + frontend)

### Banco (Supabase)

- `collaborators` / `collaborator_identifiers` / `collaborator_status_periods`
  (`active`/`leave`/`inactive`) — F3-01.
- `organizational_units` / `organizational_unit_parent_periods` /
  `organizational_positions` — F3-03.
- `position_reporting_lines` — F3-04.
- `occupations` — F3-05.
- `temporary_responsibilities` (`operational`/`evaluative`/`operational_evaluative`)
  — F3-06.
- Funções de resolução da F3-07 (`organizacao_resolver_responsavel_posicao`,
  `_gestor_direto`, `_cadeia`, `_escopo_posicoes`, etc.) — todas `SECURITY INVOKER` /
  `STABLE`.
- F3-08: `collegiate_configurations(_members)` +
  `collegiate_cycle_snapshots(_positions/_members)` + RPC `materializar_colegiado_ciclo`.
  O snapshot congela, por avaliado, **posições ocupadas**, **superior formal direto
  resolvido** (`superior_collaborator_id` = responsável *operacional*: substituto
  operacional > titular > NULL) e **colegiado**.

### Frontend (localStorage, intacto)

- `CicloAvaliacao` (ano/ciclo/status).
- `Feedback` (status `RASCUNHO`/`PRONTA_PARA_FEEDBACK`/`CONCLUIDA`/`CANCELADA`, notas de
  gerente/coordenador/colegiado).
- `Colaborador` (denormalizado: `gestorDiretoMatricula`, `avaliadoresColegiadoMatriculas`,
  `funcao` com enum `GERENTE`/`COORDENADOR`/…).
- `historicoOrganizacionalStorage.ts` = **"Fase B"** (movimentações `ADMISSAO`/
  `ALTERACAO_ESTRUTURA`/`LICENCA`/`RETORNO_LICENCA`/`DESLIGAMENTO`, com `escopo`
  `CICLO_ATUAL_E_POSTERIORES` | `SOMENTE_CICLOS_POSTERIORES`) e `getAplicabilidadeNoCiclo`
  define os outcomes de desligamento/licença ("não aplicável" / "suspensa").
- A determinação de "quem avalia" (`permissaoAvaliacao.ts`) é **dinâmica** a partir de
  `gestorDiretoMatricula` + `avaliadoresColegiadoMatriculas` (sem persistência de
  sucessão/substituto).

> Observação: o termo **"Fase B"** não existe em nenhum arquivo do repositório — vem do
> roadmap/Issues. Pela semântica do item 8, interpreta-se "Fase B" como o modelo de
> movimentações/desligamento/licença já existente no frontend (ver D9).

## 3. Conflito com a F3-08 (destaque obrigatório)

Existe um **conflito potencial real** entre "mudança definitiva de gestor transfere
responsabilidade ao novo gestor" e as decisões **D9/D10 da F3-08** ("snapshots imutáveis;
mudanças posteriores de occupation/reporting **não** alteram snapshots materializados").

- Interpretar "transferir a pendência" como **atualizar**
  `collegiate_cycle_snapshot_positions.superior_collaborator_id` quebraria a imutabilidade
  fechada na F3-08.
- **Resolução proposta:** a sucessão é modelada em uma **camada separada e auditável**
  (evento de sucessão + responsabilidade temporal) que **referencia** o snapshot como
  "responsável original" e aponta o **novo** responsável, **nunca** mutando o snapshot
  F3-08. F3-08 permanece a fonte imutável do "estado na ativação"; F3-09 acrescenta o
  "estado vigente sob sucessão/substituição".
- **Lacuna (não conflito):** a F3-08 congelou o superior **operacional**; a F3-09 precisa
  do responsável **avaliativo** (substituto `evaluative`/`operational_evaluative` > titular).
  Um substituto `evaluative`-only hoje **não** aparece em `superior_collaborator_id` da
  F3-08 — o "avaliador" não pode simplesmente reusar essa coluna (ver D2).

Não há conflito com F3-01/F3-03→F3-07: todas as fontes são compatíveis.

## 4. Desenho técnico mínimo proposto (DB-only)

Mesmo padrão das fases anteriores: **uma migration aditiva**, funções `SECURITY INVOKER`,
FKs compostas `ON DELETE RESTRICT`, RLS deny-by-default, validação SQL, documentação.
**Sem frontend, sem tabela de ciclos, sem tabela de avaliação, sem capabilities/RLS finais.**

Conceitualmente (`20260907190000_evaluator_responsibility_succession.sql`):

1. **Resolução avaliativa por posição/data** (espelho da F3-07, mas para o *avaliador*):
   - `organizacao_resolver_responsavel_avaliativo_posicao(position_id, data)` → titular
     (occupation vigente) + substituto *avaliativo*
     (`responsibility_type in ('evaluative','operational_evaluative')`) + responsável
     avaliativo = **substituto avaliativo > titular**.
   - `organizacao_resolver_avaliador_avaliado(collaborator_id, data)` → por cada posição
     ocupada na data, a posição superior (reporting line) e o responsável **avaliativo**
     dessa posição superior (mantém a separação por posição).

2. **Responsabilidade de avaliação congelada + sucessão** (camada separada da F3-08):
   - Tabela de **responsabilidade temporal** por `(ciclo, avaliado, posição ocupada)` com
     `valid_from`/`valid_to` (close+open), contendo o responsável (avaliador) vigente —
     o "original" é materializado na ativação (a partir da F3-08/resolução avaliativa) e a
     **sucessão = fechar a linha atual + abrir nova** com o novo gestor, preservando a
     original.
   - Tabela **imutável de eventos de sucessão**
     `(ciclo, avaliado, posição, responsável_original, responsável_novo, data, motivo, autor)`
     — append-only, sem update/delete.

3. **RPC explícita, transacional e idempotente** `registrar_sucessao_avaliador(...)` —
   chamada pelo fluxo de domínio ao registrar uma mudança definitiva de gestor; valida
   tenant, computa o novo gestor pela F3-07, fecha a responsabilidade atual e abre a nova,
   e grava o evento de sucessão (data/motivo/autor). Só afeta a responsabilidade **em
   aberto** (pendente) — nunca as já encerradas.

4. **Consulta de responsável vigente** `resolver_responsavel_avaliacao_vigente(...)` —
   combina: responsabilidade temporal (original → sucessores) + overlay por data da
   substituição avaliativa temporária (substituto durante o período; titular reassume no
   retorno; substituto **nunca** vira gestor permanente porque só existe em
   `temporary_responsibilities`).

5. **Não-regras preservadas:** nenhuma coluna/tabela de "carência/tempo mínimo" (item 7);
   desligamento/licença seguem F3-05/F3-07 + Fase B (item 8); múltiplas posições resolvidas
   separadamente (item 9).

### Esboço de DDL (proposta, ainda não implementado)

```sql
-- (a) Resolução avaliativa por posição/data
create or replace function public.organizacao_resolver_responsavel_avaliativo_posicao(
  p_position_id uuid,
  p_data timestamptz
)
returns table (
  position_id uuid,
  titular_collaborator_id uuid,
  substitute_collaborator_id uuid,
  responsible_collaborator_id uuid
)
language sql stable set search_path = public
as $$ /* titular = occupation vigente;
        substituto = temporary_responsibility vigente
          (responsibility_type in ('evaluative','operational_evaluative'));
        responsavel_avaliativo = substituto > titular */ $$;

-- (b) Avaliador (gestor direto avaliativo) por posição ocupada do avaliado
create or replace function public.organizacao_resolver_avaliador_avaliado(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  occupied_position_id uuid,
  manager_position_id uuid,
  manager_collaborator_id uuid
)
language sql stable set search_path = public
as $$ /* occupations + position_reporting_lines + (a) */ $$;

-- (c) Responsabilidade de avaliação temporal (close+open)
create table public.cycle_evaluation_responsibilities (
  id                        uuid        not null default gen_random_uuid(),
  organization_id           uuid        not null,
  snapshot_id               uuid        not null,      -- referencia collegiate_cycle_snapshots (original)
  position_id               uuid        not null,      -- posicao ocupada pelo avaliado
  responsible_collaborator_id uuid       not null,     -- avaliador vigente
  valid_from                timestamptz not null,
  valid_to                  timestamptz,               -- null = vigente; sucessao = close+open
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  version                   integer     not null default 0
  -- PK/FKs compostas ON DELETE RESTRICT; exclusion de nao-sobreposicao por (snapshot, position);
  -- RLS deny-by-default (sem policies)
);

-- (d) Evento de sucessão (imutável)
create table public.evaluation_succession_events (
  id                              uuid        not null default gen_random_uuid(),
  organization_id                 uuid        not null,
  snapshot_id                     uuid        not null,
  position_id                     uuid        not null,
  previous_responsible_collaborator_id uuid    not null,
  new_responsible_collaborator_id      uuid    not null,
  succession_date                 timestamptz not null,
  motive                          text        not null,
  author_collaborator_id          uuid        not null,
  created_at                      timestamptz not null default now()
  -- sem updated_at/version; append-only; FKs compostas RESTRICT; RLS deny-by-default
);

-- (e) RPC de sucessão (explícita, transacional, idempotente)
create or replace function public.registrar_sucessao_avaliador(
  p_organization_id uuid,
  p_ano integer,
  p_ciclo integer,
  p_position_id uuid,
  p_succession_date timestamptz,
  p_motive text,
  p_author_collaborator_id uuid
) returns void
language plpgsql set search_path = public
as $$ /* valida tenant; resolve snapshot vigente; resolve novo gestor (F3-07);
        fecha responsabilidade aberta e abre nova; grava evento de sucessao;
        idempotente por (ciclo, posicao, data) */ $$;
```

> O esboço acima é ilustrativo e será ajustado conforme as respostas D1–D9. Nada disso
> existe ainda no repositório.

## 5. Decisões de domínio a fechar

| # | Decisão | Recomendação |
|---|---------|--------------|
| D1 | Sucessão × imutabilidade da F3-08: camada separada que referencia (nunca muta) o snapshot | **A** — camada separada |
| D2 | Avaliador = responsável **avaliativo** (substituto evaluative > titular), não o operacional da F3-08 | **A** — novo resolvedor avaliativo |
| D3 | Granularidade por **(avaliado, posição ocupada)** (múltiplas posições separadas) | **A** — por posição |
| D4 | Modelar apenas o **gestor direto resolvido por posição**; papéis (Gerente/Coordenador) adiados | **A** — sem reificar papéis |
| D5 | Sucessão por **RPC explícita** (motivo/autor), não por trigger | **A** — RPC explícita |
| D6 | Responsável vigente = **tabela temporal (close+open)** + evento de sucessão imutável | **A** — temporal + evento |
| D7 | `autor` = `author_collaborator_id uuid NOT NULL` (FK composta para `collaborators`) | **A** — colaborador UUID |
| D8 | "Concluída não reaberta": o **chamador** passa o conjunto afetado (pendente); banco só afeta responsabilidade em aberto | **A** — lista explícita |
| D9 | Desligamento/licença reusam F3-05/F3-07 + Fase B; **sem carência**; `escopo` da mudança é decisão do chamador | **A** — reusar, sem carência |

### D1 — Sucessão × imutabilidade da F3-08

- **Pergunta:** a transferência de responsabilidade **nunca** atualiza o snapshot F3-08;
  ela cria uma camada separada que o referencia?
- **Alternativas:**
  - **A (Recomendada):** camada separada (responsabilidade temporal + evento de sucessão)
    que referencia `collegiate_cycle_snapshots` como "original" e nunca o muta.
  - B: relaxar D9/D10 e atualizar `superior_collaborator_id` do snapshot.
  - C: substituir o snapshot F3-08 por um novo modelo.
- **Impacto:** A preserva D9/D10 e o histórico; B/C reabrem a F3-08 e violam
  "imutável no fluxo normal".

### D2 — Qual "responsável" é o avaliador (operacional vs avaliativo)

- **Pergunta:** o avaliador congelado/resolvido é o responsável **avaliativo** (substituto
  `evaluative`/`operational_evaluative` > titular), não o operacional da F3-08?
- **Alternativas:**
  - **A (Recomendada):** novo resolvedor avaliativo; congelar/derivar o responsável
    avaliativo (a F3-08 continua com o operacional; os dois coexistem).
  - B: reusar `superior_collaborator_id` operacional como avaliador.
  - C: resolver o avaliador apenas no momento da avaliação (sem congelar).
- **Impacto:** A é o único que faz o substituto `evaluative`-only avaliar durante o período;
  B erra esse caso; C perde o "snapshot na ativação".

### D3 — Granularidade da responsabilidade (pessoa × posição)

- **Pergunta:** a responsabilidade/sucessão é por **(avaliado, posição ocupada)** — uma
  pessoa com duas gerências tem duas responsabilidades separadas?
- **Alternativas:**
  - **A (Recomendada):** por (avaliado, posição ocupada) — alinhado a "resolvidas
    separadamente".
  - B: por avaliado (uma responsabilidade única) — exige "posição primária", inexistente.
  - C: por avaliado com união de gerentes.
- **Impacto:** A atende o item 9 sem inventar "posição primária"; a agregação "quem é o
  avaliador único da pessoa com 2 gerentes" fica **adiada** para a migração da avaliação.

### D4 — "Papel" (Gerente × Coordenador) dentro ou fora da F3-09

- **Pergunta:** a F3-09 modela apenas o **gestor direto resolvido por posição** (avaliador),
  deixando a semântica dos papéis (Gerente = sobe a cadeia até GERENTE; Coordenador =
  direto se COORDENADOR) para o frontend/fase de avaliação?
- **Alternativas:**
  - **A (Recomendada):** só o gestor direto resolvido por posição (não reifica
    "Gerente"/"Coordenador").
  - B: modelar papéis + um mapeamento `job_role → papel de avaliação` (novo catálogo).
  - C: modelar ambos os papéis de forma genérica.
- **Impacto:** A evita antecipar o catálogo de papéis avaliativos (o banco hoje só tem
  `job_roles` configurável, sem semântica de GERENTE/COORDENADOR); B/C antecipam a migração
  da avaliação.

### D5 — Disparo da sucessão (RPC explícita × trigger)

- **Pergunta:** a sucessão é registrada por **RPC explícita** chamada pelo fluxo (que
  fornece motivo/autor e o conjunto afetado), e não por trigger?
- **Alternativas:**
  - **A (Recomendada):** RPC explícita transacional/idempotente (padrão F3-08; único caminho
    que carrega `motivo`/`autor`).
  - B: trigger em `occupations`/`position_reporting_lines`.
  - C: trigger + RPC.
- **Impacto:** A é consistente com a F3-08 e com a ausência de modelo de autoria; B não
  consegue capturar motivo/autor e anteciparia auditoria.

### D6 — Como persistir o "responsável vigente" (temporal close+open × log + derivar)

- **Pergunta:** a responsabilidade vigente é uma **tabela temporal** (fechar a linha
  original e abrir a do sucessor), com o evento de sucessão referenciando original/novo?
- **Alternativas:**
  - **A (Recomendada):** tabela temporal (close+open) + evento de sucessão imutável.
  - B: só log append-only de sucessões e derivar o "vigente" (sem linha "atual").
- **Impacto:** A é consistente com o padrão temporal do repositório
  (occupations/reporting/collegiate), dá um "vigente" trivial e auditável; B é menor, mas
  torna a derivação e a idempotência mais complexas.

### D7 — Identidade do "autor" do evento de sucessão

- **Pergunta:** o `autor` do evento de sucessão é `author_collaborator_id uuid NOT NULL`
  (FK composta para `collaborators`)?
- **Alternativas:**
  - **A (Recomendada):** `author_collaborator_id` (colaborador, NOT NULL) +
    `motivo text NOT NULL` + `data timestamptz NOT NULL`.
  - B: `author_user_profile_id` (identidade de auth) — mas a operação é de um colaborador.
  - C: texto livre (nome) — perde identidade/auditoria.
  - D: autor opcional.
- **Impacto:** A introduz a primeira coluna de autoria de domínio (F3-04/05/06 adiaram
  autor) de forma mínima e consistente com a identidade canônica (UUID); as demais
  enfraquecem a auditabilidade exigida pela Issue.

### D8 — Onde vive "pendente × concluída" (enforcement da não-reabertura)

- **Pergunta:** como as avaliações estão no localStorage (sem tabela), a regra "concluída
  não é reaberta" é aplicada pelo **chamador** (a RPC recebe explicitamente o conjunto de
  avaliados/posições *pendentes* afetados), e o banco só registra sucessão sobre
  responsabilidades em aberto?
- **Alternativas:**
  - **A (Recomendada):** RPC recebe o conjunto afetado (lista explícita, como QA-A da
    F3-08); o banco garante que só a responsabilidade em aberto é fechada/reaberta.
  - B: criar coluna/tabela de status de avaliação (antecipa a migração da avaliação).
  - C: flag "encerrada" na responsabilidade.
- **Impacto:** A mantém o domínio de avaliação fora do banco; B antecipa a migração; C
  duplica estado que pertence ao domínio de avaliação.

### D9 — Limite de "desligamento/licença (Fase B)" e carência

- **Pergunta:** confirmar que **"Fase B"** = o modelo de movimentações/desligamento/licença
  do frontend (`historicoOrganizacionalStorage`) e que a F3-09 **não** reespecifica esses
  outcomes — reusa F3-05 (inactive exige fechar occupations), F3-07 (leave não exclui;
  inactive não resolve) e deixa a decisão de `escopo` (ciclo atual vs posteriores) com o
  chamador, **sem** criar coluna de "carência/tempo mínimo"?
- **Alternativas:**
  - **A (Recomendada):** reusar as regras existentes; nenhuma tabela de carência; o `escopo`
    da mudança continua sendo decisão do chamador (lista explícita na RPC).
  - B: criar no banco um conceito de "escopo da mudança" (atual vs posteriores) para a
    sucessão.
- **Impacto:** A evita antecipar a migração das movimentações; B antecipa a Fase B no
  banco. Em ambos os casos, **nenhuma carência** (item 7 é uma não-regra a documentar +
  validar).

## 6. Fora do escopo (reafirmado)

Redesign visual, capabilities/RLS finais, dados reais, migração do domínio de
avaliações/ciclos para o banco, migração das movimentações (Fase B) para o banco, e a
agregação "avaliador único quando há 2 gerentes" (adiada para a fase de avaliação).

## 7. Próximos passos

1. Responder **D1–D9** (pode ser "A" para todas, ou customizar).
2. Ajustar este desenho conforme as respostas.
3. Só então criar a branch e a migration `20260907190000_…` + validação SQL + documentação.
