import { useAuth } from "./AuthContext";
import "../styles/auth.css";

/**
 * F5-03 (Q2 = A): tela dedicada de seleção inicial para usuário autenticado com
 * N>1 memberships ativas. Nenhuma organização é escolhida silenciosamente; a
 * lista é soberana (snapshot) e a seleção é intenção de UX revalidada no
 * servidor a cada operação.
 */
function AguardandoSelecao() {
  const { estado, organizacoesDisponiveis, selecionarOrganizacao, sair } = useAuth();
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
              Sua conta possui mais de uma organização. Escolha em qual deseja
              operar.
            </p>
          </div>
        </section>
        <section className="auth-card">
          {email && <p className="auth-card__email">{email}</p>}

          <div className="auth-card__orgs" role="list">
            {organizacoesDisponiveis.map((organizacao) => (
              <button
                key={organizacao.id}
                type="button"
                role="listitem"
                className="brand-button brand-button--primary"
                onClick={() => selecionarOrganizacao(organizacao.id)}
              >
                {organizacao.name}
              </button>
            ))}
          </div>

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
