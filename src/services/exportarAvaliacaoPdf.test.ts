/**
 * F5-11 P5 (Issue #250), L5 — o PDF da avaliação recebe as observações
 * COMUNICADAS da porta SOBERANA, nunca de um acervo local.
 *
 * Prova (sem qualquer dependência de navegador):
 * 1. o parâmetro `observacoesComunicadas` é a ÚNICA origem das observações do
 *    documento — não há leitura local (`observacaoStorage`) no caminho;
 * 2. lista vazia é ausência EXPLÍCITA: o documento é gerado normalmente, sem a
 *    seção "Observações do Ciclo" e sem quebra;
 * 3. lista vazia não quebra o documento nem faz o serviço inventar observação,
 *    autor ou ciclo;
 * 4. a barreira é ESTÁTICA: o fonte não cita acervo local, RPC direta nem
 *    credencial privilegiada.
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import type { ObservacaoSoberana } from "../application/ports/ObservationRepository";
import { getColaboradores } from "./colaboradorStorage";
import ExportarAvaliacaoPdfFonte from "./exportarAvaliacaoPdf.ts?raw";
import { exportarAvaliacaoPdf } from "./exportarAvaliacaoPdf";

/** Documento capturado: nomes de arquivo gerados e textos escritos. */
interface PdfCapturado {
  readonly arquivos: string[];
  readonly textos: string[];
}

let pdfCapturado: PdfCapturado = { arquivos: [], textos: [] };

function textoDe(valor: unknown): string {
  if (Array.isArray(valor)) return valor.map((item) => String(item)).join(" ");
  return valor === null || valor === undefined ? "" : String(valor);
}

vi.mock("jspdf", () => {
  class PdfFalso {
    private readonly textos: string[] = [];
    private readonly arquivos: string[] = [];

    internal = { pageSize: { getWidth: () => 210, getHeight: () => 297 } };

    setFont(): void {
      return undefined;
    }

    setFontSize(): void {
      return undefined;
    }

    setTextColor(): void {
      return undefined;
    }

    setDrawColor(): void {
      return undefined;
    }

    splitTextToSize(texto: unknown): string[] {
      return [textoDe(texto)];
    }

    text(valor: unknown): void {
      this.textos.push(textoDe(valor));
    }

    roundedRect(): void {
      return undefined;
    }

    addPage(): void {
      return undefined;
    }

    getNumberOfPages(): number {
      return 1;
    }

    setPage(): void {
      return undefined;
    }

    save(nome: string): void {
      this.arquivos.push(nome);
      pdfCapturado = { arquivos: [...this.arquivos], textos: [...this.textos] };
    }
  }

  return { default: PdfFalso };
});

vi.mock("./colaboradorStorage", async (importOriginal) => {
  const real = await importOriginal<typeof import("./colaboradorStorage")>();
  return { ...real, getColaboradores: vi.fn(() => []) };
});

vi.mock("./observacaoStorage", async (importOriginal) => {
  const real = await importOriginal<typeof import("./observacaoStorage")>();
  return { ...real, getObservacoesComunicadasByCiclo: vi.fn(() => []) };
});

/** Espião da leitura LEGADA de observações: precisa continuar em ZERO. */
async function espiaoDaLeituraLegadaDeObservacoes() {
  const modulo = await import("./observacaoStorage");
  return vi.mocked(modulo.getObservacoesComunicadasByCiclo);
}

const MATRICULA = 4321;

function colaboradorFicticio(): Colaborador {
  return {
    matricula: MATRICULA,
    status: "ATIVO",
    nome: "Pessoa Fictícia",
    email: "pessoa@example.invalid",
    cargo: "Cargo Fictício",
    area: "Área Fictícia",
    funcao: "ANALISTA",
    senioridade: "PLENO",
    respondePara: "",
  };
}

function feedbackFicticio(): Feedback {
  return {
    id: "avaliacao-ficticia",
    colaboradorId: MATRICULA,
    colaboradorNome: "Pessoa Fictícia",
    status: "CONCLUIDA",
    data: "2026-03-01T12:00:00.000Z",
    dataConclusao: "2026-03-10T12:00:00.000Z",
    ano: 2026,
    ciclo: 1,
    competencias: [],
    notaMedia: 4,
    criteriosDetalhados: [],
  };
}

function observacaoComunicada(
  parcial: Partial<ObservacaoSoberana> = {}
): ObservacaoSoberana {
  return {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    organizationId: "55555555-5555-4555-8555-555555555555",
    collaboratorId: "11111111-1111-4111-8111-111111111111",
    cycleId: "66666666-6666-4666-8666-666666666666",
    tipo: "POSITIVA",
    texto: "Observação comunicada fictícia",
    comunicado: true,
    comunicadoEm: "2026-03-02T12:00:00.000Z",
    excluida: false,
    motivoExclusao: null,
    autorUserProfileId: "77777777-7777-4777-8777-777777777777",
    autorCollaboratorId: "88888888-8888-4888-8888-888888888888",
    version: 1,
    criadoEm: "2026-03-01T12:00:00.000Z",
    atualizadoEm: "2026-03-02T12:00:00.000Z",
    ...parcial,
  };
}

function gerar(observacoes: readonly ObservacaoSoberana[]): PdfCapturado {
  exportarAvaliacaoPdf(colaboradorFicticio(), feedbackFicticio(), [], observacoes);
  return pdfCapturado;
}

function textoDoPdf(capturado: PdfCapturado): string {
  return capturado.textos.join("\n");
}

describe("F5-11 P5 (L5) — observações soberanas no PDF da avaliação", () => {
  beforeEach(() => {
    pdfCapturado = { arquivos: [], textos: [] };
    vi.mocked(getColaboradores).mockClear();
  });

  it("imprime as observações RECEBIDAS por parâmetro (lista soberana)", () => {
    const capturado = gerar([
      observacaoComunicada({ texto: "Fato positivo comunicado" }),
      observacaoComunicada({
        id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        tipo: "NEGATIVA",
        texto: "Fato negativo comunicado",
      }),
    ]);
    const texto = textoDoPdf(capturado);

    expect(capturado.arquivos).toHaveLength(1);
    expect(texto).toContain("Observações do Ciclo");
    expect(texto).toContain("Fato positivo comunicado");
    expect(texto).toContain("Fato negativo comunicado");
    expect(texto).toContain("Positiva");
    expect(texto).toContain("Negativa");
  });

  it("lista vazia não quebra o documento e não cria seção de observações", () => {
    const capturado = gerar([]);
    const texto = textoDoPdf(capturado);

    expect(capturado.arquivos).toHaveLength(1);
    expect(capturado.arquivos[0]).toMatch(/^avaliacao-.*\.pdf$/);
    expect(texto).toContain("Relatorio de Avaliacao");
    expect(texto).not.toContain("Observações do Ciclo");
    // Nenhuma observação, autor ou ciclo é inventado quando a lista é vazia.
    expect(texto).not.toContain("Observação comunicada fictícia");
    expect(texto).not.toContain("Autor não identificado");
  });

  it("não lê observação no acervo local: a origem é sempre o parâmetro", async () => {
    gerar([observacaoComunicada()]);

    const espiao = await espiaoDaLeituraLegadaDeObservacoes();
    expect(espiao).not.toHaveBeenCalled();
  });
});

describe("F5-11 P5 (L5) — barreira estática no serviço de PDF", () => {
  it("o fonte é varrido como string (prova não-vacuamente verde)", () => {
    expect(ExportarAvaliacaoPdfFonte).toBeTypeOf("string");
    expect(ExportarAvaliacaoPdfFonte).toContain("export function exportarAvaliacaoPdf");
    // Não-vacuidade do molde: o parâmetro soberano existe com o tipo da porta.
    expect(ExportarAvaliacaoPdfFonte).toContain(
      "observacoesComunicadas: readonly ObservacaoSoberana[] = []"
    );
    expect(ExportarAvaliacaoPdfFonte).toContain("NÃO lê storage local");
  });

  it("o serviço não cita acervo local, RPC direta nem credencial privilegiada", () => {
    for (const proibido of [
      "observacaoStorage",
      "getObservacoesComunicadasByCiclo",
      "localStorage",
      "sessionStorage",
      ".rpc(",
      "service_role",
      "SERVICE_ROLE",
    ]) {
      expect(ExportarAvaliacaoPdfFonte, proibido).not.toContain(proibido);
    }
  });

  it("o serviço não decide autorização (policy/capability ficam fora do PDF)", () => {
    expect(ExportarAvaliacaoPdfFonte).not.toMatch(/\bauthorize\s*\(/);
    expect(ExportarAvaliacaoPdfFonte).not.toMatch(/\bcan\s*\(/);
  });
});
