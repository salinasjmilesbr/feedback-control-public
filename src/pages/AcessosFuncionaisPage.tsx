import { useEffect, useState } from "react";
import { useAuth } from "../auth/AuthContext";
import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";

type Pessoa = { membership_id: string; collaborator_id: string; name: string };
type Acesso = { id: string; name: string; organization_id: string | null };

function nomeDeNegocio(acesso: Acesso): string {
  const nomes: Record<string, string> = {
    evaluator: "Avaliador",
    metas_dono: "Responsável por metas",
    metas_aprovador: "Aprovador de metas",
    observacoes_gestor: "Gestão de observações",
  };
  return nomes[acesso.name] ?? acesso.name;
}

export default function AcessosFuncionaisPage() {
  const { estado, organizacaoAtivaId } = useAuth();
  const [pessoas, setPessoas] = useState<Pessoa[]>([]);
  const [acessos, setAcessos] = useState<Acesso[]>([]);
  const [pessoa, setPessoa] = useState("");
  const [acesso, setAcesso] = useState("");
  const [alcance, setAlcance] = useState<"DIRECT_REPORTS" | "DESCENDANTS">("DIRECT_REPORTS");
  const [motivo, setMotivo] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [ocupado, setOcupado] = useState(false);

  useEffect(() => {
    if (estado.status !== "autenticado" || !organizacaoAtivaId) return;
    const cliente = criarClienteSupabase();
    if (!cliente) return;
    void cliente.functions.invoke<{ people?: Pessoa[]; roles?: Acesso[] }>("gerenciar-access-role", {
      body: { action: "list-functional", organization_id: organizacaoAtivaId },
    }).then(({ data, error }) => {
      if (error || !data) { setMensagem("Não foi possível carregar os acessos disponíveis."); return; }
      setPessoas(data.people ?? []); setAcessos(data.roles ?? []);
    });
  }, [estado.status, organizacaoAtivaId]);

  async function executar(action: "grant-functional" | "revoke-functional") {
    if (!organizacaoAtivaId || !pessoa || !acesso || motivo.trim().length < 3) return;
    const cliente = criarClienteSupabase();
    if (!cliente) { setMensagem("Serviço indisponível."); return; }
    setOcupado(true); setMensagem("");
    const { error } = await cliente.functions.invoke("gerenciar-access-role", {
      body: {
        action, membership_id: pessoa, access_role_id: acesso,
        scope_type: alcance, operation_id: crypto.randomUUID(), reason: motivo.trim(),
      },
    });
    setMensagem(error ? "Não foi possível concluir a operação." : action === "grant-functional" ? "Acesso de gestão concedido." : "Acesso de gestão revogado.");
    setOcupado(false);
  }

  if (estado.status !== "autenticado") return null;
  return <main className="virtus-page">
    <section className="virtus-page-header"><div className="virtus-page-header__copy">
      <h1>Acessos funcionais</h1>
      <p>Conceda ou revogue acesso de gestão de equipe para uma pessoa da organização.</p>
    </div></section>
    <section className="estrutura-card">
      <label className="branding-field"><span>Pessoa</span><select value={pessoa} onChange={(e) => setPessoa(e.target.value)}><option value="">Selecione…</option>{pessoas.map((item) => <option key={item.membership_id} value={item.membership_id}>{item.name}</option>)}</select></label>
      <label className="branding-field"><span>Acesso funcional</span><select value={acesso} onChange={(e) => setAcesso(e.target.value)}><option value="">Selecione…</option>{acessos.map((item) => <option key={item.id} value={item.id}>{nomeDeNegocio(item)}</option>)}</select></label>
      <label className="branding-field"><span>Alcance da equipe</span><select value={alcance} onChange={(e) => setAlcance(e.target.value as "DIRECT_REPORTS" | "DESCENDANTS")}><option value="DIRECT_REPORTS">Equipe direta</option><option value="DESCENDANTS">Toda a estrutura abaixo</option></select></label>
      <label className="branding-field"><span>Motivo</span><input value={motivo} onChange={(e) => setMotivo(e.target.value)} minLength={3} required /></label>
      <div className="virtus-page-actions"><button className="virtus-btn" disabled={ocupado || !pessoa || !acesso || motivo.trim().length < 3} onClick={() => void executar("grant-functional")}>Conceder acesso</button><button className="virtus-btn virtus-btn--outline" disabled={ocupado || !pessoa || !acesso || motivo.trim().length < 3} onClick={() => void executar("revoke-functional")}>Revogar acesso</button></div>
      {mensagem && <p role="status">{mensagem}</p>}
    </section>
  </main>;
}
