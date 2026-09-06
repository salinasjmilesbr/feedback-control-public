import { Link } from "react-router-dom";
import { useAuth } from "./AuthContext";
import "../styles/auth.css";

/**
 * Superfície mínima de estado de sessão no cabeçalho (F2-03).
 *
 * Em DEV sem autenticação real configurada, não renderiza nada: a simulação
 * existente segue disponível. Fora de DEV nunca apresenta a identidade
 * simulada como autenticada.
 */
function AuthStatus() {
  const { estado, sair } = useAuth();

  if (estado.status === "verificando" || estado.status === "indisponivel") {
    return null;
  }

  if (estado.status === "autenticado") {
    return (
      <div className="auth-status">
        <span className="auth-status__email">
          {estado.sessao.usuario.email ?? estado.sessao.usuario.id}
        </span>
        <button
          type="button"
          className="auth-status__sair"
          onClick={() => void sair()}
        >
          Sair
        </button>
      </div>
    );
  }

  if (estado.status === "acessoNegado") {
    return (
      <div className="auth-status">
        <span className="auth-status__email">Acesso negado</span>
        <button
          type="button"
          className="auth-status__sair"
          onClick={() => void sair()}
        >
          Sair
        </button>
      </div>
    );
  }

  return (
    <div className="auth-status">
      <Link to="/login" className="auth-status__entrar">
        Entrar
      </Link>
    </div>
  );
}

export default AuthStatus;
