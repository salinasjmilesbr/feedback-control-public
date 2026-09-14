/**
 * F5-10 P6 (Issue #220) — GUARDAS ESTÁTICAS DO CUTOVER FUNCIONAL DE METAS.
 *
 * Determinísticas e de baixo custo: leem o código de PRODUÇÃO (`?raw` de todo
 * `src/`, excluindo `*.test.*`) e falham se qualquer item obrigatório da Issue
 * regredir. Nenhuma guarda é vacuamente verde: a fonte varrida é afirmada como
 * string ANTES das asserções de ausência, e os recortes de função afirmam que a
 * assinatura foi encontrada.
 *
 * Cobre os itens obrigatórios da Issue #220:
 *  1. inventário estático de imports/readers/writers do legado;
 *  2. import de `services/metaStorage` por módulo de produção;
 *  3. `localStorage`/`sessionStorage` em módulos funcionais de metas;
 *  4. `.rpc("meta_` / PostgREST de metas no cliente;
 *  5. fallback para legado em `catch`/erro/resposta vazia;
 *  6. matrícula/nome/`funcao`/`gestorDiretoMatricula`/`localWorld` como
 *     autoridade de metas (`can()` incluído);
 *  7. geração browser-side de UUID persistente de meta;
 *  8. writer DEV de metas (gerador de fixtures) e reset de DEV;
 *  9. resolução funcional de ciclo por ID local no Painel;
 * 10. KPI "Minhas aprovações de metas" pelos FATOS da projeção;
 * 11. erro de leitura nunca como zero silencioso;
 * 12. versionamento otimista (`expectedVersion`) e idempotência (`operationId`);
 * 13. gate geral do Painel preservado como dívida separada (D5).
 */
import { describe, expect, it } from "vitest";

/** Visão CRUA (`?raw`) de TODO o código de produção de `src/` — sem os testes. */
const MODULOS_DE_PRODUCAO: Readonly<Record<string, string>> = Object.fromEntries(
  Object.entries(
    import.meta.glob("../**/*.{ts,tsx}", {
      query: "?raw",
      import: "default",
      eager: true,
    })
  ).filter(([caminho]) => !caminho.includes(".test."))
) as Readonly<Record<string, string>>;

/** Remove comentários: as barreiras valem para o CÓDIGO, não para a prosa. */
function apenasCodigo(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

/** Fonte de produção por caminho: falha ALTO se o módulo não existir (rename). */
function fonteDeProducao(chave: string): string {
  const fonte = MODULOS_DE_PRODUCAO[chave];
  if (typeof fonte !== "string") {
    throw new Error(`Módulo de produção não encontrado por import.meta.glob: ${chave}`);
  }
  return fonte;
}

/** Recorte de uma função declarada, com asserção de que ela existe (não-vácuo). */
function recorteDeFuncao(fonte: string, assinatura: string): string {
  const inicio = fonte.indexOf(assinatura);
  expect(inicio, `assinatura ausente no módulo: ${assinatura}`).toBeGreaterThan(-1);
  const fim = fonte.indexOf("\n}", inicio);
  expect(fim, `fim da função ausente no módulo: ${assinatura}`).toBeGreaterThan(inicio);
  return fonte.slice(inicio, fim);
}

/** Consumidores funcionais de metas (páginas, hook, caminho de acesso e PDF). */
const CAMINHOS_METAS: readonly string[] = [
  "../services/acessoMetasSoberanas.ts",
  "../pages/MinhasMetasPage.tsx",
  "../pages/AcompanhamentoMetasPage.tsx",
  "../pages/PainelCicloPage.tsx",
  "../pages/useMetasSoberanasDaAvaliacao.ts",
  "../services/exportarAvaliacaoPdf.ts",
  "../pages/MinhaAvaliacaoDetalhePage.tsx",
  "../pages/NovoFeedbackPage.tsx",
  "../pages/EditarFeedbackPage.tsx",
  "../pages/minhasMetasApoio.ts",
  "../pages/acompanhamentoMetasApoio.ts",
  "../pages/painelCicloMetasSoberanas.ts",
];

/**
 * Módulos funcionais de metas que NÃO podem usar armazenamento do navegador. As
 * páginas de feedback/detalhe ficam de fora porque ainda usam o registro LEGADO
 * de ciclos/feedbacks (domínio F5-09/F5-11) para rótulo de período — nunca para
 * metas.
 */
const CAMINHOS_METAS_SEM_NAVEGADOR: readonly string[] = [
  "../services/acessoMetasSoberanas.ts",
  "../pages/MinhasMetasPage.tsx",
  "../pages/AcompanhamentoMetasPage.tsx",
  "../pages/PainelCicloPage.tsx",
  "../pages/useMetasSoberanasDaAvaliacao.ts",
  "../services/exportarAvaliacaoPdf.ts",
  "../pages/minhasMetasApoio.ts",
  "../pages/acompanhamentoMetasApoio.ts",
  "../pages/painelCicloMetasSoberanas.ts",
];

/** Marcadores do legado de metas que NÃO podem existir em código de produção. */
const MARCADORES_LEGADO: readonly string[] = [
  "metaStorage",
  "feedback-control-metas",
  "getMetasDoColaboradorNoCiclo",
  "getMetasDoCiclo",
  "metaEstaAprovada",
  "metaExigeAprovacaoCoordenador",
  "podeAprovarMetaNoCiclo",
  "atualizarAcompanhamentoMeta",
];

/** Janela de inspeção de um `catch` (suficiente para o corpo do tratamento). */
function janelasDeCatch(codigo: string): readonly string[] {
  const janelas: string[] = [];
  let indice = codigo.indexOf("catch");
  while (indice !== -1) {
    janelas.push(codigo.slice(indice, indice + 260));
    indice = codigo.indexOf("catch", indice + 1);
  }
  return janelas;
}

describe("F5-10 P6 (Issue #220) — inventário do legado eliminado", () => {
  it("1/2. nenhum módulo de produção referencia ou importa o legado de metas", () => {
    // Sanidade do sweep: um glob vazio tornaria a prova vacuamente verde.
    expect(Object.keys(MODULOS_DE_PRODUCAO).length).toBeGreaterThan(100);
    expect(fonteDeProducao("../services/acessoMetasSoberanas.ts")).toBeTypeOf("string");

    for (const [chave, fonte] of Object.entries(MODULOS_DE_PRODUCAO)) {
      const codigo = apenasCodigo(fonte);
      for (const marcador of MARCADORES_LEGADO) {
        expect(codigo, `${chave}:${marcador}`).not.toContain(marcador);
      }
      expect(codigo, `${chave}:import-legado`).not.toMatch(
        /from\s+["'][^"']*\/?metaStorage["']/
      );
    }
  });

  it("3. módulos funcionais de metas não usam armazenamento do navegador", () => {
    for (const caminho of CAMINHOS_METAS_SEM_NAVEGADOR) {
      const codigo = apenasCodigo(fonteDeProducao(caminho));
      expect(codigo, `${caminho}:localStorage`).not.toContain("localStorage");
      expect(codigo, `${caminho}:sessionStorage`).not.toContain("sessionStorage");
    }
  });

  it("4. o cliente de metas não chama RPC `meta_*` nem PostgREST de metas", () => {
    for (const caminho of CAMINHOS_METAS) {
      const codigo = apenasCodigo(fonteDeProducao(caminho));
      expect(codigo, `${caminho}:rpc`).not.toMatch(/\.rpc\s*\(/);
      expect(codigo, `${caminho}:invoke`).not.toContain("functions.invoke");
      expect(codigo, `${caminho}:postgrest`).not.toMatch(/\.from\s*\(\s*["']/);
    }
    // Sweep global: nenhuma leitura direta das tabelas de metas no cliente.
    for (const [chave, fonte] of Object.entries(MODULOS_DE_PRODUCAO)) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, `${chave}:goals`).not.toContain('from("evaluation_goal');
      expect(codigo, `${chave}:limits`).not.toContain('from("cycle_goal_limits');
    }
  });

  it("5. falha de leitura não fabrica metas (nenhum fallback para o legado)", () => {
    for (const caminho of [
      "../pages/MinhasMetasPage.tsx",
      "../pages/AcompanhamentoMetasPage.tsx",
      "../pages/useMetasSoberanasDaAvaliacao.ts",
    ]) {
      const codigo = apenasCodigo(fonteDeProducao(caminho));
      const janelas = janelasDeCatch(codigo);
      expect(janelas.length, `${caminho}:sem catch`).toBeGreaterThan(0);
      for (const janela of janelas) {
        for (const marcador of MARCADORES_LEGADO) {
          expect(janela, `${caminho}:catch:${marcador}`).not.toContain(marcador);
        }
        expect(janela, `${caminho}:catch:localStorage`).not.toContain("localStorage");
        // Em `catch`, a lista de metas só pode ser LIMPA; nunca preenchida.
        const preenchimentos = janela.match(/setMetas\(([^)]*)\)/g) ?? [];
        for (const preenchimento of preenchimentos) {
          expect(preenchimento, `${caminho}:catch:setMetas`).toBe("setMetas([])");
        }
      }
      // O erro é SEMPRE explícito: há estado de erro dedicado no módulo.
      expect(codigo, `${caminho}:erro-explicito`).toMatch(/erro/i);
    }

    // Casos cobertos por falha de transporte: `ok: false` com código público.
    const minhas = apenasCodigo(fonteDeProducao("../pages/MinhasMetasPage.tsx"));
    expect(minhas).toContain("falhaDeTransporte");
    expect(minhas).toMatch(/ok:\s*false/);
    expect(minhas).not.toContain("?? []");
    expect(minhas).not.toContain("|| []");
  });
});

describe("F5-10 P6 (Issue #220) — autoridade de metas é soberana", () => {
  it("6. MinhasMetas/Acompanhamento não decidem por can()/funcao/gestor/localWorld", () => {
    const minhas = apenasCodigo(fonteDeProducao("../pages/MinhasMetasPage.tsx"));
    for (const proibido of [
      "funcao",
      "gestorDiretoMatricula",
      "localWorld",
      "goal.view.admin",
      "goal.read",
    ]) {
      expect(minhas, `MinhasMetasPage:${proibido}`).not.toContain(proibido);
    }
    expect(minhas, "MinhasMetasPage:can").not.toMatch(/\bcan\s*\(/);

    const acompanhamento = apenasCodigo(
      fonteDeProducao("../pages/AcompanhamentoMetasPage.tsx")
    );
    for (const proibido of ["funcao", "localWorld", "goal.view.admin", "goal.read"]) {
      expect(acompanhamento, `AcompanhamentoMetasPage:${proibido}`).not.toContain(proibido);
    }
    expect(acompanhamento, "AcompanhamentoMetasPage:can").not.toMatch(/\bcan\s*\(/);

    // A decisão de aprovação é a RELAÇÃO CONGELADA, e só ela.
    const apoioAcompanhamento = apenasCodigo(
      fonteDeProducao("../pages/acompanhamentoMetasApoio.ts")
    );
    for (const assinatura of [
      "function relacaoAutorizaPapel(",
      "function metaFormalmenteAprovada(",
    ]) {
      const recorte = recorteDeFuncao(apoioAcompanhamento, assinatura);
      for (const proibido of [
        "funcao",
        "gestorDiretoMatricula",
        "localWorld",
        "matricula",
      ]) {
        expect(recorte, `${assinatura}:${proibido}`).not.toContain(proibido);
      }
    }
    expect(apoioAcompanhamento).toContain("relacao");
    expect(apoioAcompanhamento).toContain("aprovacoes");
  });

  it("6b. o Painel decide o KPI sem funcao/gestor/localWorld/can()", () => {
    const painel = apenasCodigo(fonteDeProducao("../pages/PainelCicloPage.tsx"));
    expect(painel).not.toContain("localWorld");
    expect(painel).not.toContain("goal.view.admin");
    expect(painel).not.toContain("goal.read");
    // D5: o ÚNICO `can(` é o gate GERAL da página — dívida separada, preservada.
    expect(painel.match(/\bcan\s*\(/g) ?? []).toHaveLength(1);
    expect(painel).toContain("cycle.team.panel.view");

    const painelMetas = apenasCodigo(
      fonteDeProducao("../pages/painelCicloMetasSoberanas.ts")
    );
    const kpi = recorteDeFuncao(
      painelMetas,
      "export function metaEntraNoKpiDeAprovacoes("
    );
    for (const proibido of ["funcao", "gestorDiretoMatricula", "localWorld", "can("]) {
      expect(kpi, `kpi:${proibido}`).not.toContain(proibido);
    }
    expect(kpi).toContain("relacao");
    expect(kpi).toContain("exigida");
    expect(kpi).toContain("vigente");
  });

  it("7. nenhuma identidade de meta é fabricada no browser", () => {
    const apoioMinhas = apenasCodigo(
      fonteDeProducao("../pages/minhasMetasApoio.ts")
    );
    expect(apoioMinhas.match(/crypto\.randomUUID/g) ?? []).toHaveLength(2);
    const geradorDeTentativa = recorteDeFuncao(
      apoioMinhas,
      "function novoOperationId("
    );
    expect(geradorDeTentativa).toContain("crypto.randomUUID");

    // `crypto.randomUUID` NUNCA fabrica identidade de meta: em qualquer modulo
    // de metas ele so pode existir como chave de idempotencia (`operationId`).
    for (const caminho of CAMINHOS_METAS) {
      const codigo = apenasCodigo(fonteDeProducao(caminho));
      expect(codigo, `${caminho}:id-fabricado`).not.toMatch(
        /id\s*:\s*crypto\.randomUUID\s*\(/
      );
      const ocorrencias = codigo.split("crypto.randomUUID").length - 1;
      if (ocorrencias === 0) continue;
      let emContextoDeOperacao = 0;
      let indice = codigo.indexOf("crypto.randomUUID");
      while (indice !== -1) {
        const janela = codigo.slice(Math.max(0, indice - 220), indice);
        if (janela.toLowerCase().includes("operationid")) emContextoDeOperacao += 1;
        indice = codigo.indexOf("crypto.randomUUID", indice + 1);
      }
      expect(
        emContextoDeOperacao,
        `${caminho}:uuid-fora-de-operationId`
      ).toBe(ocorrencias);
    }
  });

  it("8. o gerador DEV de fixtures não escreve metas", () => {
    const gerador = apenasCodigo(fonteDeProducao("../services/geradorDadosTeste.ts"));
    for (const marcador of [
      "feedback-control-metas",
      "METAS_KEY",
      "metaStorage",
      "localWorld",
    ]) {
      expect(gerador, `gerador:${marcador}`).not.toContain(marcador);
    }
    // Não-vacuidade: o gerador continua gerando os OUTROS domínios de DEV.
    expect(gerador).toContain("feedback-control-feedbacks");
    expect(gerador).toContain("localStorage.setItem");
  });

  it("9. o reset de DEV não trata a chave antiga como fonte funcional", () => {
    const reset = apenasCodigo(fonteDeProducao("../services/resetBaseDesenvolvimento.ts"));
    expect(reset).not.toContain("feedback-control-metas");
    expect(reset).not.toContain("metaStorage");
    expect(reset).toContain("feedback-control-colaboradores");
  });
});

describe("F5-10 P6 (Issue #220) — Painel de Ciclo soberano", () => {
  it("10. o ciclo é resolvido por UUID soberano (sem ID local nem ano/numero)", () => {
    const painel = apenasCodigo(fonteDeProducao("../pages/PainelCicloPage.tsx"));
    expect(painel).toContain("obterRepositorioCiclosSoberanos");
    expect(painel).toMatch(/\.obterCiclo\s*\(/);
    expect(painel).not.toContain("getCiclosAvaliacao");
    expect(painel).not.toContain("getCicloAtivo(");
  });

  it("11. o KPI usa os FATOS da projeção e exclui NAO_APLICAVEL/SUSPENSA", () => {
    const painel = apenasCodigo(fonteDeProducao("../pages/PainelCicloPage.tsx"));
    const painelMetas = apenasCodigo(
      fonteDeProducao("../pages/painelCicloMetasSoberanas.ts")
    );
    for (const exigido of [
      "aprovacoes",
      "NAO_APLICAVEL",
      "SUSPENSA",
      "Minhas aprovações de metas",
    ]) {
      expect(painel, `painel:${exigido}`).toContain(exigido);
    }
    // Os FATOS de aprovação que o KPI conta vivem no módulo companheiro.
    for (const exigido of ["aprovacoes", "exigida", "vigente"]) {
      expect(painelMetas, `painelMetas:${exigido}`).toContain(exigido);
    }
    for (const proibido of ["aprovacaoGerente", "aprovacaoCoordenador"]) {
      expect(painel, `painel:${proibido}`).not.toContain(proibido);
    }
  });

  it("12. erro de leitura nunca vira zero silencioso", () => {
    const painel = apenasCodigo(fonteDeProducao("../pages/PainelCicloPage.tsx"));
    expect(painel).toContain("indisponivel");
    // O placeholder do KPI é o travessão, não `0`.
    expect(painel).toContain("\u2014");
    expect(painel).toContain("Tentar novamente");
    // A leitura é uma só, por ciclo, e a falha tem código público.
    expect(painel).toContain("listarMetasPorEscopo");
    expect(painel).toMatch(/codigo/);
  });

  it("13. toda mutação carrega expectedVersion e operationId", () => {
    const minhas = apenasCodigo(fonteDeProducao("../pages/MinhasMetasPage.tsx"));
    for (const operacao of [
      "criarMeta",
      "editarMeta",
      "atualizarProgressoMeta",
      "finalizarMeta",
      "revisarFinalizacaoMeta",
      "excluirMeta",
    ]) {
      expect(minhas, `MinhasMetasPage:${operacao}`).toContain(operacao);
    }
    expect((minhas.match(/expectedVersion/g) ?? []).length).toBeGreaterThanOrEqual(5);
    expect((minhas.match(/operationId/g) ?? []).length).toBeGreaterThanOrEqual(6);
    expect(minhas).toContain("CONFLICT");

    const acompanhamento = apenasCodigo(
      fonteDeProducao("../pages/AcompanhamentoMetasPage.tsx")
    );
    expect(acompanhamento).toContain("aprovarMeta");
    expect((acompanhamento.match(/expectedVersion/g) ?? []).length).toBeGreaterThanOrEqual(1);
    expect((acompanhamento.match(/operationId/g) ?? []).length).toBeGreaterThanOrEqual(3);
    expect(acompanhamento).toContain("CONFLICT");
  });
});
