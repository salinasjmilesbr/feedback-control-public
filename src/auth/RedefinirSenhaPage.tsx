import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "./AuthContext";
import { validarNovaSenha } from "./servico";
import "../styles/auth.css";

type EstadoRedefinicao = "verificando" | "pronto" | "invalido" | "sucesso";

const MENSAGEM_LINK_INVALIDO =
  "O link de recuperação é inválido ou expirou. Solicite um novo link.";

/**
 * Tela pública de redefinição de senha (F2-05). O link oficial de recuperação é
 * processado pelo SDK do Supabase (`detectSessionInUrl`) e a sessão de
 * recuperação aparece como estado `autenticado` do `AuthProvider`. A nova senha
 * só é aceita com essa sessão válida; sem sessão, falha de forma segura.
 */
function RedefinirSenhaPage() {
  const { estado, redefinirSenha, sair } = useAuth();
  const [senha, setSenha] = useState("");
  const [confirmacao, setConfirmacao] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [sucesso, setSucesso] = useState(false);

  const status: EstadoRedefinicao = sucesso
    ? "sucesso"
    : estado.status === "autenticado"
    ? "pronto"
    : estado.status === "verificando"
    ? "verificando"
    : "invalido";

  async function enviar(evento: FormEvent) {
    evento.preventDefault();
    const erroLocal = validarNovaSenha(senha, confirmacao);
    if (erroLocal) {
      setMensagem(erroLocal);
      return;
    }

    setMensagem("");
    setEnviando(true);
    try {
      await redefinirSenha(senha);
      setSenha("");
      setConfirmacao("");
      await sair();
      setSucesso(true);
    } catch {
      setMensagem(MENSAGEM_LINK_INVALIDO);
    } finally {
      setEnviando(false);
    }
  }

  if (status === "verificando") {
    return (
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Redefinir senha</h1>
            <p>Verificando o link de recuperação…</p>
          </div>
        </section>
      </div>
    );
  }

  if (status === "invalido") {
    return (
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Redefinição indisponível</h1>
            <p>{MENSAGEM_LINK_INVALIDO}</p>
          </div>
        </section>
        <section className="auth-card">
          <Link to="/login" className="auth-status__entrar">
            Voltar para entrar
          </Link>
        </section>
      </div>
    );
  }

  if (status === "sucesso") {
    return (
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Senha redefinida</h1>
            <p>Sua senha foi atualizada. Faça login com a nova senha.</p>
          </div>
        </section>
        <section className="auth-card">
          <Link to="/login" className="brand-button brand-button--primary">
            Ir para o login
          </Link>
        </section>
      </div>
    );
  }

  return (
    <div className="virtus-page auth-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Definir nova senha</h1>
          <p>Escolha uma nova senha para a sua conta.</p>
        </div>
      </section>

      <form className="auth-card auth-form" onSubmit={enviar}>
        <label className="branding-field">
          <span>Nova senha</span>
          <input
            type="password"
            autoComplete="new-password"
            value={senha}
            onChange={(evento) => setSenha(evento.target.value)}
            required
          />
        </label>

        <label className="branding-field">
          <span>Confirmar nova senha</span>
          <input
            type="password"
            autoComplete="new-password"
            value={confirmacao}
            onChange={(evento) => setConfirmacao(evento.target.value)}
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
          {enviando ? "Salvando…" : "Salvar nova senha"}
        </button>
      </form>
    </div>
  );
}

export default RedefinirSenhaPage;
