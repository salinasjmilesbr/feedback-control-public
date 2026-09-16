/**
 * F5-07 — testes de tela do detalhe soberano do colaborador.
 *
 * Cobre: identidade/estado pela projeção soberana, histórico organizacional vindo
 * da trilha append-only (`obterHistoricoColaborador`), ausência explícita de
 * alocação, estado restrito em negação, acervo legado apenas ROTULADO como legado
 * e ausência de leitura do `colaboradorStorage` no render.
 */

import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import type {
  ObservacaoSoberana,
  ObservationRepository,
} from "../application/ports/ObservationRepository";
import {
  getColaboradorByMatricula,
  getColaboradores,
} from "../services/colaboradorStorage";
import {
  obterHistoricoColaborador,
  redefinirAcessoColaboradoresSoberanos,
  type ColaboradorSoberano,
  type EventoColaborador,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { ServiceColaboradores } from "../services/colaboradoresSoberanos/serviceColaboradores";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { ORGANIZACAO_TESTE, ProvedorAuthTeste } from "../test/authTeste";
import ColaboradorDetalhePage, {
  type EstadoDetalheColaborador,
} from "./ColaboradorDetalhePage";
import type { EstadoEstrutura } from "./apoioEstrutura";
import fontePagina from "./ColaboradorDetalhePage.tsx?raw";

/**
 * Duplo TIPADO da porta soberana de observações (`F5-11 P5`): sem repositório o
 * painel do gestor não é montado (fail-closed), então o teste fornece o duplo
 * com as assinaturas REAIS de `ObservationRepository`. A leitura por escopo
 * devolve SOMENTE os itens semeados pelo caso (`duplo.itens`) e TODA mutação
 * falha fechado — nenhum sucesso é inventado.
 */
const duplo = vi.hoisted(() => ({ itens: [] as ObservacaoSoberana[] }));

vi.mock("../services/acessoObservacoesSoberanas", async (importOriginal) => {
  const real =
    await importOriginal<
      typeof import("../services/acessoObservacoesSoberanas")
    >();
  const falha = {
    ok: false as const,
    error: {
      code: "INTERNAL" as const,
      message: "Duplo de teste: operação soberana não exercitada.",
    },
  };
  const repositorio: ObservationRepository = {
    listarObservacoesPorEscopo: (organizationId, escopo) => {
      // A organização é INTENÇÃO de UX (quem decide é a fronteira) e NÃO faz
      // parte da projeção: o duplo apenas a marca como usada.
      void organizationId;
      return Promise.resolve({
        ok: true,
        data: {
          escopo,
          selfCollaboratorId: null,
          data: "2026-03-02T12:00:00.000Z",
          total: duplo.itens.length,
          itens: duplo.itens,
        },
      });
    },
    obterObservacao: () => Promise.resolve(falha),
    obterHistoricoObservacao: () => Promise.resolve(falha),
    criarObservacao: () => Promise.resolve(falha),
    editarObservacao: () => Promise.resolve(falha),
    definirComunicado: () => Promise.resolve(falha),
    excluirObservacao: () => Promise.resolve(falha),
    revogarExclusao: () => Promise.resolve(falha),
  };
  return {
    ...real,
    obterRepositorioObservacoesSoberanas: () => repositorio,
  };
});

/**
 * Barreira do teste: nenhuma tela migrada pode voltar a ler o cadastro legado
 * durante o render (I7). O mock registra a chamada para a asserção.
 */
vi.mock("../services/colaboradorStorage", async (importOriginal) => {
  const real =
    await importOriginal<typeof import("../services/colaboradorStorage")>();
  return {
    ...real,
    getColaboradores: vi.fn(() => []),
    getColaboradorByMatricula: vi.fn(() => undefined),
  };
});

const UUID = "99999999-9999-4999-8999-999999999999";

function soberano(parcial: Partial<ColaboradorSoberano> = {}): ColaboradorSoberano {
  return {
    collaboratorId: UUID,
    matricula: "12345",
    fullName: "Pessoa Fictícia",
    email: "pessoa@example.invalid",
    status: "active",
    admissionDate: "2024-01-10",
    unitId: null,
    unitName: null,
    jobRoleCode: null,
    jobRoleName: null,
    seniorityName: null,
    managerCollaboratorId: null,
    managerFullName: null,
    version: 3,
    ...parcial,
  };
}

function evento(parcial: Partial<EventoColaborador> = {}): EventoColaborador {
  return {
    eventId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    eventType: "IDENTIFICADOR_DEFINIDO",
    effectiveDate: "2026-03-01T00:00:00.000Z",
    reason: "Correção de matrícula",
    cycleScope: "CICLO_ATUAL_E_POSTERIORES",
    referenceCycleId: null,
    actorUserProfileId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    actorFullName: "Gestor Fictício",
    beforeValue: { matricula: "12345" },
    afterValue: { matricula: "54321" },
    createdAt: "2026-03-01T12:00:00.000Z",
    ...parcial,
  };
}

function operacoes(parcial: Partial<ServiceColaboradores>): ServiceColaboradores {
  return parcial as unknown as ServiceColaboradores;
}

/**
 * F5-11 P5 (L4) — observação SOBERANA (projeção da porta): identidade por UUID,
 * autoria por UUID e ciclo por UUID. Nenhuma matrícula/ano/ciclo legado.
 */
function observacaoSoberana(
  parcial: Partial<ObservacaoSoberana> = {}
): ObservacaoSoberana {
  return {
    id: "abcdabcd-abcd-4bcd-8bcd-abcdabcdabcd",
    organizationId: ORGANIZACAO_TESTE,
    collaboratorId: UUID,
    cycleId: "12341234-1234-4123-8123-123412341234",
    tipo: "POSITIVA",
    texto: "Observação soberana fictícia",
    comunicado: true,
    comunicadoEm: "2026-03-02T12:00:00.000Z",
    excluida: false,
    motivoExclusao: null,
    autorUserProfileId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    autorCollaboratorId: null,
    version: 1,
    criadoEm: "2026-03-01T12:00:00.000Z",
    atualizadoEm: "2026-03-02T12:00:00.000Z",
    ...parcial,
  };
}

/** Fotografia soberana com ocupação, reporting line e colegiado vigentes. */
function estruturaComAlocacao(): EstruturaSoberana {
  const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
  const POSICAO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const POSICAO_GESTOR = "bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd";
  const GESTOR = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  const MEMBRO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
  const COLEGIADO = "efefefef-efef-4fef-8fef-efefefefefef";

  return {
    unidades: [
      { unitId: UNIDADE, nome: "Unidade Fictícia", validFrom: "2026-01-01T00:00:00.000Z", validTo: null, version: 1 },
    ],
    periodosParent: [],
    posicoes: [
      { posicaoId: POSICAO, unitId: UNIDADE, jobRoleId: CARGO, seniorityLevelId: null, validFrom: "2026-01-01T00:00:00.000Z", validTo: null, version: 1 },
      { posicaoId: POSICAO_GESTOR, unitId: UNIDADE, jobRoleId: CARGO, seniorityLevelId: null, validFrom: "2026-01-01T00:00:00.000Z", validTo: null, version: 1 },
    ],
    reportingLines: [
      {
        reportingLineId: "cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd",
        subordinatePositionId: POSICAO,
        managerPositionId: POSICAO_GESTOR,
        motivo: "cadeia formal fictícia",
        validFrom: "2026-01-01T00:00:00.000Z",
        validTo: null,
        version: 1,
      },
    ],
    ocupacoes: [
      { ocupacaoId: "dededede-dede-4ede-8ede-dededededede", collaboratorId: UUID, posicaoId: POSICAO, validFrom: "2026-01-01T00:00:00.000Z", validTo: null, version: 1 },
      { ocupacaoId: "eaeaeaea-eaea-4aea-8aea-eaeaeaeaeaea", collaboratorId: GESTOR, posicaoId: POSICAO_GESTOR, validFrom: "2026-01-01T00:00:00.000Z", validTo: null, version: 1 },
    ],
    cargos: [{ jobRoleId: CARGO, code: "FICT", nome: "Cargo Fictício", status: "active", version: 1 }],
    senioridades: [],
    colegiados: [
      { colegiadoId: COLEGIADO, collaboratorId: UUID, validFrom: "2026-01-01T00:00:00.000Z", validTo: null, version: 1, membroIds: [MEMBRO] },
    ],
    colaboradores: [
      { collaboratorId: UUID, nome: "Pessoa Fictícia" },
      { collaboratorId: GESTOR, nome: "Gestor Fictício" },
      { collaboratorId: MEMBRO, nome: "Membro Fictício" },
    ],
  };
}

const ESTRUTURA_VAZIA: EstadoEstrutura = {
  fase: "pronto",
  estrutura: {
    unidades: [],
    periodosParent: [],
    posicoes: [],
    reportingLines: [],
    ocupacoes: [],
    cargos: [],
    senioridades: [],
    colegiados: [],
    colaboradores: [],
  },
};

function renderizar(
  estadoInicial: EstadoDetalheColaborador,
  identificador: string = UUID,
  estruturaInicial: EstadoEstrutura = ESTRUTURA_VAZIA,
  observacoesIniciais?: readonly ObservacaoSoberana[]
): string {
  // O duplo tipado da porta devolve EXATAMENTE os itens deste caso.
  duplo.itens = [...(observacoesIniciais ?? [])];
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <UsuarioAtualContext.Provider
        value={{
          usuarioAtual: undefined,
          usuariosDisponiveis: [],
          selecionarUsuario: () => undefined,
        }}
      >
        <MemoryRouter initialEntries={[`/colaborador/${identificador}`]}>
          <Routes>
            <Route
              path="/colaborador/:collaboratorId"
              element={
                <ColaboradorDetalhePage
                  estadoInicial={estadoInicial}
                  estruturaInicial={estruturaInicial}
                  {...(observacoesIniciais ? { observacoesIniciais } : {})}
                />
              }
            />
          </Routes>
        </MemoryRouter>
      </UsuarioAtualContext.Provider>
    </ProvedorAuthTeste>
  );
}

describe("detalhe soberano em ColaboradorDetalhePage", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    vi.mocked(getColaboradores).mockClear();
    vi.mocked(getColaboradorByMatricula).mockClear();
    redefinirAcessoColaboradoresSoberanos();
  });

  it("mostra 'sem alocação' e não lê o cadastro legado no render", () => {
    const html = renderizar({
      fase: "pronto",
      colaborador: soberano(),
      historico: [],
      erroHistorico: null,
    });

    expect(html).toContain("Pessoa Fictícia");
    expect(html).toContain("Sem alocação");
    expect(html).not.toContain("F5-08");
    expect(html).not.toContain("Gestor:");
    expect(getColaboradores).not.toHaveBeenCalled();
    expect(getColaboradorByMatricula).not.toHaveBeenCalled();
  });

  it("exibe posição, gestor derivado da reporting line e colegiado vigentes", () => {
    const html = renderizar(
      {
        fase: "pronto",
        colaborador: soberano(),
        historico: [],
        erroHistorico: null,
      },
      UUID,
      { fase: "pronto", estrutura: estruturaComAlocacao() }
    );

    expect(html).toContain("Posição vigente: Unidade Fictícia • FICT — Cargo Fictício");
    expect(html).toContain("Gestor direto (reporting line): Gestor Fictício");
    expect(html).toContain("Colegiado vigente: Membro Fictício");
    // Somente leitura: a tela não administra estrutura, apenas encaminha.
    expect(html).toContain("Administrar alocação");
    expect(html).not.toContain("Trocar posição");
  });

  it("renderiza o histórico organizacional soberano com autor e vigência", () => {
    const html = renderizar({
      fase: "pronto",
      colaborador: soberano(),
      historico: [evento()],
      erroHistorico: null,
    });

    expect(html).toContain("Matrícula definida");
    expect(html).toContain("Correção de matrícula");
    expect(html).toContain("Registrado por: Gestor Fictício");
    expect(html).toContain("Matrícula: 12345 → 54321");
    expect(html).toContain("Trilha soberana append-only");
    expect(getColaboradores).not.toHaveBeenCalled();
  });

  it("exibe negação do servidor como acesso restrito, sem fallback local", () => {
    const html = renderizar({
      fase: "erro",
      codigo: "FORBIDDEN",
      mensagem: "Você não tem permissão para esta operação.",
    });

    expect(html).toContain("Acesso restrito");
    expect(html).toContain("Você não tem permissão para esta operação.");
    expect(html).toContain("Nenhum cadastro local é exibido como substituto");
    expect(getColaboradores).not.toHaveBeenCalled();
  });

  it("mantém o acervo local claramente rotulado como legado", () => {
    const html = renderizar({
      fase: "pronto",
      colaborador: soberano(),
      historico: [],
      erroHistorico: null,
    });

    expect(html).toContain("Acervo legado local (avaliações)");
    expect(html).toContain(
      "Avaliações ainda persistidas no armazenamento local"
    );
    // F5-11 P5 (Issue #250, L4): o bloco de observações deixou de ser acervo
    // local — ele passou a vir da porta SOBERANA (escopo de gestão). A seção
    // continua existindo, sem o rótulo de legado, e a carga soberana é
    // explicitada enquanto não conclui.
    expect(html).toContain("Observações");
    expect(html).not.toContain("Observações (legado local)");
    expect(html).toContain("Carregando as observações do colaborador");
  });

  it("explicita quando não há matrícula numérica para o acervo legado", () => {
    const html = renderizar({
      fase: "pronto",
      colaborador: soberano({ matricula: null }),
      historico: [],
      erroHistorico: null,
    });

    expect(html).toContain("não possui matrícula numérica vigente");
    expect(html).toContain("O histórico soberano acima permanece íntegro.");
  });

  it("apresenta KPIs e lista a partir da projeção SOBERANA do alvo", () => {
    // O AUTOR da observação também precisa estar na estrutura carregada: sem o
    // rótulo do autor o mapeador OMITE "Registrada por" por contrato (não inventa).
    const AUTOR = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
    const html = renderizar(
      {
        fase: "pronto",
        colaborador: soberano(),
        historico: [],
        erroHistorico: null,
      },
      UUID,
      {
        // O rótulo do colaborador-ALVO vem da estrutura carregada: sem ele o
        // mapeador do painel devolve `null` por contrato e o item não é
        // apresentado (por isso a fixture precisa conter o alvo).
        ...ESTRUTURA_VAZIA,
        estrutura: {
          ...ESTRUTURA_VAZIA.estrutura,
          colaboradores: [
            { collaboratorId: UUID, nome: "Pessoa Fictícia" },
            { collaboratorId: AUTOR, nome: "Autora Fictícia" },
          ],
        },
      },
      [
        observacaoSoberana({
          id: "p1",
          tipo: "POSITIVA",
          texto: "Fato positivo",
          autorCollaboratorId: AUTOR,
        }),
        observacaoSoberana({
          id: "n1",
          tipo: "NEUTRA",
          texto: "Fato neutro",
          autorCollaboratorId: AUTOR,
        }),
        observacaoSoberana({
          id: "g1",
          tipo: "NEGATIVA",
          texto: "Fato negativo",
          autorCollaboratorId: AUTOR,
        }),
        observacaoSoberana({
          id: "outro-alvo",
          collaboratorId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab",
          texto: "De outro colaborador",
        }),
      ]
    );

    // O recorte é por UUID do alvo: a observação de outro colaborador não entra.
    expect(html).toContain("Observações soberanas do colaborador autorizadas");
    expect(html).toContain("3 registros");
    expect(html).toContain("Fato positivo");
    expect(html).toContain("Fato negativo");
    expect(html).not.toContain("De outro colaborador");
    // Sem acervo local não há carga pendente; o PAINEL apresenta o autor pelo
    // rótulo disponível e NÃO inventa nome quando ele falta (contrato do mapeador).
    expect(html).not.toContain("Carregando as observações do colaborador");
    expect(html).toContain("Registrada por");
    expect(html).not.toContain("desconhecido");
  });

  it("F5-11 P5: a seção de observações tem UMA única superfície (o painel)", () => {
    // Código SEM comentários (bloco e linha — mesma semântica de `apenasCodigo`
    // em `src/authorization/estruturaUiSeguranca.test.ts`); strings NÃO são
    // removidas, então literal proibido em código continua reprovando.
    const apenasCodigo = (fonte: string): string =>
      fonte
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .split("\n")
        .map((linha) => {
          const indice = linha.indexOf("//");
          return indice === -1 ? linha : linha.slice(0, indice);
        })
        .join("\n");
    const codigo = apenasCodigo(fontePagina);

    // Superfície ÚNICA: a página RENDERIZA o painel soberano...
    expect(codigo).toContain("<ObservacoesColaborador");
    // ...e NÃO mantém a lista inline que o cutover removeu (padrões REAIS dela).
    expect(codigo).not.toMatch(/collaborator-observations-list/);
    expect(codigo).not.toMatch(/collaborator-observation-card/);
    expect(codigo).not.toMatch(/collaborator-observations-detail/);
    expect(codigo).not.toMatch(/mostrarObservacoes/);

    // Nenhuma autoridade/credencial/tabela no browser: a página não lê storage
    // local, não chama RPC e não cria cliente Supabase (a palavra "supabase"
    // aparece em caminhos de TIPO legítimos — o proibido é o CLIENTE e o acesso).
    expect(codigo).not.toMatch(/observacaoStorage|localStorage|sessionStorage/);
    expect(codigo).not.toMatch(/\.rpc\s*\(/);
    expect(codigo).not.toMatch(/SERVICE_ROLE_KEY|serviceRoleKey/);
    expect(codigo).not.toMatch(/@supabase\/supabase-js|createClient\s*\(/);
    expect(codigo).not.toMatch(/\.from\s*\(\s*["'`]/);
  });

  it("busca o histórico pela porta soberana com o UUID do colaborador", async () => {
    const obterHistorico = vi.fn(
      async (): Promise<ResultadoColaboradores<readonly EventoColaborador[]>> => ({
        ok: true,
        dados: [evento()],
      })
    );

    const resultado = await obterHistoricoColaborador(
      { collaboratorId: UUID, organizationId: ORGANIZACAO_TESTE },
      { operacoes: operacoes({ obterHistorico }) }
    );

    expect(obterHistorico).toHaveBeenCalledWith({
      collaboratorId: UUID,
      organizationId: ORGANIZACAO_TESTE,
    });
    expect(resultado.ok).toBe(true);
  });
});
