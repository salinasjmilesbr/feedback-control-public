import { useCallback, useEffect, useRef, useState } from "react";
import type { CicloSoberano } from "../application/ports/CycleRepository";
import type { ObservacaoSoberana } from "../application/ports/ObservationRepository";
import type { TipoObservacao } from "../types/Observacao";
import {
  contarObservacoesSoberanasPorTipo,
  FILTRO_OBSERVACOES_TODOS,
  filtrarObservacoesSoberanasPorCiclo,
  ordenarCiclosSoberanosParaFiltro,
  type FiltroCicloObservacoesSoberano,
} from "./filtroObservacoesPorCiclo";
import {
  eventoTimelineDeUi,
  observacaoDeUi,
  type EventoTimelineUi,
  type FonteDeRotulosDeColaborador,
  type ObservacaoDeUi,
  type RotulosTimelineObservacao,
} from "../services/observacoesSoberanas/mapeadorObservacaoUi";
import type { ControladorObservacoes } from "../services/observacoesSoberanas/controladorObservacoes";
import {
  criarObservacaoSoberana,
  editarObservacaoSoberana,
  excluirObservacaoSoberana,
  mensagemDaFalha,
} from "../services/observacoesSoberanas/fluxoMutacaoObservacao";
import type {
  CodigoPublico,
  EscopoObservacao,
} from "../infrastructure/supabase/observacoes/contrato";
import "../styles/observacoes.css";

/**
 * F5-11 P5 (Issue #250), L3 — CUTOVER do painel de observações do gestor.
 *
 * ## O que mudou de dono
 *
 * - a fonte é a PORTA/CONTROLADOR soberanos, recebidos por PROPS: este
 *   componente **não** cria repositório, **não** fala com Supabase, **não** lê
 *   `observacaoStorage`/`localStorage` e **não** tem fallback nem dual-read
 *   (D13). Toda leitura/mutação atravessa a Edge `observacoes` → RPC
 *   `observacao_*`;
 * - a AUTORIZAÇÃO saiu do componente: o antigo gate local decidia com alvo e
 *   contexto FABRICADOS no browser e foi REMOVIDO no cutover; a decisão é sempre
 *   server-side e o componente não chama o Policy Engine.
 *   Os controles são renderizados como INTENÇÃO de UX e a decisão é sempre
 *   server-side: mutação negada exibe o CÓDIGO PÚBLICO e a mensagem do
 *   controlador (fail-closed) sem alterar a lista exibida;
 * - o HISTÓRICO/timeline deixou de ser um array local: vem de
 *   `observacao.historico` (trilha append-only, D6) e é apresentado por
 *   `EventoTimelineUi` — tipo NOVO, sem `ano`/`ciclo`, sem matrícula derivada de
 *   UUID e sem "ação" textual inventada.
 *
 * ## Identidade (UUID) e rótulos (parâmetro)
 *
 * O `colaborador` prop é a INTENÇÃO de alvo (`id` = `collaborators.id`); nome e
 * matrícula são rótulos de apresentação. `rotulos` resolve o alvo e o autor das
 * LINHAS e `rotulosTimeline` resolve o ator dos EVENTOS; sem o rótulo do alvo, o
 * item não é apresentado pelo mapeador (`null`) e a contagem de itens não
 * apresentáveis é informada — nada é inventado.
 *
 * O desenho visual (layout, classes, ordem dos blocos, KPIs/tags) é PRESERVADO:
 * o cutover troca a FONTE e o dono da decisão, não o desenho.
 */

export interface ObservacoesColaboradorProps {
  /**
   * Colaborador-ALVO do painel. A identidade é `id` (`collaborators.id`, UUID) e
   * é o ÚNICO campo consumido pelo painel (alvo da criação e filtro da leitura);
   * `nome`/`matricula` entram para deixar explícito que a página pode passar a
   * projeção SOBERANA (`ColaboradorSoberano`) — a apresentação das LINHAS vem de
   * `rotulos`, por UUID, e nunca daqui (nada de identidade por matrícula — D1/D3).
   */
  readonly colaborador: {
    readonly id: string;
    readonly nome: string;
    readonly matricula: number;
  };
  /** Organização ativa — INTENÇÃO de UX (a Edge/RPC revalida o tenant). */
  readonly organizationId: string;
  /** Escopo de leitura da listagem (`DIRECT_REPORTS` | `DESCENDANTS`). */
  readonly escopo: EscopoObservacao;
  /** Ciclos soberanos da organização (rótulos `ano`/`numero` da projeção). */
  readonly ciclos: readonly CicloSoberano[];
  /** Porta/controlador soberanos injetados pela página (nunca criados aqui). */
  readonly controlador: ControladorObservacoes;
  /** Rótulos de alvo/autor das LINHAS por UUID (superfície de colaboradores). */
  readonly rotulos: FonteDeRotulosDeColaborador;
  /** Rótulos do ATOR dos eventos da timeline (por perfil ou mapa já enriquecido). */
  readonly rotulosTimeline?: RotulosTimelineObservacao;
  /** Filtro corrente do painel (estado do consumidor). */
  readonly filtroCiclo: FiltroCicloObservacoesSoberano;
  readonly onFiltroCicloChange: (filtro: FiltroCicloObservacoesSoberano) => void;
  readonly mostrarExcluidas: boolean;
  readonly onMostrarExcluidasChange: (mostrar: boolean) => void;
  /** Aviso ao consumidor de que houve mutação soberana bem-sucedida. */
  readonly onObservacoesChange: () => void;
  /** Token que abre o formulário de nova observação (mesma UX anterior). */
  readonly abrirNovaObservacaoToken?: number;
  /**
   * Semente da LEITURA (SSR/teste determinístico): quando presente, o efeito de
   * leitura soberana NÃO dispara e o estado exibido é esta semente — mesmo padrão
   * de `useEstruturaSoberana`/`estadoInicial` do repositório. Nada é decidido
   * aqui: a semente é um recorte já devolvido pela porta.
   */
  readonly estadoInicial?: EstadoLista;
  /** Semente da TRILHA (SSR/teste determinístico): desliga a leitura de histórico. */
  readonly timelineInicial?: EstadoTimeline | null;
  /** Semente da timeline ABERTA (SSR/teste determinístico). */
  readonly historicoAbertoInicial?: string | null;
}

const labelsTipo: Record<TipoObservacao, string> = {
  POSITIVA: "Positiva",
  NEUTRA: "Neutra",
  NEGATIVA: "Negativa",
};

const estiloTipo: Record<
  TipoObservacao,
  { backgroundColor: string; color: string }
> = {
  POSITIVA: {
    backgroundColor: "#E7F6EC",
    color: "#107C41",
  },
  NEUTRA: {
    backgroundColor: "#F2F2F2",
    color: "#555",
  },
  NEGATIVA: {
    backgroundColor: "#FDE7E9",
    color: "#A4262C",
  },
};

/**
 * Rótulo do evento da timeline a partir do `event_type` FECHADO do contrato
 * (`CRIADA`/`EDITADA`/`COMUNICADO`/`COMUNICACAO_REMOVIDA`/`EXCLUIDA`/`REVOGADA`).
 */
const labelsEvento: Readonly<Record<EventoTimelineUi["evento"], string>> = {
  CRIADA: "Criação",
  EDITADA: "Edição",
  COMUNICADO: "Comunicado ao colaborador",
  COMUNICACAO_REMOVIDA: "Comunicação removida",
  EXCLUIDA: "Exclusão",
  REVOGADA: "Revogação da exclusão",
};

function formatarData(data: string) {
  return new Date(data).toLocaleString("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  });
}

/** Falha soberana exibida: código público + mensagem do controlador (fail-closed). */
interface ErroSoberano {
  readonly origem: "lista" | "mutacao" | "historico";
  readonly codigo: CodigoPublico;
  readonly mensagem: string;
}

type EstadoLista =
  | { readonly fase: "carregando" }
  | { readonly fase: "pronta"; readonly escopo: string; readonly itens: readonly ObservacaoSoberana[] }
  | { readonly fase: "erro"; readonly erro: ErroSoberano };

type EstadoTimeline =
  | { readonly fase: "carregando"; readonly observationId: string }
  | { readonly fase: "pronta"; readonly observationId: string; readonly itens: readonly EventoTimelineUi[] }
  | { readonly fase: "erro"; readonly observationId: string; readonly erro: ErroSoberano };

function ObservacoesColaborador({
  colaborador,
  organizationId,
  escopo,
  ciclos,
  controlador,
  rotulos,
  rotulosTimeline,
  filtroCiclo,
  onFiltroCicloChange,
  mostrarExcluidas,
  onMostrarExcluidasChange,
  onObservacoesChange,
  abrirNovaObservacaoToken,
  estadoInicial,
  timelineInicial,
  historicoAbertoInicial,
}: ObservacoesColaboradorProps) {
  const [versao, setVersao] = useState(0);
  const [formAberto, setFormAberto] = useState(false);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [tipo, setTipo] = useState<TipoObservacao>("NEUTRA");
  const [texto, setTexto] = useState("");
  const [comunicado, setComunicado] = useState(false);
  /** Ciclo da CRIAÇÃO: UUID soberano (`evaluation_cycles.id`), nunca `ano`/`ciclo`. */
  const [cicloSelecionado, setCicloSelecionado] = useState<string | null>(null);
  const [historicoAberto, setHistoricoAberto] = useState<string | null>(
    historicoAbertoInicial ?? null
  );
  const [erro, setErro] = useState("");
  const [listaEstado, setLista] = useState<EstadoLista & { readonly chave?: string }>(
    estadoInicial ?? { fase: "carregando" }
  );
  const [timelineEstado, setTimeline] = useState<
    (EstadoTimeline & { readonly chave?: string }) | null
  >(timelineInicial ?? null);

  /**
   * Chave de ENTRADA de cada leitura soberana. O estado guarda a chave da
   * fotografia RECEBIDA; a exibição é DERIVADA dela: quando a chave guardada não
   * é a vigente, exibimos `carregando` enquanto o efeito relê. Assim não existe
   * `setState` síncrono dentro de efeito (render em cascata) nem `setState`
   * durante o render — a entrada é a fonte da verdade.
   */
  const chaveDaLeitura = `${organizationId}\u0000${escopo}\u0000${versao}`;
  const chaveDaTimeline = historicoAberto ?? "";

  const lista: EstadoLista =
    estadoInicial !== undefined || listaEstado.chave === chaveDaLeitura
      ? listaEstado
      : { fase: "carregando" };

  const timeline: EstadoTimeline | null =
    timelineInicial !== undefined
      ? timelineEstado
      : chaveDaTimeline === ""
        ? null
        : timelineEstado !== null && timelineEstado.chave === chaveDaTimeline
          ? timelineEstado
          : { fase: "carregando", observationId: chaveDaTimeline };

  const ciclosDoFiltro = ordenarCiclosSoberanosParaFiltro(ciclos);
  const ciclosAtivos = ciclosDoFiltro.filter((item) => item.status === "ATIVO");
  const cicloAtivo = ciclosAtivos[0] ?? null;
  const cicloDaCriacao =
    ciclos.find((item) => item.id === cicloSelecionado) ?? cicloAtivo;

  // A LEITURA é sempre soberana: nenhuma chamada local, nenhum cache e nenhuma
  // completude otimista. `operationId` e escopo ficam no controlador/porta.
  // Com SEMENTE (`estadoInicial`) o efeito não dispara: o SSR/teste determinístico
  // exibe exatamente a fotografia recebida, como em `useEstruturaSoberana`.
  useEffect(() => {
    if (estadoInicial) return;

    let vigente = true;
    void controlador
      .listarPorEscopo(organizationId, escopo)
      .then((resultado) => {
        if (!vigente) return;
        setLista(
          resultado.ok
            ? {
                fase: "pronta",
                escopo: resultado.data.escopo,
                itens: resultado.data.itens,
                chave: chaveDaLeitura,
              }
            : {
                fase: "erro",
                erro: {
                  origem: "lista",
                  codigo: resultado.error.code,
                  mensagem: resultado.error.mensagem,
                },
                chave: chaveDaLeitura,
              }
        );
      });
    return () => {
      vigente = false;
    };
  }, [controlador, organizationId, escopo, versao, estadoInicial, chaveDaLeitura]);

  const recarregar = useCallback(() => setVersao((valor) => valor + 1), []);

  function limparFormulario() {
    setEditandoId(null);
    setTipo("NEUTRA");
    setTexto("");
    setComunicado(false);
    setCicloSelecionado(null);
    setErro("");
    setFormAberto(false);
  }

  useEffect(() => {
    if (!abrirNovaObservacaoToken) return;

    const timeoutId = window.setTimeout(() => {
      setEditandoId(null);
      setTipo("NEUTRA");
      setTexto("");
      setComunicado(false);
      setCicloSelecionado(null);
      setErro("");
      setFormAberto(true);
    }, 0);

    return () => window.clearTimeout(timeoutId);
  }, [abrirNovaObservacaoToken]);

  function iniciarEdicao(observacao: ObservacaoDeUi) {
    setEditandoId(observacao.id);
    setTipo(observacao.tipo);
    setTexto(observacao.texto);
    setComunicado(observacao.comunicado);
    setErro("");
    setFormAberto(true);
  }

  async function salvar() {
    if (!texto.trim()) {
      setErro("Digite o texto da observação.");
      return;
    }

    setErro("");

    // A intenção é delegada ao fluxo soberano (`fluxoMutacaoObservacao`): a versão
    // esperada vem da LEITURA soberana no controlador e NENHUMA autoridade é
    // transportada daqui.
    const contexto = {
      controlador,
      organizationId,
      collaboratorId: colaborador.id,
      ...(cicloDaCriacao ? { cycleId: cicloDaCriacao.id } : {}),
    };

    const resultado = editandoId
      ? await editarObservacaoSoberana(
          contexto,
          { id: editandoId },
          { tipo, texto, comunicado }
        )
      : await criarObservacaoSoberana(contexto, { tipo, texto });

    if (!resultado.ok) {
      // Negação/erro do servidor: a LISTA EXIBIDA permanece intacta.
      setErro(mensagemDaFalha(resultado.error));
      return;
    }

    limparFormulario();
    setVersao((valor) => valor + 1);
    onObservacoesChange();
  }

  async function excluir(observacao: ObservacaoDeUi) {
    const confirmar = window.confirm(
      "Deseja realmente excluir esta observação? Ela permanecerá no histórico."
    );
    if (!confirmar) return;

    // D8/D16: a exclusão soberana é LÓGICA e exige MOTIVO — sem motivo não há
    // intenção válida e nada é enviado.
    const motivo = window.prompt("Motivo da exclusão (obrigatório):") ?? "";

    setErro("");
    const resultado = await excluirObservacaoSoberana(
      { controlador, organizationId, collaboratorId: colaborador.id },
      { id: observacao.id },
      motivo
    );

    if (!resultado.ok) {
      setErro(mensagemDaFalha(resultado.error));
      return;
    }

    setVersao((valor) => valor + 1);
    onObservacoesChange();
  }

  function alternarHistorico(observationId: string) {
    setHistoricoAberto((atual) => (atual === observationId ? null : observationId));
  }

  // Os rótulos da timeline NÃO entram nas dependências do efeito: um objeto
  // recriado pelo consumidor a cada render dispararia releitura infinita. O ref
  // mantém o valor corrente sem tornar a identidade do objeto uma dependência.
  const rotulosTimelineRef = useRef(rotulosTimeline);
  // O ref é atualizado em EFEITO (nunca durante o render, que é proibido porque
  // o render precisa ser puro). O valor corrente continua disponível para a
  // leitura da trilha sem que a identidade do objeto vire dependência do efeito.
  useEffect(() => {
    rotulosTimelineRef.current = rotulosTimeline;
  }, [rotulosTimeline]);

  // A timeline é lida da TRILHA soberana quando (e só quando) é exibida. Com
  // semente de trilha (`timelineInicial`) o efeito NÃO dispara (SSR/teste).
  useEffect(() => {
    if (timelineInicial !== undefined) return;
    if (!historicoAberto) return;

    let vigente = true;
    void controlador.historico(organizationId, historicoAberto).then((resultado) => {
      if (!vigente) return;
      setTimeline(
        resultado.ok
          ? {
              fase: "pronta",
              observationId: historicoAberto,
              chave: chaveDaTimeline,
              itens: resultado.data.eventos
                .map((evento) => eventoTimelineDeUi(evento, rotulosTimelineRef.current))
                .filter((item): item is EventoTimelineUi => item !== null),
            }
          : {
              fase: "erro",
              observationId: historicoAberto,
              chave: chaveDaTimeline,
              erro: {
                origem: "historico",
                codigo: resultado.error.code,
                mensagem: resultado.error.mensagem,
              },
            }
      );
    });
    return () => {
      vigente = false;
    };
  }, [controlador, organizationId, historicoAberto, timelineInicial, chaveDaTimeline]);

  const itensSoberanos =
    lista.fase === "pronta"
      ? filtrarObservacoesSoberanasPorCiclo(
          mostrarExcluidas
            ? lista.itens
            : lista.itens.filter((observacao) => !observacao.excluida),
          filtroCiclo
        )
      : [];

  // O mapeador é a fronteira de apresentação: item sem rótulo do ALVO não é
  // exibido (`null`) e a contagem é informada — nunca se inventa identidade.
  const observacoes: ObservacaoDeUi[] = [];
  const timelinePorObservacao = new Map<string, readonly EventoTimelineUi[]>();
  if (timeline?.fase === "pronta") {
    timelinePorObservacao.set(timeline.observationId, timeline.itens);
  }
  let naoApresentaveis = 0;
  for (const soberana of itensSoberanos) {
    const mapeada = observacaoDeUi(
      soberana,
      rotulos,
      timelinePorObservacao.get(soberana.id) ?? []
    );
    if (mapeada) observacoes.push(mapeada);
    else naoApresentaveis += 1;
  }

  const cicloDaObservacaoEmEdicao = editandoId
    ? ciclos.find(
        (item) =>
          item.id === itensSoberanos.find((o) => o.id === editandoId)?.cycleId
      ) ?? null
    : null;

  const erroLista = lista.fase === "erro" ? lista.erro : null;
  const erroForaDoFormulario =
    erroLista ?? (timeline?.fase === "erro" ? timeline.erro : null) ?? null;

  /** KPI por tipo das observações soberanas do recorte (sem `ano`/`ciclo`). */
  const resumo = contarObservacoesSoberanasPorTipo(itensSoberanos);

  /** `cycleId` por observação: a única ponte para o RÓTULO do ciclo na tela. */
  const cycleIdPorObservacao = new Map(
    itensSoberanos.map((item) => [item.id, item.cycleId] as const)
  );

  /**
   * Rótulo do botão da trilha. O `total` de eventos NÃO está na projeção da
   * listagem (só a RPC de histórico o devolve), então o contador aparece quando a
   * trilha já foi lida — nunca é estimado nem preenchido com número inventado.
   */
  function rotuloHistorico(observationId: string): string {
    if (historicoAberto === observationId) return "Ocultar histórico";
    return timeline?.observationId === observationId && timeline.fase === "pronta"
      ? `Ver histórico (${timeline.itens.length})`
      : "Ver histórico";
  }

  return (
    <div className="observation-panel">
      <div className="observation-panel__header">
        <div>
          <h3 className="observation-panel__title">Observações</h3>
          <p className="observation-panel__description">
            Registros positivos, neutros ou negativos do colaborador.
          </p>
        </div>

        <div className="observation-panel__actions">
          <label className="observation-cycle-filter">
            <span>Ciclo:</span>
            <select
              value={filtroCiclo === "TODOS" ? "TODOS" : filtroCiclo.cycleId}
              onChange={(event) => {
                limparFormulario();
                onFiltroCicloChange(
                  event.target.value === "TODOS"
                    ? FILTRO_OBSERVACOES_TODOS
                    : { cycleId: event.target.value }
                );
              }}
            >
              {ciclosDoFiltro.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.ano} · Ciclo {item.numero}
                  {item.status === "ATIVO" ? " (Atual)" : ""}
                </option>
              ))}
              <option value="TODOS">Todos os ciclos</option>
            </select>
          </label>

          <label className="observation-toggle">
              <input
                type="checkbox"
                checked={mostrarExcluidas}
                onChange={(event) =>
                  onMostrarExcluidasChange(event.target.checked)
                }
              />
              Mostrar excluídas
          </label>

          <button
            type="button"
            onClick={() => {
              if (formAberto && !editandoId) {
                limparFormulario();
              } else {
                setEditandoId(null);
                setTipo("NEUTRA");
                setTexto("");
                setComunicado(false);
                setCicloSelecionado(null);
                setErro("");
                setFormAberto(true);
              }
            }}
            className="virtus-btn virtus-btn--primary"
          >
            + Nova observação
          </button>
        </div>
      </div>

      {erroForaDoFormulario && (
        <div className="observation-form__error" style={{ marginTop: "12px" }}>
          {erroForaDoFormulario.origem === "lista"
            ? "Não foi possível carregar as observações. "
            : erroForaDoFormulario.origem === "historico"
              ? "Não foi possível carregar o histórico. "
              : ""}
          <strong>{erroForaDoFormulario.codigo}</strong>
          {" — "}
          {erroForaDoFormulario.mensagem}
          {erroForaDoFormulario.origem === "lista" && (
            <button
              type="button"
              onClick={recarregar}
              className="virtus-btn virtus-btn--outline"
              style={{ marginLeft: "10px" }}
            >
              Tentar novamente
            </button>
          )}
        </div>
      )}

      {formAberto && (
        <div className="observation-form">
          <div className="observation-form__grid">
            <label>
              <strong>Tipo</strong>
              <select
                value={tipo}
                onChange={(event) =>
                  setTipo(event.target.value as TipoObservacao)
                }
                className="observation-control"
              >
                <option value="POSITIVA">Positiva</option>
                <option value="NEUTRA">Neutra</option>
                <option value="NEGATIVA">Negativa</option>
              </select>
            </label>

            <label>
              <strong>Ciclo da observação</strong>
              <select
                value={cicloDaCriacao?.id ?? ""}
                disabled={Boolean(editandoId)}
                onChange={(event) => {
                  setCicloSelecionado(event.target.value);
                }}
                className="observation-control"
              >
                {(editandoId
                  ? ciclosDoFiltro.filter(
                      (item) => item.id === cicloDaObservacaoEmEdicao?.id
                    )
                  : ciclosAtivos
                ).map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.ano} • Ciclo {item.numero}
                    {item.status === "ATIVO" ? " (Ativo)" : ""}
                  </option>
                ))}
              </select>
            </label>

            <label>
              <strong>Observação</strong>
              <textarea
                value={texto}
                onChange={(event) => setTexto(event.target.value)}
                className="observation-control observation-control--textarea"
              />
            </label>

            <label className="observation-checkbox">
              <input
                type="checkbox"
                checked={comunicado}
                onChange={(event) =>
                  setComunicado(event.target.checked)
                }
              />
              <strong>Comunicado ao colaborador</strong>
            </label>

            {erro && (
              <div className="observation-form__error">{erro}</div>
            )}

            <div className="observation-form__actions">
              <button
                type="button"
                onClick={limparFormulario}
                className="virtus-btn virtus-btn--outline"
              >
                Cancelar
              </button>

              <button
                type="button"
                onClick={() => {
                  void salvar();
                }}
                className="virtus-btn virtus-btn--primary"
              >
                {editandoId ? "Salvar alterações" : "Salvar observação"}
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="observation-list">
        <div
          className="collaborator-observation-summary"
          style={{ display: "flex", gap: "8px", flexWrap: "wrap", fontSize: "12px", color: "#555" }}
        >
          <span>Positivas: {resumo.POSITIVA}</span>
          <span>Neutras: {resumo.NEUTRA}</span>
          <span>Negativas: {resumo.NEGATIVA}</span>
        </div>

        {lista.fase === "carregando" ? (
          <div className="observation-empty">Carregando observações…</div>
        ) : lista.fase === "erro" ? (
          <div className="observation-empty">
            Observações indisponíveis: {lista.erro.codigo} — {lista.erro.mensagem}
          </div>
        ) : observacoes.length === 0 ? (
          <div className="observation-empty">Nenhuma observação registrada.</div>
        ) : (
          observacoes.map((observacao) => (
            <div
              key={observacao.id}
              className={`observation-card ${
                observacao.tipo === "POSITIVA"
                  ? "is-positive"
                  : observacao.tipo === "NEGATIVA"
                  ? "is-negative"
                  : "is-neutral"
              } ${observacao.excluida ? "is-deleted" : ""}`}
            >
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  gap: "12px",
                  flexWrap: "wrap",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    gap: "8px",
                    flexWrap: "wrap",
                    alignItems: "center",
                  }}
                >
                  <span
                    style={{
                      ...estiloTipo[observacao.tipo],
                      padding: "4px 9px",
                      borderRadius: "999px",
                      fontSize: "12px",
                      fontWeight: "bold",
                    }}
                  >
                    <span aria-hidden="true">
                      {observacao.tipo === "POSITIVA"
                        ? "✓ "
                        : observacao.tipo === "NEGATIVA"
                        ? "! "
                        : "• "}
                    </span>
                    {labelsTipo[observacao.tipo]}
                  </span>

                  <span
                    style={{
                      padding: "4px 9px",
                      borderRadius: "999px",
                      fontSize: "12px",
                      fontWeight: "bold",
                      backgroundColor: "#E8F4FF",
                      color: "#0078D4",
                    }}
                  >
                    {rotuloCicloDaObservacao(
                      cycleIdPorObservacao.get(observacao.id),
                      ciclos
                    )}
                  </span>

                  <span
                    style={{
                      padding: "4px 9px",
                      borderRadius: "999px",
                      fontSize: "12px",
                      fontWeight: "bold",
                      backgroundColor: observacao.comunicado
                        ? "#E7F6EC"
                        : "#FFF4CE",
                      color: observacao.comunicado
                        ? "#107C41"
                        : "#8A6D00",
                    }}
                  >
                    {observacao.comunicado
                      ? "Comunicado"
                      : "Não comunicado"}
                  </span>

                  {observacao.excluida && (
                    <span
                      style={{
                        padding: "4px 9px",
                        borderRadius: "999px",
                        fontSize: "12px",
                        fontWeight: "bold",
                        backgroundColor: "#FDE7E9",
                        color: "#A4262C",
                      }}
                    >
                      Excluída
                    </span>
                  )}
                </div>

                {!observacao.excluida && (
                  <div
                    style={{
                      display: "flex",
                      gap: "8px",
                    }}
                  >
                    <button
                      type="button"
                      onClick={() => iniciarEdicao(observacao)}
                      style={{
                        border: "none",
                        backgroundColor: "transparent",
                        color: "#660099",
                        cursor: "pointer",
                        fontWeight: "bold",
                      }}
                    >
                      Editar
                    </button>

                    <button
                      type="button"
                      onClick={() => {
                        void excluir(observacao);
                      }}
                      style={{
                        border: "none",
                        backgroundColor: "transparent",
                        color: "#A4262C",
                        cursor: "pointer",
                        fontWeight: "bold",
                      }}
                    >
                      Excluir
                    </button>
                  </div>
                )}
              </div>

<div className="observation-card__text">
                {observacao.texto}
              </div>

<div className="observation-card__meta">
                {observacao.autorNome !== null && (
                  <>
                    Registrada por <strong>{observacao.autorNome}</strong>{" "}
                  </>
                )}
                em {formatarData(observacao.dataCriacao)}
                {observacao.dataUltimaAtualizacao !==
                  observacao.dataCriacao && (
                  <>
                    {" "}
                    • Atualizada em{" "}
                    {formatarData(
                      observacao.dataUltimaAtualizacao
                    )}
                  </>
                )}
              </div>

              <button
                type="button"
                onClick={() => alternarHistorico(observacao.id)}
                className="observation-history-toggle"
              >
                {rotuloHistorico(observacao.id)}
              </button>

              {historicoAberto === observacao.id && (
<div className="observation-history">
                  {timeline === null || timeline.fase === "carregando" ? (
                    <div style={{ fontSize: "12px", color: "#555" }}>
                      Carregando histórico…
                    </div>
                  ) : timeline.fase === "erro" ? (
                    <div style={{ fontSize: "12px", color: "#a4262c" }}>
                      Histórico indisponível: {timeline.erro.codigo} —{" "}
                      {timeline.erro.mensagem}
                    </div>
                  ) : timeline.itens.length === 0 ? (
                    <div style={{ fontSize: "12px", color: "#555" }}>
                      Nenhum evento registrado na trilha.
                    </div>
                  ) : (
                    [...timeline.itens]
                      .reverse()
                      .map((evento) => (
                        <div
                          key={evento.eventId}
                          style={{
                            fontSize: "12px",
                            color: "#555",
                          }}
                        >
                          <strong>{labelsEvento[evento.evento]}</strong>
                          {" • "}
                          {formatarData(evento.dataEfetiva)}
                          {evento.actorNome !== null && (
                            <>
                              {" • "}
                              {evento.actorNome}
                            </>
                          )}

                          {evento.motivo && (
                            <div style={{ marginTop: "4px" }}>
                              Motivo: {evento.motivo}
                            </div>
                          )}

                          {evento.textoAnterior && (
                            <div
                              style={{
                                marginTop: "4px",
                                padding: "6px 8px",
                                backgroundColor: "#F8F8F8",
                                borderRadius: "6px",
                              }}
                            >
                              Texto anterior: {evento.textoAnterior}
                            </div>
                          )}
                        </div>
                      ))
                  )}
                </div>
              )}
            </div>
          ))
        )}

        {naoApresentaveis > 0 && (
          <div className="observation-empty">
            {naoApresentaveis} observação(ões) do servidor sem rótulo de
            colaborador na tela e por isso não exibida(s).
          </div>
        )}
      </div>
    </div>
  );
}

/**
 * Rótulo do ciclo da observação a partir do `cycleId` SOBERANO — usa o `ano` e o
 * `numero` da projeção de `CicloSoberano` (rótulos, não derivação do UUID).
 * Ciclo fora da projeção recebe "Ciclo não disponível" explícito em vez de um
 * número inventado.
 */
function rotuloCicloDaObservacao(
  cycleId: string | undefined,
  ciclos: readonly CicloSoberano[]
): string {
  const ciclo = ciclos.find((item) => item.id === cycleId);
  return ciclo ? `${ciclo.ano} • Ciclo ${ciclo.numero}` : "Ciclo não disponível";
}

export default ObservacoesColaborador;
