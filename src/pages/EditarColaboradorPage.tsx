/**
 * F5-07/F5-08 P5 — Editar colaborador: LEITURA por UUID e ESCRITA pela porta
 * única, incluindo a ALOCAÇÃO soberana (ocupação) e o atalho de reporting line.
 *
 * - o parâmetro de rota é `collaboratorId` (UUID canônico). URL legada com
 *   matrícula continua resolvida — mas SEMPRE no servidor, via
 *   `obterColaborador({ matricula })`: ausente/ambígua ⇒ `NOT_FOUND` (fail-closed,
 *   sem heurística de cliente e sem cair para o legado);
 * - a projeção traz `version` e TODA mutação de colaborador envia
 *   `expectedVersion`; divergência vira estado de CONFLITO explícito (§13.1);
 * - operações separadas: dados de pessoa (`editarColaborador`), matrícula
 *   (`definirIdentificadorColaborador`), status (`alterarStatusColaborador`) e
 *   ALOCAÇÃO (`definirOcupacao`/`encerrarOcupacao`) + reporting line
 *   (`definirReportingLine`/`encerrarReportingLine`) — as operações de estrutura
 *   NÃO têm `expectedVersion` no contrato F5-07 (nenhuma versão é fabricada);
 * - "trocar de posição" NÃO é uma operação nova: é `encerrarOcupacao` seguido de
 *   `definirOcupacao`, sem atomicidade fingida e sem rollback local;
 * - nenhuma escrita em `localStorage`, nenhum dual-write e nenhum histórico local.
 */

import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import SeletorPosicao from "../components/SeletorPosicao";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
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
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import {
  confirmarDefinicaoOcupacao,
  confirmarEncerramentoOcupacao,
  confirmarEncerramentoReportingLine,
  confirmarReportingLine,
  confirmarTrocaDePosicao,
  gestorDiretoDaPosicao,
  ocupacaoVigenteDoColaborador,
  reportingVigenteDaPosicao,
} from "./alocacaoSoberana";
import {
  nomeDoColaborador,
  rotuloDaPosicao,
  rotuloVigencia,
  type EstadoEstrutura,
} from "./apoioEstrutura";
import { useEstruturaSoberana } from "./useEstruturaSoberana";
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
  /** Semente da fotografia soberana (SSR/teste determinístico). */
  readonly estruturaInicial?: EstadoEstrutura;
};

type StatusSoberano = "active" | "leave" | "inactive";

/** Mensagem pública da alocação (inclui o estado PARCIAL de troca de posição). */
export type MensagemAlocacao = {
  readonly codigo: CodigoPublico;
  readonly mensagem: string;
  /** `true` quando a 1ª etapa passou e a 2ª não (colaborador sem alocação). */
  readonly parcial: boolean;
};

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

const SEM_ORGANIZACAO_ATIVA =
  "Selecione uma organização ativa para editar colaboradores.";

/**
 * Estado REAL de ausência de estrutura (não é aviso de pendência): sem ocupação
 * vigente a tela diz "sem alocação" e oferece a definição abaixo.
 */
const SEM_ALOCACAO =
  "Sem alocação: não existe ocupação vigente para este colaborador. " +
  "Defina a posição abaixo (a ocupação é uma operação própria, com vigência e motivo).";

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
  estruturaInicial,
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
  /**
   * Mensagem da ALOCAÇÃO no nível da página: sobrevive à recarga da projeção
   * (que remonta o formulário) — necessária para exibir o estado PARCIAL real.
   */
  const [mensagemAlocacao, setMensagemAlocacao] = useState<MensagemAlocacao | null>(null);

  /** Fotografia soberana (posições/ocupações/reporting lines) para alocar. */
  const estrutura = useEstruturaSoberana({
    organizacaoAtivaId,
    deps: depsInjetadas,
    ...(estruturaInicial ? { estadoInicial: estruturaInicial } : {}),
  });

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
          estruturaEstado={estrutura.estado}
          mensagemAlocacao={mensagemAlocacao}
          aoDefinirMensagemAlocacao={setMensagemAlocacao}
          aoConflitar={(mensagem) => setConflito(mensagem)}
          aoAtualizar={recarregar}
          aoRecarregarEstrutura={estrutura.recarregar}
        />
      )}
    </main>
  );
}

type FormularioEdicaoProps = {
  readonly colaborador: ColaboradorSoberano;
  readonly organizacaoAtivaId: string;
  readonly deps: DependenciasAcessoColaboradores;
  /** Fotografia soberana da estrutura (posições/ocupações/reporting lines). */
  readonly estruturaEstado: EstadoEstrutura;
  readonly mensagemAlocacao: MensagemAlocacao | null;
  readonly aoDefinirMensagemAlocacao: (mensagem: MensagemAlocacao | null) => void;
  readonly aoConflitar: (mensagem: string) => void;
  readonly aoAtualizar: () => void;
  readonly aoRecarregarEstrutura: () => void;
};

function FormularioEdicao({
  colaborador,
  organizacaoAtivaId,
  deps,
  estruturaEstado,
  mensagemAlocacao,
  aoDefinirMensagemAlocacao,
  aoConflitar,
  aoAtualizar,
  aoRecarregarEstrutura,
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

  // -------------------------------------------------------------------------
  // ALOCAÇÃO soberana (F5-08 P5): ocupação + reporting line
  //
  // A fotografia soberana (posições vigentes, ocupação vigente do colaborador e
  // reporting line vigente da posição) é a ÚNICA fonte de seleção e de exibição.
  // As operações são as da F5-07, sem `expectedVersion` (o contrato não o tem) e
  // sem nenhuma regra local de ciclo/authority.
  // -------------------------------------------------------------------------
  const [novaPosicaoId, setNovaPosicaoId] = useState("");
  const [trocarPosicaoId, setTrocarPosicaoId] = useState("");
  const [vigenciaAlocacao, setVigenciaAlocacao] = useState(hojeLocal);
  const [motivoAlocacao, setMotivoAlocacao] = useState("");
  const [gestorPosicaoId, setGestorPosicaoId] = useState("");
  const [alocando, setAlocando] = useState(false);

  const fotografia: EstruturaSoberana | null =
    estruturaEstado.fase === "pronto" ? estruturaEstado.estrutura : null;
  const ocupacaoVigente = fotografia
    ? ocupacaoVigenteDoColaborador(fotografia, colaborador.collaboratorId)
    : null;
  const gestorVigente =
    fotografia && ocupacaoVigente
      ? gestorDiretoDaPosicao(fotografia, ocupacaoVigente.posicaoId)
      : null;
  const reportingVigente =
    fotografia && ocupacaoVigente
      ? reportingVigenteDaPosicao(fotografia, ocupacaoVigente.posicaoId)
      : null;

  /** Traduz o desfecho das operações de alocação para o estado da tela. */
  function tratarAlocacao(
    desfecho:
      | { readonly tipo: "sem-motivo" }
      | { readonly tipo: "sem-vigencia" }
      | {
          readonly tipo: "fotografia-desatualizada";
          readonly codigo: CodigoPublico;
          readonly mensagem: string;
        }
      | { readonly tipo: "concluida"; readonly resultado: ResultadoColaboradores<unknown> }
  ) {
    if (desfecho.tipo === "sem-motivo") {
      aoDefinirMensagemAlocacao({
        codigo: "INVALID_INPUT",
        mensagem: "Informe o motivo da alocação.",
        parcial: false,
      });
      return;
    }
    if (desfecho.tipo === "sem-vigencia") {
      aoDefinirMensagemAlocacao({
        codigo: "INVALID_INPUT",
        mensagem: "Informe a vigência da alocação.",
        parcial: false,
      });
      return;
    }
    if (desfecho.tipo === "fotografia-desatualizada") {
      aoDefinirMensagemAlocacao({
        codigo: desfecho.codigo,
        mensagem: desfecho.mensagem,
        parcial: false,
      });
      aoRecarregarEstrutura();
      return;
    }
    if (!desfecho.resultado.ok) {
      aoDefinirMensagemAlocacao({
        codigo: desfecho.resultado.codigo,
        mensagem: desfecho.resultado.mensagem,
        parcial: false,
      });
      if (
        desfecho.resultado.codigo === "CONFLICT" ||
        desfecho.resultado.codigo === "NOT_FOUND"
      ) {
        aoRecarregarEstrutura();
        aoAtualizar();
      }
      return;
    }

    aoDefinirMensagemAlocacao(null);
    setMotivoAlocacao("");
    setNovaPosicaoId("");
    setTrocarPosicaoId("");
    setGestorPosicaoId("");
    // A projeção do colaborador deriva unidade/cargo/senioridade/gestor da
    // ocupação: recarregar é obrigatório após a mutação bem-sucedida.
    aoRecarregarEstrutura();
    aoAtualizar();
  }

  async function definirAlocacao() {
    if (processando || alocando || !fotografia) return;
    if (!novaPosicaoId || !vigenciaAlocacao || !motivoAlocacao.trim()) {
      aoDefinirMensagemAlocacao({
        codigo: "INVALID_INPUT",
        mensagem: "Informe a posição vigente, a vigência e o motivo da ocupação.",
        parcial: false,
      });
      return;
    }

    setAlocando(true);
    const desfecho = await confirmarDefinicaoOcupacao(
      {
        estrutura: fotografia,
        collaboratorId: colaborador.collaboratorId,
        posicaoId: novaPosicaoId,
        vigencia: vigenciaAlocacao,
        motivo: motivoAlocacao,
        operationId: novoOperationId(),
        organizationId: organizacaoAtivaId,
      },
      deps
    );
    setAlocando(false);
    tratarAlocacao(desfecho);
  }

  async function encerrarAlocacao() {
    if (processando || alocando || !fotografia || !ocupacaoVigente) return;
    if (!vigenciaAlocacao || !motivoAlocacao.trim()) {
      aoDefinirMensagemAlocacao({
        codigo: "INVALID_INPUT",
        mensagem: "Informe a vigência e o motivo do encerramento da ocupação.",
        parcial: false,
      });
      return;
    }

    setAlocando(true);
    const desfecho = await confirmarEncerramentoOcupacao(
      {
        estrutura: fotografia,
        collaboratorId: colaborador.collaboratorId,
        vigencia: vigenciaAlocacao,
        motivo: motivoAlocacao,
        operationId: novoOperationId(),
        organizationId: organizacaoAtivaId,
      },
      deps
    );
    setAlocando(false);
    tratarAlocacao(desfecho);
  }

  /**
   * Troca de posição: `encerrarOcupacao` + `definirOcupacao` (duas operações
   * distintas, cada uma com o SEU `operationId`). Sem atomicidade fingida: o
   * desfecho PARCIAL é exibido como estado real (colaborador sem alocação) e o
   * servidor permanece a fonte do estado.
   */
  async function trocarAlocacao() {
    if (processando || alocando || !fotografia) return;
    if (!trocarPosicaoId || !vigenciaAlocacao || !motivoAlocacao.trim()) {
      aoDefinirMensagemAlocacao({
        codigo: "INVALID_INPUT",
        mensagem: "Informe a nova posição vigente, a vigência e o motivo da troca.",
        parcial: false,
      });
      return;
    }

    setAlocando(true);
    const desfecho = await confirmarTrocaDePosicao(
      {
        estrutura: fotografia,
        collaboratorId: colaborador.collaboratorId,
        posicaoId: trocarPosicaoId,
        vigencia: vigenciaAlocacao,
        motivo: motivoAlocacao,
        operationIdEncerramento: novoOperationId(),
        operationIdDefinicao: novoOperationId(),
        organizationId: organizacaoAtivaId,
      },
      deps
    );
    setAlocando(false);

    if (desfecho.tipo === "parcial") {
      aoDefinirMensagemAlocacao({
        codigo: desfecho.codigo,
        mensagem:
          "A ocupação anterior foi ENCERRADA e a nova posição NÃO foi definida: " +
          `o colaborador está SEM ALOCAÇÃO. ${desfecho.mensagem}`,
        parcial: true,
      });
      aoRecarregarEstrutura();
      aoAtualizar();
      return;
    }

    if (desfecho.tipo === "falhou-encerrar") {
      aoDefinirMensagemAlocacao({
        codigo: desfecho.codigo,
        mensagem: `Nada foi alterado: ${desfecho.mensagem}`,
        parcial: false,
      });
      if (desfecho.codigo === "CONFLICT" || desfecho.codigo === "NOT_FOUND") {
        aoRecarregarEstrutura();
      }
      return;
    }

    if (desfecho.tipo !== "concluida") {
      tratarAlocacao(desfecho);
      return;
    }

    // Encerrou E definiu: a projeção deriva a estrutura da ocupação vigente.
    aoDefinirMensagemAlocacao(null);
    setMotivoAlocacao("");
    setNovaPosicaoId("");
    setTrocarPosicaoId("");
    setGestorPosicaoId("");
    aoRecarregarEstrutura();
    aoAtualizar();
  }

  async function salvarGestor() {
    if (processando || alocando || !fotografia || !ocupacaoVigente) return;
    if (!gestorPosicaoId || !vigenciaAlocacao || !motivoAlocacao.trim()) {
      aoDefinirMensagemAlocacao({
        codigo: "INVALID_INPUT",
        mensagem: "Informe a posição gerente, a vigência e o motivo.",
        parcial: false,
      });
      return;
    }

    setAlocando(true);
    const desfecho = await confirmarReportingLine(
      {
        estrutura: fotografia,
        subordinatePositionId: ocupacaoVigente.posicaoId,
        managerPositionId: gestorPosicaoId,
        vigencia: vigenciaAlocacao,
        motivo: motivoAlocacao,
        operationId: novoOperationId(),
        organizationId: organizacaoAtivaId,
      },
      deps
    );
    setAlocando(false);
    tratarAlocacao(desfecho);
  }

  async function encerrarGestor() {
    if (processando || alocando || !fotografia || !ocupacaoVigente) return;
    if (!vigenciaAlocacao || !motivoAlocacao.trim()) {
      aoDefinirMensagemAlocacao({
        codigo: "INVALID_INPUT",
        mensagem: "Informe a vigência e o motivo do encerramento da reporting line.",
        parcial: false,
      });
      return;
    }

    setAlocando(true);
    const desfecho = await confirmarEncerramentoReportingLine(
      {
        estrutura: fotografia,
        subordinatePositionId: ocupacaoVigente.posicaoId,
        vigencia: vigenciaAlocacao,
        motivo: motivoAlocacao,
        operationId: novoOperationId(),
        organizationId: organizacaoAtivaId,
      },
      deps
    );
    setAlocando(false);
    tratarAlocacao(desfecho);
  }

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

      <section className="collaborator-form-card" data-testid="alocacao-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">
            04
          </span>
          <div>
            <h2>Alocação</h2>
            <p>
              Ocupação e reporting line são operações soberanas próprias, com
              vigência e motivo. A posição é escolhida por identificador (UUID);
              cargo, unidade e senioridade são rótulos.
            </p>
          </div>
        </div>

        {estruturaEstado.fase === "carregando" && (
          <div className="collaborator-form-info" role="status">
            Carregando as posições soberanas…
          </div>
        )}

        {estruturaEstado.fase === "erro" && (
          <div className="collaborator-form-error" role="alert">
            <strong>Não foi possível carregar as posições</strong>
            <p>
              {estruturaEstado.mensagem} ({estruturaEstado.codigo})
            </p>
            <p>A alocação fica indisponível até a leitura soberana responder.</p>
          </div>
        )}

        {fotografia && (
          <>
            {ocupacaoVigente ? (
              <div className="collaborator-form-grid" data-testid="alocacao-vigente">
                <div className="collaborator-field collaborator-field--wide">
                  <span>Posição vigente</span>
                  <strong>{rotuloDaPosicao(fotografia, ocupacaoVigente.posicaoId)}</strong>
                </div>
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
                  <span>Vigência da ocupação</span>
                  <strong>
                    {rotuloVigencia(ocupacaoVigente.validFrom, ocupacaoVigente.validTo)}
                  </strong>
                </div>
                <div className="collaborator-field">
                  <span>Gestor direto (reporting line)</span>
                  <strong>
                    {gestorVigente
                      ? gestorVigente.collaboratorId
                        ? nomeDoColaborador(fotografia, gestorVigente.collaboratorId)
                        : `${rotuloDaPosicao(fotografia, gestorVigente.managerPositionId)} (sem ocupante)`
                      : "sem gestor formal (posição raiz)"}
                  </strong>
                </div>
                <div className="collaborator-field">
                  <span>Identidade da posição</span>
                  <strong>{ocupacaoVigente.posicaoId}</strong>
                </div>
              </div>
            ) : (
              <div className="collaborator-form-empty" data-testid="alocacao-sem">
                {SEM_ALOCACAO}
              </div>
            )}

            <div className="collaborator-form-grid">
              {!ocupacaoVigente && (
                <SeletorPosicao
                  id="editar-colaborador-posicao"
                  estrutura={fotografia}
                  valor={novaPosicaoId}
                  aoMudar={setNovaPosicaoId}
                  rotulo="Posição vigente (unidade • cargo • senioridade) *"
                  desabilitado={processando || alocando}
                />
              )}

              {ocupacaoVigente && (
                <SeletorPosicao
                  id="editar-colaborador-trocar-posicao"
                  estrutura={fotografia}
                  valor={trocarPosicaoId}
                  aoMudar={setTrocarPosicaoId}
                  rotulo="Trocar para a posição (encerra a atual e abre a nova) *"
                  vazio="Selecione a nova posição…"
                  excluirPosicaoId={ocupacaoVigente.posicaoId}
                  desabilitado={processando || alocando}
                />
              )}

              <label className="collaborator-field">
                <span>Vigência *</span>
                <input
                  type="date"
                  value={vigenciaAlocacao}
                  onChange={(evento) => setVigenciaAlocacao(evento.target.value)}
                  disabled={processando || alocando}
                />
              </label>

              <label className="collaborator-field collaborator-field--wide">
                <span>Motivo *</span>
                <input
                  type="text"
                  value={motivoAlocacao}
                  onChange={(evento) => setMotivoAlocacao(evento.target.value)}
                  disabled={processando || alocando}
                />
              </label>
            </div>

            {ocupacaoVigente && (
              <div className="collaborator-form-grid">
                <SeletorPosicao
                  id="editar-colaborador-gestor"
                  estrutura={fotografia}
                  valor={gestorPosicaoId}
                  aoMudar={setGestorPosicaoId}
                  rotulo="Posição do gestor (reporting line)"
                  vazio="Selecione a posição gerente…"
                  excluirPosicaoId={ocupacaoVigente.posicaoId}
                  mostrarOcupante
                  desabilitado={processando || alocando}
                />
              </div>
            )}

            <div className="collaborator-form-actions">
              {!ocupacaoVigente && (
                <button
                  type="button"
                  className="collaborator-form-btn collaborator-form-btn--primary"
                  onClick={() => {
                    void definirAlocacao();
                  }}
                  disabled={processando || alocando}
                  data-testid="alocacao-definir"
                >
                  Definir ocupação
                </button>
              )}

              {ocupacaoVigente && (
                <>
                  <button
                    type="button"
                    className="collaborator-form-btn collaborator-form-btn--primary"
                    onClick={() => {
                      void trocarAlocacao();
                    }}
                    disabled={processando || alocando}
                    data-testid="alocacao-trocar"
                  >
                    Trocar posição
                  </button>

                  <button
                    type="button"
                    className="collaborator-form-btn collaborator-form-btn--secondary"
                    onClick={() => {
                      void encerrarAlocacao();
                    }}
                    disabled={processando || alocando}
                    data-testid="alocacao-encerrar"
                  >
                    Encerrar ocupação
                  </button>

                  <button
                    type="button"
                    className="collaborator-form-btn collaborator-form-btn--secondary"
                    onClick={() => {
                      void salvarGestor();
                    }}
                    disabled={processando || alocando || !gestorPosicaoId}
                    data-testid="alocacao-definir-gestor"
                  >
                    {reportingVigente ? "Alterar gestor" : "Definir gestor"}
                  </button>

                  {reportingVigente && (
                    <button
                      type="button"
                      className="collaborator-form-btn collaborator-form-btn--secondary"
                      onClick={() => {
                        void encerrarGestor();
                      }}
                      disabled={processando || alocando}
                      data-testid="alocacao-encerrar-gestor"
                    >
                      Encerrar reporting line
                    </button>
                  )}
                </>
              )}
            </div>

            <p className="collaborator-form-empty">
              “Trocar posição” executa DUAS operações soberanas na ordem:
              encerrar a ocupação atual e definir a nova. Não há transação única
              no cliente: se a segunda etapa falhar, o estado real (sem alocação)
              é exibido e a leitura é recarregada.
            </p>
          </>
        )}
      </section>

      {mensagemAlocacao && (
        <div
          className="collaborator-form-error"
          role="alert"
          data-testid="alocacao-mensagem"
        >
          <strong>
            {mensagemAlocacao.parcial
              ? "Estado parcial: colaborador SEM ALOCAÇÃO"
              : mensagemAlocacao.codigo === "FORBIDDEN"
                ? "Acesso restrito"
                : mensagemAlocacao.codigo === "CONFLICT"
                  ? "Conflito na alocação"
                  : mensagemAlocacao.codigo === "INVALID_INPUT"
                    ? "Dados da alocação"
                    : "Não foi possível concluir a alocação"}
          </strong>
          <p>
            {mensagemAlocacao.mensagem} ({mensagemAlocacao.codigo})
          </p>
          {mensagemAlocacao.parcial && (
            <p>
              Nada foi restaurado localmente: a ocupação anterior foi encerrada no
              servidor e a nova não existe.
            </p>
          )}
          <div className="collaborator-form-actions">
            <button
              type="button"
              className="collaborator-form-btn collaborator-form-btn--secondary"
              onClick={() => {
                aoDefinirMensagemAlocacao(null);
                aoRecarregarEstrutura();
                aoAtualizar();
              }}
            >
              Recarregar dados
            </button>
          </div>
        </div>
      )}

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
