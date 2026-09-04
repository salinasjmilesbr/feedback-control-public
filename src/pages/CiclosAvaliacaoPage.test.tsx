import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type {
  CicloAvaliacao,
  StatusCicloAvaliacao,
} from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import CiclosAvaliacaoPage from "./CiclosAvaliacaoPage";
import { confirmarExclusaoCiclo } from "./confirmarExclusaoCiclo";

const gerente: Colaborador = {
  matricula: 1,
  status: "ATIVO",
  nome: "Gerente Fictício",
  email: "gerente@example.com",
  cargo: "Gerente",
  area: "Área fictícia",
  funcao: "GERENTE",
  respondePara: "",
};
const coordenador: Colaborador = {
  ...gerente,
  matricula: 2,
  nome: "Coordenador Fictício",
  email: "coordenador@example.com",
  funcao: "COORDENADOR",
};

function renderizar(
  status: StatusCicloAvaliacao,
  mostrarCanceladosInicial = false,
  usuario: Colaborador = gerente,
  dadosCiclo: Partial<CicloAvaliacao> = {}
): string {
  const ciclo: CicloAvaliacao = {
    id: "ciclo-ui",
    ano: 2026,
    ciclo: 1,
    status,
    dataCriacao: "2026-01-01T00:00:00.000Z",
    dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
    ...dadosCiclo,
  };
  localStorage.setItem("feedback-control-ciclos", JSON.stringify([ciclo]));

  return renderToStaticMarkup(
    <UsuarioAtualContext.Provider
      value={{
        usuarioAtual: usuario,
        usuariosDisponiveis: [gerente, coordenador],
        selecionarUsuario: () => undefined,
      }}
    >
      <MemoryRouter>
        <CiclosAvaliacaoPage
          mostrarCanceladosInicial={mostrarCanceladosInicial}
        />
      </MemoryRouter>
    </UsuarioAtualContext.Provider>
  );
}

describe("ações de lifecycle em CiclosAvaliacaoPage", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("mostra somente ativação para ciclo planejado", () => {
    const html = renderizar("PLANEJADO");

    expect(html).toContain("Ativar ciclo");
    expect(html).not.toContain("Encerrar ciclo");
    expect(html).not.toContain("Editar status");
    expect(html).toContain("Editar período");
    expect(html).not.toContain("Corrigir período");
    expect(html).toContain("Excluir ciclo");
    expect(html).not.toContain("Cancelar ciclo");
    expect(html).not.toContain("Reabrir ciclo");
  });

  it("mostra somente encerramento para ciclo ativo", () => {
    const html = renderizar("ATIVO");

    expect(html).toContain("Encerrar ciclo");
    expect(html).not.toContain("Ativar ciclo");
    expect(html).not.toContain("Editar status");
    expect(html).not.toContain("Editar período");
    expect(html).toContain("Corrigir período");
    expect(html).not.toContain("Excluir ciclo");
    expect(html).toContain("Cancelar ciclo");
    expect(html).not.toContain("Reabrir ciclo");
  });

  it("mostra reabertura somente para gerente autorizado em ciclo encerrado", () => {
    const html = renderizar("ENCERRADO");

    expect(html).not.toContain("Ativar ciclo");
    expect(html).not.toContain("Encerrar ciclo");
    expect(html).not.toContain("Editar status");
    expect(html).toContain("Ciclo encerrado");
    expect(html).not.toContain("Editar período");
    expect(html).not.toContain("Corrigir período");
    expect(html).not.toContain("Excluir ciclo");
    expect(html).not.toContain("Cancelar ciclo");
    expect(html).toContain("Reabrir ciclo");
    expect(renderizar("ENCERRADO", false, coordenador)).not.toContain("Reabrir ciclo");
  });

  it("oculta cancelados por padrão e oferece controle explícito", () => {
    const html = renderizar("CANCELADO");

    expect(html).toContain("Mostrar cancelados");
    expect(html).not.toContain("Ciclo cancelado");
  });

  it("identifica cancelado quando exibido e oculta todas as ações normais", () => {
    const html = renderizar("CANCELADO", true);

    expect(html).toContain("Cancelado");
    expect(html).toContain("Ciclo cancelado");
    expect(html).not.toContain("Ativar ciclo");
    expect(html).not.toContain("Encerrar ciclo");
    expect(html).not.toContain("Editar período");
    expect(html).not.toContain("Corrigir período");
    expect(html).not.toContain("Excluir ciclo");
    expect(html).not.toContain("Cancelar ciclo");
    expect(html).not.toContain("Reabrir ciclo");
  });

  it("exige confirmação explícita antes da exclusão", () => {
    const ciclo: CicloAvaliacao = {
      id: "ciclo-confirmacao",
      ano: 2026,
      ciclo: 2,
      status: "PLANEJADO",
      dataCriacao: "2026-01-01T00:00:00.000Z",
      dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
    };
    let mensagem = "";

    const confirmado = confirmarExclusaoCiclo(ciclo, (texto) => {
      mensagem = texto;
      return false;
    });

    expect(confirmado).toBe(false);
    expect(mensagem).toContain("Excluir 2026 • Ciclo 2?");
    expect(mensagem).toContain("Avaliações vazias");
  });
});

describe("histórico administrativo em CiclosAvaliacaoPage", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("mostra estado vazio sem ampliar ações de mutação", () => {
    const html = renderizar("ENCERRADO");
    const cicloPersistidoAntes = localStorage.getItem("feedback-control-ciclos");
    renderizar("ENCERRADO");

    expect(html).toContain("Ver histórico");
    expect(html).toContain("Nenhuma alteração auditada registrada.");
    expect(html).not.toContain("Corrigir período");
    expect(html).not.toContain("Cancelar ciclo");
    expect(localStorage.getItem("feedback-control-ciclos")).toBe(
      cicloPersistidoAntes
    );
  });

  it("exibe encerramento, reabertura e cancelamento persistidos", () => {
    const html = renderizar("CANCELADO", true, gerente, {
      encerramentos: [
        {
          data: "2026-03-01T10:00:00.000Z",
          encerradoComPendencias: true,
          quantidadePendencias: 3,
        },
      ],
      reaberturas: [
        {
          data: "2026-03-02T10:00:00.000Z",
          motivo: "Revisão administrativa",
          autorNome: "Gerente Fictício",
          autorMatricula: 1,
        },
      ],
      cancelamento: {
        data: "2026-03-03T10:00:00.000Z",
        motivo: "Mudança de planejamento",
        autorNome: "Gerente Fictício",
        autorMatricula: 1,
      },
    });

    expect(html).toContain("Encerramento");
    expect(html).toContain("Encerrado com pendências (3).");
    expect(html).toContain("Reabertura");
    expect(html).toContain("Revisão administrativa");
    expect(html).toContain("Cancelamento");
    expect(html).toContain("Mudança de planejamento");
  });

  it("exibe correção de período com auditoria e resumo de impacto", () => {
    const html = renderizar("ATIVO", false, gerente, {
      correcoesPeriodo: [
        {
          data: "2026-04-10T14:30:00.000Z",
          autorNome: "Gerente Fictício",
          autorMatricula: 1,
          justificativa: "Adequação ao calendário oficial",
          periodoAnterior: {
            dataInicio: "2026-01-01",
            dataFim: "2026-06-30",
          },
          novoPeriodo: {
            dataInicio: "2026-01-15",
            dataFim: "2026-06-15",
          },
          impacto: {
            avaliacoes: { quantidade: 2, ids: ["feedback-1", "feedback-2"] },
            metas: { quantidade: 1, ids: ["meta-1"] },
            observacoes: { quantidade: 3, ids: ["obs-1", "obs-2", "obs-3"] },
            total: 6,
          },
        },
      ],
    });

    expect(html).toContain("Correção de período");
    expect(html).toContain("Gerente Fictício (matrícula 1)");
    expect(html).toContain("Adequação ao calendário oficial");
    expect(html).toContain("Período anterior:");
    expect(html).toContain("Novo período:");
    expect(html).toContain("2 avaliação(ões), 1 meta(s), 3 observação(ões) — total 6.");
    expect(html).not.toContain("feedback-1");
  });

  it("ordena tipos diferentes do evento mais recente para o mais antigo", () => {
    const html = renderizar("ENCERRADO", false, gerente, {
      encerramentos: [
        {
          data: "2026-05-01T10:00:00.000Z",
          encerradoComPendencias: false,
          quantidadePendencias: 0,
        },
      ],
      reaberturas: [
        {
          data: "2026-05-02T10:00:00.000Z",
          motivo: "Evento mais recente",
          autorNome: "Gerente Fictício",
          autorMatricula: 1,
        },
      ],
      correcoesPeriodo: [
        {
          data: "2026-04-30T10:00:00.000Z",
          autorNome: "Gerente Fictício",
          autorMatricula: 1,
          justificativa: "Evento mais antigo",
          periodoAnterior: {},
          novoPeriodo: { dataInicio: "2026-01-01", dataFim: "2026-06-30" },
          impacto: {
            avaliacoes: { quantidade: 0, ids: [] },
            metas: { quantidade: 0, ids: [] },
            observacoes: { quantidade: 0, ids: [] },
            total: 0,
          },
        },
      ],
    });

    expect(html.indexOf("Evento mais recente")).toBeLessThan(
      html.indexOf("Encerramento")
    );
    expect(html.indexOf("Encerramento")).toBeLessThan(
      html.indexOf("Evento mais antigo")
    );
  });

  it.each<[StatusCicloAvaliacao, boolean]>([
    ["ENCERRADO", false],
    ["CANCELADO", true],
  ])("mantém histórico consultável no estado %s", (status, mostrarCancelados) => {
    const cicloAntes: Partial<CicloAvaliacao> = {
      reaberturas: [
        {
          data: "2026-02-01T10:00:00.000Z",
          motivo: "Consulta histórica",
          autorNome: "Gerente Fictício",
          autorMatricula: 1,
        },
      ],
    };
    const html = renderizar(status, mostrarCancelados, gerente, cicloAntes);

    expect(html).toContain("Ver histórico");
    expect(html).toContain("Consulta histórica");
    expect(cicloAntes.reaberturas).toHaveLength(1);
  });
});
