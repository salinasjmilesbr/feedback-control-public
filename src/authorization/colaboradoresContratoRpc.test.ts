import { describe, expect, it } from "vitest";
import edgeFonte from "../../supabase/functions/colaboradores/index.ts?raw";
import coreFonte from "../../supabase/functions/colaboradores/core.ts?raw";
import leituraF507 from "../../supabase/migrations/20260913000000_f5_07_collaborators_sovereign.sql?raw";
import rpcF507 from "../../supabase/migrations/20260913010000_f5_07_collaborators_rpc.sql?raw";
import f502 from "../../supabase/migrations/20260909000000_f5_02_hardening_resolver_collaborador.sql?raw";
import f402 from "../../supabase/migrations/20260908010000_authorization_scopes_membership_collaborator.sql?raw";
import f408 from "../../supabase/migrations/20260908130000_f4_08_hardening.sql?raw";
import {
  DEFINICAO_POR_OPERACAO,
  ID_NEUTRO,
  OPERACOES_COLABORADOR,
  OPERACOES_FUNCIONAIS,
  type OperacaoColaborador,
} from "../infrastructure/supabase/colaboradores/contrato";
import type { Capability } from "./Capability";
import { capabilityCanonica } from "./catalogoCapabilities";
import { isCapabilityTargetCompatible } from "./policyEngine/capabilityTarget";

/**
 * F5-07 — CONTRATO Edge Function `colaboradores` → RPC (PostgREST).
 *
 * Mesmo padrão de `src/authorization/avaliacoesContratoRpc.test.ts` (F5-06
 * BLOCKER 1): a fronteira confiável chama as funções SQL por NOME + ARGUMENTOS
 * NOMEADOS. Nome errado ou argumento inexistente ⇒ PostgREST responde
 * "function not found" e a operação inteira quebra — por isso o teste lê o
 * código REAL da Edge (`?raw`) e o compara com:
 *
 * - o contrato declarado abaixo (operação → RPC → argumentos nomeados), que é o
 *   espelho da espinha §1.4/§1.5 e de `docs/F5-07-desenho-tecnico.md` §8.1;
 * - a ASSINATURA REAL das migrations (nome + parâmetros), sem a qual o contrato
 *   declarado não teria valor probatório;
 * - os módulos reais importados pela Edge (Deno bundling: import quebrado
 *   impede a publicação da função).
 *
 * Invariantes verificadas aqui (D19/§8.2/§9.2):
 * - `matricula` só atravessa como INTENÇÃO (`colaborador_resolver_matricula`) e
 *   como DADO na criação (`colaborador_criar`); identidade de escrita é sempre
 *   `collaborator_id` (UUID);
 * - `organization_id`/`actor_user_profile_id` enviados às RPC são os do contexto
 *   REVALIDADO (`org`/`ator`), nunca os do payload;
 * - operações administrativas NÃO usam a allowlist funcional do Policy Engine;
 * - `estrutura.sucessao.registrar` reusa `registrar_sucessao_avaliador`.
 */

interface ContratoDaOperacao {
  readonly rpc: string;
  readonly argumentos: readonly string[];
}

/** Contrato Edge → RPC por OPERAÇÃO (espinha §2 + §1.4/§1.5). */
const CONTRATO_EDGE_RPC: Readonly<Record<OperacaoColaborador, ContratoDaOperacao>> = {
  "collaborator.listar": {
    rpc: "colaborador_visao_listar",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_data",
      "p_filtros",
    ],
  },
  "collaborator.obter": {
    rpc: "colaborador_visao_obter",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_collaborator_id",
      "p_data",
    ],
  },
  "collaborator.criar": {
    // Única operação em que `p_matricula` é legítima: é o DADO criado.
    rpc: "colaborador_criar",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_full_name",
      "p_email",
      "p_matricula",
      "p_admission_date",
      "p_status_inicial",
    ],
  },
  "collaborator.editar": {
    rpc: "colaborador_editar",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_collaborator_id",
      "p_full_name",
      "p_email",
      "p_admission_date",
      "p_expected_version",
    ],
  },
  "collaborator.identificador.definir": {
    rpc: "colaborador_identificador_definir",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_collaborator_id",
      "p_nova_matricula",
      "p_vigencia",
      "p_motivo",
      "p_expected_version",
    ],
  },
  "collaborator.status.alterar": {
    rpc: "colaborador_status_alterar",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_collaborator_id",
      "p_novo_status",
      "p_vigencia",
      "p_motivo",
      "p_cycle_scope",
      "p_reference_cycle_id",
      "p_expected_version",
    ],
  },
  "colaborador.ocupacao.definir": {
    rpc: "estrutura_ocupacao_definir",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_collaborator_id",
      "p_position_id",
      "p_vigencia",
      "p_motivo",
      "p_cycle_scope",
      "p_reference_cycle_id",
    ],
  },
  "colaborador.ocupacao.encerrar": {
    rpc: "estrutura_ocupacao_encerrar",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_collaborator_id",
      "p_vigencia",
      "p_motivo",
    ],
  },
  "estrutura.reporting.definir": {
    rpc: "estrutura_reporting_definir",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_subordinate_position_id",
      "p_manager_position_id",
      "p_vigencia",
      "p_motivo",
    ],
  },
  "estrutura.reporting.encerrar": {
    rpc: "estrutura_reporting_encerrar",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_subordinate_position_id",
      "p_vigencia",
      "p_motivo",
    ],
  },
  "estrutura.responsabilidade.definir": {
    rpc: "estrutura_responsabilidade_definir",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_position_id",
      "p_substitute_collaborator_id",
      "p_responsibility_type",
      "p_vigencia",
      "p_motivo",
    ],
  },
  "estrutura.responsabilidade.encerrar": {
    rpc: "estrutura_responsabilidade_encerrar",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_responsibility_id",
      "p_vigencia",
      "p_motivo",
    ],
  },
  "estrutura.sucessao.registrar": {
    // RPC JÁ EXISTENTE (F3-09/F4-08) — nenhuma função nova de sucessão.
    rpc: "registrar_sucessao_avaliador",
    argumentos: [
      "p_responsibility_ids",
      "p_succession_date",
      "p_motive",
      "p_author_user_profile_id",
    ],
  },
  "colaborador.historico.listar": {
    // Assinatura congelada (§1.4): sem data de referência nem ciclo.
    rpc: "colaborador_historico_listar",
    argumentos: ["p_organization_id", "p_actor_user_profile_id", "p_collaborator_id"],
  },
  "colaborador.catalogo.bootstrap": {
    rpc: "colaborador_catalogo_bootstrap",
    argumentos: [
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_operation_id",
      "p_catalogo",
    ],
  },
};

/** RPCs chamadas FORA do dispatch de operação (resolução de contexto). */
const CONTRATO_RPCS_DE_CONTEXTO: Readonly<Record<string, readonly string[]>> = {
  // Ponte INTENÇÃO matrícula → UUID (a única chamada que envia `p_matricula`).
  colaborador_resolver_matricula: [
    "p_organization_id",
    "p_actor_user_profile_id",
    "p_matricula",
  ],
  // Nome REAL da F5-02 (migration `20260909000000_f5_02_hardening_...`).
  resolver_collaborador_vinculado: ["p_user_profile_id", "p_organization_id"],
  resolver_capabilities_escopos_efetivas: ["p_user_profile_id", "p_organization_id"],
  resolver_alvos_escopo: [
    "p_user_profile_id",
    "p_organization_id",
    "p_scope_type",
    "p_organizational_unit_id",
    "p_data",
  ],
};

/** Operações cujo alvo é um colaborador EXISTENTE (identidade = UUID). */
const OPERACOES_DE_LINHA_EXISTENTE: readonly OperacaoColaborador[] = [
  "collaborator.editar",
  "collaborator.identificador.definir",
  "collaborator.status.alterar",
  "colaborador.ocupacao.definir",
  "colaborador.ocupacao.encerrar",
];

/** Operações administrativas (D19) — nunca pelo caminho funcional. */
const OPERACOES_ADMINISTRATIVAS: readonly OperacaoColaborador[] =
  OPERACOES_COLABORADOR.filter((operacao) => !OPERACOES_FUNCIONAIS.includes(operacao));

interface ChamadaRpc {
  readonly funcao: string;
  readonly argumentos: readonly string[];
  /** Corpo literal da chamada (permite inspecionar os VALORES enviados). */
  readonly corpo: string;
  readonly linha: number;
}

/** Remove comentários de linha (`//` em TS, `--` em SQL) antes de interpretar código. */
function semComentarios(codigo: string, marcador: "//" | "--" = "//"): string {
  return codigo
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf(marcador);
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

/** Extrai as chaves de primeiro nível das chamadas `admin.rpc("<nome>", {…})`. */
function extrairChamadasRpc(codigo: string): ChamadaRpc[] {
  const limpo = semComentarios(codigo);
  const chamadas: ChamadaRpc[] = [];
  const padrao = /\.rpc\(\s*"([^"]+)"\s*,\s*\{/g;

  let correspondencia: RegExpExecArray | null;
  while ((correspondencia = padrao.exec(limpo)) !== null) {
    const funcao = correspondencia[1] as string;
    let profundidade = 1;
    let indice = padrao.lastIndex;

    while (indice < limpo.length && profundidade > 0) {
      const caractere = limpo[indice];
      if (caractere === "{") profundidade += 1;
      if (caractere === "}") profundidade -= 1;
      indice += 1;
    }

    const corpo = limpo.slice(padrao.lastIndex, indice - 1);
    const argumentos: string[] = [];
    let nivel = 0;
    let inicio = 0;

    const registrar = (trecho: string) => {
      const chave = /^\s*([A-Za-z_$][\w$]*)\s*:/.exec(trecho);
      if (chave) argumentos.push(chave[1] as string);
    };

    for (let posicao = 0; posicao < corpo.length; posicao += 1) {
      const caractere = corpo[posicao];
      if (caractere === "{" || caractere === "(" || caractere === "[") nivel += 1;
      else if (caractere === "}" || caractere === ")" || caractere === "]") nivel -= 1;
      else if (caractere === "," && nivel === 0) {
        registrar(corpo.slice(inicio, posicao));
        inicio = posicao + 1;
      }
    }
    registrar(corpo.slice(inicio));

    chamadas.push({
      funcao,
      argumentos,
      corpo,
      linha: limpo.slice(0, correspondencia.index).split("\n").length,
    });
  }

  return chamadas;
}

/** Extrai os `from "…"` / `import "…"` de um fonte TS. */
function especificadoresDeImport(codigo: string): readonly string[] {
  const limpo = semComentarios(codigo);
  const padrao = /(?:from|import)\s+"([^"]+)"/g;
  const achados: string[] = [];
  let correspondencia: RegExpExecArray | null;
  while ((correspondencia = padrao.exec(limpo)) !== null) {
    achados.push(correspondencia[1] as string);
  }
  return achados;
}

/** Resolve um especificador relativo contra o diretório do arquivo. */
function caminhoResolvido(diretorio: string, especificador: string): string {
  const partes = [...diretorio.split("/"), ...especificador.split("/")];
  const pilha: string[] = [];
  for (const parte of partes) {
    if (parte === "" || parte === ".") continue;
    if (parte === "..") {
      pilha.pop();
      continue;
    }
    pilha.push(parte);
  }
  return pilha.join("/");
}

/**
 * Módulos REAIS do repositório vistos do diretório deste teste (`src/authorization`):
 * `src/**` + o diretório da Edge. `import.meta.glob` só devolve arquivos que
 * existem — é o que dá poder probatório à checagem de imports da Edge.
 */
const MODULOS_DO_REPOSITORIO: Readonly<Record<string, unknown>> = {
  ...import.meta.glob("../**/*.ts"),
  ...import.meta.glob("../../supabase/functions/colaboradores/*.ts"),
};

/** Diretório deste arquivo de teste (base das chaves de `import.meta.glob`). */
const DIRETORIO_DO_TESTE = "src/authorization";

/**
 * Caminho relativo (`./x` ou `../dir/x`) na mesma forma que `import.meta.glob`
 * devolve as chaves — inclusive para arquivos do próprio diretório do teste.
 */
function chaveDoModulo(caminho: string): string {
  const origem = DIRETORIO_DO_TESTE.split("/");
  const destino = caminho.split("/");
  let comum = 0;
  while (comum < origem.length && comum < destino.length && origem[comum] === destino[comum]) {
    comum += 1;
  }
  const subidas = origem.length - comum;
  const prefixo = subidas === 0 ? "./" : "../".repeat(subidas);
  return `${prefixo}${destino.slice(comum).join("/")}`;
}

/**
 * Assinaturas REAIS (`create [or replace] function public.<nome>(…)`) das
 * migrations. Uma redefinição posterior substitui a anterior (semântica
 * `create or replace`), por isso a última ocorrência vence.
 */
function assinaturasDasMigrations(fontes: readonly string[]): Map<string, readonly string[]> {
  const assinaturas = new Map<string, readonly string[]>();
  const padrao = /create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)\s*\(/gi;

  for (const fonte of fontes) {
    const limpo = semComentarios(fonte, "--");
    let correspondencia: RegExpExecArray | null;
    while ((correspondencia = padrao.exec(limpo)) !== null) {
      const nome = correspondencia[1] as string;
      let profundidade = 1;
      let indice = padrao.lastIndex;
      while (indice < limpo.length && profundidade > 0) {
        const caractere = limpo[indice];
        if (caractere === "(") profundidade += 1;
        if (caractere === ")") profundidade -= 1;
        indice += 1;
      }
      const lista = limpo.slice(padrao.lastIndex, indice - 1);
      const argumentos: string[] = [];
      for (const item of lista.split(",")) {
        const nomeArgumento = /^\s*([a-z_][a-z0-9_]*)\s/i.exec(item);
        if (nomeArgumento) argumentos.push((nomeArgumento[1] as string).toLowerCase());
      }
      assinaturas.set(nome, argumentos);
    }
  }

  return assinaturas;
}

/** Nomes de TODAS as funções criadas pelas migrations F5-07. */
function funcoesCriadasPelasF507(fontes: readonly string[]): readonly string[] {
  return [...assinaturasDasMigrations(fontes).keys()];
}

const chamadas = extrairChamadasRpc(edgeFonte as string);
const assinaturas = assinaturasDasMigrations([f402, f502, f408, leituraF507, rpcF507]);
const rpcsDeclaradas: readonly string[] = [
  ...Object.values(CONTRATO_EDGE_RPC).map((contrato) => contrato.rpc),
  ...Object.keys(CONTRATO_RPCS_DE_CONTEXTO),
];

function chamadaDe(rpc: string): ChamadaRpc | undefined {
  return chamadas.find((chamada) => chamada.funcao === rpc);
}

function compararConjuntos(enviado: readonly string[], esperado: readonly string[]): boolean {
  return JSON.stringify([...enviado].sort()) === JSON.stringify([...esperado].sort());
}

describe("F5-07 — contrato Edge → RPC (nome + argumentos nomeados)", () => {
  it("a extração das chamadas RPC do código real da Edge funciona", () => {
    const nomes = chamadas.map((chamada) => chamada.funcao);
    expect(nomes).toContain("colaborador_visao_listar");
    expect(nomes).toContain("colaborador_criar");
    expect(nomes).toContain("colaborador_resolver_matricula");
    expect(nomes).toContain("registrar_sucessao_avaliador");
    expect(chamadas.length).toBeGreaterThan(12);
  });

  it("as 15 operações do contrato estão declaradas e TODAS são chamadas pela Edge", () => {
    expect(OPERACOES_COLABORADOR).toHaveLength(15);
    expect(Object.keys(CONTRATO_EDGE_RPC)).toHaveLength(15);

    const semChamada = Object.entries(CONTRATO_EDGE_RPC)
      .filter(([, contrato]) => !chamadaDe(contrato.rpc))
      .map(([operacao, contrato]) => `${operacao} → ${contrato.rpc}`);

    expect(semChamada).toEqual([]);
  });

  it("os argumentos de cada RPC do domínio batem EXATAMENTE com o contrato declarado", () => {
    const divergencias: string[] = [];

    for (const [operacao, contrato] of Object.entries(CONTRATO_EDGE_RPC)) {
      const chamada = chamadaDe(contrato.rpc);
      if (!chamada) {
        divergencias.push(`${operacao}: a Edge não chama ${contrato.rpc}`);
        continue;
      }
      if (!compararConjuntos(chamada.argumentos, contrato.argumentos)) {
        divergencias.push(
          `linha ${chamada.linha}: ${contrato.rpc} envia [${[...chamada.argumentos].sort().join(", ")}] ` +
            `mas o contrato exige [${[...contrato.argumentos].sort().join(", ")}]`
        );
      }
    }

    expect(divergencias).toEqual([]);
  });

  it("o conjunto de RPCs chamadas é EXATAMENTE o declarado (nada fora do contrato)", () => {
    const chamadasFora = chamadas
      .filter((chamada) => !rpcsDeclaradas.includes(chamada.funcao))
      .map((chamada) => `linha ${chamada.linha}: ${chamada.funcao} não está no contrato`);
    const naoChamadas = rpcsDeclaradas
      .filter((rpc) => !chamadaDe(rpc))
      .map((rpc) => `${rpc} está no contrato mas a Edge não a chama`);

    expect([...chamadasFora, ...naoChamadas]).toEqual([]);
  });

  it("a resolução de vínculo usa a RPC REAL da F5-02 (`resolver_collaborador_vinculado`)", () => {
    const nomes = chamadas.map((chamada) => chamada.funcao);
    const vinculado = chamadaDe("resolver_collaborador_vinculado");

    expect(vinculado, "a Edge deve chamar resolver_collaborador_vinculado (F5-02)").toBeDefined();
    // Diagnóstico explícito do defeito conhecido: nome em inglês não existe no banco.
    expect(nomes).not.toContain("resolver_collaborator_vinculado");
  });
});

describe("F5-07 — argumentos conferem com a ASSINATURA REAL das migrations", () => {
  it("todo argumento enviado pela Edge existe na assinatura REAL da RPC", () => {
    const divergencias: string[] = [];

    for (const rpc of rpcsDeclaradas) {
      const chamada = chamadaDe(rpc);
      const assinatura = assinaturas.get(rpc);
      // Nome inexistente/nao chamado e detectado no bloco de contrato acima.
      if (!chamada || !assinatura) continue;
      for (const argumento of chamada.argumentos) {
        if (!assinatura.includes(argumento.toLowerCase())) {
          divergencias.push(
            `${rpc}: argumento "${argumento}" não existe na assinatura real [${assinatura.join(", ")}]`
          );
        }
      }
    }

    expect(divergencias).toEqual([]);
  });

  it("`registrar_sucessao_avaliador` é REUSADA: nenhuma função nova de sucessão na F5-07", () => {
    const novas = funcoesCriadasPelasF507([leituraF507, rpcF507]).filter((nome) =>
      nome.includes("sucess")
    );

    expect(novas).toEqual([]);
    expect(assinaturas.get("registrar_sucessao_avaliador")).toEqual([
      "p_responsibility_ids",
      "p_succession_date",
      "p_motive",
      "p_author_user_profile_id",
    ]);
  });
});

describe("F5-07 — matrícula NUNCA é identidade de escrita", () => {
  it("somente `colaborador_criar` (dado) e `colaborador_resolver_matricula` (ponte) enviam matrícula", () => {
    const permitidas = ["colaborador_criar", "colaborador_resolver_matricula"];
    const infratoras = chamadas
      .filter(
        (chamada) =>
          !permitidas.includes(chamada.funcao) &&
          chamada.argumentos.some(
            (argumento) => argumento === "p_matricula" || argumento === "matricula"
          )
      )
      .map((chamada) => `linha ${chamada.linha}: ${chamada.funcao}`);

    expect(infratoras).toEqual([]);
  });

  it("as operações sobre colaborador EXISTENTE enviam `p_collaborator_id`", () => {
    const divergencias: string[] = [];

    for (const operacao of OPERACOES_DE_LINHA_EXISTENTE) {
      const contrato = CONTRATO_EDGE_RPC[operacao];
      const enviado = chamadaDe(contrato.rpc)?.argumentos ?? [];
      if (!enviado.includes("p_collaborator_id")) {
        divergencias.push(`${operacao} → ${contrato.rpc} não envia p_collaborator_id`);
      }
      if (contrato.argumentos.includes("p_matricula")) {
        divergencias.push(`${operacao} → ${contrato.rpc} declara p_matricula como identidade`);
      }
    }

    expect(divergencias).toEqual([]);
  });

  it("a ponte de matrícula recebe a INTENÇÃO já normalizada em texto", () => {
    const ponte = chamadaDe("colaborador_resolver_matricula");
    expect(ponte?.argumentos).toEqual([
      "p_organization_id",
      "p_actor_user_profile_id",
      "p_matricula",
    ]);
  });
});

describe("F5-07 — o contexto REVALIDADO alimenta as RPC (nunca o payload)", () => {
  it("toda RPC do domínio recebe o ator VERIFICADO (`ator`) e a organização revalidada (`org`)", () => {
    const divergencias: string[] = [];

    for (const [operacao, contrato] of Object.entries(CONTRATO_EDGE_RPC)) {
      const chamada = chamadaDe(contrato.rpc);
      if (!chamada) continue;
      if (
        contrato.argumentos.includes("p_actor_user_profile_id") &&
        !chamada.corpo.includes("p_actor_user_profile_id: ator")
      ) {
        divergencias.push(`${operacao} → ${contrato.rpc} não envia o ator verificado`);
      }
      if (
        contrato.argumentos.includes("p_organization_id") &&
        !chamada.corpo.includes("p_organization_id: org")
      ) {
        divergencias.push(`${operacao} → ${contrato.rpc} não envia a organização revalidada`);
      }
    }

    expect(divergencias).toEqual([]);
  });

  it("a Edge nunca lê identidade/organização do corpo da intenção", () => {
    expect(edgeFonte as string).not.toContain("entrada.actor_user_profile_id");
    expect(edgeFonte as string).not.toContain("entrada.organization_id");
  });

  it("a sucessão grava a autoria com o ator verificado (`p_author_user_profile_id: ator`)", () => {
    const sucessao = chamadaDe("registrar_sucessao_avaliador");
    expect(sucessao).toBeDefined();
    expect(sucessao?.corpo).toContain("p_author_user_profile_id: ator");
  });
});

describe("F5-07 — plano administrativo (D19) não usa a allowlist funcional", () => {
  it("as 8 operações administrativas estão no gate administrativo com as capabilities de §9.2", () => {
    const esperado: Readonly<Record<string, string>> = {
      "colaborador.ocupacao.definir": "org.structure.manage",
      "colaborador.ocupacao.encerrar": "org.structure.manage",
      "estrutura.reporting.definir": "org.structure.manage",
      "estrutura.reporting.encerrar": "org.structure.manage",
      "estrutura.responsabilidade.definir": "org.structure.manage",
      "estrutura.responsabilidade.encerrar": "org.structure.manage",
      "estrutura.sucessao.registrar": "org.structure.manage",
      "colaborador.catalogo.bootstrap": "org.catalog.manage",
    };

    for (const [operacao, capability] of Object.entries(esperado)) {
      expect(DEFINICAO_POR_OPERACAO[operacao as OperacaoColaborador].gate, operacao).toBe(
        "administrativo"
      );
      expect(DEFINICAO_POR_OPERACAO[operacao as OperacaoColaborador].capability, operacao).toBe(
        capability
      );
    }
    expect(new Set(OPERACOES_ADMINISTRATIVAS)).toEqual(new Set(Object.keys(esperado)));
  });

  it("as capabilities administrativas NÃO têm alvo no engine (D19 é o único gate possível)", () => {
    const alvo = { type: "collaborator", id: ID_NEUTRO } as const;

    for (const operacao of OPERACOES_ADMINISTRATIVAS) {
      const capability = capabilityCanonica(DEFINICAO_POR_OPERACAO[operacao].capability);
      expect(capability, operacao).toBe(DEFINICAO_POR_OPERACAO[operacao].capability);
      expect(
        isCapabilityTargetCompatible(capability as Capability, alvo),
        operacao
      ).toBe(false);
    }
    for (const operacao of OPERACOES_FUNCIONAIS) {
      const capability = capabilityCanonica(DEFINICAO_POR_OPERACAO[operacao].capability) as Capability;
      expect(isCapabilityTargetCompatible(capability, alvo), operacao).toBe(true);
    }
  });

  it("o gate administrativo é decidido pelas capabilities efetivas (nunca pelo engine funcional)", () => {
    expect(coreFonte as string).toContain("avaliarGateAdministrativo");
    expect(coreFonte as string).toContain("resolverCapabilitiesEfetivas");
    expect(coreFonte as string).toContain("ehOperacaoFuncional");
    // A Edge liga o resolvedor de capabilities efetivas (D19) ao núcleo.
    expect(edgeFonte as string).toContain("resolverCapabilitiesEfetivas");
    expect(edgeFonte as string).toContain("resolver_capabilities_escopos_efetivas");
  });

  it("nenhuma operação administrativa aparece na allowlist funcional das RPCs do domínio", () => {
    const funcionaisDeclaradas = OPERACOES_FUNCIONAIS.map(
      (operacao) => CONTRATO_EDGE_RPC[operacao].rpc
    );
    for (const operacao of OPERACOES_ADMINISTRATIVAS) {
      expect(funcionaisDeclaradas).not.toContain(CONTRATO_EDGE_RPC[operacao].rpc);
    }
  });
});

describe("F5-07 — a Edge importa apenas módulos REAIS do repositório", () => {
  it("todo import relativo de `index.ts`/`core.ts` resolve para um arquivo existente", () => {
    const arquivos: readonly (readonly [string, string])[] = [
      ["supabase/functions/colaboradores", edgeFonte as string],
      ["supabase/functions/colaboradores", coreFonte as string],
    ];
    const divergencias: string[] = [];

    for (const [diretorio, fonte] of arquivos) {
      for (const especificador of especificadoresDeImport(fonte)) {
        if (!especificador.startsWith(".")) continue;
        const caminho = caminhoResolvido(diretorio, especificador);
        if (!(chaveDoModulo(caminho) in MODULOS_DO_REPOSITORIO)) {
          divergencias.push(`${diretorio}/${especificador} → ${caminho} não existe`);
        }
      }
    }

    expect(divergencias).toEqual([]);
  });
});
