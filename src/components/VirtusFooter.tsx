import VirtusLogo from "./VirtusLogo";

export default function VirtusFooter() {
  return (
    <footer className="app-footer">
      <div className="app-footer__identity">
        <VirtusLogo />
        <span aria-hidden="true">•</span>
        <span>Performance &amp; Feedback Management</span>
      </div>
      <span>Versão 1.0.0</span>
    </footer>
  );
}
