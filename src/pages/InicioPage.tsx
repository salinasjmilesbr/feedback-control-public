import ColaboradoresPage from "./ColaboradoresPage";
import MinhaAvaliacaoPage from "./MinhaAvaliacaoPage";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";

function InicioPage() {
  const { usuarioAtual } = useUsuarioAtual();

  if (!usuarioAtual) {
    return <div style={{ padding: "30px" }}><h1>Usuário atual não definido</h1></div>;
  }

  if (usuarioAtual.funcao === "ANALISTA") {
    return <MinhaAvaliacaoPage />;
  }

  return <ColaboradoresPage />;
}

export default InicioPage;
