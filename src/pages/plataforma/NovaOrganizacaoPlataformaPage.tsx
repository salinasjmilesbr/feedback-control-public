import { useEffect, useMemo, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { TechnicalError, ValidationError, toPublicError } from "../../errors/applicationErrors";
import {
  obterProvisionamentoPlataforma,
  type DependenciasAcessoPlataforma,
} from "../../services/plataforma/controladorProvisionamento";
import type { ProvisionamentoPlataforma } from "../../application/ports/ProvisionamentoPlataforma";
import {
  montarEntradaProvisao,
  type FormaPrimeiroAdmin,
} from "../../services/plataforma/formularioPlataforma";
import "../../styles/auth.css";

/**
 * F6-A03 (Issue #266) — UI MÍNIMA DE PLATAFORMA (§6.5, D18–D21).
 *
 * Superfície MÍNIMA pela qual a jornada real do produto nasce: o operador
 * autorizado cria a organização e define o primeiro Admin. Nada além disso:
 *
 * - NÃO lista tenants, NÃO gerencia operadores, roles, planos ou lifecycle (D21);
 * - NÃO decide autorização: o self-check (`souOperadorDaPlataforma`) é UX e a
 *   decisão real é da Edge + RPC soberana (D20). Alterar/remover esta página não
 *   muda veredito nenhum do servidor;
 * - NÃO exibe identificadores internos, tokens, hashes nem listas: no sucesso
 *   mostra apenas o NOME da organização criada e a orientação de login
 *   (critério 24);
 * - NÃO usa `localStorage`, RPC do banco nem credencial privilegiada.
 *
 * Estados: verificando autorização → negativa neutra (não-operador) →
 * formulário → enviando → sucesso/erro público (taxonomia F0-05).
 */

/**
 * Estados do formulário. "Ambiente sem caminho soberano" NÃO é um estado:
 * é DERIVADO da ausência de controlador na renderização (fail-closed).
 */
export type FasePlataforma = "verificando" | "negado" | "formulario" | "concluido";

/** Negativa NEUTRA: nada sobre o que a superfície faz é revelado (D20). */
export function NegativaNeutra() {
  return (
    <div className="virtus-page auth-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Não autorizado</h1>
          <p>Esta operação não está disponível para a sua conta.</p>
        </div>
      </section>
      <section className="auth-card">
        <Link to="/" className="auth-status__entrar">
          Voltar
        </Link>
      </section>
    </div>
  );
}

/** Ambiente sem caminho soberano: indisponibilidade EXPLÍCITA (fail-closed). */
export function ServicoIndisponivel() {
  return (
    <div className="virtus-page auth-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Serviço indisponível</h1>
          <p>Este ambiente não oferece a operação de provisionamento.</p>
        </div>
      </section>
      <section className="auth-card">
        <Link to="/" className="auth-status__entrar">
          Voltar
        </Link>
      </section>
    </div>
  );
}

/**
 * Confirmação: exibe APENAS o nome informado — nunca o UUID interno, hash ou
 * código de erro (critério 24).
 */
export function ConfirmacaoOrganizacao({ nome }: { readonly nome: string }) {
  return (
    <div className="virtus-page auth-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Organização criada</h1>
          <p>
            A organização <strong>{nome}</strong> foi criada e o primeiro Admin já
            pode entrar no Virtus com a identidade definida.
          </p>
        </div>
      </section>
      <section className="auth-card">
        <p className="auth-message" role="status">
          Peça ao primeiro Admin para acessar a tela de login e concluir a entrada
          na nova organização.
        </p>
        <Link to="/" className="auth-status__entrar">
          Voltar ao início
        </Link>
      </section>
    </div>
  );
}

export interface PropsFormularioNovaOrganizacao {
  readonly nome: string;
  readonly forma: FormaPrimeiroAdmin;
  readonly email: string;
  /** F6-A11/D22-D23: nome humano do primeiro Admin (obrigatório). */
  readonly nomeAdmin: string;
  /** F6-A11/D23/D28: matrícula declarada do primeiro Admin (obrigatória). */
  readonly matriculaAdmin: string;
  readonly mensagem: string;
  readonly enviando: boolean;
  readonly aoMudarNome: (valor: string) => void;
  readonly aoMudarForma: (valor: FormaPrimeiroAdmin) => void;
  readonly aoMudarEmail: (valor: string) => void;
  readonly aoMudarNomeAdmin: (valor: string) => void;
  readonly aoMudarMatriculaAdmin: (valor: string) => void;
  readonly aoEnviar: (evento: FormEvent) => void;
}

/**
 * Formulário MÍNIMO: nome da organização, identificação do primeiro Admin
 * ("eu mesmo" ou e-mail) e a identidade FUNCIONAL dele (nome humano e matrícula
 * — F6-A11/D23). Nenhuma escolha de role, organização, tenant ou usuário é
 * oferecida (critério 23).
 */
export function FormularioNovaOrganizacao({
  nome,
  forma,
  email,
  nomeAdmin,
  matriculaAdmin,
  mensagem,
  enviando,
  aoMudarNome,
  aoMudarForma,
  aoMudarEmail,
  aoMudarNomeAdmin,
  aoMudarMatriculaAdmin,
  aoEnviar,
}: PropsFormularioNovaOrganizacao) {
  return (
    <div className="virtus-page auth-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Nova organização</h1>
          <p>Crie uma organização e defina o primeiro Admin dela.</p>
        </div>
      </section>

      <form className="auth-card auth-form" onSubmit={aoEnviar}>
        <label className="branding-field">
          <span>Nome da organização</span>
          <input
            type="text"
            autoComplete="off"
            value={nome}
            onChange={(evento) => aoMudarNome(evento.target.value)}
            required
          />
        </label>

        <label className="branding-field">
          <span>Primeiro Admin</span>
          <select
            value={forma}
            onChange={(evento) => aoMudarForma(evento.target.value === "outra" ? "outra" : "eu")}
          >
            <option value="eu">Eu mesmo</option>
            <option value="outra">Outra pessoa (e-mail)</option>
          </select>
        </label>

        {forma === "outra" && (
          <label className="branding-field">
            <span>E-mail do primeiro Admin</span>
            <input
              type="email"
              autoComplete="off"
              value={email}
              onChange={(evento) => aoMudarEmail(evento.target.value)}
              required
            />
          </label>
        )}

        <label className="branding-field">
          <span>Nome do primeiro Admin</span>
          <input
            type="text"
            autoComplete="off"
            value={nomeAdmin}
            onChange={(evento) => aoMudarNomeAdmin(evento.target.value)}
            required
          />
        </label>

        <label className="branding-field">
          <span>Matrícula do primeiro Admin</span>
          <input
            type="text"
            autoComplete="off"
            value={matriculaAdmin}
            onChange={(evento) => aoMudarMatriculaAdmin(evento.target.value)}
            required
          />
        </label>

        {mensagem && (
          <p className="auth-message" role="alert">
            {mensagem}
          </p>
        )}

        <button type="submit" className="brand-button brand-button--primary" disabled={enviando}>
          {enviando ? "Criando…" : "Criar organização"}
        </button>

        <Link to="/" className="auth-status__entrar">
          Voltar
        </Link>
      </form>
    </div>
  );
}

export interface PropsNovaOrganizacaoPlataforma {
  /**
   * Injeção do controlador (teste). `undefined` = usa o caminho de produção
   * (fail-closed quando o ambiente não oferece a superfície soberana).
   */
  readonly provisionamento?: ProvisionamentoPlataforma | null;
  /** Injeção do acesso (teste) — usada apenas quando `provisionamento` é `undefined`. */
  readonly deps?: DependenciasAcessoPlataforma;
}

function NovaOrganizacaoPlataformaPage({
  provisionamento,
  deps,
}: PropsNovaOrganizacaoPlataforma = {}) {
  /**
   * Caminho soberano resolvido UMA vez (memoizado): `null` significa ambiente
   * sem superfície de provisionamento — indisponibilidade EXPLÍCITA, derivada da
   * renderização (fail-closed, sem estado e sem fallback local).
   */
  const controlador = useMemo(
    () => (provisionamento === undefined ? obterProvisionamentoPlataforma(deps) : provisionamento),
    [provisionamento, deps]
  );

  const [fase, setFase] = useState<FasePlataforma>("verificando");
  const [nome, setNome] = useState("");
  const [forma, setForma] = useState<FormaPrimeiroAdmin>("eu");
  const [email, setEmail] = useState("");
  // F6-A11/D23: identidade funcional mínima do primeiro Admin (dados a criar).
  const [nomeAdmin, setNomeAdmin] = useState("");
  const [matriculaAdmin, setMatriculaAdmin] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [nomeConfirmado, setNomeConfirmado] = useState("");

  useEffect(() => {
    let vigente = true;
    if (!controlador) return undefined;

    // `setFase` só ocorre no callback ASSÍNCRONO do self-check (nunca de forma
    // síncrona no corpo do efeito) e é protegido pelo guard de vigência.
    void controlador.souOperadorDaPlataforma().then((operador) => {
      if (!vigente) return;
      setFase(operador ? "formulario" : "negado");
    });

    return () => {
      vigente = false;
    };
  }, [controlador]);

  async function enviar(evento: FormEvent) {
    evento.preventDefault();
    setMensagem("");
    if (!controlador) return;

    setEnviando(true);
    try {
      let usuarioAutenticadoId: string | null = null;
      if (forma === "eu") {
        // "Eu mesmo": a identidade do PRÓPRIO operador vem da sessão local; a Edge
        // re-deriva o ator do JWT (isto é o ALVO da concessão, não autoridade).
        usuarioAutenticadoId = await controlador.identidadeDoOperadorAutenticado();
      }

      const montagem = montarEntradaProvisao({
        operacaoId: crypto.randomUUID(),
        nome,
        nomeAdmin,
        matriculaAdmin,
        forma,
        email,
        usuarioAutenticadoId,
      });
      if (!montagem.ok) {
        throw montagem.motivo === "identidade" ? new TechnicalError() : new ValidationError();
      }

      await controlador.provisionarOrganizacao(montagem.entrada);

      // Critério 24: guarda apenas o NOME informado — o UUID nunca é exibido.
      setNomeConfirmado(montagem.entrada.organizationName);
      setFase("concluido");
    } catch (erro) {
      setMensagem(toPublicError(erro).message);
    } finally {
      setEnviando(false);
    }
  }

  // Sem caminho soberano: indisponibilidade explícita (nada de fallback local).
  if (!controlador) return <ServicoIndisponivel />;

  if (fase === "verificando") {
    // Nada de formulário antes de o guard/self-check resolver (fail-closed).
    return (
      <div className="auth-loading" role="status" aria-live="polite">
        Verificando autorização…
      </div>
    );
  }

  if (fase === "negado") return <NegativaNeutra />;
  if (fase === "concluido") return <ConfirmacaoOrganizacao nome={nomeConfirmado} />;

  return (
    <FormularioNovaOrganizacao
      nome={nome}
      forma={forma}
      email={email}
      nomeAdmin={nomeAdmin}
      matriculaAdmin={matriculaAdmin}
      mensagem={mensagem}
      enviando={enviando}
      aoMudarNome={setNome}
      aoMudarForma={setForma}
      aoMudarEmail={setEmail}
      aoMudarNomeAdmin={setNomeAdmin}
      aoMudarMatriculaAdmin={setMatriculaAdmin}
      aoEnviar={enviar}
    />
  );
}

export default NovaOrganizacaoPlataformaPage;
