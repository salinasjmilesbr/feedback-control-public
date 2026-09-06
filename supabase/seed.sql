-- ============================================================================
-- Seed sintético de desenvolvimento — F1-05 (Issue #66)
-- ----------------------------------------------------------------------------
-- Propósito: validar a infraestrutura local de seed do Supabase, reaplicado a
-- cada rebuild do banco local (`supabase db reset`), com conteúdo exclusivamente
-- sintético e determinístico — nunca dados pessoais, corporativos ou históricos
-- reais.
--
-- Estado atual do schema técnico (F1-03): o schema `public` ainda não possui
-- tabelas funcionais do Virtus. Portanto este seed NÃO insere linhas nem cria
-- tabelas/entidades para "ter onde" gravar dados: nenhuma entidade funcional
-- deve ser inventada apenas para suportar o seed. Quando tabelas de domínio
-- existirem, fases posteriores autorizadas poderão adicionar aqui somente dados
-- sintéticos e claramente fictícios.
--
-- Determinismo e idempotência: o arquivo não depende de estado manual, não usa
-- timestamps voláteis nem dados externos; executar o rebuild duas vezes produz o
-- mesmo estado técnico. Não afeta localStorage nem o runtime da aplicação.
--
-- Invariante técnico: assegura que as migrations da foundation (F1-03) foram
-- aplicadas antes do seed, falhando com mensagem clara caso contrário.
-- ============================================================================

do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'set_updated_at'
  ) then
    raise exception
      'seed (F1-05): foundation ausente — execute as migrations antes do seed (supabase db reset).';
  end if;
end
$$;
