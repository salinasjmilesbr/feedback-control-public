import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { useAuth } from "../auth/AuthContext";

/**
 * Issue #317 (Fase 2) — CONTROLES DO TENANT no header universal.
 *
 * Escopo depois da reconstrução do shell: a marca oficial (`VIRTUS · [empresa]`)
 * e a sessão real (`AuthStatus`) passaram a ser responsabilidade do
 * `ShellVirtus`; aqui ficam apenas os controles que SÓ existem no contexto de
 * empresa:
 *
 * - seleção da ORGANIZAÇÃO ativa (aparece com mais de uma disponível);
 * - seletor de identidade **simulação DEV** (F2-09): colaboradores sintéticos do
 *   seed local. Fora de DEV explícito não é renderizado — a identidade real vem
 *   do Supabase Auth e nunca há fallback simulado.
 *
 * Este componente é estrutura SOBERANA DE TENANT: por isso não pode ser montado
 * pela superfície de plataforma (D19, guarda estática em
 * `src/authorization/estruturaUiSeguranca.test.ts`).
 *
 * §6 do brand guide: o header é simples — sem avatar e sem menu. O perfil
 * simulado (`avatar`/`role-badge`) foi removido do header; a função continua
 * legível no próprio rótulo da opção do seletor.
 */
function UsuarioAtualBar() {
  const {
    usuarioAtual,
    usuariosDisponiveis,
    selecionarUsuario,
    simulacaoDevAtiva,
  } = useUsuarioAtual();
  const { organizacoesDisponiveis, organizacaoAtivaId, selecionarOrganizacao } =
    useAuth();

  const impersonacaoDevVisivel =
    simulacaoDevAtiva === true && usuariosDisponiveis.length > 0;
  const seletorDeOrganizacao = organizacoesDisponiveis.length > 1;

  if (!seletorDeOrganizacao && !impersonacaoDevVisivel) return null;

  return (
    <>
      {seletorDeOrganizacao && (
        <div className="virtus-shell__control">
          <label htmlFor="organizacao-ativa">Organização</label>
          <select
            id="organizacao-ativa"
            aria-label="Organização ativa"
            value={organizacaoAtivaId ?? ""}
            onChange={(event) => selecionarOrganizacao(event.target.value)}
          >
            {organizacoesDisponiveis.map((organizacao) => (
              <option key={organizacao.id} value={organizacao.id}>
                {organizacao.name}
              </option>
            ))}
          </select>
        </div>
      )}

      {impersonacaoDevVisivel && (
        <div className="virtus-shell__control">
          <label htmlFor="usuario-atual">Usuário atual — simulação DEV</label>
          <select
            id="usuario-atual"
            aria-label="Usuário atual — simulação DEV"
            value={usuarioAtual?.matricula ?? ""}
            onChange={(event) => selecionarUsuario(Number(event.target.value))}
          >
            {usuariosDisponiveis.map((usuario) => (
              <option key={usuario.matricula} value={usuario.matricula}>
                {usuario.nome} -{" "}
                {usuario.funcao === "GERENTE"
                  ? "Gerente"
                  : usuario.funcao === "COORDENADOR"
                  ? "Coordenador"
                  : usuario.funcao === "CONSULTOR"
                  ? "Consultor"
                  : usuario.funcao === "ESTAGIARIO"
                  ? "Estagiário"
                  : "Analista"}
              </option>
            ))}
          </select>
        </div>
      )}
    </>
  );
}

export default UsuarioAtualBar;
