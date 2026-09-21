import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { toPublicError } from "../errors/applicationErrors";
import type { DependenciasAcessoColaboradores } from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { EstadoEstrutura } from "../pages/apoioEstrutura";
import { useEstruturaSoberana } from "../pages/useEstruturaSoberana";
import { useAuth } from "./AuthContext";
import "../styles/auth.css";

/**
 * F2-06 + F6-A19 (Issue #319) — formulário mínimo de convite administrativo.
 *
 * A autorização real é server-side: JWT verificado + perfil interno ativo +
 * `usuario_eh_administrador` no tenant escolhido (F5-04 D16/Q3). Aqui só se
 * coleta a INTENÇÃO.
 *
 * O convite VINCULA a conta de acesso à colaboradora JÁ CADASTRADA
 * (`collaborator_id`): conta sem vínculo fica "solta" — não corresponde a
 * nenhuma pessoa da organização. A lista de colaboradoras vem da fotografia
 * soberana own-tenant (mesma porta das telas de alocação) e NÃO é autoridade: o
 * servidor revalida organização + colaboradora e recusa cross-tenant.
 *
 * NENHUMA role/capability é concedida pelo convite: papel funcional é ato
 * administrativo próprio e autoridade administrativa não é auto-servida
 * (F5-04 D15/D16).
 */
type ConvidarUsuarioPageProps = {
  /** Operações da porta (injeção de teste); produção usa o caminho padrão. */
  readonly deps?: DependenciasAcessoColaboradores;
  /** Semente da fotografia soberana (SSR/teste determinístico). */
  readonly estadoInicial?: EstadoEstrutura;
};

function ConvidarUsuarioPage({ deps, estadoInicial }: ConvidarUsuarioPageProps = {}) {
  const { estado, convidarUsuario } = useAuth();
  const [email, setEmail] = useState("");
  const [organizacaoId, setOrganizacaoId] = useState("");
  const [colaboradorId, setColaboradorId] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [enviando, setEnviando] = useState(false);

  const organizacoes = estado.status === "autenticado" ? estado.identidade.organizacoes : [];

  // Fotografia soberana da organização ESCOLHIDA: leitura own-tenant, sem
  // capability e sem RPC de listagem (D16). Nada é inventado localmente.
  const estrutura = useEstruturaSoberana({
    organizacaoAtivaId: organizacaoId || null,
    ...(deps ? { deps } : {}),
    ...(estadoInicial ? { estadoInicial } : {}),
  });
  const colaboradores =
    estrutura.estado.fase === "pronto" ? estrutura.estado.estrutura.colaboradores : [];

  async function enviar(evento: FormEvent) {
    evento.preventDefault();
    setMensagem("");
    setEnviando(true);
    try {
      await convidarUsuario(email.trim(), organizacaoId, colaboradorId);
      setEmail("");
      setOrganizacaoId("");
      setColaboradorId("");
      setMensagem("Convite enviado com sucesso.");
    } catch (erro) {
      setMensagem(toPublicError(erro).message);
    } finally {
      setEnviando(false);
    }
  }

  if (estado.status !== "autenticado") {
    return null;
  }

  return (
    <div className="virtus-page auth-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Convidar usuário</h1>
          <p>
            Envie um convite por e-mail e vincule a conta de acesso à
            colaboradora já cadastrada. Nenhum papel é concedido pelo convite.
          </p>
        </div>
      </section>

      <form className="auth-card auth-form" onSubmit={enviar}>
        <label className="branding-field">
          <span>E-mail</span>
          <input
            type="email"
            autoComplete="off"
            value={email}
            onChange={(evento) => setEmail(evento.target.value)}
            required
          />
        </label>

        <label className="branding-field">
          <span>Organização</span>
          <select
            value={organizacaoId}
            onChange={(evento) => {
              setOrganizacaoId(evento.target.value);
              // A colaboradora pertence ao tenant escolhido: nunca transportar
              // uma seleção de outra organização.
              setColaboradorId("");
            }}
            required
          >
            <option value="">Selecione…</option>
            {organizacoes.map((organizacao) => (
              <option key={organizacao.id} value={organizacao.id}>
                {organizacao.name}
              </option>
            ))}
          </select>
        </label>

        {organizacaoId && estrutura.estado.fase === "carregando" && (
          <p className="auth-message auth-message--neutral" role="status">
            Carregando colaboradoras…
          </p>
        )}

        {organizacaoId && estrutura.estado.fase === "erro" && (
          <p className="auth-message" role="alert">
            Não foi possível carregar as colaboradoras ({estrutura.estado.codigo}).
          </p>
        )}

        <label className="branding-field">
          <span>Colaboradora</span>
          <select
            value={colaboradorId}
            onChange={(evento) => setColaboradorId(evento.target.value)}
            required
            disabled={colaboradores.length === 0}
          >
            <option value="">Selecione…</option>
            {colaboradores.map((colaborador) => (
              <option key={colaborador.collaboratorId} value={colaborador.collaboratorId}>
                {colaborador.nome}
              </option>
            ))}
          </select>
        </label>

        {organizacaoId &&
          estrutura.estado.fase === "pronto" &&
          colaboradores.length === 0 && (
            <p className="auth-message" role="alert">
              Nenhuma colaboradora cadastrada nesta organização: cadastre a pessoa
              antes de convidar.
            </p>
          )}

        {mensagem && (
          <p className="auth-message" role="alert">
            {mensagem}
          </p>
        )}

        <button
          type="submit"
          className="brand-button brand-button--primary"
          disabled={enviando || organizacoes.length === 0 || !colaboradorId}
        >
          {enviando ? "Enviando…" : "Convidar"}
        </button>

        <Link to="/" className="auth-status__entrar">
          Voltar ao início
        </Link>
      </form>
    </div>
  );
}

export default ConvidarUsuarioPage;
