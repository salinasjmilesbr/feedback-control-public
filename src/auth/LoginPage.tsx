import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { toPublicError } from "../errors/applicationErrors";
import { useAuth } from "./AuthContext";
import { mensagemDeExpiracao } from "./politicaSessao";
import "../styles/auth.css";

function LoginPage() {
  const { estado, entrar, sair, reconhecerExpiracao } = useAuth();
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [enviando, setEnviando] = useState(false);

  async function enviar(evento: FormEvent) {
    evento.preventDefault();
    setMensagem("");
    setEnviando(true);
    try {
      await entrar(email.trim(), senha);
      setSenha("");
    } catch (erro) {
      setMensagem(toPublicError(erro).message);
    } finally {
      setEnviando(false);
    }
  }

  if (estado.status === "verificando") {
    return (
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Autenticação</h1>
            <p>Verificando sessão…</p>
          </div>
        </section>
      </div>
    );
  }

  if (estado.status === "indisponivel") {
    return (
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Autenticação</h1>
            <p>
              A autenticação não está configurada neste ambiente. Em
              desenvolvimento, a simulação local continua disponível.
            </p>
          </div>
        </section>
      </div>
    );
  }

  if (estado.status === "autenticado") {
    const { sessao, identidade } = estado;
    return (
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Sessão iniciada</h1>
            <p>Você está autenticado no Virtus.</p>
          </div>
        </section>
        <section className="auth-card">
          <p className="auth-card__email">
            {sessao.usuario.email ?? sessao.usuario.id}
          </p>
          <p>
            Organizações com acesso: {identidade.organizacoes.length}
          </p>
          {identidade.organizacoes.length > 0 && (
            <ul className="auth-card__orgs">
              {identidade.organizacoes.map((organizacao) => (
                <li key={organizacao.id}>{organizacao.name}</li>
              ))}
            </ul>
          )}
          <div className="auth-card__actions">
            <Link to="/" className="brand-button brand-button--primary">
              Acessar o Virtus
            </Link>
            <button
              type="button"
              className="brand-button brand-button--secondary"
              onClick={() => void sair()}
            >
              Sair
            </button>
          </div>
        </section>
      </div>
    );
  }

  if (estado.status === "acessoNegado") {
    return (
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Acesso negado</h1>
            <p>{estado.erro.message}</p>
          </div>
        </section>
        <section className="auth-card">
          <button
            type="button"
            className="brand-button brand-button--secondary"
            onClick={() => void sair()}
          >
            Sair
          </button>
        </section>
      </div>
    );
  }

  // F2-08: sessão expirada por inatividade/duração máxima — explica o motivo e
  // oferece o login comum; a primeira interação reconhece o aviso.
  const sessaoExpirada = estado.status === "sessaoExpirada";
  const titulo = sessaoExpirada ? "Sessão expirada" : "Entrar";
  const descricao =
    estado.status === "sessaoExpirada"
      ? mensagemDeExpiracao(estado.motivo)
      : "Acesse o Virtus com sua conta.";

  function aoEditar(alterar: (valor: string) => void, valor: string) {
    alterar(valor);
    if (sessaoExpirada) reconhecerExpiracao();
  }

  return (
    <div className="virtus-page auth-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>{titulo}</h1>
          <p>{descricao}</p>
        </div>
      </section>

      <form className="auth-card auth-form" onSubmit={enviar}>
        <label className="branding-field">
          <span>E-mail</span>
          <input
            type="email"
            autoComplete="username"
            value={email}
            onChange={(evento) => aoEditar(setEmail, evento.target.value)}
            required
          />
        </label>

        <label className="branding-field">
          <span>Senha</span>
          <input
            type="password"
            autoComplete="current-password"
            value={senha}
            onChange={(evento) => aoEditar(setSenha, evento.target.value)}
            required
          />
        </label>

        {mensagem && (
          <p className="auth-message" role="alert">
            {mensagem}
          </p>
        )}

        <button
          type="submit"
          className="brand-button brand-button--primary"
          disabled={enviando}
        >
          {enviando ? "Entrando…" : "Entrar"}
        </button>

        <Link to="/recuperar-senha" className="auth-status__entrar">
          Esqueci minha senha
        </Link>
      </form>
    </div>
  );
}

export default LoginPage;
