import { useBranding } from "../contexts/BrandingContext";

function AppFooter() {
  const { branding } = useBranding();

  return (
    <footer className="app-footer">
      <div className="app-footer__inner">
        <div>
          <strong>{branding.nomeSistema}</strong>
          <span aria-hidden="true"> • </span>
          <span>{branding.subtituloSistema}</span>
        </div>
        <div className="app-footer__version">Versão 1.0.0</div>
      </div>
    </footer>
  );
}

export default AppFooter;
