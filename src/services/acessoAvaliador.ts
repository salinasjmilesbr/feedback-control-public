import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";

export async function alterarAcessoAvaliador(input: {
  readonly action: "grant-evaluator" | "revoke-evaluator";
  readonly organizationId: string;
  readonly targetEmail: string;
}): Promise<void> {
  const cliente = criarClienteSupabase();
  if (!cliente) throw new Error("Supabase indisponível.");
  const { error } = await cliente.functions.invoke("gerenciar-access-role", {
    body: { action: input.action, organization_id: input.organizationId, target_email: input.targetEmail.trim().toLowerCase() },
  });
  if (error) throw error;
}
