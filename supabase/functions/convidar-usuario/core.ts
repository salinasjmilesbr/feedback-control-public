/** Gate puro da fronteira de convite: somente a capability efetiva soberana. */
export type LinhaCapabilityEfetiva = { readonly capability_code?: unknown };

export function podeConvidarPorMembershipManage(
  linhas: unknown,
  erro: unknown
): boolean {
  if (erro || !Array.isArray(linhas)) return false;
  return linhas.some(
    (linha: LinhaCapabilityEfetiva) => linha?.capability_code === "membership.manage"
  );
}
