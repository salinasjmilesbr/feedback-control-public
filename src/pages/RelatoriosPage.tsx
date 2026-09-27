import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { criarControladorCiclosSoberanos, type CicloSoberano } from "../services/acessoCiclosSoberanos";
import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";
import { criarRepositorioRelatoriosSoberanos, type LinhaRelatorioSoberano } from "../infrastructure/supabase/relatorios/repositorioRelatoriosSoberanos";
import "../styles/relatorios.css";

function rotuloCiclo(ciclo: CicloSoberano): string { return `Ciclo ${ciclo.numero}/${ciclo.ano}`; }

function RelatoriosPage() {
  const navigate = useNavigate();
  const { organizacaoAtivaId } = useAuth();
  const { usuarioAtual, estadoResolucaoIdentidade } = useUsuarioAtual();
  const [ciclos, setCiclos] = useState<readonly CicloSoberano[]>([]);
  const [cicloId, setCicloId] = useState("");
  const [linhas, setLinhas] = useState<readonly LinhaRelatorioSoberano[]>([]);
  const [fase, setFase] = useState<"carregando" | "pronta" | "indisponivel">("carregando");
  const [mensagem, setMensagem] = useState<string | null>(null);
  const [filtroStatus, setFiltroStatus] = useState("");

  useEffect(() => {
    if (!organizacaoAtivaId) return;
    let ativo = true;
    const controlador = criarControladorCiclosSoberanos();
    void controlador.carregar(organizacaoAtivaId).then((resultado) => {
      if (!ativo) return;
      if (!resultado.ok) { setFase("indisponivel"); setMensagem(resultado.error.message); return; }
      setCiclos(resultado.data);
      const cicloInicial = resultado.data.find((ciclo) => ciclo.status === "ATIVO")?.id ?? resultado.data[0]?.id ?? "";
      setCicloId(cicloInicial);
      if (!cicloInicial) { setFase("pronta"); setMensagem(null); }
    });
    return () => { ativo = false; controlador.descartar(); };
  }, [organizacaoAtivaId]);

  useEffect(() => {
    if (!organizacaoAtivaId || !cicloId) return;
    let ativo = true;
    setFase("carregando");
    const cliente = criarClienteSupabase();
    if (!cliente) { setFase("indisponivel"); setMensagem("Leitura soberana de relatórios indisponível neste ambiente."); return; }
    void criarRepositorioRelatoriosSoberanos(cliente).listar(organizacaoAtivaId, cicloId).then((resultado) => {
      if (!ativo) return;
      if (!resultado.ok) { setFase("indisponivel"); setMensagem(resultado.message); return; }
      setLinhas(resultado.data.colaboradores); setFase("pronta"); setMensagem(null);
    });
    return () => { ativo = false; };
  }, [organizacaoAtivaId, cicloId]);

  const linhasVisiveis = useMemo(() => filtroStatus ? linhas.filter((linha) => (linha.evaluationStatus ?? "SEM_AVALIACAO") === filtroStatus) : linhas, [filtroStatus, linhas]);
  const cicloSelecionado = ciclos.find((ciclo) => ciclo.id === cicloId);

  if (estadoResolucaoIdentidade === "carregando") return <main className="relatorios-page"><p>Carregando identidade...</p></main>;
  if (!organizacaoAtivaId || !usuarioAtual || estadoResolucaoIdentidade === "resolvida-sem-usuario") return <main className="relatorios-page"><h1>Relatórios</h1><p>Acesso restrito.</p></main>;

  return <main className="relatorios-page">
    <header><h1>Relatórios</h1><p>Visão soberana da equipe autorizada para o ciclo selecionado.</p></header>
    <section aria-label="Filtros do relatório">
      <label htmlFor="relatorio-ciclo">Ciclo</label>
      <select id="relatorio-ciclo" value={cicloId} onChange={(evento) => setCicloId(evento.target.value)}>{ciclos.map((ciclo) => <option key={ciclo.id} value={ciclo.id}>{rotuloCiclo(ciclo)}</option>)}</select>
      <label htmlFor="relatorio-status">Situação da avaliação</label>
      <select id="relatorio-status" value={filtroStatus} onChange={(evento) => setFiltroStatus(evento.target.value)}><option value="">Todas</option><option value="SEM_AVALIACAO">Sem avaliação</option><option value="CONCLUIDA">Concluída</option><option value="EM_ANDAMENTO">Em andamento</option></select>
    </section>
    {fase === "carregando" && <p role="status">Carregando relatório...</p>}
    {fase === "indisponivel" && <p role="alert">{mensagem ?? "Relatório indisponível."}</p>}
    {fase === "pronta" && <>
      <section aria-label="Resumo do relatório"><p>Escopo: DESCENDANTS</p><p>Ciclo: {cicloSelecionado ? rotuloCiclo(cicloSelecionado) : cicloId}</p><p>Colaboradores autorizados: {linhas.length}</p></section>
      {!cicloId ? <p>Nenhum ciclo disponível para consulta.</p> : linhasVisiveis.length === 0 ? <p>Nenhum colaborador autorizado neste ciclo.</p> : <ul aria-label="Colaboradores do relatório">{linhasVisiveis.map((linha) => <li key={linha.collaboratorId}><button type="button" onClick={() => navigate(`/colaborador/${linha.collaboratorId}`)}>{linha.nome}</button><span>{linha.evaluationStatus ?? "Sem avaliação"}</span><span>{linha.notaMedia === null ? "Nota não disponível" : `Nota média: ${linha.notaMedia}`}</span></li>)}</ul>}
    </>}
    <aside aria-label="Funcionalidades indisponíveis">Históricos avançados, detalhamento por critério e exportação não estão disponíveis nesta visão soberana.</aside>
  </main>;
}

export default RelatoriosPage;
