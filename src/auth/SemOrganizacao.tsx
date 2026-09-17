import { useAuth } from "./AuthContext";
import EntradaPlataforma from "./EntradaPlataforma";
import "../styles/auth.css";

/**
 * F5-01 (Q2 aprovada): estado dedicado "sem organização" para usuário
 * autenticado com profile ativo, mas sem membership ativa. A área funcional
 * permanece bloqueada e nenhum tenant é inventado; o usuário pode apenas sair.
 * A UX final de seleção de organização pertence à F5-03 (não implementada aqui).
 *
 * F6-A04 (Issue #269): a entrada da superfície de plataforma passou a ser o
 * componente ÚNICO `EntradaPlataforma` (sonda + link, fail-closed, D20/D3) —
 * antes o bloco era inline aqui. Nada aqui decide autorização: a ausência do
 * link não bloqueia nada e a decisão real continua na Edge + RPC soberana.
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
          <EntradaPlataforma />
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
