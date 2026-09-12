/**
 * F5-08 P6 (correção da auditoria GPT) — CUTOVER ESTRUTURAL DOS SERVIÇOS.
 *
 * Prova, em RUNTIME, que os caminhos produtivos de ciclo/metas deixaram de
 * decidir PAPEL/ELEGIBILIDADE/HIERARQUIA por estrutura local:
 *
 * 1. `progressoAvaliacao` não decide papel por `funcao` textual;
 * 2. `progressoAvaliacao` não decide cadeia por `gestorDiretoMatricula` local;
 * 3. `cicloEquipeService` não decide gerente/coordenador por estrutura local;
 * 4. `cicloEquipeService` não usa seed/`localStorage` como fallback estrutural;
 * 5. `metaStorage` não decide hierarquia/elegibilidade por estrutura local;
 * 6. sem evidência soberana ⇒ FAIL-CLOSED (e, com evidência, a decisão segue a
 *    projeção SOBERANA mesmo quando ela CONTRADIZ os dados locais);
 * 7. DEV/teste continuam funcionando, atrás do gate explícito;
 * 8. `permissaoAvaliacao` (mesma classe de decisão) também não concede papel
 *    por estrutura local.
 *
 * O gate estático que detecta a REINTRODUÇÃO desses caminhos vive em
 * `src/authorization/estruturaUiSeguranca.test.ts` (bloco P6).
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Meta } from "../types/Meta";
import type {
  PapelEstrutural,
  VinculoEstruturalSoberano,
} from "./projecaoEstruturalSoberana";

const ORG = "11111111-1111-4111-8111-111111111111";
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

/** Fixture LOCAL com estrutura completa (o que o P6 não aceita mais decidir). */
const gerente = pessoa(1, "GERENTE");
const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
const analista = pessoa(3, "ANALISTA", coordenador.matricula, [4]);
const colega = pessoa(4, "ANALISTA", coordenador.matricula);
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

function metaDe(colaborador: Colaborador, aprovacoes = {}): Meta {
  return {
    id: "meta-1",
    colaboradorMatricula: colaborador.matricula,
    colaboradorNome: colaborador.nome,
    cicloId: ciclo.id,
    ano: ciclo.ano,
    ciclo: ciclo.ciclo,
    tipo: "INDIVIDUAL",
    descricao: "Meta fictícia",
    kpi: "KPI fictício",
    valorAlvo: "1",
    status: "EM_ANDAMENTO",
    dataCriacao: "2026-01-02T00:00:00.000Z",
    dataUltimaAtualizacao: "2026-01-02T00:00:00.000Z",
    excluida: false,
    historico: [],
    ...aprovacoes,
  };
}

function vinculo(
  matricula: number,
  papel: PapelEstrutural,
  gestorSoberanoMatricula: number | null,
  extras: Partial<VinculoEstruturalSoberano> = {}
): VinculoEstruturalSoberano {
  return {
    matricula,
    papel,
    gestorSoberanoMatricula,
    cadeiaDeGestaoMatriculas: [],
    cadeiaConfiavel: true,
    colegiadoSoberanoMatriculas: [],
    usaEstruturaAvaliacao: false,
    ...extras,
  };
}

/** Projeção SOBERANA coerente com a estrutura real (gerente → coord → analista). */
function projecaoSoberana(criar: ProjecaoCriar) {
  return criar([
    vinculo(1, "GERENTE", null),
    vinculo(2, "COORDENADOR", 1, { cadeiaDeGestaoMatriculas: [1] }),
    vinculo(3, "OUTRO", 2, {
      cadeiaDeGestaoMatriculas: [2, 1],
      colegiadoSoberanoMatriculas: [4],
      usaEstruturaAvaliacao: true,
    }),
    vinculo(4, "OUTRO", 2, { cadeiaDeGestaoMatriculas: [2, 1] }),
  ]);
}

/**
 * Projeção SOBERANA que CONTRADIZ o cadastro local: o local diz GERENTE (1),
 * COORDENADOR (2) e ANALISTA (3) com colegiado (4); a soberana diz que a cadeia
 * de 3 passa por 4 (que é a RAIZ) e que NÃO existe papel de gerente/coordenador
 * nem estrutura de analista. Se a decisão seguir o local, o teste falha.
 */
function projecaoContraditoria(criar: ProjecaoCriar) {
  return criar([
    vinculo(4, "OUTRO", null),
    vinculo(3, "OUTRO", 4, {
      cadeiaDeGestaoMatriculas: [4],
      colegiadoSoberanoMatriculas: [],
      usaEstruturaAvaliacao: false,
    }),
  ]);
}

type ProjecaoCriar = (
  vinculos: readonly VinculoEstruturalSoberano[]
) => { readonly vinculos: ReadonlyMap<number, VinculoEstruturalSoberano> };

/** Carrega os módulos num contexto de PRODUÇÃO (fora do gate DEV). */
async function carregarProducao() {
  vi.stubEnv("DEV", false);
  vi.stubEnv("PROD", true);
  vi.stubEnv("VITE_APP_ENV", "production");
  return carregarModulos();
}

/** Carrega os módulos no contexto DEV do Vite (fixtures fictícias). */
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
  const projecao = await import("./projecaoEstruturalSoberana");
  return { progresso, cicloEquipe, metas, permissao, projecao };
}

beforeEach(() => {
  vi.resetModules();
  instalarLocalStorageEmMemoria();
  localStorage.setItem(CHAVE_COLABORADORES, JSON.stringify(mundo));
  localStorage.setItem(CHAVE_CICLOS, JSON.stringify([ciclo]));
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

describe("F5-08 P6 — produção: papel/elegibilidade sem estrutura local", () => {
  it("progressoAvaliacao NÃO decide papel por `funcao` nem por cadeia local (fail-closed)", async () => {
    const { progresso, projecao } = await carregarProducao();

    // Mesmo com a estrutura local completa E todas as notas preenchidas, a
    // avaliação NÃO é declarada completa em produção.
    const resultado = progresso.calcularProgressoAvaliacao(
      criterios,
      notasCompletas,
      votosCompletos,
      analista,
      mundo,
      "feedback do gerente",
      "feedback do coordenador"
    );

    expect(resultado.gerente.necessario).toBe(false);
    expect(resultado.coordenador.necessario).toBe(false);
    expect(resultado.colegiado.necessario).toBe(false);
    expect(resultado.completo).toBe(false);
    expect(resultado.pendencias).toContain(
      projecao.ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL
    );
  });

  it("progressoAvaliacao segue a projeção SOBERANA mesmo quando ela contradiz o cadastro local", async () => {
    const { progresso, projecao } = await carregarProducao();

    const coerente = progresso.calcularProgressoAvaliacao(
      criterios,
      notasCompletas,
      votosCompletos,
      analista,
      mundo,
      "ok",
      "ok",
      projecaoSoberana(projecao.criarProjecaoEstrutural)
    );
    expect(coerente.gerente.necessario).toBe(true);
    expect(coerente.coordenador.necessario).toBe(true);
    expect(coerente.colegiado.necessario).toBe(true);
    expect(coerente.completo).toBe(true);

    // A projeção contraditória NÃO tem GERENTE na cadeia e o "gestor direto"
    // (4) é OUTRO ⇒ nenhum papel exigido, apesar de o cadastro local dizer
    // GERENTE/COORDENADOR/colegiado.
    const contraditorio = progresso.calcularProgressoAvaliacao(
      criterios,
      notasCompletas,
      votosCompletos,
      analista,
      mundo,
      "ok",
      "ok",
      projecaoContraditoria(projecao.criarProjecaoEstrutural)
    );
    expect(contraditorio.gerente.necessario).toBe(false);
    expect(contraditorio.coordenador.necessario).toBe(false);
    expect(contraditorio.colegiado.necessario).toBe(false);
    expect(contraditorio.completo).toBe(true);
  });

  it("cicloEquipeService não expõe painel nem pendências por alcance local", async () => {
    const { cicloEquipe } = await carregarProducao();

    // Sem projeção soberana: painel VAZIO (o alcance local não é autoridade) e
    // pendência explícita de ESTRUTURA — nunca "tudo completo".
    expect(cicloEquipe.getPainelCiclo(ciclo, gerente)).toEqual([]);

    const pendencias = cicloEquipe.analisarPendenciasDoCiclo(ciclo);
    expect(pendencias).toHaveLength(1);
    expect(pendencias[0]?.papel).toBe("Estrutura");
    expect(pendencias[0]?.detalhes?.join(" ")).toContain("fail-closed");

    // Com projeção soberana, o painel volta a ser derivado da ESTRUTURA.
    const projecaoModulo = await import("./projecaoEstruturalSoberana");
    const linhas = cicloEquipe.getPainelCiclo(ciclo, gerente, {}, projecaoSoberana(projecaoModulo.criarProjecaoEstrutural));
    expect(linhas.map((linha) => linha.colaborador.matricula)).toEqual([2, 3, 4]);
  });

  it("cicloEquipeService não usa seed/localStorage como fallback estrutural (recusa explícita)", async () => {
    const { cicloEquipe, projecao } = await carregarProducao();

    const chamadas: string[] = [];
    const deps = {
      organizationId: ORG,
      criarCutover: () => {
        chamadas.push("criarCutover");
        return null;
      },
    };

    await expect(
      cicloEquipe.criarAvaliacoesDoCicloAtivado(ciclo, deps)
    ).rejects.toThrow(projecao.ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL);

    // Nem o caminho soberano é acionado: nada é criado, nada é lido.
    expect(chamadas).toEqual([]);
    expect(localStorage.getItem(CHAVE_METAS)).toBeNull();

    // O mesmo vale quando o cadastro local nem existe (seed NÃO é fallback).
    localStorage.removeItem(CHAVE_COLABORADORES);
    await expect(
      cicloEquipe.criarAvaliacoesDoCicloAtivado(ciclo, deps)
    ).rejects.toThrow(projecao.ERRO_ESTRUTURA_SOBERANA_INDISPONIVEL);
    expect(chamadas).toEqual([]);
  });

  it("metaStorage não decide hierarquia/elegibilidade por estrutura local", async () => {
    const { metas } = await carregarProducao();

    // Relação de aprovação: gestor direto e raiz locais NÃO concedem nada.
    expect(
      metas.podeAprovarMetaNoCiclo(coordenador, analista, mundo, ciclo)
    ).toBe(false);
    expect(metas.podeAprovarMetaNoCiclo(gerente, analista, mundo, ciclo)).toBe(
      false
    );

    // Exigência de aprovação do coordenador: fail-closed (não é possível provar
    // que NÃO é exigida).
    expect(metas.metaExigeAprovacaoCoordenador(analista, mundo, ciclo)).toBe(
      true
    );

    // Meta sem aprovações e meta com apenas a aprovação do gerente NÃO estão
    // aprovadas (a do coordenador não é dispensada por dado local).
    expect(metas.metaEstaAprovada(metaDe(analista), analista, mundo)).toBe(false);
    expect(
      metas.metaEstaAprovada(
        metaDe(analista, {
          aprovacaoGerente: {
            matricula: gerente.matricula,
            nome: gerente.nome,
            data: "2026-01-03T00:00:00.000Z",
          },
        }),
        analista,
        mundo
      )
    ).toBe(false);

    // Mutação própria de meta: o engine nega (mundo local não é provider de
    // produção) e NADA é gravado.
    expect(() =>
      metas.criarMeta(analista, ciclo, "INDIVIDUAL", "Nova", "KPI", "1")
    ).toThrow();
    expect(localStorage.getItem(CHAVE_METAS)).toBeNull();
  });

  it("metaStorage segue a projeção SOBERANA (e não o `funcao` local) na relação de aprovação", async () => {
    const { metas, projecao } = await carregarProducao();

    // Soberano coerente: gestor direto é COORDENADOR e a raiz é o gerente.
    const coerente = projecaoSoberana(projecao.criarProjecaoEstrutural);
    expect(
      metas.podeAprovarMetaNoCiclo(coordenador, analista, mundo, ciclo, coerente)
    ).toBe(true);
    expect(
      metas.podeAprovarMetaNoCiclo(gerente, analista, mundo, ciclo, coerente)
    ).toBe(true);
    expect(
      metas.metaExigeAprovacaoCoordenador(analista, mundo, ciclo, coerente)
    ).toBe(true);

    // Soberano contraditório: o cadastro local diz COORDENADOR, a estrutura
    // soberana diz OUTRO ⇒ a aprovação do coordenador NÃO é exigida.
    const contraditorio = projecaoContraditoria(projecao.criarProjecaoEstrutural);
    expect(
      metas.podeAprovarMetaNoCiclo(coordenador, analista, mundo, ciclo, contraditorio)
    ).toBe(false);
    expect(
      metas.podeAprovarMetaNoCiclo(gerente, analista, mundo, ciclo, contraditorio)
    ).toBe(false);
    expect(
      metas.metaExigeAprovacaoCoordenador(analista, mundo, ciclo, contraditorio)
    ).toBe(false);
  });

  it("permissaoAvaliacao não concede papel por estrutura local (fail-closed)", async () => {
    const { permissao, projecao } = await carregarProducao();

    const semProjecao = permissao.obterPermissoesAvaliacao(
      coordenador,
      analista,
      mundo,
      ciclo
    );
    expect(semProjecao.podeAvaliar).toBe(false);
    expect(semProjecao.papeisPermitidos).toEqual([]);

    // Com a projeção soberana contraditória, o papel segue a ESTRUTURA (e não o
    // `funcao`/`gestorDiretoMatricula` local).
    const contraditorio = permissao.obterPermissoesAvaliacao(
      coordenador,
      analista,
      mundo,
      ciclo,
      projecaoContraditoria(projecao.criarProjecaoEstrutural)
    );
    expect(contraditorio.podeAvaliarComoCoordenador).toBe(false);
    expect(contraditorio.podeAvaliarComoColegiado).toBe(false);
    expect(contraditorio.podeAvaliar).toBe(false);

    const coerente = permissao.obterPermissoesAvaliacao(
      coordenador,
      analista,
      mundo,
      ciclo,
      projecaoSoberana(projecao.criarProjecaoEstrutural)
    );
    expect(coerente.podeAvaliarComoCoordenador).toBe(true);
    expect(coerente.podeAvaliar).toBe(true);
  });
});

describe("F5-08 P6 — DEV: fixtures continuam atrás do gate explícito", () => {
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
    expect(metas.metaExigeAprovacaoCoordenador(analista, mundo, ciclo)).toBe(
      true
    );

    expect(
      permissao.obterPermissoesAvaliacao(coordenador, analista, mundo, ciclo)
        .podeAvaliarComoCoordenador
    ).toBe(true);

    expect(cicloEquipe.getPainelCiclo(ciclo, gerente).length).toBeGreaterThan(0);

    // A mutação própria de meta continua possível em DEV (fixture), sem
    // qualquer escrita fora do domínio de metas.
    metas.criarMeta(analista, ciclo, "INDIVIDUAL", "Nova", "KPI", "1");
    expect(localStorage.getItem(CHAVE_METAS)).toContain("Nova");
  });
});
