-- ============================================================================
-- F6-A21 P2 (Issue #327): validação da EQUIVALÊNCIA TEMPORAL do subgrafo pessoal
-- ----------------------------------------------------------------------------
-- Prova: vigência meio-aberta `[valid_from, valid_to)` na referência (now()),
-- posição vaga não quebra a travessia, histórico encerrado NÃO amplia o alcance,
-- colegiado vigente, membership-only sem vínculo, usuário vinculado sem
-- capability, Admin lendo o snapshot administrativo (com histórico) e
-- cross-tenant zero. Também confirma a projeção de autorização para o menu.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) PESSOA_A (vinculada, sem capability): subgrafo VIGENTE exato
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a22000-0000-4000-8000-000000000002', false);
set local role authenticated;
do $$
declare
  v_unidades integer; v_parent integer; v_posicoes integer; v_linhas integer;
  v_ocupacoes integer; v_colegiados integer; v_membros integer;
  v_colaboradores integer; v_cargos integer; v_senioridades integer;
  v_n integer;
begin
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 0 then
    raise exception '[FAIL] A1: usuario sem capability recebeu leitura administrativa (%)', v_n;
  end if;

  select jsonb_array_length(unidades), jsonb_array_length(periodos_parent),
         jsonb_array_length(posicoes), jsonb_array_length(reporting_lines),
         jsonb_array_length(ocupacoes), jsonb_array_length(colegiados),
         jsonb_array_length(membros_colegiado), jsonb_array_length(colaboradores),
         jsonb_array_length(cargos), jsonb_array_length(senioridades)
    into v_unidades, v_parent, v_posicoes, v_linhas, v_ocupacoes, v_colegiados,
         v_membros, v_colaboradores, v_cargos, v_senioridades
    from public.estrutura_pessoal;

  -- Anti-passe-vacuoso: sem linha na view as variaveis ficam NULL e as
  -- comparacoes seriam NULL (tratado como falso pelo plpgsql).
  if v_posicoes is null then
    raise exception '[FAIL] A0: estrutura_pessoal sem linha para o ator vinculado';
  end if;

  if v_unidades <> 2 or v_parent <> 0 or v_posicoes <> 5 or v_linhas <> 4
     or v_ocupacoes <> 3 or v_colegiados <> 1 or v_membros <> 1
     or v_colaboradores <> 3 or v_cargos <> 1 or v_senioridades <> 1 then
    raise exception
      '[FAIL] A2: subgrafo vigente inesperado (unidades=%, parent=%, posicoes=%, linhas=%, ocupacoes=%, colegiados=%, membros=%, colaboradores=%, cargos=%, senioridades=%)',
      v_unidades, v_parent, v_posicoes, v_linhas, v_ocupacoes, v_colegiados,
      v_membros, v_colaboradores, v_cargos, v_senioridades;
  end if;

  raise notice '[PASS] A: subgrafo pessoal VIGENTE exato (5 posicoes, 3 colaboradores, 4 linhas, 3 ocupacoes, 1 colegiado, 1 membro, 2 unidades) e ZERO leitura administrativa';
end $$;
rollback;

-- ============================================================================
-- B) Posição VAGA no meio da cadeia não quebra a travessia
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a22000-0000-4000-8000-000000000002', false);
set local role authenticated;
do $$
declare v_n integer;
begin
  -- P_TOPO (vaga) está no alcance...
  select count(*) into v_n
    from public.estrutura_pessoal p, jsonb_array_elements(p.posicoes) e
   where e->>'id' = 'f6a22000-0000-4000-8000-000000000d03';
  if v_n <> 1 then
    raise exception '[FAIL] B1: posicao VAGA intermediaria nao apareceu no alcance (%)', v_n;
  end if;

  -- ...e NENHUMA ocupação a referencia (não inventa ocupante).
  select count(*) into v_n
    from public.estrutura_pessoal p, jsonb_array_elements(p.ocupacoes) e
   where e->>'organizational_position_id' = 'f6a22000-0000-4000-8000-000000000d03';
  if v_n <> 0 then
    raise exception '[FAIL] B2: posicao vaga com ocupacao inventada (%)', v_n;
  end if;

  -- A travessia continua até a posição acima do vago (TOPO é o topo).
  select count(*) into v_n
    from public.estrutura_pessoal p, jsonb_array_elements(p.reporting_lines) e
   where e->>'subordinate_position_id' = 'f6a22000-0000-4000-8000-000000000d02'
     and e->>'manager_position_id' = 'f6a22000-0000-4000-8000-000000000d03';
  if v_n <> 1 then
    raise exception '[FAIL] B3: linha chefe -> vaga ausente do subgrafo (%)', v_n;
  end if;

  raise notice '[PASS] B: posicao VAGA no meio entra no alcance, nao inventa ocupante e nao interrompe a travessia';
end $$;
rollback;

-- ============================================================================
-- C) Histórico ENCERRADO não amplia o alcance atual
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a22000-0000-4000-8000-000000000002', false);
set local role authenticated;
do $$
declare v_n integer;
begin
  -- Posição cuja única relação está ENCERRADA (d06) e posição ENCERRADA (d08): fora.
  -- (O banco proíbe relação aberta para posição encerrada, logo o recorte de
  -- vigência de POSIÇÃO é defesa em profundidade; os casos PROVADOS aqui são a
  -- linha encerrada e a ocupação encerrada.)
  select count(*) into v_n
    from public.estrutura_pessoal p, jsonb_array_elements(p.posicoes) e
   where e->>'id' in ('f6a22000-0000-4000-8000-000000000d06',
                      'f6a22000-0000-4000-8000-000000000d08');
  if v_n <> 0 then
    raise exception '[FAIL] C1: posicao encerrada/fora-do-alcance apareceu (%)', v_n;
  end if;

  -- Pessoas por ocupação ENCERRADA (ANTIGO), por linha encerrada (FECHADA) ou
  -- sem relação (FORA): fora do subgrafo.
  select count(*) into v_n
    from public.estrutura_pessoal p, jsonb_array_elements(p.colaboradores) e
   where e->>'id' in ('f6a22000-0000-4000-8000-000000000e04',
                      'f6a22000-0000-4000-8000-000000000e05',
                      'f6a22000-0000-4000-8000-000000000e06');
  if v_n <> 0 then
    raise exception '[FAIL] C2: historico encerrado ampliou o alcance de pessoas (%)', v_n;
  end if;

  -- A linha ENCERRADA (fechada -> ator) nao entra.
  select count(*) into v_n
    from public.estrutura_pessoal p, jsonb_array_elements(p.reporting_lines) e
   where e->>'id' = 'f6a22000-0000-4000-8000-000000000105';
  if v_n <> 0 then
    raise exception '[FAIL] C3: reporting line ENCERRADA no subgrafo (%)', v_n;
  end if;

  -- O colegiado ENCERRADO (membro FORA) nao entra; so o vigente.
  select count(*) into v_n
    from public.estrutura_pessoal p, jsonb_array_elements(p.colegiados) e
   where e->>'id' = 'f6a22000-0000-4000-8000-000000000202';
  if v_n <> 0 then
    raise exception '[FAIL] C4: colegiado ENCERRADO no subgrafo (%)', v_n;
  end if;
  select count(*) into v_n
    from public.estrutura_pessoal p, jsonb_array_elements(p.membros_colegiado) e
   where e->>'member_collaborator_id' = 'f6a22000-0000-4000-8000-000000000e06';
  if v_n <> 0 then
    raise exception '[FAIL] C5: membro do colegiado ENCERRADO no subgrafo (%)', v_n;
  end if;

  raise notice '[PASS] C: posicao encerrada, ocupacao encerrada, linha encerrada e colegiado encerrado NAO ampliam o alcance atual';
end $$;
rollback;

-- ============================================================================
-- D) Membership-only SEM vínculo (menor privilégio) e) sem capability
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a22000-0000-4000-8000-000000000003', false);
set local role authenticated;
do $$
declare v_n integer; v_flags text;
begin
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 0 then raise exception '[FAIL] D1: membership-only com leitura administrativa (%)', v_n; end if;
  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 0 then raise exception '[FAIL] D2: membership-only sem vinculo com projecao pessoal (%)', v_n; end if;
  select pode_estrutura::text || '/' || pode_catalogo::text into v_flags from public.estrutura_autorizacao;
  if v_flags <> 'false/false' then raise exception '[FAIL] D3: flags=% (esperado false/false)', v_flags; end if;
  raise notice '[PASS] D: membership-only sem vinculo => zero administrativo, zero pessoal e flags false/false (menu nao projeta)';
end $$;
rollback;

-- ============================================================================
-- E) Admin: snapshot administrativo COMPLETO (inclui histórico) — contraste com o pessoal
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a22000-0000-4000-8000-000000000001', false);
set local role authenticated;
do $$
declare
  v_posicoes integer; v_colaboradores integer; v_linhas integer;
  v_colegiados integer; v_membros integer; v_ocupacoes integer;
  v_flags text; v_n integer;
begin
  select pode_estrutura::text || '/' || pode_catalogo::text into v_flags
    from public.estrutura_autorizacao;
  if v_flags <> 'true/true' then raise exception '[FAIL] E1: flags do admin=%', v_flags; end if;

  select jsonb_array_length(posicoes), jsonb_array_length(colaboradores),
         jsonb_array_length(reporting_lines), jsonb_array_length(colegiados),
         jsonb_array_length(membros_colegiado), jsonb_array_length(ocupacoes)
    into v_posicoes, v_colaboradores, v_linhas, v_colegiados, v_membros, v_ocupacoes
    from public.estrutura_administrativa;

  if v_posicoes <> 8 or v_colaboradores <> 6 or v_linhas <> 5
     or v_colegiados <> 2 or v_membros <> 2 or v_ocupacoes <> 6 then
    raise exception
      '[FAIL] E2: snapshot administrativo inesperado (posicoes=%, colaboradores=%, linhas=%, colegiados=%, membros=%, ocupacoes=%)',
      v_posicoes, v_colaboradores, v_linhas, v_colegiados, v_membros, v_ocupacoes;
  end if;

  -- O admin (sem vínculo) NAO recebe projecao pessoal.
  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 0 then raise exception '[FAIL] E3: admin sem vinculo com projecao pessoal (%)', v_n; end if;

  -- Cross-tenant: nada de BETA.
  select count(*) into v_n from public.estrutura_administrativa
   where organization_id = 'f6a22000-0000-4000-8000-0000000000a2';
  if v_n <> 0 then raise exception '[FAIL] E4: cross-tenant administrativo (%)', v_n; end if;

  raise notice '[PASS] E: Admin le o snapshot administrativo COMPLETO (8 posicoes/6 colaboradores/6 linhas/2 colegiados, incluindo historico), sem projecao pessoal e com cross-tenant zero';
end $$;
rollback;

do $$
begin
  raise notice '[PASS] F6-A21 P2: equivalencia temporal do subgrafo pessoal validada (vigencia, vaga no meio, historico encerrado sem ampliacao, colegiado vigente, membership-only, vinculado sem capability, Admin e cross-tenant)';
end $$;
