import { describe, expect, it } from "vitest";
import edgeMetasFonte from "../../supabase/functions/metas/index.ts?raw";
import edgeCoreFonte from "../../supabase/functions/metas/core.ts?raw";
import edgeContratoFonte from "../../supabase/functions/metas/contrato.ts?raw";
import migracaoP2Fonte from "../../supabase/migrations/20260923000000_f5_10_p2_goals_rpc.sql?raw";
import migracaoP3Fonte from "../../supabase/migrations/20260924000000_f5_10_p3_approvals_rpc.sql?raw";
import migracaoP4Fonte from "../../supabase/migrations/20260925000000_f5_10_p4_authorization_rls.sql?raw";
import adapterFonte from "../infrastructure/supabase/metas/edgeMetas.ts?raw";
import contratoFonteFonte from "../infrastructure/supabase/metas/contrato.ts?raw";
import {
  CHAVES_POR_OPERACAO,
  DEFINICAO_POR_OPERACAO,
  OPERACOES_META,
  RPC_POR_OPERACAO,
  capacidadeAdministrativaDaOperacao,
  ehOperacaoFuncional,
  ehOperacaoMeta,
  validarEntradaMeta,
} from "../infrastructure/supabase/metas/contrato.ts";
import { capabilityCanonica } from "./catalogoCapabilities.ts";

/**
 * F5-10 P5 (Issue #218) — CONTRATO Edge → RPC do caminho soberano de METAS.
 *
 * A fronteira confiável chama as funções SQL por NOME + ARGUMENTOS NOMEADOS via
 * PostgREST: um argumento inexistente faz o PostgREST responder "function not
 * found" e a operação inteira quebra (histórico real da F5-06). Este teste lê o
 * código REAL do wiring da Edge (`supabase/functions/metas/index.ts`) e exige
 * correspondência EXATA com as assinaturas verificadas nas migrations P2–P4
 * (`p_payload_hash` NÃO é parâmetro: o hash é derivado server-side — D11).
 *
 * Prova também que:
 * - `service_role` só aparece como EXECUTOR no wiring, nunca no núcleo testável;
 * - a ordem do núcleo é identidade → gate → execução (decisão antes de execução);
 * - as 10 RPCs soberanas de meta continuam `SECURITY INVOKER` com `EXECUTE` só
 *   `service_role` e nenhuma capability nova é criada;
 * - a allowlist do contrato recusa campos de identidade/autoridade e
 *   `goal.approve` NÃO implica `goal.write` (D7/D9).
 */

/**
 * Assinatura REAL de cada RPC, conferida nas migrations P2/P3/P4 (§G.5 do
 * reconhecimento). A ordem aqui é a ordem canônica do `create function`; a
 * comparação é feita por CONJUNTO (a fronteira pode reordenar chaves).
 */
const CONTRATO_EDGE_RPC: Readonly<Record<string, readonly string[]>> = {
  meta_criar: [
    "p_organization_id",
    "p_cycle_id",
    "p_collaborator_id",
    "p_tipo",
    "p_descricao",
    "p_kpi",
    "p_valor_alvo",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  meta_editar: [
    "p_goal_id",
    "p_organization_id",
    "p_descricao",
    "p_kpi",
    "p_valor_alvo",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  meta_atualizar_progresso: [
    "p_goal_id",
    "p_organization_id",
    "p_resultado_atual",
    "p_progresso_percentual",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  meta_finalizar: [
    "p_goal_id",
    "p_organization_id",
    "p_resultado_final",
    "p_atingida",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  meta_revisar_finalizacao: [
    "p_goal_id",
    "p_organization_id",
    "p_resultado_final",
    "p_atingida",
    "p_motivo",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  meta_excluir: [
    "p_goal_id",
    "p_organization_id",
    "p_motivo",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  meta_definir_limites_do_ciclo: [
    "p_cycle_id",
    "p_organization_id",
    "p_tipo",
    "p_quantidade",
    "p_motivo",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  meta_aprovar: [
    "p_goal_id",
    "p_organization_id",
    "p_papel",
    "p_motivo",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  meta_listar_por_escopo: ["p_organization_id", "p_cycle_id", "p_actor_user_profile_id"],
};

/**
 * O mapa operação → RPC é o do CONTRATO-FONTE (`RPC_POR_OPERACAO`, importado):
 * a guarda não mantém uma segunda cópia que pudesse divergir da produção.
 */

/** `meta_invalidar_aprovacoes` é INTERNA às mutações (§13) — não é operação. */
const OPERACOES_META_CONTRATADAS = [
  "goal.criar",
  "goal.editar",
  "goal.atualizar_progresso",
  "goal.finalizar",
  "goal.revisar_finalizacao",
  "goal.excluir",
  "goal.aprovar",
  "goal.definir_limites_do_ciclo",
  "goal.listar_por_escopo",
] as const;

/** UUIDs sintéticos (nenhum dado real) usados nas provas de FORMA do contrato. */
const ORG = "11111111-1111-4111-8111-111111111111";
const OPERACAO = "66666666-6666-4666-8666-666666666666";
const CICLO = "55555555-5555-4555-8555-555555555555";
const GOAL = "88888888-8888-4888-8888-888888888888";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";

interface ChamadaRpc {
  readonly funcao: string;
  readonly argumentos: readonly string[];
  readonly linha: number;
}

function semComentarios(codigo: string): string {
  return codigo
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

/**
 * Código SEM comentários (linha e bloco): as guardas de "não reimplementar o
 * domínio" e de "service_role só como executor" valem para o CÓDIGO — os
 * cabeçalhos documentam justamente o que a Edge NÃO faz.
 */
function codigoSemComentarios(codigo: string): string {
  return codigo
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

function extrairChamadasRpc(codigo: string): ChamadaRpc[] {
  const limpo = semComentarios(codigo);
  const chamadas: ChamadaRpc[] = [];
  const padrao = /\.rpc\(\s*"([^"]+)"\s*,\s*\{/g;

  let correspondencia: RegExpExecArray | null;
  while ((correspondencia = padrao.exec(limpo)) !== null) {
    const funcao = correspondencia[1]!;
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
      if (chave) argumentos.push(chave[1]!);
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
      linha: limpo.slice(0, correspondencia.index).split("\n").length,
    });
  }
  return chamadas;
}

const chamadas = extrairChamadasRpc(edgeMetasFonte as string);
const chamadasMeta = chamadas.filter((chamada) => chamada.funcao.startsWith("meta_"));
/** Resolvedores de fronteira que a Edge `metas` está autorizada a chamar. */
const RESOLVEDORES_ESPERADOS = [
  "resolver_collaborador_vinculado",
  "resolver_capabilities_escopos_efetivas",
  "resolver_alvos_escopo",
] as const;

/**
 * Fontes SQL do schema (migrations). Usadas para provar que a Edge só chama
 * funções que EXISTEM — um nome divergente faz o PostgREST responder
 * "function not found" e quebra a operação (BLOCKER 1 da F5-06).
 */
const MIGRACOES: Readonly<Record<string, string>> = import.meta.glob(
  "../../supabase/migrations/*.sql",
  { query: "?raw", import: "default", eager: true }
) as Readonly<Record<string, string>>;
const SQL_DO_SCHEMA = Object.values(MIGRACOES).join("\n");

/** Bloco DD/ACL da P4 que redefine e reafirma as 10 RPCs soberanas de meta. */
const MIGRACOES_METAS = [migracaoP2Fonte, migracaoP3Fonte, migracaoP4Fonte].join("\n");

/**
 * Blocos de `create or replace function` da RPC (nome → corpo até o `$$` do
 * plpgsql). É onde vivem `security invoker` e o `search_path = public`. Uma
 * função redefinida em P2/P3/P4 rende MAIS de um bloco: todos são conferidos.
 */
function blocosDaFuncao(sql: string, nome: string): readonly string[] {
  const blocos: string[] = [];
  // Marcador RESTRITO ao `create or replace` REAL: a ACL (`revoke all on
  // function public.meta_x(`) e as guardas de catálogo citam o mesmo nome e
  // produziriam blocos falsos, sem `security invoker`.
  const marcador = `create or replace function public.${nome}(`;
  let indice = sql.indexOf(marcador);
  while (indice !== -1) {
    const separador = sql.indexOf("$$", indice);
    blocos.push(separador === -1 ? sql.slice(indice) : sql.slice(indice, separador));
    indice = sql.indexOf(marcador, indice + marcador.length);
  }
  return blocos;
}

describe("F5-10 P5 — contrato Edge → RPC (nome + argumentos nomeados)", () => {
  it("a extração encontra as NOVE RPCs de operação da Edge `metas`", () => {
    const nomes = Array.from(new Set(chamadasMeta.map((chamada) => chamada.funcao))).sort();
    expect(nomes).toEqual(Object.keys(CONTRATO_EDGE_RPC).sort());
  });

  it("a Edge não chama NENHUMA RPC de meta fora do contrato (nada de `meta_invalidar_aprovacoes`)", () => {
    const proibidas = chamadasMeta.filter(
      (chamada) => !Object.prototype.hasOwnProperty.call(CONTRATO_EDGE_RPC, chamada.funcao)
    );
    expect(proibidas.map((chamada) => `${chamada.funcao}:${chamada.linha}`)).toEqual([]);
    // `meta_invalidar_aprovacoes` é interna às mutações (§13) e NÃO é operação
    // da Edge: nem o wiring, nem o adapter, nem a allowlist a expõem.
    for (const [arquivo, fonte] of [
      ["index.ts", edgeMetasFonte as string],
      ["edgeMetas.ts", adapterFonte as string],
    ] as const) {
      expect(codigoSemComentarios(fonte), arquivo).not.toContain("meta_invalidar_aprovacoes");
      expect(codigoSemComentarios(fonte), arquivo).not.toContain("goal.invalidar_aprovacoes");
    }
    expect(OPERACOES_META as readonly string[]).not.toContain("goal.invalidar_aprovacoes");
  });

  it("além das RPCs de operação, o wiring só chama resolvedores já existentes no schema", () => {
    const outras = Array.from(
      new Set(
        chamadas
          .filter(
            (chamada) =>
              !chamada.funcao.startsWith("meta_") &&
              chamada.funcao !== "f5_10_aprovador_congelado"
          )
          .map((chamada) => chamada.funcao)
      )
    );
    expect(outras.sort()).toEqual([...RESOLVEDORES_ESPERADOS].sort());
    // O resolvedor de aprovador CONGELADO (P3/P4) é chamado só para
    // `goal.approve`: dois papéis, nenhuma função nova inventada na fronteira.
    expect(chamadas.filter((c) => c.funcao === "f5_10_aprovador_congelado")).toHaveLength(2);
  });

  it("TODA função chamada pela Edge existe no schema (guard do BLOCKER 1)", () => {
    const nomes = Array.from(new Set(chamadas.map((chamada) => chamada.funcao)));
    expect(nomes.length).toBeGreaterThanOrEqual(12);

    const inexistentes = nomes.filter(
      (funcao) => !SQL_DO_SCHEMA.includes(`function public.${funcao}(`)
    );
    expect(inexistentes).toEqual([]);
  });

  it("os argumentos de cada RPC batem EXATAMENTE com a assinatura real das migrations", () => {
    const problemas: string[] = [];

    for (const [funcao, esperado] of Object.entries(CONTRATO_EDGE_RPC)) {
      const chamada = chamadasMeta.find((item) => item.funcao === funcao);
      if (!chamada) {
        problemas.push(`${funcao}: a Edge não chama esta RPC`);
        continue;
      }
      const enviado = [...chamada.argumentos].sort();
      const contrato = [...esperado].sort();
      if (JSON.stringify(enviado) !== JSON.stringify(contrato)) {
        problemas.push(
          `linha ${chamada.linha}: ${funcao} envia [${enviado.join(", ")}] ` +
            `mas a assinatura exige [${contrato.join(", ")}]`
        );
      }
    }

    expect(problemas).toEqual([]);
  });

  it("toda RPC de operação recebe o ATOR verificado e nunca `p_payload_hash`", () => {
    const proibidos = [
      "p_payload_hash",
      "p_actor_id",
      "p_author_id",
      "p_actor_collaborator_id",
      "p_actor_membership_id",
    ];
    for (const chamada of chamadasMeta) {
      for (const proibido of proibidos) {
        expect(chamada.argumentos, `${chamada.funcao}:${proibido}`).not.toContain(proibido);
      }
      // O ator é SEMPRE o `auth.uid` verificado — o hash é derivado server-side.
      expect(chamada.argumentos, chamada.funcao).toContain("p_actor_user_profile_id");
    }
    // `p_operation_id` (idempotência, D11) vai para as 8 operações de mutação/
    // criação — exceto `meta_listar_por_escopo`, cuja assinatura real é de
    // LEITURA e não possui esse parâmetro (não há evento de trilha).
    for (const [funcao, esperado] of Object.entries(CONTRATO_EDGE_RPC)) {
      const chamada = chamadasMeta.find((item) => item.funcao === funcao);
      expect(chamada, funcao).toBeDefined();
      const comOperationId = (chamada?.argumentos ?? []).includes("p_operation_id");
      expect(comOperationId, funcao).toBe(esperado.includes("p_operation_id"));
      expect(esperado.includes("p_operation_id"), funcao).toBe(
        funcao !== "meta_listar_por_escopo"
      );
    }
    // Nenhum arquivo do caminho soberano menciona o hash do corpo (D11).
    for (const [arquivo, fonte] of [
      ["core.ts", edgeCoreFonte as string],
      ["index.ts", edgeMetasFonte as string],
      ["contrato.ts", edgeContratoFonte as string],
      ["edgeMetas.ts", adapterFonte as string],
    ] as const) {
      expect(codigoSemComentarios(fonte).includes("p_payload_hash"), arquivo).toBe(false);
    }
  });

  it("o trio da Edge existe e a pasta reexporta o contrato-fonte (fonte única)", () => {
    // O reexport mantém `index`/`core`/`contrato` sem duplicar a allowlist.
    expect(edgeContratoFonte as string).toContain(
      'export * from "../../../src/infrastructure/supabase/metas/contrato.ts";'
    );
    // Nenhuma cópia local da lista de operações no lado da Edge.
    expect(edgeContratoFonte as string).not.toContain("DEFINICAO_POR_OPERACAO = {");
  });
});

describe("F5-10 P5 — mapa de operações e capabilities (nenhuma capability nova)", () => {
  it("o mapa cobre EXATAMENTE as nove operações contratadas", () => {
    expect([...OPERACOES_META].sort()).toEqual([...OPERACOES_META_CONTRATADAS].sort());
    expect(Object.keys(DEFINICAO_POR_OPERACAO).sort()).toEqual([...OPERACOES_META_CONTRATADAS].sort());
  });

  it("toda capability do mapa é CANÔNICA e de metas (nunca alias, nunca nova)", () => {
    const deMetas = ["goal.read", "goal.write", "goal.approve", "cycle.manage"];
    for (const operacao of OPERACOES_META) {
      const definicao = DEFINICAO_POR_OPERACAO[operacao];
      const canonica = capabilityCanonica(definicao.capability);
      expect(canonica, operacao).toBe(definicao.capability);
      expect(deMetas, operacao).toContain(definicao.capability);
      // A ponte booleana `funcional` consumida pelo núcleo da Edge é DERIVADA de
      // `gate` (fonte da verdade): as duas leituras nunca divergem.
      expect(definicao.funcional, operacao).toBe(definicao.gate === "funcional");
      expect(ehOperacaoFuncional(operacao), operacao).toBe(definicao.funcional);
    }
    // O servidor exige exatamente essas 4 capabilities (§13/F5-10 P4:294-305):
    // nenhuma operação inventa uma capability própria de metas.
    expect(
      Array.from(new Set(Object.values(DEFINICAO_POR_OPERACAO).map((d) => d.capability))).sort()
    ).toEqual(["cycle.manage", "goal.approve", "goal.read", "goal.write"]);
  });

  it("a allowlist por operação cobre exatamente as chaves que o validador aceita", () => {
    const comuns = ["organization_id", "operacao", "operation_id"];
    for (const operacao of OPERACOES_META) {
      const chaves = CHAVES_POR_OPERACAO[operacao];
      // As três chaves comuns estão SEMPRE presentes; nada de chave duplicada.
      for (const comum of comuns) expect(chaves, `${operacao}:${comum}`).toContain(comum);
      expect(new Set(chaves).size, operacao).toBe(chaves.length);
      // Nenhuma chave de identidade/autoridade entra na allowlist de NENHUMA
      // operação (a lista é a fonte da recusa por campo desconhecido).
      for (const proibida of [
        "status",
        "aprovado",
        "domainState",
        "excluida",
        "version",
        "payload_hash",
        "actor_id",
        "actorId",
        "actor_user_profile_id",
        "membership_id",
        "membershipId",
        "capability",
        "role",
        "cargo",
        "funcao",
      ]) {
        expect(chaves, `${operacao}:${proibida}`).not.toContain(proibida);
      }
    }
    // O alvo de cada operação está na SUA allowlist (nenhum alvo aceito por
    // engano em outra operação, nenhuma versão onde não há linha existente).
    expect(CHAVES_POR_OPERACAO["goal.criar"]).toContain("cycle_id");
    expect(CHAVES_POR_OPERACAO["goal.criar"]).toContain("collaborator_id");
    expect(CHAVES_POR_OPERACAO["goal.criar"]).not.toContain("expected_version");
    expect(CHAVES_POR_OPERACAO["goal.listar_por_escopo"]).toContain("cycle_id");
    expect(CHAVES_POR_OPERACAO["goal.listar_por_escopo"]).not.toContain("expected_version");
    for (const operacao of [
      "goal.editar",
      "goal.atualizar_progresso",
      "goal.finalizar",
      "goal.revisar_finalizacao",
      "goal.excluir",
      "goal.aprovar",
    ] as const) {
      expect(CHAVES_POR_OPERACAO[operacao], operacao).toContain("goal_id");
      expect(CHAVES_POR_OPERACAO[operacao], operacao).toContain("expected_version");
    }
  });

  it("o gate de cada operação é o fixado no contrato congelado (D7/D9/D21)", () => {
    expect(Object.fromEntries(
      Object.entries(DEFINICAO_POR_OPERACAO).map(([operacao, definicao]) => [
        operacao,
        `${definicao.gate}/${definicao.capability}`,
      ])
    )).toEqual({
      "goal.criar": "funcional/goal.write",
      "goal.editar": "funcional/goal.write",
      "goal.atualizar_progresso": "funcional/goal.write",
      "goal.finalizar": "funcional/goal.write",
      "goal.revisar_finalizacao": "funcional/goal.write",
      "goal.excluir": "funcional/goal.write",
      "goal.aprovar": "funcional/goal.approve",
      "goal.definir_limites_do_ciclo": "funcional/cycle.manage",
      "goal.listar_por_escopo": "administrativo/goal.read",
    });
  });

  it("`goal.approve` NÃO implica `goal.write` e a única operação administrativa é a leitura de escopo", () => {
    expect(DEFINICAO_POR_OPERACAO["goal.aprovar"].capability).toBe("goal.approve");
    expect(DEFINICAO_POR_OPERACAO["goal.aprovar"].capability).not.toBe("goal.write");
    expect(DEFINICAO_POR_OPERACAO["goal.editar"].capability).not.toBe("goal.approve");

    const administrativas = OPERACOES_META.filter((operacao) => !ehOperacaoFuncional(operacao));
    expect(administrativas).toEqual(["goal.listar_por_escopo"]);
    expect(capacidadeAdministrativaDaOperacao("goal.listar_por_escopo")).toBe("goal.read");
    for (const operacao of OPERACOES_META) {
      if (operacao === "goal.listar_por_escopo") continue;
      // Operação funcional NUNCA devolve capability administrativa: nenhum
      // caminho alternativo de decisão (sem default permissivo).
      expect(capacidadeAdministrativaDaOperacao(operacao), operacao).toBeNull();
    }
  });

  it("operação desconhecida é recusada e nenhuma operação de outro domínio entra", () => {
    for (const desconhecida of [
      "goal.invalidar_aprovacoes",
      "goal.listar",
      "meta.criar",
      "cycle.editar",
      "evaluation.criar",
      undefined,
      null,
      42,
    ]) {
      expect(ehOperacaoMeta(desconhecida), String(desconhecida)).toBe(false);
    }
    for (const operacao of OPERACOES_META_CONTRATADAS) {
      expect(ehOperacaoMeta(operacao), operacao).toBe(true);
    }
  });
});

describe("F5-10 P5 — invariantes de forma do contrato (allowlist é forma, nunca autoridade)", () => {
  it("a RPC de cada operação está mapeada 1:1 com o contrato-fonte", () => {
    expect(Object.keys(RPC_POR_OPERACAO).sort()).toEqual([...OPERACOES_META_CONTRATADAS].sort());
    for (const funcao of Object.values(RPC_POR_OPERACAO)) {
      expect(Object.keys(CONTRATO_EDGE_RPC), funcao).toContain(funcao);
    }
  });

  it("a Edge e o adapter não inventam campos de autoridade/identidade", () => {
    // A allowlist do contrato é a única superfície de forma: nenhum arquivo do
    // caminho soberano pode montar `status`, `aprovado`, `domainState`,
    // `excluida`, `version`, `payload_hash`, `actor*`, `membership*`,
    // `capability`, `role`, `cargo` ou `funcao` a partir do corpo.
    const camposProibidos = [
      "domainState",
      "membership_id",
      "membershipId",
      "actor_user_profile_id",
      "actorId",
      "payload_hash",
      "payloadHash",
    ];
    for (const [arquivo, fonte] of [
      ["contrato.ts", edgeContratoFonte as string],
      ["edgeMetas.ts", adapterFonte as string],
    ] as const) {
      const codigo = codigoSemComentarios(fonte);
      for (const campo of camposProibidos) {
        expect(codigo, `${arquivo}:${campo}`).not.toContain(campo);
      }
    }
  });

  it("a allowlist RECUSA campos de identidade/autoridade em qualquer operação", () => {
    // Corpo COMPLETO de `goal.criar` (todos os parâmetros da RPC, por segurança):
    // é a base VÁLIDA que isola o campo proibido como causa da recusa.
    const base = {
      organization_id: ORG,
      operacao: "goal.criar",
      operation_id: OPERACAO,
      cycle_id: CICLO,
      collaborator_id: COLABORADOR,
      tipo: "INDIVIDUAL",
      descricao: "Meta sintetica de teste",
      kpi: "Indicador sintetico",
      valor_alvo: "100",
    };
    expect(validarEntradaMeta(base).ok).toBe(true);

    const proibidos: readonly (readonly [string, unknown])[] = [
      ["status", "ATIVO"],
      ["aprovado", true],
      ["domainState", { metaExistente: true }],
      ["excluida", false],
      ["version", 1],
      ["payload_hash", "0".repeat(64)],
      ["actorId", COLABORADOR],
      ["actor_id", COLABORADOR],
      ["actor_user_profile_id", COLABORADOR],
      ["actorUserId", COLABORADOR],
      ["membershipId", COLABORADOR],
      ["membership_id", COLABORADOR],
      ["capability", "goal.write"],
      ["role", "admin"],
      ["cargo", "Diretor"],
      ["funcao", "GERENTE"],
      ["papel_autorizado", "COORDENADOR"],
    ];
    const recusados: string[] = [];
    for (const [campo, valor] of proibidos) {
      const validacao = validarEntradaMeta({ ...base, [campo]: valor });
      if (validacao.ok) recusados.push(campo);
    }
    expect(recusados).toEqual([]);
  });

  it("a allowlist é POR OPERAÇÃO e a operação desconhecida não tem default permissivo", () => {
    const base = {
      organization_id: ORG,
      operacao: "goal.criar",
      operation_id: OPERACAO,
      cycle_id: CICLO,
      collaborator_id: COLABORADOR,
      tipo: "INDIVIDUAL",
      descricao: "Meta sintetica de teste",
      kpi: "Indicador sintetico",
      valor_alvo: "100",
    };
    expect(validarEntradaMeta(base).ok).toBe(true);
    // Campo de OUTRA operação ⇒ INVALID_INPUT (a allowlist não é global).
    for (const extra of [
      { goal_id: GOAL },
      { expected_version: 1 },
      { resultado_final: "concluida" },
      { papel: "GERENTE" },
    ]) {
      expect(validarEntradaMeta({ ...base, ...extra }).ok, JSON.stringify(extra)).toBe(false);
    }

    // Operação desconhecida ⇒ INVALID_INPUT (nenhum default permissivo).
    for (const operacao of [
      "goal.invalidar_aprovacoes",
      "goal.tudo",
      "cycle.criar",
      "meta_criar",
      "",
      7,
      undefined,
    ]) {
      const validacao = validarEntradaMeta({ ...base, operacao });
      expect(validacao.ok, String(operacao)).toBe(false);
      if (!validacao.ok) expect(validacao.code, String(operacao)).toBe("INVALID_INPUT");
    }
    // Corpo sem forma de objeto também é recusado (fail-closed).
    for (const corpo of [null, undefined, [], "{}", 42]) {
      expect(validarEntradaMeta(corpo).ok, JSON.stringify(corpo)).toBe(false);
    }
  });

  it("o contrato-fonte documenta os campos que a allowlist NÃO aceita", () => {
    // Texto CRU (com comentários): a proibição de identidade/autoridade está
    // escrita no cabeçalho do contrato-fonte, espelhando `ciclos/contrato.ts`.
    const fonte = contratoFonteFonte as string;
    for (const campo of [
      "status",
      "aprovado",
      "domainState",
      "excluida",
      "version",
      "payload_hash",
      "capability",
      "role",
      "cargo",
      "funcao",
    ]) {
      expect(fonte, campo).toContain(campo);
    }
    // E a Edge apenas REEXPORTA esse contrato (nenhuma cópia local da lista).
    expect(edgeContratoFonte as string).toContain(
      'export * from "../../../src/infrastructure/supabase/metas/contrato.ts";'
    );
  });
});

describe("F5-10 P5 — `service_role` só no wiring e a RPC só DEPOIS do gate", () => {
  it("o núcleo testável NÃO menciona a credencial privilegiada", () => {
    const codigoCore = codigoSemComentarios(edgeCoreFonte as string);
    expect(codigoCore).not.toContain("service_role");
    expect(codigoCore).not.toContain("SERVICE_ROLE");
    expect(codigoCore).not.toContain("serviceRole");
    expect(codigoCore).not.toContain("createClient");
    // O wiring é o ÚNICO que cria o cliente privilegiado.
    expect(codigoSemComentarios(edgeMetasFonte as string)).toContain("SUPABASE_SERVICE_ROLE_KEY");
  });

  it("a ordem no núcleo é identidade → gate → execução (indexOf)", () => {
    const codigoCore = codigoSemComentarios(edgeCoreFonte as string);

    const posIdentidade = codigoCore.indexOf("deps.resolveCaller(");
    const posGate = codigoCore.indexOf("const negacao = await avaliarGate");
    const posExecucao = codigoCore.indexOf("await deps.executarRpc(");

    expect(posIdentidade).toBeGreaterThan(-1);
    expect(posGate).toBeGreaterThan(posIdentidade);
    // A RPC privilegiada só é chamada DEPOIS da decisão de autorização.
    expect(posExecucao).toBeGreaterThan(posGate);
    // E o gate funcional usa o Policy Engine real — nenhum atalho local.
    expect(codigoCore).toContain("deps.avaliarAutorizacao(");
    expect(codigoCore).toContain("resolverCapabilitiesEfetivas");
  });

  it("o núcleo não importa APIs de runtime nem o engine diretamente", () => {
    const codigoCore = codigoSemComentarios(edgeCoreFonte as string);
    for (const proibido of ["Deno.", "Deno.serve", "process.env", "avaliarOperacaoAutorizacao("]) {
      expect(codigoCore, proibido).not.toContain(proibido);
    }
    // A tradução para o engine é responsabilidade do wiring.
    expect(codigoSemComentarios(edgeMetasFonte as string)).toContain("avaliarOperacaoAutorizacao");
  });
});

describe("F5-10 P5 — ACL e `SECURITY INVOKER` das 10 RPCs soberanas de meta", () => {
  it("as 10 RPCs de meta continuam `security invoker` (nenhum DEFINER novo)", () => {
    const faltando: string[] = [];
    for (const nome of [
      "meta_criar",
      "meta_editar",
      "meta_atualizar_progresso",
      "meta_finalizar",
      "meta_revisar_finalizacao",
      "meta_excluir",
      "meta_definir_limites_do_ciclo",
      "meta_aprovar",
      "meta_invalidar_aprovacoes",
      "meta_listar_por_escopo",
    ]) {
      const blocos = blocosDaFuncao(MIGRACOES_METAS, nome);
      if (blocos.length === 0) {
        faltando.push(`${nome}: definição ausente nas migrations de metas`);
        continue;
      }
      for (const [indice, bloco] of blocos.entries()) {
        if (bloco.includes("security definer")) {
          faltando.push(`${nome}[${indice}]: SECURITY DEFINER inesperado`);
        }
        if (!bloco.includes("security invoker")) {
          faltando.push(`${nome}[${indice}]: sem SECURITY INVOKER`);
        }
        if (!bloco.includes("set search_path = public")) {
          faltando.push(`${nome}[${indice}]: search_path fixo ausente`);
        }
      }
    }
    expect(faltando).toEqual([]);
  });

  it("o `EXECUTE` das 10 RPCs é SÓ de `service_role` (ACL textual da P4 §7)", () => {
    // Toda assinatura REAL precisa aparecer fechada na P4 (prova de que o
    // revoke/grant foi reafirmado sobre a função vigente, não sobre sobrecarga
    // antiga das fases P2/P3).
    for (const assinatura of [
      "uuid, uuid, uuid, text, text, text, text, uuid, uuid", // meta_criar
      "uuid, uuid, text, text, text, integer, uuid, uuid", // meta_editar
      "uuid, uuid, text, integer, integer, uuid, uuid", // meta_atualizar_progresso
      "uuid, uuid, text, boolean, integer, uuid, uuid", // meta_finalizar
      "uuid, uuid, text, boolean, text, integer, uuid, uuid", // meta_revisar_finalizacao
      "uuid, uuid, text, integer, uuid, uuid", // meta_excluir / meta_invalidar_aprovacoes
      "uuid, uuid, text, integer, text, integer, uuid, uuid", // meta_definir_limites_do_ciclo
      "uuid, uuid, text, text, integer, uuid, uuid", // meta_aprovar
      "uuid, uuid, uuid", // meta_listar_por_escopo
    ]) {
      expect(
        (migracaoP4Fonte as string).includes(`(${assinatura})`),
        `assinatura ausente: ${assinatura}`
      ).toBe(true);
    }

    // Bloco §7 da P4: entre o primeiro revoke das RPCs de meta e o `do $$` da
    // guarda final ficam TODOS os revokes/grants das 10 RPCs soberanas.
    const inicio = (migracaoP4Fonte as string).indexOf(
      "revoke all on function public.meta_criar("
    );
    const fim = (migracaoP4Fonte as string).indexOf("do $$", inicio);
    expect(inicio).toBeGreaterThan(-1);
    expect(fim).toBeGreaterThan(inicio);
    const bloco = (migracaoP4Fonte as string).slice(inicio, fim);

    const revogacoes =
      bloco.match(
        /revoke all on function public\.meta_[a-z_]+\([^)]*\)[\s\S]{0,40}?from public, anon, authenticated;/g
      ) ?? [];
    // 9 operações + meta_invalidar_aprovacoes (interna às mutações) = 10 RPCs.
    expect(revogacoes).toHaveLength(10);

    const concedidas = Array.from(
      bloco.matchAll(
        /grant execute on function public\.(meta_[a-z_]+)\([^)]*\)[\s\S]{0,20}?to ([a-z_]+);/g
      )
    ).map((achado) => `${achado[1]}->${achado[2]}`);
    expect(concedidas).toHaveLength(10);
    for (const concessao of concedidas) {
      expect(concessao, concessao).toMatch(/->service_role$/);
    }
    // Nenhuma RPC de meta é executável por cliente (authenticated/anon/public).
    expect(bloco).not.toMatch(/grant execute[\s\S]{0,120}?to (authenticated|anon|public);/);

    // O validador da própria P4 reafirma os três invariantes NO BANCO.
    expect(migracaoP4Fonte as string).toContain("EXECUTE exposto a cliente");
    expect(migracaoP4Fonte as string).toContain("SECURITY DEFINER inesperado");
    expect(migracaoP4Fonte as string).toContain("search_path ausente");
    for (const rpc of Object.keys(CONTRATO_EDGE_RPC)) {
      expect(migracaoP4Fonte as string, rpc).toContain(`public.${rpc}(`);
    }
  });

  it("nenhuma capability nova aparece nas migrations de metas", () => {
    for (const [nome, fonte] of [
      ["P2", migracaoP2Fonte as string],
      ["P3", migracaoP3Fonte as string],
      ["P4", migracaoP4Fonte as string],
    ] as const) {
      expect(fonte, nome).not.toContain("insert into public.capabilities");
      expect(fonte, nome).not.toContain("update public.capabilities");
    }
    // O catálogo canônico segue com as três capabilities de meta (D6).
    for (const capability of ["goal.read", "goal.write", "goal.approve"]) {
      expect(SQL_DO_SCHEMA, capability).toContain(`'${capability}'`);
    }
  });
});

describe("F5-10 P5 — a Edge não replica o domínio de metas", () => {
  it("nenhum estado de meta/ciclo é codificado na fronteira", () => {
    const fontes = [
      codigoSemComentarios(edgeMetasFonte as string),
      codigoSemComentarios(edgeCoreFonte as string),
    ];
    for (const fonte of fontes) {
      for (const estado of [
        "NEGOCIO_PROJETO",
        "ATINGIDA",
        "NAO_ATINGIDA",
        "EM_ANDAMENTO",
        "GESTAO_CADEIA",
        "GESTAO_DIRETA",
      ]) {
        expect(fonte, estado).not.toContain(estado);
      }
      // O estado da meta NUNCA é comparado na fronteira: quem decide é o probe
      // do domínio (Policy Engine) + a precondição da RPC.
      expect(fonte).not.toMatch(/status\s*===\s*"(ATINGIDA|NAO_ATINGIDA|EM_ANDAMENTO)"/);
    }
  });

  it("a fronteira não compara versão, não materializa e não calcula progresso", () => {
    for (const proibido of [
      "expectedVersion ===",
      "expectedVersion >",
      "expectedVersion <",
      "progresso_percentual *",
      "/ 100",
      "sha256",
      "materializar",
      "sobrepo",
    ]) {
      expect(codigoSemComentarios(edgeMetasFonte as string), proibido).not.toContain(proibido);
      expect(codigoSemComentarios(edgeCoreFonte as string), proibido).not.toContain(proibido);
    }
    // O hash canônico é derivado server-side (D11) e NÃO é parâmetro da Edge.
    expect(codigoSemComentarios(edgeCoreFonte as string)).not.toContain("payloadHash");
    expect(codigoSemComentarios(edgeMetasFonte as string)).not.toContain("payloadHash");
  });

  it("a tradução de erro usa os prefixos `F5_10_*` (e só eles)", () => {
    const codigoCore = codigoSemComentarios(edgeCoreFonte as string);
    expect(codigoCore).toContain("F5_10_FORBIDDEN");
    expect(codigoCore).toContain("F5_10_NOT_FOUND");
    expect(codigoCore).toContain("F5_10_CONFLICT");
    expect(codigoCore).toContain("F5_10_INVALID_INPUT");
    // Nenhum resquício da fronteira de ciclos no caminho de metas.
    expect(codigoCore).not.toContain("F5_09_");
    expect(codigoSemComentarios(edgeMetasFonte as string)).not.toContain("F5_09_");
  });
});

describe("F5-10 P5 — adapter de cliente espelha o contrato (fail-closed)", () => {
  it("o adapter oferece exatamente as nove operações contratadas", () => {
    for (const operacao of OPERACOES_META_CONTRATADAS) {
      const ocorrencias = (adapterFonte as string).split(`"${operacao}"`).length - 1;
      expect(ocorrencias, operacao).toBe(1);
    }
    expect(adapterFonte as string).toContain('FUNCAO_METAS = "metas"');
  });

  it("nenhuma autoridade ou fallback do lado do cliente (no CÓDIGO)", () => {
    const codigoAdapter = codigoSemComentarios(adapterFonte as string);
    for (const proibido of [
      "service_role",
      "SERVICE_ROLE",
      "localStorage",
      "sessionStorage",
      ".rpc(",
      "metaStorage",
    ]) {
      expect(codigoAdapter, proibido).not.toContain(proibido);
    }
    // A superfície é a Edge, por `functions.invoke`, com fail-closed.
    expect(codigoAdapter).toContain("functions.invoke");
    expect(codigoAdapter).toContain("INTERNAL");
  });
});
