/**
 * F5-08 P6 (correção da auditoria GPT) — CONSUMIDORES com estrutura SOBERANA.
 *
 * Prova o contrato das decisões de ciclo/meta quando recebem uma estrutura
 * soberana EXPLÍCITA (UUID canônico + ponte de compatibilidade):
 *
 * 1. com evidência estrutural as decisões funcionam (não é bloqueio cego);
 * 2. a estrutura soberana VENCE o cadastro local quando eles divergem;
 * 3. sem evidência (produção, nada carregado) tudo é fail-closed;
 * 4. em DEV, a fixture local continua funcionando atrás do gate explícito.
 *
 * O produtor real (leitura RLS + porta F5-07, sem injeção manual) é provado em
 * `estruturaSoberanaCliente.test.ts`.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import {
  criarProjecaoEstrutural,
  type VinculoEstruturalSoberano,
} from "./projecaoEstruturalSoberana";
import {
  criarEstruturaDoCliente,
  redefinirEstruturaSoberana,
  type EstruturaSoberanaDoCliente,
} from "./estruturaSoberanaCliente";

const CHAVE_COLABORADORES = "feedback-control-colaboradores";
const CHAVE_CICLOS = "feedback-control-ciclos";
const CHAVE_METAS = "feedback-control-metas";

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number,
  colegiado: readonly number[] = []
): Colaborador {
  return {
    matricula,
    status: "ATIVO",
    nome: `Pessoa ${matricula}`,
    email: `${matricula}@example.com`,
    cargo: funcao ?? "Sem função",
    area: "Área fictícia",
    funcao,
    gestorDiretoMatricula,
    avaliadoresColegiadoMatriculas: [...colegiado],
    respondePara: "",
  };
}

/** Cadastro LOCAL (legado) — nunca é a fonte estrutural em produção. */
const gerente = pessoa(1, "GERENTE");
const coordenador = pessoa(2, "COORDENADOR", 1);
const analista = pessoa(3, "ANALISTA", 2, [4]);
const colega = pessoa(4, "ANALISTA", 2);
const mundo = [gerente, coordenador, analista, colega];

const ciclo: CicloAvaliacao = {
  id: "ciclo-ativo",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataInicio: "2026-01-01",
  dataFim: "2026-12-31",
  quantidadeMetasNegocio: 3,
  quantidadeMetasIndividuais: 3,
  dataCriacao: "2025-12-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};

const criterios = [{ id: "c1", subcriterios: ["s1"] }];
const notasCompletas = {
  c1: { notas: { s1: { gerente: 5, coordenador: 5, colegiado: 5 } } },
};
const votosCompletos = { c1: { s1: { 4: 5 } } };

// UUIDs canônicos (identidade estrutural).
const ID_GERENTE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ID_COORD = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ID_ANALISTA = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const ID_COLEGA = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

function posicaoDe(collaboratorId: string): string {
  return `pos-${collaboratorId}`;
}

/** Vínculo com a cadeia EXPLÍCITA (UUID), do gestor direto à raiz. */
function vinculo(
  collaboratorId: string,
  cadeia: readonly string[],
  extras: {
    readonly colegiado?: readonly string[];
    readonly gestorTemSuperior?: boolean;
    readonly cadeiaConfiavel?: boolean;
  } = {}
): VinculoEstruturalSoberano {
  const gestor = cadeia[0] ?? null;
  return {
    collaboratorId,
    posicaoId: posicaoDe(collaboratorId),
    gestorSoberanoPositionId: gestor === null ? null : posicaoDe(gestor),
    gestorSoberanoCollaboratorId: gestor,
    cadeiaDeGestaoPositionIds: cadeia.map(posicaoDe),
    cadeiaDeGestaoCollaboratorIds: cadeia,
    cadeiaConfiavel: extras.cadeiaConfiavel ?? true,
    gestorTemSuperior: extras.gestorTemSuperior ?? cadeia.length > 1,
    colegiadoSoberanoCollaboratorIds: [...(extras.colegiado ?? [])],
  };
}

function estruturaSoberana(
  vinculos: readonly VinculoEstruturalSoberano[],
  ponte: readonly (readonly [number, string])[]
): EstruturaSoberanaDoCliente {
  return criarEstruturaDoCliente({
    projecao: criarProjecaoEstrutural(vinculos),
    ponteMatriculas: new Map(ponte.map(([matricula, id]) => [String(matricula), id])),
    matriculaLegada: new Map(ponte.map(([matricula, id]) => [id, matricula])),
  });
}

const PONTE = [
  [1, ID_GERENTE],
  [2, ID_COORD],
  [3, ID_ANALISTA],
  [4, ID_COLEGA],
] as const;

/** Estrutura coerente: gerente ← coordenação ← analista (colegiado = 4). */
function estruturaCoerente(): EstruturaSoberanaDoCliente {
  return estruturaSoberana(
    [
      vinculo(ID_GERENTE, []),
      vinculo(ID_COORD, [ID_GERENTE], { gestorTemSuperior: false }),
      vinculo(ID_ANALISTA, [ID_COORD, ID_GERENTE], { colegiado: [ID_COLEGA] }),
      vinculo(ID_COLEGA, [ID_COORD, ID_GERENTE]),
    ],
    PONTE
  );
}

/** Estrutura que CONTRADIZ o cadastro local: o analista (3) responde a 4, que é
 * a RAIZ da cadeia; o "gerente local" (1) e o "coordenador local" (2) não
 * participam da hierarquia soberana do analista. */
function estruturaContraditoria(): EstruturaSoberanaDoCliente {
  return estruturaSoberana(
    [
      vinculo(ID_GERENTE, []),
      vinculo(ID_COLEGA, [], { gestorTemSuperior: false }),
      vinculo(ID_ANALISTA, [ID_COLEGA], { gestorTemSuperior: false }),
    ],
    PONTE
  );
}

async function carregarProducao() {
  vi.stubEnv("DEV", false);
  vi.stubEnv("PROD", true);
  vi.stubEnv("VITE_APP_ENV", "production");
  return carregarModulos();
}

async function carregarDev() {
  vi.stubEnv("DEV", true);
  vi.stubEnv("PROD", false);
  vi.stubEnv("VITE_APP_ENV", "development");
  return carregarModulos();
}

async function carregarModulos() {
  const progresso = await import("./progressoAvaliacao");
  const cicloEquipe = await import("./cicloEquipeService");
  const metas = await import("./metaStorage");
  const permissao = await import("./permissaoAvaliacao");
  return { progresso, cicloEquipe, metas, permissao };
}

beforeEach(() => {
  vi.resetModules();
  redefinirEstruturaSoberana();
  instalarLocalStorageEmMemoria();
  localStorage.setItem(CHAVE_COLABORADORES, JSON.stringify(mundo));
  localStorage.setItem(CHAVE_CICLOS, JSON.stringify([ciclo]));
});

afterEach(() => {
  vi.unstubAllEnvs();
  redefinirEstruturaSoberana();
  vi.resetModules();
});

describe("F5-08 P6 — consumidores com estrutura soberana explícita (UUID)", () => {
  it("com evidência estrutural as decisões funcionam (ciclo, metas, painel, permissões)", async () => {
    const { progresso, cicloEquipe, metas, permissao } = await carregarProducao();
    const estrutura = estruturaCoerente();

    const resultado = progresso.calcularProgressoAvaliacao(
      criterios,
      notasCompletas,
      votosCompletos,
      analista,
      mundo,
      "ok",
      "ok",
      estrutura
    );
    expect(resultado.gerente.necessario).toBe(true);
    expect(resultado.coordenador.necessario).toBe(true);
    expect(resultado.colegiado.necessario).toBe(true);
    expect(resultado.completo).toBe(true);

    expect(
      cicloEquipe
        .getPainelCiclo(ciclo, gerente, {}, estrutura)
        .map((linha) => linha.colaborador.matricula)
    ).toEqual([2, 3, 4]);

    expect(
      metas.podeAprovarMetaNoCiclo(coordenador, analista, mundo, ciclo, estrutura)
    ).toBe(true);
    expect(
      metas.podeAprovarMetaNoCiclo(gerente, analista, mundo, ciclo, estrutura)
    ).toBe(true);
    expect(
      metas.metaExigeAprovacaoCoordenador(analista, mundo, ciclo, estrutura)
    ).toBe(true);

    const permissoes = permissao.obterPermissoesAvaliacao(
      coordenador,
      analista,
      mundo,
      ciclo,
      estrutura
    );
    expect(permissoes.podeAvaliarComoCoordenador).toBe(true);
    expect(permissoes.podeAvaliar).toBe(true);
  });

  it("a estrutura SOBERANA vence o cadastro local quando divergem", async () => {
    const { progresso, cicloEquipe, metas, permissao } = await carregarProducao();
    const contraditoria = estruturaContraditoria();

    const resultado = progresso.calcularProgressoAvaliacao(
      criterios,
      notasCompletas,
      votosCompletos,
      analista,
      mundo,
      "ok",
      "ok",
      contraditoria
    );
    expect(resultado.gerente.necessario).toBe(true);
    // O cadastro local diz que o gestor direto é COORDENADOR; a estrutura
    // soberana diz que ele é a RAIZ da cadeia ⇒ nenhum papel de coordenador.
    expect(resultado.coordenador.necessario).toBe(false);

    // Quem aprova: o gestor direto SOBERANO (4), que também é a raiz — nunca o
    // 2 (que o cadastro local aponta como gestor) nem o 1.
    expect(
      metas.podeAprovarMetaNoCiclo(coordenador, analista, mundo, ciclo, contraditoria)
    ).toBe(false);
    expect(
      metas.podeAprovarMetaNoCiclo(colega, analista, mundo, ciclo, contraditoria)
    ).toBe(true);
    expect(
      metas.podeAprovarMetaNoCiclo(gerente, analista, mundo, ciclo, contraditoria)
    ).toBe(false);

    // Painel do gerente (1) segue o alcance SOBERANO: ninguém reporta a ele.
    expect(cicloEquipe.getPainelCiclo(ciclo, gerente, {}, contraditoria)).toEqual([]);

    // O gestor direto soberano (4) é a RAIZ da cadeia do analista ⇒ avalia como
    // gerente responsável; o "gerente local" (1) NÃO é responsável por nada.
    const permissoesDoColega = permissao.obterPermissoesAvaliacao(
      colega,
      analista,
      mundo,
      ciclo,
      contraditoria
    );
    expect(permissoesDoColega.podeAvaliarComoGerente).toBe(true);
    expect(permissoesDoColega.podeAvaliarComoCoordenador).toBe(false);

    const permissoesDoGerenteLocal = permissao.obterPermissoesAvaliacao(
      gerente,
      analista,
      mundo,
      ciclo,
      contraditoria
    );
    expect(permissoesDoGerenteLocal.podeAvaliar).toBe(false);
  });

  it("sem estrutura (produção, nada carregado) é fail-closed", async () => {
    const { progresso, cicloEquipe, metas, permissao } = await carregarProducao();

    const resultado = progresso.calcularProgressoAvaliacao(
      criterios,
      notasCompletas,
      votosCompletos,
      analista,
      mundo,
      "ok",
      "ok"
    );
    expect(resultado.completo).toBe(false);
    expect(resultado.pendencias.join(" ")).toContain("fail-closed");

    expect(cicloEquipe.getPainelCiclo(ciclo, gerente)).toEqual([]);
    expect(cicloEquipe.analisarPendenciasDoCiclo(ciclo)[0]?.papel).toBe("Estrutura");

    expect(
      metas.podeAprovarMetaNoCiclo(coordenador, analista, mundo, ciclo)
    ).toBe(false);
    expect(metas.metaExigeAprovacaoCoordenador(analista, mundo, ciclo)).toBe(true);
    expect(
      metas.metaEstaAprovada(
        {
          id: "meta-1",
          colaboradorMatricula: analista.matricula,
          colaboradorNome: analista.nome,
          cicloId: ciclo.id,
          ano: ciclo.ano,
          ciclo: ciclo.ciclo,
          tipo: "INDIVIDUAL",
          descricao: "Meta fictícia",
          kpi: "KPI",
          valorAlvo: "1",
          status: "EM_ANDAMENTO",
          dataCriacao: "2026-01-02T00:00:00.000Z",
          dataUltimaAtualizacao: "2026-01-02T00:00:00.000Z",
          excluida: false,
          historico: [],
        },
        analista,
        mundo
      )
    ).toBe(false);

    expect(
      permissao.obterPermissoesAvaliacao(coordenador, analista, mundo, ciclo).podeAvaliar
    ).toBe(false);

    expect(() =>
      metas.criarMeta(analista, ciclo, "INDIVIDUAL", "Nova", "KPI", "1")
    ).toThrow();
    expect(localStorage.getItem(CHAVE_METAS)).toBeNull();
  });
});

describe("F5-08 P6 — DEV: fixture local atrás do gate explícito", () => {
  it("o mundo local decide papel/elegibilidade apenas em DEV", async () => {
    const { progresso, cicloEquipe, metas, permissao } = await carregarDev();

    const resultado = progresso.calcularProgressoAvaliacao(
      criterios,
      notasCompletas,
      votosCompletos,
      analista,
      mundo,
      "ok",
      "ok"
    );
    expect(resultado.gerente.necessario).toBe(true);
    expect(resultado.coordenador.necessario).toBe(true);
    expect(resultado.colegiado.necessario).toBe(true);
    expect(resultado.completo).toBe(true);

    expect(
      metas.podeAprovarMetaNoCiclo(coordenador, analista, mundo, ciclo)
    ).toBe(true);
    expect(metas.metaExigeAprovacaoCoordenador(analista, mundo, ciclo)).toBe(true);
    expect(
      permissao.obterPermissoesAvaliacao(coordenador, analista, mundo, ciclo)
        .podeAvaliarComoCoordenador
    ).toBe(true);

    expect(cicloEquipe.getPainelCiclo(ciclo, gerente).length).toBeGreaterThan(0);

    metas.criarMeta(analista, ciclo, "INDIVIDUAL", "Nova", "KPI", "1");
    expect(localStorage.getItem(CHAVE_METAS)).toContain("Nova");
  });
});
