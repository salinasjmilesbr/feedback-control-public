import { useAuth } from "./AuthContext";
import "../styles/auth.css";

/**
 * F5-01 (Q2 aprovada): estado dedicado "sem organização" para usuário
 * autenticado com profile ativo, mas sem membership ativa. A área funcional
 * permanece bloqueada e nenhum tenant é inventado; o usuário pode apenas sair.
 * A UX final de seleção de organização pertence à F5-03 (não implementada aqui).
 */
function SemOrganizacao() {
  const { estado, sair } = useAuth();
  const email =
    estado.status === "semOrganizacao"
      ? estado.sessao.usuario.email ?? estado.sessao.usuario.id
      : null;

  return (
    <main className="app-main">
      <div className="virtus-page auth-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Sem organização</h1>
            <p>
              Você está autenticado, mas ainda não possui uma organização
              atribuída. Aguarde a atribuição de organização para acessar o
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

export default SemOrganizacao;
