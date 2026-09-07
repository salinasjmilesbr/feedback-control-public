# F3-10 — Desenho da validação integrada da estrutura organizacional (Issue #87)

> **Status:** desenho técnico em revisão — **não implementado**.
> Esta etapa entrega apenas este documento; nenhuma migration, schema, código,
> teste final ou PR de implementação é criado aqui. 100% sintético (sem dados reais).

## 1. Objetivo e escopo

Encerrar a **Fase 3** validando o modelo organizacional com uma **estrutura 100%
sintética, mas representativa dos padrões do piloto**, exercitando em conjunto as
entregas F3-01..F3-09 e provando os critérios de aceite da Issue #87.

- **Em escopo:** estrutura sintética representativa; reconstrução histórica por
  data; cenários de occupation/reporting/status/substituição/sucessão; colegiado
  0..N e snapshots históricos; matriz de validação documentada; rebuild
  reproduzível.
- **Fora do escopo:** importação da planilha real, produção, autorização completa,
  relatórios finais.

## 2. Inventário F3-01..F3-09 a exercitar

| Fase | Estruturas / funções | Papel na F3-10 |
| --- | --- | --- |
| F2 | `organizations`, `user_profiles`, `user_organization_memberships` | contexto de tenant; `user_profiles` apenas para o autor da sucessão (se D1=A) |
| F3-01 | `collaborators`, `collaborator_identifiers`, `collaborator_status_periods` | identidade; matrícula sintética; lifecycle (`active`/`leave`/`inactive`) |
| F3-02 | `job_roles`, `seniority_levels` | catálogo: oito conceitos do piloto + Junior/Pleno/Senior |
| F3-03 | `organizational_units`, `organizational_unit_parent_periods`, `organizational_positions` | unidades e posições formais (existência temporal; sem ocupante) |
| F3-04 | `position_reporting_lines` (+ triggers) | hierarquia formal temporal (superior único, sem ciclo, fail-closed) |
| F3-05 | `occupations` (+ triggers) | ocupação temporal; vacância; troca/transferência; licença; múltiplas posições |
| F3-06 | `temporary_responsibilities` (+ triggers) | substituição temporária (período fechado; titular derivado) |
| F3-07 | `organizacao_resolver_*` (7 funções) | reconstrução por data: responsável, gestor direto, subordinados, descendentes, cadeia, escopo |
| F3-08 | `collegiate_configurations`(+`_members`), `collegiate_cycle_snapshots`(+`_positions`/`_members`), `materializar_colegiado_ciclo` | colegiado 0..N (ausente/vazio/com membros) e snapshot imutável por ciclo |
| F3-09 | `cycle_evaluation_responsibilities`, `evaluation_succession_events`, `materializar_responsabilidades_avaliacao`, `registrar_sucessao_avaliador`, `resolver_responsavel_avaliacao_vigente` | responsabilidade avaliativa e sucessão de avaliador (se D1=A) |

## 3. Matriz: cenário da Issue #87 × estruturas/regras

| # | Cenário | Representação | Estruturas/regras exercitadas |
| --- | --- | --- | --- |
| 1 | Gerente com 3 Coordenadores + colaboradores | P_GER → {P_COORD1..3}; cada P_COORD → analistas/estagiário | `organizational_positions` + `position_reporting_lines`; `organizacao_resolver_descendentes`/`_cadeia` |
| 2 | Consultor direto ao Gerente | P_CONS → P_GER | `position_reporting_lines`; `job_role` Consultor sem nível intermediário |
| 3 | Analistas Júnior/Pleno/Sênior sob o mesmo Coordenador | 3 posições `Analista` com `seniority` Junior/Pleno/Senior → P_COORD | `organizational_positions` + `job_roles` + `seniority_levels` (senioridade ≠ hierarquia) |
| 4 | Estagiário sob Coordenador e/ou Gerente | P_EST1 → P_COORD; P_EST2 → P_GER2 | `job_role` Estagiario **sem seniority** |
| 5 | Gerência menor sem Coordenador | P_GER2 → Analista/Consultor/Estagiário diretos | reporting direta ao Gerente (sem degrau intermediário) |
| 6 | Especialista no patamar de Gerente, sem equipe | P_ESP → mesmo superior de P_GER (Diretor); zero subordinados | reporting line; "patamar" derivado (sem campo de nível) |
| 7 | Posição vaga | P_VACANTE sem `occupations` | `occupations` (vacância = ausência); resolução retorna NULL |
| 8 | Troca definitiva de ocupante | close occupation C1 + open C1_SUCESSOR | `occupations` (close+open); F3-09 sucessão (se D1=A) |
| 9 | Transferência entre coordenações | close occupation em P sob C1 + open em P' sob C2 | `occupations`; reporting lines inalteradas |
| 10 | Licença mantendo occupation | `collaborator_status_periods` `leave` no período; occupation vigente | status × occupation independentes (F3-01/F3-05) |
| 11 | Substituição temporária | `temporary_responsibilities` (`operational_evaluative`) sobre P_GER | substituição; titular/substituto resolvidos por data |
| 12 | Pessoa com duas posições simultâneas | 2 `occupations` do mesmo colaborador | múltiplas occupations simultâneas |
| 13 | Diretor reportando a Diretor (nível repetido) | P_DIR_AREA → P_DIR_EXEC | reporting line entre posições do mesmo `job_role` |
| 14 | Colegiado ausente / com membros / histórico por ciclo | sem config; config vazia; config {M1,M2} v1→v2; snapshots por ciclo | `collegiate_configurations`(+`_members`) + `collegiate_cycle_snapshots` |

**Conclusão da matriz:** os 14 cenários são **representáveis sem campos especiais por
cargo** — a hierarquia vem só de `position_reporting_lines`; o cargo/senioridade são
catálogos de configuração; vacância é ausência de occupation; substituição é
`temporary_responsibilities`; colegiado é configuração explícita 0..N.

## 4. Organização sintética proposta

Organização única **`Org Sintetica F3-10 Alfa`** (prefixo UUID `fc`), com o catálogo
reusando os **oito conceitos do piloto** já estabelecidos na F3-02
(Diretor, Gerente Senior, Gerente, Especialista, Coordenador, Consultor, Analista,
Estagiario) e as senioridades **Junior/Pleno/Senior**. Todos os nomes de pessoas,
matrículas, e-mails e unidades são **100% sintéticos**.

Esboço da árvore (posições → reporting lines):

```
P_DIR_EXEC (Diretor, raiz — sem superior)
└── P_DIR_AREA (Diretor)                    ← "Diretor → Diretor" (nível repetido)
    ├── P_GER1 (Gerente)
    │   ├── P_COORD1 (Coordenador)
    │   │   ├── P_AN_JR  (Analista/Junior)
    │   │   ├── P_AN_PL  (Analista/Pleno)
    │   │   ├── P_AN_SR  (Analista/Senior)
    │   │   └── P_EST1   (Estagiário — sem seniority)
    │   ├── P_COORD2 (Coordenador)          ← recebe transferência (cenário 9)
    │   ├── P_COORD3 (Coordenador)
    │   ├── P_CONS1  (Consultor)            ← responde direto ao Gerente (cenário 2)
    │   └── P_VACANTE (Analista)            ← posição vaga (cenário 7)
    ├── P_GER2 (Gerente)                    ← gerência menor sem Coordenador (cenário 5)
    │   ├── P_AN_G2   (Analista)
    │   ├── P_CONS_G2 (Consultor)
    │   └── P_EST_G2  (Estagiário — direto ao Gerente)
    └── P_ESP1 (Especialista)               ← mesmo superior do Gerente, sem equipe (cenário 6)
```

Colaboradores sintéticos (papel → matrícula sintética): Diretores (2), Gerentes (2),
Coordenadores (3 + 1 sucessor), Especialista (1), Consultores (2), Analistas
(Jr/Pl/Sr + gerência menor = 4), Estagiários (2), e um colaborador **DUP** que ocupa
duas posições simultâneas (cenário 12). Matrículas com prefixo sintético (ex.:
`FC-1001` … `FC-1099`), e-mails `*.f3-10@example.invalid`.

## 5. Linha do tempo sintética (reconstrução por data)

Para provar "estrutura histórica reconstruível por data", os eventos abaixo usam
`valid_from`/`valid_to` e são consultados por datas de referência distintas.

| Data | Evento | Estrutura/regra exercitada |
| --- | --- | --- |
| 2024-01-01 | criação do catálogo, unidades, posições e occupations iniciais | estado base |
| 2024-04-01 | **troca definitiva** de C1 → C1_SUCESSOR | `occupations` close+open (+ sucessão F3-09 se D1=A) |
| 2024-06-01 | **transferência** do Analista Júnior de C1 para C2 | `occupations` (nova posição sob C2) |
| 2024-07-01 | **reporting line** de P_COORD3 move de P_GER1 para P_GER2 | `position_reporting_lines` close+open |
| 2024-08-01 → 2024-10-01 | Analista Sênior em **licença** (`leave`) | `collaborator_status_periods`; occupation mantida |
| 2024-09-01 → 2024-11-01 | **substituição temporária** de P_GER1 (substituto) | `temporary_responsibilities` (período fechado) |
| 2024-07-01 | colegiado do Avaliado X muda de {M1,M2} → {M1} | `collegiate_configurations` v1→v2 |

Datas de consulta para asserts de reconstrução: **2024-02-01** (base), **2024-05-01**
(após troca), **2024-07-15** (após transferência/reporting), **2024-09-15** (durante
licença + substituição) e **2024-12-01** (após tudo).

## 6. Cenários de occupation / reporting line / status / substituição / sucessão

- **Troca definitiva (8):** fechar occupation de C1 e abrir a de C1_SUCESSOR na MESMA
  posição P_COORD1 — histórico preservado (duas linhas) e posição não recriada. Se
  D1=A, materializar snapshot/responsabilidades e `registrar_sucessao_avaliador`
  (evento com original → novo, data, motivo, autor).
- **Transferência (9):** fechar occupation na posição sob C1 e abrir na posição sob
  C2 — reporting lines inalteradas; a hierarquia do colaborador muda por ocupação.
- **Licença (10):** inserir período `leave`; a occupation permanece vigente; a
  resolução F3-07 continua a derivar o titular (licença não exclui).
- **Substituição (11):** `temporary_responsibilities` `operational_evaluative` sobre
  P_GER1; a resolução retorna substituto durante o período e titular depois; o
  substituto **não** recebe occupation nem vira gestor permanente.
- **Duas posições (12):** duas `occupations` simultâneas do mesmo colaborador; a
  resolução devolve duas linhas (uma por posição ocupada).
- **Reporting (1,2,5,6,13):** provar que a hierarquia é derivada apenas da reporting
  line (nunca de cargo/senioridade) e que "mesmo patamar"/"nível repetido" são
  representáveis com o mesmo `job_role` em alturas diferentes.

## 7. Colegiado 0..N e snapshots históricos

- **Ausente:** avaliado sem `collegiate_configurations` → snapshot com 0 membros.
- **Vazio explícito:** config existente sem membros → 0 membros (distinto de ausente).
- **Com membros:** config {M1, M2} → snapshot congela {M1, M2}.
- **Histórico por ciclo:** v1 {M1,M2} vigente até 2024-06-30; v2 {M1} de 2024-07-01;
  snapshot do ciclo 2024/1 (ref. 2024-03-01) congela {M1,M2}; snapshot do ciclo
  2024/2 (ref. 2024-08-01) congela {M1}. Mudança posterior de config **não** altera
  snapshots (imutabilidade).

## 8. Consultas/asserts por critério de aceite

| Critério | Asserts previstos |
| --- | --- |
| Todos os cenários representáveis sem campos por cargo | 14 cenários resolvem via reporting/occupation; ausência de colunas rank/level/order/hierarchy (já garantida por F3-02/F3-03) |
| Estrutura histórica reconstruível por data | `organizacao_resolver_*` em ≥5 datas distintas retornam a árvore esperada em cada instante |
| Nenhum cenário exige gestor fictício | raiz = ausência de reporting line; vaga = responsável NULL; sem occupation artificial |
| Estagiário coberto explicitamente | posições/occupations de Estagiário existem e resolvem; sem `seniority` exigida |
| Dados 100% sintéticos | por construção; varredura de nome/e-mail/matrícula real ausente |
| Matriz documentada | este documento + `supabase/validacao/README.md` |
| rebuild/testes/build/lint/CI/CodeQL | `npm test`/`build`/`lint`/`git diff --check`; `db reset` ×2 + runner SQL com `[PASS]` |
| Codex não faz merge | nenhum merge |

## 9. Estratégia de rebuild e repetibilidade

- Artefato único e determinístico: `supabase/validacao/01-cenario-f3-10.sql`
  (monta a organização sintética; idempotente por prefixo `fc`) +
  `02-validar-f3-10.sql` (runner de asserts `[PASS]`/`[FAIL]`, `ON_ERROR_STOP`).
- Fluxo: `supabase start` → `db reset` (16 migrations + seed) → cenário → validação,
  repetido **duas vezes** para provar reprodutibilidade; limpeza ao final.
- Execução apenas no **Supabase local** (superuser = service_role); RLS
  deny-by-default comprovado como `authenticated`; nenhuma policy alterada; nenhuma
  conexão remota.

## 10. Critérios objetivos para declarar a Fase 3 validada

1. O runner `02-validar-f3-10.sql` termina com **0 falhas** e todas as verificações
   `[PASS]` em **duas** reconstruções limpas.
2. Os 14 cenários da Issue #87 estão cobertos por pelo menos um assert cada.
3. A reconstrução por data é comprovada em ≥5 datas distintas.
4. `npm test`/`build`/`lint`/`git diff --check` passam.
5. Nenhum dado real presente (varredura) e nenhum merge realizado.

## 11. Riscos, lacunas e ambiguidades

- **Custo do cenário:** a estrutura completa é grande (2 diretores, 2 gerentes, 3+
  coordenadores, ~15 colaboradores, 2 organizações). Mitigação: prefixo `fc` único,
  cenário idempotente e limpeza automática.
- **F3-09 exige pré-requisitos** (snapshot F3-08 materializado + autor `user_profiles`
  + responsabilidades materializadas) — só faz sentido se D1=A.
- **"Mesmo patamar" / "nível repetido"** não têm conceito próprio no modelo: são
  interpretados como *reporting line entre posições do mesmo job_role* ou *mesmo
  superior* (sem campo de nível). Já decidido pela F3-03/F3-04 — registrado como
  nota, não como decisão pendente.
- **"Gerente Senior"** é nome de catálogo da F3-02 (sintético); o cenário "nível
  repetido" da Issue usa o MESMO job_role em alturas diferentes, não um sufixo.
- Nenhuma regra de negócio nova é inventada; a validação apenas exercita o modelo
  existente.

## 12. Decisões pendentes (para revisão)

### D1 — Incluir a F3-09 (responsabilidade avaliativa + sucessão) na validação?

- **Pergunta:** a F3-10 exercita apenas a estrutura (F3-01..F3-08) ou também a
  sucessão de avaliador (F3-09) no cenário de "troca definitiva de ocupante"?
- **Alternativas:**
  - **A (Recomendada):** F3-01..F3-08 integralmente + F3-09 no ponto "troca
    definitiva" (materializar snapshot + responsabilidades + `registrar_sucessao_avaliador`).
  - B: só F3-01..F3-08 (estrutura pura), F3-09 fora.
  - C: F3-09 extensiva (múltiplas sucessões/vacância/substituição avaliativa).
- **Impacto:** A fecha a integração ponta a ponta da Fase 3 (requer autor
  `user_profiles` + snapshots); B é mais simples mas deixa a costura estrutura→
  avaliação não validada em conjunto; C amplia além do pedido da Issue.

### D2 — Organização do artefato de validação

- **Pergunta:** um único par `01-cenario-f3-10.sql` + `02-validar-f3-10.sql`, ou
  múltiplos arquivos por tema?
- **Alternativas:**
  - **A (Recomendada):** um único cenário + um único runner (padrão F3-01..F3-09).
  - B: dividir por tema (estrutura, temporalidade, colegiado, sucessão).
- **Impacto:** A é determinístico e consistente com o padrão; B fragmenta e complica
  a ordem de dependências.

### D3 — Catálogo de job_roles/seniorities a usar

- **Pergunta:** reusar exatamente os oito conceitos do piloto da F3-02 (incluindo
  "Gerente Senior") + Junior/Pleno/Senior, ou definir um subconjunto?
- **Alternativas:**
  - **A (Recomendada):** reusar os 8 conceitos + 3 senioridades (100% sintéticos).
  - B: subconjunto apenas dos papéis citados na Issue (sem "Gerente Senior").
- **Impacto:** A preserva o catálogo canônico da F3-02 e cobre "nível repetido" sem
  inventar nome; B diverge do catálogo já validado.
