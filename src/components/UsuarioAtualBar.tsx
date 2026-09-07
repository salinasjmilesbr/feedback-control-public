import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { useBranding } from "../contexts/BrandingContext";
import AuthStatus from "../auth/AuthStatus";

function obterIniciais(nome: string) {
  const partes = nome.trim().split(/\s+/).filter(Boolean);

  if (partes.length === 0) return "?";
  if (partes.length === 1) return partes[0].slice(0, 2).toUpperCase();

  return `${partes[0][0]}${partes[partes.length - 1][0]}`.toUpperCase();
}

function UsuarioAtualBar() {
  const {
    usuarioAtual,
    usuariosDisponiveis,
    selecionarUsuario,
    simulacaoDevAtiva,
  } = useUsuarioAtual();
  const { branding } = useBranding();

  // F2-09: o seletor de identidade é impersonação DEV (colaboradores sintéticos
  // do seed local). Fora de DEV explícito não é renderizado — a identidade real
  // vem do Supabase Auth (AuthStatus) e nunca há fallback simulado.
  const impersonacaoDevVisivel = simulacaoDevAtiva === true && usuariosDisponiveis.length > 0;

  return (
    <header className="app-header">
      <div className="app-header__inner">
      <div className="app-header__brand">
        {branding.logoDataUrl ? (
          <img
            src={branding.logoDataUrl}
            alt={`Logo ${branding.nomeSistema}`}
            className="app-header__logo"
          />
        ) : (
          <div className="app-header__logo-placeholder">
            {branding.nomeSistema.slice(0, 1).toUpperCase() || "V"}
          </div>
        )}

        <div className="app-header__brand-copy">
          <strong>{branding.nomeSistema}</strong>
          <span className="app-header__subtitle">
            {branding.subtituloSistema ||
              "Performance & Feedback Management"}
          </span>
        </div>
      </div>

      <div className="app-header__user">
        <AuthStatus />

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

        {impersonacaoDevVisivel && usuarioAtual && (
          <div className="app-header__profile">
            <div
              className="app-header__avatar"
              aria-hidden="true"
            >
              {obterIniciais(usuarioAtual.nome)}
            </div>
            <span className="app-role-badge">
              {usuarioAtual.funcao}
            </span>
          </div>
        )}
      </div>
      </div>
    </header>
  );
}

export default UsuarioAtualBar;
