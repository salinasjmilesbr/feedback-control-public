import { useState, type FormEvent } from "react";
import { useAuth } from "../auth/AuthContext";
import { alterarAcessoAvaliador } from "../services/acessoAvaliador";

function AcessoAvaliadorPage() {
  const { estado } = useAuth();
  const [organizacaoId, setOrganizacaoId] = useState("");
  const [email, setEmail] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [enviando, setEnviando] = useState(false);
  if (estado.status !== "autenticado") return null;
  const organizacoes = estado.identidade.organizacoes;

  async function executar(action: "grant-evaluator" | "revoke-evaluator") {
    setMensagem(""); setEnviando(true);
    try {
      await alterarAcessoAvaliador({ action, organizationId: organizacaoId, targetEmail: email });
      setMensagem(action === "grant-evaluator" ? "Acesso de leitura concedido." : "Acesso de leitura revogado.");
    } catch { setMensagem("Não foi possível concluir a operação. A decisão permanece no servidor."); }
    finally { setEnviando(false); }
  }
  function submeter(evento: FormEvent) { evento.preventDefault(); void executar("grant-evaluator"); }

  return <main className="virtus-page">
    <section className="virtus-page-header"><div className="virtus-page-header__copy">
      <h1>Acesso às avaliações</h1><p>Conceda ou revogue leitura somente das avaliações atribuídas ao usuário.</p>
    </div></section>
    <form className="estrutura-card" onSubmit={submeter}>
      <label className="branding-field"><span>Organização</span><select value={organizacaoId} onChange={(e) => setOrganizacaoId(e.target.value)} required>
        <option value="">Selecione…</option>{organizacoes.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}
      </select></label>
      <label className="branding-field"><span>E-mail do usuário</span><input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required /></label>
      <p>O servidor fixa <code>evaluation.read</code> e <code>ASSIGNED</code>; não há acesso organizacional amplo.</p>
      <div className="virtus-page-actions"><button className="virtus-btn" type="submit" disabled={enviando}>Conceder leitura</button>
        <button className="virtus-btn virtus-btn--outline" type="button" disabled={enviando || !organizacaoId || !email} onClick={() => void executar("revoke-evaluator")}>Revogar leitura</button></div>
      {mensagem && <p role="status">{mensagem}</p>}
    </form>
  </main>;
}
export default AcessoAvaliadorPage;
