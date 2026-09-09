import { useAuth } from "./AuthContext";
import "../styles/auth.css";

/**
 * F5-01 (Q1 aprovada/D11): estado de revalidação não confirmada por falha
 * transitória (rede/5xx). A sessão local é preservada (sem logout), mas a área
 * funcional permanece bloqueada até a revalidação ser confirmada (fail-closed).
 * O usuário pode tentar novamente ou sair.
 */
function SessaoIndisponivel() {
  const { revalidar, sair } = useAuth();

  return (
    <main className="app-main">
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Verificação indisponível</h1>
            <p>
              Não foi possível confirmar sua sessão agora. Sua sessão foi
              preservada, mas o acesso ficará bloqueado até a confirmação.
            </p>
          </div>
        </section>
        <section className="auth-card">
          <div className="auth-card__actions">
            <button
              type="button"
              className="brand-button brand-button--primary"
              onClick={() => void revalidar()}
            >
              Tentar novamente
            </button>
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
    </main>
  );
}

export default SessaoIndisponivel;
