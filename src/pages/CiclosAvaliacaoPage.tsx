import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import { useAuth } from "../auth/AuthContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import {
  excluirCiclo,
  atualizarConfiguracaoMetasCiclo,
  formatarPeriodoCiclo,
} from "../services/cicloAvaliacaoStorage";
/** Bloco 3 remove este resíduo junto com a exclusão física da UI. */
import { excluirAvaliacoesVaziasDoCiclo } from "../services/cicloEquipeService";
import { confirmarExclusaoCiclo } from "./confirmarExclusaoCiclo";
import {
  criarControladorGestaoCiclos,
  type ControladorGestaoCiclos,
} from "../services/ciclosSoberanos/controladorGestaoCiclos";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import "../styles/ciclos.css";

type CiclosAvaliacaoPageProps = {
  mostrarCanceladosInicial?: boolean;
  /** Injeção do controlador soberano (testes). Em produção é criado pela página. */
  controlador?: ControladorGestaoCiclos;
};

type EventoHistoricoCiclo =
  | {
      tipo: "encerramento";
      data: string;
      encerradoComPendencias: boolean;
      quantidadePendencias: number;
    }
  | {
      tipo: "reabertura";
      data: string;
      motivo: string;
      autorNome: string;
      autorMatricula: number;
    }
  | {
      tipo: "cancelamento";
      data: string;
      motivo: string;
      autorNome: string;
      autorMatricula: number;
    }
  | {
      tipo: "correcao-periodo";
      data: string;
      justificativa: string;
      autorNome: string;
      autorMatricula: number;
      periodoAnterior: { dataInicio?: string; dataFim?: string };
      novoPeriodo: { dataInicio: string; dataFim: string };
      impacto: NonNullable<CicloAvaliacao["correcoesPeriodo"]>[number]["impacto"];
    };

function getEventosHistoricoCiclo(
  ciclo: CicloAvaliacao
): EventoHistoricoCiclo[] {
  const encerramentos =
    ciclo.encerramentos ??
    (ciclo.dataEncerramento
      ? [
          {
            data: ciclo.dataEncerramento,
            encerradoComPendencias: Boolean(ciclo.encerradoComPendencias),
            quantidadePendencias: ciclo.quantidadePendencias ?? 0,
          },
        ]
      : []);

  return [
    ...encerramentos.map((evento) => ({
      tipo: "encerramento" as const,
      ...evento,
    })),
    ...(ciclo.reaberturas ?? []).map((evento) => ({
      tipo: "reabertura" as const,
      ...evento,
    })),
    ...(ciclo.cancelamento
      ? [{ tipo: "cancelamento" as const, ...ciclo.cancelamento }]
      : []),
    ...(ciclo.correcoesPeriodo ?? []).map((evento) => ({
      tipo: "correcao-periodo" as const,
      ...evento,
    })),
  ].sort((a, b) => {
    const diferencaData = Date.parse(b.data) - Date.parse(a.data);
    if (diferencaData !== 0) return diferencaData;
    return a.tipo.localeCompare(b.tipo);
  });
}

function formatarDataHoraHistorico(data: string): string {
  return new Date(data).toLocaleString("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  });
}

function CiclosAvaliacaoPage({
  mostrarCanceladosInicial = false,
  controlador: controladorInjetado,
}: CiclosAvaliacaoPageProps = {}) {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const { organizacaoAtivaId } = useAuth();
  const [versao, setVersao] = useState(0);
  const [ano, setAno] = useState(new Date().getFullYear());
  const [ciclo, setCiclo] = useState<1 | 2 | 3>(1);
  const [dataInicio, setDataInicio] = useState("");
  const [dataFim, setDataFim] = useState("");
  const [quantidadeMetasNegocio, setQuantidadeMetasNegocio] =
    useState<0 | 1 | 2 | 3>(0);
  const [quantidadeMetasIndividuais, setQuantidadeMetasIndividuais] =
    useState<0 | 1 | 2 | 3>(0);
  const [ativarAgora, setAtivarAgora] = useState(false);
  const [mostrarCancelados, setMostrarCancelados] = useState(
    mostrarCanceladosInicial
  );
  const [editandoPeriodoId, setEditandoPeriodoId] = useState<string | null>(null);
  const [periodoInicioEdicao, setPeriodoInicioEdicao] = useState("");
  const [periodoFimEdicao, setPeriodoFimEdicao] = useState("");
  const [corrigindoPeriodoId, setCorrigindoPeriodoId] = useState<string | null>(null);
  const [periodoInicioCorrecao, setPeriodoInicioCorrecao] = useState("");
  const [periodoFimCorrecao, setPeriodoFimCorrecao] = useState("");
  const [justificativaCorrecao, setJustificativaCorrecao] = useState("");
  const [editandoMetasId, setEditandoMetasId] = useState<string | null>(null);
  const [metasNegocioEdicao, setMetasNegocioEdicao] =
    useState<0 | 1 | 2 | 3>(0);
  const [metasIndividuaisEdicao, setMetasIndividuaisEdicao] =
    useState<0 | 1 | 2 | 3>(0);
  const [erro, setErro] = useState("");

  /**
   * F5-09 P8 (Bloco 1) — LEITURA SOBERANA: o controlador puro é a ÚNICA fonte da
   * lista exibida. Nada de `getCiclosAdministrativos`/`getCiclosAvaliacao`/
   * `localStorage` para listar ciclos; sem fallback local em erro.
   */
  const controlador = useMemo(
    () => controladorInjetado ?? criarControladorGestaoCiclos(),
    [controladorInjetado]
  );
  const [estado, setEstado] = useState(controlador.estado());

  // Carga ao entrar/trocar de organização (o controlador invalida a geração
  // anterior, então resposta antiga não substitui o contexto novo).
  useEffect(() => {
    let ativo = true;
    void (async () => {
      await controlador.carregar(organizacaoAtivaId ?? null, {
        incluirCancelados: mostrarCancelados,
      });
      if (ativo) setEstado(controlador.estado());
    })();
    return () => {
      ativo = false;
    };
  }, [controlador, organizacaoAtivaId, mostrarCancelados]);

  // Unmount/logout descartam respostas em voo.
  useEffect(
    () => () => {
      controlador.descartar();
    },
    [controlador]
  );
  const podeGerenciarCiclos = usuarioAtual
    ? can(
        {
          actor: {
            matricula: usuarioAtual.matricula,
            funcao: usuarioAtual.funcao,
            status: usuarioAtual.status,
          },
        },
        "cycle.management.view",
        { kind: "global" }
      )
    : false;

  void versao;

  if (!usuarioAtual || !podeGerenciarCiclos) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Acesso restrito</h1>
          <p>A gestão dos ciclos está disponível apenas para gerentes.</p>
          <button className="cycle-btn cycle-btn--secondary" onClick={() => navigate("/")}>
            Voltar ao início
          </button>
        </section>
      </main>
    );
  }

  const ciclos = estado.ciclos;

  const totalAtivos = ciclos.filter((item) => item.status === "ATIVO").length;
  const totalPlanejados = ciclos.filter((item) => item.status === "PLANEJADO").length;
  const totalEncerrados = ciclos.filter((item) => item.status === "ENCERRADO").length;

  /**
   * F5-09 P8 (Bloco 2) — MUTATIONS SOBERANAS.
   *
   * Todas as operações de lifecycle passam pelo controlador (→ gestão → Edge P7
   * → RPC soberana). O controlador publica o estado após SUCESSO (com reload
   * soberano) e preserva o último estado válido em FALHA; aqui apenas espelhamos
   * `controlador.estado()` no React e exibimos o erro público. Nenhuma mutação
   * local de ciclo permanece — nem rollback, nem compensação, nem `.rpc(`.
   */
  async function publicar(
    resultado: { readonly ok: boolean; readonly error?: { readonly message: string } },
    falhaPadrao: string
  ): Promise<boolean> {
    setEstado(controlador.estado());
    if (resultado.ok) {
      setErro("");
      return true;
    }
    setErro(resultado.error?.message ?? falhaPadrao);
    return false;
  }

  async function criar() {
    setErro("");
    const ok = await publicar(
      await controlador.criar({
        ano,
        numero: ciclo,
        dataInicio,
        dataFim,
      }),
      "Não foi possível criar o ciclo."
    );
    if (!ok) return;

    setDataInicio("");
    setDataFim("");
    setVersao((valor) => valor + 1);
  }

  async function encerrarComValidacao(item: CicloAvaliacao) {
    setErro("");
    const motivo = window.prompt("Informe o motivo do encerramento do ciclo:");
    if (motivo === null) return;
    if (!motivo.trim()) {
      setErro("Informe o motivo do encerramento do ciclo.");
      return;
    }
    if (
      !window.confirm(
        `Encerrar ${item.ano} • Ciclo ${item.ciclo}? As avaliações incompletas serão marcadas como pendências permanentes pela operação soberana.`
      )
    ) {
      return;
    }

    const ok = await publicar(
      await controlador.encerrar(item.id, motivo.trim()),
      "Não foi possível encerrar o ciclo."
    );
    if (!ok) return;
    setVersao((valor) => valor + 1);
  }

  async function ativarComValidacao(item: CicloAvaliacao) {
    setErro("");
    if (!window.confirm(`Ativar ${item.ano} • Ciclo ${item.ciclo}?`)) return;

    // A ativação materializa colegiado e responsabilidades NA RPC soberana.
    const ok = await publicar(
      await controlador.ativar(item.id),
      "Não foi possível ativar o ciclo."
    );
    if (!ok) return;
    setVersao((valor) => valor + 1);
  }

  async function cancelarComMotivo(item: CicloAvaliacao) {
    setErro("");
    const motivo = window.prompt("Informe o motivo do cancelamento do ciclo:");
    if (motivo === null) return;
    if (!motivo.trim()) {
      setErro("Informe o motivo do cancelamento do ciclo.");
      return;
    }

    // PLANEJADO e ATIVO são aceitos pelo contrato soberano (P4/P6).
    const ok = await publicar(
      await controlador.cancelar(item.id, motivo.trim()),
      "Não foi possível cancelar o ciclo."
    );
    if (!ok) return;
    setVersao((valor) => valor + 1);
  }

  async function reabrirComMotivo(item: CicloAvaliacao) {
    setErro("");
    const motivo = window.prompt("Informe o motivo da reabertura do ciclo:");
    if (motivo === null) return;
    if (!motivo.trim()) {
      setErro("Informe o motivo da reabertura do ciclo.");
      return;
    }
    if (!window.confirm(`Reabrir ${item.ano} • Ciclo ${item.ciclo}?`)) return;

    const ok = await publicar(
      await controlador.reabrir(item.id, motivo.trim()),
      "Não foi possível reabrir o ciclo."
    );
    if (!ok) return;
    setVersao((valor) => valor + 1);
  }

  async function corrigirPeriodoComAuditoria(item: CicloAvaliacao) {
    setErro("");
    if (!justificativaCorrecao.trim()) {
      setErro("Informe a justificativa da correção do período.");
      return;
    }

    // O impacto é calculado server-side pela operação soberana.
    const ok = await publicar(
      await controlador.corrigirPeriodo({
        cicloId: item.id,
        dataInicio: periodoInicioCorrecao,
        dataFim: periodoFimCorrecao,
        justificativa: justificativaCorrecao.trim(),
      }),
      "Não foi possível corrigir o período."
    );
    if (!ok) return;

    setCorrigindoPeriodoId(null);
    setJustificativaCorrecao("");
    setVersao((valor) => valor + 1);
  }

  return (
    <main className="virtus-page cycle-page">
      <section className="cycle-page-header">
        <div>
          <h1>Ciclos de Avaliação</h1>
          <p>
            Configure períodos, metas e acompanhe a evolução de cada ciclo.
          </p>
        </div>

        <div className="cycle-summary">
          <div>
            <strong>{ciclos.length}</strong>
            <span>Total</span>
          </div>
          <div>
            <strong>{totalAtivos}</strong>
            <span>Ativo</span>
          </div>
          <div>
            <strong>{totalPlanejados}</strong>
            <span>Planejados</span>
          </div>
          <div>
            <strong>{totalEncerrados}</strong>
            <span>Encerrados</span>
          </div>
        </div>
      </section>

      <section className="cycle-create-card">
        <div className="cycle-section-heading">
          <div>
            <span className="cycle-eyebrow">Novo ciclo</span>
            <h2>Configuração inicial</h2>
          </div>
          <span className="cycle-helper">Apenas um ciclo pode ficar ativo por vez.</span>
        </div>

        <div className="cycle-form-grid cycle-form-grid--four">
          <label className="cycle-field">
            <span>Ano</span>
            <input
              type="number"
              min={2020}
              max={2100}
              value={ano}
              onChange={(event) => setAno(Number(event.target.value))}
            />
          </label>

          <label className="cycle-field">
            <span>Ciclo</span>
            <select
              value={ciclo}
              onChange={(event) =>
                setCiclo(Number(event.target.value) as 1 | 2 | 3)
              }
            >
              <option value={1}>Ciclo 1</option>
              <option value={2}>Ciclo 2</option>
              <option value={3}>Ciclo 3</option>
            </select>
          </label>

          <label className="cycle-field">
            <span>Início</span>
            <input
              type="date"
              value={dataInicio}
              onChange={(event) => setDataInicio(event.target.value)}
            />
          </label>

          <label className="cycle-field">
            <span>Fim</span>
            <input
              type="date"
              value={dataFim}
              onChange={(event) => setDataFim(event.target.value)}
            />
          </label>
        </div>

        <div className="cycle-form-grid cycle-form-grid--two">
          <label className="cycle-field">
            <span>Metas de Negócio / Projetos</span>
            <select
              value={quantidadeMetasNegocio}
              onChange={(event) =>
                setQuantidadeMetasNegocio(
                  Number(event.target.value) as 0 | 1 | 2 | 3
                )
              }
            >
              <option value={0}>0 metas</option>
              <option value={1}>1 meta</option>
              <option value={2}>2 metas</option>
              <option value={3}>3 metas</option>
            </select>
          </label>

          <label className="cycle-field">
            <span>Metas Individuais</span>
            <select
              value={quantidadeMetasIndividuais}
              onChange={(event) =>
                setQuantidadeMetasIndividuais(
                  Number(event.target.value) as 0 | 1 | 2 | 3
                )
              }
            >
              <option value={0}>0 metas</option>
              <option value={1}>1 meta</option>
              <option value={2}>2 metas</option>
              <option value={3}>3 metas</option>
            </select>
          </label>
        </div>

        <div className="cycle-create-footer">
          <label className="cycle-checkbox">
            <input
              type="checkbox"
              checked={ativarAgora}
              onChange={(event) => setAtivarAgora(event.target.checked)}
            />
            <span>
              <strong>Ativar imediatamente</strong>
              <small>Cria as avaliações automaticamente ao salvar.</small>
            </span>
          </label>

          <button
            className="cycle-btn cycle-btn--primary"
            onClick={() => {
              void criar();
            }}
          >
            + Criar ciclo
          </button>
        </div>

        {erro && <div className="cycle-alert cycle-alert--error">{erro}</div>}
      </section>

      {(estado.fase === "ocioso" || estado.fase === "carregando") && (
        <div className="cycle-alert" role="status">
          Carregando ciclos…
        </div>
      )}

      {estado.fase === "erro" && estado.erro && (
        <div className="cycle-alert cycle-alert--error" role="alert">
          {estado.erro.message}
        </div>
      )}

      <section className="cycle-list">
        <div className="cycle-list-heading">
          <div>
            <span className="cycle-eyebrow">Histórico</span>
            <h2>Ciclos cadastrados</h2>
          </div>
          <label className="cycle-checkbox">
            <input
              type="checkbox"
              checked={mostrarCancelados}
              onChange={(event) => setMostrarCancelados(event.target.checked)}
            />
            <span>Mostrar cancelados</span>
          </label>
        </div>

        {ciclos.length === 0 ? (
          <div className="cycle-empty">
            <h3>Nenhum ciclo cadastrado</h3>
            <p>Crie o primeiro ciclo usando o formulário acima.</p>
          </div>
        ) : (
          ciclos.map((item) => {
            const eventosHistorico = getEventosHistoricoCiclo(item);
            const podeCorrigirPeriodo = can(
              {
                actor: {
                  matricula: usuarioAtual.matricula,
                  funcao: usuarioAtual.funcao,
                  status: usuarioAtual.status,
                },
              },
              "cycle.period.correct.manager",
              { kind: "cycle", cycle: item }
            );
            const statusLabel =
              item.status === "ATIVO"
                ? "Ativo"
                : item.status === "PLANEJADO"
                ? "Planejado"
                : item.status === "CANCELADO"
                ? "Cancelado"
                : item.encerradoComPendencias
                ? "Encerrado com pendências"
                : "Encerrado";

            const statusClass =
              item.status === "ATIVO"
                ? "is-active"
                : item.status === "PLANEJADO"
                ? "is-planned"
                : item.status === "CANCELADO"
                ? "is-cancelled"
                : item.encerradoComPendencias
                ? "is-warning"
                : "is-closed";

            return (
              <article
                key={item.id}
                className={`cycle-card ${item.status === "ATIVO" ? "cycle-card--active" : ""}`}
              >
                <div className="cycle-card__main">
                  <div className="cycle-card__identity">
                    <div className="cycle-card__title-row">
                      <h3>
                        {item.ano} <span>•</span> Ciclo {item.ciclo}
                      </h3>
                      <span className={`cycle-status ${statusClass}`}>
                        {statusLabel}
                      </span>
                    </div>

                    <div className="cycle-card__meta-grid">
                      <div>
                        <small>Período</small>
                        <strong>
                          {formatarPeriodoCiclo(item.dataInicio, item.dataFim)}
                        </strong>
                      </div>
                      <div>
                        <small>Metas de Negócio</small>
                        <strong>{item.quantidadeMetasNegocio ?? 0}</strong>
                      </div>
                      <div>
                        <small>Metas Individuais</small>
                        <strong>{item.quantidadeMetasIndividuais ?? 0}</strong>
                      </div>
                      {item.encerradoComPendencias && (
                        <div>
                          <small>Pendências</small>
                          <strong className="cycle-danger">
                            {item.quantidadePendencias ?? 0}
                          </strong>
                        </div>
                      )}
                      {item.cancelamento && (
                        <div>
                          <small>Cancelamento</small>
                          <strong>{item.cancelamento.motivo}</strong>
                        </div>
                      )}
                    </div>
                  </div>

                  <button
                    className="cycle-btn cycle-btn--primary cycle-btn--panel"
                    onClick={() => navigate(`/ciclos/${item.id}`)}
                  >
                    Painel da equipe →
                  </button>
                </div>

                <div className="cycle-card__editors">
                  <div className="cycle-editor">
                    <span className="cycle-editor__label">Período</span>
                    {item.status === "PLANEJADO" ? (
                      editandoPeriodoId === item.id ? (
                        <div className="cycle-inline-form cycle-inline-form--period">
                          <input
                            type="date"
                            value={periodoInicioEdicao}
                            onChange={(event) =>
                              setPeriodoInicioEdicao(event.target.value)
                            }
                          />
                          <input
                            type="date"
                            value={periodoFimEdicao}
                            onChange={(event) =>
                              setPeriodoFimEdicao(event.target.value)
                            }
                          />
                          <button
                            className="cycle-btn cycle-btn--small cycle-btn--primary"
                            onClick={() => {
                              void (async () => {
                                const ok = await publicar(
                                  await controlador.editar({
                                    cicloId: item.id,
                                    ano: item.ano,
                                    numero: item.ciclo,
                                    dataInicio: periodoInicioEdicao,
                                    dataFim: periodoFimEdicao,
                                  }),
                                  "Não foi possível atualizar o período."
                                );
                                if (!ok) return;
                                setEditandoPeriodoId(null);
                                setVersao((valor) => valor + 1);
                              })();
                            }}
                          >
                            Salvar
                          </button>
                        </div>
                      ) : (
                        <button
                          className="cycle-link-button"
                          onClick={() => {
                            setEditandoPeriodoId(item.id);
                            setPeriodoInicioEdicao(item.dataInicio ?? "");
                            setPeriodoFimEdicao(item.dataFim ?? "");
                            setErro("");
                          }}
                        >
                          Editar período
                        </button>
                      )
                    ) : podeCorrigirPeriodo ? (
                      corrigindoPeriodoId === item.id ? (
                        <div className="cycle-period-correction-form">
                          <div className="cycle-inline-form cycle-inline-form--period">
                            <input
                              type="date"
                              aria-label="Nova data inicial"
                              value={periodoInicioCorrecao}
                              onChange={(event) =>
                                setPeriodoInicioCorrecao(event.target.value)
                              }
                            />
                            <input
                              type="date"
                              aria-label="Nova data final"
                              value={periodoFimCorrecao}
                              onChange={(event) =>
                                setPeriodoFimCorrecao(event.target.value)
                              }
                            />
                          </div>
                          <textarea
                            aria-label="Justificativa da correção"
                            placeholder="Justificativa obrigatória"
                            value={justificativaCorrecao}
                            onChange={(event) =>
                              setJustificativaCorrecao(event.target.value)
                            }
                          />
                          <div className="cycle-inline-form">
                            <button
                              className="cycle-btn cycle-btn--small cycle-btn--primary"
                              onClick={() => {
                                void corrigirPeriodoComAuditoria(item);
                              }}
                            >
                              Confirmar correção
                            </button>
                            <button
                              className="cycle-btn cycle-btn--small cycle-btn--secondary"
                              onClick={() => {
                                setCorrigindoPeriodoId(null);
                                setJustificativaCorrecao("");
                                setErro("");
                              }}
                            >
                              Cancelar
                            </button>
                          </div>
                        </div>
                      ) : (
                        <button
                          className="cycle-link-button"
                          onClick={() => {
                            setCorrigindoPeriodoId(item.id);
                            setPeriodoInicioCorrecao(item.dataInicio ?? "");
                            setPeriodoFimCorrecao(item.dataFim ?? "");
                            setJustificativaCorrecao("");
                            setErro("");
                          }}
                        >
                          Corrigir período
                        </button>
                      )
                    ) : (
                      <span className="cycle-muted">Bloqueado após o início</span>
                    )}
                  </div>

                  <div className="cycle-editor">
                    <span className="cycle-editor__label">Metas</span>
                    {item.status === "PLANEJADO" ? (
                      editandoMetasId === item.id ? (
                        <div className="cycle-inline-form">
                          <select
                            value={metasNegocioEdicao}
                            onChange={(event) =>
                              setMetasNegocioEdicao(
                                Number(event.target.value) as 0 | 1 | 2 | 3
                              )
                            }
                          >
                            <option value={0}>Negócio: 0</option>
                            <option value={1}>Negócio: 1</option>
                            <option value={2}>Negócio: 2</option>
                            <option value={3}>Negócio: 3</option>
                          </select>

                          <select
                            value={metasIndividuaisEdicao}
                            onChange={(event) =>
                              setMetasIndividuaisEdicao(
                                Number(event.target.value) as 0 | 1 | 2 | 3
                              )
                            }
                          >
                            <option value={0}>Individual: 0</option>
                            <option value={1}>Individual: 1</option>
                            <option value={2}>Individual: 2</option>
                            <option value={3}>Individual: 3</option>
                          </select>

                          <button
                            className="cycle-btn cycle-btn--small cycle-btn--primary"
                            onClick={() => {
                              try {
                                atualizarConfiguracaoMetasCiclo(
                                  item.id,
                                  metasNegocioEdicao,
                                  metasIndividuaisEdicao
                                );
                                setEditandoMetasId(null);
                                setErro("");
                                setVersao((valor) => valor + 1);
                              } catch (error) {
                                setErro(
                                  error instanceof Error
                                    ? error.message
                                    : "Não foi possível atualizar as metas."
                                );
                              }
                            }}
                          >
                            Salvar
                          </button>
                        </div>
                      ) : (
                        <button
                          className="cycle-link-button"
                          onClick={() => {
                            setEditandoMetasId(item.id);
                            setMetasNegocioEdicao(
                              item.quantidadeMetasNegocio ?? 0
                            );
                            setMetasIndividuaisEdicao(
                              item.quantidadeMetasIndividuais ?? 0
                            );
                            setErro("");
                          }}
                        >
                          Editar metas
                        </button>
                      )
                    ) : (
                      <span className="cycle-muted">Bloqueadas após o início</span>
                    )}
                  </div>

                  <div className="cycle-editor cycle-editor--actions">
                    <span className="cycle-editor__label">Status</span>
                    {item.status === "PLANEJADO" && (
                      <button
                        className="cycle-link-button"
                        onClick={() => {
                          void ativarComValidacao(item);
                        }}
                      >
                        Ativar ciclo
                      </button>
                    )}
                    {item.status === "ATIVO" && (
                      <button
                        className="cycle-link-button"
                        onClick={() => {
                          void encerrarComValidacao(item);
                        }}
                      >
                        Encerrar ciclo
                      </button>
                    )}
                    {item.status === "ENCERRADO" && (
                      <span className="cycle-muted">Ciclo encerrado</span>
                    )}
                    {item.status === "CANCELADO" && (
                      <span className="cycle-muted">Ciclo cancelado</span>
                    )}
                  </div>

                  {can(
                    {
                      actor: {
                        matricula: usuarioAtual.matricula,
                        funcao: usuarioAtual.funcao,
                        status: usuarioAtual.status,
                      },
                    },
                    "cycle.reopen.manager",
                    { kind: "cycle", cycle: item }
                  ) && (
                    <button
                      className="cycle-link-button"
                      onClick={() => {
                        void reabrirComMotivo(item);
                      }}
                    >
                      Reabrir ciclo
                    </button>
                  )}

                  {can(
                    {
                      actor: {
                        matricula: usuarioAtual.matricula,
                        funcao: usuarioAtual.funcao,
                        status: usuarioAtual.status,
                      },
                    },
                    "cycle.cancel.manager",
                    { kind: "cycle", cycle: item }
                  ) && (
                    <button
                      className="cycle-link-button cycle-link-button--danger"
                      onClick={() => {
                        void cancelarComMotivo(item);
                      }}
                    >
                      Cancelar ciclo
                    </button>
                  )}

                  {item.status === "PLANEJADO" && (
                    <button
                      className="cycle-link-button cycle-link-button--danger"
                      onClick={() => {
                        if (!confirmarExclusaoCiclo(item)) return;

                        try {
                          excluirAvaliacoesVaziasDoCiclo(item);
                          excluirCiclo(item.id);
                          setErro("");
                          setVersao((valor) => valor + 1);
                        } catch (error) {
                          setErro(
                            error instanceof Error
                              ? error.message
                              : "Não foi possível excluir o ciclo."
                          );
                        }
                      }}
                    >
                      Excluir ciclo
                    </button>
                  )}
                </div>

                <details className="cycle-history">
                  <summary>Ver histórico</summary>
                  <div className="cycle-history__content">
                    {eventosHistorico.length === 0 ? (
                      <p className="cycle-muted">
                        Nenhuma alteração auditada registrada.
                      </p>
                    ) : (
                      <ol className="cycle-history__timeline">
                        {eventosHistorico.map((evento, indice) => (
                          <li key={`${evento.tipo}-${evento.data}-${indice}`}>
                            <div className="cycle-history__heading">
                              <strong>
                                {evento.tipo === "encerramento"
                                  ? "Encerramento"
                                  : evento.tipo === "reabertura"
                                  ? "Reabertura"
                                  : evento.tipo === "cancelamento"
                                  ? "Cancelamento"
                                  : "Correção de período"}
                              </strong>
                              <time dateTime={evento.data}>
                                {formatarDataHoraHistorico(evento.data)}
                              </time>
                            </div>

                            {evento.tipo === "encerramento" ? (
                              <p>
                                {evento.encerradoComPendencias
                                  ? `Encerrado com pendências (${evento.quantidadePendencias}).`
                                  : `Encerrado sem pendências (${evento.quantidadePendencias}).`}
                              </p>
                            ) : (
                              <>
                                <p>
                                  Autor: {evento.autorNome} (matrícula {evento.autorMatricula})
                                </p>
                                <p>
                                  {evento.tipo === "correcao-periodo"
                                    ? "Justificativa"
                                    : "Motivo"}
                                  : {evento.tipo === "correcao-periodo"
                                    ? evento.justificativa
                                    : evento.motivo}
                                </p>
                              </>
                            )}

                            {evento.tipo === "correcao-periodo" && (
                              <>
                                <p>
                                  Período anterior: {formatarPeriodoCiclo(
                                    evento.periodoAnterior.dataInicio,
                                    evento.periodoAnterior.dataFim
                                  )}
                                </p>
                                <p>
                                  Novo período: {formatarPeriodoCiclo(
                                    evento.novoPeriodo.dataInicio,
                                    evento.novoPeriodo.dataFim
                                  )}
                                </p>
                                <p>
                                  Impacto: {evento.impacto.avaliacoes.quantidade} avaliação(ões), {evento.impacto.metas.quantidade} meta(s), {evento.impacto.observacoes.quantidade} observação(ões) — total {evento.impacto.total}.
                                </p>
                              </>
                            )}
                          </li>
                        ))}
                      </ol>
                    )}
                  </div>
                </details>
              </article>
            );
          })
        )}
      </section>
    </main>
  );
}

export default CiclosAvaliacaoPage;
