import AppRoutes from "./routes/AppRoutes";
import UsuarioAtualBar from "./components/UsuarioAtualBar";
import { UsuarioAtualProvider } from "./contexts/UsuarioAtualContext";

function App() {
  return (
    <UsuarioAtualProvider>
      <UsuarioAtualBar />
      <AppRoutes />
    </UsuarioAtualProvider>
  );
}

export default App;
