-- ============================================================================
-- F6 / Issue #427: CONCORRENCIA REAL entre DUAS sessoes PostgreSQL — SESSAO A
-- (primeiro processo psql; roda em BACKGROUND, inicia a corrida e E DONA DAS
--  TRES JANELAS DE CONTENCAO)
-- ----------------------------------------------------------------------------
-- Papel desta sessao (processo psql 1 de 3):
--   (0) confere as pre-condicoes da corrida (fixture EXCLUSIVA `56-cenario-f6-
--       427-concorrencia.sql`, ator soberano, assinaturas das RPCs, barreira
--       nova instalada e a ORDEM CANONICA DE LOCKS presente no corpo das TRES
--       RPCs de ocupacao — `definir`, `trocar`, `encerrar`);
--   (1) instala um artefato TEMPORARIO em `public` (sequence NAO transacional +
--       funcao/gatilho em `public.occupations`) que torna a JANELA DE CONTENCAO
--       observavel de fora: o gatilho grava a marca (`nextval`) e dorme ~8s,
--       SOMENTE na sessao A e SOMENTE na operacao declarada no GUC
--       `virtus.f6_427_janela` ('insert' ou 'update');
--   (2) executa TRES janelas de contencao, cada uma DENTRO de um unico
--       `do $$ ... $$` (uma instrucao = uma transacao) e cada uma precedida do
--       `set` do GUC e seguida do `reset` do GUC;
--   (3) ao final REMOVE o artefato e afirma a higiene (nada residual).
--
-- Ordem REAL de execucao (tres processos psql INDEPENDENTES; sem `dblink`, sem
-- `postgres_fdw`, sem extensao nova — a prova e entre dois backends reais):
--   1) `56-cenario-f6-427-concorrencia.sql` (fixture exclusiva, single-session);
--   2) `57-sessao-a-f6-427-concorrencia.sql` (ESTE arquivo) -> BACKGROUND,
--      iniciado PRIMEIRO;
--   3) `58-sessao-b-f6-427-concorrencia.sql`                -> FOREGROUND,
--      iniciado ~1s depois e BLOQUEADO pelos locks de A;
--   4) `59-validar-f6-427-concorrencia.sql`                 -> single-session,
--      SOMENTE depois de A e B terminarem (estado consolidado).
--   A UNICA coordenacao entre A e B e o laco de espera DETERMINISTICO da sessao
--   B (marca 1, 2 e 3 da sequence NAO transacional do artefato). No CI a corrida
--   e exatamente: A em background (`&`), `sleep 1`, B em foreground, `wait` em A
--   e, ao final, o validador 59.
--
-- AS TRES JANELAS E OS VEREDITOS CONTRATADOS (detalhe no cabecalho do 58):
--   JANELA 1 (GUC='update') — `definir` (A) x `trocar` (B), MESMO colaborador X:
--     A chama `estrutura_ocupacao_definir(X, XP2, 2035-01-01Z)`. X tem UMA
--     ocupacao ABERTA em XP1 desde 2024-01-01: a RPC fecha XP1 EXATAMENTE em
--     2035-01-01Z e abre XP2 no mesmo instante. A VENCE e nao pode falhar. B
--     chama `estrutura_ocupacao_trocar(X, atual=XP1, nova=XP3, 2035-01-02Z)` e
--     fica BLOQUEADA na linha do colaborador ate A commitar; depois da
--     serializacao, a ocupacao vigente de X e XP2 (nao XP1) => recusa PUBLICA
--     e DETERMINISTICA `F5_07_CONFLICT: ocupacao vigente nao corresponde a
--     posicao atual informada` (a data civil DIFERENTE de B — 2035-01-02 — torna
--     impossivel a variante "segunda transicao ... mesma data civil"). NUNCA
--     40P01/deadlock. Ver o bloco "ORDEM CANONICA DE LOCKS" abaixo.
--   JANELA 2 (GUC='insert') — `definir` (A) x `definir` (B), MESMO colaborador Y
--     (nasce SEM ocupacao): A chama `definir(Y, YQ1, 2036-01-01Z)` — 0 ocupacoes
--     atravessando a data, abre a PRIMEIRA. B chama `definir(Y, YQ2,
--     2036-02-01Z)` (dia civil POSTERIOR) e e SERIALIZADA pela linha do
--     colaborador: depois do commit de A, B fecha YQ1 exatamente em 2036-02-01Z e
--     abre YQ2. Os DOIS aplicam — o resultado e a sequencia consecutiva
--     YQ1 [2036-01-01, 2036-02-01) + YQ2 [2036-02-01, infinity), com EXATAMENTE
--     UMA ocupacao ABERTA e ZERO sobreposicao. NUNCA 40P01.
--   JANELA 3 (GUC='insert') — `definir` (A) x INSERCAO CRUA (B), colaborador Z
--     (nasce SEM ocupacao): A chama `definir(Z, ZR1, 2037-01-01Z)`; enquanto A
--     esta DENTRO da escrita (linha de Z travada + advisory lock da organizacao
--     em maos + a linha [2037-01-01, infinity) JA inserida no indice e ainda NAO
--     commitada), B insere CRUAMENTE em `public.occupations` para Z, na posicao
--     VAGA ZR2, o intervalo [2037-06-01, 2038-01-01) — que SOBREPOE o de A. A
--     exclusion `ex_occupations_collaborator_no_overlap` (GiST) FAZ B ESPERAR
--     pela transacao de A e, depois do commit de A, recusa B com SQLSTATE
--     `23P01` nomeando a constraint POR COLABORADOR. A posicao alvo (ZR2) esta
--     VAGA, portanto a exclusion por POSICAO nao tem o que barrar: se a mensagem
--     nomear `ex_occupations_position_no_overlap`, a prova FALHA (isso indicaria
--     que B atacou uma posicao errada, nao a barreira nova).
--
-- ORDEM CANONICA DE LOCKS (o ponto CENTRAL desta prova — regressao = deadlock):
--   `definir`, `trocar` e `encerrar` travam NESTA ordem:
--     (1) a LINHA do colaborador alvo (`select ... from public.collaborators ...
--         for update`);
--     (2) o advisory lock da organizacao
--         (`pg_advisory_xact_lock(hashtext('position_reporting_lines:' ||
--         v_org::text))`);
--     (3) so entao a guarda de segunda transicao e todo o DML.
--   Com a ordem INVERTIDA (advisory primeiro, como `trocar` tinha antes da
--   correcao) uma corrida `definir` x `trocar` sobre o MESMO colaborador forma
--   CICLO DE ESPERA (um segura a linha e espera o advisory; o outro segura o
--   advisory e espera a linha) e o PostgreSQL aborta um dos backends com
--   SQLSTATE `40P01` / "deadlock detected" — o desfecho PUBLICO contratado
--   (`F5_07_CONFLICT`) NUNCA acontece. Esta prova FALHA ALTO nesse caso:
--     - a sessao B detecta 40P01/"deadlock" e levanta `[FAIL] ... DEADLOCK ...`;
--     - a sessao A detecta 40P01/"deadlock" na propria escrita e levanta
--       `[FAIL] ... DEADLOCK ...`;
--     - ALEM DISSO, e de forma DETERMINISTICA (sem depender de escalonamento),
--       esta sessao (e a sessao B e o validador 59) confere no TEXTO das tres
--       RPCs (`pg_get_functiondef`) que a posicao de `public.collaborators`
--       (travamento da linha) vem ANTES da posicao de `pg_advisory_xact_lock`.
--   JULGAMENTO (declarado, nao escondido): a marca de contencao so pode ser
--   observada por B DEPOIS de A ja ter os DOIS locks em maos (o gatilho dispara
--   dentro da escrita). Nessa fotografia o ciclo de espera da ordem invertida
--   nao chega a se formar por escalonamento (B sempre entra depois), por isso a
--   deteccao DETERMINISTICA da regressao de ordem e a conferencia ESTATICA de
--   `pg_get_functiondef` acima — a deteccao dinamica de 40P01 continua em pe
--   como segunda linha de defesa.
--
-- Evidencia de contencao esperada (server-side):
--   - A dorme ~8s DENTRO da escrita de cada janela, com os DOIS locks em maos
--     (linha do colaborador + advisory lock da organizacao);
--   - B tenta a escrita concorrente e fica BLOQUEADA (linha do colaborador nas
--     janelas 1 e 2; espera da exclusion GiST na janela 3) ate A commitar; B
--     mede com `clock_timestamp()` e so aceita a prova com tempo decorrido >= 2s;
--   - os desfechos sao os PUBLICOS do contrato: `F5_07_CONFLICT` (janela 1),
--     sucesso serializado (janela 2) e `23P01` nomeando a exclusion POR
--     COLABORADOR (janela 3) — em nenhuma janela ha efeito parcial.
--
-- operation_id desta sessao (UUIDs sinteticos fixos, NUNCA reutilizados entre as
-- duas sessoes; os eventos de encerramento usam o operation_id DERIVADO
-- `md5(<operation_id> || ':OCUPACAO_ENCERRADA')::uuid`, como na RPC):
--   janela 1 definir X -> XP2 2035-01-01Z -> f4279000-0000-0000-0000-0000000000a1
--   janela 2 definir Y -> YQ1 2036-01-01Z -> f4279000-0000-0000-0000-0000000000a2
--   janela 3 definir Z -> ZR1 2037-01-01Z -> f4279000-0000-0000-0000-0000000000a3
--   (a sessao B usa f4279100-0000-0000-0000-0000000000b1 na janela 1 —
--    PERDEDORA — e f4279100-0000-0000-0000-0000000000b2 na janela 2)
--
-- Alvo fixo do contrato (fixture EXCLUSIVA `56-cenario-f6-427-concorrencia.sql`;
-- nenhum outro validador escreve nesta organizacao):
--   organizacao          : f427a000-0000-0000-0000-0000000000a1
--   ator soberano        : f427b000-0000-0000-0000-0000000000a1
--                          (membership ativa f427d000-...-a1)
--   colaborador X (jan.1): f427c000-0000-0000-0000-0000000000a1 (XP1 -> XP2)
--   colaborador Y (jan.2): f427c000-0000-0000-0000-0000000000a2 (sem -> YQ1)
--   colaborador Z (jan.3): f427c000-0000-0000-0000-0000000000a3 (sem -> ZR1)
--   posicoes             : XP1 ...c1, XP2 ...c2, XP3 ...c3, YQ1 ...c4,
--                          YQ2 ...c5, ZR1 ...c6, ZR2 ...c7
--                          (todas abertas, valid_from 2024-01-01Z)
--
-- LIMITACOES CONHECIDAS (declaradas, nao presumidas):
--   - a janela de contencao e o `pg_sleep(8)` DENTRO da escrita (topo do
--     intervalo 3..5s do desenho, AMPLIADO para 8s por robustez do runner do
--     CI). A sessao B precisa TENTAR a escrita enquanto A dorme; se o runner
--     demorar mais que ~8s para subir o segundo psql, o laco de espera de B
--     aborta com `[FAIL]` explicito. Ao ampliar o `pg_sleep`, amplie TAMBEM o
--     teto do laco de espera de B (120 x 0.25s = 30s por janela) nos DOIS
--     arquivos, de forma coerente;
--   - a marca do gatilho e uma SEQUENCE (nao transacional) DE PROPOSITO: e ela
--     que permite a B provar que A JA esta DENTRO da escrita com os locks em
--     maos no instante da tentativa, eliminando a corrida de "quem chega
--     primeiro" e tornando a prova deterministica;
--   - o artefato e um gatilho `AFTER INSERT OR UPDATE` (e NAO `BEFORE`): na
--     janela 3 B precisa encontrar o intervalo de A JAH presente no indice GiST
--     (a exclusion so faz B esperar e so pode recusar depois do commit de A). Um
--     gatilho BEFORE dormiria ANTES da insercao no indice (o intervalo de A nao
--     existiria durante a janela) e a corrida viraria espera pelo lock da FK —
--     ou deadlock — em vez do `23P01` contratado. Ver JULGAMENTO no bloco 3;
--   - `collaborator_events` e append-only e as FKs sao RESTRICT: a prova NAO tem
--     reset parcial. Para reexecutar: `supabase db reset --local` + todas as
--     fixtures + 57 (background) + 58 (foreground) + 59 (mesma doutrina dos
--     validadores P9/F5).
--
-- Como executar (Supabase local; NUNCA remoto). A em BACKGROUND e B em
-- FOREGROUND, quase ao mesmo tempo:
--   uteis: `supabase db reset --local` + fixtures, depois
--   A) Get-Content supabase/validacao/57-sessao-a-f6-427-concorrencia.sql -Raw -Encoding UTF8 |
--        docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   B) idem para 58-...sql (foreground) e, ao final dos dois, 59-...sql.
-- ============================================================================

\set ON_ERROR_STOP on

-- A prova tem uma janela LEGITIMA de ~8s dentro de UMA instrucao (o pg_sleep do
-- artefato temporario). Um `statement_timeout` herdado do papel de conexao
-- (ex.: 8s de `service_role` no Supabase local) nao pode transformar essa janela
-- contratada em falha espuria: o timeout e desligado APENAS nesta sessao de
-- validacao (nenhum objeto do banco e alterado, nenhum controle do produto e
-- relaxado).
set statement_timeout = 0;
set lock_timeout = 0;

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture EXCLUSIVA presente no estado NAO CORRIDO, ator
--    soberano, RPCs na assinatura do contrato, barreira nova instalada e ORDEM
--    CANONICA DE LOCKS presente nas TRES RPCs de ocupacao
-- ----------------------------------------------------------------------------
do $$
declare
  v_org        uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator       uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_x          uuid := 'f427c000-0000-0000-0000-0000000000a1';
  v_y          uuid := 'f427c000-0000-0000-0000-0000000000a2';
  v_z          uuid := 'f427c000-0000-0000-0000-0000000000a3';
  v_memb       uuid;
  v_n          int;
  v_args       text;
  v_def        text;
  v_fn         text;
  v_pos_linha  int;
  v_pos_advis  int;
begin
  if not exists (select 1 from public.organizations o where o.id = v_org) then
    raise exception '[FAIL] pre-condicao A: organizacao EXCLUSIVA da corrida (%) ausente — execute 56-cenario-f6-427-concorrencia.sql', v_org;
  end if;
  if not exists (select 1 from public.user_profiles p where p.id = v_ator and p.status = 'active') then
    raise exception '[FAIL] pre-condicao A: perfil ATIVO do ator da corrida (%) ausente na fixture', v_ator;
  end if;
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator and m.organization_id = v_org and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] pre-condicao A: membership ATIVA do ator da corrida na organizacao % ausente', v_org;
  end if;
  if not public.colaborador_ator_valido(v_ator, v_org) then
    raise exception '[FAIL] pre-condicao A: colaborador_ator_valido falso para o ator da corrida (%)', v_ator;
  end if;

  -- Estado NAO CORRIDO (protege contra reexecucao sem `db reset`): X com UMA
  -- ocupacao ABERTA em XP1 desde 2024-01-01; Y e Z sem ocupacao; nenhum evento
  -- na organizacao; nenhuma ocupacao iniciando em 2035 ou depois.
  select count(*) into v_n from public.collaborators c where c.organization_id = v_org;
  if v_n <> 3 then
    raise exception '[FAIL] pre-condicao A: a organizacao EXCLUSIVA da corrida deveria ter exatamente 3 colaboradores (X/Y/Z), encontrados % — outro validador escreveu nesta organizacao?', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = 'f4278000-0000-0000-0000-0000000000c1'
       and o.valid_from = '2024-01-01T00:00:00Z' and o.valid_to is null
  ) then
    raise exception '[FAIL] pre-condicao A: X deveria ter UMA ocupacao ABERTA em XP1 desde 2024-01-01Z — execute 56-cenario-f6-427-concorrencia.sql num banco recem-resetado';
  end if;
  select count(*) into v_n from public.occupations o where o.organization_id = v_org;
  if v_n <> 1 then
    raise exception '[FAIL] pre-condicao A: a organizacao da corrida deveria ter exatamente 1 ocupacao antes da corrida (X em XP1), encontradas % — a trilha e append-only: reexecute apos `supabase db reset --local`', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e where e.organization_id = v_org;
  if v_n <> 0 then
    raise exception '[FAIL] pre-condicao A: a organizacao da corrida ja tem % evento(s) — a trilha e append-only: reexecute apos `supabase db reset --local`', v_n;
  end if;
  select count(*) into v_n
    from public.occupations o
   where o.organization_id = v_org and o.collaborator_id in (v_y, v_z);
  if v_n <> 0 then
    raise exception '[FAIL] pre-condicao A: Y e Z deveriam estar SEM ocupacao antes da corrida (encontradas %)', v_n;
  end if;

  -- Assinaturas EXATAS do contrato (as duas RPCs usadas pela corrida).
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)');
  if v_args is distinct from
     'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_position_id uuid, p_vigencia timestamp with time zone, p_motivo text, p_cycle_scope text, p_reference_cycle_id uuid' then
    raise exception '[FAIL] pre-condicao A: assinatura de estrutura_ocupacao_definir fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)');
  if v_args is distinct from
     'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_current_position_id uuid, p_new_position_id uuid, p_vigencia timestamp with time zone, p_motivo text' then
    raise exception '[FAIL] pre-condicao A: assinatura de estrutura_ocupacao_trocar fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;

  -- Barreira final instalada (posicao + colaborador) e forma meio-aberta `[)`.
  select count(*) into v_n from pg_constraint
   where conrelid = 'public.occupations'::regclass
     and conname in ('ex_occupations_position_no_overlap','ex_occupations_collaborator_no_overlap');
  if v_n <> 2 then
    raise exception '[FAIL] pre-condicao A: exclusoes de occupations esperadas=2, encontradas=%', v_n;
  end if;
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'public.occupations'::regclass and c.conname = 'ex_occupations_collaborator_no_overlap';
  if v_def is null or position('[)' in v_def) = 0 then
    raise exception '[FAIL] pre-condicao A: ex_occupations_collaborator_no_overlap ausente ou fora da forma meio-aberta [) (%)', coalesce(v_def,'ausente');
  end if;

  -- ORDEM CANONICA DE LOCKS: (1) linha do colaborador ANTES de (2) advisory
  -- lock da organizacao, nas TRES RPCs de ocupacao. Checagem ESTATICA e
  -- DETERMINISTICA: e ela que denuncia a regressao de ordem mesmo quando o
  -- escalonamento nao chega a formar o ciclo de espera (40P01).
  foreach v_fn in array array[
    'estrutura_ocupacao_definir', 'estrutura_ocupacao_trocar', 'estrutura_ocupacao_encerrar'
  ] loop
    v_def := null;
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn
     order by p.oid desc
     limit 1;
    if v_def is null then
      raise exception '[FAIL] pre-condicao A: RPC public.% ausente', v_fn;
    end if;
    v_pos_linha := position('public.collaborators' in v_def);
    v_pos_advis := position('pg_advisory_xact_lock' in v_def);
    if v_pos_linha = 0 or v_pos_advis = 0 then
      raise exception '[FAIL] pre-condicao A: nao foi possivel localizar o travamento da linha do colaborador e/ou o advisory lock da organizacao no corpo de public.%', v_fn;
    end if;
    if not (v_pos_linha < v_pos_advis) then
      raise exception '[FAIL] pre-condicao A: ORDEM CANONICA DE LOCKS REGREDIU em public.% — o advisory lock da organizacao aparece ANTES do travamento da linha do colaborador (posicoes % e %). Com a ordem invertida uma corrida definir x trocar sobre o MESMO colaborador forma ciclo de espera (SQLSTATE 40P01 / "deadlock detected") em vez do F5_07_CONFLICT publico',
        v_fn, v_pos_advis, v_pos_linha;
    end if;
  end loop;

  raise notice '[PASS] pre-condicoes da sessao A: organizacao EXCLUSIVA % no estado NAO CORRIDO (X com 1 ocupacao aberta em XP1; Y e Z sem ocupacao; zero eventos), ator % com membership ativa %, RPCs na assinatura do contrato, as duas exclusoes instaladas e ORDEM CANONICA DE LOCKS (linha do colaborador antes do advisory lock da organizacao) presente em definir/trocar/encerrar',
    v_org, v_ator, v_memb;
end $$;

-- ----------------------------------------------------------------------------
-- 1) Higiene fail-safe + artefato TEMPORARIO de contencao
-- ----------------------------------------------------------------------------
-- Higiene fail-safe: remove artefato de uma execucao ANTERIOR interrompida
-- (idempotente; nao altera nada quando nao existe).
drop trigger if exists _mut_f6_427_contencao on public.occupations;
drop function if exists public._mut_f6_427_contencao_marca();
drop sequence if exists public._mut_f6_427_contencao_seq;

-- Duas partes, ambas TEMPORARIAS e removidas no passo 5:
--   (a) `_mut_f6_427_contencao_seq` — SEQUENCE (nao transacional) usada como
--       MARCA de que a sessao A ja esta DENTRO da escrita com os locks em maos.
--       E lida por OUTRA sessao (a sessao B) e e o que torna a prova
--       deterministica: B so tenta a escrita quando A ja dorme;
--   (b) `_mut_f6_427_contencao_marca()` + gatilho `AFTER INSERT OR UPDATE` em
--       `public.occupations` — grava a marca e executa `pg_sleep(8)` SOMENTE na
--       sessao que declarou a janela no GUC `virtus.f6_427_janela`
--       ('insert'/'update') e SOMENTE na operacao correspondente. Sem o GUC (caso
--       da sessao B) o gatilho retorna imediatamente: as escritas de B continuam
--       RAPIDAS e as esperas medidas por B sao SIGNIFICATIVAS.
--   JULGAMENTO (a escolha AFTER em vez de BEFORE esta justificada): a janela 3
--   exige que o intervalo [2037-01-01, infinity) de A JA exista no indice GiST
--   enquanto A dorme — so assim a insercao crua de B e OBRIGADA a esperar pela
--   transacao de A na propria checagem da exclusion e, depois do commit, recusada
--   com 23P01. Um gatilho BEFORE dormiria ANTES de a linha entrar no indice: B
--   passaria pela exclusion (que ainda nao veria conflito) e ficaria presa
--   apenas no lock da FK (KEY SHARE na linha do colaborador) — produzindo
--   exatamente o deadlock ou uma violacao de estado que a prova NAO admite.
create sequence public._mut_f6_427_contencao_seq;

create or replace function public._mut_f6_427_contencao_marca()
returns trigger
language plpgsql
set search_path = public
as $mut$
declare
  v_janela text := nullif(current_setting('virtus.f6_427_janela', true), '');
  v_marca  bigint;
begin
  -- Sem GUC declarado nesta sessao a escrita NAO e atrasada (a sessao B nunca
  -- declara a janela: so a sessao A).
  if v_janela is null then
    return null;
  end if;
  -- A janela atrasa SOMENTE a operacao declarada ('insert' ou 'update').
  if v_janela <> lower(tg_op) then
    return null;
  end if;
  v_marca := nextval('public._mut_f6_427_contencao_seq');
  raise notice 'sessao A: DENTRO do % de public.occupations (colaborador %) com a LINHA do colaborador (FOR UPDATE) e o advisory lock da organizacao em maos — dormindo 8s antes do commit (marca=%). Janela %',
    tg_op, new.collaborator_id, v_marca, v_janela;
  perform pg_sleep(8);
  return null;
end;
$mut$;

create trigger _mut_f6_427_contencao
  after insert or update on public.occupations
  for each row execute function public._mut_f6_427_contencao_marca();

-- ----------------------------------------------------------------------------
-- 2) JANELA 1 — `definir` (A) x `trocar` (B) no MESMO colaborador X
--    Veredito de A: SUCESSO (XP1 fechada em 2035-01-01Z + XP2 aberta).
--    Veredito de B: F5_07_CONFLICT publico (posicao atual divergente), NUNCA 40P01.
-- ----------------------------------------------------------------------------
set "virtus.f6_427_janela" = 'update';

do $$
declare
  v_org     uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator    uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_x       uuid := 'f427c000-0000-0000-0000-0000000000a1';
  v_xp1     uuid := 'f4278000-0000-0000-0000-0000000000c1';
  v_xp2     uuid := 'f4278000-0000-0000-0000-0000000000c2';
  v_op      uuid := 'f4279000-0000-0000-0000-0000000000a1';
  v_vig     timestamptz := '2035-01-01T00:00:00Z';
  v_id      uuid;
  v_n       int;
  v_card    int;
  v_pos     uuid;
  v_seg     numeric;
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_marca   bigint;
  v_called  boolean;
begin
  -- Pre-condicao da janela: X tem exatamente UMA ocupacao vigente na vigencia.
  select count(*) into v_n
    from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_x
     and o.valid_from <= v_vig and (o.valid_to is null or o.valid_to > v_vig);
  if v_n <> 1 then
    raise exception '[FAIL] A/janela 1: X deveria ter exatamente 1 ocupacao vigente em 2035-01-01Z (tem %)', v_n;
  end if;

  raise notice 'sessao A/janela 1: chamando estrutura_ocupacao_definir (X: XP1 -> XP2, vigencia 2035-01-01Z) com a janela de contencao ATIVA (marca + pg_sleep 8s no UPDATE de public.occupations)';
  v_ini := clock_timestamp();
  begin
    v_id := public.estrutura_ocupacao_definir(
      v_org, v_ator, v_op, v_x, v_xp2, v_vig,
      'Ocupacao concorrente F6-427 janela 1 (A vence)',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    if sqlstate = '40P01' or sqlerrm ilike '%deadlock%' then
      raise exception '[FAIL] A/janela 1: DEADLOCK DETECTADO (sqlstate %, mensagem %) — a ORDEM CANONICA DE LOCKS regrediu: a linha do colaborador (FOR UPDATE) tem de ser travada ANTES do advisory lock da organizacao', sqlstate, sqlerrm;
    end if;
    raise exception '[FAIL] A/janela 1: estrutura_ocupacao_definir falhou (sqlstate %, mensagem %) — a escrita vencedora da janela 1 nao pode falhar', sqlstate, sqlerrm;
  end;
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  if v_id is null then
    raise exception '[FAIL] A/janela 1: definir nao devolveu o id da nova ocupacao';
  end if;

  -- A marca e uma sequence NAO transacional: prova que o gatilho temporario
  -- disparou DENTRO desta escrita, com os locks em maos.
  select s.last_value, s.is_called into v_marca, v_called
    from public._mut_f6_427_contencao_seq s;
  if v_called is not true or v_marca < 1 then
    raise exception '[FAIL] A/janela 1: o gatilho temporario nao gravou a marca 1 de contencao (is_called=%, last_value=%) — a janela de contencao nao existiu', v_called, v_marca;
  end if;
  if v_seg < 4.0 then
    raise exception '[FAIL] A/janela 1: a escrita durou % segundos (esperado >= 4s: o pg_sleep(8) do artefato DENTRO da escrita e a janela de contencao que a sessao B deve sentir)', round(v_seg, 3);
  end if;

  -- Efeito EXATO da janela 1: X com 2 ocupacoes, UMA aberta (XP2), XP1 fechada
  -- exatamente na vigencia.
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_x;
  if v_n <> 2 then
    raise exception '[FAIL] A/janela 1: X deveria terminar com 2 ocupacoes (XP1 fechada + XP2 aberta), tem %', v_n;
  end if;
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_x and o.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] A/janela 1: X deveria ter exatamente 1 ocupacao ABERTA, tem %', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.id = v_id and o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = v_xp2
       and o.valid_from = v_vig and o.valid_to is null
  ) then
    raise exception '[FAIL] A/janela 1: a ocupacao devolvida por definir nao e a ABERTA em XP2 a partir de 2035-01-01Z';
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = v_xp1
       and o.valid_from = '2024-01-01T00:00:00Z' and o.valid_to = v_vig
  ) then
    raise exception '[FAIL] A/janela 1: XP1 deveria ter sido FECHADA exatamente em 2035-01-01Z';
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_x,'2034-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] A/janela 1: cardinalidade de X em 2034-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_x,'2035-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] A/janela 1: cardinalidade de X em 2035-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_posicao_soberana(v_x,'2035-06-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_xp2 then
    raise exception '[FAIL] A/janela 1: posicao soberana de X em 2035-06 deveria ser XP2 (%)', v_pos;
  end if;

  -- Trilha: OCUPACAO_INICIADA (operation_id de A) + OCUPACAO_ENCERRADA (derivado).
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_x
     and e.event_type = 'OCUPACAO_INICIADA' and e.operation_id = v_op
     and e.position_id = v_xp2 and e.effective_date = v_vig and e.result_entity_id = v_id;
  if v_n <> 1 then
    raise exception '[FAIL] A/janela 1: esperado 1 evento OCUPACAO_INICIADA com o operation_id de A (encontrados %)', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_x
     and e.event_type = 'OCUPACAO_ENCERRADA'
     and e.operation_id = md5(v_op::text || ':OCUPACAO_ENCERRADA')::uuid
     and e.position_id = v_xp1 and e.effective_date = v_vig;
  if v_n <> 1 then
    raise exception '[FAIL] A/janela 1: esperado 1 evento OCUPACAO_ENCERRADA com o operation_id DERIVADO de A (encontrados %)', v_n;
  end if;

  -- Nenhum par sobreposto para X (meio-aberto).
  select count(*) into v_n
    from public.occupations a
    join public.occupations b
      on b.collaborator_id = a.collaborator_id
     and b.id > a.id
     and tstzrange(a.valid_from, coalesce(a.valid_to,'infinity'::timestamptz), '[)')
      && tstzrange(b.valid_from, coalesce(b.valid_to,'infinity'::timestamptz), '[)')
   where a.organization_id = v_org and a.collaborator_id = v_x;
  if v_n <> 0 then
    raise exception '[FAIL] A/janela 1: % par(es) de ocupacoes sobrepostas de X apos a transicao', v_n;
  end if;

  raise notice '[PASS] sessao A/janela 1: definir VENCEU — X migrou XP1 -> XP2 em 2035-01-01Z (XP1 fechada no MESMO instante, exatamente 1 ABERTA, cardinalidade 1, sem sobreposicao, trilha OCUPACAO_INICIADA + OCUPACAO_ENCERRADA com os operation_id de A); a janela durou ~%s com a marca % e o advisory lock da organizacao em maos',
    round(v_seg, 3), v_marca;
end $$;

reset "virtus.f6_427_janela";

-- ----------------------------------------------------------------------------
-- 3) JANELA 2 — `definir` (A) x `definir` (B) no MESMO colaborador Y
--    Veredito de A: SUCESSO (abre a PRIMEIRA ocupacao de Y, em YQ1).
--    Veredito de B: SUCESSO SERIALIZADO (fecha YQ1 e abre YQ2) — NUNCA 40P01.
-- ----------------------------------------------------------------------------
set "virtus.f6_427_janela" = 'insert';

do $$
declare
  v_org     uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator    uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_y       uuid := 'f427c000-0000-0000-0000-0000000000a2';
  v_yq1     uuid := 'f4278000-0000-0000-0000-0000000000c4';
  v_op      uuid := 'f4279000-0000-0000-0000-0000000000a2';
  v_vig     timestamptz := '2036-01-01T00:00:00Z';
  v_id      uuid;
  v_n       int;
  v_card    int;
  v_seg     numeric;
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_marca   bigint;
  v_called  boolean;
begin
  -- Pre-condicao da janela: Y nasce SEM ocupacao (0 atravessando a vigencia).
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_y;
  if v_n <> 0 then
    raise exception '[FAIL] A/janela 2: Y deveria estar SEM ocupacao antes da janela 2 (tem %)', v_n;
  end if;

  raise notice 'sessao A/janela 2: chamando estrutura_ocupacao_definir (Y: sem ocupacao -> YQ1, vigencia 2036-01-01Z) com a janela de contencao ATIVA (marca + pg_sleep 8s no INSERT de public.occupations)';
  v_ini := clock_timestamp();
  begin
    v_id := public.estrutura_ocupacao_definir(
      v_org, v_ator, v_op, v_y, v_yq1, v_vig,
      'Ocupacao concorrente F6-427 janela 2 (A abre a primeira)',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    if sqlstate = '40P01' or sqlerrm ilike '%deadlock%' then
      raise exception '[FAIL] A/janela 2: DEADLOCK DETECTADO (sqlstate %, mensagem %) — a ORDEM CANONICA DE LOCKS regrediu: a linha do colaborador (FOR UPDATE) tem de ser travada ANTES do advisory lock da organizacao', sqlstate, sqlerrm;
    end if;
    raise exception '[FAIL] A/janela 2: estrutura_ocupacao_definir falhou (sqlstate %, mensagem %) — a escrita vencedora da janela 2 nao pode falhar', sqlstate, sqlerrm;
  end;
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  if v_id is null then
    raise exception '[FAIL] A/janela 2: definir nao devolveu o id da ocupacao de Y';
  end if;

  select s.last_value, s.is_called into v_marca, v_called
    from public._mut_f6_427_contencao_seq s;
  if v_called is not true or v_marca < 2 then
    raise exception '[FAIL] A/janela 2: o gatilho temporario nao gravou a marca 2 de contencao (is_called=%, last_value=%) — a janela 2 nao existiu', v_called, v_marca;
  end if;
  if v_seg < 4.0 then
    raise exception '[FAIL] A/janela 2: a escrita durou % segundos (esperado >= 4s: o pg_sleep(8) do artefato DENTRO da escrita e a janela que a sessao B deve sentir)', round(v_seg, 3);
  end if;

  -- Efeito de A na janela 2: Y com UMA ocupacao ABERTA em YQ1 (o fechamento
  -- dela em 2036-02-01Z e o efeito da sessao B e sera conferido pelo 59).
  select count(*) into v_n from public.occupations o
   where o.id = v_id and o.organization_id = v_org and o.collaborator_id = v_y
     and o.organizational_position_id = v_yq1
     and o.valid_from = v_vig and o.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] A/janela 2: a ocupacao ABERTA de Y em YQ1 a partir de 2036-01-01Z nao foi criada';
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_y,'2036-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] A/janela 2: cardinalidade de Y em 2036-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_y
     and e.event_type = 'OCUPACAO_INICIADA' and e.operation_id = v_op
     and e.position_id = v_yq1 and e.effective_date = v_vig and e.result_entity_id = v_id;
  if v_n <> 1 then
    raise exception '[FAIL] A/janela 2: esperado 1 evento OCUPACAO_INICIADA com o operation_id de A (encontrados %)', v_n;
  end if;
  -- Y nasceu sem ocupacao: a janela 2 NAO fecha nada, portanto NAO ha evento de
  -- encerramento com o operation_id derivado de A.
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org
     and e.operation_id = md5(v_op::text || ':OCUPACAO_ENCERRADA')::uuid;
  if v_n <> 0 then
    raise exception '[FAIL] A/janela 2: A nao deveria ter gravado OCUPACAO_ENCERRADA (Y nasceu sem ocupacao), encontrados %', v_n;
  end if;

  raise notice '[PASS] sessao A/janela 2: definir VENCEU — Y nasceu com UMA ocupacao ABERTA em YQ1 desde 2036-01-01Z (0 ocupacoes atravessando a data; nenhum encerramento por A); a janela durou ~%s com a marca %',
    round(v_seg, 3), v_marca;
end $$;

reset "virtus.f6_427_janela";

-- ----------------------------------------------------------------------------
-- 4) JANELA 3 — `definir` (A) x INSERCAO CRUA (B) no MESMO colaborador Z
--    Veredito de A: SUCESSO (abre a PRIMEIRA ocupacao de Z, em ZR1).
--    Veredito de B: SQLSTATE 23P01 nomeando ex_occupations_collaborator_no_overlap
--    (a posicao ZR2 esta VAGA: a exclusion por POSICAO nao pode disparar).
-- ----------------------------------------------------------------------------
set "virtus.f6_427_janela" = 'insert';

do $$
declare
  v_org     uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator    uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_z       uuid := 'f427c000-0000-0000-0000-0000000000a3';
  v_zr1     uuid := 'f4278000-0000-0000-0000-0000000000c6';
  v_op      uuid := 'f4279000-0000-0000-0000-0000000000a3';
  v_vig     timestamptz := '2037-01-01T00:00:00Z';
  v_id      uuid;
  v_n       int;
  v_card    int;
  v_pos     uuid;
  v_seg     numeric;
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_marca   bigint;
  v_called  boolean;
begin
  -- Pre-condicao da janela: Z nasce SEM ocupacao e ZR2 esta VAGA (para que a
  -- unica barreira capaz de recusar a insercao crua de B seja a POR COLABORADOR).
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_z;
  if v_n <> 0 then
    raise exception '[FAIL] A/janela 3: Z deveria estar SEM ocupacao antes da janela 3 (tem %)', v_n;
  end if;
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org
     and o.organizational_position_id = 'f4278000-0000-0000-0000-0000000000c7'
     and o.valid_from <= '2037-06-01T00:00:00Z'
     and (o.valid_to is null or o.valid_to > '2037-06-01T00:00:00Z');
  if v_n <> 0 then
    raise exception '[FAIL] A/janela 3: a posicao ZR2 (alvo da insercao crua de B) deveria estar VAGA (tem % ocupante vigente)', v_n;
  end if;

  raise notice 'sessao A/janela 3: chamando estrutura_ocupacao_definir (Z: sem ocupacao -> ZR1, vigencia 2037-01-01Z) com a janela de contencao ATIVA (marca + pg_sleep 8s no INSERT de public.occupations; a linha [2037-01-01, infinity) fica JA inserida no indice GiST e NAO commitada durante a janela)';
  v_ini := clock_timestamp();
  begin
    v_id := public.estrutura_ocupacao_definir(
      v_org, v_ator, v_op, v_z, v_zr1, v_vig,
      'Ocupacao concorrente F6-427 janela 3 (A abre a primeira de Z)',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    if sqlstate = '40P01' or sqlerrm ilike '%deadlock%' then
      raise exception '[FAIL] A/janela 3: DEADLOCK DETECTADO (sqlstate %, mensagem %) — a ORDEM CANONICA DE LOCKS regrediu: a linha do colaborador (FOR UPDATE) tem de ser travada ANTES do advisory lock da organizacao', sqlstate, sqlerrm;
    end if;
    raise exception '[FAIL] A/janela 3: estrutura_ocupacao_definir falhou (sqlstate %, mensagem %) — a escrita vencedora da janela 3 nao pode falhar (a insercao crua da sessao B e quem deve ser recusada)', sqlstate, sqlerrm;
  end;
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  if v_id is null then
    raise exception '[FAIL] A/janela 3: definir nao devolveu o id da ocupacao de Z';
  end if;

  select s.last_value, s.is_called into v_marca, v_called
    from public._mut_f6_427_contencao_seq s;
  if v_called is not true or v_marca < 3 then
    raise exception '[FAIL] A/janela 3: o gatilho temporario nao gravou a marca 3 de contencao (is_called=%, last_value=%) — a janela 3 nao existiu', v_called, v_marca;
  end if;
  if v_seg < 4.0 then
    raise exception '[FAIL] A/janela 3: a escrita durou % segundos (esperado >= 4s: o pg_sleep(8) do artefato DENTRO da escrita e a janela que a sessao B deve sentir na exclusion)', round(v_seg, 3);
  end if;

  -- Efeito da janela 3: Z com EXATAMENTE UMA ocupacao ABERTA em ZR1.
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_z;
  if v_n <> 1 then
    raise exception '[FAIL] A/janela 3: Z deveria terminar com exatamente 1 ocupacao, tem %', v_n;
  end if;
  select count(*) into v_n from public.occupations o
   where o.id = v_id and o.organization_id = v_org and o.collaborator_id = v_z
     and o.organizational_position_id = v_zr1
     and o.valid_from = v_vig and o.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] A/janela 3: a ocupacao ABERTA de Z em ZR1 a partir de 2037-01-01Z nao foi criada';
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_z,'2037-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] A/janela 3: cardinalidade de Z em 2037-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_posicao_soberana(v_z,'2037-06-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_zr1 then
    raise exception '[FAIL] A/janela 3: posicao soberana de Z em 2037-06 deveria ser ZR1 (%)', v_pos;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_z
     and e.event_type = 'OCUPACAO_INICIADA' and e.operation_id = v_op
     and e.position_id = v_zr1 and e.effective_date = v_vig and e.result_entity_id = v_id;
  if v_n <> 1 then
    raise exception '[FAIL] A/janela 3: esperado 1 evento OCUPACAO_INICIADA com o operation_id de A (encontrados %)', v_n;
  end if;

  raise notice '[PASS] sessao A/janela 3: definir VENCEU — Z nasceu com UMA ocupacao ABERTA em ZR1 desde 2037-01-01Z, JA inserida no indice GiST e NAO commitada durante ~%s (marca %); a insercao CRUA sobreposta da sessao B tem de ser recusada com 23P01 nomeando ex_occupations_collaborator_no_overlap',
    round(v_seg, 3), v_marca;
end $$;

reset "virtus.f6_427_janela";

-- ----------------------------------------------------------------------------
-- 5) Remocao do artefato TEMPORARIO (higiene) e estado consolidado POS-COMMIT
-- ----------------------------------------------------------------------------
drop trigger if exists _mut_f6_427_contencao on public.occupations;
drop function if exists public._mut_f6_427_contencao_marca();
drop sequence if exists public._mut_f6_427_contencao_seq;

do $$
declare
  v_org     uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator    uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_x       uuid := 'f427c000-0000-0000-0000-0000000000a1';
  v_y       uuid := 'f427c000-0000-0000-0000-0000000000a2';
  v_z       uuid := 'f427c000-0000-0000-0000-0000000000a3';
  v_xp1     uuid := 'f4278000-0000-0000-0000-0000000000c1';
  v_xp2     uuid := 'f4278000-0000-0000-0000-0000000000c2';
  v_yq1     uuid := 'f4278000-0000-0000-0000-0000000000c4';
  v_zr1     uuid := 'f4278000-0000-0000-0000-0000000000c6';
  v_memb    uuid;
  v_n       int;
begin
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator and m.organization_id = v_org and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] A/estado final: membership ativa do ator nao resolvida (a autoria da trilha nao pode ser conferida)';
  end if;

  -- X (janela 1): 2 ocupacoes, XP1 fechada EXATAMENTE em 2035-01-01Z e UMA ABERTA
  -- em XP2 desde 2035-01-01Z — o estado de A tem de ser o estado final de X
  -- (nenhuma escrita de B pode ter vencido nem deixado rastro).
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_x;
  if v_n <> 2 then
    raise exception '[FAIL] A/estado final: X deveria ter 2 ocupacoes (XP1 fechada + XP2 aberta), tem %', v_n;
  end if;
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_x and o.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] A/estado final: X deveria ter exatamente 1 ocupacao ABERTA, tem %', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = v_xp2
       and o.valid_from = '2035-01-01T00:00:00Z' and o.valid_to is null
  ) then
    raise exception '[FAIL] A/estado final: a ocupacao ABERTA de X deveria ser XP2 desde 2035-01-01Z';
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = v_xp1 and o.valid_to = '2035-01-01T00:00:00Z'
  ) then
    raise exception '[FAIL] A/estado final: XP1 deveria estar fechada EXATAMENTE em 2035-01-01Z';
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_x
     and e.actor_user_profile_id = v_ator and e.actor_membership_id = v_memb
     and e.operation_id in ('f4279000-0000-0000-0000-0000000000a1',
                            md5('f4279000-0000-0000-0000-0000000000a1' || ':OCUPACAO_ENCERRADA')::uuid);
  if v_n <> 2 then
    raise exception '[FAIL] A/estado final: a trilha de X deveria ter exatamente os 2 eventos de A (OCUPACAO_INICIADA + OCUPACAO_ENCERRADA) com a autoria do ator, encontrados %', v_n;
  end if;

  -- Y (janela 2): o efeito de A e a ocupacao ABERTA/ou fechada por B em YQ1 desde
  -- 2036-01-01Z; o evento OCUPACAO_INICIADA de A existe SEMPRE e a cardinalidade
  -- de Y e 1 com ou sem o commit da janela 2 de B (nenhuma sobreposicao em
  -- qualquer interleaving).
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_y
       and o.organizational_position_id = v_yq1
       and o.valid_from = '2036-01-01T00:00:00Z'
  ) then
    raise exception '[FAIL] A/estado final: a ocupacao de Y em YQ1 desde 2036-01-01Z (efeito de A na janela 2) nao existe';
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_y
     and e.event_type = 'OCUPACAO_INICIADA'
     and e.operation_id = 'f4279000-0000-0000-0000-0000000000a2'
     and e.position_id = v_yq1 and e.effective_date = '2036-01-01T00:00:00Z';
  if v_n <> 1 then
    raise exception '[FAIL] A/estado final: esperado 1 evento OCUPACAO_INICIADA de A para Y/YQ1 (encontrados %)', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_y and o.valid_to is null
  ) then
    raise exception '[FAIL] A/estado final: Y deveria ter exatamente UMA ocupacao ABERTA (YQ1, ou YQ2 se a sessao B ja commitou a janela 2)';
  end if;
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_y and o.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] A/estado final: Y deveria ter exatamente 1 ocupacao ABERTA, tem %', v_n;
  end if;

  -- Z (janela 3): EXATAMENTE UMA ocupacao, ABERTA em ZR1 desde 2037-01-01Z, e
  -- nenhuma linha com o id reservado a insercao CRUA da sessao B.
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_z;
  if v_n <> 1 then
    raise exception '[FAIL] A/estado final: Z deveria ter exatamente 1 ocupacao, tem %', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_z
       and o.organizational_position_id = v_zr1
       and o.valid_from = '2037-01-01T00:00:00Z' and o.valid_to is null
  ) then
    raise exception '[FAIL] A/estado final: a ocupacao de Z em ZR1 desde 2037-01-01Z nao existe ou nao esta aberta';
  end if;
  if exists (select 1 from public.occupations o where o.id = 'f4278000-0000-0000-0000-0000000003f1') then
    raise exception '[FAIL] A/estado final: a insercao CRUA sobreposta da sessao B (id reservado f4278000-...-3f1) foi ACEITA — a exclusion por colaborador nao barrou';
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org
     and e.operation_id = 'f4279100-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] A/estado final: a intencao PERDEDORA da sessao B na janela 1 (operation_id f4279100-...-b1) gravou % evento(s) na trilha', v_n;
  end if;

  -- Nenhum par sobreposto por colaborador em toda a organizacao EXCLUSIVA.
  select count(*) into v_n
    from public.occupations a
    join public.occupations b
      on b.collaborator_id = a.collaborator_id
     and b.id > a.id
     and tstzrange(a.valid_from, coalesce(a.valid_to,'infinity'::timestamptz), '[)')
      && tstzrange(b.valid_from, coalesce(b.valid_to,'infinity'::timestamptz), '[)')
   where a.organization_id = v_org;
  if v_n <> 0 then
    raise exception '[FAIL] A/estado final: % par(es) de ocupacoes SOBREPOSTAS do mesmo colaborador na organizacao da corrida — o invariante da #427 foi violado', v_n;
  end if;

  -- Higiene: nenhum residuo do artefato temporario.
  if to_regclass('public._mut_f6_427_contencao_seq') is not null then
    raise exception '[FAIL] A/higiene: sequence temporaria de contencao NAO foi removida';
  end if;
  if to_regprocedure('public._mut_f6_427_contencao_marca()') is not null then
    raise exception '[FAIL] A/higiene: funcao temporaria de contencao NAO foi removida';
  end if;
  if exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.occupations'::regclass
       and t.tgname = '_mut_f6_427_contencao'
  ) then
    raise exception '[FAIL] A/higiene: gatilho temporario de contencao NAO foi removido';
  end if;

  raise notice '[PASS] sessao A: as TRES janelas venceram (X em XP2 desde 2035-01-01Z, Y com a primeira ocupacao em YQ1 desde 2036-01-01Z e Z em ZR1 desde 2037-01-01Z), nenhum deadlock, nenhuma sobreposicao por colaborador na organizacao da corrida e nenhum residuo do artefato temporario';
  raise notice 'sessao A: a contencao SERVER-SIDE e provada pelo tempo de espera medido pela sessao B (arquivo 58) e o estado consolidado e conferido pelo validador 59';
  raise notice 'sessao A: para reexecutar a prova e obrigatorio `supabase db reset --local` + fixtures (as trilhas sao append-only e as ocupacoes sao historicas)';
end $$;
