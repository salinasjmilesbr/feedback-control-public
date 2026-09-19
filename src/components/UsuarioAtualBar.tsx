import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { useAuth } from "../auth/AuthContext";
import AuthStatus from "../auth/AuthStatus";
import VirtusBrand from "./VirtusBrand";

function UsuarioAtualBar() {
  const {
    usuarioAtual,
    usuariosDisponiveis,
    selecionarUsuario,
    simulacaoDevAtiva,
  } = useUsuarioAtual();
  const { organizacoesDisponiveis, organizacaoAtivaId, selecionarOrganizacao } = useAuth();
  const organizacaoAtiva = organizacoesDisponiveis.find(
    (organizacao) => organizacao.id === organizacaoAtivaId
  );

  // F2-09: o seletor de identidade é impersonação DEV (colaboradores sintéticos
  // do seed local). Fora de DEV explícito não é renderizado — a identidade real
  // vem do Supabase Auth (AuthStatus) e nunca há fallback simulado.
  const impersonacaoDevVisivel = simulacaoDevAtiva === true && usuariosDisponiveis.length > 0;

  return (
    <header className="app-header">
      <div className="app-header__inner">
      <div className="app-header__brand">
        <VirtusBrand context={organizacaoAtiva?.name ?? "Empresa"} />
      </div>

      <div className="app-header__user">
        <AuthStatus />

        {organizacoesDisponiveis.length > 1 && (
          <div className="app-header__user-control">
            <label htmlFor="organizacao-ativa">Organização</label>
            <select
              id="organizacao-ativa"
              aria-label="Organização ativa"
              value={organizacaoAtivaId ?? ""}
              onChange={(event) => selecionarOrganizacao(event.target.value)}
            >
              {organizacoesDisponiveis.map((organizacao) => (
                <option key={organizacao.id} value={organizacao.id}>
                  {organizacao.name}
                </option>
              ))}
            </select>
          </div>
        )}

        {impersonacaoDevVisivel && (
          <div className="app-header__user-control">
            <label htmlFor="usuario-atual">
              Usuário atual — simulação DEV
            </label>
            <select
              id="usuario-atual"
              aria-label="Usuário atual — simulação DEV"
              value={usuarioAtual?.matricula ?? ""}
              onChange={(event) =>
                selecionarUsuario(Number(event.target.value))
              }
            >
              {usuariosDisponiveis.map((usuario) => (
                <option
                  key={usuario.matricula}
                  value={usuario.matricula}
                >
                  {usuario.nome} -{" "}
                  {usuario.funcao === "GERENTE"
                    ? "Gerente"
                    : usuario.funcao === "COORDENADOR"
                    ? "Coordenador"
                    : usuario.funcao === "CONSULTOR"
                    ? "Consultor"
                    : usuario.funcao === "ESTAGIARIO"
                    ? "Estagiário"
                    : "Analista"}
                </option>
              ))}
            </select>
          </div>
        )}

      </div>
      </div>
    </header>
  );
}

export default UsuarioAtualBar;
