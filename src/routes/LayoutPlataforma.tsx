import { Link, Navigate, Outlet } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import SessaoIndisponivel from "../auth/SessaoIndisponivel";
import { decidirAcessoARotaDePlataforma } from "./plataformaRotas";
import AppFooter from "../components/AppFooter";
import { useBranding } from "../contexts/BrandingContext";
import "../styles/platform.css";

/**
 * F6-A03 (Issue #266) — layout/guard da superfície mínima de PLATAFORMA (D19).
 *
 * Deliberadamente FORA de `LayoutAutenticado`/`LayoutFuncional`
 * (`src/routes/AppRoutes.tsx`): o plano de plataforma não depende da resolução
 * de identidade de TENANT (D19) e, por isso, NÃO carrega estrutura soberana, NÃO
 * monta `AuthorizationContext` de tenant e NÃO lê navegação funcional.
 *
 * Não decide autorização: apenas aplica a decisão do guard puro
 * (`plataformaRotas.decidirAcessoARotaDePlataforma`). A autoridade é sempre da
 * Edge `provisionar-organizacao` + RPC soberana.
 */
export default function LayoutPlataforma() {
  const { estado, sair } = useAuth();
  const { branding } = useBranding();
  const decisao = decidirAcessoARotaDePlataforma(estado);

  if (decisao.tipo === "carregando") {
    return (
      <div className="auth-loading" role="status" aria-live="polite">
        Verificando sessão…
      </div>
    );
  }

  if (decisao.tipo === "redirecionarLogin") {
    return <Navigate to="/login" replace />;
  }

  if (decisao.tipo === "bloquear") {
    return <SessaoIndisponivel />;
  }

  return (
    <div className="platform-shell">
      <header className="platform-header">
        <div className="platform-header__inner">
          <span>
            <Link to="/plataforma" className="platform-header__brand">{branding.nomeSistema}</Link>
            <span className="platform-header__label">Administração da plataforma</span>
          </span>
          <button type="button" className="platform-header__exit" onClick={() => void sair()}>
            Sair
          </button>
        </div>
      </header>
      <main className="platform-main">
        <Outlet />
      </main>
      <AppFooter />
    </div>
  );
}
