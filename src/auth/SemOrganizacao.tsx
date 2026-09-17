import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "./AuthContext";
import { obterProvisionamentoPlataforma } from "../services/plataforma/controladorProvisionamento";
import { ROTA_PLATAFORMA_NOVA_ORGANIZACAO } from "../routes/plataformaRotas";
import "../styles/auth.css";

/**
 * F5-01 (Q2 aprovada): estado dedicado "sem organização" para usuário
 * autenticado com profile ativo, mas sem membership ativa. A área funcional
 * permanece bloqueada e nenhum tenant é inventado; o usuário pode apenas sair.
 * A UX final de seleção de organização pertence à F5-03 (não implementada aqui).
 *
 * F6-A03 (Issue #266) — entrada da superfície de PLATAFORMA: o operador
 * autorizado (self-check de UX, D20) recebe um link para criar a organização e
 * definir o primeiro Admin — é o estado em que ele aterrissa quando ainda não há
 * tenant. Nada aqui decide autorização: a ausência do link não bloqueia nada e a
 * decisão real continua na Edge + RPC soberana. O link NÃO é exibido para quem
 * não é operador.
 */
function SemOrganizacao() {
  const { estado, sair } = useAuth();
  const [ehOperadorDePlataforma, setEhOperadorDePlataforma] = useState(false);

  useEffect(() => {
    let vigente = true;
    const provisionamento = obterProvisionamentoPlataforma();
    // Fail-closed: sem caminho soberano no ambiente, nenhum atalho é oferecido.
    if (!provisionamento) return undefined;

    void provisionamento.souOperadorDaPlataforma().then((operador) => {
      if (vigente) setEhOperadorDePlataforma(operador);
    });

    return () => {
      vigente = false;
    };
  }, []);

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
          {ehOperadorDePlataforma && (
            <Link to={ROTA_PLATAFORMA_NOVA_ORGANIZACAO} className="auth-status__entrar">
              Criar organização
            </Link>
          )}
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
