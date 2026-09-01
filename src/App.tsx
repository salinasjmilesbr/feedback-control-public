import AppRoutes from "./routes/AppRoutes";
import { UsuarioAtualProvider } from "./contexts/UsuarioAtualProvider";
import { BrandingProvider } from "./contexts/BrandingProvider";

function App() {
  return (
    <BrandingProvider>
      <UsuarioAtualProvider>
        <AppRoutes />
      </UsuarioAtualProvider>
    </BrandingProvider>
  );
}

export default App;
