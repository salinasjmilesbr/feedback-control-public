import { useAuth } from "./AuthContext";
import "../styles/auth.css";

/**
 * F5-01 (Q4 aprovada/D4/D8): estado dedicado para usuário autenticado com N>1
 * memberships ativas. Nenhuma organização é escolhida silenciosamente — a área
 * funcional permanece bloqueada. A seleção explícita, sua persistência e o
 * switcher pertencem à F5-03 (não implementados aqui).
 */
function AguardandoSelecao() {
  const { estado, sair } = useAuth();
  const email =
    estado.status === "aguardandoSelecao"
      ? estado.sessao.usuario.email ?? estado.sessao.usuario.id
      : null;

  return (
    <main className="app-main">
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Selecione a organização</h1>
            <p>
              Sua conta possui mais de uma organização. A seleção de organização
              ainda não está disponível nesta etapa — aguarde para acessar o
              Virtus.
            </p>
          </div>
        </section>
        <section className="auth-card">
          {email && <p className="auth-card__email">{email}</p>}
          <button
            type="button"
            className="brand-button brand-button--secondary"
            onClick={() => void sair()}
          >
            Sair
          </button>
        </section>
      </div>
    </main>
  );
}

export default AguardandoSelecao;
