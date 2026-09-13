import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import { useAuth } from "../auth/AuthContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
/**
 * Único símbolo aproveitado do módulo legado: formatação PURA de período para
 * apresentação (função de string/Data — não lê storage, não decide e não
 * persiste). Toda autoridade de ciclo nesta página vem do controlador soberano.
 */
import { formatarPeriodoCiclo } from "../services/cicloAvaliacaoStorage";
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

/**
 * F5-09 P8 (Bloco 3) — HISTÓRICO: a página NÃO constrói mais trilha a partir do
 * modelo legado. `cycle_events` permanece deny-by-default (sem RLS nova e sem
 * RPC de leitura), então a trilha detalhada é apresentada como indisponível —
 * nunca como lista vazia "real" nem misturada com dado local.
 */

function CiclosAvaliacaoPage({
  mostrarCanceladosInicial = false,
  controlador: controladorInjetado,
}: CiclosAvaliacaoPageProps = {}) {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const { organizacaoAtivaId } = useAuth();
  /**
   * F5-09 P8 (Bloco 3): estados sem função foram removidos — `versao/setVersao`
   * (contador artificial de rerender; o estado agora vem do controlador),
   * `ativarAgora` (ativava ciclo na criação: virou operação soberana separada) e
   * os estados de metas (F5-10).
   */
  const [ano, setAno] = useState(new Date().getFullYear());
  const [ciclo, setCiclo] = useState<1 | 2 | 3>(1);
  const [dataInicio, setDataInicio] = useState("");
  const [dataFim, setDataFim] = useState("");
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

        {/*
          F5-09 P8 (Bloco 3): a criação NÃO envia metas — a Edge P7 não as aceita
          e o PostgreSQL é a única autoridade. Nenhuma persistência temporária.
        */}
        <p className="cycle-helper">
          Configuração de metas será disponibilizada na etapa F5-10. Este
          formulário cria apenas o ciclo (ano, número e período).
        </p>

        <div className="cycle-create-footer">
          <span className="cycle-helper">
            O ciclo é criado como PLANEJADO; a ativação é uma operação separada.
          </span>

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
                        <small>Metas</small>
                        <strong>Configuração na etapa F5-10</strong>
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
                    <span className="cycle-muted">
                      Configuração de metas será disponibilizada na etapa F5-10.
                    </span>
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

                  {/*
                    F5-09 P8 (Bloco 3): a exclusão FÍSICA saiu da UI. Ela exigia
                    apagar avaliações vazias e o ciclo no armazenamento local —
                    nenhum dos dois é autoridade. O ciclo PLANEJADO é resolvido no
                    domínio por "Cancelar ciclo" (soft, auditável).
                  */}
                  {item.status === "PLANEJADO" && (
                    <span className="cycle-muted">
                      Exclusão física indisponível nesta fase: use “Cancelar ciclo”.
                    </span>
                  )}
                </div>

                <details className="cycle-history">
                  <summary>Ver histórico</summary>
                  <div className="cycle-history__content">
                    <p className="cycle-muted">
                      Histórico detalhado indisponível nesta fase da migração: a
                      trilha auditada de ciclo não é lida do modelo local nem de
                      cycle_events (deny-by-default, sem RPC de leitura).
                    </p>
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
