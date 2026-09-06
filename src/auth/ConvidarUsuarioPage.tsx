import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { toPublicError } from "../errors/applicationErrors";
import { useAuth } from "./AuthContext";
import "../styles/auth.css";

/**
 * Formulário mínimo de convite administrativo (F2-06). A autorização real é
 * server-side (Edge Function + allowlist); este formulário apenas invoca o
 * fluxo com o JWT do usuário logado.
 */
function ConvidarUsuarioPage() {
  const { estado, convidarUsuario } = useAuth();
  const [email, setEmail] = useState("");
  const [organizacaoId, setOrganizacaoId] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [enviando, setEnviando] = useState(false);

  const organizacoes = estado.status === "autenticado" ? estado.identidade.organizacoes : [];

  async function enviar(evento: FormEvent) {
    evento.preventDefault();
    setMensagem("");
    setEnviando(true);
    try {
      await convidarUsuario(email.trim(), organizacaoId);
      setEmail("");
      setOrganizacaoId("");
      setMensagem("Convite enviado com sucesso.");
    } catch (erro) {
      setMensagem(toPublicError(erro).message);
    } finally {
      setEnviando(false);
    }
  }

  if (estado.status !== "autenticado") {
    return null;
  }

  return (
    <div className="virtus-page auth-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Convidar usuário</h1>
          <p>Envie um convite por e-mail para acessar o Virtus.</p>
        </div>
      </section>

      <form className="auth-card auth-form" onSubmit={enviar}>
        <label className="branding-field">
          <span>E-mail</span>
          <input
            type="email"
            autoComplete="off"
            value={email}
            onChange={(evento) => setEmail(evento.target.value)}
            required
          />
        </label>

        <label className="branding-field">
          <span>Organização</span>
          <select
            value={organizacaoId}
            onChange={(evento) => setOrganizacaoId(evento.target.value)}
            required
          >
            <option value="">Selecione…</option>
            {organizacoes.map((organizacao) => (
              <option key={organizacao.id} value={organizacao.id}>
                {organizacao.name}
              </option>
            ))}
          </select>
        </label>

        {mensagem && (
          <p className="auth-message" role="alert">
            {mensagem}
          </p>
        )}

        <button
          type="submit"
          className="brand-button brand-button--primary"
          disabled={enviando || organizacoes.length === 0}
        >
          {enviando ? "Enviando…" : "Convidar"}
        </button>

        <Link to="/" className="auth-status__entrar">
          Voltar ao início
        </Link>
      </form>
    </div>
  );
}

export default ConvidarUsuarioPage;
