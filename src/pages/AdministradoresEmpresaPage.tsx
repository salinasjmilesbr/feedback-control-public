import { useCallback, useEffect, useState } from "react";
import { useAuth } from "../auth/AuthContext";
import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";

type AdminRow = { id: string; user_profile_id: string; status: string; admin_status?: string; display_name?: string | null; email?: string | null; user_profiles?: { id: string; status: string; first_access_pending?: boolean } };

export default function AdministradoresEmpresaPage() {
  const { estado, organizacaoAtivaId } = useAuth();
  const [admins, setAdmins] = useState<AdminRow[]>([]);
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  const carregar = useCallback(async () => {
    if (!organizacaoAtivaId) return;
    const client = criarClienteSupabase();
    if (!client) return;
    const { data, error } = await client.functions.invoke<{ administrators?: AdminRow[] }>("gerenciar-admin-empresa", { body: { action: "list", organization_id: organizacaoAtivaId } });
    if (error || !data) { setMessage("Não foi possível carregar os administradores."); return; }
    setAdmins(data.administrators ?? []);
  }, [organizacaoAtivaId]);
  // A leitura assíncrona sincroniza a tela com a sessão/tenant resolvidos.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { if (estado.status === "autenticado") void carregar(); }, [carregar, estado.status]);

  async function convidar() {
    if (!organizacaoAtivaId || !email.trim()) return;
    const client = criarClienteSupabase();
    if (!client) return;
    setBusy(true); setMessage("");
    const { error } = await client.functions.invoke("gerenciar-admin-empresa", { body: { action: "invite", organization_id: organizacaoAtivaId, email: email.trim(), operation_id: crypto.randomUUID() } });
    setMessage(error ? "Não foi possível enviar o convite." : "Convite enviado. O novo Admin já reservou uma vaga e aparecerá como pendente de primeiro acesso.");
    if (!error) { setEmail(""); await carregar(); }
    setBusy(false);
  }

  async function alterar(action: "revoke" | "reactivate", membershipId: string) {
    if (!organizacaoAtivaId) return;
    const client = criarClienteSupabase();
    if (!client) return;
    setBusy(true);
    const { error } = await client.functions.invoke("gerenciar-admin-empresa", { body: { action, organization_id: organizacaoAtivaId, membership_id: membershipId, operation_id: crypto.randomUUID() } });
    setMessage(error ? (error.message || "Não foi possível concluir a operação.") : action === "revoke" ? "Admin revogado." : "Admin reativado.");
    await carregar();
    setBusy(false);
  }

  if (estado.status !== "autenticado") return null;
  const ativos = admins.filter((admin) => admin.admin_status === "active").length;
  return <main className="virtus-page">
    <section className="virtus-page-header"><div className="virtus-page-header__copy"><h1>Administradores da Empresa</h1><p>Gerencie de forma auditada os administradores ativos deste tenant.</p></div></section>
    <section className="admin-company-list"><h2>Administradores ativos ({ativos}/4)</h2><div className="admin-company-grid">{admins.map((admin) => {
      const pendente = admin.admin_status === "active" && admin.user_profiles?.first_access_pending === true;
      const nome = admin.display_name?.trim() || admin.email || "Administrador";
      const statusLabel = admin.admin_status === "active" ? (pendente ? "Convite pendente" : "Ativo") : "Revogado";
      return <article className="admin-company-card" key={admin.id}>
        <div className="admin-company-card__identity"><h3>{nome}</h3>{admin.email && <p>{admin.email}</p>}</div>
        <span className={`admin-company-card__status admin-company-card__status--${admin.admin_status === "active" ? (pendente ? "pending" : "active") : "revoked"}`}>{statusLabel}</span>
        <button className="virtus-btn virtus-btn--outline" disabled={busy} onClick={() => void alterar(admin.admin_status === "active" ? "revoke" : "reactivate", admin.id)}>{admin.admin_status === "active" ? "Revogar" : "Reativar"}</button>
      </article>;
    })}</div></section>
    <section className="estrutura-card admin-company-invite"><h2>Convidar novo administrador</h2><label className="branding-field"><span>E-mail do novo Admin</span><input type="email" value={email} onChange={(event) => setEmail(event.target.value)} /></label>
      <button className="virtus-btn" disabled={busy || ativos >= 4 || !email.includes("@")} onClick={() => void convidar()}>Enviar convite</button>
      {ativos >= 4 && <p role="status">Limite de 4 administradores ativos atingido.</p>}
      {message && <p role="status">{message}</p>}
    </section>
  </main>;
}
