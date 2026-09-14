import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import { useAuth } from "../auth/AuthContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { formatarPeriodoCiclo } from "./cicloApresentacaoLegada";
import {
  getPainelCiclo,
  type ProgressoPapelPainel,
  type SituacaoAvaliacaoCiclo,
} from "../services/cicloEquipeService";
import {
  obterRepositorioCiclosSoberanos,
  type CicloSoberano,
} from "../services/acessoCiclosSoberanos";
import { obterRepositorioMetasSoberanas } from "../services/acessoMetasSoberanas";
import type { MetaSoberana } from "../application/ports/GoalRepository";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import { getColaboradores } from "../services/colaboradorStorage";
import {
  collaboratorIdDoLegado,
  matriculaLegadaDoCollaborator,
  estruturaSoberanaEfetiva,
} from "../services/estruturaSoberanaCliente";
import "../styles/ciclos.css";
import "../styles/equipe-colegiado.css";
import "../styles/metas-gestao.css";
import "../styles/historico-ciclo.css";
import { obterAcaoAvaliacaoPainel } from "./painelCicloAvaliacaoAction";
import {
  cicloLegadoDeApresentacao,
  contarAprovacoesPendentes,
  indisponivel,
  relacoesSoberanasPorColaborador,
} from "./painelCicloMetasSoberanas";
import { getStatusGeralPainel } from "./painelCicloStatus";

/**
 * F5-10 P6 (Issue #220) — CUTOVER FUNCIONAL DO PAINEL DE CICLO.
 *
 * ## Identidade do ciclo
 *
 * O ciclo deixa de ser resolvido pelo storage LEGADO
 * (`getCiclosAvaliacao().find(...)`) e passa a ser resolvido pelo **UUID
 * soberano** (`CycleRepository.obterCiclo` → `evaluation_cycles`, RLS
 * own-tenant do F5-09 P5). A organização é a **organização ativa** do contexto
 * de auth (`organizacaoAtivaId`), tratada como INTENÇÃO de UX — quem isola o
 * tenant é a RLS. Não há fallback para ciclo local e nada é resolvido por
 * `ano`/`numero` (que seguem apenas RÓTULOS de apresentação).
 *
 * ## Autoridade de METAS (decisão FECHADA da P5.3, D1)
 *
 * O painel usa SOMENTE a leitura soberana `goal.listar_por_escopo`, cujo
 * conjunto autorizado é `SELF ∪ APROVADOR_GERENTE_CONGELADO ∪
 * APROVADOR_COORDENADOR_CONGELADO` no ciclo. **Não existe leitura cycle-wide.**
 * Os únicos usos de metas são:
 *
 * - o KPI agregado "Minhas aprovações de metas" — contagem das metas em que o
 *   ator é **aprovador congelado aplicável** e o papel correspondente está
 *   *exigido e pendente*, pelos FATOS `aprovacoes[].exigida`/`vigente` (nunca
 *   `aprovacaoGerente`/`aprovacaoCoordenador`, nunca `funcao`, nunca
 *   `gestorDiretoMatricula`);
 * - o botão "Acompanhar metas", decidido pela **relação soberana já autorizada**
 *   (o colaborador aparece no conjunto devolvido pela leitura) — nunca por
 *   gate legado de metas da Policy Engine de cliente.
 *
 * Metas de colaboradores `NAO_APLICAVEL` ou `SUSPENSA` no ciclo ficam fora do
 * KPI (D6), pela `situacao` que o painel JÁ calcula por colaborador.
 *
 * ## Estados
 *
 * A leitura é ASSÍNCRONA: a tela distingue **carregando**, **pronta** e
 * **indisponível** — erro de leitura NUNCA vira zero silencioso nem cache
 * local. Resposta de contexto anterior (organização/ciclo/refresh) e qualquer
 * `setState` depois do desmonte são descartados.
 *
 * ## O que NÃO mudou
 *
 * O comportamento de AVALIAÇÃO/colaborador (tabela por colaborador, blocos por
 * vínculo, status geral, ações de avaliação) é o mesmo. O gate geral da página
 * (`cycle.team.panel.view`) é DÍVIDA SEPARADA do domínio de ciclo/avaliação (D5)
 * e não foi substituído por `goal.read`.
 */

/** Leitura soberana do KPI de aprovações: nunca "zero silencioso". */
export type EstadoAprovacoesPainel =
  | { readonly fase: "carregando" }
  | { readonly fase: "pronta"; readonly metas: readonly MetaSoberana[] }
  | {
      readonly fase: "indisponivel";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    };

/** Estado do CICLO soberano (UUID) — sempre explícito, nunca inferido. */
type EstadoCicloPainel =
  | { readonly fase: "carregando" }
  | { readonly fase: "pronta"; readonly ciclo: CicloSoberano | null }
  | {
      readonly fase: "erro";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    };

/** Sem organização ativa nada é lido: fail-closed, nunca leitura "global". */
const SEM_ORGANIZACAO_ATIVA = "Organização ativa ausente.";

function labelPapel(progresso: ProgressoPapelPainel) {
  if (progresso.situacao === "NAO_APLICA") return "—";
  if (progresso.situacao === "CONCLUIDO") return "Concluído";
  if (progresso.situacao === "PENDENTE") {
    return `Pendente ${progresso.preenchidos}/${progresso.total}`;
  }
  if (progresso.situacao === "EM_ANDAMENTO") {
    return `Em andamento ${progresso.preenchidos}/${progresso.total}`;
  }
  return `Não iniciado 0/${progresso.total}`;
}

function classePapel(progresso: ProgressoPapelPainel) {
  if (progresso.situacao === "CONCLUIDO") return "is-complete";
  if (progresso.situacao === "PENDENTE") return "is-pending";
  if (progresso.situacao === "EM_ANDAMENTO") return "is-progress";
  if (progresso.situacao === "NAO_APLICA") return "is-na";
  return "is-not-started";
}

/**
 * Códigos PÚBLICOS que a leitura de metas pode devolver. QUALQUER um deles é
 * INDISPONIBILIDADE explícita para a tela: erro de leitura jamais pode ser lido
 * como "não há aprovação pendente".
 */
function codigoPublicoDaLeitura(codigo: string): CodigoPublico {
  switch (codigo) {
    case "CONFLICT":
    case "NOT_FOUND":
    case "INVALID_INPUT":
    case "INTERNAL":
    case "NOT_AUTHORIZED":
    case "FORBIDDEN":
      return codigo;
    default:
      return "INTERNAL";
  }
}

// Os helpers PUROS de METAS SOBERANAS do painel
// (`relacoesSoberanasPorColaborador`, `metaEntraNoKpiDeAprovacoes`,
// `contarAprovacoesPendentes`, `cicloLegadoDeApresentacao` e `indisponivel`, com
// seus privados) vivem no companheiro `./painelCicloMetasSoberanas`: este
// arquivo exporta apenas o componente e TIPOS
// (`react-refresh/only-export-components`).

function PainelCicloPage() {
  const { cicloId } = useParams();
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const { organizacaoAtivaId } = useAuth();
  const [mostrarCanceladas, setMostrarCanceladas] = useState(false);
  const [tentativa, setTentativa] = useState(0);

  /**
   * Resultado da leitura SOBERANA, publicado SEMPRE com a CHAVE do contexto que
   * o produziu (organização + ciclo + tentativa). O estado EXIBIDO é DERIVADO
   * dessa chave (mesmo padrão de `MinhasMetasPage`): nada é resetado dentro do
   * efeito — resposta de contexto anterior não casa com a chave corrente e a
   * tela permanece `carregando`.
   */
  const [leitura, setLeitura] = useState<{
    readonly chave: string;
    readonly ciclo: EstadoCicloPainel;
    readonly aprovacoes: EstadoAprovacoesPainel;
  } | null>(null);

  const podeAcessarPainelCiclo = usuarioAtual
    ? can(
        {
          actor: {
            matricula: usuarioAtual.matricula,
            funcao: usuarioAtual.funcao,
            status: usuarioAtual.status,
          },
        },
        "cycle.team.panel.view",
        { kind: "global" }
      )
    : false;

  // O acesso ao painel é decidido ANTES da carga: sem acesso não há leitura.
  const habilitado = Boolean(usuarioAtual) && podeAcessarPainelCiclo;

  const semOrganizacaoAtiva = !organizacaoAtivaId;
  const semCiclo = !cicloId;
  /** Chave do contexto da leitura: organização + ciclo + tentativa. */
  const chaveLeitura = `${organizacaoAtivaId ?? "sem-organizacao"}|${
    cicloId ?? "sem-ciclo"
  }|${tentativa}`;

  useEffect(() => {
    if (!habilitado || !organizacaoAtivaId || !cicloId) return;

    // A chave fica FIXA nesta execução: só ela pode publicar o resultado.
    const organizacaoId = organizacaoAtivaId;
    const cicloIdAlvo = cicloId;

    let ativo = true;
    let estadoCiclo: EstadoCicloPainel = { fase: "carregando" };
    let estadoAprovacoes: EstadoAprovacoesPainel = { fase: "carregando" };

    // Publica SEMPRE com a chave do contexto corrente — resposta de contexto
    // anterior não é exibida — e `ativo` descarta `setState` pós-desmonte.
    const publicar = () => {
      if (ativo) {
        setLeitura({
          chave: chaveLeitura,
          ciclo: estadoCiclo,
          aprovacoes: estadoAprovacoes,
        });
      }
    };

    const publicarCiclo = (estado: EstadoCicloPainel) => {
      estadoCiclo = estado;
      publicar();
    };

    const publicarAprovacoes = (estado: EstadoAprovacoesPainel) => {
      estadoAprovacoes = estado;
      publicar();
    };

    void (async () => {
      try {
        const cicloRepositorio = obterRepositorioCiclosSoberanos();
        if (!cicloRepositorio) {
          const mensagem =
            "Leitura soberana de ciclos indisponível neste ambiente.";
          publicarCiclo({ fase: "erro", codigo: "INTERNAL", mensagem });
          publicarAprovacoes(indisponivel("INTERNAL", mensagem));
          return;
        }

        const leituraCiclo = await cicloRepositorio.obterCiclo(
          organizacaoId,
          cicloIdAlvo
        );

        if (!leituraCiclo.ok) {
          publicarCiclo({
            fase: "erro",
            codigo: leituraCiclo.error.code,
            mensagem: leituraCiclo.error.message,
          });
          publicarAprovacoes(
            indisponivel(leituraCiclo.error.code, leituraCiclo.error.message)
          );
          return;
        }

        const ciclo = leituraCiclo.data;
        if (!ciclo) {
          // Ciclo inexistente (ou de outro tenant) NÃO é erro de leitura.
          publicarCiclo({ fase: "pronta", ciclo: null });
          publicarAprovacoes({ fase: "pronta", metas: [] });
          return;
        }

        publicarCiclo({ fase: "pronta", ciclo });

        if (ciclo.status === "CANCELADO") {
          // Ciclo cancelado não tem aprovação pendente acionável: ZERO REAL,
          // derivado do estado SOBERANO do ciclo — nunca de falha de leitura.
          publicarAprovacoes({ fase: "pronta", metas: [] });
          return;
        }

        // KPI: UMA leitura soberana por ciclo (SELF ∪ aprovadores CONGELADOS).
        const metasRepositorio = obterRepositorioMetasSoberanas();
        if (!metasRepositorio) {
          publicarAprovacoes(
            indisponivel(
              "INTERNAL",
              "Leitura soberana de metas indisponível neste ambiente."
            )
          );
          return;
        }

        const leituraEscopo = await metasRepositorio.listarMetasPorEscopo(
          organizacaoId,
          ciclo.id
        );

        if (!leituraEscopo.ok) {
          // ERRO DE LEITURA ⇒ INDISPONÍVEL. Nunca zero silencioso.
          publicarAprovacoes(
            indisponivel(
              codigoPublicoDaLeitura(leituraEscopo.error.code),
              leituraEscopo.error.message
            )
          );
          return;
        }

        // Conjunto vazio é ausência EXPLÍCITA de meta autorizada ⇒ zero real.
        // A elegibilidade por aplicabilidade (D6) é aplicada no render, sobre a
        // `situacao` que o painel já calcula por colaborador.
        publicarAprovacoes({ fase: "pronta", metas: leituraEscopo.data.metas });
      } catch {
        // Falha de TRANSPORTE (exceção do adaptador) é INDISPONIBILIDADE
        // explícita na tela — jamais `carregando` infinito nem zero silencioso.
        const mensagem =
          "Não foi possível concluir a leitura soberana deste ciclo.";
        publicarCiclo({ fase: "erro", codigo: "INTERNAL", mensagem });
        publicarAprovacoes(indisponivel("INTERNAL", mensagem));
      }
    })();

    return () => {
      ativo = false;
    };
  }, [habilitado, organizacaoAtivaId, cicloId, chaveLeitura]);

  /**
   * Estado EXIBIDO DERIVADO (sem `setState` no corpo do efeito): sem resultado
   * para a chave do contexto corrente a tela está `carregando`; sem organização
   * ativa nada é lido (fail-closed) e sem ciclo não há leitura a fazer.
   */
  const leituraCorrente = leitura?.chave === chaveLeitura ? leitura : null;
  const cicloEstado: EstadoCicloPainel = semOrganizacaoAtiva
    ? { fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ORGANIZACAO_ATIVA }
    : semCiclo
    ? { fase: "pronta", ciclo: null }
    : leituraCorrente?.ciclo ?? { fase: "carregando" };
  const aprovacoes: EstadoAprovacoesPainel = semOrganizacaoAtiva
    ? indisponivel("FORBIDDEN", SEM_ORGANIZACAO_ATIVA)
    : semCiclo
    ? { fase: "pronta", metas: [] }
    : leituraCorrente?.aprovacoes ?? { fase: "carregando" };

  if (!usuarioAtual || !podeAcessarPainelCiclo) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Acesso restrito</h1>
          <p>O painel do ciclo está disponível para gerentes e coordenadores.</p>
        </section>
      </main>
    );
  }

  if (cicloEstado.fase === "carregando") {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Carregando o ciclo…</h1>
          <p>Aguardando a leitura soberana do ciclo.</p>
        </section>
      </main>
    );
  }

  if (cicloEstado.fase === "erro") {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Ciclo indisponível</h1>
          <p>{cicloEstado.mensagem}</p>
          <button
            className="cycle-btn cycle-btn--secondary"
            onClick={() => setTentativa((valor) => valor + 1)}
          >
            Tentar novamente
          </button>
        </section>
      </main>
    );
  }

  if (!cicloEstado.ciclo) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Ciclo não encontrado</h1>
        </section>
      </main>
    );
  }

  const usuario = usuarioAtual;
  const cicloSoberano = cicloEstado.ciclo;
  const cicloAtual = cicloLegadoDeApresentacao(cicloSoberano);
  const linhas = getPainelCiclo(cicloAtual, usuario, {
    incluirCanceladas: mostrarCanceladas,
  });
  const separarPorVinculo = usuario.funcao === "COORDENADOR";

  // D6: fonte de aplicabilidade JÁ usada pelo painel — a `situacao` por
  // colaborador. `NAO_APLICAVEL` e `SUSPENSA` ficam fora do KPI.
  const matriculasForaDoKpi = new Set(
    linhas
      .filter(
        (linha) =>
          linha.situacao === "NAO_APLICAVEL" || linha.situacao === "SUSPENSA"
      )
      .map((linha) => linha.colaborador.matricula)
  );
  // A ponte é de APRESENTAÇÃO (UUID soberano → matrícula legada) e usa a
  // estrutura SOBERANA publicada; sem ponte o colaborador NÃO é elegível.
  const estruturaSoberana = estruturaSoberanaEfetiva();
  const colaboradorElegivelParaKpi = (collaboratorId: string) => {
    const matricula = matriculaLegadaDoCollaborator(
      estruturaSoberana,
      collaboratorId
    );
    return matricula !== null && !matriculasForaDoKpi.has(matricula);
  };
  const idSoberanoDoColaborador = (matricula: number) =>
    collaboratorIdDoLegado(estruturaSoberana, matricula) ?? "";

  const linhasEquipeDireta = separarPorVinculo
    ? linhas.filter(
        (linha) =>
          linha.colaborador.gestorDiretoMatricula === usuario.matricula
      )
    : linhas;

  const linhasColegiado = separarPorVinculo
    ? linhas.filter(
        (linha) =>
          linha.colaborador.gestorDiretoMatricula !== usuario.matricula
      )
    : [];

  const totais = linhas.reduce(
    (acc, linha) => {
      acc[linha.situacao] += 1;
      return acc;
    },
    {
      NAO_INICIADA: 0,
      EM_ANDAMENTO: 0,
      PRONTA_PARA_FEEDBACK: 0,
      CONCLUIDA: 0,
      CANCELADA: 0,
      SUSPENSA: 0,
      NAO_APLICAVEL: 0,
    } as Record<SituacaoAvaliacaoCiclo, number>
  );

  // Metas do conjunto AUTORIZADO (SELF ∪ aprovadores congelados) — fonte única
  // do KPI e do botão "Acompanhar metas".
  const metasAutorizadas =
    aprovacoes.fase === "pronta" ? aprovacoes.metas : [];
  const relacoesSoberanas =
    relacoesSoberanasPorColaborador(metasAutorizadas);
  const aprovacoesPendentes = contarAprovacoesPendentes(
    metasAutorizadas,
    colaboradorElegivelParaKpi
  );

  const indicadores = [
    { label: "Total", valor: linhas.length },
    { label: "Não iniciadas", valor: totais.NAO_INICIADA },
    { label: "Em andamento", valor: totais.EM_ANDAMENTO },
    { label: "Prontas p/ feedback", valor: totais.PRONTA_PARA_FEEDBACK },
    { label: "Concluídas", valor: totais.CONCLUIDA },
    { label: "Minhas aprovações de metas", valor: aprovacoesPendentes },
  ];

  function obterAcaoAvaliacao(linha: (typeof linhas)[number]) {
    if (!linha.feedback) return undefined;
    return obterAcaoAvaliacaoPainel(
      usuario,
      linha.colaborador,
      getColaboradores(),
      cicloAtual,
      linha.feedback
    );
  }

  function renderTabelaGrupo(
    linhasGrupo: typeof linhas,
    titulo: string,
    descricao: string
  ) {
    return (
      <section className="cycle-table-card cycle-team-group">
        <div className="cycle-table-heading">
          <div>
            <h2>{titulo}</h2>
            <p className="cycle-team-group__description">{descricao}</p>
          </div>
          <span>{linhasGrupo.length} colaboradores</span>
        </div>

        {linhasGrupo.length === 0 ? (
          <div className="cycle-empty cycle-team-group__empty">
            <p>Nenhum colaborador neste grupo.</p>
          </div>
        ) : (
          <div className="cycle-table-wrap">
            <div className="cycle-table cycle-table--responsive">
              <div className="cycle-table__row cycle-table__row--header">
                <div>Colaborador</div>
                <div>Gerente</div>
                <div>Coordenador</div>
                <div>Colegiado</div>
                <div>Status geral</div>
                <div>Ações</div>
              </div>

              {linhasGrupo.map((linha) => {
                const acaoAvaliacao = obterAcaoAvaliacao(linha);
                const statusGeral = getStatusGeralPainel(
                  linha.situacao,
                  cicloAtual.status
                );
                return (
                  <div
                    className="cycle-table__row"
                    key={linha.colaborador.matricula}
                  >
                  <div className="cycle-person">
                    <div className="cycle-person__avatar">
                      {linha.colaborador.nome
                        .split(" ")
                        .filter(Boolean)
                        .slice(0, 2)
                        .map((p) => p[0])
                        .join("")
                        .toUpperCase()}
                    </div>
                    <div>
                      <strong>{linha.colaborador.nome}</strong>
                      <span>
                        {linha.colaborador.funcao === "COORDENADOR"
                          ? "Coordenador"
                          : linha.colaborador.funcao === "CONSULTOR"
                          ? "Consultor"
                          : linha.colaborador.funcao === "ESTAGIARIO"
                          ? "Estagiário"
                          : "Analista"}
                      </span>
                    </div>
                  </div>

                  <div className="cycle-mobile-field" data-label="Gerente">
                    <span
                      className={`cycle-progress ${classePapel(linha.gerente)}`}
                    >
                      {labelPapel(linha.gerente)}
                    </span>
                  </div>

                  <div className="cycle-mobile-field" data-label="Coordenador">
                    <span
                      className={`cycle-progress ${classePapel(
                        linha.coordenador
                      )}`}
                    >
                      {labelPapel(linha.coordenador)}
                    </span>
                  </div>

                  <div className="cycle-mobile-field" data-label="Colegiado">
                    <span
                      className={`cycle-progress ${classePapel(
                        linha.colegiado
                      )}`}
                    >
                      {labelPapel(linha.colegiado)}
                    </span>
                  </div>

                  <div className="cycle-mobile-field" data-label="Status geral">
                    <span
                      className={`cycle-general-status ${statusGeral.className}`}
                    >
                      {statusGeral.label}
                    </span>
                    {linha.motivoNaoAplicavel && (
                      <small className="cycle-muted">
                        {(() => {
                          const motivo = linha.motivoNaoAplicavel
                            .replace(/^Não aplicável\s*[—–-]\s*/i, "")
                            .replace(/^Suspensa\s*[—–-]\s*/i, "");

                          return motivo
                            ? motivo.charAt(0).toUpperCase() + motivo.slice(1)
                            : motivo;
                        })()}
                      </small>
                    )}
                    {linha.feedback?.encerradaComPendencias && (
                      <small className="cycle-danger-text">
                        Encerrada com pendências
                      </small>
                    )}
                  </div>

                  <div className="cycle-row-actions">
                    {relacoesSoberanas.has(
                      idSoberanoDoColaborador(linha.colaborador.matricula)
                    ) && (
                      <button
                        className="cycle-btn cycle-btn--small cycle-btn--secondary"
                        onClick={() =>
                          navigate(
                            `/ciclos/${cicloSoberano.id}/colaborador/${linha.colaborador.matricula}/metas`
                          )
                        }
                      >
                        Acompanhar metas
                      </button>
                    )}

                    {acaoAvaliacao ? (
                      <button
                        className="cycle-btn cycle-btn--small cycle-btn--secondary"
                        onClick={() => navigate(acaoAvaliacao.destino)}
                      >
                        {acaoAvaliacao.label}
                      </button>
                    ) : !linha.feedback ? (
                      <span className="cycle-muted">Avaliação não criada</span>
                    ) : null}
                  </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </section>
    );
  }

  return (
    <main className="virtus-page cycle-panel-page">
      <section className="cycle-page-header">
        <div>
          <button
            className="cycle-back-link"
            onClick={() =>
              navigate(
                usuario.funcao === "COORDENADOR"
                  ? "/painel-ciclos"
                  : "/ciclos"
              )
            }
          >
            ← Voltar aos ciclos
          </button>
          <h1>
            {cicloSoberano.ano} <span>•</span> Ciclo {cicloSoberano.numero}
          </h1>
          <p>
            {formatarPeriodoCiclo(
              cicloSoberano.dataInicio ?? undefined,
              cicloSoberano.dataFim ?? undefined
            )}
          </p>
        </div>

        <span
          className={`cycle-status ${
            cicloSoberano.status === "ATIVO"
              ? "is-active"
              : cicloSoberano.encerradoComPendencias
              ? "is-warning"
              : "is-closed"
          }`}
        >
          {cicloSoberano.status === "ATIVO"
            ? "Ativo"
            : cicloSoberano.status === "CANCELADO"
            ? "Cancelado"
            : cicloSoberano.encerradoComPendencias
            ? "Encerrado com pendências"
            : "Encerrado"}
        </span>
      </section>

      {aprovacoes.fase === "indisponivel" && (
        <section className="cycle-empty cycle-team-group__empty">
          <p>
            Não foi possível ler as suas aprovações de metas neste ciclo (
            {aprovacoes.codigo}): {aprovacoes.mensagem}
          </p>
          <button
            className="cycle-btn cycle-btn--secondary"
            onClick={() => setTentativa((valor) => valor + 1)}
          >
            Tentar novamente
          </button>
        </section>
      )}

      <section className="cycle-kpis">
        {indicadores.map((indicador) => (
          <div className="cycle-kpi" key={indicador.label}>
            <span>{indicador.label}</span>
            <strong>
              {indicador.label === "Minhas aprovações de metas" &&
              aprovacoes.fase !== "pronta"
                ? "—"
                : indicador.valor}
            </strong>
          </div>
        ))}
      </section>

      <label className="cycle-show-cancelled">
        <input
          type="checkbox"
          checked={mostrarCanceladas}
          onChange={(event) => setMostrarCanceladas(event.target.checked)}
        />
        Mostrar canceladas
      </label>

      {separarPorVinculo ? (
        <div className="cycle-team-groups">
          {renderTabelaGrupo(
            linhasEquipeDireta,
            "Minha equipe direta",
            "Colaboradores que respondem diretamente para você neste ciclo."
          )}
          {renderTabelaGrupo(
            linhasColegiado,
            "Avaliações como colegiado",
            "Colaboradores de outras equipes em que você participa como avaliador do colegiado. Metas não ficam disponíveis por vínculo de colegiado."
          )}
        </div>
      ) : (
        renderTabelaGrupo(
          linhas,
          "Equipe no ciclo",
          "Acompanhamento das avaliações elegíveis na estrutura."
        )
      )}
    </main>
  );
}

export default PainelCicloPage;