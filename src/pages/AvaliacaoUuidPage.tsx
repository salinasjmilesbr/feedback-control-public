import { useEffect, useState } from "react";
import { Link, useLocation, useNavigate, useParams } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { ehUuid } from "../infrastructure/supabase/avaliacoes/contrato";
import type { AvaliacaoSoberana, PainelParticipante } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import {
  carregarPainelSoberano,
  concluirAvaliacaoSoberana,
  criarAvaliacaoPorUuidSoberano,
  gravarComentarioFinalSoberano,
  gravarNotasPorIdSoberanas,
  gravarObservacoesSoberanas,
  lerStatusSoberano,
} from "../services/acessoAvaliacoesSoberanas";
import { obterRepositorioCiclosSoberanos, type CicloSoberano } from "../services/acessoCiclosSoberanos";
import { obterColaborador, type ColaboradorSoberano } from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import { concluirFormularioAvaliacaoUuid, salvarFormularioAvaliacaoUuid } from "./avaliacaoUuidFormulario";

type Modo = "nova" | "editar" | "detalhe";
type Estado = {
  colaborador: ColaboradorSoberano;
  ciclo: CicloSoberano | null;
  avaliacao: AvaliacaoSoberana | null;
  painel: PainelParticipante | null;
};

export function AvaliacaoUuidPage({ modo }: { readonly modo: Modo }) {
  const { pathname } = useLocation();
  return <ConteudoAvaliacaoUuid key={pathname} modo={modo} />;
}

function ConteudoAvaliacaoUuid({ modo }: { readonly modo: Modo }) {
  const { collaboratorId, evaluationId } = useParams();
  const { organizacaoAtivaId } = useAuth();
  const navigate = useNavigate();
  const [estado, setEstado] = useState<Estado | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(true);
  const [processando, setProcessando] = useState(false);
  const [notas, setNotas] = useState<Record<string, string>>({});
  const [comentario, setComentario] = useState("");
  const [observacoes, setObservacoes] = useState<Record<string, string>>({});
  const [mensagem, setMensagem] = useState<string | null>(null);
  const [painelSincronizado, setPainelSincronizado] = useState(true);

  useEffect(() => {
    let vigente = true;
    void (async () => {
      if (!organizacaoAtivaId || !ehUuid(collaboratorId ?? "") || (modo !== "nova" && !ehUuid(evaluationId ?? ""))) {
        if (vigente) { setErro("Identidade soberana da avaliação indisponível."); setCarregando(false); }
        return;
      }
      const org = organizacaoAtivaId;
      const alvo = collaboratorId!;
      const colaborador = await obterColaborador({ organizationId: org, collaboratorId: alvo });
      if (!vigente) return;
      if (!colaborador.ok) { setErro(colaborador.mensagem); setCarregando(false); return; }
      const ciclos = obterRepositorioCiclosSoberanos();
      if (!ciclos) { setErro("Ciclos soberanos indisponíveis."); setCarregando(false); return; }

      if (modo === "nova") {
        const ciclo = await ciclos.obterCicloAtivo(org);
        if (!vigente) return;
        if (!ciclo.ok || !ciclo.data) {
          setErro(ciclo.ok ? "Não existe ciclo ativo para criar avaliação." : ciclo.error.message);
        } else {
          setEstado({ colaborador: colaborador.dados, ciclo: ciclo.data, avaliacao: null, painel: null });
        }
        setCarregando(false);
        return;
      }

      const id = evaluationId!;
      if (modo === "editar") {
        const painel = await carregarPainelSoberano({ organizationId: org, evaluationId: id });
        if (!vigente) return;
        if (!painel.ok || !painel.data || painel.data.evaluatedCollaboratorId !== alvo || painel.data.organizationId !== org) {
          setErro(painel.erro ?? "Avaliação indisponível para edição."); setCarregando(false); return;
        }
        const ciclo = await ciclos.obterCiclo(org, painel.data.cycleId);
        if (!vigente) return;
        if (!ciclo.ok || !ciclo.data) { setErro(ciclo.ok ? "Ciclo não encontrado." : ciclo.error.message); setCarregando(false); return; }
        setNotas(Object.fromEntries(painel.data.minhasNotas.map((nota) => [nota.subcriterionId, String(nota.nota)])));
        setComentario(painel.data.meusComentarios.find((item) => item.escopo === "FINAL")?.texto ?? "");
        setObservacoes(Object.fromEntries(painel.data.criterios.map((criterio) => [
          criterio.code,
          painel.data!.meusComentarios.find((item) => item.escopo === "CRITERIO" && item.criterionId === criterio.criterionId)?.texto ?? "",
        ])));
        setEstado({ colaborador: colaborador.dados, ciclo: ciclo.data, avaliacao: null, painel: painel.data });
        setPainelSincronizado(true);
      } else {
        const avaliacao = await lerStatusSoberano({ organizationId: org, evaluationId: id });
        if (!vigente) return;
        if (!avaliacao.ok || !avaliacao.data || avaliacao.data.evaluatedCollaboratorId !== alvo || avaliacao.data.organizationId !== org) {
          setErro(avaliacao.erro ?? "Avaliação não encontrada ou sem autorização."); setCarregando(false); return;
        }
        const ciclo = await ciclos.obterCiclo(org, avaliacao.data.cycleId);
        if (!vigente) return;
        if (!ciclo.ok || !ciclo.data) { setErro(ciclo.ok ? "Ciclo não encontrado." : ciclo.error.message); setCarregando(false); return; }
        setEstado({ colaborador: colaborador.dados, ciclo: ciclo.data, avaliacao: avaliacao.data, painel: null });
      }
      setCarregando(false);
    })();
    return () => { vigente = false; };
  }, [organizacaoAtivaId, collaboratorId, evaluationId, modo]);

  async function criar() {
    if (!estado?.ciclo || !organizacaoAtivaId || !collaboratorId) return;
    setProcessando(true); setErro(null);
    const resultado = await criarAvaliacaoPorUuidSoberano({
      organizationId: organizacaoAtivaId,
      cycleId: estado.ciclo.id,
      evaluatedCollaboratorId: collaboratorId,
    });
    setProcessando(false);
    if (!resultado.ok || !resultado.data) { setErro(resultado.erro ?? "Não foi possível criar a avaliação."); return; }
    navigate(`/colaborador/${collaboratorId}/avaliacoes/${resultado.data.evaluationId}/editar`);
  }

  async function salvar(): Promise<boolean> {
    if (!estado?.painel || !organizacaoAtivaId || !evaluationId) return false;
    setProcessando(true); setErro(null); setMensagem(null);
    const resultado = await salvarFormularioAvaliacaoUuid({
      organizationId: organizacaoAtivaId,
      evaluationId,
      painel: estado.painel,
      notas,
      observacoes,
      comentarioFinal: comentario,
      operacoes: {
        gravarNotas: (entrada) => gravarNotasPorIdSoberanas(entrada),
        gravarObservacoes: (entrada) => gravarObservacoesSoberanas(entrada),
        gravarComentarioFinal: (entrada) => gravarComentarioFinalSoberano(entrada),
        carregarPainel: (entrada) => carregarPainelSoberano(entrada),
      },
    });
    setEstado((atual) => atual ? { ...atual, painel: resultado.painel } : atual);
    setPainelSincronizado(resultado.sincronizado);
    if (resultado.erro?.includes("não permite remover comentários")) {
      setComentario(resultado.painel.meusComentarios.find((item) => item.escopo === "FINAL")?.texto ?? "");
      setObservacoes(Object.fromEntries(resultado.painel.criterios.map((criterio) => [
        criterio.code,
        resultado.painel.meusComentarios.find((item) => item.escopo === "CRITERIO" && item.criterionId === criterio.criterionId)?.texto ?? "",
      ])));
    }
    setProcessando(false);
    if (!resultado.ok) { setErro(resultado.erro ?? "Não foi possível salvar a avaliação."); return false; }
    if (resultado.alterado) setMensagem("Alterações salvas.");
    return true;
  }

  async function concluir() {
    if (!estado?.painel || !organizacaoAtivaId || !evaluationId || !collaboratorId) return;
    setProcessando(true); setErro(null); setMensagem(null);
    const resultado = await concluirFormularioAvaliacaoUuid({
      organizationId: organizacaoAtivaId,
      evaluationId,
      painel: estado.painel,
      notas,
      observacoes,
      comentarioFinal: comentario,
      operacoes: {
        gravarNotas: (entrada) => gravarNotasPorIdSoberanas(entrada),
        gravarObservacoes: (entrada) => gravarObservacoesSoberanas(entrada),
        gravarComentarioFinal: (entrada) => gravarComentarioFinalSoberano(entrada),
        carregarPainel: (entrada) => carregarPainelSoberano(entrada),
      },
      concluir: (entrada) => concluirAvaliacaoSoberana(entrada),
    });
    setProcessando(false);
    setEstado((atual) => atual ? { ...atual, painel: resultado.painel } : atual);
    setPainelSincronizado(resultado.sincronizado);
    if (resultado.erro?.includes("não permite remover comentários")) {
      setComentario(resultado.painel.meusComentarios.find((item) => item.escopo === "FINAL")?.texto ?? "");
      setObservacoes(Object.fromEntries(resultado.painel.criterios.map((criterio) => [
        criterio.code,
        resultado.painel.meusComentarios.find((item) => item.escopo === "CRITERIO" && item.criterionId === criterio.criterionId)?.texto ?? "",
      ])));
    }
    if (!resultado.ok) { setErro(resultado.erro ?? "Conclusão recusada pela validação oficial."); return; }
    navigate(`/colaborador/${collaboratorId}/avaliacoes/${evaluationId}`);
  }

  return (
    <main className="virtus-page">
      <Link to={`/colaborador/${collaboratorId ?? ""}`}>← Voltar à ficha do colaborador</Link>
      <h1>{modo === "nova" ? "Nova avaliação" : modo === "editar" ? "Preencher avaliação" : "Detalhe da avaliação"}</h1>
      {carregando && <p role="status">Carregando avaliação…</p>}
      {erro && <p role="alert">{erro}</p>}
      {estado && <>
        <p>{estado.colaborador.fullName}</p>
        <p>Ciclo {estado.ciclo?.numero}/{estado.ciclo?.ano}</p>
        {modo === "nova" && <button type="button" className="virtus-btn" disabled={processando} onClick={() => void criar()}>Criar avaliação</button>}
        {estado.avaliacao && <section aria-label="Resultado soberano">
          <p>Status: {estado.avaliacao.status}</p>
          <p>Resultado oficial: {estado.avaliacao.notaMedia ?? "Ainda não disponível"}</p>
          {estado.avaliacao.dataConclusao && <p>Concluída em {estado.avaliacao.dataConclusao}</p>}
          {estado.avaliacao.status !== "CONCLUIDA" && estado.avaliacao.status !== "CANCELADA" &&
            <Link to={`/colaborador/${collaboratorId}/avaliacoes/${evaluationId}/editar`}>Editar avaliação</Link>}
        </section>}
        {estado.painel && <>
          <p>Status: {estado.painel.status}</p>
          {estado.painel.criterios.map((criterio) => <section key={criterio.criterionId} aria-label={criterio.name}>
            <h2>{criterio.name}</h2>
            {estado.painel!.subcriterios.filter((item) => item.criterionCode === criterio.code).map((item) => <label key={item.subcriterionId}>
              {item.name}
              <input type="number" min="1" max="5" step="1" value={notas[item.subcriterionId] ?? ""} onChange={(event) => setNotas((atual) => ({ ...atual, [item.subcriterionId]: event.target.value }))} />
            </label>)}
            <label>Comentário sobre {criterio.name}<textarea value={observacoes[criterio.code] ?? ""} onChange={(event) => setObservacoes((atual) => ({ ...atual, [criterio.code]: event.target.value }))} /></label>
          </section>)}
          <label>Comentário final<textarea value={comentario} onChange={(event) => setComentario(event.target.value)} /></label>
          {mensagem && <p role="status">{mensagem}</p>}
          {!painelSincronizado && <p role="alert">Não foi possível confirmar o estado persistido. Recarregue o painel antes de continuar.</p>}
          <div className="virtus-page-actions">
            <button type="button" className="virtus-btn virtus-btn--outline" disabled={processando || !painelSincronizado} onClick={() => void salvar()}>Salvar</button>
            <button type="button" className="virtus-btn" disabled={processando || !painelSincronizado} onClick={() => void concluir()}>Concluir avaliação</button>
            {!painelSincronizado && <button type="button" className="virtus-btn virtus-btn--outline" onClick={() => window.location.reload()}>Recarregar painel</button>}
          </div>
        </>}
      </>}
    </main>
  );
}
