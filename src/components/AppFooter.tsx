import VirtusBrand from "./VirtusBrand";

function AppFooter() {
  return (
    <footer className="app-footer">
      <div className="app-footer__inner">
        <div className="app-footer__brandline">
          <VirtusBrand />
          <span className="app-footer__separator" aria-hidden="true">·</span>
          <span>Performance &amp; Feedback Management</span>
        </div>
        <div className="app-footer__version">Versão 1.0.0</div>
      </div>
    </footer>
  );
}

export default AppFooter;
