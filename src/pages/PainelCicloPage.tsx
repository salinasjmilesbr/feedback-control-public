import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import type { GoalResource } from "../authorization/ResourceContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import {
  getCiclosAvaliacao,
  formatarPeriodoCiclo,
} from "../services/cicloAvaliacaoStorage";
import {
  getPainelCiclo,
  type ProgressoPapelPainel,
  type SituacaoAvaliacaoCiclo,
} from "../services/cicloEquipeService";
import {
  getMetasDoCiclo,
} from "../services/metaStorage";
import { getColaboradores } from "../services/colaboradorStorage";
import { getColaboradoresEfetivosNoCiclo } from "../services/historicoOrganizacionalStorage";
import "../styles/ciclos.css";
import "../styles/equipe-colegiado.css";
import "../styles/metas-gestao.css";
import "../styles/historico-ciclo.css";
import { obterAcaoAvaliacaoPainel } from "./painelCicloAvaliacaoAction";

const labelsSituacao: Record<SituacaoAvaliacaoCiclo, string> = {
  NAO_INICIADA: "Não iniciada",
  EM_ANDAMENTO: "Em andamento",
  PRONTA_PARA_FEEDBACK: "Pronta para Feedback",
  CONCLUIDA: "Concluída",
  CANCELADA: "Cancelada",
  SUSPENSA: "Suspensa",
  NAO_APLICAVEL: "Não aplicável",
};

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

function PainelCicloPage() {
  const { cicloId } = useParams();
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const [mostrarCanceladas, setMostrarCanceladas] = useState(false);
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

  const ciclo = getCiclosAvaliacao().find((item) => item.id === cicloId);

  if (!ciclo) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Ciclo não encontrado</h1>
        </section>
      </main>
    );
  }

  const usuario = usuarioAtual;
  const cicloAtual = ciclo;
  const linhas = getPainelCiclo(cicloAtual, usuario, {
    incluirCanceladas: mostrarCanceladas,
  });
  const colaboradoresAutorizacao = getColaboradoresEfetivosNoCiclo(
    cicloAtual,
    getColaboradores()
  );
  const colaboradoresEfetivos = new Map(
    linhas.map((linha) => [linha.colaborador.matricula, linha.colaborador])
  );
  const metasDoCiclo = getMetasDoCiclo(cicloAtual.id);
  const separarPorVinculo = usuario.funcao === "COORDENADOR";

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

  // Este KPI mostra somente o que depende do perfil que está vendo a tela:
  // gerente -> aprovações do gerente pendentes;
  // coordenador -> aprovações do coordenador direto pendentes.
  const matriculasComAcessoAMetas = new Set(
    linhas
      .filter(
        (linha) =>
          usuario.funcao === "GERENTE" ||
          linha.colaborador.gestorDiretoMatricula === usuario.matricula
      )
      .map((linha) => linha.colaborador.matricula)
  );

  const metasPendentesDoPerfil =
    cicloAtual.status === "CANCELADO"
      ? 0
      : metasDoCiclo.filter((meta) => {
          if (!matriculasComAcessoAMetas.has(meta.colaboradorMatricula)) {
            return false;
          }

          if (usuario.funcao === "GERENTE") {
            return !meta.aprovacaoGerente;
          }

          const colaborador = colaboradoresEfetivos.get(
            meta.colaboradorMatricula
          );

          return (
            colaborador?.gestorDiretoMatricula === usuario.matricula &&
            !meta.aprovacaoCoordenador
          );
        }).length;

  const indicadores = [
    { label: "Total", valor: linhas.length },
    { label: "Não iniciadas", valor: totais.NAO_INICIADA },
    { label: "Em andamento", valor: totais.EM_ANDAMENTO },
    { label: "Prontas p/ feedback", valor: totais.PRONTA_PARA_FEEDBACK },
    { label: "Concluídas", valor: totais.CONCLUIDA },
    {
      label:
        usuario.funcao === "GERENTE"
          ? "Minhas aprovações de metas"
          : "Minhas aprovações de metas",
      valor: metasPendentesDoPerfil,
    },
  ];

  function podeVerMetas(
    colaborador: (typeof linhas)[number]["colaborador"]
  ) {
    const resource: GoalResource = {
      kind: "goal",
      owner: colaborador,
      collaborators: colaboradoresAutorizacao,
      cycle: cicloAtual,
    };
    return can(
      { actor: usuario },
      "goal.view.admin",
      resource
    );
  }

  function obterAcaoAvaliacao(linha: (typeof linhas)[number]) {
    if (!linha.feedback) return undefined;
    return obterAcaoAvaliacaoPainel(
      usuario,
      linha.colaborador,
      colaboradoresAutorizacao,
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
                const situacaoExibida =
                  cicloAtual.status === "CANCELADO"
                    ? "CANCELADA"
                    : linha.situacao;
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
                      className={`cycle-general-status ${
                        situacaoExibida === "CONCLUIDA"
                          ? "is-complete"
                          : situacaoExibida === "CANCELADA"
                          ? "is-cancelled"
                          : linha.situacao === "PRONTA_PARA_FEEDBACK"
                          ? "is-feedback"
                          : linha.situacao === "EM_ANDAMENTO"
                          ? "is-progress"
                          : linha.situacao === "SUSPENSA" ||
                            linha.situacao === "NAO_APLICAVEL"
                          ? "is-na"
                          : "is-not-started"
                      }`}
                    >
                      {cicloAtual.status === "CANCELADO"
                        ? "Ciclo cancelado"
                        : labelsSituacao[situacaoExibida]}
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
                    {podeVerMetas(linha.colaborador) && (
                      <button
                        className="cycle-btn cycle-btn--small cycle-btn--secondary"
                        onClick={() =>
                          navigate(
                            `/ciclos/${cicloAtual.id}/colaborador/${linha.colaborador.matricula}/metas`
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
            {ciclo.ano} <span>•</span> Ciclo {ciclo.ciclo}
          </h1>
          <p>{formatarPeriodoCiclo(ciclo.dataInicio, ciclo.dataFim)}</p>
        </div>

        <span
          className={`cycle-status ${
            ciclo.status === "ATIVO"
              ? "is-active"
              : ciclo.encerradoComPendencias
              ? "is-warning"
              : "is-closed"
          }`}
        >
          {ciclo.status === "ATIVO"
            ? "Ativo"
            : ciclo.status === "CANCELADO"
            ? "Cancelado"
            : ciclo.encerradoComPendencias
            ? "Encerrado com pendências"
            : "Encerrado"}
        </span>
      </section>

      <section className="cycle-kpis">
        {indicadores.map((indicador) => (
          <div className="cycle-kpi" key={indicador.label}>
            <span>{indicador.label}</span>
            <strong>{indicador.valor}</strong>
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
