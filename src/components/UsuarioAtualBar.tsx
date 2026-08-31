import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { useBranding } from "../contexts/BrandingContext";

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
  } = useUsuarioAtual();
  const { branding } = useBranding();

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
        <div className="app-header__user-control">
          <label htmlFor="usuario-atual">Usuário atual</label>
          <select
            id="usuario-atual"
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

        {usuarioAtual && (
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
