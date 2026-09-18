import AppRoutes from "./routes/AppRoutes";
import type { ReactNode } from "react";
import { UsuarioAtualProvider } from "./contexts/UsuarioAtualProvider";
import { BrandingProvider } from "./contexts/BrandingProvider";
import { AuthProvider } from "./auth/AuthProvider";
import { useAuth } from "./auth/AuthContext";

function UsuarioAtualComTenant({ children }: { children: ReactNode }) {
  const { organizacaoAtivaId, estado } = useAuth();
  const usuarioAutenticadoEmail =
    estado.status === "autenticado" || estado.status === "aguardandoSelecao" || estado.status === "semOrganizacao"
      ? estado.sessao.usuario.email
      : null;

  return (
    <UsuarioAtualProvider
      organizacaoAtivaId={organizacaoAtivaId}
      usuarioAutenticadoEmail={usuarioAutenticadoEmail}
    >
      {children}
    </UsuarioAtualProvider>
  );
}

function App() {
  return (
    <BrandingProvider>
      <AuthProvider>
        <UsuarioAtualComTenant>
          <AppRoutes />
        </UsuarioAtualComTenant>
      </AuthProvider>
    </BrandingProvider>
  );
}

export default App;
