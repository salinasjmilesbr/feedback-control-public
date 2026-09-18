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
