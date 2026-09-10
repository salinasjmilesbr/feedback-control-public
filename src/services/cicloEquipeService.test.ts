import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import {
  criarArmazenamentoMemoria,
  lerAvaliacoesDoCiclo,
  registrarAvaliacoesDoCiclo,
  type ArmazenamentoCutover,
} from "../infrastructure/supabase/avaliacoes/cutover";
import { criarCutoverAvaliacoes } from "./avaliacoesSoberanas/cutoverAvaliacoesService";
import type {
  AvaliacaoSoberana,
  RepositorioAvaliacoes,
} from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { getColaboradores } from "./colaboradorStorage";
import {
  analisarPendenciasDoCiclo,
  concluirAvaliacoesNoEncerramentoDoCiclo,
  criarAvaliacoesDoCicloAtivado,
  excluirAvaliacoesVaziasDoCiclo,
  getPainelCiclo,
  type DependenciasCicloEquipe,
} from "./cicloEquipeService";

/**
 * F5-06 (Issue #103) — CICLO SOBERANO.
 *
 * A criação automática na ativação e a conclusão no encerramento deixaram de
 * escrever no `localStorage`: ambas falam com o PostgreSQL pelo caminho
 * soberano. Os testes verificam:
 *
 * - a criação automática DELEGA ao servidor e não cria registro local;
 * - o legado existente continua contando como "já existe" (não é duplicado);
 * - o encerramento conclui no servidor e NÃO recalcula nota no frontend;
 * - o cleanup da exclusão de ciclo é fail-closed sobre o acervo somente leitura.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO_POSTGRES = "22222222-2222-4222-8222-222222222222";
const CHAVE_LEGADO = "feedback-control-feedbacks";

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
const avaliado: Colaborador = {
  matricula: 2,
  status: "ATIVO",
  nome: "Pessoa Avaliada",
  email: "avaliado@example.com",
  cargo: "Consultor",
  area: "Área fictícia",
  funcao: "CONSULTOR",
  gestorDiretoMatricula: gerente.matricula,
  respondePara: gerente.nome,
};
const ciclo: CicloAvaliacao = {
  id: "ciclo-cancelada",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};
const cancelada: Feedback = {
  id: "avaliacao-cancelada",
  colaboradorId: avaliado.matricula,
  colaboradorNome: avaliado.nome,
  status: "CANCELADA",
  data: "2026-01-10T00:00:00.000Z",
  ano: 2026,
  ciclo: 1,
  notaMedia: 0,
  competencias: [],
  criteriosDetalhados: [
    {
      criterioId: "criterio",
      criterioNome: "Critério",
      nota: 0,
      observacaoGerente: "",
      observacaoCoordenador: "",
      subcriterios: [
        {
          nome: "Subcritério",
          notaGerente: 0,
          notaCoordenador: 0,
          notaColegiado: 0,
          notaFinal: 0,
        },
      ],
    },
  ],
};

const avaliacaoSoberana = (
  status: string,
  id: string
): AvaliacaoSoberana => ({
  id,
  organizationId: ORG,
  cycleId: CICLO_POSTGRES,
  evaluatedCollaboratorId: "44444444-4444-4444-8444-444444444444",
  status,
  notaMedia: null,
  dataConclusao: null,
  encerradaComPendencias: false,
});

function repositorioFalso(
  comportamentos: Partial<RepositorioAvaliacoes> = {}
): RepositorioAvaliacoes & { readonly chamadas: string[] } {
  const chamadas: string[] = [];
  let sequencia = 0;
  const base: RepositorioAvaliacoes = {
    // Cada criação devolve um id técnico DISTINTO (como o PostgreSQL faria):
    // ids repetidos esconderiam erros de livro-caixa e de contagem.
    criar: async () => {
      sequencia += 1;
      return {
        ok: true,
        data: `99999999-9999-4999-8999-${String(sequencia).padStart(12, "0")}`,
      };
    },
    ler: async () => ({ ok: true, data: avaliacaoSoberana("RASCUNHO", CICLO_POSTGRES) }),
    gravarNotas: async () => ({ ok: true, data: null }),
    gravarComentario: async () => ({ ok: true, data: null }),
    concluir: async () => ({ ok: true, data: null }),
    reabrir: async () => ({ ok: true, data: null }),
    cancelar: async () => ({ ok: true, data: null }),
    realinharParticipantes: async () => ({ ok: true, data: 0 }),
    transparenciaDoAvaliado: async () => {
      throw new Error("não usado neste teste");
    },
    painelParticipante: async () => {
      throw new Error("não usado neste teste");
    },
    resolverCiclo: async () => ({ ok: true, data: CICLO_POSTGRES }),
  };

  const instrumentado = Object.fromEntries(
    Object.entries({ ...base, ...comportamentos }).map(([nome, fn]) => [
      nome,
      async (...args: unknown[]) => {
        chamadas.push(nome);
        return (fn as (...a: unknown[]) => unknown)(...args);
      },
    ])
  ) as unknown as RepositorioAvaliacoes;

  return Object.assign(instrumentado, { chamadas });
}

function deps(
  comportamentos: Partial<RepositorioAvaliacoes> = {},
  armazenamento: ArmazenamentoCutover = criarArmazenamentoMemoria()
): DependenciasCicloEquipe & { readonly repositorio: RepositorioAvaliacoes & { readonly chamadas: string[] } } {
  const repositorio = repositorioFalso(comportamentos);
  return {
    organizationId: ORG,
    armazenamento,
    repositorio,
    criarCutover: () => criarCutoverAvaliacoes({ repositorio, armazenamento }),
  };
}

describe("cicloEquipeService com avaliação cancelada", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      "feedback-control-colaboradores",
      JSON.stringify([gerente, avaliado])
    );
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([ciclo]));
    localStorage.setItem(CHAVE_LEGADO, JSON.stringify([cancelada]));
  });

  it("oculta no painel por padrão e inclui com status explícito", () => {
    expect(getPainelCiclo(ciclo, gerente)).toEqual([]);

    const linhas = getPainelCiclo(ciclo, gerente, { incluirCanceladas: true });
    expect(linhas).toHaveLength(1);
    expect(linhas[0].situacao).toBe("CANCELADA");
    expect(linhas[0].possuiPendencias).toBe(false);
  });

  it("não gera pendência de encerramento", () => {
    expect(analisarPendenciasDoCiclo(ciclo)).toEqual([]);
  });

  it("não gera pendências para ciclo cancelado", () => {
    const cicloCancelado = { ...ciclo, status: "CANCELADO" as const };
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([cicloCancelado])
    );

    expect(analisarPendenciasDoCiclo(cicloCancelado)).toEqual([]);
  });

  it("encerramento de ciclo sem avaliação nova não chama o servidor nem escreve local", async () => {
    const legadoAntes = localStorage.getItem(CHAVE_LEGADO);
    const dependencias = deps();

    const resultado = await concluirAvaliacoesNoEncerramentoDoCiclo(
      ciclo,
      dependencias
    );

    expect(resultado).toEqual({ concluidas: 0, bloqueadas: 0 });
    expect(dependencias.repositorio.chamadas).toEqual([]);
    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
  });

  it("encerramento conclui no servidor as avaliações NOVAS do ciclo", async () => {
    const armazenamento = criarArmazenamentoMemoria();
    registrarAvaliacoesDoCiclo(ORG, 2026, 1, [CICLO_POSTGRES], armazenamento);
    const dependencias = deps({}, armazenamento);
    const legadoAntes = localStorage.getItem(CHAVE_LEGADO);

    const resultado = await concluirAvaliacoesNoEncerramentoDoCiclo(
      ciclo,
      dependencias
    );

    expect(resultado).toEqual({ concluidas: 1, bloqueadas: 0 });
    expect(dependencias.repositorio.chamadas).toEqual(["ler", "concluir"]);
    // Sem re-cálculo oficial no frontend e sem dual-write.
    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
  });

  it("encerramento NÃO reabre nem reconclui avaliação já concluída", async () => {
    const armazenamento = criarArmazenamentoMemoria();
    registrarAvaliacoesDoCiclo(ORG, 2026, 1, [CICLO_POSTGRES], armazenamento);
    const dependencias = deps(
      {
        ler: async () => ({
          ok: true,
          data: avaliacaoSoberana("CONCLUIDA", CICLO_POSTGRES),
        }),
      },
      armazenamento
    );

    const resultado = await concluirAvaliacoesNoEncerramentoDoCiclo(
      ciclo,
      dependencias
    );

    expect(resultado).toEqual({ concluidas: 0, bloqueadas: 0 });
    expect(dependencias.repositorio.chamadas).toEqual(["ler"]);
  });

  it("recusa do servidor na conclusão é contabilizada como bloqueada", async () => {
    const armazenamento = criarArmazenamentoMemoria();
    registrarAvaliacoesDoCiclo(ORG, 2026, 1, [CICLO_POSTGRES], armazenamento);
    const dependencias = deps(
      {
        concluir: async () => ({
          ok: false,
          error: { code: "CONFLICT", message: "incompleta" },
        }),
      },
      armazenamento
    );

    const resultado = await concluirAvaliacoesNoEncerramentoDoCiclo(
      ciclo,
      dependencias
    );

    expect(resultado).toEqual({ concluidas: 0, bloqueadas: 1 });
  });

  it("gera avaliação automática no SERVIDOR quando só existe cancelada no legado", async () => {
    const dependencias = deps();
    const legadoAntes = localStorage.getItem(CHAVE_LEGADO);

    const resultado = await criarAvaliacoesDoCicloAtivado(ciclo, dependencias);

    // Uma criação soberana por colaborador elegível; nenhuma avaliação é
    // criada no acervo legado (sem dual-write).
    expect(resultado.criadas).toBeGreaterThan(0);
    expect(resultado.existentes).toBe(0);
    expect(resultado.bloqueadas).toBe(0);
    expect(
      dependencias.repositorio.chamadas.filter((nome) => nome === "criar")
    ).toHaveLength(resultado.criadas);
    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
  });

  it("registra o id soberano no livro-caixa do ciclo (navegação, não autoridade)", async () => {
    // Este cenário precisa dos colaboradores REAIS (o cadastro de teste acima
    // tem apenas duas pessoas, das quais uma é gestora e não é elegível).
    localStorage.removeItem("feedback-control-colaboradores");
    const armazenamento = criarArmazenamentoMemoria();
    const dependencias = deps({}, armazenamento);

    const resultado = await criarAvaliacoesDoCicloAtivado(ciclo, dependencias);

    const ids = lerAvaliacoesDoCiclo(ORG, 2026, 1, armazenamento);
    expect(resultado.criadas).toBeGreaterThan(0);
    expect(ids).toHaveLength(resultado.criadas);
    // Somente ids TÉCNICOS (UUID) entram no livro-caixa.
    expect(ids.every((id) => /^[0-9a-f-]{36}$/i.test(id))).toBe(true);
  });

  it("mantém toda avaliação não cancelada do legado como existente (não duplica)", async () => {
    // Um registro legado por colaborador cadastrado: como a checagem legada
    // ocorre ANTES de qualquer chamada, nada deve ser criado nem resolvido.
    const legados = getColaboradores().map((colaborador, indice) => ({
      ...cancelada,
      id: `legado-${indice}`,
      colaboradorId: colaborador.matricula,
      status: "RASCUNHO" as const,
    }));
    localStorage.setItem(CHAVE_LEGADO, JSON.stringify(legados));
    const dependencias = deps();

    const resultado = await criarAvaliacoesDoCicloAtivado(ciclo, dependencias);

    expect(resultado.criadas).toBe(0);
    expect(resultado.existentes).toBeGreaterThan(0);
    expect(dependencias.repositorio.chamadas).toEqual([]);
    expect(JSON.parse(localStorage.getItem(CHAVE_LEGADO) ?? "[]")).toHaveLength(
      legados.length
    );
  });

  it("recusa do servidor na criação conta como bloqueada (fail-closed)", async () => {
    const dependencias = deps({
      resolverCiclo: async () => ({
        ok: false,
        error: { code: "NOT_FOUND", message: "ciclo ausente" },
      }),
    });

    const resultado = await criarAvaliacoesDoCicloAtivado(ciclo, dependencias);

    expect(resultado.criadas).toBe(0);
    expect(resultado.bloqueadas).toBeGreaterThan(0);
  });

  it("sem caminho soberano configurado nada é criado localmente", async () => {
    const legadoAntes = localStorage.getItem(CHAVE_LEGADO);

    const resultado = await criarAvaliacoesDoCicloAtivado(ciclo, {
      organizationId: ORG,
      criarCutover: () => null,
    });

    expect(resultado.criadas).toBe(0);
    expect(resultado.bloqueadas).toBeGreaterThan(0);
    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
  });
});

describe("cleanup seguro na exclusão de ciclo", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      "feedback-control-colaboradores",
      JSON.stringify([gerente, avaliado])
    );
  });

  it.each(["ATIVO", "ENCERRADO"] as const)(
    "rejeita ciclo %s antes de remover avaliações relacionadas",
    (status) => {
      const cicloProtegido = { ...ciclo, status };
      const feedbackRelacionado = { ...cancelada, status: "RASCUNHO" as const };
      localStorage.setItem(
        "feedback-control-ciclos",
        JSON.stringify([cicloProtegido])
      );
      localStorage.setItem(
        CHAVE_LEGADO,
        JSON.stringify([feedbackRelacionado])
      );

      expect(() => excluirAvaliacoesVaziasDoCiclo(cicloProtegido)).toThrow(
        "Somente ciclos planejados podem ser excluídos fisicamente."
      );
      expect(
        JSON.parse(localStorage.getItem("feedback-control-ciclos") ?? "[]")
      ).toEqual([cicloProtegido]);
      expect(
        JSON.parse(localStorage.getItem(CHAVE_LEGADO) ?? "[]")
      ).toEqual([feedbackRelacionado]);
    }
  );

  it("rejeita ciclo planejado com avaliação preenchida e preserva tudo", () => {
    const cicloPlanejado = { ...ciclo, status: "PLANEJADO" as const };
    const preenchida = {
      ...cancelada,
      status: "RASCUNHO" as const,
      feedbackFinalGerente: "Conteúdo operacional",
    };
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([cicloPlanejado]));
    localStorage.setItem(CHAVE_LEGADO, JSON.stringify([preenchida]));

    expect(() => excluirAvaliacoesVaziasDoCiclo(cicloPlanejado)).toThrow(
      "dados preenchidos"
    );
    expect(
      JSON.parse(localStorage.getItem("feedback-control-ciclos") ?? "[]")
    ).toEqual([cicloPlanejado]);
    expect(
      JSON.parse(localStorage.getItem(CHAVE_LEGADO) ?? "[]")
    ).toEqual([preenchida]);
  });

  it("recusa apagar avaliação vazia do legado: acervo é somente leitura", () => {
    const cicloPlanejado = { ...ciclo, status: "PLANEJADO" as const };
    const vazia = { ...cancelada, status: "RASCUNHO" as const };
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([cicloPlanejado]));
    localStorage.setItem(CHAVE_LEGADO, JSON.stringify([vazia]));

    expect(() => excluirAvaliacoesVaziasDoCiclo(cicloPlanejado)).toThrow(
      /desativada/i
    );
    // O acervo permanece intacto: nenhuma exclusão física pelo produto.
    expect(JSON.parse(localStorage.getItem(CHAVE_LEGADO) ?? "[]")).toEqual([vazia]);
  });
});
