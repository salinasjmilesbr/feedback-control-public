import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { GoalResource } from "../authorization/ResourceContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import CollaboratorIdentity from "../components/CollaboratorIdentity";
import {
  formatarPeriodoCiclo,
  getCiclosAvaliacao,
} from "../services/cicloAvaliacaoStorage";
import {
  getColaboradorByMatricula,
  getColaboradores,
} from "../services/colaboradorStorage";
import {
  aprovarMeta,
  getMetasDoColaboradorNoCiclo,
  metaEstaAprovada,
  metaExigeAprovacaoCoordenador,
} from "../services/metaStorage";
import { getColaboradorEfetivoNoCiclo } from "../services/historicoOrganizacionalStorage";
import type { Meta } from "../types/Meta";
import "../styles/ciclos.css";
import "../styles/metas-gestao.css";
import "../styles/historico-ciclo.css";

function formatarDataHora(data?: string) {
  if (!data) return "Ainda não atualizado";

  return new Date(data).toLocaleString("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  });
}

function AcompanhamentoMetasPage() {
  const { cicloId, id } = useParams();
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const [versao, setVersao] = useState(0);
  const [erro, setErro] = useState("");

  if (!usuarioAtual) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Acesso restrito</h1>
          <p>O acompanhamento de metas está disponível para gestores.</p>
        </section>
      </main>
    );
  }

  const ciclo = getCiclosAvaliacao().find((item) => item.id === cicloId);
  const matricula = Number(id);
  const colaborador = Number.isFinite(matricula)
    ? getColaboradorByMatricula(matricula)
    : undefined;

  if (!ciclo || !colaborador) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Metas não encontradas</h1>
        </section>
      </main>
    );
  }

  const usuario = usuarioAtual;
  const cicloAtual = ciclo;
  const colaboradorAtual = colaborador;
  const colaboradores = getColaboradores();
  const colaboradorEfetivo = getColaboradorEfetivoNoCiclo(
    colaboradorAtual,
    cicloAtual,
    colaboradores
  );
  const authorizationContext: AuthorizationContext = {
    actor: {
      matricula: usuario.matricula,
      funcao: usuario.funcao,
      status: usuario.status,
    },
  };
  const goalResource: GoalResource = {
    kind: "goal",
    owner: colaboradorAtual,
    collaborators: colaboradores,
    cycle: cicloAtual,
  };
  const podeAprovarComoGerente = can(
    authorizationContext,
    "goal.approve.manager",
    goalResource
  );
  const podeAprovarComoCoordenador = can(
    authorizationContext,
    "goal.approve.coordinator",
    goalResource
  );
  const podeAcessar = can(
    authorizationContext,
    "goal.view.admin",
    goalResource
  );

  if (!podeAcessar) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Acesso restrito</h1>
          <p>
            A participação como colegiado não concede acesso às metas do
            colaborador.
          </p>
          <button
            className="cycle-btn cycle-btn--secondary"
            onClick={() => navigate(`/ciclos/${cicloAtual.id}`)}
          >
            Voltar ao ciclo
          </button>
        </section>
      </main>
    );
  }

  void versao;
  const metas = getMetasDoColaboradorNoCiclo(colaboradorAtual.matricula, cicloAtual.id);

  const negocio = metas.filter((meta) => meta.tipo === "NEGOCIO_PROJETO");
  const individuais = metas.filter((meta) => meta.tipo === "INDIVIDUAL");
  const aprovadas = metas.filter((meta) =>
    metaEstaAprovada(meta, colaboradorAtual, colaboradores)
  ).length;
  const progressoMedio = metas.length
    ? Math.round(
        metas.reduce(
          (soma, meta) => soma + (meta.progressoPercentual ?? 0),
          0
        ) / metas.length
      )
    : 0;

  const pendentesDoPerfil =
    cicloAtual.status === "CANCELADO"
      ? 0
      : metas.filter((meta) => {
          if (!podeAcessar) {
            return false;
          }

          return podeAprovarComoGerente
            ? !meta.aprovacaoGerente
            : !meta.aprovacaoCoordenador;
        }).length;

  function aprovar(meta: Meta) {
    setErro("");

    try {
      aprovarMeta(meta.id, usuario, colaboradorAtual, cicloAtual);
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível aprovar a meta."
      );
    }
  }

  function renderMeta(meta: Meta, indice: number) {
    const exigeCoordenador = metaExigeAprovacaoCoordenador(
      colaboradorAtual,
      colaboradores,
      cicloAtual
    );
    const aprovada = metaEstaAprovada(meta, colaboradorAtual, colaboradores);
    const podeAprovarDoPerfil =
      cicloAtual.status === "ATIVO" &&
      ((podeAprovarComoGerente && !meta.aprovacaoGerente) ||
        (podeAprovarComoCoordenador && !meta.aprovacaoCoordenador));

    return (
      <article className="goals-manager-card" key={meta.id}>
        <div className="goals-manager-card__top">
          <span className="goals-manager-card__number">{indice + 1}</span>
          <div>
            <span className="cycle-eyebrow">
              {meta.tipo === "NEGOCIO_PROJETO"
                ? "Negócio / Projeto"
                : "Individual"}
            </span>
            <h3>{meta.descricao}</h3>
          </div>
          <span
            className={`goals-manager-approval-status ${
              aprovada ? "is-approved" : "is-pending"
            }`}
          >
            {aprovada ? "Aprovada" : "Aguardando aprovação"}
          </span>
        </div>

        <div className="goals-manager-facts">
          <div>
            <span>KPI</span>
            <strong>{meta.kpi}</strong>
          </div>
          <div>
            <span>Valor-alvo</span>
            <strong>{meta.valorAlvo}</strong>
          </div>
          <div>
            <span>Progresso</span>
            <strong>{meta.progressoPercentual ?? 0}%</strong>
          </div>
        </div>

        <div className="goals-manager-progress">
          <div style={{ width: `${meta.progressoPercentual ?? 0}%` }} />
        </div>

        <div className="goals-manager-result">
          <span>Resultado atual</span>
          <strong>
            {meta.resultadoAtual?.trim() || "Ainda não informado"}
          </strong>
          <small>
            Última atualização:{" "}
            {formatarDataHora(meta.dataUltimoAcompanhamento)}
          </small>
        </div>

        {meta.resultadoFinal && (
          <div
            className={`goals-manager-final ${
              meta.status === "ATINGIDA" ? "is-success" : "is-danger"
            }`}
          >
            <span>Resultado final</span>
            <strong>{meta.resultadoFinal}</strong>
          </div>
        )}

        <div className="goals-manager-approvals">
          {exigeCoordenador && (
            <label
              className={
                meta.aprovacaoCoordenador ? "is-approved" : ""
              }
            >
              <input
                type="checkbox"
                checked={Boolean(meta.aprovacaoCoordenador)}
                disabled={
                  Boolean(meta.aprovacaoCoordenador) ||
                  !podeAprovarComoCoordenador ||
                  cicloAtual.status !== "ATIVO"
                }
                onChange={() => aprovar(meta)}
              />
              <span>
                <strong>Aprovação do coordenador direto</strong>
                <small>
                  {meta.aprovacaoCoordenador
                    ? `${meta.aprovacaoCoordenador.nome} · ${formatarDataHora(
                        meta.aprovacaoCoordenador.data
                      )}`
                    : podeAprovarComoCoordenador && podeAprovarDoPerfil
                    ? "Marque para aprovar esta meta."
                    : "Aguardando aprovação."}
                </small>
              </span>
            </label>
          )}

          <label
            className={meta.aprovacaoGerente ? "is-approved" : ""}
          >
            <input
              type="checkbox"
              checked={Boolean(meta.aprovacaoGerente)}
              disabled={
                Boolean(meta.aprovacaoGerente) ||
                !podeAprovarComoGerente ||
                cicloAtual.status !== "ATIVO"
              }
              onChange={() => aprovar(meta)}
            />
            <span>
              <strong>Aprovação do gerente</strong>
              <small>
                {meta.aprovacaoGerente
                  ? `${meta.aprovacaoGerente.nome} · ${formatarDataHora(
                      meta.aprovacaoGerente.data
                    )}`
                  : podeAprovarComoGerente && podeAprovarDoPerfil
                  ? "Marque para aprovar esta meta."
                  : "Aguardando aprovação."}
              </small>
            </span>
          </label>
        </div>

        {!aprovada && cicloAtual.status === "ENCERRADO" && (
          <div className="goals-manager-warning">
            O ciclo foi encerrado com esta meta sem todas as aprovações
            formais.
          </div>
        )}
      </article>
    );
  }

  function renderGrupo(
    titulo: string,
    descricao: string,
    metasGrupo: Meta[]
  ) {
    return (
      <section className="goals-manager-section">
        <header className="goals-manager-section__header">
          <div>
            <span className="cycle-eyebrow">Metas</span>
            <h2>{titulo}</h2>
            <p>{descricao}</p>
          </div>
          <strong>{metasGrupo.length}</strong>
        </header>

        {metasGrupo.length ? (
          <div className="goals-manager-list">
            {metasGrupo.map((meta, indice) => renderMeta(meta, indice))}
          </div>
        ) : (
          <div className="goals-manager-empty">
            Nenhuma meta cadastrada neste bloco.
          </div>
        )}
      </section>
    );
  }

  return (
    <main className="virtus-page goals-manager-page">
      <section className="virtus-page-header goals-manager-page__header goals-manager-page__header--standard">
        <div className="virtus-page-header__copy">
          <h1>Acompanhamento de Metas</h1>
          <p>
            {cicloAtual.ano} • Ciclo {cicloAtual.ciclo} ·{" "}
            {formatarPeriodoCiclo(cicloAtual.dataInicio, cicloAtual.dataFim)}
          </p>
        </div>

        <div className="virtus-page-actions goals-manager-page__actions">
          <span
            className={`cycle-status ${
              cicloAtual.status === "ATIVO" ? "is-active" : "is-closed"
            }`}
          >
            {cicloAtual.status === "ATIVO"
              ? "Ciclo ativo"
              : cicloAtual.status === "CANCELADO"
              ? "Ciclo cancelado"
              : "Ciclo encerrado"}
          </span>

          <button
            type="button"
            className="virtus-btn virtus-btn--outline"
            onClick={() => navigate(`/ciclos/${cicloAtual.id}`)}
          >
            ← Voltar ao ciclo
          </button>
        </div>
      </section>

      <section className="goals-manager-identity">
        <CollaboratorIdentity
          colaborador={colaboradorEfetivo}
          variant="standard"
        />
        {colaboradorEfetivo.gestorDiretoMatricula && (
          <p className="goals-manager-effective-context goals-manager-effective-context--identity">
            Estrutura considerada conforme a vigência registrada no ciclo.
          </p>
        )}
      </section>

      <section className="goals-manager-summary">
        <article>
          <span>Total de metas</span>
          <strong>{metas.length}</strong>
        </article>
        <article>
          <span>Minhas aprovações pendentes</span>
          <strong>{pendentesDoPerfil}</strong>
        </article>
        <article>
          <span>Aprovadas por todos</span>
          <strong>{aprovadas}</strong>
        </article>
        <article>
          <span>Progresso médio</span>
          <strong>{progressoMedio}%</strong>
        </article>
      </section>

      {erro && <div className="goals-manager-error">{erro}</div>}

      {metas.length === 0 ? (
        <div className="goals-manager-empty goals-manager-empty--page">
          Nenhuma meta cadastrada para este colaborador neste ciclo.
        </div>
      ) : (
        <div className="goals-manager-sections">
          {renderGrupo(
            "Negócio / Projetos",
            "Metas relacionadas às entregas, resultados e prioridades do negócio.",
            negocio
          )}
          {renderGrupo(
            "Individuais",
            "Metas de desenvolvimento e evolução individual.",
            individuais
          )}
        </div>
      )}
    </main>
  );
}

export default AcompanhamentoMetasPage;
