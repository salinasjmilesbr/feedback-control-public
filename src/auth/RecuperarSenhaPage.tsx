import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "./AuthContext";
import "../styles/auth.css";

const MENSAGEM_NEUTRA =
  "Se o e-mail informado estiver cadastrado, você receberá um link para redefinir sua senha.";

function RecuperarSenhaPage() {
  const { solicitarRecuperacaoDeSenha } = useAuth();
  const [email, setEmail] = useState("");
  const [enviado, setEnviado] = useState(false);
  const [enviando, setEnviando] = useState(false);

  async function enviar(evento: FormEvent) {
    evento.preventDefault();
    setEnviando(true);
    try {
      await solicitarRecuperacaoDeSenha(email.trim());
    } catch {
      // Intencional: a mensagem é sempre neutra, independente do resultado.
    } finally {
      setEnviando(false);
      setEmail("");
      setEnviado(true);
    }
  }

  return (
    <div className="virtus-page auth-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Recuperar senha</h1>
          <p>Informe seu e-mail para receber o link de redefinição.</p>
        </div>
      </section>

      {enviado ? (
        <section className="auth-card">
          <p className="auth-message auth-message--neutral">{MENSAGEM_NEUTRA}</p>
          <Link to="/login" className="auth-status__entrar">
            Voltar para entrar
          </Link>
        </section>
      ) : (
        <form className="auth-card auth-form" onSubmit={enviar}>
          <label className="branding-field">
            <span>E-mail</span>
            <input
              type="email"
              autoComplete="email"
              value={email}
              onChange={(evento) => setEmail(evento.target.value)}
              required
            />
          </label>

          <button
            type="submit"
            className="brand-button brand-button--primary"
            disabled={enviando}
          >
            {enviando ? "Enviando…" : "Enviar link"}
          </button>

          <Link to="/login" className="auth-status__entrar">
            Voltar para entrar
          </Link>
        </form>
      )}
    </div>
  );
}

export default RecuperarSenhaPage;
