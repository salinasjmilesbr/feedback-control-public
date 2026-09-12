/**
 * F5-08 P4 — GUARDA de segurança/regressão da camada de UI de estrutura.
 *
 * Prova, de forma ESTÁTICA e determinística, que a entrega do P4:
 * - não cria regra de autorização local (nenhuma página decide capability,
 *   tenant ou ciclo);
 * - não escreve estrutura em `localStorage` (nenhum `setItem`/dual-write);
 * - não chama RPC do banco diretamente nem usa `service_role`/credencial
 *   privilegiada no bundle;
 * - não cria capability nova nem altera a allowlist funcional (D19/D20);
 * - registra as quatro rotas e os quatro itens de menu, sem item duplicado.
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
