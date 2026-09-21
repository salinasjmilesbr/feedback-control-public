/**
 * F5-07 — Detalhe do colaborador: LEITURA SOBERANA + histórico soberano.
 *
 * - a identidade canônica é o `collaboratorId` (UUID) da rota; URL legada com
 *   matrícula é resolvida NO SERVIDOR (`obterColaborador({ matricula })`) e
 *   ausente/ambígua vira estado de erro (fail-closed, sem heurística local);
 * - o histórico organizacional passa a vir da trilha append-only
 *   (`obterHistoricoColaborador`) — eventos soberanos, com autor e vigência;
 * - NÃO existe leitura de `colaboradorStorage` nem de
 *   `historicoOrganizacionalStorage` no render: o acervo legado de avaliações
 *   (ainda não migrado — F5-06/F5-09) permanece, porém claramente ROTULADO como
 *   legado, sem autoridade sobre identidade ou estrutura;
 * - **F5-11 P5 (Issue #250), L4:** as observações do colaborador-ALVO vêm da
 *   PORTA SOBERANA (`acessoObservacoesSoberanas` → Edge `observacoes`), por
 *   escopo de GESTÃO revalidado server-side — sem acervo do navegador, sem
 *   dual-read e sem armazenamento local (D9/D13/D22). A identidade do alvo é o
 *   UUID `collaborator_id`; o rótulo do AUTOR vem dos colaboradores que a
 *   estrutura soberana já carregou (nenhuma resolução de identidade local é
 *   inventada);
 * - estrutura organizacional: exibida quando existe alocação soberana; ausente ⇒
 *   "sem alocação" explícito (nada de estrutura sintética — F5-08);
 * - nenhuma decisão de acesso por `funcao`/cargo textual: a leitura é do servidor
 *   (negação ⇒ estado restrito explícito) e os botões de ação não decidem nada.
 */

import {
  useEffect,
  useLayoutEffect,
  useState,
  type CSSProperties,
  type ReactNode,
} from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import {
  ehUuid,
  type CodigoPublico,
} from "../infrastructure/supabase/colaboradores/contrato";
import type { ObservacaoSoberana } from "../application/ports/ObservationRepository";
import {
  formatarNotaAvaliacao,
  getTextoNotaAvaliacao,
  possuiNotaAvaliacao,
} from "../services/apresentacaoNota";
import { obterRepositorioObservacoesSoberanas } from "../services/acessoObservacoesSoberanas";
import { criarControladorObservacoes } from "../services/observacoesSoberanas/controladorObservacoes";
import type { FonteDeRotulosDeColaborador } from "../services/observacoesSoberanas/mapeadorObservacaoUi";
import ObservacoesColaborador from "../components/ObservacoesColaborador";
import {
  FILTRO_OBSERVACOES_TODOS,
  type FiltroCicloObservacoesSoberano,
} from "../components/filtroObservacoesPorCiclo";
// F5-09 P5 — a leitura LEGADA de ciclos (usada só para ROTULAR a seção de
// avaliações do acervo local) vem da PONTE ISOLADA `cicloApresentacaoLegada`, que
// não importa o caminho soberano: é esse isolamento que a guarda anti-dual-read
// (`src/services/ciclosSoberanosSemFallback.test.ts`) exige de quem usa
// `acessoCiclosSoberanos` para o painel de observações (F5-11 P5).
import { getCiclosAvaliacao } from "./cicloApresentacaoLegada";
// F5-11 P5 (Issue #250): ciclos SOBERANOS para o painel de observações — a
// criação gerencial exige `cycleId` de `evaluation_cycles` (nunca do acervo
// local, que permanece apenas como leitura legada das avaliações).
import {
  obterRepositorioCiclosSoberanos,
  type CicloSoberano,
} from "../services/acessoCiclosSoberanos";
import {
  obterColaborador,
  obterHistoricoColaborador,
  type ColaboradorSoberano,
  type DependenciasAcessoColaboradores,
  type EventoColaborador,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import { getEscalaAvaliacao, getItemEscalaPorNota } from "../services/escalaAvaliacaoStorage";
import { getFeedbacksAdministrativosByColaborador } from "../services/feedbackStorage";
import type { Colaborador, StatusColaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import "../styles/colaborador-detalhe.css";
import "../styles/collaborator-identity.css";
import {
  getAcaoConsultaHistoricoAdministrativo,
  ordenarHistoricoAdministrativo,
} from "./historicoAvaliacaoAdministrativa";
import { getStatusAvaliacaoAdministrativa } from "./statusAvaliacaoAdministrativa";
import {
  colegiadoVigente,
  nomeDoColaborador,
  formatarData as formatarDataCivil,
  rotuloDaPosicao,
  rotuloVigencia,
  type EstadoEstrutura,
} from "./apoioEstrutura";
import {
  gestorDiretoDaPosicao,
  ocupacaoVigenteDoColaborador,
  reportingVigenteDaPosicao,
} from "./alocacaoSoberana";
import {
  observacoesDoAlvo,
  resumoDeObservacoesPorTipo,
  type EstadoObservacoesSoberanas,
  type MapaDeNomesDeColaborador,
} from "./observacoesSoberanasDaPagina";
import { useEstruturaSoberana } from "./useEstruturaSoberana";

/** Estado da leitura soberana do colaborador e da sua trilha de eventos. */
export type EstadoDetalheColaborador =
  | { readonly fase: "carregando" }
  | {
      readonly fase: "erro";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | {
      readonly fase: "pronto";
      readonly colaborador: ColaboradorSoberano;
      readonly historico: readonly EventoColaborador[];
      readonly erroHistorico: string | null;
    };

type ColaboradorDetalhePageProps = {
  /** Operações da porta (injeção de teste); produção usa o caminho padrão. */
  readonly deps?: DependenciasAcessoColaboradores;
  /** Semente de estado (SSR/teste determinístico). */
  readonly estadoInicial?: EstadoDetalheColaborador;
  /** Semente da fotografia soberana (SSR/teste determinístico). */
  readonly estruturaInicial?: EstadoEstrutura;
  /**
   * Lista SOBERANA de observações (SSR/teste determinístico, L4). Produção lê a
   * porta por escopo de gestão; a semente nunca substitui a leitura feita.
   */
  readonly observacoesIniciais?: readonly ObservacaoSoberana[];
  /**
   * F5-11 P5 (Issue #250) — ciclos SOBERANOS da organização (SSR/teste
   * determinístico). Produção lê a porta única de ciclos
   * (`obterRepositorioCiclosSoberanos`, F5-09 P5): a CRIAÇÃO de observação exige
   * um `cycleId` soberano (`evaluation_cycles.id`) e nunca um ciclo inventado ou
   * lido do acervo local.
   */
  readonly ciclosIniciais?: readonly CicloSoberano[];
};

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

const SEM_ORGANIZACAO_ATIVA =
  "Selecione uma organização ativa para consultar o colaborador.";

/**
 * Estado REAL de ausência de estrutura para este colaborador (não é aviso de
 * pendência): sem ocupação vigente, a tela diz "sem alocação".
 */
const AVISO_SEM_ALOCACAO =
  "Sem alocação: não existe ocupação vigente para este colaborador.";

const ROTULO_EVENTO: Readonly<Record<string, string>> = {
  ADMISSAO: "Admissão",
  DADOS_PESSOAIS_ALTERADOS: "Dados de pessoa alterados",
  IDENTIFICADOR_DEFINIDO: "Matrícula definida",
  IDENTIFICADOR_ENCERRADO: "Matrícula encerrada",
  STATUS_ALTERADO: "Status alterado",
  OCUPACAO_INICIADA: "Ocupação iniciada",
  OCUPACAO_ENCERRADA: "Ocupação encerrada",
  REPORTING_LINE_INICIADA: "Linha de gestão iniciada",
  REPORTING_LINE_ENCERRADA: "Linha de gestão encerrada",
  RESPONSABILIDADE_INICIADA: "Responsabilidade temporária iniciada",
  RESPONSABILIDADE_ENCERRADA: "Responsabilidade temporária encerrada",
  SUCESSAO_REGISTRADA: "Sucessão registrada",
};

const ROTULO_CAMPO: Readonly<Record<string, string>> = {
  full_name: "Nome",
  email: "E-mail",
  admission_date: "Admissão",
  status: "Status",
  matricula: "Matrícula",
  business_code: "Matrícula",
  unit_name: "Unidade",
  job_role_name: "Cargo/função",
  seniority_name: "Senioridade",
  reason: "Motivo",
};

function Icon({
  children,
  size = 18,
}: {
  children: ReactNode;
  size?: number;
}) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

function IconEdit() {
  return (
    <Icon>
      <path d="M4 20h4l11-11-4-4L4 16v4Z" />
      <path d="m13.5 6.5 4 4" />
    </Icon>
  );
}

function IconChart() {
  return (
    <Icon>
      <path d="M4 20V11M10 20V6M16 20v-4M22 20H2" />
    </Icon>
  );
}

function IconStar() {
  return (
    <Icon>
      <path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3l-5.6 2.9 1.1-6.2L3 9.6l6.2-.9L12 3Z" />
    </Icon>
  );
}

function IconTrend() {
  return (
    <Icon>
      <path d="m4 17 6-6 4 4 6-8" />
      <path d="M15 7h5v5" />
    </Icon>
  );
}

function IconCheck() {
  return (
    <Icon>
      <circle cx="12" cy="12" r="9" />
      <path d="m8 12 2.7 2.7L16.5 9" />
    </Icon>
  );
}

function IconCalendar() {
  return (
    <Icon>
      <rect x="3" y="5" width="18" height="16" rx="2" />
      <path d="M8 3v4M16 3v4M3 10h18" />
    </Icon>
  );
}

function iniciaisDe(nome: string): string {
  return nome
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((parte) => parte[0])
    .join("")
    .toUpperCase();
}

function rotuloStatus(status: string): string {
  if (status === "active") return "Ativo";
  if (status === "leave") return "Em licença";
  if (status === "inactive") return "Desligado";
  return status || "—";
}

function classeStatus(status: string): string {
  if (status === "active") return "is-active";
  if (status === "leave") return "is-leave";
  return "is-inactive";
}

function possuiAlocacao(colaborador: ColaboradorSoberano): boolean {
  return Boolean(
    colaborador.unitName ??
      colaborador.jobRoleName ??
      colaborador.seniorityName ??
      colaborador.managerFullName
  );
}

function formatarData(valor?: string | null): string | undefined {
  if (!valor) return undefined;
  const normalizada = valor.length === 10 ? `${valor}T12:00:00` : valor;
  const data = new Date(normalizada);
  return Number.isNaN(data.getTime()) ? undefined : data.toLocaleDateString("pt-BR");
}

function formatarDataHora(valor?: string | null): string | undefined {
  if (!valor) return undefined;
  const data = new Date(valor);
  return Number.isNaN(data.getTime())
    ? undefined
    : data.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function rotuloEvento(eventType: string): string {
  return ROTULO_EVENTO[eventType] ?? eventType;
}

function rotuloEscopo(cycleScope: string): string {
  return cycleScope === "SOMENTE_CICLOS_POSTERIORES"
    ? "Somente ciclos posteriores"
    : "Ciclo atual e posteriores";
}

function valorLegivel(valor: unknown): string {
  if (valor === null || valor === undefined || valor === "") return "—";
  if (typeof valor === "boolean") return valor ? "sim" : "não";
  if (typeof valor === "object") return JSON.stringify(valor);
  return String(valor);
}

/**
 * Mudanças descritas a partir do `before_value`/`after_value` do evento soberano.
 * Nenhum valor é inventado: só o que a trilha registrou.
 */
function mudancasDoEvento(evento: EventoColaborador): string[] {
  const antes = (evento.beforeValue ?? {}) as Record<string, unknown>;
  const depois = (evento.afterValue ?? {}) as Record<string, unknown>;
  const chaves = Array.from(
    new Set([...Object.keys(antes), ...Object.keys(depois)])
  ).sort();

  return chaves.flatMap((chave) => {
    const anterior = antes[chave];
    const atual = depois[chave];
    if (JSON.stringify(anterior) === JSON.stringify(atual)) return [];
    const rotulo = ROTULO_CAMPO[chave] ?? chave;
    if (anterior === undefined) return [`${rotulo}: ${valorLegivel(atual)}`];
    if (atual === undefined) return [`${rotulo}: ${valorLegivel(anterior)}`];
    return [
      `${rotulo}: ${valorLegivel(anterior)} → ${valorLegivel(atual)}`,
    ];
  });
}

function statusLegado(status: string): StatusColaborador {
  if (status === "leave") return "LICENCA";
  if (status === "inactive") return "DESLIGADO";
  return "ATIVO";
}

/**
 * Projeção da projeção soberana para o vocabulário legado usado APENAS pelos
 * componentes de acervo ainda não migrados (avaliações/observações locais). Nada
 * de `funcao`, cargo ou hierarquia é fabricado; o que não existe fica vazio.
 */
function paraColaboradorLegado(
  colaborador: ColaboradorSoberano
): Colaborador | null {
  const matricula = Number(colaborador.matricula);
  if (!Number.isInteger(matricula) || matricula <= 0) return null;

  return {
    matricula,
    nome: colaborador.fullName,
    email: colaborador.email,
    cargo: colaborador.jobRoleName ?? "",
    area: colaborador.unitName ?? "",
    status: statusLegado(colaborador.status),
    respondePara: "",
    ...(colaborador.admissionDate
      ? { dataAdmissao: colaborador.admissionDate }
      : {}),
  };
}

function calcularPercentual(parte: number, total: number): number {
  if (total === 0) return 0;
  return Math.round((parte / total) * 100);
}

function calcularPreenchimentoFeedback(feedback: Feedback) {
  const subcriterios =
    feedback.criteriosDetalhados?.flatMap((criterio) => criterio.subcriterios) ??
    [];
  const totalSubcriterios = subcriterios.length;
  const gerente = subcriterios.filter((item) => item.notaGerente > 0).length;
  const coordenador = subcriterios.filter(
    (item) => item.notaCoordenador > 0
  ).length;
  const colegiado = subcriterios.filter((item) => item.notaColegiado > 0).length;

  return {
    geral: calcularPercentual(
      gerente + coordenador + colegiado,
      totalSubcriterios * 3
    ),
    gerente: calcularPercentual(gerente, totalSubcriterios),
    coordenador: calcularPercentual(coordenador, totalSubcriterios),
    colegiado: calcularPercentual(colegiado, totalSubcriterios),
  };
}

function ColaboradorDetalhePage({
  deps,
  estadoInicial,
  estruturaInicial,
  observacoesIniciais,
  ciclosIniciais,
}: ColaboradorDetalhePageProps = {}) {
  const { collaboratorId } = useParams();
  const navigate = useNavigate();
  const { organizacaoAtivaId, convidarUsuario } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [carregamento, setCarregamento] = useState<{
    readonly chave: string;
    readonly estado: EstadoDetalheColaborador;
  } | null>(null);
  const [versao, setVersao] = useState(0);
  const [estadoConvite, setEstadoConvite] = useState<
    | { readonly fase: "inativo" }
    | { readonly fase: "processando" }
    | { readonly fase: "enviado" }
    | { readonly fase: "erro"; readonly mensagem: string }
  >({ fase: "inativo" });

  /**
   * Fotografia soberana (posições/ocupações/reporting lines/colegiado) — usada
   * SOMENTE para exibir a alocação vigente, o gestor derivado da reporting line
   * e o colegiado vigente. Esta tela não administra estrutura.
   */
  const estrutura = useEstruturaSoberana({
    organizacaoAtivaId,
    deps: depsInjetadas,
    ...(estruturaInicial ? { estadoInicial: estruturaInicial } : {}),
  });

  const identificador = (collaboratorId ?? "").trim();

  /** Chave da leitura corrente: organização + identificador + versão de recarga. */
  const chaveCarregamento = `${organizacaoAtivaId ?? "sem-organizacao"}|${identificador}|${versao}`;

  useLayoutEffect(() => {
    window.scrollTo(0, 0);
  }, [identificador]);

  useLayoutEffect(() => {
    if (estadoInicial || !organizacaoAtivaId || !identificador) return;

    let vigente = true;

    const entradaLeitura = ehUuid(identificador)
      ? { collaboratorId: identificador }
      : { matricula: identificador };

    void (async () => {
      const resultado = await obterColaborador(
        { ...entradaLeitura, organizationId: organizacaoAtivaId },
        depsInjetadas
      );
      if (!vigente) return;

      if (!resultado.ok) {
        setCarregamento({
          chave: chaveCarregamento,
          estado: {
            fase: "erro",
            codigo: resultado.codigo,
            mensagem: resultado.mensagem,
          },
        });
        return;
      }

      const colaborador = resultado.dados;
      const historico = await obterHistoricoColaborador(
        {
          collaboratorId: colaborador.collaboratorId,
          organizationId: organizacaoAtivaId,
        },
        depsInjetadas
      );
      if (!vigente) return;

      setCarregamento({
        chave: chaveCarregamento,
        estado: {
          fase: "pronto",
          colaborador,
          historico: historico.ok ? historico.dados : [],
          erroHistorico: historico.ok ? null : historico.mensagem,
        },
      });
    })();

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
  const estado: EstadoDetalheColaborador =
    !organizacaoAtivaId && !estadoInicial
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

  async function enviarConvite() {
    if (
      estado.fase !== "pronto" ||
      !organizacaoAtivaId ||
      !estado.colaborador.email.trim() ||
      estadoConvite.fase === "processando"
    ) {
      return;
    }

    setEstadoConvite({ fase: "processando" });
    try {
      await convidarUsuario(
        estado.colaborador.email.trim(),
        organizacaoAtivaId,
        estado.colaborador.collaboratorId
      );
      setEstadoConvite({ fase: "enviado" });
    } catch (erro) {
      setEstadoConvite({
        fase: "erro",
        mensagem:
          erro instanceof Error
            ? erro.message
            : "Não foi possível enviar o convite.",
      });
    }
  }

  /**
   * F5-11 P5 (Issue #250), L4 — leitura SOBERANA das observações do ALVO pela
   * porta (escopo de GESTÃO, revalidado server-side). O estado exibido é
   * DERIVADO da chave do contexto (mesmo padrão das outras telas): resposta de
   * um alvo/organização anterior nunca publica. Erro ⇒ `indisponivel` EXPLÍCITO
   * — nunca lista vazia silenciosa, nunca fallback local (D9/D13/D22).
   */
  const alvoObservacoesId =
    estado.fase === "pronto" ? estado.colaborador.collaboratorId : null;
  /** Versão de RECARGA: o painel avisa após mutação soberana e a leitura relê. */
  const [versaoObservacoes, setVersaoObservacoes] = useState(0);
  const chaveObservacoes = `${organizacaoAtivaId ?? "sem-organizacao"}|${
    alvoObservacoesId ?? "sem-alvo"
  }|${versaoObservacoes}`;
  const [leituraObservacoes, setLeituraObservacoes] = useState<{
    readonly chave: string;
    readonly estado: EstadoObservacoesSoberanas;
  }>(() => ({
    chave: chaveObservacoes,
    // Semente de SSR/teste: nunca substitui uma leitura real (o efeito relê).
    estado:
      observacoesIniciais && observacoesIniciais.length > 0
        ? { fase: "pronta", observacoes: observacoesIniciais }
        : { fase: "carregando" },
  }));

  useEffect(() => {
    // Rechecagem explícita: é ela que ESTREITA os tipos dentro do fluxo (o
    // estreitamento do corpo do componente não atravessa a assíncrona).
    if (
      observacoesIniciais ||
      !organizacaoAtivaId ||
      !alvoObservacoesId ||
      !chaveObservacoes
    ) {
      return;
    }

    const organizacaoId = organizacaoAtivaId;
    let vigente = true;
    const chave = chaveObservacoes;

    function publicar(estado: EstadoObservacoesSoberanas): void {
      if (vigente) setLeituraObservacoes({ chave, estado });
    }

    void (async () => {
      const repositorio = obterRepositorioObservacoesSoberanas();
      if (!repositorio) {
        publicar({
          fase: "indisponivel",
          mensagem:
            "As observações não estão disponíveis pelo caminho soberano neste ambiente.",
        });
        return;
      }

      try {
        // Escopo de GESTÃO: o servidor revalida relação/escopo/capability e
        // devolve SOMENTE as observações autorizadas para os alvos do ator.
        const resultado = await repositorio.listarObservacoesPorEscopo(
          organizacaoId,
          "DESCENDANTS"
        );
        if (!vigente) return;

        if (!resultado.ok) {
          publicar({
            fase: "indisponivel",
            mensagem:
              "Não foi possível carregar as observações do colaborador no caminho soberano.",
          });
          return;
        }

        publicar({ fase: "pronta", observacoes: resultado.data.itens });
      } catch {
        publicar({
          fase: "indisponivel",
          mensagem:
            "Não foi possível carregar as observações do colaborador no caminho soberano.",
        });
      }
    })();

    return () => {
      vigente = false;
    };
  }, [
    chaveObservacoes,
    alvoObservacoesId,
    organizacaoAtivaId,
    observacoesIniciais,
  ]);

  /** Estado exibido das observações: só vale a leitura da chave corrente. */
  const estadoObservacoes: EstadoObservacoesSoberanas =
    leituraObservacoes.chave === chaveObservacoes
      ? leituraObservacoes.estado
      : { fase: "carregando" };

  function recarregar() {
    setVersao((valor) => valor + 1);
  }

  if (estado.fase === "carregando") {
    return (
      <main className="virtus-page collaborator-detail-v3">
        <section className="virtus-empty" role="status" aria-live="polite">
          <h2>Carregando colaborador…</h2>
          <p>Consultando o cadastro e a trilha de eventos no servidor.</p>
        </section>
      </main>
    );
  }

  if (estado.fase === "erro") {
    return (
      <main className="virtus-page collaborator-detail-v3">
        <section className="virtus-empty" role="alert">
          <h2>
            {estado.codigo === "FORBIDDEN"
              ? "Acesso restrito"
              : estado.codigo === "NOT_FOUND"
                ? "Colaborador não encontrado"
                : "Não foi possível carregar o colaborador"}
          </h2>
          <p>{estado.mensagem}</p>
          <p>
            Nenhum cadastro local é exibido como substituto e a matrícula da URL
            é resolvida somente no servidor.
          </p>
          <div className="virtus-page-actions">
            <button
              type="button"
              className="virtus-btn virtus-btn--outline"
              onClick={recarregar}
            >
              Tentar novamente
            </button>
            <button
              type="button"
              className="virtus-btn virtus-btn--outline"
              onClick={() => navigate("/")}
            >
              Voltar
            </button>
          </div>
        </section>
      </main>
    );
  }

  const { colaborador, historico, erroHistorico } = estado;

  return (
    <main className="virtus-page collaborator-detail-v3">
      <button
        type="button"
        className="collaborator-detail-back"
        onClick={() => navigate("/")}
      >
        ← Voltar para colaboradores
      </button>

      <section className="collaborator-profile-card collaborator-profile-card--identity">
        <div className="collaborator-identity collaborator-identity--profile">
          <div className="collaborator-identity__avatar" aria-hidden="true">
            {iniciaisDe(colaborador.fullName)}
          </div>

          <div className="collaborator-identity__body">
            <div className="collaborator-identity__title">
              <strong>{colaborador.fullName}</strong>
              <span
                className={`collaborator-identity__status ${classeStatus(
                  colaborador.status
                )}`}
              >
                {rotuloStatus(colaborador.status)}
              </span>
            </div>

            <div className="collaborator-identity__role">
              {colaborador.jobRoleName ?? "Sem alocação"}
              {colaborador.seniorityName ? ` • ${colaborador.seniorityName}` : ""}
            </div>

            <div className="collaborator-identity__details">
              <span className="collaborator-identity__detail">
                <span>{colaborador.email}</span>
              </span>
              <span className="collaborator-identity__detail">
                <span>
                  {colaborador.matricula
                    ? `Matrícula ${colaborador.matricula}`
                    : "Sem matrícula vigente"}
                </span>
              </span>
              <span className="collaborator-identity__detail">
                <span>Identificador {colaborador.collaboratorId}</span>
              </span>
            </div>
          </div>
        </div>

        <div className="virtus-page-actions collaborator-profile-actions">
          <Link
            to={`/colaborador/${colaborador.collaboratorId}/editar`}
            className="virtus-btn virtus-btn--outline collaborator-link-button"
          >
            <IconEdit />
            Editar cadastro
          </Link>
          {colaborador.email.trim() && estadoConvite.fase === "inativo" && (
            <button
              type="button"
              className="virtus-btn virtus-btn--outline collaborator-link-button"
              onClick={() => void enviarConvite()}
            >
              Enviar convite
            </button>
          )}
          {estadoConvite.fase === "processando" && (
            <span role="status">Enviando convite…</span>
          )}
          {estadoConvite.fase === "enviado" && (
            <span role="status">Convite enviado para {colaborador.email}.</span>
          )}
          {estadoConvite.fase === "erro" && (
            <>
              <span role="alert">{estadoConvite.mensagem}</span>
              <button
                type="button"
                className="virtus-btn virtus-btn--outline collaborator-link-button"
                onClick={() => void enviarConvite()}
              >
                Tentar enviar novamente
              </button>
            </>
          )}
        </div>
      </section>

      <section className="collaborator-kpis">
        <article className="collaborator-kpi">
          <span className="collaborator-kpi__icon">
            <IconCheck />
          </span>
          <div>
            <small>Status</small>
            <strong>{rotuloStatus(colaborador.status)}</strong>
            <span>Vigente no servidor</span>
          </div>
        </article>

        <article className="collaborator-kpi">
          <span className="collaborator-kpi__icon">
            <IconCalendar />
          </span>
          <div>
            <small>Admissão</small>
            <strong>{formatarData(colaborador.admissionDate) ?? "—"}</strong>
            <span>Data registrada</span>
          </div>
        </article>

        <article className="collaborator-kpi">
          <span className="collaborator-kpi__icon">
            <IconChart />
          </span>
          <div>
            <small>Versão</small>
            <strong>{colaborador.version}</strong>
            <span>Controle otimista</span>
          </div>
        </article>
      </section>

      <section className="collaborator-section">
        <div className="collaborator-section-heading">
          <div>
            <h2>Alocação vigente</h2>
            <p className="collaborator-section-subtitle">
              Derivada da ocupação soberana na data de referência. O gestor direto
              vem da reporting line vigente da posição; o colegiado, da
              configuração vigente do avaliado.
            </p>
          </div>
          <div className="collaborator-section-actions">
            <button
              type="button"
              className="virtus-btn virtus-btn--outline"
              onClick={() => navigate(`/colaborador/${colaborador.collaboratorId}/editar`)}
            >
              Administrar alocação
            </button>
          </div>
        </div>

        {possuiAlocacao(colaborador) ? (
          <div className="collaborator-identity__details">
            <span className="collaborator-identity__detail">
              <span>Unidade: {colaborador.unitName ?? "—"}</span>
            </span>
            <span className="collaborator-identity__detail">
              <span>Cargo/função: {colaborador.jobRoleName ?? "—"}</span>
            </span>
            <span className="collaborator-identity__detail">
              <span>Senioridade: {colaborador.seniorityName ?? "—"}</span>
            </span>
            <span className="collaborator-identity__detail">
              <span>Gestor: {colaborador.managerFullName ?? "—"}</span>
            </span>
          </div>
        ) : (
          <div className="collaborator-history-empty">{AVISO_SEM_ALOCACAO}</div>
        )}

        {estrutura.estado.fase === "pronto" &&
          (() => {
            const fotografia = estrutura.estado.estrutura;
            const ocupacao = ocupacaoVigenteDoColaborador(
              fotografia,
              colaborador.collaboratorId
            );
            const gestor = ocupacao
              ? gestorDiretoDaPosicao(fotografia, ocupacao.posicaoId)
              : null;
            const reporting = ocupacao
              ? reportingVigenteDaPosicao(fotografia, ocupacao.posicaoId)
              : null;
            const colegiado = colegiadoVigente(fotografia, colaborador.collaboratorId);

            return (
              <div className="collaborator-identity__details" data-testid="alocacao-soberana">
                {ocupacao ? (
                  <>
                    <span className="collaborator-identity__detail">
                      <span>
                        Posição vigente: {rotuloDaPosicao(fotografia, ocupacao.posicaoId)}
                      </span>
                    </span>
                    <span className="collaborator-identity__detail">
                      <span>
                        Vigência da ocupação:{" "}
                        {rotuloVigencia(ocupacao.validFrom, ocupacao.validTo)}
                      </span>
                    </span>
                    <span className="collaborator-identity__detail">
                      <span>
                        Gestor direto (reporting line):{" "}
                        {gestor
                          ? gestor.collaboratorId
                            ? nomeDoColaborador(fotografia, gestor.collaboratorId)
                            : `${rotuloDaPosicao(fotografia, gestor.managerPositionId)} (sem ocupante)`
                          : reporting
                            ? "posição sem ocupante"
                            : "sem gestor formal (posição raiz)"}
                      </span>
                    </span>
                  </>
                ) : (
                  <span className="collaborator-identity__detail">
                    <span>
                      Nenhuma ocupação vigente na leitura soberana de estrutura.
                    </span>
                  </span>
                )}
                <span className="collaborator-identity__detail">
                  <span>
                    Colegiado vigente:{" "}
                    {colegiado
                      ? colegiado.membroIds.length > 0
                        ? colegiado.membroIds
                            .map((membroId) => nomeDoColaborador(fotografia, membroId))
                            .join(", ")
                        : "sem colegiado (zero membros)"
                      : "não configurado"}
                  </span>
                </span>
              </div>
            );
          })()}

        {estrutura.estado.fase === "erro" && (
          <div className="collaborator-history-empty" role="alert">
            Não foi possível carregar a estrutura soberana: {estrutura.estado.mensagem} (
            {estrutura.estado.codigo})
          </div>
        )}
      </section>

      <section className="collaborator-section collaborator-org-history-section">
        <div className="collaborator-section-heading">
          <div>
            <h2>Histórico organizacional</h2>
            <p className="collaborator-section-subtitle">
              Trilha soberana append-only: cada evento traz vigência, motivo e
              autoria registrados na mesma transação da mudança.
            </p>
          </div>
        </div>

        {erroHistorico && (
          <div className="collaborator-history-empty" role="alert">
            Não foi possível carregar o histórico soberano: {erroHistorico}
          </div>
        )}

        {historico.length === 0 && !erroHistorico ? (
          <div className="collaborator-history-empty">
            Nenhuma movimentação organizacional registrada ainda.
          </div>
        ) : (
          <div className="collaborator-org-timeline">
            {historico.map((evento) => {
              const mudancas = mudancasDoEvento(evento);
              return (
                <article className="collaborator-org-event" key={evento.eventId}>
                  <div className="collaborator-org-event__rail" aria-hidden="true">
                    <span />
                  </div>
                  <div className="collaborator-org-event__content">
                    <header>
                      <div>
                        <strong>{rotuloEvento(evento.eventType)}</strong>
                        <span>{formatarDataCivil(evento.effectiveDate)}</span>
                      </div>
                      <span className="collaborator-org-event__scope">
                        {rotuloEscopo(evento.cycleScope)}
                      </span>
                    </header>

                    {mudancas.length > 0 && (
                      <div className="collaborator-org-event__changes">
                        {mudancas.map((mudanca) => (
                          <span key={mudanca}>{mudanca}</span>
                        ))}
                      </div>
                    )}

                    <footer>
                      <span>Motivo: {evento.reason}</span>
                      {evento.actorFullName && (
                        <span>Registrado por: {evento.actorFullName}</span>
                      )}
                      {formatarDataHora(evento.createdAt) && (
                        <span>Em {formatarDataHora(evento.createdAt)}</span>
                      )}
                    </footer>
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>

      <AcervoLegado
        colaborador={colaborador}
        estadoObservacoes={estadoObservacoes}
        alvoObservacoesId={alvoObservacoesId}
        organizacaoId={organizacaoAtivaId}
        {...(ciclosIniciais ? { ciclosIniciais } : {})}
        onObservacoesChange={() => setVersaoObservacoes((v) => v + 1)}
        nomesDeColaborador={Object.fromEntries(
          estrutura.estado.fase === "pronto"
            ? estrutura.estado.estrutura.colaboradores.map((item) => [
                item.collaboratorId,
                item.nome,
              ])
            : []
        )}
      />
    </main>
  );
}

/**
 * Acervo LEGADO de AVALIAÇÕES (ainda no armazenamento local do navegador,
 * migração em F5-06/F5-09/F5-10). Fica explicitamente rotulado como legado e NÃO
 * é usado para identidade, estrutura nem autorização. As OBSERVAÇÕES do alvo já
 * foram cortadas para a porta soberana (F5-11 P5, L4) e chegam por parâmetro —
 * este componente não lê observação em acervo local.
 */
function AcervoLegado({
  colaborador,
  estadoObservacoes,
  alvoObservacoesId,
  organizacaoId,
  onObservacoesChange,
  nomesDeColaborador,
  ciclosIniciais,
}: {
  colaborador: ColaboradorSoberano;
  estadoObservacoes: EstadoObservacoesSoberanas;
  alvoObservacoesId: string | null;
  organizacaoId: string | null;
  onObservacoesChange: () => void;
  nomesDeColaborador: MapaDeNomesDeColaborador;
  /** Semente soberana de ciclos (SSR/teste); produção lê a porta de ciclos. */
  ciclosIniciais?: readonly CicloSoberano[];
}) {
  const { usuarioAtualLegado } = useUsuarioAtual();
  // F5-11 P5 — intenção de UX da PÁGINA (filtro de ciclo e visibilidade das
  // excluídas); o painel recebe os setters reais, nunca handler inerte.
  const [filtroObservacoes, setFiltroObservacoes] =
    useState<FiltroCicloObservacoesSoberano>(FILTRO_OBSERVACOES_TODOS);
  const [mostrarExcluidas, setMostrarExcluidas] = useState(false);
  // O controlador nasce UMA vez do MESMO singleton usado na leitura soberana;
  // sem repositório (ambiente sem Supabase) o painel não é montado (fail-closed).
  const [controladorObservacoes] = useState(() => {
    const repositorio = obterRepositorioObservacoesSoberanas();
    return repositorio ? criarControladorObservacoes({ repositorio }) : null;
  });
  /**
   * F5-11 P5 (Issue #250) — CICLOS SOBERANOS do painel. A criação gerencial exige
   * um `cycleId` SOBERANO (`evaluation_cycles.id`); a lista vem da porta única de
   * ciclos (`obterRepositorioCiclosSoberanos`) e NUNCA do acervo legado de ciclos.
   * Ausência de caminho soberano ou erro do
   * backend ⇒ lista VAZIA (fail-closed): o painel fica sem ciclo e a criação é
   * recusada localmente (D2) — nenhum ciclo sintético é inventado.
   *
   * O estado guarda a CHAVE da organização e a exibição é DERIVADA: ciclos de
   * outro tenant nunca aparecem e não há `setState` síncrono no efeito (mesmo
   * padrão da leitura de observações desta tela).
   */
  const chaveCiclos = organizacaoId ?? "sem-organizacao";
  const [leituraCiclos, setLeituraCiclos] = useState<{
    readonly chave: string;
    readonly ciclos: readonly CicloSoberano[];
  }>(() => ({
    chave: chaveCiclos,
    // Semente de SSR/teste: nunca substitui uma leitura real (o efeito relê).
    ciclos: ciclosIniciais ?? [],
  }));

  useEffect(() => {
    if (ciclosIniciais || !organizacaoId) return;
    const organizacao = organizacaoId;
    let vigente = true;

    function publicar(ciclos: readonly CicloSoberano[]): void {
      if (vigente) setLeituraCiclos({ chave: organizacao, ciclos });
    }

    void (async () => {
      const porta = obterRepositorioCiclosSoberanos();
      if (!porta) {
        // Sem caminho soberano ⇒ fail-closed (nunca ciclo local como resposta).
        publicar([]);
        return;
      }
      const resultado = await porta.listarCiclos(organizacao);
      if (!vigente) return;
      // Erro de backend é INDISPONIBILIDADE: lista vazia, nunca ciclo inventado.
      publicar(resultado.ok ? resultado.data : []);
    })();

    return () => {
      vigente = false;
    };
  }, [ciclosIniciais, organizacaoId]);

  const ciclosSoberanos: readonly CicloSoberano[] =
    leituraCiclos.chave === chaveCiclos ? leituraCiclos.ciclos : [];
  /**
   * Rótulos por UUID a partir dos NOMES já carregados pela página. A matrícula
   * não existe nessa superfície: o rótulo vai SEM matrícula (apresentação), e
   * `null` continua significando indisponível — nada de sentinela.
   */
  const rotulosObservacoes: FonteDeRotulosDeColaborador = {
    doColaborador: (id) => {
      const nome = nomesDeColaborador[id];
      return nome ? { nome } : null;
    },
    doAutor: (id) => {
      const nome = nomesDeColaborador[id];
      return nome ? { nome } : null;
    },
  };
  const [mostrarCanceladas, setMostrarCanceladas] = useState(false);
  const [ordenacao, setOrdenacao] = useState<"RECENTES" | "ANTIGAS">("RECENTES");

  const colaboradorLegado = paraColaboradorLegado(colaborador);

  if (!colaboradorLegado) {
    return (
      <section className="collaborator-section">
        <div className="collaborator-section-heading">
          <div>
            <h2>Acervo legado local</h2>
          </div>
        </div>
        <div className="collaborator-history-empty">
          Este colaborador não possui matrícula numérica vigente; o acervo legado
          local (avaliações e observações) é indexado por matrícula e não pôde ser
          exibido. O histórico soberano acima permanece íntegro.
        </div>
      </section>
    );
  }

  const ciclos = getCiclosAvaliacao();
  const escala = getEscalaAvaliacao();
  const todosLegado: Colaborador[] = [colaboradorLegado];

  const feedbacksBase = getFeedbacksAdministrativosByColaborador(
    colaboradorLegado.matricula,
    mostrarCanceladas
  );
  const feedbacksOrdenados = ordenarHistoricoAdministrativo(
    feedbacksBase,
    ordenacao
  );
  const feedbacksConcluidos = feedbacksBase.filter(
    (feedback) => feedback.status === "CONCLUIDA"
  );
  const notasValidas = feedbacksConcluidos
    .map((feedback) => feedback.notaMedia)
    .filter((nota) => nota > 0);
  const ultimaAvaliacao = [...feedbacksBase].sort(
    (a, b) =>
      new Date(b.dataCriacao ?? b.data).getTime() -
      new Date(a.dataCriacao ?? a.data).getTime()
  )[0];
  const ultimaNota = ultimaAvaliacao?.notaMedia ?? 0;
  const melhorNota = notasValidas.length > 0 ? Math.max(...notasValidas) : 0;

  /**
   * Observações do ALVO na projeção SOBERANA (L4). O recorte é por UUID; nada é
   * lido do acervo local e nada é derivado de matrícula/ano/ciclo.
   */
  const observacoesSoberanas = observacoesDoAlvo(
    estadoObservacoes.fase === "pronta" ? estadoObservacoes.observacoes : [],
    colaborador.collaboratorId,
    nomesDeColaborador
  );
  const resumoObservacoes = resumoDeObservacoesPorTipo(observacoesSoberanas);
  const observacoesProntas = estadoObservacoes.fase === "pronta";
  const contagemObservacoes = (quantidade: number): string =>
    observacoesProntas ? String(quantidade) : "—";
  /** Sufixo de contagem do subtítulo; vazio enquanto a leitura não conclui. */
  const resumoDaContagemObservacoes = observacoesProntas
    ? ` (${observacoesSoberanas.length} ${
        observacoesSoberanas.length === 1 ? "registro" : "registros"
      })`
    : "";

  function estiloNota(valor: number) {
    if (!possuiNotaAvaliacao(valor)) {
      return {
        "--score-color": "#655d69",
        "--score-bg": "#f4f1f5",
        "--score-border": "#d8d2dc",
      } as CSSProperties;
    }
    const faixa = getItemEscalaPorNota(valor, escala);
    return {
      "--score-color": faixa.cor,
      "--score-bg": faixa.corFundo,
      "--score-border": `${faixa.cor}44`,
    } as CSSProperties;
  }

  return (
    <>
      <section className="collaborator-section">
        <div className="collaborator-section-heading">
          <div>
            <h2>Acervo legado local (avaliações)</h2>
            <p className="collaborator-section-subtitle">
              Avaliações ainda persistidas no armazenamento local do navegador.
              São exibidas apenas como legado — a identidade, o status e o
              histórico oficiais vêm do PostgreSQL (trilha acima).
            </p>
          </div>

          <div className="collaborator-history-controls">
            <Link
              className="virtus-btn virtus-btn--outline collaborator-link-button collaborator-link-button--compact"
              to={`/colaborador/${colaboradorLegado.matricula}/novo-feedback`}
            >
              Nova avaliação (rota legada)
            </Link>
            <label className="collaborator-show-cancelled">
              <input
                type="checkbox"
                checked={mostrarCanceladas}
                onChange={(event) => setMostrarCanceladas(event.target.checked)}
              />
              Mostrar canceladas
            </label>
            <label className="collaborator-sort">
              <span>Ordenar por:</span>
              <select
                value={ordenacao}
                onChange={(event) =>
                  setOrdenacao(event.target.value as "RECENTES" | "ANTIGAS")
                }
              >
                <option value="RECENTES">Mais recentes</option>
                <option value="ANTIGAS">Mais antigas</option>
              </select>
            </label>
          </div>
        </div>

        <div className="collaborator-kpis">
          <article className="collaborator-kpi">
            <span className="collaborator-kpi__icon">
              <IconChart />
            </span>
            <div>
              <small>Avaliações (legado)</small>
              <strong>{feedbacksBase.length}</strong>
              <span>Total local</span>
            </div>
          </article>

          <article
            className="collaborator-kpi score-semantic"
            style={estiloNota(ultimaNota)}
          >
            <span className="collaborator-kpi__icon">
              <IconStar />
            </span>
            <div>
              <small>Última nota (legado)</small>
              <strong className="is-score">
                {formatarNotaAvaliacao(ultimaNota)}
              </strong>
              <span className="collaborator-kpi__score-label">
                {getTextoNotaAvaliacao(ultimaNota, escala)}
              </span>
            </div>
          </article>

          <article
            className="collaborator-kpi score-semantic"
            style={estiloNota(melhorNota)}
          >
            <span className="collaborator-kpi__icon">
              <IconTrend />
            </span>
            <div>
              <small>Melhor nota (legado)</small>
              <strong className="is-score">
                {formatarNotaAvaliacao(melhorNota)}
              </strong>
              <span className="collaborator-kpi__score-label">
                {getTextoNotaAvaliacao(melhorNota, escala)}
              </span>
            </div>
          </article>
        </div>

        {feedbacksOrdenados.length === 0 ? (
          <div className="collaborator-history-empty">
            Nenhuma avaliação legada registrada para este colaborador.
          </div>
        ) : (
          <div className="collaborator-history">
            {feedbacksOrdenados.map((feedback) => {
              const cicloDaAvaliacao = ciclos.find(
                (ciclo) =>
                  ciclo.ano === feedback.ano && ciclo.ciclo === feedback.ciclo
              );
              const statusExibido = getStatusAvaliacaoAdministrativa(
                feedback.status,
                cicloDaAvaliacao?.status
              );
              const acaoConsulta = usuarioAtualLegado
                ? getAcaoConsultaHistoricoAdministrativo(
                    usuarioAtualLegado,
                    colaboradorLegado,
                    todosLegado,
                    cicloDaAvaliacao,
                    feedback
                  )
                : undefined;
              const preenchimento = calcularPreenchimentoFeedback(feedback);
              const dataInicio = formatarData(feedback.dataCriacao ?? feedback.data);
              const dataFim = formatarData(feedback.dataConclusao);

              return (
                <article
                  className="collaborator-evaluation-card score-semantic is-closed"
                  style={estiloNota(feedback.notaMedia)}
                  key={feedback.id}
                >
                  <header className="collaborator-evaluation-card__header">
                    <span className="collaborator-evaluation-card__toggle">
                      <span className="collaborator-evaluation-card__calendar">
                        <IconCalendar />
                      </span>
                      <span className="collaborator-evaluation-card__cycle-copy">
                        <span className="collaborator-evaluation-card__title">
                          <strong>
                            {feedback.ano} • Ciclo {feedback.ciclo}
                          </strong>
                          <span
                            className={`collaborator-evaluation-status ${statusExibido.className}`}
                          >
                            {statusExibido.label}
                          </span>
                        </span>
                        <small>
                          {dataInicio ? `Início: ${dataInicio}` : ""}
                          {dataFim ? ` • Conclusão: ${dataFim}` : ""}
                        </small>
                      </span>
                    </span>

                    <div className="collaborator-evaluation-card__actions">
                      {acaoConsulta && (
                        <Link
                          className="virtus-btn virtus-btn--outline collaborator-link-button collaborator-link-button--compact"
                          to={acaoConsulta.destino}
                        >
                          {acaoConsulta.label} →
                        </Link>
                      )}
                    </div>
                  </header>

                  <div className="collaborator-evaluation-summary">
                    <div className="collaborator-evaluation-score">
                      <small>
                        {feedback.status === "CONCLUIDA"
                          ? "Nota final"
                          : "Nota atual / final"}
                      </small>
                      <strong>{formatarNotaAvaliacao(feedback.notaMedia)}</strong>
                      <span>{getTextoNotaAvaliacao(feedback.notaMedia, escala)}</span>
                    </div>

                    <div className="collaborator-evaluation-progress">
                      <small>Progresso geral</small>
                      <strong>{preenchimento.geral}%</strong>
                      <span>Preenchimento total</span>
                    </div>
                  </div>

                  {feedback.criteriosDetalhados &&
                    feedback.criteriosDetalhados.length > 0 && (
                      <div className="collaborator-competencies">
                        <small>Competências avaliadas (legado)</small>
                        <div className="collaborator-competencies__grid">
                          {feedback.criteriosDetalhados.map((criterio) => (
                            <div
                              className={`collaborator-competency ${
                                possuiNotaAvaliacao(criterio.nota)
                                  ? "score-semantic has-score"
                                  : ""
                              }`}
                              key={criterio.criterioNome}
                              style={
                                possuiNotaAvaliacao(criterio.nota)
                                  ? estiloNota(criterio.nota)
                                  : undefined
                              }
                            >
                              <span className="collaborator-competency__name">
                                {criterio.criterioNome}
                              </span>
                              <strong>
                                {formatarNotaAvaliacao(criterio.nota)}
                              </strong>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                  <footer className="collaborator-evaluation-card__footer">
                    <small>
                      Registro legado local — não é a fonte soberana de avaliação.
                    </small>
                  </footer>
                </article>
              );
            })}
          </div>
        )}
      </section>

      <section className="collaborator-section">
        <div className="collaborator-section-heading">
          <div>
            <h2>Observações</h2>
            <p className="collaborator-section-subtitle">
              Observações soberanas do colaborador autorizadas ao seu escopo de
              gestão{resumoDaContagemObservacoes}. Nada é lido do armazenamento
              local.
            </p>
          </div>
        </div>

        <div className="collaborator-observation-summary">
          <button
            type="button"
            className="collaborator-observation-kpi is-positive"
          >
            <span className="collaborator-observation-kpi__copy">
              <small>Positivas</small>
              <strong>{contagemObservacoes(resumoObservacoes.positivas)}</strong>
              <em>Ver todas →</em>
            </span>
          </button>

          <button
            type="button"
            className="collaborator-observation-kpi is-neutral"
          >
            <span className="collaborator-observation-kpi__copy">
              <small>Neutras</small>
              <strong>{contagemObservacoes(resumoObservacoes.neutras)}</strong>
              <em>Ver todas →</em>
            </span>
          </button>

          <button
            type="button"
            className="collaborator-observation-kpi is-negative"
          >
            <span className="collaborator-observation-kpi__copy">
              <small>Negativas</small>
              <strong>{contagemObservacoes(resumoObservacoes.negativas)}</strong>
              <em>Ver todas →</em>
            </span>
          </button>
        </div>

        {estadoObservacoes.fase === "carregando" && (
          <div className="collaborator-history-empty" role="status">
            Carregando as observações do colaborador pelo caminho soberano…
          </div>
        )}

        {estadoObservacoes.fase === "indisponivel" && (
          <div className="collaborator-history-empty" role="alert">
            Observações indisponíveis: {estadoObservacoes.mensagem}
          </div>
        )}

        {observacoesProntas && observacoesSoberanas.length === 0 && (
          <div className="collaborator-history-empty">
            Nenhuma observação autorizada para este colaborador.
          </div>
        )}

        {/* F5-11 P5 (Issue #250) — superfície ÚNICA do fluxo gerencial: o PAINEL
            soberano (lista + timeline + mutações com código público). A página
            entrega a projeção JÁ carregada como semente (um único fetch) e os
            rótulos por UUID; nenhuma lista inline duplicada é renderizada. */}
        {observacoesProntas &&
          controladorObservacoes &&
          alvoObservacoesId &&
          organizacaoId && (
            <ObservacoesColaborador
              colaborador={{
                id: alvoObservacoesId,
                nome: colaborador.fullName,
                matricula: Number(colaborador.matricula),
              }}
              organizationId={organizacaoId}
              escopo="DESCENDANTS"
              ciclos={ciclosSoberanos}
              controlador={controladorObservacoes}
              rotulos={rotulosObservacoes}
              filtroCiclo={filtroObservacoes}
              onFiltroCicloChange={setFiltroObservacoes}
              mostrarExcluidas={mostrarExcluidas}
              onMostrarExcluidasChange={setMostrarExcluidas}
              onObservacoesChange={onObservacoesChange}
              estadoInicial={{
                fase: "pronta",
                escopo: "DESCENDANTS",
                itens: estadoObservacoes.observacoes,
              }}
            />
          )}
      </section>
    </>
  );
}

export default ColaboradorDetalhePage;
