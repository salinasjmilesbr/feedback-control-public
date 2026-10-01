import type { PainelParticipante } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import type { ObservacaoDoPainel } from "../services/avaliacoesSoberanas/cutoverAvaliacoesService";

type Resultado<T> = { readonly ok: boolean; readonly data?: T; readonly erro?: string };

export interface OperacoesFormularioAvaliacaoUuid {
  gravarNotas(entrada: { readonly organizationId: string; readonly evaluationId: string; readonly painel: PainelParticipante; readonly notas: readonly { readonly subcriterionId: string; readonly nota: number }[] }): Promise<Resultado<number | null>>;
  gravarObservacoes(entrada: { readonly organizationId: string; readonly evaluationId: string; readonly painel: PainelParticipante; readonly observacoes: readonly ObservacaoDoPainel[] }): Promise<Resultado<number>>;
  gravarComentarioFinal(entrada: { readonly organizationId: string; readonly evaluationId: string; readonly painel: PainelParticipante; readonly texto: string }): Promise<Resultado<null>>;
  carregarPainel(entrada: { readonly organizationId: string; readonly evaluationId: string }): Promise<Resultado<PainelParticipante>>;
}

export interface ResultadoSalvarFormularioUuid {
  readonly ok: boolean;
  readonly painel: PainelParticipante;
  readonly erro?: string;
  readonly alterado: boolean;
  readonly sincronizado: boolean;
}

export async function concluirFormularioAvaliacaoUuid(entrada: Parameters<typeof salvarFormularioAvaliacaoUuid>[0] & {
  readonly concluir: (entrada: { readonly organizationId: string; readonly evaluationId: string }) => Promise<Resultado<null>>;
}): Promise<ResultadoSalvarFormularioUuid> {
  const salvo = await salvarFormularioAvaliacaoUuid(entrada);
  if (!salvo.ok || !salvo.sincronizado) return salvo;
  const resultado = await entrada.concluir({ organizationId: entrada.organizationId, evaluationId: entrada.evaluationId });
  if (!resultado.ok) return { ...salvo, ok: false, erro: resultado.erro ?? "Conclusão recusada pela validação oficial." };
  return salvo;
}

export async function salvarFormularioAvaliacaoUuid(entrada: {
  readonly organizationId: string;
  readonly evaluationId: string;
  readonly painel: PainelParticipante;
  readonly notas: Readonly<Record<string, string>>;
  readonly observacoes: Readonly<Record<string, string>>;
  readonly comentarioFinal: string;
  readonly operacoes: OperacoesFormularioAvaliacaoUuid;
}): Promise<ResultadoSalvarFormularioUuid> {
  const { organizationId, evaluationId, operacoes } = entrada;
  let painel = entrada.painel;
  const anteriorNotas = new Map(painel.minhasNotas.map((item) => [item.subcriterionId, item.nota]));
  const notas = Object.entries(entrada.notas)
    .filter(([id, valor]) => valor.trim() !== "" && anteriorNotas.get(id) !== Number(valor))
    .map(([subcriterionId, valor]) => ({ subcriterionId, nota: Number(valor) }));
  if (notas.some(({ nota }) => !Number.isInteger(nota) || nota < 1 || nota > 5)) {
    return { ok: false, erro: "Informe notas inteiras entre 1 e 5.", painel, alterado: false, sincronizado: true };
  }

  const comentariosExistentes = new Map(painel.meusComentarios.map((item) => [
    `${item.escopo}:${item.criterionId ?? ""}`,
    item.texto,
  ]));
  const comentarioFinalAnterior = comentariosExistentes.get("FINAL:") ?? "";
  const comentariosCriterioRemovidos = painel.criterios.filter((criterio) =>
    (comentariosExistentes.get(`CRITERIO:${criterio.criterionId}`) ?? "").trim() !== "" &&
    !(entrada.observacoes[criterio.code] ?? "").trim()
  );
  if ((comentarioFinalAnterior.trim() && !entrada.comentarioFinal.trim()) || comentariosCriterioRemovidos.length > 0) {
    return {
      ok: false,
      erro: "Este fluxo não permite remover comentários já salvos. Restaure o texto ou substitua-o por outro conteúdo.",
      painel,
      alterado: false,
      sincronizado: true,
    };
  }

  const observacoes = Object.entries(entrada.observacoes).filter(([code, texto]) => {
    const criterio = painel.criterios.find((item) => item.code === code);
    const anterior = comentariosExistentes.get(`CRITERIO:${criterio?.criterionId ?? ""}`) ?? "";
    return texto.trim() !== "" && texto !== anterior;
  }).map(([criterioCode, texto]) => ({ criterioCode, texto }));
  const comentarioMudou = entrada.comentarioFinal.trim() !== "" && entrada.comentarioFinal !== comentarioFinalAnterior;
  const alterado = notas.length > 0 || observacoes.length > 0 || comentarioMudou;
  if (!alterado) return { ok: true, painel, alterado: false, sincronizado: true };

  let erro: string | undefined;
  let sincronizado = false;
  try {
    if (notas.length > 0) {
      const resultado = await operacoes.gravarNotas({ organizationId, evaluationId, painel, notas });
      if (!resultado.ok) erro = resultado.erro ?? "Não foi possível salvar as notas.";
    }
    if (!erro && observacoes.length > 0) {
      const resultado = await operacoes.gravarObservacoes({ organizationId, evaluationId, painel, observacoes });
      if (!resultado.ok) erro = resultado.erro ?? "Não foi possível salvar os comentários.";
    }
    if (!erro && comentarioMudou) {
      const resultado = await operacoes.gravarComentarioFinal({ organizationId, evaluationId, painel, texto: entrada.comentarioFinal });
      if (!resultado.ok) erro = resultado.erro ?? "Não foi possível salvar o comentário final.";
    }
  } catch {
    erro = "Não foi possível concluir o salvamento da avaliação.";
  }

  // Releitura também após falha: etapas anteriores podem ter sido confirmadas
  // independentemente. O próximo diff parte sempre da fotografia persistida.
  try {
    const atualizado = await operacoes.carregarPainel({ organizationId, evaluationId });
    if (atualizado.ok && atualizado.data) { painel = atualizado.data; sincronizado = true; }
    else erro ??= atualizado.erro ?? "Salvamento realizado, mas o painel não pôde ser sincronizado.";
  } catch {
    erro ??= "Salvamento realizado, mas o painel não pôde ser sincronizado.";
  }

  return { ok: !erro, ...(erro ? { erro } : {}), painel, alterado, sincronizado };
}
