/**
 * F5-08 P4/P5/P6 — GUARDA de segurança/regressão da camada de estrutura.
 *
 * Prova, de forma ESTÁTICA e determinística, que a entrega:
 * - não cria regra de autorização local (nenhuma página decide capability,
 *   tenant ou ciclo);
 * - não escreve estrutura em `localStorage` (nenhum `setItem`/dual-write);
 * - não chama RPC do banco diretamente nem usa `service_role`/credencial
 *   privilegiada no bundle;
 * - não cria capability nova nem altera a allowlist funcional (D19/D20);
 * - registra as quatro rotas e os quatro itens de menu, sem item duplicado;
 * - **P6 (cutover):** nenhum caminho estrutural de produção lê o cadastro ou o
 *   histórico organizacional local; o mundo funcional só cai no cadastro local
 *   sob barreira explícita de DEV; as chaves estruturais legadas têm donos
 *   únicos e conhecidos (sweep global de `src/`).
 */

import { describe, expect, it } from "vitest";
import { CAPABILIDADES_CANONICAS } from "./catalogoCapabilities";
import { isCapabilityTargetCompatible } from "./policyEngine/capabilityTarget";
import {
  definirParentUnidade,
  definirColegiado,
  lerEstrutura,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import CatalogosFonte from "../pages/CatalogosPage.tsx?raw";
import UnidadesFonte from "../pages/UnidadesPage.tsx?raw";
import PosicoesFonte from "../pages/PosicoesPage.tsx?raw";
import ColegiadoFonte from "../pages/ColegiadoPage.tsx?raw";
import ApoioFonte from "../pages/apoioEstrutura.ts?raw";
import CatalogosEdicaoFonte from "../pages/catalogosEdicao.ts?raw";
import PortaFonte from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos.ts?raw";
import ServiceFonte from "../services/colaboradoresSoberanos/serviceColaboradores.ts?raw";
import LeituraFonte from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana.ts?raw";
import RepositorioFonte from "../infrastructure/supabase/colaboradores/repositorioColaboradores.ts?raw";
import RotasFonte from "../routes/AppRoutes.tsx?raw";
import MenuFonte from "../components/NavegacaoPrincipal.tsx?raw";
// F5-08 P5 — alocação soberana (ocupação + reporting line)
import AlocacaoFonte from "../pages/alocacaoSoberana.ts?raw";
import AlocacaoNovoFonte from "../pages/alocacaoNovoColaborador.ts?raw";
import UseEstruturaFonte from "../pages/useEstruturaSoberana.ts?raw";
import SeletorPosicaoFonte from "../components/SeletorPosicao.tsx?raw";
import NovoColaboradorFonte from "../pages/NovoColaboradorPage.tsx?raw";
import EditarColaboradorFonte from "../pages/EditarColaboradorPage.tsx?raw";
import DetalheColaboradorFonte from "../pages/ColaboradorDetalhePage.tsx?raw";
// F5-08 P6 — cutover estrutural (autoridade estrutural local encerrada)
import AuthorizationPolicyFonte from "./authorizationPolicy.ts?raw";
import MundoFuncionalFonte from "./mundoFuncional.ts?raw";
import HistoricoOrganizacionalFonte from "../services/historicoOrganizacionalStorage.ts?raw";
import ResetDesenvolvimentoFonte from "../services/resetBaseDesenvolvimento.ts?raw";

const FONTES_UI: readonly (readonly [string, string])[] = [
  ["CatalogosPage", CatalogosFonte as string],
  ["UnidadesPage", UnidadesFonte as string],
  ["PosicoesPage", PosicoesFonte as string],
  ["ColegiadoPage", ColegiadoFonte as string],
  ["apoioEstrutura", ApoioFonte as string],
  ["catalogosEdicao", CatalogosEdicaoFonte as string],
];

const FONTES_CLIENTE: readonly (readonly [string, string])[] = [
  ...FONTES_UI,
  ["acessoColaboradoresSoberanos", PortaFonte as string],
  ["serviceColaboradores", ServiceFonte as string],
  ["repositorioEstruturaSoberana", LeituraFonte as string],
  ["repositorioColaboradores", RepositorioFonte as string],
];

/** F5-08 P5 — arquivos da ALOCAÇÃO soberana (ocupação + reporting line). */
const FONTES_ALOCACAO: readonly (readonly [string, string])[] = [
  ["alocacaoSoberana", AlocacaoFonte as string],
  ["alocacaoNovoColaborador", AlocacaoNovoFonte as string],
  ["useEstruturaSoberana", UseEstruturaFonte as string],
  ["SeletorPosicao", SeletorPosicaoFonte as string],
  ["NovoColaboradorPage", NovoColaboradorFonte as string],
  ["EditarColaboradorPage", EditarColaboradorFonte as string],
  ["ColaboradorDetalhePage", DetalheColaboradorFonte as string],
];

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

describe("F5-08 P4 — nenhuma regra de autorização/tenant no React", () => {
  it("as telas não decidem autorização (sem authorize/can/capability)", () => {
    for (const [nome, fonte] of FONTES_UI) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).not.toMatch(/\bauthorize\s*\(/);
      expect(codigo, nome).not.toMatch(/\bcan\s*\(/);
      expect(codigo, nome).not.toContain("capability");
      expect(codigo, nome).not.toContain("org.structure.manage");
      expect(codigo, nome).not.toContain("org.catalog.manage");
      expect(codigo, nome).not.toContain("Policy Engine");
    }
  });

  it("as telas não constroem hierarquia/autorização por cargo, nome ou matrícula", () => {
    for (const [nome, fonte] of FONTES_UI) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).not.toMatch(/\bfuncao\b/);
      expect(codigo, nome).not.toMatch(/respondePara/);
      expect(codigo, nome).not.toMatch(/matricula\s*===/);
    }
  });

  it("nenhum arquivo da entrega escreve em localStorage", () => {
    for (const [nome, fonte] of FONTES_CLIENTE) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).not.toContain("localStorage");
      expect(codigo, nome).not.toContain("sessionStorage");
    }
  });

  it("nenhum arquivo da entrega usa service_role nem chama RPC do banco diretamente", () => {
    for (const [nome, fonte] of FONTES_CLIENTE) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).not.toContain("service_role");
      expect(codigo, nome).not.toContain("SERVICE_ROLE");
      expect(codigo, nome).not.toMatch(/\.rpc\s*\(/);
      for (const rpc of [
        "estrutura_unidade_criar",
        "estrutura_unidade_renomear",
        "estrutura_unidade_encerrar",
        "estrutura_unidade_parent_definir",
        "estrutura_unidade_parent_encerrar",
        "estrutura_posicao_criar",
        "estrutura_posicao_encerrar",
        "estrutura_colegiado_definir",
        "estrutura_colegiado_encerrar",
        "catalogo_cargo_criar",
        "catalogo_cargo_renomear",
        "catalogo_cargo_status_alterar",
        "catalogo_senioridade_criar",
        "catalogo_senioridade_renomear",
        "catalogo_senioridade_status_alterar",
      ]) {
        expect(codigo, `${nome}:${rpc}`).not.toContain(rpc);
      }
    }
  });

  it("a via de leitura é PostgREST sob RLS (sem Edge na leitura soberana)", () => {
    const codigo = apenasCodigo(LeituraFonte as string);
    expect(codigo).toContain(".select(");
    expect(codigo).not.toContain("functions.invoke");
    expect(codigo).not.toContain("FUNCAO_COLABORADORES");
  });
});

describe("F5-08 P4 — vigência e versão otimista (correções da auditoria)", () => {
  it("nenhuma tela fabrica expectedVersion (sem `?? 0` nem `expectedVersion: 0`)", () => {
    for (const [nome, fonte] of FONTES_UI) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).not.toMatch(/\?\?\s*0/);
      expect(codigo, nome).not.toMatch(/expectedVersion\s*:\s*\d/);
    }
  });

  it("a vigência é meio-aberta e derivada de validFrom+validTo (nunca `validTo === null`)", () => {
    const codigo = apenasCodigo(ApoioFonte as string);

    // Regra do contrato: início inclusivo, fim exclusivo.
    expect(codigo).toContain("ref < inicio");
    expect(codigo).toContain("fim !== null && ref >= fim");
    // O antipadrão corrigido não pode voltar.
    expect(codigo).not.toMatch(/validTo\s*===\s*null\s*;/);
  });

  it("as telas que enviam versão usam a decisão sobre a fotografia corrente", () => {
    expect(apenasCodigo(UnidadesFonte as string)).toContain("decidirVersaoOtimista");
    expect(apenasCodigo(PosicoesFonte as string)).toContain("decidirVersaoOtimista");
    expect(apenasCodigo(CatalogosFonte as string)).toContain("confirmarEdicaoCatalogo");
    expect(apenasCodigo(CatalogosEdicaoFonte as string)).toContain("decidirVersaoOtimista");
    expect(apenasCodigo(CatalogosEdicaoFonte as string)).not.toMatch(/\?\?\s*0/);
  });
});

describe("F5-08 P4 — capabilities e allowlist INALTERADAS (D19/D20)", () => {
  it("nenhuma capability nova de estrutura/catálogo", () => {
    const estruturais = CAPABILIDADES_CANONICAS.filter((capability) =>
      capability.startsWith("org.")
    );
    expect([...estruturais].sort()).toEqual(["org.catalog.manage", "org.structure.manage"]);
    expect(CAPABILIDADES_CANONICAS).toHaveLength(29);
  });

  it("a allowlist funcional das duas capabilities administrativas segue VAZIA", () => {
    // Nenhum tipo de alvo é compatível: as duas capabilities são decididas
    // SOMENTE server-side (plano administrativo D19) e seguem fail-closed no
    // Policy Engine funcional.
    for (const capability of ["org.structure.manage", "org.catalog.manage"] as const) {
      for (const tipo of ["collaborator", "cycle", "position", "evaluation"] as const) {
        expect(
          isCapabilityTargetCompatible(capability, {
            type: tipo,
            id: "00000000-0000-4000-8000-000000000000",
          }),
          `${capability}x${tipo}`
        ).toBe(false);
      }
    }
  });
});

describe("F5-08 P4 — rotas e menu", () => {
  it("as quatro rotas existem no roteador autenticado", () => {
    const rotas = RotasFonte as string;
    expect(rotas).toContain('path="/unidades"');
    expect(rotas).toContain('path="/posicoes"');
    expect(rotas).toContain('path="/colegiado"');
    expect(rotas).toContain('path="/catalogos"');
  });

  it("cada item de menu aparece UMA única vez", () => {
    const menu = MenuFonte as string;
    for (const [rotulo, alvo] of [
      ["Unidades", '"/unidades"'],
      ["Posições", '"/posicoes"'],
      ["Colegiado", '"/colegiado"'],
      ["Catálogos", '"/catalogos"'],
    ] as const) {
      expect(menu.split(alvo).length - 1, rotulo).toBe(1);
    }
  });
});

describe("F5-08 P4 — porta expõe as operações exigidas", () => {
  it("leitura, parent e colegiado são funções exportadas da porta", () => {
    expect(typeof lerEstrutura).toBe("function");
    expect(typeof definirParentUnidade).toBe("function");
    expect(typeof definirColegiado).toBe("function");
  });
});

describe("F5-08 P5 — alocação soberana: barreiras estáticas", () => {
  it("as telas de alocação não decidem autorização (sem authorize/can/capability)", () => {
    for (const [nome, fonte] of FONTES_ALOCACAO) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).not.toMatch(/\bauthorize\s*\(/);
      expect(codigo, nome).not.toMatch(/\bcan\s*\(/);
      expect(codigo, nome).not.toContain("org.structure.manage");
      expect(codigo, nome).not.toContain("Policy Engine");
    }
  });

  it("nenhum arquivo de alocação escreve em localStorage/sessionStorage", () => {
    for (const [nome, fonte] of FONTES_ALOCACAO) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).not.toContain("localStorage");
      expect(codigo, nome).not.toContain("sessionStorage");
    }
  });

  it("nenhum arquivo de alocação usa service_role nem chama RPC do banco", () => {
    for (const [nome, fonte] of FONTES_ALOCACAO) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).not.toContain("service_role");
      expect(codigo, nome).not.toMatch(/\.rpc\s*\(/);
      for (const rpc of [
        "estrutura_ocupacao_definir",
        "estrutura_ocupacao_encerrar",
        "estrutura_reporting_definir",
        "estrutura_reporting_encerrar",
      ]) {
        expect(codigo, `${nome}:${rpc}`).not.toContain(rpc);
      }
    }
  });

  it("a alocação reusa as portas existentes e NÃO inventa expectedVersion", () => {
    const codigo = apenasCodigo(AlocacaoFonte as string);

    // As mutações passam pelas portas soberanas da F5-07.
    for (const porta of [
      "definirOcupacao",
      "encerrarOcupacao",
      "definirReportingLine",
      "encerrarReportingLine",
    ]) {
      expect(codigo).toContain(porta);
    }
    // O contrato F5-07 dessas operações não tem versão otimista: nada é fabricado.
    expect(codigo).not.toContain("expectedVersion");
  });

  it("o gestor é POSIÇÃO (nunca colaborador/cargo/nome/matrícula)", () => {
    const codigo = apenasCodigo(AlocacaoFonte as string);

    expect(codigo).toContain("subordinatePositionId");
    expect(codigo).toContain("managerPositionId");
    expect(codigo).not.toContain("managerCollaboratorId");
    expect(codigo).not.toContain("managerFullName");
    // Nenhum algoritmo local de ciclo: sem travessia de grafo no cliente.
    expect(codigo).not.toMatch(/recurs|visited|profundidade/);
  });

  it("o retry de reporting NÃO tem fallback local para a posição antiga", () => {
    const codigo = apenasCodigo(AlocacaoNovoFonte as string);

    // A fonte da subordinada no retry é a ocupação VIGENTE da fotografia atual.
    expect(codigo).toContain("ocupacaoVigenteDoColaborador");
    // Nenhum fallback `?? posicaoId` na derivação da posição subordinada.
    expect(codigo).not.toMatch(/ocupacao\?\.posicaoId\s*\?\?/);
    expect(codigo).not.toMatch(/\?\?\s*entrada\.posicaoId/);
    // O caminho "após ocupação confirmada" é privado (não exportado) e usa a
    // posição explicitamente aceita pelo servidor.
    expect(codigo).not.toMatch(/export\s+async\s+function\s+confirmarReportingAposOcupacao/);
    expect(codigo).toContain("posicaoAceitaId");
  });

  it("a fotografia é lida pela mesma porta soberana do P4 (sem leitura nova)", () => {
    const codigo = apenasCodigo(UseEstruturaFonte as string);
    expect(codigo).toContain("lerEstrutura");
    expect(codigo).not.toContain("functions.invoke");
    expect(codigo).not.toContain("FUNCAO_COLABORADORES");
  });
});

// ---------------------------------------------------------------------------
// F5-08 P6 — CUTOVER ESTRUTURAL: a autoridade estrutural local foi ENCERRADA
// ---------------------------------------------------------------------------

/**
 * Visão CRUA (`?raw`) de TODO o código de produção de `src/` — sem os testes.
 * É o que dá poder probatório aos sweeps globais do P6: um arquivo NOVO que
 * reintroduza leitura estrutural local, RPC direta ou credencial privilegiada
 * no bundle é reprovado sem depender de lista manual.
 */
const MODULOS_DE_PRODUCAO: Readonly<Record<string, string>> = Object.fromEntries(
  Object.entries(
    import.meta.glob("../**/*.{ts,tsx}", {
      query: "?raw",
      import: "default",
      eager: true,
    })
  ).filter(([caminho]) => !caminho.includes(".test."))
) as Readonly<Record<string, string>>;

/** Chave do glob (relativa a este teste) → caminho canônico `src/...`. */
function caminhoDeSrc(chave: string): string {
  return `src/${chave
    .split("/")
    .filter((parte) => parte !== ".." && parte !== ".")
    .join("/")}`;
}

/** Fonte de produção por caminho: falha ALTO se o módulo não existir (rename). */
function fonteDeProducao(chave: string): string {
  const fonte = MODULOS_DE_PRODUCAO[chave];
  if (typeof fonte !== "string") {
    throw new Error(`Módulo de produção não encontrado por import.meta.glob: ${chave}`);
  }
  return fonte;
}

/** Arquivos de produção que mencionam (em CÓDIGO) um trecho qualquer. */
function produtoresQueCitam(trecho: string): readonly string[] {
  return Object.entries(MODULOS_DE_PRODUCAO)
    .filter(([, fonte]) => apenasCodigo(fonte).includes(trecho))
    .map(([chave]) => caminhoDeSrc(chave))
    .sort();
}

/**
 * Caminho ESTRUTURAL (unidades, posições, cargos, senioridades, hierarquia,
 * gestor, colegiado, ocupação e reporting line): não pode ler cadastro nem
 * histórico organizacional local. `authorizationPolicy` fica FORA desta lista
 * porque é o único módulo com um call site legado, sob barreira de DEV
 * (verificado em teste próprio).
 */
const FONTES_CAMINHO_ESTRUTURAL: readonly (readonly [string, string])[] = [
  ...FONTES_CLIENTE,
  ...FONTES_ALOCACAO,
  ["mundoFuncional", MundoFuncionalFonte as string],
  ["historicoOrganizacionalStorage", HistoricoOrganizacionalFonte as string],
];

/**
 * Consumidores LEGADOS de ciclo/metas/feedback — classificação **B** do §3
 * (somente leitura autorizada; domínios das atividades F5-09..F5-11, FORA do
 * escopo do P6). Podem LER o cadastro local; nunca regravá-lo.
 */
const CAMINHOS_LEGADO_LEITURA: readonly string[] = [
  "../pages/AcompanhamentoMetasPage.tsx",
  "../pages/EditarFeedbackPage.tsx",
  "../pages/FeedbackDetalhePage.tsx",
  "../pages/MinhaAvaliacaoDetalhePage.tsx",
  "../pages/MinhasMetasPage.tsx",
  "../pages/NovoFeedbackPage.tsx",
  "../pages/PainelCicloPage.tsx",
  "../pages/RelatoriosPage.tsx",
  "../services/cancelamentoCicloService.ts",
  "../services/cicloEquipeService.ts",
  "../services/correcaoPeriodoCicloService.ts",
  "../services/exportarAvaliacaoPdf.ts",
  "../services/geradorDadosTeste.ts",
  "../services/historicoOrganizacionalStorage.ts",
  "../services/metaStorage.ts",
  "../services/permissaoAvaliacao.ts",
  "../services/reaberturaCicloService.ts",
  "../infrastructure/localStorage/localCollaboratorRepository.ts",
  "../contexts/UsuarioAtualProvider.tsx",
];

describe("F5-08 P6 — nenhuma autoridade estrutural local", () => {
  it("o caminho estrutural não lê o cadastro nem o histórico organizacional local", () => {
    for (const [nome, fonte] of FONTES_CAMINHO_ESTRUTURAL) {
      const codigo = apenasCodigo(fonte);
      for (const legado of [
        "getColaboradores(",
        "getColaboradorByMatricula(",
        "colaboradorStorage",
        "historicoOrganizacionalStorage",
        "data/colaboradores",
      ]) {
        expect(codigo, `${nome}:${legado}`).not.toContain(legado);
      }
    }
  });

  it("authorizationPolicy: o cadastro local só entra sob barreira explícita de DEV", () => {
    const codigo = apenasCodigo(AuthorizationPolicyFonte as string);

    // A barreira é o gate DEV do Vite (o mesmo do seletor de impersonação).
    expect(codigo).toContain("simulacaoDevPermitida");
    // Existe UM único call site do cadastro legado, e ele está DENTRO do gate.
    expect(codigo.match(/getColaboradores\(\)/g) ?? []).toHaveLength(1);
    expect(codigo).toMatch(
      /if \(simulacaoDevPermitida\) \{\s*try \{\s*return getColaboradores\(\);/
    );
    // Fora do gate o mundo é VAZIO ⇒ ator não resolvido ⇒ DENY (fail-closed).
    expect(codigo).toContain("return [];");
    expect(codigo).not.toMatch(/\?\?\s*getColaboradores\(\)/);
  });

  it("mundoFuncional: bindings NÃO são derivados do mundo local fora do gate DEV", () => {
    const codigo = apenasCodigo(MundoFuncionalFonte as string);

    expect(codigo).toContain("SEM_BINDINGS_DEV");
    expect(codigo).toMatch(
      /simulacaoDevPermitida\s*\?\s*derivarBindingsDev\(colaboradores\)\s*:\s*SEM_BINDINGS_DEV/
    );
    // O fallback implícito removido no P6 não pode voltar.
    expect(codigo).not.toMatch(/\?\?\s*derivarBindingsDev\s*\(/);
  });

  it("historicoOrganizacionalStorage: sem promoção de texto local a relação estrutural", () => {
    const codigo = apenasCodigo(HistoricoOrganizacionalFonte as string);

    // O gestor do snapshot vem de MATRÍCULA; o rótulo textual não o substitui.
    expect(codigo).toMatch(/gestorDiretoNome:\s*gestor\?\.nome,/);
    expect(codigo).not.toMatch(/gestorDiretoNome\s*:\s*[^,\n]*\?\?/);
    expect(codigo).not.toMatch(/respondePara\s*\|\|/);
    expect(codigo).not.toMatch(/\?\?\s*\(?\s*[\w.]*\.respondePara\b/);
    // A escrita local continua BARREIRA fail-closed (F5-07).
    expect(codigo).toMatch(/export function registrarMovimentacaoOrganizacional/);
    expect(codigo).toMatch(/throw new Error/);
  });

  it("as chaves estruturais legadas só são tocadas pelos módulos donos", () => {
    const donos: readonly (readonly [string, readonly string[]])[] = [
      [
        "feedback-control-historico-organizacional",
        ["src/services/historicoOrganizacionalStorage.ts"],
      ],
      [
        "feedback-control-colaboradores",
        ["src/services/colaboradorStorage.ts", "src/services/resetBaseDesenvolvimento.ts"],
      ],
    ];
    for (const [chave, esperados] of donos) {
      expect(produtoresQueCitam(chave), chave).toEqual([...esperados].sort());
    }
  });

  it("a fixture de DEV não alimenta o caminho soberano (seed com um único dono legado)", () => {
    expect(produtoresQueCitam("data/colaboradores")).toEqual([
      "src/services/colaboradorStorage.ts",
    ]);
    // O dono é LEITURA legada: a barreira de escrita segue lançando.
    const codigo = apenasCodigo(fonteDeProducao("../services/colaboradorStorage.ts"));
    expect(codigo).toContain("colaboradoresIniciais");
    expect(codigo).toMatch(/export function saveColaborador[\s\S]*?throw new Error/);
    expect(codigo).toMatch(/export function updateColaborador[\s\S]*?throw new Error/);
  });

  it("a única escrita local do cadastro é o reset de DEV, sob gate explícito", () => {
    const codigo = apenasCodigo(ResetDesenvolvimentoFonte as string);

    expect(codigo).toContain("resetDesenvolvimentoPermitido");
    expect(codigo).toMatch(/if \(!resetBaseDesenvolvimentoHabilitado\) return;/);
    // Apaga chaves de DEV; NUNCA regrava o cadastro.
    expect(codigo).not.toMatch(/setItem\(\s*["'`]feedback-control-colaboradores/);
  });

  it("a autoridade de mundo local não é consumida por estrutura (legado contido)", () => {
    expect(produtoresQueCitam("providers/localWorld")).toEqual([
      "src/pages/MinhasMetasPage.tsx",
      "src/services/metaStorage.ts",
    ]);
  });

  it("a fixture local de equipe de avaliação foi removida e não é referenciada", () => {
    expect(Object.keys(MODULOS_DE_PRODUCAO)).not.toContain("../data/evaluationTeam.ts");
    expect(produtoresQueCitam("evaluationTeam")).toEqual([]);
  });

  it("consumidores legados leem, mas NUNCA regravam o cadastro (sem dual-write)", () => {
    for (const caminho of CAMINHOS_LEGADO_LEITURA) {
      const codigo = apenasCodigo(fonteDeProducao(caminho));
      expect(codigo, `${caminho}:saveColaborador`).not.toContain("saveColaborador(");
      expect(codigo, `${caminho}:updateColaborador`).not.toContain("updateColaborador(");
      expect(codigo, `${caminho}:chave`).not.toMatch(
        /setItem\(\s*["'`]feedback-control-colaboradores/
      );
    }
  });

  it("nenhum arquivo de produção chama RPC do banco nem carrega credencial privilegiada", () => {
    // Sanidade do sweep: o glob precisa enxergar o código REAL de produção —
    // um glob vazio tornaria esta prova vacuamente verde.
    expect(Object.keys(MODULOS_DE_PRODUCAO).length).toBeGreaterThan(100);
    expect(MODULOS_DE_PRODUCAO["../services/colaboradorStorage.ts"]).toBeTypeOf("string");

    for (const [chave, fonte] of Object.entries(MODULOS_DE_PRODUCAO)) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, caminhoDeSrc(chave)).not.toMatch(/\.rpc\s*\(/);
      expect(codigo, caminhoDeSrc(chave)).not.toMatch(/SERVICE_ROLE_KEY|serviceRoleKey/);
    }
  });
});

// ---------------------------------------------------------------------------
// F5-08 P6 (correção da auditoria) — PAPEL/ELEGIBILIDADE sem estrutura local
// ---------------------------------------------------------------------------

/**
 * Módulos que decidem QUEM GERENCIA QUEM, QUEM AVALIA QUEM, quem é
 * GERENTE/COORDENADOR e quem é ELEGÍVEL. Depois da correção eles derivam esses
 * fatos da ESTRUTURA SOBERANA (projeção por UUID produzida pelas portas do
 * P4/F5-07) — nunca mais dos campos do cadastro local (`funcao`,
 * `gestorDiretoMatricula`, `avaliadoresColegiadoMatriculas`) nem de
 * `getColaboradoresVisiveis`.
 */
const CAMINHOS_PAPEL_ELEGIBILIDADE: readonly string[] = [
  "../services/progressoAvaliacao.ts",
  "../services/cicloEquipeService.ts",
  "../services/metaStorage.ts",
  "../services/permissaoAvaliacao.ts",
];

/** Modelo estrutural (UUID) e fronteira de compatibilidade do cliente. */
const PROJECAO_ESTRUTURAL = "../services/projecaoEstruturalSoberana.ts";
const ESTRUTURA_DO_CLIENTE = "../services/estruturaSoberanaCliente.ts";
const HOOK_ESTRUTURA = "../pages/useEstruturaSoberanaDoCliente.ts";

describe("F5-08 P6 (correção) — papel/elegibilidade sem estrutura local", () => {
  it("os módulos de papel/elegibilidade não leem campos estruturais locais", () => {
    for (const caminho of CAMINHOS_PAPEL_ELEGIBILIDADE) {
      const codigo = apenasCodigo(fonteDeProducao(caminho));
      for (const proibido of [
        "funcao",
        "gestorDiretoMatricula",
        "avaliadoresColegiadoMatriculas",
        "funcaoUsaEstruturaAvaliacaoAnalista",
        "getColaboradoresVisiveis",
      ]) {
        expect(codigo, `${caminho}:${proibido}`).not.toContain(proibido);
      }
    }
  });

  it("o MODELO estrutural é UUID-first e não conhece matrícula", () => {
    const codigo = apenasCodigo(fonteDeProducao(PROJECAO_ESTRUTURAL));

    // §19.3/§19.1: matrícula não é identidade funcional nem chave estrutural.
    expect(codigo).not.toContain("matricula");
    expect(codigo).not.toContain("Matricula");
    // A hierarquia vem das relações soberanas: posições + reporting lines.
    expect(codigo).toContain("gestorSoberanoPositionId");
    expect(codigo).toContain("cadeiaDeGestaoPositionIds");
    expect(codigo).toContain("cadeiaDeGestaoCollaboratorIds");
    expect(codigo).toContain("collaboratorId");
    // Nenhuma superfície nova (RPC/Edge/credencial) foi criada para isso.
    for (const proibido of [".rpc(", "functions.invoke", "service_role", "SERVICE_ROLE"]) {
      expect(codigo, proibido).not.toContain(proibido);
    }
  });

  it("a derivação por `funcao` não é consumida por nenhum módulo de produção", () => {
    // Reintroduzir a decisão por `funcao` em qualquer caminho produtivo reprova
    // aqui: depois da correção o helper existe apenas como vocabulário do
    // domínio (tipos), sem consumidor.
    expect(
      [...produtoresQueCitam("funcaoUsaEstruturaAvaliacaoAnalista")].sort()
    ).toEqual(["src/types/Colaborador.ts"]);
    // O adaptador de fixture usa as RELAÇÕES (cadeia e colegiado), nunca `funcao`.
    const fixture = apenasCodigo(fonteDeProducao(ESTRUTURA_DO_CLIENTE));
    expect(fixture).not.toContain("funcaoUsaEstruturaAvaliacaoAnalista");
    expect(produtoresQueCitam("estruturaDeFixtureLocal")).toEqual([
      "src/services/estruturaSoberanaCliente.ts",
    ]);
    // A matrícula como IDENTIFICADOR legado aparece só na fronteira.
    expect([...produtoresQueCitam("ponteMatriculas")].sort()).toEqual([
      "src/services/estruturaSoberanaCliente.ts",
    ]);
  });

  it("o produtor carrega a estrutura pelas portas soberanas e é acionado pelo shell", () => {
    const produtor = apenasCodigo(fonteDeProducao(ESTRUTURA_DO_CLIENTE));

    // Fonte: as portas JÁ existentes (leitura RLS do P4 + colaboradores F5-07).
    expect(produtor).toContain("lerEstrutura(");
    expect(produtor).toContain("listarColaboradores(");
    expect(produtor).toContain("montarProjecaoEstrutural(");
    expect(produtor).toContain("carregarEstruturaSoberana");
    // O caminho normal NÃO depende de injeção manual de projeção.
    expect(produtor).toContain("estruturaSoberanaEfetiva");
    // Nenhuma superfície nova (RPC/Edge/credencial).
    for (const proibido of [".rpc(", "functions.invoke", "service_role", "SERVICE_ROLE"]) {
      expect(produtor, proibido).not.toContain(proibido);
    }

    // O shell autenticado aciona o produtor com a organização ativa.
    const rotas = apenasCodigo(fonteDeProducao("../routes/AppRoutes.tsx"));
    expect(rotas).toContain("useEstruturaSoberanaDoCliente(organizacaoAtivaId)");
    expect(rotas).toContain("import { useAuth }");

    const hook = apenasCodigo(fonteDeProducao(HOOK_ESTRUTURA));
    expect(hook).toContain("carregarEstruturaSoberana");
  });

  it("o adaptador de fixture só entrega estrutura sob o gate explícito de DEV", () => {
    const codigo = apenasCodigo(fonteDeProducao(ESTRUTURA_DO_CLIENTE));

    expect(codigo).toContain("simulacaoDevPermitida");
    expect(codigo).toMatch(
      /if \(simulacaoDevPermitida && mundoLocalDev\) return estruturaDeFixtureLocal\(mundoLocalDev\);/
    );
    // Mesmo em DEV a matrícula não é a chave estrutural: o identificador é de
    // FIXTURE, namespaced.
    expect(codigo).toContain("idDeFixture");
    expect(codigo).toMatch(/return `fixture:\$\{matricula\}`/);
  });

  it("o mundo sintético de `localWorld` só é construído atrás do gate de DEV", () => {
    const codigo = apenasCodigo(fonteDeProducao("./providers/localWorld.ts"));

    expect(codigo).toContain("simulacaoDevPermitida");
    // Produção ⇒ mundo soberano VAZIO (fail-closed) e o corpo sintético fica
    // inalcançável fora do gate.
    expect(codigo).toMatch(
      /if \(!simulacaoDevPermitida\) \{[\s\S]*?criarProvidersMundoFuncional\(\{ actor, colaboradores: \[\] \}\)[\s\S]*?\}/
    );
    expect(codigo).toContain("return mundoLocalSintetico(actor, colaboradores);");
  });
});
