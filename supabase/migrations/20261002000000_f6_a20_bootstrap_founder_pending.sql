-- F6-A20 / Issue #310: primeiro acesso do founder provisionado.
-- Migration aditiva com definição explícita da RPC canônica vigente.

create or replace function public.organizacao_provisionar_inicial(
  p_operation_id            uuid,
  p_organization_name       text,
  p_founder_user_profile_id uuid,
  p_actor_user_profile_id   uuid,
  p_founder_full_name       text,
  p_founder_matricula       text,
  p_founder_email           text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_nome          text;
  v_full_name     text;
  v_matricula     text;
  v_email         text;
  v_hash          text;
  v_org           uuid;
  v_evento_id     uuid;
  v_evento        public.platform_provisioning_events%rowtype;
  v_role          uuid;
  v_status_ator   text;
  v_membership    uuid;
  v_collaborator  uuid;
  v_assignment    uuid;
begin
  -- (1) FORMA do payload - nada aqui e autoridade.
  if p_operation_id is null
     or p_actor_user_profile_id is null
     or p_founder_user_profile_id is null then
    raise exception 'F6_A03_INVALID_INPUT: operation_id, ator e primeiro Admin sao obrigatorios';
  end if;

  v_nome := btrim(coalesce(p_organization_name, ''));
  if v_nome = '' then
    raise exception 'F6_A03_INVALID_NAME: nome da organizacao obrigatorio';
  end if;

  -- D23: identidade funcional minima do primeiro Admin. A FORMA e validada aqui
  -- (nao depende de estado); o ESTADO do founder e validado no passo (6), depois
  -- da idempotencia, conforme a ordem do contrato Â§5.
  v_full_name := btrim(coalesce(p_founder_full_name, ''));
  if v_full_name = '' then
    raise exception 'F6_A03_INVALID_FOUNDER: nome humano do primeiro Admin obrigatorio';
  end if;

  v_matricula := btrim(coalesce(p_founder_matricula, ''));
  if v_matricula = '' then
    raise exception 'F6_A03_INVALID_FOUNDER: matricula do primeiro Admin obrigatoria';
  end if;

  v_email := lower(btrim(coalesce(p_founder_email, '')));
  if v_email = '' or position('@' in v_email) <= 1 then
    raise exception 'F6_A03_INVALID_FOUNDER: e-mail da identidade do primeiro Admin indisponivel';
  end if;

  -- (2) HASH canonico da INTENCAO, derivado SERVER-SIDE (nunca do corpo).
  --     D25: a identidade funcional minima participa do hash - retry com o mesmo
  --     `operation_id` e nome/matricula/e-mail diferentes e RECUSADO fail-closed.
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'organizacao_provisionar_inicial',
    'organization_name', v_nome,
    'founder_user_profile_id', p_founder_user_profile_id,
    'founder_full_name', v_full_name,
    'founder_matricula', v_matricula,
    'founder_email', v_email
  )::text, 'UTF8')), 'hex');

  -- (3) GATE DE PLATAFORMA no banco (D14/D17): o ator precisa ser admissivel.
  --     Perfil AUSENTE e admissivel (o ambiente virgem nao tem perfil ainda e a
  --     linha e criada no passo (8)); perfil EXISTENTE e nao ativo RECUSA.
  --     A autoridade nominal da allowlist e da fronteira server-side (Edge): a
  --     RPC e contida por CONSTRUCAO (D3) e nunca e alcancavel por `authenticated`
  --     (EXECUTE so service_role).
  select up.status into v_status_ator
    from public.user_profiles up
   where up.id = p_actor_user_profile_id;
  if found and v_status_ator <> 'active' then
    raise exception 'F6_A03_FORBIDDEN: perfil do operador de plataforma nao esta ativo';
  end if;

  -- (4) Role de sistema `admin` resolvida NOMINALMENTE (D9/D13 - nunca por UUID).
  select r.id into v_role
    from public.access_roles r
   where r.name = 'admin'
     and r.is_system = true
     and r.organization_id is null
     and r.status = 'active';
  if v_role is null then
    raise exception 'F6_A03_INTERNAL: role de sistema admin indisponivel';
  end if;

  -- (5) IDEMPOTENCIA - ponto UNICO de serializacao (unique em operation_id).
  --     O id da organizacao e gerado pelo BANCO (convencao F1-02) e ja entra na
  --     trilha: e ele que torna o replay devolvivel sem novo efeito.
  --
  --     ORDEM (contrato Â§5, passos `a`->`b`): a resolucao da idempotencia vem
  --     ANTES de qualquer validacao/escrita que dependa do ESTADO ATUAL do
  --     founder. Assim o REPLAY e ESTAVEL e sem efeito: repetir a MESMA intencao
  --     devolve o mesmo `organization_id` mesmo que o perfil do primeiro Admin
  --     tenha sido inativado depois (fail-closed permanece para operacao NOVA).
  v_org := gen_random_uuid();

  insert into public.platform_provisioning_events (
    operation_id, payload_hash, organization_id, organization_name,
    actor_user_profile_id, founder_user_profile_id
  ) values (
    p_operation_id, v_hash, v_org, v_nome,
    p_actor_user_profile_id, p_founder_user_profile_id
  )
  on conflict (operation_id) do nothing
  returning id into v_evento_id;

  if v_evento_id is null then
    -- A operacao JA foi registrada (retry ou concorrente vencedor): rele a
    -- trilha e decide entre REPLAY e RECUSA, sem produzir efeito nenhum.
    select * into v_evento
      from public.platform_provisioning_events e
     where e.operation_id = p_operation_id;

    if not found then
      raise exception 'F6_A03_CONFLICT: operacao concorrente nao concluida';
    end if;
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F6_A03_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;

    return v_evento.organization_id;  -- REPLAY: mesmo resultado, zero efeito novo
  end if;

  -- (6) FOUNDER: perfil EXISTENTE precisa estar ativo (paridade com
  --     `conceder_acesso_role`, que exige perfil ativo do titular). Avaliado no
  --     caminho de operacao NOVA - depois da idempotencia, conforme o Â§5.
  if exists (
    select 1 from public.user_profiles up
     where up.id = p_founder_user_profile_id and up.status <> 'active'
  ) then
    raise exception 'F6_A03_INVALID_FOUNDER: perfil do primeiro Admin nao esta ativo';
  end if;

  -- (7) ORGANIZACAO nova (unico INSERT de organizacao do produto).
  insert into public.organizations (id, name)
  values (v_org, v_nome);

  -- (8) Linhas GLOBAIS de identidade (D16/D17). Sao identidade global, sem
  --     membership e sem atribuicao: por si so NAO concedem nada (autorizacao
  --     exige membership + atribuicao ativas).
  begin
    insert into public.user_profiles (id, first_access_pending) values (p_founder_user_profile_id, true)
    on conflict (id) do nothing;
  exception when foreign_key_violation then
    -- FK `user_profiles.id -> auth.users.id`: identidade inexistente.
    raise exception 'F6_A03_INVALID_FOUNDER: identidade autenticada do primeiro Admin inexistente';
  end;

  insert into public.user_profiles (id) values (p_actor_user_profile_id)
  on conflict (id) do nothing;

  -- (9) MEMBERSHIP ativa do founder na organizacao NOVA (par necessariamente
  --     novo: a organizacao acabou de nascer nesta transacao).
  insert into public.user_organization_memberships (
    user_profile_id, organization_id, status
  ) values (
    p_founder_user_profile_id, v_org, 'active'
  )
  returning id into v_membership;

  -- (10) CONCESSAO pelo PRIMITIVO da F4-01 (reuso D4): valida membership ativa,
  --      perfil ativo, role ativa e tenant; reativa no lugar. O caminho do TENANT
  --      (`conceder_acesso_role_rpc`) permanece INTOCADO - inclusive o
  --      anti-self-escalation (D5).
  perform public.conceder_acesso_role(v_membership, v_role, p_actor_user_profile_id);

  -- F6-A14: scope ORGANIZATION da assignment real do primeiro Admin.
  select a.id into v_assignment
    from public.membership_access_role_assignments a
   where a.membership_id = v_membership
     and a.organization_id = v_org
     and a.access_role_id = v_role
     and a.status = 'active'
     and a.created_by = p_actor_user_profile_id;
  if v_assignment is null then
    raise exception using message = v_assignment::text;
  end if;

  insert into public.access_role_assignment_scopes (
    assignment_id, organization_id, scope_type, status, created_by
  ) values (
    v_assignment, v_org, 'ORGANIZATION', 'active', p_actor_user_profile_id
  ) on conflict (assignment_id, scope_type) do nothing;

  -- (11) Trilha D18 append-only, com autoria SOBERANA do operador verificado.
  insert into public.privilege_mutation_audit (
    organization_id, membership_id, access_role_id, action, actor_user_profile_id
  ) values (
    v_org, v_membership, v_role, 'grant', p_actor_user_profile_id
  );

  -- (11.1) F6-A11/D24: ANCORA FUNCIONAL do primeiro Admin pelo PRIMITIVO canonico
  --        da F5-07. Ele grava, na MESMA transacao, `collaborators` +
  --        `collaborator_identifiers` (linha ABERTA) + `collaborator_status_periods`
  --        + evento `ADMISSAO`, e revalida o ator no banco
  --        (`colaborador_ator_valido`): o founder ja tem perfil ativo (8) e
  --        membership ativa (9), portanto e um ator valido. `admission_date` e
  --        `status_inicial` ficam a cargo do default canonico (NULL / `active`).
  --        O `operation_id` e o MESMO da operacao de plataforma: a unicidade
  --        `(organization_id, operation_id)` de `collaborator_events` permanece
  --        como segunda barreira contra duplicacao do evento.
  v_collaborator := public.colaborador_criar(
    v_org,
    p_founder_user_profile_id,
    p_operation_id,
    v_full_name,
    v_email,
    v_matricula,
    null,
    null
  );

  -- (11.2) F6-A11/D24: VINCULO F5-02 pelo primitivo canonico (F5-02 D9), NUNCA
  --        por INSERT direto (Issue Â§5). Ele valida mesmo tenant, no maximo 1
  --        vinculo ativo por membership (Q6=B) e por colaborador/organizacao
  --        (Q3=B) - as unicidades parciais seguem como backstop.
  perform public.vincular_colaborador(v_membership, v_collaborator);

  -- (12) GUARDA FINAL fail-closed: o tenant so se confirma completo.
  if not exists (select 1 from public.organizations o where o.id = v_org) then
    raise exception 'F6_A03_INTERNAL: organizacao nao persistida';
  end if;
  if not exists (
    select 1 from public.user_organization_memberships m
     where m.id = v_membership and m.organization_id = v_org and m.status = 'active'
  ) then
    raise exception 'F6_A03_INTERNAL: membership do primeiro Admin nao persistida';
  end if;
  if not exists (
    select 1 from public.membership_access_role_assignments a
     where a.membership_id = v_membership
       and a.access_role_id = v_role
       and a.organization_id = v_org
       and a.status = 'active'
  ) then
    raise exception 'F6_A03_INTERNAL: atribuicao da role admin nao persistida';
  end if;
  -- F6-A11: a ancora funcional e parte do estado CONFIRMADO do tenant.
  if not exists (
    select 1 from public.collaborators c
     where c.id = v_collaborator and c.organization_id = v_org
  ) then
    raise exception 'F6_A11_INTERNAL: colaborador do primeiro Admin nao persistido';
  end if;
  if not exists (
    select 1 from public.collaborator_identifiers i
     where i.collaborator_id = v_collaborator
       and i.organization_id = v_org
       and i.business_code = v_matricula
       and i.valid_to is null
  ) then
    raise exception 'F6_A11_INTERNAL: identificador aberto do primeiro Admin nao persistido';
  end if;
  if not exists (
    select 1 from public.collaborator_status_periods sp
     where sp.collaborator_id = v_collaborator
       and sp.status = 'active'
       and sp.valid_to is null
  ) then
    raise exception 'F6_A11_INTERNAL: periodo de status ativo do primeiro Admin nao persistido';
  end if;
  if not exists (
    select 1 from public.membership_collaborator_links l
     where l.membership_id = v_membership
       and l.collaborator_id = v_collaborator
       and l.organization_id = v_org
       and l.status = 'active'
  ) then
    raise exception 'F6_A11_INTERNAL: vinculo F5-02 do primeiro Admin nao persistido';
  end if;

  return v_org;
end;
$fn$;



comment on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text) is
  'F6-A20/#310: founder novo nasce com primeiro acesso pendente; perfil preexistente permanece inalterado.';

revoke all on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text) to service_role;
