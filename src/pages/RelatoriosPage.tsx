import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { criarControladorCiclosSoberanos, type CicloSoberano } from "../services/acessoCiclosSoberanos";
import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";
import { criarRepositorioRelatoriosSoberanos, type LinhaRelatorioSoberano } from "../infrastructure/supabase/relatorios/repositorioRelatoriosSoberanos";
import "../styles/relatorios.css";

function rotuloCiclo(ciclo: CicloSoberano): string { return `${ciclo.ano} • Ciclo ${ciclo.numero}`; }
function periodo(ciclo: CicloSoberano | undefined): string {
  if (!ciclo?.dataInicio && !ciclo?.dataFim) return "Período não informado";
  return `${ciclo.dataInicio ?? "—"} a ${ciclo.dataFim ?? "—"}`;
}
function formatarNota(valor: number | null): string { return valor === null ? "—" : valor.toFixed(2); }
function faixaDaNota(valor: number | null): string { return valor === null ? "SEM_NOTA" : String(Math.round(valor)); }

type Fase = "carregando" | "pronta" | "indisponivel";

function RelatoriosPage() {
  const navigate = useNavigate();
  const { organizacaoAtivaId } = useAuth();
  const { usuarioAtual, estadoResolucaoIdentidade } = useUsuarioAtual();
  const [ciclos, setCiclos] = useState<readonly CicloSoberano[]>([]);
  const [cicloId, setCicloId] = useState("");
  const [linhas, setLinhas] = useState<readonly LinhaRelatorioSoberano[]>([]);
  const [fase, setFase] = useState<Fase>("carregando");
  const [mensagem, setMensagem] = useState<string | null>(null);
  const [filtroStatus, setFiltroStatus] = useState("");
  const [filtroFaixa, setFiltroFaixa] = useState("");

  useEffect(() => {
    if (!organizacaoAtivaId) return;
    let ativo = true;
    const controlador = criarControladorCiclosSoberanos();
    void controlador.carregar(organizacaoAtivaId).then((resultado) => {
      if (!ativo) return;
      if (!resultado.ok) { setFase("indisponivel"); setMensagem(resultado.error.message); return; }
      setCiclos(resultado.data);
      const inicial = resultado.data.find((ciclo) => ciclo.status === "ATIVO")?.id ?? resultado.data[0]?.id ?? "";
      setCicloId(inicial);
      if (!inicial) { setFase("pronta"); setMensagem(null); }
    });
    return () => { ativo = false; controlador.descartar(); };
  }, [organizacaoAtivaId]);

  useEffect(() => {
    if (!organizacaoAtivaId || !cicloId) return;
    let ativo = true;
    const cliente = criarClienteSupabase();
    if (!cliente) {
      void Promise.resolve().then(() => {
        if (ativo) { setFase("indisponivel"); setMensagem("Leitura soberana de relatórios indisponível neste ambiente."); }
      });
      return;
    }
    void criarRepositorioRelatoriosSoberanos(cliente).listar(organizacaoAtivaId, cicloId).then((resultado) => {
      if (!ativo) return;
      if (!resultado.ok) { setFase("indisponivel"); setMensagem(resultado.message); return; }
      setLinhas(resultado.data.colaboradores); setFase("pronta"); setMensagem(null);
    });
    return () => { ativo = false; };
  }, [organizacaoAtivaId, cicloId]);

  const ciclo = ciclos.find((item) => item.id === cicloId);
  const linhasFiltradas = useMemo(() => linhas.filter((linha) => {
    if (filtroStatus && (linha.evaluationStatus ?? "SEM_AVALIACAO") !== filtroStatus) return false;
    if (filtroFaixa && faixaDaNota(linha.notaMedia) !== filtroFaixa) return false;
    return true;
  }), [filtroFaixa, filtroStatus, linhas]);
  const comNota = linhasFiltradas.filter((linha) => linha.notaMedia !== null);
  const media = comNota.length ? comNota.reduce((total, linha) => total + (linha.notaMedia ?? 0), 0) / comNota.length : null;
  const concluidas = linhasFiltradas.filter((linha) => linha.evaluationStatus === "CONCLUIDA").length;
  const emAndamento = linhasFiltradas.filter((linha) => linha.evaluationStatus === "EM_ANDAMENTO").length;
  const faixas = [1, 2, 3, 4, 5].map((nota) => ({ nota, quantidade: comNota.filter((linha) => faixaDaNota(linha.notaMedia) === String(nota)).length }));

  if (estadoResolucaoIdentidade === "carregando") return <main className="virtus-page reports-page"><section className="reports-empty"><h1>Carregando identidade…</h1></section></main>;
  if (!organizacaoAtivaId || !usuarioAtual || estadoResolucaoIdentidade === "resolvida-sem-usuario") return <main className="virtus-page reports-page"><section className="reports-empty"><h1>Acesso restrito</h1><p>O relatório exige uma identidade autenticada e organização ativa.</p></section></main>;

  return <main className="virtus-page reports-page">
    <section className="reports-page-header">
      <div><h1>Relatórios</h1><p>Visão consolidada de desempenho da equipe autorizada.</p></div>
      <label className="reports-cycle-filter"><span>Ciclo</span><select value={cicloId} onChange={(evento) => { setFase("carregando"); setCicloId(evento.target.value); }}>{ciclos.map((item) => <option key={item.id} value={item.id}>{rotuloCiclo(item)}{item.status === "ATIVO" ? " — Ativo" : ""}</option>)}</select></label>
    </section>
    {ciclo && <section className="reports-cycle-context"><div><strong>{rotuloCiclo(ciclo)}</strong><span>{periodo(ciclo)}</span></div><span className={`reports-cycle-status ${ciclo.status === "ATIVO" ? "is-active" : "is-closed"}`}>{ciclo.status === "ATIVO" ? "Ativo" : ciclo.status}</span></section>}
    {ciclos.length === 0 && fase === "pronta" && <section className="reports-empty"><h2>Nenhum ciclo disponível</h2><p>Não há ciclo soberano disponível para esta organização.</p></section>}
    {fase === "carregando" && <section className="reports-empty"><h2>Carregando relatório…</h2><p>Consultando o universo autorizado no servidor.</p></section>}
    {fase === "indisponivel" && <section className="reports-empty"><h2>Relatório indisponível</h2><p>{mensagem}</p></section>}
    {fase === "pronta" && cicloId && <>
      <section className="reports-filters" aria-label="Filtros do relatório"><div className="reports-filters__heading"><div><strong>Filtros</strong><span>Aplicados somente sobre a resposta autorizada</span></div></div><div className="reports-filters__grid"><label className="reports-filter-control"><span>Status</span><select value={filtroStatus} onChange={(evento) => setFiltroStatus(evento.target.value)}><option value="">Todos</option><option value="SEM_AVALIACAO">Sem avaliação</option><option value="CONCLUIDA">Concluída</option><option value="EM_ANDAMENTO">Em andamento</option></select></label><label className="reports-filter-control"><span>Faixa de nota</span><select value={filtroFaixa} onChange={(evento) => setFiltroFaixa(evento.target.value)}><option value="">Todas</option>{[1, 2, 3, 4, 5].map((nota) => <option key={nota} value={nota}>{nota}</option>)}</select></label><div className="reports-filter-control"><span>Outros filtros</span><strong>Indisponíveis nesta visão soberana</strong></div></div></section>
      <section className="reports-kpis" aria-label="Indicadores gerais"><article className="reports-kpi reports-kpi--featured"><span>Média da equipe</span><strong>{formatarNota(media)}</strong><small>{comNota.length ? `${comNota.length} com nota` : "Sem nota consolidada"}</small></article><article className="reports-kpi"><span>Colaboradores</span><strong>{linhasFiltradas.length}</strong><small>no escopo autorizado</small></article><article className="reports-kpi"><span>Com nota consolidada</span><strong>{comNota.length}</strong><small>avaliações com nota</small></article><article className="reports-kpi"><span>Concluídas</span><strong>{concluidas}</strong><small>no ciclo selecionado</small></article><article className="reports-kpi"><span>Em andamento</span><strong>{emAndamento}</strong><small>no ciclo selecionado</small></article></section>
      <div className="reports-grid"><section className="reports-card"><div className="reports-card__heading"><div><h2>Distribuição das notas</h2><p>Derivada somente das notas retornadas pelo servidor.</p></div></div><div className="reports-distribution">{faixas.map((faixa) => <div className="reports-distribution__row" key={faixa.nota}><div className="reports-distribution__label"><span className="reports-score-dot">{faixa.nota}</span><div><strong>Nota {faixa.nota}</strong><small>{faixa.quantidade} colaborador{faixa.quantidade === 1 ? "" : "es"}</small></div></div><strong className="reports-distribution__percent">{comNota.length ? `${Math.round((faixa.quantidade / comNota.length) * 100)}%` : "—"}</strong></div>)}</div></section><section className="reports-card"><div className="reports-card__heading"><div><h2>Média por critério</h2><p>Indisponível: o contrato atual não retorna critérios.</p></div></div><div className="reports-evolution-empty">Detalhamento por critério indisponível nesta etapa.</div></section></div>
      <section className="reports-card reports-team-card"><div className="reports-card__heading reports-team-heading"><div><h2>Desempenho da equipe</h2><p>Colaboradores e avaliações retornados pelo escopo soberano.</p></div><span>{linhasFiltradas.length} colaboradores</span></div><div className="reports-table-wrap"><div className="reports-table"><div className="reports-table__row reports-table__row--header"><div>Colaborador</div><div>Status</div><div>Nota</div><div>Data de conclusão</div><div>Ações</div></div>{linhasFiltradas.map((linha) => <div className="reports-table__row" key={linha.collaboratorId}><div className="reports-person"><div className="reports-avatar">{linha.nome.split(" ").filter(Boolean).slice(0, 2).map((parte) => parte[0]).join("").toUpperCase()}</div><div><strong>{linha.nome}</strong><span>{linha.status ?? "Status não informado"}</span></div></div><div data-label="Status"><span className="reports-status">{linha.evaluationStatus ?? "Sem avaliação"}</span></div><div data-label="Nota"><strong className="reports-table-score">{formatarNota(linha.notaMedia)}</strong></div><div data-label="Data de conclusão">{linha.dataConclusao ?? "—"}</div><div className="reports-actions"><button type="button" className="virtus-btn virtus-btn--outline virtus-btn--small" onClick={() => navigate(`/colaborador/${linha.collaboratorId}`)}>Abrir colaborador</button></div></div>)}</div></div></section>
      <div className="reports-grid"><section className="reports-card"><div className="reports-card__heading"><div><h2>Evolução entre ciclos</h2><p>Indisponível: esta etapa não possui histórico consolidado.</p></div></div><div className="reports-evolution-empty">A evolução será disponibilizada quando houver contrato soberano histórico.</div></section><section className="reports-card"><div className="reports-card__heading"><div><h2>Histórico de ciclos</h2><p>Indisponível nesta visão soberana.</p></div></div><div className="reports-evolution-empty">O histórico avançado não é calculado a partir de dados legados.</div></section></div>
    </>}
    <aside aria-label="Funcionalidades indisponíveis">Filtros por cargo, senioridade e coordenador; evolução individual; detalhamento por critério; históricos avançados e exportação permanecem indisponíveis nesta etapa.</aside>
  </main>;
}

export default RelatoriosPage;
