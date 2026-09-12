/**
 * F5-08 P6 (correção da auditoria GPT) — PRODUTOR e PONTE da estrutura soberana.
 *
 * Prova que a estrutura consumida pelos domínios legados de ciclo/meta é
 * obtida pelo caminho NORMAL já existente (leitura RLS do P4 + porta de
 * colaboradores F5-07), sem injeção manual:
 *
 * 1. o carregamento usa as portas soberanas e publica a projeção por UUID;
 * 2. a matrícula é apenas PONTE de compatibilidade (não é chave estrutural);
 * 3. ciclo/metas/painel/permissões funcionam em produção com a estrutura
 *    soberana carregada — sem parâmetro manual;
 * 4. falha real do Supabase/porta ⇒ fail-closed (nada de `localStorage`/seed);
 * 5. a estrutura SOBERANA vence o cadastro local quando eles divergem;
 * 6. DEV continua isolado atrás do gate explícito.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { ColaboradorSoberano } from "./colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { ServiceColaboradores } from "./colaboradoresSoberanos/serviceColaboradores";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import { redefinirAcessoColaboradoresSoberanos } from "./colaboradoresSoberanos/acessoColaboradoresSoberanos";
import {
  alcanceLegado,
  collaboratorIdDoLegado,
  matriculaLegadaDoCollaborator,
  matriculaLegadaNumerica,
  visaoEstruturalLegada,
} from "./estruturaSoberanaCliente";

const ORG = "11111111-1111-4111-8111-111111111111";
const INICIO = "2026-01-01T00:00:00.000Z";
const CHAVE_COLABORADORES = "feedback-control-colaboradores";
const CHAVE_CICLOS = "feedback-control-ciclos";

const UUID_GERENTE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const UUID_COORD = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const UUID_ANALISTA = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const UUID_COLEGA = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

const POS_GERENTE = "11111111-1111-4111-8111-111111111111";
const POS_COORD = "22222222-2222-4222-8222-222222222222";
const POS_ANALISTA = "33333333-3333-4333-8333-333333333333";
const POS_COLEGA = "44444444-4444-4444-8444-444444444444";

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

const gerenteLocal = pessoa(1, "GERENTE");
const coordenadorLocal = pessoa(2, "COORDENADOR", 1);
const analistaLocal = pessoa(3, "ANALISTA", 2, [4]);
const colegaLocal = pessoa(4, "ANALISTA", 2);
const mundoLocal = [gerenteLocal, coordenadorLocal, analistaLocal, colegaLocal];

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

function colaboradorSoberano(
  collaboratorId: string,
  matricula: string,
  managerCollaboratorId: string | null
): ColaboradorSoberano {
  return {
    collaboratorId,
    matricula,
    fullName: `Pessoa ${matricula}`,
    email: `${matricula}@example.com`,
    status: "active",
    admissionDate: null,
    unitId: null,
    unitName: null,
    jobRoleCode: null,
    jobRoleName: null,
    seniorityName: null,
    managerCollaboratorId,
    managerFullName: null,
    version: 1,
  };
}

/** Estrutura SOBERANA coerente com o mundo local (mesma hierarquia). */
function estruturaSoberanaCoerente(): EstruturaSoberana {
  return {
    unidades: [],
    periodosParent: [],
    posicoes: [POS_GERENTE, POS_COORD, POS_ANALISTA, POS_COLEGA].map((posicaoId) => ({
      posicaoId,
      unitId: "99999999-9999-4999-8999-999999999999",
      jobRoleId: "88888888-8888-4888-8888-888888888888",
      seniorityLevelId: null,
      validFrom: INICIO,
      validTo: null,
      version: 1,
    })),
    reportingLines: [
      {
        reportingLineId: "r-1",
        subordinatePositionId: POS_COORD,
        managerPositionId: POS_GERENTE,
        motivo: "fixture",
        validFrom: INICIO,
        validTo: null,
        version: 1,
      },
      {
        reportingLineId: "r-2",
        subordinatePositionId: POS_ANALISTA,
        managerPositionId: POS_COORD,
        motivo: "fixture",
        validFrom: INICIO,
        validTo: null,
        version: 1,
      },
      {
        reportingLineId: "r-3",
        subordinatePositionId: POS_COLEGA,
        managerPositionId: POS_COORD,
        motivo: "fixture",
        validFrom: INICIO,
        validTo: null,
        version: 1,
      },
    ],
    ocupacoes: [
      { ocupacaoId: "o-1", collaboratorId: UUID_GERENTE, posicaoId: POS_GERENTE, validFrom: INICIO, validTo: null, version: 1 },
      { ocupacaoId: "o-2", collaboratorId: UUID_COORD, posicaoId: POS_COORD, validFrom: INICIO, validTo: null, version: 1 },
      { ocupacaoId: "o-3", collaboratorId: UUID_ANALISTA, posicaoId: POS_ANALISTA, validFrom: INICIO, validTo: null, version: 1 },
      { ocupacaoId: "o-4", collaboratorId: UUID_COLEGA, posicaoId: POS_COLEGA, validFrom: INICIO, validTo: null, version: 1 },
    ],
    cargos: [],
    senioridades: [],
    colegiados: [
      {
        colegiadoId: "c-1",
        collaboratorId: UUID_ANALISTA,
        validFrom: INICIO,
        validTo: null,
        version: 1,
        membroIds: [UUID_COLEGA],
      },
    ],
    colaboradores: [],
  };
}

function operacoes(parcial: Partial<ServiceColaboradores>): ServiceColaboradores {
  return parcial as unknown as ServiceColaboradores;
}

function servicoSoberano(entrada: {
  readonly estrutura: EstruturaSoberana;
  readonly colaboradores: readonly ColaboradorSoberano[];
}): ServiceColaboradores {
  return operacoes({
    lerEstrutura: async () => ({ ok: true, dados: entrada.estrutura }),
    listar: async () => ({ ok: true, dados: entrada.colaboradores }),
  });
}

const colaboradoresSoberanos = [
  colaboradorSoberano(UUID_GERENTE, "1", null),
  colaboradorSoberano(UUID_COORD, "2", UUID_GERENTE),
  colaboradorSoberano(UUID_ANALISTA, "3", UUID_COORD),
  colaboradorSoberano(UUID_COLEGA, "4", UUID_COORD),
];

/**
 * Carrega o módulo do cliente (instância NOVA após `resetModules`) e devolve o
 * produtor já acionado — o teste nunca mistura instâncias de módulo.
 */
async function carregarProducao(servico: ServiceColaboradores) {
  const modulo = await import("./estruturaSoberanaCliente");
  const estado = await modulo.carregarEstruturaSoberana(
    { organizationId: ORG },
    { operacoes: servico }
  );
  return { modulo, estado };
}

beforeEach(() => {
  vi.resetModules();
  instalarLocalStorageEmMemoria();
  redefinirAcessoColaboradoresSoberanos();
  localStorage.setItem(CHAVE_COLABORADORES, JSON.stringify(mundoLocal));
  localStorage.setItem(CHAVE_CICLOS, JSON.stringify([ciclo]));
});

afterEach(() => {
  vi.unstubAllEnvs();
  redefinirAcessoColaboradoresSoberanos();
  vi.resetModules();
});

describe("F5-08 P6 — produtor soberano (caminho normal, sem injeção manual)", () => {
  it("carrega a estrutura pelas portas existentes e publica a projeção por UUID", async () => {
    vi.stubEnv("DEV", false);
    vi.stubEnv("PROD", true);
    vi.stubEnv("VITE_APP_ENV", "production");

    const { modulo, estado } = await carregarProducao(
      servicoSoberano({
        estrutura: estruturaSoberanaCoerente(),
        colaboradores: colaboradoresSoberanos,
      })
    );

    expect(estado.fase).toBe("pronta");
    expect(modulo.estadoEstruturaSoberana().fase).toBe("pronta");

    // Identidade estrutural = UUID canônico.
    expect([...estado.estrutura.projecao.vinculos.keys()].sort()).toEqual(
      [UUID_GERENTE, UUID_COORD, UUID_ANALISTA, UUID_COLEGA].sort()
    );

    // Ponte de compatibilidade (matrícula legada ↔ UUID).
    expect(collaboratorIdDoLegado(estado.estrutura, 3)).toBe(UUID_ANALISTA);
    expect(matriculaLegadaDoCollaborator(estado.estrutura, UUID_ANALISTA)).toBe(3);
    expect(visaoEstruturalLegada(estado.estrutura, 3)?.gestorCollaboratorId).toBe(UUID_COORD);
    expect(visaoEstruturalLegada(estado.estrutura, 3)?.gestorMatriculaLegada).toBe(2);
    expect(visaoEstruturalLegada(estado.estrutura, 3)?.raizMatriculaLegada).toBe(1);
    expect(visaoEstruturalLegada(estado.estrutura, 3)?.colegiadoMatriculasLegadas).toEqual([4]);
    expect([...alcanceLegado(estado.estrutura, 1)].sort()).toEqual([2, 3, 4]);
  });

  it("ciclo, metas e painel funcionam com a estrutura soberana SEM parâmetro manual", async () => {
    vi.stubEnv("DEV", false);
    vi.stubEnv("PROD", true);
    vi.stubEnv("VITE_APP_ENV", "production");

    await carregarProducao(
      servicoSoberano({
        estrutura: estruturaSoberanaCoerente(),
        colaboradores: colaboradoresSoberanos,
      })
    );

    const progresso = await import("./progressoAvaliacao");
    const cicloEquipe = await import("./cicloEquipeService");
    const metas = await import("./metaStorage");
    const permissao = await import("./permissaoAvaliacao");

    const criterios = [{ id: "c1", subcriterios: ["s1"] }];
    const notas = { c1: { notas: { s1: { gerente: 5, coordenador: 5, colegiado: 5 } } } };
    const votos = { c1: { s1: { 4: 5 } } };

    const resultado = progresso.calcularProgressoAvaliacao(
      criterios,
      notas,
      votos,
      analistaLocal,
      mundoLocal,
      "ok",
      "ok"
    );
    expect(resultado.gerente.necessario).toBe(true);
    expect(resultado.coordenador.necessario).toBe(true);
    expect(resultado.colegiado.necessario).toBe(true);
    expect(resultado.completo).toBe(true);

    const linhas = cicloEquipe.getPainelCiclo(ciclo, gerenteLocal);
    expect(linhas.map((linha) => linha.colaborador.matricula)).toEqual([2, 3, 4]);

    expect(
      metas.podeAprovarMetaNoCiclo(coordenadorLocal, analistaLocal, mundoLocal, ciclo)
    ).toBe(true);
    expect(
      metas.podeAprovarMetaNoCiclo(gerenteLocal, analistaLocal, mundoLocal, ciclo)
    ).toBe(true);
    expect(
      metas.metaExigeAprovacaoCoordenador(analistaLocal, mundoLocal, ciclo)
    ).toBe(true);

    const permissoes = permissao.obterPermissoesAvaliacao(
      coordenadorLocal,
      analistaLocal,
      mundoLocal,
      ciclo
    );
    expect(permissoes.podeAvaliarComoCoordenador).toBe(true);
    expect(permissoes.podeAvaliar).toBe(true);
  });

  it("a estrutura SOBERANA vence o cadastro local quando divergem", async () => {
    vi.stubEnv("DEV", false);
    vi.stubEnv("PROD", true);
    vi.stubEnv("VITE_APP_ENV", "production");

    // Soberano: o analista (3) responde ao colega (4); o "coordenador local" (2)
    // não participa da cadeia e o colega é nível intermediário.
    const divergente = estruturaSoberanaCoerente();
    await carregarProducao(
      servicoSoberano({
        estrutura: {
          ...divergente,
          reportingLines: [
            {
              reportingLineId: "r-1",
              subordinatePositionId: POS_ANALISTA,
              managerPositionId: POS_COLEGA,
              motivo: "fixture",
              validFrom: INICIO,
              validTo: null,
              version: 1,
            },
            {
              reportingLineId: "r-2",
              subordinatePositionId: POS_COLEGA,
              managerPositionId: POS_GERENTE,
              motivo: "fixture",
              validFrom: INICIO,
              validTo: null,
              version: 1,
            },
          ],
        },
        colaboradores: [
          colaboradorSoberano(UUID_GERENTE, "1", null),
          colaboradorSoberano(UUID_ANALISTA, "3", UUID_COLEGA),
          colaboradorSoberano(UUID_COLEGA, "4", UUID_GERENTE),
        ],
      })
    );

    const metas = await import("./metaStorage");
    const cicloEquipe = await import("./cicloEquipeService");

    // O cadastro local diz que 2 gerencia 3; o soberano diz que é 4.
    expect(
      metas.podeAprovarMetaNoCiclo(coordenadorLocal, analistaLocal, mundoLocal, ciclo)
    ).toBe(false);
    expect(
      metas.podeAprovarMetaNoCiclo(colegaLocal, analistaLocal, mundoLocal, ciclo)
    ).toBe(true);
    // A raiz continua sendo o gerente (1).
    expect(
      metas.podeAprovarMetaNoCiclo(gerenteLocal, analistaLocal, mundoLocal, ciclo)
    ).toBe(true);

    // Painel do gerente: o alcance soberano inclui 3 e 4 (não 2).
    expect(
      cicloEquipe
        .getPainelCiclo(ciclo, gerenteLocal)
        .map((linha) => linha.colaborador.matricula)
    ).toEqual([3, 4]);
  });
});

describe("F5-08 P6 — fail-closed real e isolamento de DEV", () => {
  it("falha real da porta ⇒ indisponível ⇒ decisões negativas (sem localStorage/seed)", async () => {
    vi.stubEnv("DEV", false);
    vi.stubEnv("PROD", true);
    vi.stubEnv("VITE_APP_ENV", "production");

    const { estado } = await carregarProducao(
      operacoes({
        lerEstrutura: async () => ({
          ok: false,
          codigo: "FORBIDDEN",
          mensagem: "sem permissão",
        }),
        listar: async () => ({ ok: true, dados: colaboradoresSoberanos }),
      })
    );

    expect(estado.fase).toBe("indisponivel");
    expect(estado.codigo).toBe("FORBIDDEN");
    // Estrutura vazia (sem vínculos e sem ponte) — nada é presumido.
    expect(estado.estrutura.projecao.vinculos.size).toBe(0);
    expect(estado.estrutura.ponteMatriculas.size).toBe(0);

    const progresso = await import("./progressoAvaliacao");
    const cicloEquipe = await import("./cicloEquipeService");
    const metas = await import("./metaStorage");
    const permissao = await import("./permissaoAvaliacao");

    // O cadastro local está populado — e ainda assim nada é concedido.
    const criterios = [{ id: "c1", subcriterios: ["s1"] }];
    const cheio = { c1: { notas: { s1: { gerente: 5, coordenador: 5, colegiado: 5 } } } };
    const votos = { c1: { s1: { 4: 5 } } };

    const resultado = progresso.calcularProgressoAvaliacao(
      criterios,
      cheio,
      votos,
      analistaLocal,
      mundoLocal,
      "ok",
      "ok"
    );
    expect(resultado.completo).toBe(false);
    expect(resultado.gerente.necessario).toBe(false);
    expect(resultado.coordenador.necessario).toBe(false);

    expect(cicloEquipe.getPainelCiclo(ciclo, gerenteLocal)).toEqual([]);
    expect(cicloEquipe.analisarPendenciasDoCiclo(ciclo)[0]?.papel).toBe("Estrutura");

    expect(
      metas.podeAprovarMetaNoCiclo(coordenadorLocal, analistaLocal, mundoLocal, ciclo)
    ).toBe(false);
    expect(
      metas.podeAprovarMetaNoCiclo(gerenteLocal, analistaLocal, mundoLocal, ciclo)
    ).toBe(false);
    expect(metas.metaExigeAprovacaoCoordenador(analistaLocal, mundoLocal, ciclo)).toBe(true);

    expect(
      permissao.obterPermissoesAvaliacao(coordenadorLocal, analistaLocal, mundoLocal, ciclo)
        .podeAvaliar
    ).toBe(false);

    await expect(
      cicloEquipe.criarAvaliacoesDoCicloAtivado(ciclo, { organizationId: ORG })
    ).rejects.toThrow(/estrutura organizacional/i);
  });

  it("sem organização ativa não há carregamento (fail-closed explícito)", async () => {
    vi.stubEnv("DEV", false);
    vi.stubEnv("PROD", true);
    vi.stubEnv("VITE_APP_ENV", "production");

    const modulo = await import("./estruturaSoberanaCliente");
    const estado = await modulo.carregarEstruturaSoberana({ organizationId: null });
    expect(estado.fase).toBe("indisponivel");
    expect(estado.codigo).toBe("FORBIDDEN");
  });

  it("DEV: fixture local atrás do gate, com identificadores de fixture (não UUID)", async () => {
    vi.stubEnv("DEV", true);
    vi.stubEnv("PROD", false);
    vi.stubEnv("VITE_APP_ENV", "development");

    const modulo = await import("./estruturaSoberanaCliente");
    const estrutura = modulo.estruturaSoberanaEfetiva(mundoLocal);

    expect([...estrutura.projecao.vinculos.keys()].sort()).toEqual([
      "fixture:1",
      "fixture:2",
      "fixture:3",
      "fixture:4",
    ]);
    expect(modulo.visaoEstruturalLegada(estrutura, 3)?.gestorMatriculaLegada).toBe(2);
    expect(modulo.visaoEstruturalLegada(estrutura, 3)?.colegiadoMatriculasLegadas).toEqual([4]);
    expect(modulo.alcanceLegado(estrutura, 1).has(3)).toBe(true);
  });

  it("fora de DEV, sem carregamento soberano, não existe fallback para a fixture", async () => {
    vi.stubEnv("DEV", false);
    vi.stubEnv("PROD", true);
    vi.stubEnv("VITE_APP_ENV", "production");

    const modulo = await import("./estruturaSoberanaCliente");
    const efetiva = modulo.estruturaSoberanaEfetiva(mundoLocal);
    expect(efetiva.projecao.vinculos.size).toBe(0);
    expect(efetiva.ponteMatriculas.size).toBe(0);
    expect(modulo.visaoEstruturalLegada(efetiva, 3)).toBeNull();
  });

  it("ponte: matrícula não numérica não é endereçável pelo domínio legado", async () => {
    expect(matriculaLegadaNumerica("12345")).toBe(12345);
    expect(matriculaLegadaNumerica("F507-0001")).toBeNull();
    expect(matriculaLegadaNumerica(null)).toBeNull();

    vi.stubEnv("DEV", false);
    vi.stubEnv("PROD", true);
    vi.stubEnv("VITE_APP_ENV", "production");

    // O rótulo humano do gerente passa a ser NÃO numérico: o vínculo estrutural
    // continua existindo por UUID, mas o domínio legado deixa de alcançá-lo.
    const { estado } = await carregarProducao(
      servicoSoberano({
        estrutura: estruturaSoberanaCoerente(),
        colaboradores: [
          colaboradorSoberano(UUID_GERENTE, "F507-0001", null),
          colaboradorSoberano(UUID_COORD, "2", UUID_GERENTE),
          colaboradorSoberano(UUID_ANALISTA, "3", UUID_COORD),
          colaboradorSoberano(UUID_COLEGA, "4", UUID_COORD),
        ],
      })
    );

    expect(estado.estrutura.projecao.vinculos.has(UUID_GERENTE)).toBe(true);
    expect(matriculaLegadaDoCollaborator(estado.estrutura, UUID_GERENTE)).toBeNull();
    expect(collaboratorIdDoLegado(estado.estrutura, 1)).toBeNull();
  });
});
