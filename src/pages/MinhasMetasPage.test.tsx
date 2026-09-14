/**
 * F5-10 P6 (Issue #220) — testes de tela de "Minhas Metas" no caminho SOBERANO.
 *
 * Cobre o que o cutover mudou de fato:
 * - estados explícitos de carregamento/erro/sem-ciclo (nenhum deles é "sem metas"
 *   por negação silenciosa);
 * - quota "X de Y" vinda dos `limites` do envelope, com AUSÊNCIA = quota ZERO;
 * - aprovação como FATO (`exigida`/`vigente`), sem reconstruir a regra;
 * - bloqueio de clique duplo durante a operação (loading por operação);
 * - `CONFLICT` (409) com mensagem própria e REFRESH SOBERANO da lista;
 * - `operationId` estável na MESMA tentativa lógica e novo na tentativa seguinte;
 * - ausência total de autoridade/fallback local nos DOIS módulos de produção
 *   (página e companheiro `minhasMetasApoio`: `metaStorage`, armazenamento do
 *   navegador, mundo local, `can(` e leitura de tabela/RPC).
 */

import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import type { LimiteSoberano, MetaSoberana } from "../application/ports/GoalRepository";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import { ProvedorAuthTeste } from "../test/authTeste";
import type { Colaborador } from "../types/Colaborador";
import MinhasMetasPage, {
  type EstadoMinhasMetas,
  type OperacaoMinhasMetas,
} from "./MinhasMetasPage";
import {
  MENSAGEM_CONFLITO,
  chaveDaTentativa,
  criarRegistroDeTentativas,
  limiteDoTipo,
  mensagemDeFalhaDeOperacao,
  metaAprovada,
  metasDoAtor,
} from "./minhasMetasApoio";

const ORGANIZACAO = "11111111-1111-4111-8111-111111111111";
const CICLO = "22222222-2222-4222-8222-222222222222";
const COLABORADOR_ID = "33333333-3333-4333-8333-333333333333";
const META_ID = "44444444-4444-4444-8444-444444444444";

/** Fonte CRUA do arquivo de produção (guardas negativas valem para o CÓDIGO). */
const FONTES = import.meta.glob("./MinhasMetasPage.tsx", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Readonly<Record<string, string>>;
const FONTE = Object.values(FONTES)[0] as string | undefined;

/**
 * Fonte CRUA do módulo COMPANHEIRO: os auxiliares PUROS de runtime vivem lá
 * (a página exporta apenas o componente e os TIPOS do seu estado).
 */
const FONTES_APOIO = import.meta.glob("./minhasMetasApoio.ts", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Readonly<Record<string, string>>;
const FONTE_APOIO = Object.values(FONTES_APOIO)[0] as string | undefined;

/** Colaborador FICTÍCIO de apresentação (nenhum dado real participa). */
const COLABORADOR: Colaborador = {
  matricula: 4242,
  nome: "Pessoa Fictícia",
  email: "pessoa.ficticia@example.invalid",
  cargo: "Cargo Fictício",
  area: "Área Fictícia",
  funcao: "ANALISTA",
  status: "ATIVO",
  respondePara: "",
};

/** Meta soberana FICTÍCIA; os dois papéis vêm SEMPRE na projeção (§4). */
function metaSoberana(parcial: Partial<MetaSoberana> = {}): MetaSoberana {
  return {
    id: META_ID,
    organizationId: ORGANIZACAO,
    cycleId: CICLO,
    collaboratorId: COLABORADOR_ID,
    tipo: "NEGOCIO_PROJETO",
    descricao: "Meta fictícia de negócio",
    kpi: "KPI fictício",
    valorAlvo: "100",
    status: "EM_ANDAMENTO",
    progressoPercentual: 40,
    resultadoAtual: null,
    resultadoFinal: null,
    atingida: null,
    excluida: false,
    version: 3,
    relacao: "SELF",
    criadoEm: "2026-01-01T00:00:00.000Z",
    atualizadoEm: "2026-01-02T00:00:00.000Z",
    dataUltimoAcompanhamento: null,
    dataFechamento: null,
    dataExclusao: null,
    aprovacoes: [
      {
        papel: "GERENTE",
        exigida: true,
        vigente: true,
        aprovacaoId: null,
        decididoEm: null,
        motivo: null,
        aprovadorCollaboratorId: null,
      },
      {
        papel: "COORDENADOR",
        exigida: false,
        vigente: false,
        aprovacaoId: null,
        decididoEm: null,
        motivo: null,
        aprovadorCollaboratorId: null,
      },
    ],
    aprovacoesVigentes: [],
    ...parcial,
  };
}

function estadoPronto(
  metas: readonly MetaSoberana[] = [metaSoberana()],
  limites: readonly LimiteSoberano[] = [
    { tipo: "NEGOCIO_PROJETO", quantidade: 2, version: 1 },
  ]
): Extract<EstadoMinhasMetas, { fase: "pronto" }> {
  return {
    fase: "pronto",
    ciclo: { id: CICLO, ano: 2026, numero: 1, status: "ATIVO" },
    identidade: { colaboradorId: COLABORADOR_ID, matricula: "4242", nome: "Pessoa Fictícia" },
    metas,
    limites,
  };
}

function renderizar(
  estadoInicial?: EstadoMinhasMetas,
  operacaoInicial?: OperacaoMinhasMetas | null
): string {
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <UsuarioAtualContext.Provider
        value={{
          usuarioAtual: COLABORADOR,
          usuariosDisponiveis: [COLABORADOR],
          selecionarUsuario: () => undefined,
        }}
      >
        <MemoryRouter>
          <MinhasMetasPage
            {...(estadoInicial ? { estadoInicial } : {})}
            {...(operacaoInicial ? { operacaoInicial } : {})}
          />
        </MemoryRouter>
      </UsuarioAtualContext.Provider>
    </ProvedorAuthTeste>
  );
}

describe("MinhasMetasPage — estados explícitos do caminho soberano", () => {
  it("mostra carregamento explícito enquanto lê o escopo no servidor", () => {
    const html = renderizar({ fase: "carregando" });

    expect(html).toContain('role="status"');
    expect(html).toContain("Carregando suas metas no servidor");
    expect(html).not.toContain("Nenhuma meta cadastrada nesta categoria");
  });

  it("mostra negação/indisponibilidade explícita com retry, sem dado local", () => {
    const negado = renderizar({
      fase: "erro",
      codigo: "FORBIDDEN",
      mensagem: "Você não tem permissão para esta operação.",
    });
    expect(negado).toContain("Acesso restrito");
    expect(negado).toContain("Você não tem permissão para esta operação.");
    expect(negado).toContain("Tentar novamente");
    expect(negado).toContain("Nenhuma meta é lida do armazenamento local");

    const indisponivel = renderizar({
      fase: "erro",
      codigo: "INTERNAL",
      mensagem: "O caminho soberano de metas não está disponível neste ambiente.",
    });
    expect(indisponivel).toContain("Não foi possível carregar suas metas");
    expect(indisponivel).toContain("caminho soberano de metas não está disponível");
  });

  it("sem ciclo ativo diz 'nenhum ciclo ativo' em vez de inventar ciclo", () => {
    const html = renderizar({ fase: "sem-ciclo" });

    expect(html).toContain("Nenhum ciclo ativo");
    expect(html).not.toContain("Nova meta");
  });
});

describe("MinhasMetasPage — quota pelos `limites` do envelope", () => {
  it("usa `limites` no 'X de Y' e bloqueia o cadastro no teto", () => {
    const html = renderizar(
      estadoPronto([metaSoberana()], [
        { tipo: "NEGOCIO_PROJETO", quantidade: 1, version: 1 },
        { tipo: "INDIVIDUAL", quantidade: 0, version: 1 },
      ])
    );

    expect(html).toContain("1 de 1");
    expect(html).toContain("não foi habilitada para este ciclo");
    // Teto atingido: o botão de cadastro não é oferecido.
    expect(html).not.toContain("+ Adicionar meta");
    expect(html).not.toContain("Nova meta");
  });

  it("AUSÊNCIA de limite = quota ZERO (nunca ilimitado)", () => {
    const html = renderizar(estadoPronto([metaSoberana()], []));

    expect(html).toContain("0 de 0");
    expect(html).not.toContain("+ Adicionar meta");
    expect(limiteDoTipo([], "NEGOCIO_PROJETO")).toBe(0);
    expect(limiteDoTipo([], "INDIVIDUAL")).toBe(0);
  });

  it("quota do tipo NÃO conta meta de outro tipo", () => {
    const html = renderizar(
      estadoPronto([metaSoberana({ tipo: "INDIVIDUAL" })], [
        { tipo: "NEGOCIO_PROJETO", quantidade: 2, version: 1 },
      ])
    );

    expect(html).toContain("0 de 2");
  });
});

describe("MinhasMetasPage — aprovação e datas como FATOS", () => {
  it("papel exigido e vigente ⇒ aprovada; papel não exigido não vira pendência", () => {
    const aprovada = metaSoberana();
    expect(metaAprovada(aprovada)).toBe(true);

    const html = renderizar(estadoPronto([aprovada]));
    expect(html).toContain("Meta aprovada");
    expect(html).toContain("não exigida neste ciclo");
  });

  it("papel exigido sem decisão vigente ⇒ aguardando aprovação", () => {
    const pendente = metaSoberana({
      aprovacoes: [
        {
          papel: "GERENTE",
          exigida: true,
          vigente: false,
          aprovacaoId: null,
          decididoEm: null,
          motivo: null,
          aprovadorCollaboratorId: null,
        },
        {
          papel: "COORDENADOR",
          exigida: true,
          vigente: false,
          aprovacaoId: null,
          decididoEm: null,
          motivo: null,
          aprovadorCollaboratorId: null,
        },
      ],
    });
    expect(metaAprovada(pendente)).toBe(false);

    const html = renderizar(estadoPronto([pendente]));
    expect(html).toContain("Aguardando aprovação");
    expect(html).toContain("Coordenador direto");
    expect(html).not.toContain("não exigida neste ciclo");
  });

  it("datas exibidas são as da projeção soberana (sem inventar 'último acompanhamento')", () => {
    const semData = renderizar(estadoPronto([metaSoberana()]));
    expect(semData).toContain("Ainda não atualizado");

    const comData = renderizar(
      estadoPronto([
        metaSoberana({
          dataUltimoAcompanhamento: "2026-03-04T12:00:00.000Z",
          status: "ATINGIDA",
          atingida: true,
          resultadoFinal: "Resultado fictício",
          dataFechamento: "2026-03-05T12:00:00.000Z",
        }),
      ])
    );
    expect(comData).not.toContain("Ainda não atualizado");
    expect(comData).toContain("Atingida");
    expect(comData).toContain("Fechada em");
  });

  it("só metas com relação SELF e não excluídas entram na tela e na quota", () => {
    const visiveis = metasDoAtor([
      metaSoberana(),
      metaSoberana({ id: "55555555-5555-4555-8555-555555555555", relacao: "APROVADOR_GERENTE_CONGELADO" }),
      metaSoberana({ id: "66666666-6666-4666-8666-666666666666", excluida: true }),
    ]);

    expect(visiveis).toHaveLength(1);
    expect(visiveis[0]?.id).toBe(META_ID);
  });
});

describe("MinhasMetasPage — FASE 4 (assíncrono)", () => {
  it("bloqueia clique duplo: com operação em curso todas as ações ficam desabilitadas", () => {
    const html = renderizar(estadoPronto(), "editando");

    const acoes = html.match(/<button[^>]*goal-action-btn[^>]*>/g) ?? [];
    expect(acoes.length).toBeGreaterThan(0);
    for (const botao of acoes) {
      expect(botao).toContain("disabled");
    }
    expect(html).toContain("Executando a operação no servidor");
  });

  it("409/CONFLICT tem mensagem própria e a lista é relida do servidor", () => {
    const mensagem = mensagemDeFalhaDeOperacao({
      code: "CONFLICT",
      message: "Versão divergente.",
    });
    expect(mensagem).toBe(MENSAGEM_CONFLITO);
    expect(mensagem).toContain("alterada por outra sessão");
    expect(mensagem).toContain("recarregada com o estado do servidor");

    // Outros códigos NÃO usam o texto do conflito.
    expect(mensagemDeFalhaDeOperacao({ code: "FORBIDDEN", message: "x" })).not.toContain(
      "outra sessão"
    );

    expect(FONTE).toBeTypeOf("string");
    const fonte = FONTE as string;
    // O ramo do conflito relê o escopo (refresh soberano) antes de liberar a tela.
    expect(fonte).toMatch(/if \(conflito\) tentativas\.encerrar\(chave\);/);
    expect(fonte).toMatch(/if \(conflito\) await atualizarLista\(\);/);
    // Sucesso também passa pelo refresh soberano — nada de estado otimista.
    expect(fonte).toMatch(/await atualizarLista\(\);\n\s*return true;/);
  });

  it("operationId é estável na MESMA tentativa e novo na próxima ação", () => {
    const registro = criarRegistroDeTentativas();
    const chave = chaveDaTentativa(["editar", META_ID, 3, "d", "k", "v"]);

    const primeiro = registro.idDa(chave);
    // Retry da MESMA tentativa (mesma chave) reutiliza o id de idempotência.
    expect(registro.idDa(chave)).toBe(primeiro);
    expect(chaveDaTentativa(["editar", META_ID, 3, "d", "k", "v"])).toBe(chave);

    // Versão esperada diferente ⇒ outra tentativa lógica ⇒ outro id.
    const outraVersao = chaveDaTentativa(["editar", META_ID, 4, "d", "k", "v"]);
    expect(outraVersao).not.toBe(chave);
    expect(registro.idDa(outraVersao)).not.toBe(primeiro);

    // Tentativa concluída ⇒ a próxima ação com a mesma chave gera id NOVO.
    registro.encerrar(chave);
    const proximo = registro.idDa(chave);
    expect(proximo).not.toBe(primeiro);
    expect(proximo).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
  });
});

describe("MinhasMetasPage — guardas estáticas do cutover", () => {
  it("não há autoridade nem fallback local em nenhum dos dois módulos", () => {
    expect(FONTE).toBeTypeOf("string");
    expect(FONTE_APOIO).toBeTypeOf("string");
    const fonte = FONTE as string;
    const apoio = FONTE_APOIO as string;

    for (const [nome, codigo] of [
      ["MinhasMetasPage", fonte],
      ["minhasMetasApoio", apoio],
    ] as const) {
      for (const proibido of [
        "metaStorage",
        "localStorage",
        "sessionStorage",
        "feedback-control-metas",
        "localWorld",
        "gestorDiretoMatricula",
        "funcao",
        "can(",
        ".rpc(",
        'from("evaluation_goal',
        "eslint-disable",
      ]) {
        expect(codigo, `${nome}:${proibido}`).not.toContain(proibido);
      }
    }

    // O módulo companheiro NUNCA importa a página: a dependência é de mão única
    // (página → apoio), sem ciclo de runtime.
    expect(apoio).not.toMatch(/from\s+["'][^"']*MinhasMetasPage["']/);

    // `crypto.randomUUID` existe APENAS na geração de `operationId` (idempotência):
    // a identidade da meta é sempre o UUID atribuído pelo servidor.
    expect(apoio.match(/crypto\.randomUUID/g) ?? []).toHaveLength(2);
    expect(apoio.match(/function novoOperationId/g) ?? []).toHaveLength(1);

    // A porta soberana é a única superfície de leitura e mutação.
    expect(fonte).toContain("obterRepositorioMetasSoberanas(");
    expect(fonte).toContain("listarMetasPorEscopo(organizationId, cycleId)");
    expect(apoio).toContain('relacao === "SELF"');
    expect(fonte).toContain("revisarFinalizacaoMeta");
    expect(fonte).toContain("expectedVersion: meta.version");
    expect(fonte).toContain("motivoExclusao");
  });
});
