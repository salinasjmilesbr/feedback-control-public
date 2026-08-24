import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";

function UsuarioAtualBar() {
  const { usuarioAtual, usuariosDisponiveis, selecionarUsuario } =
    useUsuarioAtual();

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: "16px",
        padding: "12px 30px",
        borderBottom: "1px solid #ddd",
        backgroundColor: "#F8F1FF",
        flexWrap: "wrap",
      }}
    >
      <div>
        <strong>Usuário atual</strong>
        <div style={{ fontSize: "13px", color: "#666", marginTop: "2px" }}>
          Modo de desenvolvimento para testar permissões
        </div>
      </div>

      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "12px",
          flexWrap: "wrap",
        }}
      >
        <select
          value={usuarioAtual?.matricula ?? ""}
          onChange={(event) => selecionarUsuario(Number(event.target.value))}
          style={{
            minWidth: "280px",
            padding: "9px 12px",
            borderRadius: "8px",
            border: "1px solid #bbb",
            backgroundColor: "#fff",
          }}
        >
          {usuariosDisponiveis.map((usuario) => (
            <option key={usuario.matricula} value={usuario.matricula}>
              {usuario.nome} -{" "}
              {usuario.funcao === "GERENTE"
                ? "Gerente"
                : usuario.funcao === "COORDENADOR"
                ? "Coordenador"
                : "Analista"}
            </option>
          ))}
        </select>

        {usuarioAtual && (
          <span
            style={{
              padding: "7px 11px",
              borderRadius: "999px",
              backgroundColor: "#660099",
              color: "#fff",
              fontSize: "12px",
              fontWeight: "bold",
            }}
          >
            {usuarioAtual.funcao === "GERENTE"
              ? "GERENTE"
              : usuarioAtual.funcao === "COORDENADOR"
              ? "COORDENADOR"
              : "ANALISTA"}
          </span>
        )}
      </div>
    </div>
  );
}

export default UsuarioAtualBar;
