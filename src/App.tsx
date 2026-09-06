import AppRoutes from "./routes/AppRoutes";
import { UsuarioAtualProvider } from "./contexts/UsuarioAtualProvider";
import { BrandingProvider } from "./contexts/BrandingProvider";
import { AuthProvider } from "./auth/AuthProvider";

function App() {
  return (
    <BrandingProvider>
      <AuthProvider>
        <UsuarioAtualProvider>
          <AppRoutes />
        </UsuarioAtualProvider>
      </AuthProvider>
    </BrandingProvider>
  );
}

export default App;
