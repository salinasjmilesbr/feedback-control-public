import { useNavigate } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import { formatarPeriodoCiclo, getCiclosAvaliacao } from "../services/cicloAvaliacaoStorage";
import "../styles/ciclos.css";
import "../styles/painel-ciclos-coordenador.css";

function PainelCiclosCoordenadorPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const podeListarCiclos = usuarioAtual
    ? can(
        {
          actor: {
            matricula: usuarioAtual.matricula,
            funcao: usuarioAtual.funcao,
            status: usuarioAtual.status,
          },
        },
        "cycle.coordinator.list",
        { kind: "global" }
      )
    : false;

  if (!usuarioAtual || !podeListarCiclos) {
    return <main className="virtus-page"><section className="cycle-empty">
      <h1>Acesso restrito</h1><p>Esta visão está disponível apenas para coordenadores.</p>
      <button type="button" className="cycle-btn cycle-btn--secondary" onClick={() => navigate("/")}>Voltar ao início</button>
    </section></main>;
  }

  const ciclos = getCiclosAvaliacao()
    .filter(c => c.status === "ATIVO" || c.status === "ENCERRADO")
    .sort((a,b) => a.status !== b.status ? (a.status === "ATIVO" ? -1 : 1) : a.ano !== b.ano ? b.ano-a.ano : b.ciclo-a.ciclo);

  const ativos = ciclos.filter(c => c.status === "ATIVO").length;
  const encerrados = ciclos.filter(c => c.status === "ENCERRADO").length;
  const comPendencias = ciclos.filter(c => c.encerradoComPendencias).length;

  return <main className="virtus-page coordinator-cycles-page">
    <section className="cycle-page-header coordinator-cycles-header">
      <div><h1>Painel de Ciclos</h1><p>Acompanhe o ciclo ativo e consulte o histórico de avaliações da sua equipe.</p></div>
      <button type="button" className="cycle-btn cycle-btn--secondary coordinator-cycles-back" onClick={() => navigate("/")}>← Minha equipe</button>
    </section>

    <section className="coordinator-cycles-kpis" aria-label="Resumo dos ciclos">
      {[["Ciclos disponíveis",ciclos.length],["Ativos",ativos],["Encerrados",encerrados],["Com pendências",comPendencias]].map(([label,valor]) =>
        <article className="coordinator-cycle-kpi" key={String(label)}><span>{label}</span><strong>{valor}</strong></article>
      )}
    </section>

    <section className="coordinator-cycles-section">
      <div className="cycle-list-heading coordinator-cycles-heading">
        <div><span className="cycle-eyebrow">Acompanhamento</span><h2>Ciclos da equipe</h2></div>
        <span className="coordinator-cycles-count">{ciclos.length} {ciclos.length === 1 ? "ciclo" : "ciclos"}</span>
      </div>

      {ciclos.length === 0 ? <div className="cycle-empty"><h3>Nenhum ciclo disponível</h3><p>Não há ciclos ativos ou encerrados disponíveis para consulta no momento.</p></div> :
      <div className="coordinator-cycles-list">{ciclos.map(ciclo => {
        const pendencias=ciclo.quantidadePendencias ?? 0;
        const statusClass=ciclo.status==="ATIVO"?"is-active":ciclo.encerradoComPendencias?"is-warning":"is-closed";
        return <article key={ciclo.id} className={`cycle-card coordinator-cycle-card ${ciclo.status==="ATIVO"?"cycle-card--active":""}`}>
          <div className="cycle-card__main coordinator-cycle-card__main">
            <div className="cycle-card__identity">
              <div className="cycle-card__title-row"><h3>{ciclo.ano} <span>•</span> Ciclo {ciclo.ciclo}</h3>
                <span className={`cycle-status ${statusClass}`}>{ciclo.status==="ATIVO"?"Ativo":ciclo.encerradoComPendencias?"Encerrado com pendências":"Encerrado"}</span>
              </div>
              <div className="coordinator-cycle-card__details">
                <div><small>Período</small><strong>{formatarPeriodoCiclo(ciclo.dataInicio,ciclo.dataFim)}</strong></div>
                <div><small>Situação</small><strong>{ciclo.status==="ATIVO"?"Avaliações em andamento":ciclo.encerradoComPendencias?`${pendencias} nota${pendencias===1?"":"s"} pendente${pendencias===1?"":"s"}`:"Ciclo concluído"}</strong></div>
              </div>
            </div>
            <button type="button" className={`cycle-btn cycle-btn--panel ${ciclo.status==="ATIVO"?"cycle-btn--primary":"cycle-btn--secondary"}`} onClick={() => navigate(`/ciclos/${ciclo.id}`)}>
              {ciclo.status==="ATIVO"?"Acompanhar ciclo":"Consultar ciclo"}
            </button>
          </div>
        </article>;
      })}</div>}
    </section>
  </main>;
}
export default PainelCiclosCoordenadorPage;
