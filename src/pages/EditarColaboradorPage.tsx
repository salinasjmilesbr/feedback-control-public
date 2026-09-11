/**
 * F5-07 — Editar colaborador: LEITURA por UUID e ESCRITA pela porta única.
 *
 * - o parâmetro de rota é `collaboratorId` (UUID canônico). URL legada com
 *   matrícula continua resolvida — mas SEMPRE no servidor, via
 *   `obterColaborador({ matricula })`: ausente/ambígua ⇒ `NOT_FOUND` (fail-closed,
 *   sem heurística de cliente e sem cair para o legado);
 * - a projeção traz `version` e TODA mutação envia `expectedVersion`; divergência
 *   vira estado de CONFLITO explícito (§13.1);
 * - operações separadas: dados de pessoa (`editarColaborador`), matrícula
 *   (`definirIdentificadorColaborador`) e status/licença/inativação
 *   (`alterarStatusColaborador`);
 * - NADA de estrutura organizacional (cargo/unidade/gestor/colegiado/senioridade):
 *   isso é F5-08. Sem alocação soberana a tela diz explicitamente "sem alocação";
 * - nenhuma escrita em `localStorage`, nenhum dual-write e nenhum histórico local.
 */

import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import {
  ehUuid,
  type CodigoPublico,
} from "../infrastructure/supabase/colaboradores/contrato";
import {
  alterarStatusColaborador,
  definirIdentificadorColaborador,
  editarColaborador,
  obterColaborador,
  type ColaboradorSoberano,
  type DependenciasAcessoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import "../styles/collaborator-identity.css";
import "../styles/colaborador-form.css";

/** Estado da leitura/gravação: carregando, erro público, conflito ou projeção. */
export type EstadoEdicaoColaborador =
  | { readonly fase: "carregando" }
  | {
      readonly fase: "erro";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | { readonly fase: "conflito"; readonly mensagem: string }
  | { readonly fase: "pronto"; readonly colaborador: ColaboradorSoberano };

type EditarColaboradorPageProps = {
  /** Operações da porta (injeção de teste); produção usa o caminho padrão. */
  readonly deps?: DependenciasAcessoColaboradores;
  /** Semente de estado (SSR/teste determinístico). */
  readonly estadoInicial?: EstadoEdicaoColaborador;
};

type StatusSoberano = "active" | "leave" | "inactive";

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

const SEM_ORGANIZACAO_ATIVA =
  "Selecione uma organização ativa para editar colaboradores.";

const AVISO_SEM_ALOCACAO =
  "Sem alocação: cargo, unidade, senioridade e gestor vêm da estrutura organizacional (F5-08). " +
  "A alocação não é editada nesta tela.";

function hojeLocal(): string {
  const agora = new Date();
  const offset = agora.getTimezoneOffset();
  return new Date(agora.getTime() - offset * 60000).toISOString().slice(0, 10);
}

function rotuloStatus(status: string): string {
  if (status === "active") return "Ativo";
  if (status === "leave") return "Em licença";
  if (status === "inactive") return "Desligado";
  return status || "—";
}

function possuiAlocacao(colaborador: ColaboradorSoberano): boolean {
  return Boolean(
    colaborador.unitName ??
      colaborador.jobRoleName ??
      colaborador.seniorityName ??
      colaborador.managerFullName
  );
}

/** `operation_id` da mutação (idempotência §13.5) — não é identidade. */
function novoOperationId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (caractere) => {
    const aleatorio = Math.floor(Math.random() * 16);
    const valor = caractere === "x" ? aleatorio : (aleatorio & 0x3) | 0x8;
    return valor.toString(16);
  });
}

function EditarColaboradorPage({
  deps,
  estadoInicial,
}: EditarColaboradorPageProps = {}) {
  const navigate = useNavigate();
  const { collaboratorId } = useParams();
  const { organizacaoAtivaId } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [carregamento, setCarregamento] = useState<{
    readonly chave: string;
    readonly estado: EstadoEdicaoColaborador;
  } | null>(null);
  const [versao, setVersao] = useState(0);
  /** Conflito de versão (§13.1): exibido até a projeção ser recarregada. */
  const [conflito, setConflito] = useState<string | null>(null);

  const identificador = (collaboratorId ?? "").trim();

  /** Chave da leitura corrente: organização + identificador + versão de recarga. */
  const chaveCarregamento = `${organizacaoAtivaId ?? "sem-organizacao"}|${identificador}|${versao}`;

  useEffect(() => {
    if (estadoInicial || !organizacaoAtivaId || !identificador) return;

    let vigente = true;

    // UUID = identidade canônica. Qualquer outro valor é tratado como INTENÇÃO de
    // matrícula e resolvido NO SERVIDOR (nunca no cliente).
    const entrada = ehUuid(identificador)
      ? { collaboratorId: identificador }
      : { matricula: identificador };

    void obterColaborador(
      { ...entrada, organizationId: organizacaoAtivaId },
      depsInjetadas
    ).then((resultado) => {
      if (!vigente) return;
      setCarregamento({
        chave: chaveCarregamento,
        estado: resultado.ok
          ? { fase: "pronto", colaborador: resultado.dados }
          : {
              fase: "erro",
              codigo: resultado.codigo,
              mensagem: resultado.mensagem,
            },
      });
    });

    return () => {
      vigente = false;
    };
  }, [
    chaveCarregamento,
    identificador,
    organizacaoAtivaId,
    estadoInicial,
    depsInjetadas,
  ]);

  /**
   * Estado exibido DERIVADO (sem `setState` síncrono no efeito): sem resultado
   * para a chave corrente a tela está carregando; sem organização ativa ou sem
   * identificador na rota o caminho é fail-closed e nada é lido.
   */
  const estado: EstadoEdicaoColaborador =
    conflito && !estadoInicial
      ? { fase: "conflito", mensagem: conflito }
      : !organizacaoAtivaId && !estadoInicial
        ? { fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ORGANIZACAO_ATIVA }
        : !identificador && !estadoInicial
          ? {
              fase: "erro",
              codigo: "NOT_FOUND",
              mensagem: "Colaborador não informado na rota.",
            }
          : (estadoInicial ??
            (carregamento?.chave === chaveCarregamento
              ? carregamento.estado
              : { fase: "carregando" }));

  function recarregar() {
    setConflito(null);
    setVersao((valor) => valor + 1);
  }

  function voltar() {
    navigate(
      estado.fase === "pronto"
        ? `/colaborador/${estado.colaborador.collaboratorId}`
        : "/"
    );
  }

  return (
    <main className="virtus-page collaborator-form-page">
      <section className="collaborator-form-header">
        <div>
          <button
            type="button"
            className="collaborator-form-back"
            onClick={voltar}
          >
            ← Voltar
          </button>
          <span className="collaborator-form-eyebrow">Cadastro</span>
          <h1>Editar colaborador</h1>
          <p>
            Dados de pessoa, matrícula e status vigentes no PostgreSQL. Cada
            gravação exige a versão lida do servidor.
          </p>
        </div>
      </section>

      {estado.fase === "carregando" && (
        <section className="collaborator-form-empty-state" role="status" aria-live="polite">
          <h2>Carregando colaborador…</h2>
          <p>Consultando a projeção soberana no servidor.</p>
        </section>
      )}

      {estado.fase === "erro" && (
        <section className="collaborator-form-empty-state" role="alert">
          <h2>
            {estado.codigo === "FORBIDDEN"
              ? "Acesso restrito"
              : estado.codigo === "NOT_FOUND"
                ? "Colaborador não encontrado"
                : "Não foi possível carregar o colaborador"}
          </h2>
          <p>{estado.mensagem}</p>
          {estado.codigo === "NOT_FOUND" && (
            <p>
              A matrícula da URL é resolvida no servidor: ausente ou ambígua não
              cai para nenhum cadastro local.
            </p>
          )}
          <button
            type="button"
            className="collaborator-form-btn collaborator-form-btn--secondary"
            onClick={recarregar}
          >
            Tentar novamente
          </button>
        </section>
      )}

      {estado.fase === "conflito" && (
        <section className="collaborator-form-empty-state" role="alert">
          <h2>Conflito de versão</h2>
          <p>{estado.mensagem}</p>
          <p>
            Os dados foram alterados por outra pessoa desde a sua leitura.
            Recarregue a projeção antes de gravar novamente.
          </p>
          <button
            type="button"
            className="collaborator-form-btn collaborator-form-btn--primary"
            onClick={recarregar}
          >
            Recarregar dados
          </button>
        </section>
      )}

      {estado.fase === "pronto" && (
        <FormularioEdicao
          key={`${estado.colaborador.collaboratorId}-${estado.colaborador.version}`}
          colaborador={estado.colaborador}
          organizacaoAtivaId={organizacaoAtivaId ?? ""}
          deps={depsInjetadas}
          aoConflitar={(mensagem) => setConflito(mensagem)}
          aoAtualizar={recarregar}
        />
      )}
    </main>
  );
}

type FormularioEdicaoProps = {
  readonly colaborador: ColaboradorSoberano;
  readonly organizacaoAtivaId: string;
  readonly deps: DependenciasAcessoColaboradores;
  readonly aoConflitar: (mensagem: string) => void;
  readonly aoAtualizar: () => void;
};

function FormularioEdicao({
  colaborador,
  organizacaoAtivaId,
  deps,
  aoConflitar,
  aoAtualizar,
}: FormularioEdicaoProps) {
  const navigate = useNavigate();
  const [nome, setNome] = useState(colaborador.fullName);
  const [email, setEmail] = useState(colaborador.email);
  const [dataAdmissao, setDataAdmissao] = useState(
    colaborador.admissionDate ?? ""
  );
  const [novaMatricula, setNovaMatricula] = useState(colaborador.matricula ?? "");
  const [vigenciaMatricula, setVigenciaMatricula] = useState(hojeLocal);
  const [motivoMatricula, setMotivoMatricula] = useState("");
  const [novoStatus, setNovoStatus] = useState<StatusSoberano>(
    colaborador.status === "leave" || colaborador.status === "inactive"
      ? colaborador.status
      : "active"
  );
  const [vigenciaStatus, setVigenciaStatus] = useState(hojeLocal);
  const [motivoStatus, setMotivoStatus] = useState("");
  const [erro, setErro] = useState("");
  const [aviso, setAviso] = useState("");
  const [processando, setProcessando] = useState(false);

  const expectedVersion = colaborador.version;

  async function salvarPessoa() {
    if (processando) return;
    setErro("");
    setAviso("");

    if (!nome.trim() || !email.trim()) {
      setErro("Preencha nome e e-mail.");
      return;
    }

    setProcessando(true);
    const resultado = await editarColaborador(
      {
        collaboratorId: colaborador.collaboratorId,
        operationId: novoOperationId(),
        expectedVersion,
        fullName: nome.trim(),
        email: email.trim(),
        ...(dataAdmissao ? { admissionDate: dataAdmissao } : {}),
        organizationId: organizacaoAtivaId,
      },
      deps
    );
    setProcessando(false);

    if (!resultado.ok) {
      if (resultado.codigo === "CONFLICT") {
        aoConflitar(resultado.mensagem);
        return;
      }
      setErro(resultado.mensagem);
      return;
    }

    navigate(`/colaborador/${colaborador.collaboratorId}`);
  }

  async function salvarMatricula() {
    if (processando) return;
    setErro("");
    setAviso("");

    if (!/^\d+$/.test(novaMatricula.trim()) || Number(novaMatricula.trim()) <= 0) {
      setErro("Informe uma matrícula válida (somente dígitos).");
      return;
    }
    if (!vigenciaMatricula || !motivoMatricula.trim()) {
      setErro("Informe a vigência e o motivo da alteração de matrícula.");
      return;
    }

    setProcessando(true);
    const resultado = await definirIdentificadorColaborador(
      {
        collaboratorId: colaborador.collaboratorId,
        operationId: novoOperationId(),
        novaMatricula: novaMatricula.trim(),
        vigencia: vigenciaMatricula,
        motivo: motivoMatricula.trim(),
        expectedVersion,
        organizationId: organizacaoAtivaId,
      },
      deps
    );
    setProcessando(false);

    if (!resultado.ok) {
      if (resultado.codigo === "CONFLICT") {
        aoConflitar(resultado.mensagem);
        return;
      }
      setErro(resultado.mensagem);
      return;
    }

    setAviso("Matrícula atualizada no cadastro soberano.");
    setMotivoMatricula("");
    aoAtualizar();
  }

  async function salvarStatus() {
    if (processando) return;
    setErro("");
    setAviso("");

    if (!vigenciaStatus || !motivoStatus.trim()) {
      setErro("Informe a vigência e o motivo da alteração de status.");
      return;
    }

    setProcessando(true);
    const resultado = await alterarStatusColaborador(
      {
        collaboratorId: colaborador.collaboratorId,
        operationId: novoOperationId(),
        novoStatus,
        vigencia: vigenciaStatus,
        motivo: motivoStatus.trim(),
        expectedVersion,
        organizationId: organizacaoAtivaId,
      },
      deps
    );
    setProcessando(false);

    if (!resultado.ok) {
      if (resultado.codigo === "CONFLICT") {
        aoConflitar(resultado.mensagem);
        return;
      }
      setErro(resultado.mensagem);
      return;
    }

    setAviso("Status atualizado no cadastro soberano.");
    setMotivoStatus("");
    aoAtualizar();
  }

  return (
    <>
      <section className="collaborator-form-identity-card">
        <div className="collaborator-identity collaborator-identity--profile">
          <div className="collaborator-identity__body">
            <div className="collaborator-identity__title">
              <strong>{colaborador.fullName}</strong>
              <span className="collaborator-identity__status is-active">
                {rotuloStatus(colaborador.status)}
              </span>
            </div>
            <div className="collaborator-identity__role">
              {colaborador.matricula
                ? `Matrícula ${colaborador.matricula}`
                : "Sem matrícula vigente"}
            </div>
            <div className="collaborator-identity__details">
              <span className="collaborator-identity__detail">
                <span>{colaborador.email}</span>
              </span>
              <span className="collaborator-identity__detail">
                <span>Versão da projeção: {colaborador.version}</span>
              </span>
            </div>
          </div>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">
            01
          </span>
          <div>
            <h2>Dados de pessoa</h2>
            <p>Nome, e-mail e data de admissão do cadastro soberano.</p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field collaborator-field--wide">
            <span>Nome *</span>
            <input
              type="text"
              value={nome}
              onChange={(event) => setNome(event.target.value)}
            />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>E-mail *</span>
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </label>

          <label className="collaborator-field">
            <span>Data de admissão</span>
            <input
              type="date"
              value={dataAdmissao}
              onChange={(event) => setDataAdmissao(event.target.value)}
            />
          </label>
        </div>

        <div className="collaborator-form-actions">
          <button
            type="button"
            className="collaborator-form-btn collaborator-form-btn--primary"
            onClick={() => {
              void salvarPessoa();
            }}
            disabled={processando}
          >
            Salvar dados de pessoa
          </button>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">
            02
          </span>
          <div>
            <h2>Matrícula</h2>
            <p>
              A matrícula vigente é encerrada e uma nova linha é aberta na
              vigência informada. O identificador funcional continua sendo o UUID.
            </p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Nova matrícula *</span>
            <input
              type="text"
              inputMode="numeric"
              value={novaMatricula}
              onChange={(event) => setNovaMatricula(event.target.value)}
            />
          </label>

          <label className="collaborator-field">
            <span>Vigência *</span>
            <input
              type="date"
              value={vigenciaMatricula}
              onChange={(event) => setVigenciaMatricula(event.target.value)}
            />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>Motivo *</span>
            <input
              type="text"
              value={motivoMatricula}
              onChange={(event) => setMotivoMatricula(event.target.value)}
              placeholder="Ex.: correção de matrícula"
            />
          </label>
        </div>

        <div className="collaborator-form-actions">
          <button
            type="button"
            className="collaborator-form-btn collaborator-form-btn--primary"
            onClick={() => {
              void salvarMatricula();
            }}
            disabled={processando}
          >
            Alterar matrícula
          </button>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">
            03
          </span>
          <div>
            <h2>Status, licença e inativação</h2>
            <p>
              Transições permitidas: ativo↔licença, ativo→desligado e
              licença→desligado. A inativação com ocupação vigente é recusada pelo
              servidor (pendências de estrutura).
            </p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Novo status *</span>
            <select
              value={novoStatus}
              onChange={(event) =>
                setNovoStatus(event.target.value as StatusSoberano)
              }
            >
              <option value="active">Ativo</option>
              <option value="leave">Em licença</option>
              <option value="inactive">Desligado</option>
            </select>
          </label>

          <label className="collaborator-field">
            <span>Vigência *</span>
            <input
              type="date"
              value={vigenciaStatus}
              onChange={(event) => setVigenciaStatus(event.target.value)}
            />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>Motivo *</span>
            <input
              type="text"
              value={motivoStatus}
              onChange={(event) => setMotivoStatus(event.target.value)}
              placeholder="Ex.: início de licença médica"
            />
          </label>
        </div>

        {novoStatus === "inactive" && (
          <div className="collaborator-form-warning" role="status">
            Após a inativação não é possível abrir novas avaliações ou
            observações para este colaborador. O histórico existente permanece.
          </div>
        )}

        <div className="collaborator-form-actions">
          <button
            type="button"
            className="collaborator-form-btn collaborator-form-btn--primary"
            onClick={() => {
              void salvarStatus();
            }}
            disabled={processando}
          >
            Alterar status
          </button>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">
            04
          </span>
          <div>
            <h2>Estrutura organizacional (F5-08)</h2>
            <p>Somente leitura: a estrutura é definida no módulo próprio.</p>
          </div>
        </div>

        {possuiAlocacao(colaborador) ? (
          <div className="collaborator-form-grid">
            <div className="collaborator-field">
              <span>Unidade</span>
              <strong>{colaborador.unitName ?? "—"}</strong>
            </div>
            <div className="collaborator-field">
              <span>Cargo / função</span>
              <strong>{colaborador.jobRoleName ?? "—"}</strong>
            </div>
            <div className="collaborator-field">
              <span>Senioridade</span>
              <strong>{colaborador.seniorityName ?? "—"}</strong>
            </div>
            <div className="collaborator-field">
              <span>Gestor</span>
              <strong>{colaborador.managerFullName ?? "—"}</strong>
            </div>
          </div>
        ) : (
          <div className="collaborator-form-empty">{AVISO_SEM_ALOCACAO}</div>
        )}
      </section>

      {erro && (
        <div className="collaborator-form-error" role="alert">
          {erro}
        </div>
      )}

      {aviso && (
        <div className="collaborator-form-info" role="status">
          {aviso}
        </div>
      )}
    </>
  );
}

export default EditarColaboradorPage;
