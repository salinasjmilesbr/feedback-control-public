import jsPDF from "jspdf";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { getColaboradores } from "./colaboradorStorage";
import { getObservacoesComunicadasByCiclo } from "./observacaoStorage";
import { getCiclosAvaliacao } from "./cicloAvaliacaoStorage";
import { getMetasDoColaboradorNoCiclo } from "./metaStorage";
import { formatarNota } from "./escalaAvaliacaoStorage";

function limparNomeArquivo(valor: string) {
  return valor
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
}

function formatarSenioridade(
  senioridade: Colaborador["senioridade"]
) {
  if (senioridade === "JUNIOR") return "Júnior";
  if (senioridade === "PLENO") return "Pleno";
  if (senioridade === "SENIOR") return "Sênior";
  return "-";
}

function formatarFuncao(funcao: Colaborador["funcao"]) {
  if (funcao === "GERENTE") return "Gerente";
  if (funcao === "COORDENADOR") return "Coordenador";
  if (funcao === "CONSULTOR") return "Consultor";
  if (funcao === "ANALISTA") return "Analista";
  return "-";
}

function formatarData(data?: string) {
  if (!data) return "-";

  const valor = new Date(data);

  if (Number.isNaN(valor.getTime())) return "-";

  return valor.toLocaleDateString("pt-BR");
}

function obterAvaliadores(colaborador: Colaborador) {
  const colaboradores = getColaboradores();

  const gestorDireto = colaborador.gestorDiretoMatricula
    ? colaboradores.find(
        (item) =>
          item.matricula === colaborador.gestorDiretoMatricula
      )
    : undefined;

  const coordenador =
    gestorDireto?.funcao === "COORDENADOR"
      ? gestorDireto
      : undefined;

  const gerente =
    gestorDireto?.funcao === "GERENTE"
      ? gestorDireto
      : coordenador?.gestorDiretoMatricula
      ? colaboradores.find(
          (item) =>
            item.matricula ===
            coordenador.gestorDiretoMatricula
        )
      : undefined;

  const colegiado = (
    colaborador.avaliadoresColegiadoMatriculas ?? []
  )
    .map((matricula) =>
      colaboradores.find(
        (item) => item.matricula === matricula
      )
    )
    .filter((item) => item !== undefined);

  return {
    gerente,
    coordenador,
    colegiado,
  };
}

export function exportarAvaliacaoPdf(
  colaborador: Colaborador,
  feedback: Feedback
) {
  const avaliadores = obterAvaliadores(colaborador);

  const observacoesComunicadas = getObservacoesComunicadasByCiclo(
    colaborador.matricula,
    feedback.ano,
    feedback.ciclo
  );

  const cicloDaAvaliacao = getCiclosAvaliacao().find(
    (ciclo) =>
      ciclo.ano === feedback.ano &&
      ciclo.ciclo === feedback.ciclo
  );

  const metasDoCiclo = cicloDaAvaliacao
    ? getMetasDoColaboradorNoCiclo(
        colaborador.matricula,
        cicloDaAvaliacao.id
      )
    : [];

  const dataConclusao =
    feedback.dataConclusao ??
    feedback.dataUltimaAtualizacao ??
    feedback.data;

  const pdf = new jsPDF({
    orientation: "portrait",
    unit: "mm",
    format: "a4",
  });

  const margem = 16;
  const larguraPagina = pdf.internal.pageSize.getWidth();
  const alturaPagina = pdf.internal.pageSize.getHeight();
  const larguraTexto = larguraPagina - margem * 2;
  let y = 18;

  function garantirEspaco(alturaNecessaria: number) {
    if (y + alturaNecessaria > alturaPagina - 16) {
      pdf.addPage();
      y = 18;
    }
  }

  function escreverTexto(
    texto: string,
    tamanho = 10,
    negrito = false,
    espacamentoDepois = 3
  ) {
    if (!texto.trim()) return;

    pdf.setFont("helvetica", negrito ? "bold" : "normal");
    pdf.setFontSize(tamanho);

    const linhas = pdf.splitTextToSize(texto, larguraTexto);
    const alturaLinha = tamanho * 0.42 + 1.5;
    const alturaTotal = linhas.length * alturaLinha;

    garantirEspaco(alturaTotal + espacamentoDepois);
    pdf.text(linhas, margem, y);
    y += alturaTotal + espacamentoDepois;
  }

  function escreverLinhaNotas(
    notaGerente: number,
    notaCoordenador: number,
    notaColegiado: number,
    notaFinal: number
  ) {
    const valor = (nota: number) =>
      nota > 0 ? formatarNota(nota) : "Não avaliado";

    const partes = [`Gerente: ${valor(notaGerente)}`];

    if (colaborador.funcao === "ANALISTA") {
      partes.push(`Coordenador: ${valor(notaCoordenador)}`);
      partes.push(`Colegiado: ${valor(notaColegiado)}`);
    }

    partes.push(`Nota final: ${valor(notaFinal)}`);

    escreverTexto(partes.join("    "), 9, false, 4);
  }

  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(18);
  pdf.text("Relatorio de Avaliacao", margem, y);
  y += 9;

  escreverTexto(colaborador.nome, 13, true, 2);
  escreverTexto(
    `Matrícula: ${colaborador.matricula}`,
    10,
    false,
    2
  );
  escreverTexto(
    `${feedback.ano} - Ciclo ${feedback.ciclo} | Concluído em: ${formatarData(
      dataConclusao
    )}`,
    10,
    false,
    3
  );

  escreverTexto(`Cargo: ${colaborador.cargo}`, 10, false, 1);
  escreverTexto(`Área: ${colaborador.area}`, 10, false, 1);
  escreverTexto(
    `Função: ${formatarFuncao(colaborador.funcao)}`,
    10,
    false,
    1
  );
  if (colaborador.funcao === "ANALISTA") {
    escreverTexto(
      `Senioridade: ${formatarSenioridade(
        colaborador.senioridade
      )}`,
      10,
      false,
      5
    );
  } else {
    y += 3;
  }

  if (feedback.encerradaComPendencias) {
    escreverTexto(
      "Avaliação parcialmente concluída. O ciclo foi encerrado com notas pendentes. As médias consideram somente as avaliações efetivamente realizadas.",
      10,
      true,
      2
    );

    (feedback.pendenciasEncerramento ?? []).forEach((pendencia) =>
      escreverTexto(`• ${pendencia}`, 9, false, 1)
    );

    y += 3;
  }

  garantirEspaco(18);
  pdf.setDrawColor(102, 0, 153);
  pdf.roundedRect(margem, y, larguraTexto, 16, 2, 2);
  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(11);
  pdf.text("Nota Final", margem + 4, y + 6);
  pdf.setFontSize(17);
  pdf.text(formatarNota(feedback.notaMedia), margem + 4, y + 13);
  y += 23;

  escreverTexto("Avaliadores envolvidos", 12, true, 2);

  if (avaliadores.gerente) {
    escreverTexto(
      `Gerente: ${avaliadores.gerente.nome}`,
      10,
      false,
      1
    );
  }

  if (colaborador.funcao === "ANALISTA") {
    if (avaliadores.coordenador) {
      escreverTexto(
        `Coordenador: ${avaliadores.coordenador.nome}`,
        10,
        false,
        1
      );
    }

    if (avaliadores.colegiado.length > 0) {
      escreverTexto(
        `Colegiado: ${avaliadores.colegiado
          .map((avaliador) => avaliador.nome)
          .join(", ")}`,
        10,
        false,
        5
      );
    } else {
      escreverTexto("Colegiado: -", 10, false, 5);
    }
  } else {
    y += 3;
  }

  const criterios = feedback.criteriosDetalhados ?? [];

  criterios.forEach((criterio, indice) => {
    garantirEspaco(22);

    pdf.setFont("helvetica", "bold");
    pdf.setFontSize(12);
    pdf.text(
      `${indice + 1}. ${criterio.criterioNome} - ${formatarNota(criterio.nota)}`,
      margem,
      y
    );
    y += 7;

    criterio.subcriterios.forEach((subcriterio) => {
      escreverTexto(subcriterio.nome, 10, true, 1);
      escreverLinhaNotas(
        subcriterio.notaGerente,
        subcriterio.notaCoordenador,
        subcriterio.notaColegiado,
        subcriterio.notaFinal
      );
    });

    if (criterio.observacaoGerente?.trim()) {
      escreverTexto("Observacao do Gerente", 10, true, 1);
      escreverTexto(criterio.observacaoGerente, 9, false, 4);
    }

    if (
      colaborador.funcao === "ANALISTA" &&
      criterio.observacaoCoordenador?.trim()
    ) {
      escreverTexto("Observacao do Coordenador", 10, true, 1);
      escreverTexto(criterio.observacaoCoordenador, 9, false, 4);
    }

    y += 3;
  });

  if (metasDoCiclo.length > 0) {
    garantirEspaco(18);
    escreverTexto("Metas do Ciclo", 13, true, 3);

    const gruposMetas = [
      {
        titulo: "Metas de Negócio / Projetos",
        metas: metasDoCiclo.filter(
          (meta) => meta.tipo === "NEGOCIO_PROJETO"
        ),
      },
      {
        titulo: "Metas Individuais",
        metas: metasDoCiclo.filter(
          (meta) => meta.tipo === "INDIVIDUAL"
        ),
      },
    ];

    gruposMetas.forEach((grupo) => {
      if (grupo.metas.length === 0) return;

      garantirEspaco(12);
      escreverTexto(grupo.titulo, 10, true, 2);

      grupo.metas.forEach((meta, indice) => {
        garantirEspaco(28);

        const statusMeta =
          meta.status === "ATINGIDA"
            ? "Atingida"
            : meta.status === "NAO_ATINGIDA"
            ? "Não atingida"
            : "Pendente / Não finalizada";

        escreverTexto(
          `${indice + 1}. ${meta.descricao}`,
          10,
          true,
          1
        );
        escreverTexto(`KPI: ${meta.kpi}`, 9, false, 1);
        escreverTexto(
          `Valor-alvo: ${meta.valorAlvo}`,
          9,
          false,
          1
        );
        escreverTexto(
          `Resultado final: ${
            meta.resultadoFinal?.trim()
              ? meta.resultadoFinal
              : "Não informado"
          }`,
          9,
          false,
          1
        );
        escreverTexto(
          `Status: ${statusMeta}`,
          9,
          true,
          4
        );
      });
    });
  }

  if (observacoesComunicadas.length > 0) {
    garantirEspaco(16);
    escreverTexto("Observações do Ciclo", 13, true, 3);

    observacoesComunicadas.forEach((observacao) => {
      const tipoObservacao =
        observacao.tipo === "POSITIVA"
          ? "Positiva"
          : observacao.tipo === "NEGATIVA"
          ? "Negativa"
          : "Neutra";

      escreverTexto(
        `${tipoObservacao} | ${formatarData(
          observacao.dataCriacao
        )} | ${observacao.autorNome}`,
        9,
        true,
        1
      );
      escreverTexto(observacao.texto, 9, false, 4);
    });
  }

  if (
    feedback.feedbackFinalGerente?.trim() ||
    (colaborador.funcao === "ANALISTA" &&
      feedback.feedbackFinalCoordenador?.trim())
  ) {
    garantirEspaco(16);
    escreverTexto("Feedback Final", 13, true, 3);

    if (feedback.feedbackFinalGerente?.trim()) {
      escreverTexto("Gerente", 10, true, 1);
      escreverTexto(feedback.feedbackFinalGerente, 9, false, 4);
    }

    if (
      colaborador.funcao === "ANALISTA" &&
      feedback.feedbackFinalCoordenador?.trim()
    ) {
      escreverTexto("Coordenador", 10, true, 1);
      escreverTexto(
        feedback.feedbackFinalCoordenador,
        9,
        false,
        4
      );
    }
  }

  const totalPaginas = pdf.getNumberOfPages();

  for (let pagina = 1; pagina <= totalPaginas; pagina++) {
    pdf.setPage(pagina);
    pdf.setFont("helvetica", "normal");
    pdf.setFontSize(8);
    pdf.setTextColor(100);
    pdf.text(
      `Pagina ${pagina} de ${totalPaginas}`,
      larguraPagina - margem,
      alturaPagina - 8,
      { align: "right" }
    );
    pdf.setTextColor(0);
  }

  const nomeArquivo = [
    "avaliacao",
    limparNomeArquivo(colaborador.nome),
    String(feedback.ano),
    `ciclo-${feedback.ciclo}`,
  ].join("-");

  pdf.save(`${nomeArquivo}.pdf`);
}


