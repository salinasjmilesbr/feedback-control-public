import AppRoutes from "./routes/AppRoutes";
import { UsuarioAtualProvider } from "./contexts/UsuarioAtualContext";
import { BrandingProvider } from "./contexts/BrandingContext";

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
