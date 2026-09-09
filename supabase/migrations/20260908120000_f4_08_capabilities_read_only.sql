-- ============================================================================
-- F4-08 (Issue #95): capabilities como catálogo GLOBAL read-only (D12/Q7)
-- ----------------------------------------------------------------------------
-- `capabilities` é um catálogo global do produto (sem organization_id): saber
-- a existência/código de uma capability NÃO a concede (autorização funcional
-- permanece no Policy Engine). Expõe SELECT a authenticated (read-only); sem
-- INSERT/UPDATE/DELETE por authenticated (deny-by-default).
--
-- Policy pronta antes do grant (D21).
-- ============================================================================

create policy capabilities_select_authenticated on public.capabilities
  for select to authenticated
  using (true);

grant select on public.capabilities to authenticated;
