import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { getCicloAtivo } from "../services/cicloAvaliacaoStorage";
import {
  atualizarAcompanhamentoMeta,
  atualizarMeta,
  criarMeta,
  excluirMeta,
  finalizarMeta,
  getMetasDoColaboradorNoCiclo,
  metaEstaAprovada,
  metaExigeAprovacaoCoordenador,
} from "../services/metaStorage";
import { getColaboradores } from "../services/colaboradorStorage";
import type { Meta, TipoMeta } from "../types/Meta";
import "../styles/ciclos.css";
import "../styles/minhas-metas.css";

function MinhasMetasPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();

  const [versao, setVersao] = useState(0);
  const [tipo, setTipo] = useState<TipoMeta>("NEGOCIO_PROJETO");
  const [descricao, setDescricao] = useState("");
  const [kpi, setKpi] = useState("");
  const [valorAlvo, setValorAlvo] = useState("");
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [acompanhandoId, setAcompanhandoId] = useState<string | null>(null);
  const [resultadoAtual, setResultadoAtual] = useState("");
  const [progressoPercentual, setProgressoPercentual] = useState(0);
  const [fechandoId, setFechandoId] = useState<string | null>(null);
  const [resultadoFinal, setResultadoFinal] = useState("");
  const [atingida, setAtingida] = useState<boolean | null>(null);
  const [erro, setErro] = useState("");

  void versao;

  if (!usuarioAtual) {
    return (
      <main className="virtus-page">
        <section className="goals-empty">
          <h1>Usuário atual não definido</h1>
          <p>Selecione um usuário para acessar suas metas.</p>
        </section>
      </main>
    );
  }

  if (usuarioAtual.funcao === "GERENTE") {
    return (
      <main className="virtus-page">
        <section className="goals-empty">
          <h1>Minhas Metas</h1>
          <p>O cadastro de metas próprias ainda não está habilitado para o perfil de Gerente.</p>
          <button type="button" className="cycle-btn cycle-btn--secondary" onClick={() => navigate("/")}>
            Voltar ao início
          </button>
        </section>
      </main>
    );
  }

  const usuario = usuarioAtual;
  const cicloEncontrado = getCicloAtivo();

  if (!cicloEncontrado) {
    return (
      <main className="virtus-page">
        <section className="cycle-page-header goals-page-header">
          <div>
            <h1>Minhas Metas</h1>
            <p>Acompanhe seus objetivos de negócio e desenvolvimento individual.</p>
          </div>
          <button type="button" className="cycle-btn cycle-btn--secondary" onClick={() => navigate(-1)}>
            ← Voltar
          </button>
        </section>
        <section className="goals-empty">
          <h2>Nenhum ciclo ativo</h2>
          <p>Não existe um ciclo ativo para cadastro ou acompanhamento de metas.</p>
        </section>
      </main>
    );
  }

  const cicloAtivo = cicloEncontrado;
  const colaboradores = getColaboradores();
  const metas = getMetasDoColaboradorNoCiclo(usuario.matricula, cicloAtivo.id);
  const metasNegocio = metas.filter((meta) => meta.tipo === "NEGOCIO_PROJETO");
  const metasIndividuais = metas.filter((meta) => meta.tipo === "INDIVIDUAL");

  const limiteNegocio = cicloAtivo.quantidadeMetasNegocio ?? 0;
  const limiteIndividuais = cicloAtivo.quantidadeMetasIndividuais ?? 0;
  const limiteAtual = tipo === "NEGOCIO_PROJETO" ? limiteNegocio : limiteIndividuais;
  const quantidadeAtual = tipo === "NEGOCIO_PROJETO" ? metasNegocio.length : metasIndividuais.length;
  const podeAdicionar = editandoId !== null || quantidadeAtual < limiteAtual;

  const totalConfigurado = limiteNegocio + limiteIndividuais;
  const totalCadastrado = metas.length;
  const emAndamento = metas.filter((meta) => meta.status === "EM_ANDAMENTO").length;
  const aprovadas = metas.filter((meta) => metaEstaAprovada(meta, usuario, colaboradores)).length;

  function limparFormulario() {
    setDescricao("");
    setKpi("");
    setValorAlvo("");
    setEditandoId(null);
    setErro("");
  }

  function limparAcompanhamento() {
    setAcompanhandoId(null);
    setResultadoAtual("");
    setProgressoPercentual(0);
    setErro("");
  }

  function iniciarAcompanhamento(meta: Meta) {
    setAcompanhandoId(meta.id);
    setResultadoAtual(meta.resultadoAtual ?? "");
    setProgressoPercentual(meta.progressoPercentual ?? 0);
    setErro("");
  }

  function salvarAcompanhamento() {
    if (!acompanhandoId) return;
    setErro("");

    try {
      atualizarAcompanhamentoMeta(
        acompanhandoId,
        usuario,
        cicloAtivo,
        resultadoAtual,
        progressoPercentual
      );
      limparAcompanhamento();
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível atualizar o andamento da meta."
      );
    }
  }

  function limparFechamento() {
    setFechandoId(null);
    setResultadoFinal("");
    setAtingida(null);
    setErro("");
  }

  function iniciarFechamento(meta: Meta) {
    limparFormulario();
    limparAcompanhamento();
    setFechandoId(meta.id);
    setResultadoFinal(meta.resultadoFinal ?? "");
    setAtingida(typeof meta.atingida === "boolean" ? meta.atingida : null);
    setErro("");
  }

  function salvarFechamento() {
    if (!fechandoId) return;

    if (atingida === null) {
      setErro("Informe se a meta foi atingida ou não.");
      return;
    }

    setErro("");

    try {
      finalizarMeta(
        fechandoId,
        usuario,
        cicloAtivo,
        resultadoFinal,
        atingida
      );
      limparFechamento();
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível finalizar a meta."
      );
    }
  }

  function formatarDataHora(data?: string) {
    if (!data) return "Ainda não atualizado";
    return new Date(data).toLocaleString("pt-BR", {
      dateStyle: "short",
      timeStyle: "short",
    });
  }

  function salvar() {
    setErro("");

    try {
      if (editandoId) {
        atualizarMeta(
          editandoId,
          usuario,
          cicloAtivo,
          descricao,
          kpi,
          valorAlvo
        );
      } else {
        criarMeta(
          usuario,
          cicloAtivo,
          tipo,
          descricao,
          kpi,
          valorAlvo
        );
      }

      limparFormulario();
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível salvar a meta."
      );
    }
  }

  function editar(meta: Meta) {
    limparAcompanhamento();
    limparFechamento();
    setTipo(meta.tipo);
    setDescricao(meta.descricao);
    setKpi(meta.kpi);
    setValorAlvo(meta.valorAlvo);
    setEditandoId(meta.id);
    setErro("");
  }

  function excluir(meta: Meta) {
    const confirmar = window.confirm(
      "Deseja excluir esta meta? O registro será mantido no histórico."
    );
    if (!confirmar) return;

    try {
      excluirMeta(meta.id, usuario, cicloAtivo);
      if (editandoId === meta.id) limparFormulario();
      if (acompanhandoId === meta.id) limparAcompanhamento();
      if (fechandoId === meta.id) limparFechamento();
      setVersao((valor) => valor + 1);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível excluir a meta."
      );
    }
  }

  function statusLabel(meta: Meta) {
    if (meta.status === "ATINGIDA") return "Atingida";
    if (meta.status === "NAO_ATINGIDA") return "Não atingida";
    return "Em andamento";
  }

  function statusClass(meta: Meta) {
    if (meta.status === "ATINGIDA") return "is-success";
    if (meta.status === "NAO_ATINGIDA") return "is-danger";
    return "is-progress";
  }

  function renderEditorAcompanhamento(meta: Meta) {
    if (acompanhandoId !== meta.id || fechandoId) return null;

    return (
      <div className="goal-inline-editor">
        <div className="goal-inline-editor__header">
          <div>
            <span className="cycle-eyebrow">Acompanhamento</span>
            <h4>Atualizar andamento</h4>
            <p>Atualize o resultado parcial e o percentual de progresso desta meta.</p>
          </div>
        </div>

        <label className="goals-field">
          <span>Resultado atual</span>
          <textarea
            value={resultadoAtual}
            onChange={(event) => setResultadoAtual(event.target.value)}
            placeholder="Ex.: O tempo médio atual caiu para 5,1 horas."
          />
        </label>

        <label className="goals-field">
          <div className="goals-field__row">
            <span>Progresso</span>
            <strong>{progressoPercentual}%</strong>
          </div>
          <input
            type="range"
            min={0}
            max={100}
            step={5}
            value={progressoPercentual}
            onChange={(event) => setProgressoPercentual(Number(event.target.value))}
          />
        </label>

        <label className="goals-progress-number">
          <input
            type="number"
            min={0}
            max={100}
            value={progressoPercentual}
            onChange={(event) => {
              const valor = Number(event.target.value);
              setProgressoPercentual(Math.min(100, Math.max(0, valor)));
            }}
          />
          <span>%</span>
        </label>

        {erro && <div className="goals-error">{erro}</div>}

        <div className="goals-editor__actions">
          <button type="button" className="cycle-btn cycle-btn--secondary" onClick={limparAcompanhamento}>Cancelar</button>
          <button type="button" className="cycle-btn cycle-btn--primary" onClick={salvarAcompanhamento}>Salvar andamento</button>
        </div>
      </div>
    );
  }

  function renderEditorFechamento(meta: Meta) {
    if (fechandoId !== meta.id) return null;

    return (
      <div className="goal-inline-editor">
        <div className="goal-inline-editor__header">
          <div>
            <span className="cycle-eyebrow">Conclusão</span>
            <h4>{meta.status === "EM_ANDAMENTO" ? "Fechar meta" : "Revisar fechamento"}</h4>
            <p>Registre o resultado alcançado e indique se a meta foi atingida.</p>
          </div>
        </div>

        <label className="goals-field">
          <span>Resultado final</span>
          <textarea
            value={resultadoFinal}
            onChange={(event) => setResultadoFinal(event.target.value)}
            placeholder="Descreva o resultado obtido de acordo com o KPI e o valor-alvo."
          />
        </label>

        <fieldset className="goals-radio-group">
          <legend>Meta atingida?</legend>
          <label><input type="radio" checked={atingida === true} onChange={() => setAtingida(true)} /> Sim</label>
          <label><input type="radio" checked={atingida === false} onChange={() => setAtingida(false)} /> Não</label>
        </fieldset>

        {erro && <div className="goals-error">{erro}</div>}

        <div className="goals-editor__actions">
          <button type="button" className="cycle-btn cycle-btn--secondary" onClick={limparFechamento}>Cancelar</button>
          <button type="button" className="cycle-btn cycle-btn--primary" onClick={salvarFechamento}>Salvar fechamento</button>
        </div>
      </div>
    );
  }

  function renderEditorMeta(meta: Meta) {
    if (editandoId !== meta.id || acompanhandoId || fechandoId) return null;

    return (
      <div className="goal-inline-editor">
        <div className="goal-inline-editor__header">
          <div>
            <span className="cycle-eyebrow">Edição</span>
            <h4>Editar meta</h4>
            <p>Atualize a descrição, o KPI mensurável ou o valor-alvo desta meta.</p>
          </div>
        </div>

        <label className="goals-field">
          <span>Descrição da meta</span>
          <textarea
            value={descricao}
            onChange={(event) => setDescricao(event.target.value)}
            placeholder="Ex.: Reduzir o tempo médio de publicação"
          />
        </label>

        <div className="goals-editor__grid">
          <label className="goals-field">
            <span>KPI mensurável</span>
            <input
              value={kpi}
              onChange={(event) => setKpi(event.target.value)}
              placeholder="Ex.: Tempo médio entre aprovação e publicação"
            />
          </label>

          <label className="goals-field">
            <span>Valor-alvo</span>
            <input
              value={valorAlvo}
              onChange={(event) => setValorAlvo(event.target.value)}
              placeholder="Ex.: ≤ 4 horas, 95%, R$ 1 milhão"
            />
          </label>
        </div>

        {erro && <div className="goals-error">{erro}</div>}

        <div className="goals-editor__actions">
          <button type="button" className="cycle-btn cycle-btn--secondary" onClick={limparFormulario}>Cancelar</button>
          <button type="button" className="cycle-btn cycle-btn--primary" onClick={salvar}>Salvar alterações</button>
        </div>
      </div>
    );
  }

  function renderGrupo(
    titulo: string,
    descricaoGrupo: string,
    tipoGrupo: TipoMeta,
    itens: Meta[],
    limite: number
  ) {
    return (
      <section className="goals-group">
        <div className="goals-group__header">
          <div>
            <span className="cycle-eyebrow">
              {tipoGrupo === "NEGOCIO_PROJETO" ? "Performance" : "Desenvolvimento"}
            </span>
            <h2>{titulo}</h2>
            <p>{descricaoGrupo}</p>
          </div>
          <span className="goals-count">{itens.length} de {limite}</span>
        </div>

        {limite === 0 ? (
          <div className="goals-group__empty">Esta categoria não foi habilitada para este ciclo.</div>
        ) : itens.length === 0 ? (
          <div className="goals-group__empty">Nenhuma meta cadastrada nesta categoria.</div>
        ) : (
          <div className="goals-list">
            {itens.map((meta, indice) => (
              <article className="goal-card" key={meta.id}>
                <div className="goal-card__top">
                  <div className="goal-card__identity">
                    <span className="goal-card__index">{indice + 1}</span>
                    <div>
                      <h3>{meta.descricao}</h3>
                      <span className={`goal-status ${statusClass(meta)}`}>{statusLabel(meta)}</span>
                    </div>
                  </div>

                  <div className="goal-card__actions">
                    {meta.status === "EM_ANDAMENTO" && (
                      <button
                        type="button"
                        className="goal-action-btn goal-action-btn--primary"
                        onClick={() => {
                          limparFormulario();
                          limparFechamento();
                          iniciarAcompanhamento(meta);
                        }}
                      >
                        Atualizar andamento
                      </button>
                    )}
                    <button
                      type="button"
                      className="goal-action-btn goal-action-btn--success"
                      onClick={() => iniciarFechamento(meta)}
                    >
                      {meta.status === "EM_ANDAMENTO" ? "Fechar meta" : "Revisar fechamento"}
                    </button>
                    <button type="button" className="goal-action-btn" onClick={() => editar(meta)}>Editar</button>
                    <button type="button" className="goal-action-btn goal-action-btn--danger" onClick={() => excluir(meta)}>Excluir</button>
                  </div>
                </div>

                <div className="goal-card__facts">
                  <div>
                    <span>KPI</span>
                    <strong>{meta.kpi}</strong>
                  </div>
                  <div>
                    <span>Valor-alvo</span>
                    <strong>{meta.valorAlvo}</strong>
                  </div>
                  <div>
                    <span>Última atualização</span>
                    <strong>{formatarDataHora(meta.dataUltimoAcompanhamento)}</strong>
                  </div>
                </div>

                <div className={`goal-approval ${metaEstaAprovada(meta, usuario, colaboradores) ? "is-approved" : "is-pending"}`}>
                  <div className="goal-approval__title">
                    <strong>{metaEstaAprovada(meta, usuario, colaboradores) ? "Meta aprovada" : "Aguardando aprovação"}</strong>
                    <span>Aprovação formal</span>
                  </div>
                  <div className="goal-approval__checks">
                    {metaExigeAprovacaoCoordenador(usuario, colaboradores) && (
                      <span className={meta.aprovacaoCoordenador ? "is-ok" : ""}>
                        {meta.aprovacaoCoordenador ? "✓" : "○"} Coordenador direto
                        {meta.aprovacaoCoordenador && <small> • {formatarDataHora(meta.aprovacaoCoordenador.data)}</small>}
                      </span>
                    )}
                    <span className={meta.aprovacaoGerente ? "is-ok" : ""}>
                      {meta.aprovacaoGerente ? "✓" : "○"} Gerente
                      {meta.aprovacaoGerente && <small> • {formatarDataHora(meta.aprovacaoGerente.data)}</small>}
                    </span>
                  </div>
                </div>

                <div className="goal-progress">
                  <div className="goal-progress__label">
                    <span>Progresso</span>
                    <strong>{meta.progressoPercentual ?? 0}%</strong>
                  </div>
                  <div className="goal-progress__track">
                    <div style={{ width: `${meta.progressoPercentual ?? 0}%` }} />
                  </div>
                </div>

                <div className="goal-result">
                  <span>Resultado atual</span>
                  <strong className={!meta.resultadoAtual?.trim() ? "is-muted" : ""}>
                    {meta.resultadoAtual?.trim() ? meta.resultadoAtual : "Ainda não informado"}
                  </strong>
                </div>

                {meta.status !== "EM_ANDAMENTO" && (
                  <div className={`goal-final-result ${meta.status === "ATINGIDA" ? "is-success" : "is-danger"}`}>
                    <div>
                      <span>Resultado final</span>
                      <strong>{meta.resultadoFinal}</strong>
                    </div>
                    <small>Fechada em {formatarDataHora(meta.dataFechamento)}</small>
                  </div>
                )}

                {renderEditorAcompanhamento(meta)}
                {renderEditorFechamento(meta)}
                {renderEditorMeta(meta)}
              </article>
            ))}
          </div>
        )}

        {itens.length < limite && !editandoId && !acompanhandoId && !fechandoId && (
          <button
            type="button"
            className="goals-add-btn"
            onClick={() => {
              setTipo(tipoGrupo);
              setDescricao("");
              setKpi("");
              setValorAlvo("");
              setErro("");
            }}
          >
            + Adicionar meta
          </button>
        )}
      </section>
    );
  }

  return (
    <main className="virtus-page goals-page">
      <section className="cycle-page-header goals-page-header">
        <div>
          <h1>Minhas Metas</h1>
          <p>Acompanhe seus objetivos de negócio e desenvolvimento individual no ciclo atual.</p>
        </div>
        <button type="button" className="cycle-btn cycle-btn--secondary" onClick={() => navigate(-1)}>
          ← Voltar
        </button>
      </section>

      <section className="goals-cycle-card">
        <div>
          <span className="cycle-eyebrow">Ciclo atual</span>
          <h2>{cicloAtivo.ano} • Ciclo {cicloAtivo.ciclo}</h2>
          <p>
            Até <strong>{limiteNegocio}</strong> meta{limiteNegocio === 1 ? "" : "s"} de Negócio/Projetos e{" "}
            <strong>{limiteIndividuais}</strong> meta{limiteIndividuais === 1 ? "" : "s"} individual
            {limiteIndividuais === 1 ? "" : "is"}.
          </p>
        </div>
      </section>

      <section className="goals-kpis" aria-label="Resumo das metas">
        <article><span>Metas cadastradas</span><strong>{totalCadastrado}<small>/{totalConfigurado}</small></strong></article>
        <article><span>Aguardando aprovação</span><strong>{totalCadastrado - aprovadas}</strong></article>
        <article><span>Em andamento</span><strong>{emAndamento}</strong></article>
        <article><span>Progresso médio</span><strong>{metas.length ? Math.round(metas.reduce((s, m) => s + (m.progressoPercentual ?? 0), 0) / metas.length) : 0}<small>%</small></strong></article>
      </section>

      <div className="goals-groups">
        {renderGrupo(
          "Metas de Negócio / Projetos",
          "Resultados ligados às prioridades, entregas e indicadores do negócio.",
          "NEGOCIO_PROJETO",
          metasNegocio,
          limiteNegocio
        )}
        {renderGrupo(
          "Metas Individuais",
          "Objetivos voltados ao desenvolvimento e à evolução profissional.",
          "INDIVIDUAL",
          metasIndividuais,
          limiteIndividuais
        )}
      </div>

      {!fechandoId &&
        !acompanhandoId &&
        !editandoId &&
        podeAdicionar &&
        (limiteNegocio > 0 || limiteIndividuais > 0) && (
          <section className="goals-editor">
            <div className="goals-editor__header">
              <div>
                <span className="cycle-eyebrow">Cadastro</span>
                <h2>Nova meta</h2>
                <p>Defina a descrição, o KPI mensurável e o valor-alvo.</p>
              </div>
            </div>

            <label className="goals-field">
                <span>Categoria</span>
                <select
                  value={tipo}
                  onChange={(event) => {
                    setTipo(event.target.value as TipoMeta);
                    setErro("");
                  }}
                >
                  {limiteNegocio > 0 && (
                    <option value="NEGOCIO_PROJETO" disabled={metasNegocio.length >= limiteNegocio}>
                      Negócio / Projetos
                    </option>
                  )}
                  {limiteIndividuais > 0 && (
                    <option value="INDIVIDUAL" disabled={metasIndividuais.length >= limiteIndividuais}>
                      Desenvolvimento Individual
                    </option>
                  )}
                </select>
              </label>

            <label className="goals-field">
              <span>Descrição da meta</span>
              <textarea
                value={descricao}
                onChange={(event) => setDescricao(event.target.value)}
                placeholder="Ex.: Reduzir o tempo médio de publicação"
              />
            </label>

            <div className="goals-editor__grid">
              <label className="goals-field">
                <span>KPI mensurável</span>
                <input
                  value={kpi}
                  onChange={(event) => setKpi(event.target.value)}
                  placeholder="Ex.: Tempo médio entre aprovação e publicação"
                />
              </label>

              <label className="goals-field">
                <span>Valor-alvo</span>
                <input
                  value={valorAlvo}
                  onChange={(event) => setValorAlvo(event.target.value)}
                  placeholder="Ex.: ≤ 4 horas, 95%, R$ 1 milhão"
                />
              </label>
            </div>

            {erro && <div className="goals-error">{erro}</div>}

            <div className="goals-editor__actions">
              <button
                type="button"
                className="cycle-btn cycle-btn--primary"
                onClick={salvar}
                disabled={!podeAdicionar}
              >
                Salvar meta
              </button>
            </div>
          </section>
        )}
    </main>
  );
}

export default MinhasMetasPage;
