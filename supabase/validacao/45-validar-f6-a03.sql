-- ============================================================================
-- F6-A03 (Issue #266) + F6-A11 (Issue #273): validação automatizada —
-- BOOTSTRAP DE PLATAFORMA com a ANCORA FUNCIONAL do primeiro Admin
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de `44-cenario-f6-a03.sql`, como owner local (`postgres`), com
-- ON_ERROR_STOP ativo. Cada verificacao imprime um [PASS]; qualquer divergencia
-- aborta com exit code != 0.
--
-- Cobre os criterios de aceite do contrato (docs/F6-A03-desenho-tecnico.md §9) na
-- assinatura VIGENTE ampliada pela F6-A11 (docs/F6-A11-desenho-tecnico.md,
-- D22-D30):
--   A  preflight: tabela/RLS/ACL, RPC INVOKER + search_path + EXECUTE so
--      service_role, catalogo 31 e bundle admin 9 INTACTOS; assinatura NOVA de
--      7 parametros PRESENTE e assinatura ANTIGA (4 parametros) MORTA (D25);
--   B  trilha: append-only (trigger e ACL) e INVISIVEL para `authenticated`;
--   C  gate: negativos (ator inativo, nome vazio, entrada nula, founder
--      inexistente e founder inativo) — TODOS fail-closed e SEM efeito;
--   C7-C9 rollback fail-closed da FORMA NOVA do founder (nome/matricula/e-mail,
--      D25) sem nenhum efeito persistido;
--   D  caminho feliz + D16/D17 + SEPARACAO DE PLANOS (o operador nao ganha
--      authority no tenant criado);
--   D24 ancora FUNCIONAL do primeiro Admin: 1 colaborador + 1 identificador
--      ABERTO = matricula + 1 periodo `active` aberto + 1 evento `ADMISSAO`
--      (ator = membership do founder) + 1 vinculo F5-02 ATIVO, na MESMA
--      transacao;
--   E  idempotencia: replay devolve o MESMO organization_id sem novo efeito
--      (inclusive dos dados da ancora: 1/1/1/1/1) e payload divergente RECUSA —
--      inclusive quando diverge SOMENTE em campo NOVO do hash canonico;
--   F  isolamento: o estado PREEXISTENTE (LEGADO) fica intocado e uma SEGUNDA
--      organizacao pode ser provisionada para o mesmo founder (com a ancora
--      funcional propria);
--   G  higiene final: nenhum residuo do cenario (inclusive da ancora funcional).
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) PREFLIGHT — schema, ACL e invariantes herdados
-- ============================================================================
do $$
declare
  v_n          integer;
  v_rls        boolean;
  v_def        text;
  v_reg        regprocedure;
  v_catalogo   integer;
  v_bundle     integer;
  v_admin_n    integer;
begin
  -- (A1) Tabela nova presente, com RLS habilitado e ZERO policy.
  if to_regclass('public.platform_provisioning_events') is null then
    raise exception '[FAIL] A1: platform_provisioning_events ausente';
  end if;
  select c.relrowsecurity into v_rls
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'platform_provisioning_events';
  if v_rls is not true then
    raise exception '[FAIL] A1: platform_provisioning_events sem RLS';
  end if;
  select count(*) into v_n from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'platform_provisioning_events';
  if v_n <> 0 then
    raise exception '[FAIL] A1: platform_provisioning_events com % policy (esperado ZERO)', v_n;
  end if;

  -- (A2) ACL: `service_role` SOMENTE SELECT+INSERT (append-only no runtime).
  if not has_table_privilege('service_role', 'public.platform_provisioning_events', 'SELECT')
     or not has_table_privilege('service_role', 'public.platform_provisioning_events', 'INSERT') then
    raise exception '[FAIL] A2: service_role sem SELECT/INSERT na trilha de plataforma';
  end if;
  if has_table_privilege('service_role', 'public.platform_provisioning_events', 'UPDATE')
     or has_table_privilege('service_role', 'public.platform_provisioning_events', 'DELETE')
     or has_table_privilege('service_role', 'public.platform_provisioning_events', 'TRUNCATE') then
    raise exception '[FAIL] A2: service_role com UPDATE/DELETE/TRUNCATE na trilha de plataforma';
  end if;
  if has_table_privilege('authenticated', 'public.platform_provisioning_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.platform_provisioning_events', 'INSERT')
     or has_table_privilege('anon', 'public.platform_provisioning_events', 'SELECT') then
    raise exception '[FAIL] A2: cliente com privilegio na trilha de plataforma';
  end if;

  -- (A3) RPC — assinatura VIGENTE da F6-A11 (D25): 7 parametros, com os tres
  --      campos do founder NO FIM da lista; SECURITY INVOKER (nenhum DEFINER
  --      novo: a guarda F4-08 exige exatamente 4), search_path fixo e EXECUTE
  --      so service_role.
  v_reg := to_regprocedure(
    'public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text)');
  if v_reg is null then
    raise exception '[FAIL] A3: assinatura NOVA (7 parametros) ausente — migration da F6-A11 nao aplicada';
  end if;
  select pg_get_functiondef(v_reg) into v_def;
  if position('SECURITY DEFINER' in v_def) <> 0 then
    raise exception '[FAIL] A3: organizacao_provisionar_inicial e SECURITY DEFINER';
  end if;
  -- `pg_get_functiondef` NAO emite `SECURITY INVOKER` (o default) e renderiza o
  -- `search_path` como `SET search_path TO 'public'`: a prova e pelo NOME do
  -- parametro, nao pela forma `=public`.
  if position('search_path' in replace(v_def, ' ', '')) = 0 then
    raise exception '[FAIL] A3: organizacao_provisionar_inicial sem search_path fixo';
  end if;

  -- (A3.a) D25 — a assinatura ANTIGA (4 parametros) tem de estar MORTA: manter
  --        as duas vivas criaria SOBRECARGA com um caminho de bootstrap SEM a
  --        ancora funcional (o `drop function` da migration e obrigatorio).
  if to_regprocedure('public.organizacao_provisionar_inicial(uuid, text, uuid, uuid)') is not null then
    raise exception '[FAIL] A3: assinatura ANTIGA (4 parametros) ainda existe — sobrecarga viva sem ancora funcional';
  end if;
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'organizacao_provisionar_inicial';
  if v_n <> 1 then
    raise exception '[FAIL] A3: funcoes `organizacao_provisionar_inicial` esperado=1, encontrado=% (sobrecarga)', v_n;
  end if;

  -- (A3.b) EXECUTE da assinatura VIGENTE concedido SOMENTE a `service_role`.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
   where n.nspname = 'public'
     and p.oid = v_reg
     and a.privilege_type = 'EXECUTE'
     and a.grantee = 'service_role'::regrole;
  if v_n <> 1 then
    raise exception '[FAIL] A3: EXECUTE de service_role esperado=1, encontrado=%', v_n;
  end if;

  -- (A4) Cinco SECURITY DEFINER no schema (as 4 historicas), nunca 5.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_n <> 4 then
    raise exception '[FAIL] A4: SECURITY DEFINER esperado=4, encontrado=%', v_n;
  end if;

  -- (A5) Invariantes herdados: catalogo 31, bundle admin 9, 1 role admin ativa.
  select count(*) into v_catalogo from public.capabilities;
  if v_catalogo <> 31 then
    raise exception '[FAIL] A5: catalogo com % capabilities (esperado 31)', v_catalogo;
  end if;
  select count(*) into v_bundle
    from public.access_role_capabilities m
    join public.access_roles r on r.id = m.access_role_id
   where r.name = 'admin' and r.is_system = true;
  if v_bundle <> 9 then
    raise exception '[FAIL] A5: bundle admin com % capabilities (esperado 9)', v_bundle;
  end if;
  select count(*) into v_admin_n from public.access_roles r
   where r.is_system = true and r.name = 'admin' and r.status = 'active';
  if v_admin_n <> 1 then
    raise exception '[FAIL] A5: roles de sistema admin ativas = % (esperado 1)', v_admin_n;
  end if;

  raise notice '[PASS] A: preflight OK (tabela com RLS e ZERO policy; service_role so SELECT+INSERT; RPC INVOKER com search_path fixo e EXECUTE so service_role; assinatura NOVA de 7 parametros viva e assinatura ANTIGA de 4 parametros MORTA; 4 DEFINER; catalogo 31; bundle admin 9)';
end $$;

-- ============================================================================
-- B) TRILHA — append-only e invisivel para o cliente
-- ============================================================================
-- B1) `authenticated` NAO le a trilha (sem grant ⇒ permission denied).
set role authenticated;
do $$
declare v_ok boolean := false;
begin
  begin
    perform 1 from public.platform_provisioning_events;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] B1: authenticated leu a trilha de plataforma';
  end if;
  raise notice '[PASS] B1: authenticated NAO le a trilha de plataforma (fail-closed)';
end $$;
reset role;

-- B2) `authenticated` NAO executa a RPC (EXECUTE so service_role).
set role authenticated;
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000ff', 'F6-A03 Nao Autorizado',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000001',
      'Admin Nao Autorizado A11', 'A1100000', 'nao.autorizado.a11@example.com');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] B2: authenticated executou organizacao_provisionar_inicial';
  end if;
  raise notice '[PASS] B2: authenticated NAO executa organizacao_provisionar_inicial';
end $$;
reset role;

-- B3) `service_role` NAO faz UPDATE na trilha (ACL).
set role service_role;
do $$
declare v_ok boolean := false;
begin
  begin
    update public.platform_provisioning_events set organization_name = 'x';
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] B3: service_role atualizou a trilha de plataforma';
  end if;
  raise notice '[PASS] B3: service_role NAO faz UPDATE na trilha (ACL append-only)';
end $$;
reset role;

-- ============================================================================
-- C) GATE — negativos fail-closed, SEM efeito
-- ============================================================================
do $$
declare
  v_n        integer;
  v_msg      text;
  v_antes    integer;
  v_ok       boolean;
begin
  select count(*) into v_antes from public.organizations;

  -- (C1) Nome vazio ⇒ F6_A03_INVALID_NAME (forma nova do founder valida, para
  --      que a recusa venha SO do nome da organizacao).
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000c1', '   ',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000001',
      'Admin Teste A11 C1', 'A1100011', 'admin.c1.a11@example.com');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_NAME' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C1: nome vazio deveria recusar com F6_A03_INVALID_NAME (msg=%)', v_msg;
  end if;

  -- (C2) Entrada obrigatoria nula ⇒ F6_A03_INVALID_INPUT.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      null, 'F6-A03 Sem Operacao',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000001',
      'Admin Teste A11 C2', 'A1100012', 'admin.c2.a11@example.com');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_INPUT' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C2: operation_id nulo deveria recusar com F6_A03_INVALID_INPUT (msg=%)', v_msg;
  end if;

  -- (C3) Operador com perfil NAO ativo ⇒ F6_A03_FORBIDDEN (D14/D17).
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000c3', 'F6-A03 Operador Inativo',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000004',
      'Admin Teste A11 C3', 'A1100013', 'admin.c3.a11@example.com');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_FORBIDDEN' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C3: operador disabled deveria recusar com F6_A03_FORBIDDEN (msg=%)', v_msg;
  end if;

  -- (C4) Founder SEM identidade no Auth ⇒ F6_A03_INVALID_FOUNDER (FK).
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000c4', 'F6-A03 Founder Inexistente',
      'f6a30000-0000-4000-8000-000000000009', 'f6a30000-0000-4000-8000-000000000001',
      'Admin Teste A11 C4', 'A1100014', 'admin.c4.a11@example.com');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_FOUNDER' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C4: founder inexistente deveria recusar com F6_A03_INVALID_FOUNDER (msg=%)', v_msg;
  end if;

  -- (C5) Founder com perfil NAO ativo ⇒ F6_A03_INVALID_FOUNDER.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000c5', 'F6-A03 Founder Inativo',
      'f6a30000-0000-4000-8000-000000000005', 'f6a30000-0000-4000-8000-000000000001',
      'Admin Teste A11 C5', 'A1100015', 'admin.c5.a11@example.com');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_FOUNDER' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C5: founder disabled deveria recusar com F6_A03_INVALID_FOUNDER (msg=%)', v_msg;
  end if;

  -- (C6) Nenhum negativo persistiu organizacao nem evento de provisionamento.
  select count(*) into v_n from public.organizations;
  if v_n <> v_antes then
    raise exception '[FAIL] C6: negativos alteraram organizations (% -> %)', v_antes, v_n;
  end if;
  select count(*) into v_n from public.platform_provisioning_events
   where organization_name like 'F6-A03 %';
  if v_n <> 0 then
    raise exception '[FAIL] C6: negativos gravaram % evento(s) de provisionamento', v_n;
  end if;

  raise notice '[PASS] C: negativos fail-closed (nome vazio, entrada nula, operador inativo, founder inexistente, founder inativo) SEM qualquer efeito persistido';
end $$;

-- ============================================================================
-- D) CAMINHO FELIZ — D16/D17, trilha D18 e SEPARACAO DE PLANOS
-- ============================================================================
set role service_role;
do $$
declare
  v_org      uuid;
  v_founder  uuid := 'f6a30000-0000-4000-8000-000000000002';
  v_operador uuid := 'f6a30000-0000-4000-8000-000000000003';  -- SEM perfil (D17)
  v_role     uuid;
  v_n        integer;
  v_caps     integer;
  v_memb     uuid;
begin
  select r.id into v_role from public.access_roles r
   where r.name = 'admin' and r.is_system = true and r.organization_id is null;

  -- Intencao CANONICA do provisionamento da organizacao ALFA (F6-A11/D23): os
  -- tres campos novos alimentam o hash e a ancora funcional. Guardados em
  -- `set_config` para que TODO replay use literalmente os MESMOS valores (hash
  -- identico — o replay com valores diferentes recusaria com F6_A03_CONFLICT).
  v_org := public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa', v_founder, v_operador,
    'Admin Teste A11', 'A1100001', 'admin.a11@example.com');

  perform set_config('f6a03.org_alfa', v_org::text, false);
  perform set_config('f6a03.founder_nome', 'Admin Teste A11', false);
  perform set_config('f6a03.founder_matricula', 'A1100001', false);
  perform set_config('f6a03.founder_email', 'admin.a11@example.com', false);

  -- (D1) Organizacao criada, com o nome normalizado.
  if not exists (select 1 from public.organizations o
                  where o.id = v_org and o.name = 'F6-A03 Alfa') then
    raise exception '[FAIL] D1: organizacao nao criada com o nome esperado';
  end if;

  -- (D2) D17 — o perfil GLOBAL do ATOR foi criado (o ambiente virgem e admissivel).
  if not exists (select 1 from public.user_profiles up
                  where up.id = v_operador and up.status = 'active') then
    raise exception '[FAIL] D2: perfil do operador (D17) nao foi criado';
  end if;

  -- (D3) D16 — o perfil GLOBAL do FOUNDER foi criado.
  if not exists (select 1 from public.user_profiles up
                  where up.id = v_founder and up.status = 'active') then
    raise exception '[FAIL] D3: perfil do founder (D16) nao foi criado';
  end if;
  if not exists (select 1 from public.user_profiles up
                  where up.id = v_founder and up.first_access_pending is true) then
    raise exception '[FAIL] D3.1: founder novo deveria nascer com first_access_pending=true';
  end if;
  if exists (select 1 from public.user_profiles up
              where up.id = v_operador and up.first_access_pending is true) then
    raise exception '[FAIL] D3.2: perfil preexistente do operador foi marcado como pendente';
  end if;

  -- (D4) Membership ativa do founder NA organizacao NOVA.
  select m.id into v_memb from public.user_organization_memberships m
   where m.user_profile_id = v_founder and m.organization_id = v_org and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] D4: membership do founder ausente/inativa';
  end if;

  -- (D5) Atribuicao ativa da role de sistema `admin` (origin human, autor = operador).
  if not exists (
    select 1 from public.membership_access_role_assignments a
     where a.membership_id = v_memb and a.access_role_id = v_role
       and a.organization_id = v_org and a.status = 'active'
       and a.origin = 'human'
       and a.created_by = v_operador
  ) then
    raise exception '[FAIL] D5: atribuicao da role admin ausente/incorreta';
  end if;

  -- (D5.1) F6-A14: o bootstrap cria o scope ORGANIZATION completo na
  -- assignment real; fixtures/concessoes normais nao passam por esse caminho.
  if not exists (
    select 1 from public.access_role_assignment_scopes s
     where s.assignment_id = (
       select a.id
         from public.membership_access_role_assignments a
        where a.membership_id = v_memb
          and a.access_role_id = v_role
          and a.organization_id = v_org
          and a.status = 'active'
          and a.created_by = v_operador
     )
       and s.organization_id = v_org
       and s.scope_type = 'ORGANIZATION'
       and s.status = 'active'
       and s.created_by = v_operador
  ) then
    raise exception '[FAIL] D5.1: scope ORGANIZATION do bootstrap ausente/incompleto';
  end if;

  -- (D6) Trilha D18: EXATAMENTE um `grant` humano com ator = operador.
  select count(*) into v_n from public.privilege_mutation_audit p
   where p.organization_id = v_org and p.membership_id = v_memb
     and p.access_role_id = v_role and p.action = 'grant'
     and p.actor_user_profile_id = v_operador;
  if v_n <> 1 then
    raise exception '[FAIL] D6: trilha D18 deveria ter 1 grant do operador (tem %)', v_n;
  end if;

  -- (D7) Evento de provisionamento: EXATAMENTE um, com hash canonico e autores.
  select count(*) into v_n from public.platform_provisioning_events e
   where e.operation_id = 'f6a3b000-0000-4000-8000-000000000001'
     and e.organization_id = v_org
     and e.organization_name = 'F6-A03 Alfa'
     and e.actor_user_profile_id = v_operador
     and e.founder_user_profile_id = v_founder
     and e.payload_hash ~ '^[0-9a-f]{64}$';
  if v_n <> 1 then
    raise exception '[FAIL] D7: evento de provisionamento ausente/incompleto (n=%)', v_n;
  end if;

  -- (D8) O founder e ADMIN do tenant novo e resolve as capabilities ESPERADAS:
  --      as 9 do bundle `admin` MAIS `observation.read`, provisionada
  --      AUTOMATICAMENTE pelo lifecycle do avaliado (F5-11 P5.1/P5.3: o trigger
  --      do vinculo F5-02 chama `f5_11_p5_1_provisionar_observacoes_avaliado`,
  --      cujo bundle e EXATAMENTE `observation.read` e que, pela P5.4, e
  --      concedida SOMENTE por elegibilidade — nunca por caminho administrativo).
  --      A partir da F6-A11/D24 o primeiro Admin TAMBEM e colaborador do tenant,
  --      entao essa elegibilidade passa a valer para ele; a assercao abaixo e
  --      pelo CONJUNTO EXATO, para que nenhuma capability fora dessas apareca.
  if not public.usuario_eh_administrador(v_founder, v_org) then
    raise exception '[FAIL] D8: founder nao e administrador do tenant criado';
  end if;

  select count(*) into v_caps
    from public.resolver_capabilities_efetivas(v_founder, v_org) c
   where c.capability_code <> 'observation.read'
     and c.capability_code not in (
       select cap.code
         from public.access_role_capabilities rc
         join public.access_roles r on r.id = rc.access_role_id
         join public.capabilities cap on cap.id = rc.capability_id
        where r.name = 'admin' and r.is_system = true
     );
  if v_caps <> 0 then
    raise exception '[FAIL] D8: founder resolve % capability(ies) fora do bundle admin + observation.read', v_caps;
  end if;

  select count(*) into v_caps from public.resolver_capabilities_efetivas(v_founder, v_org) c;
  if v_caps <> 10 then
    raise exception '[FAIL] D8: founder resolve % capabilities (esperado 10 = 9 do bundle admin + observation.read do lifecycle do avaliado)', v_caps;
  end if;

  -- (D9) SEPARACAO DE PLANOS: o OPERADOR de plataforma NAO ganhou nada no tenant.
  if exists (select 1 from public.user_organization_memberships m
              where m.user_profile_id = v_operador and m.organization_id = v_org) then
    raise exception '[FAIL] D9: operador de plataforma virou membro do tenant criado';
  end if;
  select count(*) into v_caps from public.resolver_capabilities_efetivas(v_operador, v_org) c;
  if v_caps <> 0 then
    raise exception '[FAIL] D9: operador sem membership resolveu % capabilities', v_caps;
  end if;

  raise notice '[PASS] D: caminho feliz OK — organizacao criada, perfis globais do founder (D16) e do ator (D17), membership ativa, role admin pelo primitivo F4-01, trilha D18 com ator humano e SEPARACAO DE PLANOS (operador sem autoridade no tenant)';
end $$;
reset role;

-- ============================================================================
-- D3.3) F6-A20 — perfil preexistente permanece inalterado.
set role service_role;
do $$
declare
  v_operador uuid := 'f6a30000-0000-4000-8000-000000000003';
  v_pendente boolean;
begin
  select up.first_access_pending into v_pendente
    from public.user_profiles up where up.id = v_operador;
  if v_pendente is distinct from false then
    raise exception '[FAIL] D3.3: precondicao do perfil preexistente invalida (%)', v_pendente;
  end if;

  perform public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-0000000000d3', 'F6-A03 Founder Preexistente',
    v_operador, v_operador, 'Operador Preexistente', 'A1100003',
    'operador.novo.f6-a03@example.invalid'
  );

  select up.first_access_pending into v_pendente
    from public.user_profiles up where up.id = v_operador;
  if v_pendente is distinct from false then
    raise exception '[FAIL] D3.3: perfil preexistente foi alterado para pendente';
  end if;
end $$;
reset role;

-- ============================================================================
-- D24) ANCORA FUNCIONAL do primeiro Admin (F6-A11) — criada NA MESMA TRANSACAO
-- ============================================================================
-- Efeitos canonicos exigidos: `collaborators` + `collaborator_identifiers`
-- (linha ABERTA = matricula) + `collaborator_status_periods` + evento
-- `ADMISSAO` (ator = membership do FOUNDER) + `membership_collaborator_links`
-- ATIVO da membership do founder (docs/F6-A11-desenho-tecnico.md, D23/D24).
do $$
declare
  v_org     uuid := current_setting('f6a03.org_alfa')::uuid;
  v_founder uuid := 'f6a30000-0000-4000-8000-000000000002';
  v_memb    uuid;
  v_collab  uuid;
  v_n       integer;
begin
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_founder and m.organization_id = v_org
     and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] D24: membership ativa do founder nao resolvida';
  end if;

  -- (D24.1) EXATAMENTE 1 colaborador na organizacao, com o nome informado
  --         (trim) e o e-mail informado normalizado em minusculas (D23).
  select count(*) into v_n
    from public.collaborators c
   where c.organization_id = v_org
     and c.full_name = btrim(current_setting('f6a03.founder_nome'))
     and c.email = lower(btrim(current_setting('f6a03.founder_email')))
     and c.admission_date is null;
  if v_n <> 1 then
    raise exception '[FAIL] D24: colaborador do founder com nome/email informados esperado=1, encontrado=%', v_n;
  end if;
  select count(*) into v_n from public.collaborators c where c.organization_id = v_org;
  if v_n <> 1 then
    raise exception '[FAIL] D24: organizacao com % colaborador(es) (esperado 1)', v_n;
  end if;
  select c.id into v_collab from public.collaborators c where c.organization_id = v_org;

  -- (D24.2) EXATAMENTE 1 identificador ABERTO com business_code = matricula.
  select count(*) into v_n
    from public.collaborator_identifiers i
   where i.organization_id = v_org
     and i.collaborator_id = v_collab
     and i.valid_to is null
     and i.business_code = btrim(current_setting('f6a03.founder_matricula'));
  if v_n <> 1 then
    raise exception '[FAIL] D24: identificador ABERTO com business_code = matricula esperado=1, encontrado=%', v_n;
  end if;

  -- (D24.3) EXATAMENTE 1 periodo de status `active` ABERTO.
  select count(*) into v_n
    from public.collaborator_status_periods s
   where s.collaborator_id = v_collab
     and s.status = 'active'
     and s.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] D24: periodo de status active ABERTO esperado=1, encontrado=%', v_n;
  end if;

  -- (D24.4) EXATAMENTE 1 evento `ADMISSAO` com ator = FOUNDER e
  --         actor_membership_id = a membership do founder NA ORGANIZACAO.
  select count(*) into v_n
    from public.collaborator_events e
   where e.organization_id = v_org
     and e.collaborator_id = v_collab
     and e.event_type = 'ADMISSAO'
     and e.actor_user_profile_id = v_founder
     and e.actor_membership_id = v_memb
     and e.operation_id = 'f6a3b000-0000-4000-8000-000000000001';
  if v_n <> 1 then
    raise exception '[FAIL] D24: evento ADMISSAO com autoria do founder esperado=1, encontrado=%', v_n;
  end if;

  -- (D24.5) EXATAMENTE 1 vinculo ATIVO membership do founder -> colaborador.
  select count(*) into v_n
    from public.membership_collaborator_links l
   where l.membership_id = v_memb
     and l.organization_id = v_org
     and l.collaborator_id = v_collab
     and l.status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] D24: vinculo ATIVO membership->colaborador esperado=1, encontrado=%', v_n;
  end if;
  select count(*) into v_n from public.membership_collaborator_links l
   where l.organization_id = v_org and l.status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] D24: organizacao com % vinculo(s) ativo(s) (esperado 1)', v_n;
  end if;

  -- (D24.6) O resolver SOBERANO da F5-02 passa a resolver a ancora do founder.
  select count(*) into v_n
    from public.resolver_collaborador_vinculado(v_founder, v_org) r
   where r.collaborator_id = v_collab;
  if v_n <> 1 then
    raise exception '[FAIL] D24: resolver_collaborator_vinculado nao resolve o colaborador do founder (%)', v_n;
  end if;

  raise notice '[PASS] D24: ancora funcional do primeiro Admin criada na MESMA transacao (1 colaborador com nome/email informados, 1 identificador ABERTO = matricula, 1 periodo active ABERTO, 1 evento ADMISSAO com ator = membership do founder, 1 vinculo F5-02 ATIVO resolvido pelo resolver soberano)';
end $$;

-- ============================================================================
-- C7-C9) D25 — ROLLBACK FAIL-CLOSED da FORMA NOVA do founder
-- ----------------------------------------------------------------------------
-- Executado DE PROPOSITO depois de D: o founder `...0002` ja possui perfil ATIVO,
-- de modo que a recusa so pode vir da forma invalida (nome vazio, matricula
-- vazia, e-mail sem `@`) — nunca da checagem de estado do founder. Nenhuma das
-- tres tentativas pode deixar organizacao, colaborador, identificador, periodo,
-- evento ou vinculo.
-- ============================================================================
do $$
declare
  v_founder   uuid := 'f6a30000-0000-4000-8000-000000000002';
  v_operador  uuid := 'f6a30000-0000-4000-8000-000000000001';  -- perfil ATIVO
  v_ok        boolean;
  v_msg       text;
  v_msg_falha text;
  v_antes_org integer;
  v_antes_col integer;
  v_antes_ide integer;
  v_antes_per integer;
  v_antes_lnk integer;
  v_n         integer;
begin
  select count(*) into v_antes_org from public.organizations;
  select count(*) into v_antes_col from public.collaborators;
  select count(*) into v_antes_ide from public.collaborator_identifiers;
  select count(*) into v_antes_per from public.collaborator_status_periods;
  select count(*) into v_antes_lnk from public.membership_collaborator_links;

  -- (C7) founder_full_name vazio (apenas espacos) ⇒ F6_A03_INVALID_FOUNDER.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000f1', 'F6-A03 Rollback Nome Vazio',
      v_founder, v_operador,
      '   ', 'A1100031', 'rollback.nome.a11@example.com');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_FOUNDER' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C7: founder_full_name vazio deveria recusar com F6_A03_INVALID_FOUNDER (msg=%)', v_msg;
  end if;

  -- (C8) founder_matricula vazia (apenas espacos) ⇒ F6_A03_INVALID_FOUNDER.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000f2', 'F6-A03 Rollback Matricula Vazia',
      v_founder, v_operador,
      'Rollback Matricula A11', '   ', 'rollback.matricula.a11@example.com');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_FOUNDER' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C8: founder_matricula vazia deveria recusar com F6_A03_INVALID_FOUNDER (msg=%)', v_msg;
  end if;

  -- (C9) founder_email sem `@` ⇒ F6_A03_INVALID_FOUNDER.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000f3', 'F6-A03 Rollback Email Invalido',
      v_founder, v_operador,
      'Rollback Email A11', 'A1100033', 'sem-arroba.example.com');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_FOUNDER' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C9: founder_email sem @ deveria recusar com F6_A03_INVALID_FOUNDER (msg=%)', v_msg;
  end if;

  -- (C10) As tres recusas nao deixaram QUALQUER efeito persistido.
  v_msg_falha := null;
  select count(*) into v_n from public.organizations;
  if v_n <> v_antes_org then v_msg_falha := 'organizations'; end if;
  select count(*) into v_n from public.collaborators;
  if v_n <> v_antes_col then v_msg_falha := coalesce(v_msg_falha || '+', '') || 'collaborators'; end if;
  select count(*) into v_n from public.collaborator_identifiers;
  if v_n <> v_antes_ide then v_msg_falha := coalesce(v_msg_falha || '+', '') || 'collaborator_identifiers'; end if;
  select count(*) into v_n from public.collaborator_status_periods;
  if v_n <> v_antes_per then v_msg_falha := coalesce(v_msg_falha || '+', '') || 'collaborator_status_periods'; end if;
  select count(*) into v_n from public.membership_collaborator_links;
  if v_n <> v_antes_lnk then v_msg_falha := coalesce(v_msg_falha || '+', '') || 'membership_collaborator_links'; end if;
  select count(*) into v_n from public.platform_provisioning_events e
   where e.operation_id in ('f6a3b000-0000-4000-8000-0000000000f1',
                            'f6a3b000-0000-4000-8000-0000000000f2',
                            'f6a3b000-0000-4000-8000-0000000000f3');
  if v_n <> 0 then v_msg_falha := coalesce(v_msg_falha || '+', '') || 'platform_provisioning_events'; end if;
  if v_msg_falha is not null then
    raise exception '[FAIL] C10: rollback da forma invalida deixou efeito em %', v_msg_falha;
  end if;

  raise notice '[PASS] C7-C9: rollback fail-closed da FORMA NOVA (founder_full_name vazio, founder_matricula vazia, founder_email sem @) — F6_A03_INVALID_FOUNDER e ZERO efeito (organizacao/colaborador/identificador/periodo/vinculo/trilha)';
end $$;

-- ============================================================================
-- E) IDEMPOTENCIA — replay verificado (D6)
-- ============================================================================
set role service_role;
do $$
declare
  v_org      uuid := current_setting('f6a03.org_alfa')::uuid;
  v_replay   uuid;
  v_msg      text;
  v_n        integer;
begin
  -- (E1) Mesmo payload ⇒ MESMO organization_id, sem novo efeito. Os tres campos
  --      novos vem de `current_setting`, ou seja, sao LITERALMENTE os mesmos da
  --      primeira chamada (hash identico ⇒ replay, nunca CONFLICT).
  v_replay := public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa',
    'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000003',
    current_setting('f6a03.founder_nome'), current_setting('f6a03.founder_matricula'),
    current_setting('f6a03.founder_email'));
  if v_replay is distinct from v_org then
    raise exception '[FAIL] E1: replay devolveu % (esperado %)', v_replay, v_org;
  end if;

  select count(*) into v_n from public.organizations o where o.name = 'F6-A03 Alfa';
  if v_n <> 1 then
    raise exception '[FAIL] E1: replay criou organizacao duplicada (%)', v_n;
  end if;
  select count(*) into v_n from public.platform_provisioning_events e
   where e.operation_id = 'f6a3b000-0000-4000-8000-000000000001';
  if v_n <> 1 then
    raise exception '[FAIL] E1: replay duplicou o evento de provisionamento (%)', v_n;
  end if;
  -- A trilha D18 DO PROVISIONAMENTO e o `grant` HUMANO da role `admin` pelo
  -- operador: EXATAMENTE 1 — e o replay (ja executado acima) nao acrescentou nada.
  -- A contagem NAO pode ser global na organizacao: desde a F6-A11/D24 o founder
  -- TAMBEM e colaborador do tenant e o lifecycle do avaliado (F5-11 P5.1/P5.3)
  -- concede `observacoes_avaliado` automaticamente ao criar o vinculo F5-02,
  -- gravando `system_grant` com ator NULL (F5-11 P5.4, `20260936000000:300-303`).
  select count(*) into v_n from public.privilege_mutation_audit p
   where p.organization_id = v_org
     and p.action = 'grant'
     and p.actor_user_profile_id = 'f6a30000-0000-4000-8000-000000000003'
     and p.access_role_id = (
       select r.id from public.access_roles r
        where r.name = 'admin' and r.is_system = true
     );
  if v_n <> 1 then
    raise exception '[FAIL] E1: trilha D18 do grant humano `admin` esperada=1, encontrada=%', v_n;
  end if;

  -- (E2) Mesmo operation_id com payload DIFERENTE ⇒ RECUSA fail-closed.
  --      A divergencia e INTENCIONAL: o nome da organizacao E a matricula do
  --      founder diferem da intencao registrada (o hash canonico da F6-A11 cobre
  --      founder_full_name/matricula/email — D25).
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa (divergente)',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000003',
      current_setting('f6a03.founder_nome'), 'A1100099',  -- matricula divergente (intencional)
      current_setting('f6a03.founder_email'));
    raise exception '[FAIL] E2: payload divergente aceito no mesmo operation_id';
  exception when others then
    v_msg := SQLERRM;
    if position('F6_A03_CONFLICT' in v_msg) = 0 then
      raise exception '[FAIL] E2: causa inesperada (%)', v_msg;
    end if;
  end;

  select count(*) into v_n from public.organizations o where o.name like 'F6-A03 Alfa%';
  if v_n <> 1 then
    raise exception '[FAIL] E2: divergencia criou organizacao extra (%)', v_n;
  end if;

  -- (E3) O trigger append-only vale tambem no caminho do OWNER (nao so a ACL);
  -- provado em SUBTRANSACAO controlada logo abaixo.
end $$;
reset role;

do $$
declare v_msg text;
begin
  begin
    update public.platform_provisioning_events
       set organization_name = 'F6-A03 adulterado'
     where operation_id = 'f6a3b000-0000-4000-8000-000000000001';
    raise exception '[FAIL] E3: trigger append-only nao bloqueou o UPDATE do owner';
  exception when others then
    v_msg := SQLERRM;
    if position('append-only' in v_msg) = 0 then
      raise exception '[FAIL] E3: causa inesperada no append-only (%)', v_msg;
    end if;
  end;
  raise notice '[PASS] E3: trigger append-only bloqueia UPDATE da trilha inclusive para o owner';
end $$;

-- (E4) REPLAY e ESTAVEL: repetir a MESMA intencao devolve o MESMO
--      `organization_id` mesmo que o perfil do primeiro Admin tenha sido
--      INATIVADO depois (a idempotencia e resolvida ANTES da validacao de estado
--      do founder, conforme o §5 do contrato) — e operacao NOVA com founder
--      inativo continua RECUSADA (fail-closed).
set role service_role;
do $$
declare
  v_org    uuid := current_setting('f6a03.org_alfa')::uuid;
  v_replay uuid;
  v_n      integer;
  v_msg    text;
  v_ok     boolean;
begin
  update public.user_profiles set status = 'disabled'
   where id = 'f6a30000-0000-4000-8000-000000000002';

  v_replay := public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa',
    'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000003',
    current_setting('f6a03.founder_nome'), current_setting('f6a03.founder_matricula'),
    current_setting('f6a03.founder_email'));
  if v_replay is distinct from v_org then
    raise exception '[FAIL] E4: replay com founder inativo devolveu % (esperado %)', v_replay, v_org;
  end if;

  select count(*) into v_n from public.platform_provisioning_events e
   where e.operation_id = 'f6a3b000-0000-4000-8000-000000000001';
  if v_n <> 1 then
    raise exception '[FAIL] E4: replay com founder inativo duplicou o evento (%)', v_n;
  end if;

  -- Operacao NOVA com o MESMO founder inativo continua fail-closed.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000e4', 'F6-A03 Founder Inativo Nova',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000003',
      'Admin Inativo Nova A11', 'A1100004', 'admin.inativo.nova.a11@example.com');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_FOUNDER' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] E4: operacao NOVA com founder inativo deveria recusar com F6_A03_INVALID_FOUNDER (msg=%)', v_msg;
  end if;

  -- Reativa o perfil: os blocos seguintes (F/G) usam o founder ativo.
  update public.user_profiles set status = 'active'
   where id = 'f6a30000-0000-4000-8000-000000000002';

  raise notice '[PASS] E4: REPLAY ESTAVEL (mesmo com o primeiro Admin inativado depois) e operacao NOVA com founder inativo segue fail-closed';
end $$;
reset role;

-- ============================================================================
-- E5/E6) D24/D25 — replay SEM duplicacao da ancora e divergencia em CAMPO NOVO
-- ============================================================================
do $$
declare
  v_org     uuid := current_setting('f6a03.org_alfa')::uuid;
  v_founder uuid := 'f6a30000-0000-4000-8000-000000000002';
  v_memb    uuid;
  v_collab  uuid;
  v_collab2 uuid;
  v_replay  uuid;
  v_msg     text;
  v_n       integer;
begin
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_founder and m.organization_id = v_org
     and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] E5: membership ativa do founder nao resolvida';
  end if;
  select c.id into v_collab from public.collaborators c where c.organization_id = v_org;
  if v_collab is null then
    raise exception '[FAIL] E5: colaborador do founder nao resolvido antes do replay';
  end if;

  -- (E5) REPLAY IDENTICO (mesmo hash, ja com os campos novos) ⇒ MESMO
  --      organization_id e ZERO linhas novas da ancora funcional (1/1/1/1/1).
  v_replay := public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa', v_founder,
    'f6a30000-0000-4000-8000-000000000003',
    current_setting('f6a03.founder_nome'), current_setting('f6a03.founder_matricula'),
    current_setting('f6a03.founder_email'));
  if v_replay is distinct from v_org then
    raise exception '[FAIL] E5: replay devolveu % (esperado %)', v_replay, v_org;
  end if;

  select count(*) into v_n from public.collaborators c where c.organization_id = v_org;
  if v_n <> 1 then
    raise exception '[FAIL] E5: replay duplicou colaborador (n=%)', v_n;
  end if;
  select count(*) into v_n from public.collaborator_identifiers i
   where i.organization_id = v_org and i.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] E5: replay duplicou identificador ABERTO (n=%)', v_n;
  end if;
  select count(*) into v_n
    from public.collaborator_status_periods s
    join public.collaborators c on c.id = s.collaborator_id
   where c.organization_id = v_org and s.status = 'active' and s.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] E5: replay duplicou periodo de status active ABERTO (n=%)', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.event_type = 'ADMISSAO';
  if v_n <> 1 then
    raise exception '[FAIL] E5: replay duplicou evento ADMISSAO (n=%)', v_n;
  end if;
  select count(*) into v_n from public.membership_collaborator_links l
   where l.organization_id = v_org and l.status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] E5: replay duplicou vinculo ATIVO (n=%)', v_n;
  end if;

  select c.id into v_collab2 from public.collaborators c where c.organization_id = v_org;
  if v_collab2 is distinct from v_collab then
    raise exception '[FAIL] E5: replay trocou o colaborador do founder (% -> %)', v_collab, v_collab2;
  end if;
  select count(*) into v_n
    from public.membership_collaborator_links l
   where l.membership_id = v_memb and l.collaborator_id = v_collab
     and l.organization_id = v_org and l.status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] E5: vinculo ATIVO do founder alterado pelo replay (n=%)', v_n;
  end if;

  raise notice '[PASS] E5: replay identico sem duplicacao da ancora funcional (1 colaborador / 1 identificador ABERTO / 1 periodo active / 1 evento ADMISSAO / 1 vinculo ATIVO — mesmo colaborador e mesmo vinculo)';

  -- (E6) DIVERGENCIA SOMENTE EM CAMPO NOVO: MESMO organization_name, MESMO
  --      founder/ator e operation_id JA USADO; APENAS a matricula difere ⇒
  --      RECUSA fail-closed. Prova que o hash canonico COBRE
  --      `founder_matricula` (antes da ampliacao da F6-A11 o hash nao a
  --      incluia e isto teria passado como replay silencioso). A divergencia e
  --      INTENCIONAL.
  v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa', v_founder,
      'f6a30000-0000-4000-8000-000000000003',
      current_setting('f6a03.founder_nome'), 'A1100098',  -- divergencia INTENCIONAL
      current_setting('f6a03.founder_email'));
    raise exception '[FAIL] E6: divergencia SOMENTE na matricula foi aceita como replay';
  exception when others then
    v_msg := SQLERRM;
    if position('F6_A03_CONFLICT' in v_msg) = 0 then
      raise exception '[FAIL] E6: causa inesperada (%)', v_msg;
    end if;
  end;

  select count(*) into v_n from public.collaborators c where c.organization_id = v_org;
  if v_n <> 1 then
    raise exception '[FAIL] E6: divergencia criou colaborador extra (n=%)', v_n;
  end if;
  select count(*) into v_n from public.collaborator_identifiers i where i.organization_id = v_org;
  if v_n <> 1 then
    raise exception '[FAIL] E6: divergencia criou identificador extra (n=%)', v_n;
  end if;
  select count(*) into v_n from public.membership_collaborator_links l where l.organization_id = v_org;
  if v_n <> 1 then
    raise exception '[FAIL] E6: divergencia criou vinculo extra (n=%)', v_n;
  end if;
  select count(*) into v_n from public.platform_provisioning_events e
   where e.operation_id = 'f6a3b000-0000-4000-8000-000000000001';
  if v_n <> 1 then
    raise exception '[FAIL] E6: divergencia duplicou o evento de provisionamento (n=%)', v_n;
  end if;

  raise notice '[PASS] E6: divergencia SOMENTE em campo NOVO do hash canonico (founder_matricula) recusada com F6_A03_CONFLICT e SEM qualquer efeito';
end $$;

-- ============================================================================
-- F) ISOLAMENTO — estado preexistente intocado + SEGUNDA organizacao
-- ============================================================================
do $$
declare
  v_legado    uuid := 'f6a30000-0000-4000-8000-0000000000a1';
  v_org_alfa  uuid := current_setting('f6a03.org_alfa')::uuid;
  v_n         integer;
begin
  -- (F1) A organizacao LEGADO permanece com nome, membership e atribuicao originais.
  if not exists (select 1 from public.organizations o
                  where o.id = v_legado and o.name = 'F6-A03 Legado (preexistente)') then
    raise exception '[FAIL] F1: organizacao preexistente alterada';
  end if;
  select count(*) into v_n
    from public.user_organization_memberships m
    join public.membership_access_role_assignments a on a.membership_id = m.id
   where m.organization_id = v_legado and m.status = 'active' and a.status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] F1: membership/atribuicao preexistente alterada (n=%)', v_n;
  end if;

  -- (F2) Nada do tenant novo referencia o LEGADO e vice-versa.
  select count(*) into v_n from public.user_organization_memberships m
   where m.organization_id = v_org_alfa and m.organization_id = v_legado;
  if v_n <> 0 then
    raise exception '[FAIL] F2: cruzamento de tenants detectado';
  end if;

  -- (F3) Nenhum dado de fixture LEGADO apareceu no tenant novo (vazio por construcao).
  select count(*) into v_n from public.user_organization_memberships m
   where m.organization_id = v_org_alfa;
  if v_n <> 1 then
    raise exception '[FAIL] F3: tenant novo deveria ter exatamente 1 membership (tem %)', v_n;
  end if;

  raise notice '[PASS] F1/F2/F3: estado preexistente INTOCADO e tenant novo isolado';
end $$;

-- (F4) Segunda organizacao para o MESMO founder (GREENFIELD usa N organizacoes).
set role service_role;
do $$
declare
  v_founder uuid := 'f6a30000-0000-4000-8000-000000000002';
  v_operador uuid := 'f6a30000-0000-4000-8000-000000000003';
  v_org_beta uuid;
  v_n integer;
begin
  v_org_beta := public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-000000000002', 'F6-A03 Beta', v_founder, v_operador,
    'Admin Teste A11 Beta', 'A1100002', 'admin.beta.a11@example.com');

  if v_org_beta = current_setting('f6a03.org_alfa')::uuid then
    raise exception '[FAIL] F4: segunda organizacao reutilizou o id da primeira';
  end if;
  if not public.usuario_eh_administrador(v_founder, v_org_beta) then
    raise exception '[FAIL] F4: founder nao e admin da segunda organizacao';
  end if;
  select count(*) into v_n from public.user_organization_memberships m
   where m.user_profile_id = v_founder and m.status = 'active';
  if v_n <> 2 then
    raise exception '[FAIL] F4: founder deveria ter 2 memberships ativas (tem %)', v_n;
  end if;

  -- (F4.b) A segunda organizacao ganha a PROPRIA ancora funcional (D24): o
  --        colaborador do founder e POR TENANT (D22), sem vazar dados do Alfa.
  select count(*) into v_n from public.collaborators c
   where c.organization_id = v_org_beta
     and c.full_name = 'Admin Teste A11 Beta'
     and c.email = 'admin.beta.a11@example.com';
  if v_n <> 1 then
    raise exception '[FAIL] F4: colaborador do founder na 2a organizacao esperado=1, encontrado=%', v_n;
  end if;
  select count(*) into v_n from public.collaborator_identifiers i
   where i.organization_id = v_org_beta and i.valid_to is null
     and i.business_code = 'A1100002';
  if v_n <> 1 then
    raise exception '[FAIL] F4: identificador ABERTO da 2a organizacao esperado=1, encontrado=%', v_n;
  end if;
  select count(*) into v_n from public.membership_collaborator_links l
   where l.organization_id = v_org_beta and l.status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] F4: vinculo ATIVO da 2a organizacao esperado=1, encontrado=%', v_n;
  end if;

  raise notice '[PASS] F4: segunda organizacao provisionada para o mesmo founder com ancora funcional PROPRIA (isolamento por tenant preservado)';
end $$;
reset role;

-- ============================================================================
-- G) HIGIENE — nenhum residuo do cenario
-- ============================================================================
-- F6-A14: scopes sao filhos da assignment; removê-los antes da assignment
-- preserva a FK e trata o scope ORGANIZATION do bootstrap como parte legitima
-- do fixture, sem alterar a implementacao ou enfraquecer a restricao.
delete from public.access_role_assignment_scopes s
 using public.membership_access_role_assignments a,
       public.user_organization_memberships m,
       public.organizations o
 where s.assignment_id = a.id
   and a.membership_id = m.id
   and m.organization_id = o.id
   and (o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.membership_access_role_assignments a
 using public.user_organization_memberships m, public.organizations o
 where a.membership_id = m.id and m.organization_id = o.id
   and (o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.privilege_mutation_audit
 where organization_id in (
   select o.id from public.organizations o
    where o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.platform_provisioning_events
 where organization_name like 'F6-A03 %'
    or actor_user_profile_id::text like 'f6a30000-%'
    or founder_user_profile_id::text like 'f6a30000-%';

-- Ancora funcional (F5-02/F5-07): TODAS as FKs envolvidas sao ON DELETE
-- RESTRICT, entao os filhos saem ANTES de membership/colaborador/organizacao.
-- A propria conclusao da higiene ja prova a ausencia de residuo: uma linha
-- remanescente abortaria estes DELETEs.
delete from public.membership_collaborator_links
 where organization_id in (
   select o.id from public.organizations o
    where o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.collaborator_events
 where organization_id in (
   select o.id from public.organizations o
    where o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.collaborator_identifiers
 where organization_id in (
   select o.id from public.organizations o
    where o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.collaborator_status_periods
 where collaborator_id in (
   select c.id from public.collaborators c
    where c.organization_id in (
      select o.id from public.organizations o
       where o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1'));

delete from public.collaborators
 where organization_id in (
   select o.id from public.organizations o
    where o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.user_organization_memberships
 where organization_id in (
   select o.id from public.organizations o
    where o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.user_profiles where id::text like 'f6a30000-%';

delete from public.organizations
 where name like 'F6-A03 %' or id = 'f6a30000-0000-4000-8000-0000000000a1';

delete from auth.users where id::text like 'f6a30000-%';

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.organizations where name like 'F6-A03 %';
  if v_n <> 0 then raise exception '[FAIL] G: organizacoes residuais (%)', v_n; end if;
  select count(*) into v_n from public.platform_provisioning_events
   where organization_name like 'F6-A03 %';
  if v_n <> 0 then raise exception '[FAIL] G: eventos residuais (%)', v_n; end if;
  select count(*) into v_n from public.user_profiles where id::text like 'f6a30000-%';
  if v_n <> 0 then raise exception '[FAIL] G: perfis residuais (%)', v_n; end if;
  select count(*) into v_n from auth.users where id::text like 'f6a30000-%';
  if v_n <> 0 then raise exception '[FAIL] G: identidades residuais (%)', v_n; end if;

  -- (G.b) Ancora funcional (F6-A11): nenhum residuo de colaborador,
  --       identificador, evento de colaborador ou vinculo orfao.
  select count(*) into v_n from public.collaborators where email like '%.a11@example.com';
  if v_n <> 0 then raise exception '[FAIL] G: colaboradores residuais (%)', v_n; end if;
  select count(*) into v_n from public.collaborator_identifiers
   where business_code in ('A1100001', 'A1100002');
  if v_n <> 0 then raise exception '[FAIL] G: identificadores residuais (%)', v_n; end if;
  select count(*) into v_n from public.collaborator_events
   where operation_id in ('f6a3b000-0000-4000-8000-000000000001',
                          'f6a3b000-0000-4000-8000-000000000002');
  if v_n <> 0 then raise exception '[FAIL] G: eventos de colaborador residuais (%)', v_n; end if;
  select count(*) into v_n from public.membership_collaborator_links l
   where not exists (select 1 from public.collaborators c where c.id = l.collaborator_id);
  if v_n <> 0 then raise exception '[FAIL] G: vinculos orfaos (%)', v_n; end if;

  raise notice '[PASS] G: higiene completa — nenhum residuo do cenario F6-A03 (inclusive da ancora funcional do primeiro Admin)';
  raise notice '[PASS] F6-A03/F6-A11: A/B/C/C7-C9/D/D24/E/E5-E6/F/G concluidos — bootstrap de plataforma validado (RLS+ACL, append-only, gate fail-closed, D16/D17, separacao de planos, assinatura NOVA sem sobrecarga, ancora funcional D24, rollback da forma nova, idempotencia por replay sem duplicacao e isolamento multi-tenant)';
end $$;
