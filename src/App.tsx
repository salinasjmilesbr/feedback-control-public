import AppRoutes from "./routes/AppRoutes";
import type { ReactNode } from "react";
import { UsuarioAtualProvider } from "./contexts/UsuarioAtualProvider";
import { BrandingProvider } from "./contexts/BrandingProvider";
import { AuthProvider } from "./auth/AuthProvider";
import { useAuth } from "./auth/AuthContext";

function UsuarioAtualComTenant({ children }: { children: ReactNode }) {
  const { organizacaoAtivaId } = useAuth();

  return (
    <UsuarioAtualProvider organizacaoAtivaId={organizacaoAtivaId}>
      {children}
    </UsuarioAtualProvider>
  );
}

function App() {
  return (
    <AuthProvider>
      {/* Issue #317 (Fase 1): o branding depende da ORGANIZAÇÃO ATIVA, portanto
          vive DENTRO do AuthProvider. Sem organização ativa (plataforma) ele
          opera em escopo `plataforma`, com defaults seguros. */}
      <BrandingProvider>
        <UsuarioAtualComTenant>
          <AppRoutes />
        </UsuarioAtualComTenant>
      </BrandingProvider>
    </AuthProvider>
  );
}

export default App;
