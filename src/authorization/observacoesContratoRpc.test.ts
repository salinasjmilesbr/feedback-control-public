import { describe, expect, it } from "vitest";
import edgeObservacoesFonte from "../../supabase/functions/observacoes/index.ts?raw";
import edgeCoreFonte from "../../supabase/functions/observacoes/core.ts?raw";
import edgeContratoFonte from "../../supabase/functions/observacoes/contrato.ts?raw";
import migracaoP2Fonte from "../../supabase/migrations/20260931000000_f5_11_p2_observacoes_rpc.sql?raw";
import migracaoP3Fonte from "../../supabase/migrations/20260932000000_f5_11_p3_authorization_observacoes.sql?raw";
import adapterFonte from "../infrastructure/supabase/observacoes/edgeObservacoes.ts?raw";
import contratoFonteFonte from "../infrastructure/supabase/observacoes/contrato.ts?raw";
import {
  CHAVES_POR_OPERACAO,
  DEFINICAO_POR_OPERACAO,
  OPERACOES_OBSERVACAO,
  RPC_POR_OPERACAO,
  capacidadeAdministrativaDaOperacao,
  ehOperacaoFuncional,
  validarEntradaObservacao,
} from "../infrastructure/supabase/observacoes/contrato.ts";
import { capabilityCanonica } from "./catalogoCapabilities.ts";

/** UUIDs sintéticos (nenhum dado real) usados nas provas de FORMA. */
const ORG = "11111111-1111-4111-8111-111111111111";
const OPERACAO = "66666666-6666-4666-8666-666666666666";
const CICLO = "55555555-5555-4555-8555-555555555555";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";
const OBSERVACAO = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

/**
 * Valor válido por chave da allowlist — o corpo MÍNIMO VÁLIDO de cada operação,
 * derivado da allowlist REAL (`CHAVES_POR_OPERACAO`), para que a recusa de uma
 * chave proibida seja ATRIBUÍVEL só a ela.
 */
function valorDaChave(
  operacao: (typeof OPERACOES_OBSERVACAO)[number],
  chave: string
): unknown {
  switch (chave) {
    case "operacao":
      // A operação é a PRÓPRIA chave comum transportada (mold `metas`/`observacoes`:
      // `CHAVES_COMUNS = [organization_id, operacao, operation_id]`) — o valor tem
      // de ser o da operação validada, senão a recusa deixaria de ser atribuível.
      return operacao;
    case "organization_id":
      return ORG;
    case "operation_id":
      return OPERACAO;
    case "cycle_id":
      return CICLO;
    case "collaborator_id":
      return COLABORADOR;
    case "observation_id":
      return OBSERVACAO;
    case "tipo":
      return "POSITIVA";
    case "texto":
      return "Observação sintética de teste.";
    case "comunicado":
      return true;
    case "expected_version":
      return 0;
    case "motivo":
      return "Motivo sintético de teste.";
    case "escopo":
      return "SELF";
    case "organizational_unit_id":
      return "33333333-3333-4333-8333-333333333333";
    default:
      throw new Error(`sem valor de teste para a chave ${chave}`);
  }
}

/** Corpo mínimo VÁLIDO de uma operação (chaves da allowlist do contrato). */
function corpoMinimo(operacao: (typeof OPERACOES_OBSERVACAO)[number]): Record<string, unknown> {
  const corpo: Record<string, unknown> = { operacao };
  for (const chave of CHAVES_POR_OPERACAO[operacao]) corpo[chave] = valorDaChave(operacao, chave);
  return corpo;
}

/**
 * F5-11 P4 (Issue #248) — CONTRATO Edge → RPC do caminho soberano de
 * OBSERVAÇÕES (espelha `metasContratoRpc.test.ts` da F5-10 P5).
 *
 * A fronteira confiável chama as funções SQL por NOME + ARGUMENTOS NOMEADOS via
 * PostgREST: um argumento inexistente faz o PostgREST responder "function not
 * found" e a operação inteira quebra (BLOCKER histórico da F5-06). Este teste lê
 * o código REAL do wiring da Edge (`supabase/functions/observacoes/index.ts`), o
 * SQL REAL das migrations da P2 (`observacao_*`) e da P3 (reescrita do gate) e
 * exige correspondência EXATA de nomes e de ORDEM/TIPO dos parâmetros —
 * `p_payload_hash` NÃO é parâmetro (o hash é derivado server-side — D6).
 *
 * Prova também que:
 * - o gate `f5_11_exigir_autorizacao_observacao` aplica CAPABILITY + SCOPE +
 *   RELAÇÃO + AUTORIA, derivando o ator de `auth.uid()` e resolvendo o alvo
 *   sempre por (id, tenant);
 * - as 8 RPCs continuam `SECURITY INVOKER` com `search_path` fixo e `EXECUTE`
 *   só de `service_role` (nenhum DEFINER/privilegio novo);
 * - `service_role` só aparece como EXECUTOR no wiring, nunca no núcleo testável;
 * - a ordem do núcleo é identidade → gate → execução (decisão antes de execução).
 */

/** Ordem/tipo EXATOS dos parâmetros de cada RPC (migrations P2/P3). */
const CONTRATO_EDGE_RPC: Readonly<Record<string, readonly string[]>> = {
  observacao_criar: ["uuid", "uuid", "uuid", "text", "text", "uuid", "uuid"],
  observacao_editar: ["uuid", "uuid", "text", "text", "boolean", "integer", "uuid", "uuid"],
  observacao_definir_comunicado: ["uuid", "uuid", "boolean", "integer", "uuid", "uuid"],
  observacao_excluir: ["uuid", "uuid", "text", "integer", "uuid", "uuid"],
  observacao_revogar: ["uuid", "uuid", "text", "integer", "uuid", "uuid"],
  observacao_obter: ["uuid", "uuid", "uuid"],
  observacao_listar_por_escopo: ["uuid", "uuid", "text", "uuid", "timestamptz"],
  observacao_historico: ["uuid", "uuid", "uuid"],
};

/** Parâmetros de CAST do PostgREST usados pelo wiring (nome → tipo esperado). */
const TIPO_DO_PARAMETRO: Readonly<Record<string, string>> = {
  p_organization_id: "uuid",
  p_operation_id: "uuid",
  p_actor_user_profile_id: "uuid",
  p_cycle_id: "uuid",
  p_collaborator_id: "uuid",
  p_observation_id: "uuid",
  p_organizational_unit_id: "uuid",
  p_tipo: "text",
  p_texto: "text",
  p_motivo: "text",
  p_escopo: "text",
  p_comunicado: "boolean",
  p_expected_version: "integer",
  p_data: "timestamptz",
};

/** As 8 operações contratadas (o mapa vem do contrato-fonte importado). */
const OPERACOES_CONTRATADAS = [
  "observacao.criar",
  "observacao.editar",
  "observacao.definir_comunicado",
  "observacao.excluir",
  "observacao.revogar",
  "observacao.obter",
  "observacao.listar_por_escopo",
  "observacao.historico",
] as const;

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
  const padrao = /\.rpc\(\s*["']([^"']+)["']\s*,\s*\{/g;

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

const chamadas = extrairChamadasRpc(edgeObservacoesFonte as string);
const chamadasObservacao = chamadas.filter((chamada) => chamada.funcao.startsWith("observacao_"));
/** Chamadas que NÃO são RPC de observação (resolvedores soberanos do wiring). */
const chamadasResolvedores = chamadas.filter(
  (chamada) => !chamada.funcao.startsWith("observacao_")
);

/**
 * Fontes SQL das 8 RPC de operação e do gate da F5-11 (P2 cria, P3 reescreve o
 * gate e a listagem por escopo). É a fonte das provas de ASSINATURA das RPCs de
 * observação.
 */
const SQL_DAS_OBSERVACOES = [migracaoP2Fonte, migracaoP3Fonte].join("\n");

/**
 * Fontes SQL de TODO o schema (migrations). Usadas para provar que a Edge só
 * chama funções que EXISTEM — um nome divergente faz o PostgREST responder
 * "function not found" e quebra a operação (BLOCKER 1 da F5-06).
 *
 * O glob é o SCHEMA INTEIRO (e não só P2/P3) porque o wiring chama também os
 * resolvedores SOBERANOS de outros domínios — `resolver_collaborador_vinculado`
 * (F5-02), `resolver_capabilities_escopos_efetivas` e `resolver_alvos_escopo`
 * (F4-02) —, definidos muito antes da F5-11, exatamente como o molde
 * `metasContratoRpc.test.ts:238-246` faz para a Edge `metas`.
 */
const MIGRACOES: Readonly<Record<string, string>> = import.meta.glob(
  "../../supabase/migrations/*.sql",
  { query: "?raw", import: "default", eager: true }
) as Readonly<Record<string, string>>;
const SQL_DO_SCHEMA = Object.values(MIGRACOES).join("\n");

/**
 * Resolvedores soberanos que a Edge `observacoes` está autorizada a chamar, com
 * a fonte REAL de cada um (lista FECHADA — nenhum resolvedor inventado e nenhuma
 * RPC de outro domínio no wiring).
 */
const RESOLVEDORES_ESPERADOS = [
  "resolver_collaborador_vinculado",
  "resolver_capabilities_escopos_efetivas",
  "resolver_alvos_escopo",
] as const;

/** Declaração de função no SQL, aceitando `create [or replace] function`. */
function declaracaoDaFuncao(nome: string): RegExp {
  return new RegExp(`create (?:or replace )?function public\\.${nome}\\(`);
}

/**
 * Parâmetros (nome + tipo) de cada `create or replace function public.<nome>(`
 * do SQL REAL. O mesmo nome pode ser redefinido pela P3 (o gate e a listagem por
 * escopo): as assinaturas devem ser IDÊNTICAS entre as definições.
 */
function parametrosDaFuncao(sql: string, nome: string): readonly string[] {
  const marcador = `create or replace function public.${nome}(`;
  const assinaturas: string[][] = [];
  let indice = sql.indexOf(marcador);
  while (indice !== -1) {
    const fim = sql.indexOf(")", indice);
    const bloco = sql.slice(indice + marcador.length, fim === -1 ? undefined : fim);
    const parametros: string[] = [];
    for (const linha of bloco.split("\n")) {
      const achado = /^\s*(p_[a-z_]+)\s+([a-z_ ]+?)\s*,?\s*$/.exec(linha);
      if (achado) parametros.push(`${achado[1]}:${achado[2]!.trim()}`);
    }
    assinaturas.push(parametros);
    indice = sql.indexOf(marcador, indice + marcador.length);
  }
  if (assinaturas.length === 0) return [];
  // Todas as definições da mesma função precisam ter a MESMA assinatura.
  const primeira = assinaturas[0]!;
  for (const assinatura of assinaturas) {
    expect(assinatura, `${nome}: assinatura divergente entre definições`).toEqual(primeira);
  }
  return primeira;
}

function nomesDosParametros(assinatura: readonly string[]): readonly string[] {
  return assinatura.map((item) => item.split(":")[0]!);
}

function tiposDosParametros(assinatura: readonly string[]): readonly string[] {
  return assinatura.map((item) => item.split(":")[1]!);
}

/**
 * Corpo da FUNÇÃO pública (do `create or replace function public.<nome>(` até a
 * PRÓXIMA função pública do arquivo). Procurar marcadores no arquivo INTEIRO
 * casa primeiro as cadeias do PREFLIGHT (`foreach v_fn in array array[...]`, que
 * cita as mesmas funções como texto) e falseia a ORDEM dos blocos: a ordem e as
 * constantes do `declare` só valem DENTRO do gate.
 */
function corpoDaFuncaoPublica(sql: string, nome: string): string {
  const inicio = sql.indexOf(`create or replace function public.${nome}(`);
  if (inicio < 0) return "";
  const proxima = sql.indexOf("\ncreate or replace function public.", inicio + 1);
  return proxima < 0 ? sql.slice(inicio) : sql.slice(inicio, proxima);
}

describe("F5-11 P4 — contrato Edge → RPC (nome + argumentos nomeados)", () => {
  it("a extração encontra as OITO RPCs de operação da Edge `observacoes`", () => {
    const nomes = Array.from(new Set(chamadasObservacao.map((chamada) => chamada.funcao))).sort();
    expect(nomes).toEqual(Object.keys(CONTRATO_EDGE_RPC).sort());
    expect(nomes).toHaveLength(8);
  });

  it("a Edge não chama NENHUMA RPC de observação fora do contrato", () => {
    const proibidas = chamadasObservacao.filter(
      (chamada) => !Object.prototype.hasOwnProperty.call(CONTRATO_EDGE_RPC, chamada.funcao)
    );
    expect(proibidas.map((chamada) => `${chamada.funcao}:${chamada.linha}`)).toEqual([]);
    // O mapa operação → RPC é o do CONTRATO-FONTE (importado): nenhuma cópia.
    expect(Object.keys(RPC_POR_OPERACAO).sort()).toEqual([...OPERACOES_CONTRATADAS].sort());
    for (const funcao of Object.values(RPC_POR_OPERACAO)) {
      expect(Object.keys(CONTRATO_EDGE_RPC), funcao).toContain(funcao);
    }
    // As funções INTERNAS da P2/P3 (`f5_11_*`) não são operação de cliente.
    for (const [arquivo, fonte] of [
      ["index.ts", edgeObservacoesFonte as string],
      ["edgeObservacoes.ts", adapterFonte as string],
    ] as const) {
      expect(codigoSemComentarios(fonte), arquivo).not.toMatch(/\.rpc\(\s*["']f5_11_/);
    }
  });

  it("além das RPCs de operação, o wiring só chama RESOLVEDORES soberanos", () => {
    // Nenhuma RPC de OUTRO domínio (`meta_*`, `ciclo_*`, `evaluation_*`,
    // `colaborador_*`) pode ser chamada pela Edge `observacoes`: os fatos de
    // identidade, escopo e relação entram apenas pelos resolvedores soberanos.
    const outras = Array.from(new Set(chamadasResolvedores.map((chamada) => chamada.funcao)));
    for (const funcao of outras) {
      expect(funcao, funcao).toMatch(/^resolver_/);
      expect(funcao, funcao).not.toMatch(/^(meta|ciclo|evaluation|colaborador)_/);
    }
  });

  it("TODA função chamada pela Edge existe no SCHEMA (guard do BLOCKER 1)", () => {
    // A fonte é o glob COMPLETO de `supabase/migrations/*.sql` (molde
    // `metasContratoRpc.test.ts:238-246`): o wiring chama, legitimamente, os
    // resolvedores soberanos de F4-02/F5-02, que vivem FORA das migrations da
    // F5-11 — restringir a fonte a P2/P3 acusaria falso positivo.
    const nomes = Array.from(new Set(chamadas.map((chamada) => chamada.funcao)));
    expect(nomes.length).toBeGreaterThanOrEqual(8);

    const inexistentes = nomes.filter((funcao) => !declaracaoDaFuncao(funcao).test(SQL_DO_SCHEMA));
    expect(inexistentes).toEqual([]);

    // O glob é SUBSTANTIVO: as 8 RPC de operação ESTÃO nele...
    for (const rpc of Object.keys(CONTRATO_EDGE_RPC)) {
      expect(SQL_DO_SCHEMA, rpc).toMatch(declaracaoDaFuncao(rpc));
    }
    // ...e os resolvedores chamados pelo wiring também (lista FECHADA, com a
    // fonte real de cada um presente no schema completo).
    const chamadosResolvedores = Array.from(
      new Set(chamadasResolvedores.map((chamada) => chamada.funcao))
    );
    for (const resolvedor of chamadosResolvedores) {
      expect(RESOLVEDORES_ESPERADOS, resolvedor).toContain(resolvedor);
      expect(SQL_DO_SCHEMA, resolvedor).toContain(`function public.${resolvedor}(`);
    }
    // Os resolvedores soberanos NÃO são migrations da F5-11: a prova de FORMA das
    // RPC de observação continua restrita a P2/P3.
    for (const resolvedor of RESOLVEDORES_ESPERADOS) {
      expect(SQL_DAS_OBSERVACOES, resolvedor).not.toContain(`function public.${resolvedor}(`);
    }
  });

  it("os argumentos de cada RPC batem EXATAMENTE com a assinatura real das migrations", () => {
    const problemas: string[] = [];

    for (const [funcao, esperado] of Object.entries(CONTRATO_EDGE_RPC)) {
      const chamada = chamadasObservacao.find((item) => item.funcao === funcao);
      if (!chamada) {
        problemas.push(`${funcao}: a Edge não chama esta RPC`);
        continue;
      }
      const assinatura = parametrosDaFuncao(SQL_DAS_OBSERVACOES, funcao);
      if (assinatura.length === 0) {
        problemas.push(`${funcao}: definição ausente nas migrations da F5-11`);
        continue;
      }
      const nomes = nomesDosParametros(assinatura);
      const tipos = tiposDosParametros(assinatura);
      if (JSON.stringify(tipos) !== JSON.stringify(esperado)) {
        problemas.push(
          `${funcao}: ordem/tipo reais [${assinatura.join(", ")}] ≠ contrato [${esperado.join(", ")}]`
        );
      }
      const enviado = [...chamada.argumentos].sort();
      const contrato = [...nomes].sort();
      if (JSON.stringify(enviado) !== JSON.stringify(contrato)) {
        problemas.push(
          `linha ${chamada.linha}: ${funcao} envia [${enviado.join(", ")}] ` +
            `mas a assinatura exige [${contrato.join(", ")}]`
        );
      }
      // O tipo de cada argumento nomeado enviado tem de existir no mapa de casts.
      for (const argumento of chamada.argumentos) {
        if (!TIPO_DO_PARAMETRO[argumento]) {
          problemas.push(`${funcao}: parâmetro sem tipo conhecido (${argumento})`);
        }
      }
    }

    expect(problemas).toEqual([]);
  });

  it("toda RPC de operação recebe o ATOR verificado e nunca `p_payload_hash`", () => {
    const proibidos = [
      "p_payload_hash",
      "p_payload",
      "p_actor_id",
      "p_author_id",
      "p_author_user_profile_id",
      "p_actor_collaborator_id",
      "p_actor_membership_id",
      "p_actor_membership",
    ];
    for (const chamada of chamadasObservacao) {
      for (const proibido of proibidos) {
        expect(chamada.argumentos, `${chamada.funcao}:${proibido}`).not.toContain(proibido);
      }
      // O ator é SEMPRE o `auth.uid` verificado — o hash é derivado server-side.
      expect(chamada.argumentos, chamada.funcao).toContain("p_actor_user_profile_id");
    }

    // `p_operation_id` (idempotência, D6) vai para as 5 MUTAÇÕES; as três
    // LEITURAS (`obter`, `listar_por_escopo`, `historico`) não têm esse
    // parâmetro — não há evento de trilha a idempotenciar.
    const porOperacao = Object.keys(CONTRATO_EDGE_RPC).map(
      (nome) => [nome, chamadasObservacao.find((item) => item.funcao === nome)] as const
    );
    for (const [funcao, chamada] of porOperacao) {
      expect(chamada === undefined, funcao).toBe(false);
      const assinatura = parametrosDaFuncao(SQL_DAS_OBSERVACOES, funcao);
      const nomes = nomesDosParametros(assinatura);
      const temOperationId = nomes.includes("p_operation_id");
      const mutacao = [
        "observacao_criar",
        "observacao_editar",
        "observacao_definir_comunicado",
        "observacao_excluir",
        "observacao_revogar",
      ].includes(funcao);
      expect(temOperationId, funcao).toBe(mutacao);
      expect((chamada?.argumentos ?? []).includes("p_operation_id"), funcao).toBe(temOperationId);
      // A LEITURA de trilha e a leitura por escopo nunca recebem versão.
      if (!mutacao && funcao !== "observacao_editar") {
        expect(nomes, funcao).not.toContain("p_expected_version");
      }
    }

    // Nenhum arquivo do caminho soberano menciona o hash do corpo (D6).
    for (const [arquivo, fonte] of [
      ["core.ts", edgeCoreFonte as string],
      ["index.ts", edgeObservacoesFonte as string],
      ["contrato.ts", edgeContratoFonte as string],
      ["edgeObservacoes.ts", adapterFonte as string],
    ] as const) {
      expect(codigoSemComentarios(fonte).includes("p_payload_hash"), arquivo).toBe(false);
    }
  });

  it("o trio da Edge existe e a pasta reexporta o contrato-fonte (fonte única)", () => {
    expect(edgeContratoFonte as string).toContain(
      'export * from "../../../src/infrastructure/supabase/observacoes/contrato.ts";'
    );
    // Nenhuma cópia local da lista de operações/allowlist no lado da Edge.
    expect(edgeContratoFonte as string).not.toContain("DEFINICAO_POR_OPERACAO = {");
    expect(edgeContratoFonte as string).not.toContain("CHAVES_POR_OPERACAO = {");
    expect(edgeContratoFonte as string).not.toContain("RPC_POR_OPERACAO = {");
  });
});

describe("F5-11 P4 — o GATE aplica capability + scope + relação + autoria (leitura do SQL)", () => {
  const GATE = "f5_11_exigir_autorizacao_observacao";

  it("o gate existe, é chamado pelas 8 RPCs e é `SECURITY INVOKER` com search_path fixo", () => {
    // A P2 cria o gate e a P3 o reescreve: as DUAS definições são conferidas.
    const definicoes = migracaoP2Fonte.split(`create or replace function public.${GATE}(`)
      .length - 1;
    expect(definicoes).toBe(1);
    const reescrita = migracaoP3Fonte.split(`create or replace function public.${GATE}(`)
      .length - 1;
    expect(reescrita).toBe(1);
    for (const fonte of [migracaoP2Fonte as string, migracaoP3Fonte as string]) {
      const inicio = fonte.indexOf(`create or replace function public.${GATE}(`);
      const bloco = fonte.slice(inicio, fonte.indexOf("$$", inicio));
      expect(bloco).toContain("security invoker");
      expect(bloco).not.toContain("security definer");
      expect(bloco).toContain("set search_path = public");
    }

    // As 8 RPCs chamam o gate (o `perform` é o ponto único de decisão).
    const invocacoesDoGate = (
      SQL_DAS_OBSERVACOES.match(new RegExp(`${GATE}\\(`, "g")) ?? []
    ).length;
    expect(invocacoesDoGate).toBeGreaterThanOrEqual(8);
    for (const rpc of Object.keys(CONTRATO_EDGE_RPC)) {
      // Cada definição da RPC invoca o gate ANTES de tocar a linha.
      const marca = `create or replace function public.${rpc}(`;
      let indice = SQL_DAS_OBSERVACOES.indexOf(marca);
      const invocacoes: string[] = [];
      while (indice !== -1) {
        const corpo = SQL_DAS_OBSERVACOES.slice(indice);
        const posGate = corpo.indexOf(`${GATE}(`);
        const posUpdate = corpo.search(/\b(update|insert into)\s+public\.evaluation_observations/);
        expect(posGate, `${rpc}: gate ausente`).toBeGreaterThan(-1);
        if (posUpdate !== -1) {
          expect(posGate, `${rpc}: gate DEPOIS da escrita`).toBeLessThan(posUpdate);
        }
        invocacoes.push(rpc);
        indice = SQL_DAS_OBSERVACOES.indexOf(marca, indice + marca.length);
      }
      expect(invocacoes.length, rpc).toBeGreaterThanOrEqual(1);
    }
  });

  it("o mapa operação → capability do gate é FECHADO e cobre as 4 canônicas", () => {
    const trecho = migracaoP3Fonte.slice(
      (migracaoP3Fonte as string).indexOf("v_cap := case v_operacao"),
      (migracaoP3Fonte as string).indexOf("if v_cap is null then")
    );
    expect(trecho).not.toBe("");

    const esperado: readonly (readonly [string, string])[] = [
      ["CRIAR", "observation.create"],
      ["EDITAR", "observation.edit"],
      ["COMUNICAR", "observation.edit"],
      ["DESCOMUNICAR", "observation.edit"],
      ["REVOGAR", "observation.edit"],
      ["EXCLUIR", "observation.delete"],
      ["OBTER", "observation.read"],
      ["HISTORICO", "observation.read"],
      ["LISTAR_ESCOPO", "observation.read"],
    ];
    for (const [operacao, capability] of esperado) {
      expect(trecho, operacao).toContain(`when '${operacao}'`);
      expect(trecho, `${operacao}:${capability}`).toContain(`'${capability}'`);
    }
    // Operação desconhecida ⇒ raise (fail-closed), nunca uma capability default.
    expect(migracaoP3Fonte as string).toContain("operacao de observacao desconhecida");
    expect(migracaoP3Fonte as string).toContain("F5_11_FORBIDDEN");
    // As 4 capabilities do mapa são canônicas no catálogo do cliente.
    for (const capability of [
      "observation.read",
      "observation.create",
      "observation.edit",
      "observation.delete",
    ]) {
      expect(capabilityCanonica(capability), capability).toBe(capability);
    }
    // Nenhuma capability nova/exótica é exigida pelo gate.
    for (const inventada of [
      "observation.write",
      "observation.communicate",
      "observation.revoke",
      "observation.manage",
    ]) {
      expect(trecho, inventada).not.toContain(`'${inventada}'`);
    }
  });

  it("a AUTORIA (D5) é conferida contra o ator de `auth.uid()` — nunca do corpo", () => {
    // A raiz soberana de identidade: o ator efetivo é derivado de `auth.uid()`.
    expect(migracaoP2Fonte as string).toContain("f5_11_ator_efetivo_observacao");
    expect(migracaoP3Fonte as string).toContain("f5_11_ator_efetivo_observacao");
    expect(SQL_DAS_OBSERVACOES).toContain("auth.uid()");

    const trecho = migracaoP3Fonte.slice((migracaoP3Fonte as string).indexOf("(3) AUTORIA"));
    // Somente o autor persistido pode editar/comunicar/descomunicar/revogar/excluir.
    expect(trecho).toContain("v_autor is distinct from v_ator");
    expect(trecho).toContain("somente o autor soberano");
    for (const operacao of ["'EDITAR'", "'COMUNICAR'", "'DESCOMUNICAR'", "'REVOGAR'", "'EXCLUIR'"]) {
      expect(trecho, operacao).toContain(operacao);
    }
    // A autoria NUNCA vem de um parâmetro do corpo: o único parâmetro de ator é
    // o `p_actor_user_profile_id`, validado contra `auth.uid()` (sem override).
    for (const rpc of Object.keys(CONTRATO_EDGE_RPC)) {
      const nomes = nomesDosParametros(parametrosDaFuncao(SQL_DAS_OBSERVACOES, rpc));
      for (const nome of nomes) {
        expect(nome, `${rpc}:${nome}`).not.toMatch(/^p_(author|actor)_(id|collaborator)/);
      }
    }
  });

  it("a RELAÇÃO estrutural é exigida (DIRECT_REPORTS/DESCENDANTS) e SELF não cria sobre si", () => {
    expect(SQL_DAS_OBSERVACOES).toContain("f5_11_relacao_observacao_do_ator");
    const trecho = migracaoP3Fonte.slice((migracaoP3Fonte as string).indexOf("(3) AUTORIA"));
    expect(trecho).toContain("ator sem relacao vigente com o colaborador alvo");
    expect(trecho).toContain("'CRIAR'");
    expect(trecho).toContain("SELF nao cria observacao sobre si proprio");
    // O escopo de LEITURA por escopo é uma allowlist FECHADA.
    expect(migracaoP3Fonte as string).toContain(
      "v_escopo not in ('SELF', 'DIRECT_REPORTS', 'DESCENDANTS')"
    );
    expect(migracaoP3Fonte as string).toContain("fora da allowlist fechada");
  });

  it("o SCOPE soberano é CUMULATIVO (D15/P3) e vem do resolver escopado real", () => {
    expect(migracaoP3Fonte as string).toContain("f5_11_ator_tem_escopo_observacao");
    expect(migracaoP3Fonte as string).toContain("resolver_capabilities_escopos_efetivas");
    // Assignments sem scope ⇒ nada resolvido ⇒ DENY (fail-closed).
    expect(migracaoP3Fonte as string).toContain("assignment sem scope => falso");
    const trecho = migracaoP3Fonte.slice(
      (migracaoP3Fonte as string).indexOf("(2c) SCOPE SOBERANO"),
      (migracaoP3Fonte as string).indexOf("(3) AUTORIA")
    );
    expect(trecho).toContain("v_escopos_gestao");
    // A constante `v_escopos_gestao` é declarada no `declare` do gate, ANTES do
    // bloco (2c): a allowlist fechada de escopos é provada no corpo do gate.
    expect(corpoDaFuncaoPublica(migracaoP3Fonte as string, GATE)).toContain(
      "'DIRECT_REPORTS', 'DESCENDANTS'"
    );
    // A leitura SELF-comunicada é a ÚNICA exceção normativa (D7/§8 linha 2).
    expect(trecho).toContain("v_self_ok");
    expect(trecho).toContain("comunicado");
  });

  it("a ORDEM do gate é identidade → capability → alvo (id, tenant) → scope → autoria/relação", () => {
    const codigo = corpoDaFuncaoPublica(codigoSemComentarios(migracaoP3Fonte as string), GATE);
    const posAtor = codigo.indexOf("f5_11_ator_efetivo_observacao(");
    const posCapability = codigo.indexOf("f5_11_ator_valido_observacao(");
    const posAlvo = codigo.indexOf("public.evaluation_observations o");
    const posScope = codigo.indexOf("f5_11_ator_tem_escopo_observacao(");
    const posRelacao = codigo.indexOf("f5_11_relacao_observacao_do_ator(");
    const posAutoria = codigo.indexOf("v_autor is distinct from v_ator");

    expect(posAtor).toBeGreaterThan(-1);
    expect(posCapability).toBeGreaterThan(posAtor);
    expect(posAlvo).toBeGreaterThan(posCapability);
    expect(posScope).toBeGreaterThan(posAlvo);
    expect(posAutoria).toBeGreaterThan(posScope);
    expect(posRelacao).toBeGreaterThan(posAutoria);
  });

  it("o gate resolve o alvo SEMPRE por (id, tenant) e nega sem oracle de existência", () => {
    const trecho = migracaoP3Fonte as string;
    expect(trecho).toContain("o.id = p_observation_id");
    expect(trecho).toContain("o.organization_id = p_organization_id");
    expect(trecho).toContain("c.id = v_alvo and c.organization_id = p_organization_id");
    // Mesma mensagem para inexistente e cross-tenant (NOT_FOUND indistinguível).
    expect(trecho).toContain("observacao inexistente ou de outro tenant");
    expect(trecho).toContain("colaborador inexistente ou de outro tenant");
    // O tenant do corpo é INTENÇÃO revalidada, nunca autoridade.
    expect(trecho).toContain("organizacao obrigatoria na autorizacao funcional de observacao");
  });

  it("o estado do colaborador (D11) é avaliado por fonte soberana, com precedência declarada", () => {
    expect(migracaoP3Fonte as string).toContain("f5_11_status_vigente_do_colaborador");
    // A tabela do lifecycle é lida pela função soberana da P2, que o gate da P3
    // consome (o nome da tabela NÃO aparece na migration da P3).
    expect(SQL_DAS_OBSERVACOES).toContain("collaborator_status_periods");
    // CRIAR/COMUNICAR exigem status vigente ≠ inactive (fail-closed se ausente).
    expect(migracaoP3Fonte as string).toContain("v_operacao in ('CRIAR', 'COMUNICAR')");
    expect(migracaoP3Fonte as string).toContain("status vigente do colaborador alvo nao resolvido");
    expect(migracaoP3Fonte as string).toContain("proibida para colaborador inactive");
  });
});

describe("F5-11 P4 — ACL e `SECURITY INVOKER` das 8 RPCs soberanas", () => {
  it("as 8 RPCs são `security invoker` com `search_path` fixo (nenhum DEFINER novo)", () => {
    const faltando: string[] = [];
    for (const nome of Object.keys(CONTRATO_EDGE_RPC)) {
      const marca = `create or replace function public.${nome}(`;
      let indice = SQL_DAS_OBSERVACOES.indexOf(marca);
      let definicoes = 0;
      while (indice !== -1) {
        definicoes += 1;
        const separador = SQL_DAS_OBSERVACOES.indexOf("$$", indice);
        const bloco = SQL_DAS_OBSERVACOES.slice(indice, separador);
        if (bloco.includes("security definer")) {
          faltando.push(`${nome}[${definicoes}]: SECURITY DEFINER inesperado`);
        }
        if (!bloco.includes("security invoker")) {
          faltando.push(`${nome}[${definicoes}]: sem SECURITY INVOKER`);
        }
        if (!bloco.includes("set search_path = public")) {
          faltando.push(`${nome}[${definicoes}]: search_path fixo ausente`);
        }
        indice = SQL_DAS_OBSERVACOES.indexOf(marca, indice + marca.length);
      }
      if (definicoes === 0) faltando.push(`${nome}: definição ausente`);
    }
    expect(faltando).toEqual([]);
  });

  it("o `EXECUTE` das 8 RPCs é SÓ de `service_role` (nenhum privilegio de cliente)", () => {
    // Toda assinatura REAL aparece fechada — prova de que o revoke/grant foi
    // reafirmado sobre a função vigente, não sobre sobrecarga antiga.
    for (const assinatura of [
      "uuid, uuid, uuid, text, text, uuid, uuid", // observacao_criar
      "uuid, uuid, text, text, boolean, integer, uuid, uuid", // observacao_editar
      "uuid, uuid, boolean, integer, uuid, uuid", // observacao_definir_comunicado
      "uuid, uuid, text, integer, uuid, uuid", // observacao_excluir
      "uuid, uuid, text, integer, uuid, uuid", // observacao_revogar
      "uuid, uuid, uuid", // observacao_obter
      "uuid, uuid, text, uuid, timestamptz", // observacao_listar_por_escopo
      "uuid, uuid, uuid", // observacao_historico
    ]) {
      expect(
        (migracaoP2Fonte as string).includes(`(${assinatura})`),
        `assinatura ausente: ${assinatura}`
      ).toBe(true);
    }

    const revogacoes =
      (migracaoP2Fonte as string).match(
        /revoke all on function public\.observacao_[a-z_]+\([^)]*\)[\s\S]{0,40}?from public, anon, authenticated;/g
      ) ?? [];
    expect(revogacoes).toHaveLength(8);

    const concedidas = Array.from(
      (migracaoP2Fonte as string).matchAll(
        /grant execute on function public\.(observacao_[a-z_]+)\([^)]*\)[\s\S]{0,20}?to ([a-z_]+);/g
      )
    ).map((achado) => `${achado[1]}->${achado[2]}`);
    expect(concedidas).toHaveLength(8);
    for (const concessao of concedidas) {
      expect(concessao, concessao).toMatch(/->service_role$/);
    }
    // Nenhuma RPC de observação é executável por cliente (authenticated/anon/public).
    expect(migracaoP2Fonte as string).not.toMatch(
      /grant execute[\s\S]{0,120}?to (authenticated|anon|public);/
    );
    for (const rpc of Object.keys(CONTRATO_EDGE_RPC)) {
      expect(migracaoP2Fonte as string, rpc).toContain(`public.${rpc}(`);
    }
  });

  it("os helpers internos do gate também são `service_role`-only", () => {
    for (const helper of [
      "f5_11_ator_efetivo_observacao",
      "f5_11_ator_valido_observacao",
      "f5_11_vinculo_observacao_do_ator",
      "f5_11_relacao_observacao_do_ator",
      "f5_11_status_vigente_do_colaborador",
      "f5_11_exigir_autorizacao_observacao",
    ]) {
      const padrao = new RegExp(
        `revoke all on function public\\.${helper}\\([\\s\\S]*?\\)\\s*\\n\\s*from public, anon, authenticated;`
      );
      expect(SQL_DAS_OBSERVACOES, helper).toMatch(padrao);
      const padraoGrant = new RegExp(
        `grant execute on function public\\.${helper}\\([\\s\\S]*?\\)\\s*\\n\\s*to service_role;`
      );
      expect(SQL_DAS_OBSERVACOES, helper).toMatch(padraoGrant);
    }
    // O helper de scope da P3 segue a mesma ACL.
    expect(migracaoP3Fonte as string).toMatch(
      /grant execute on function public\.f5_11_ator_tem_escopo_observacao\([\s\S]*?\)\s*\n\s*to service_role;/
    );
  });

  it("nenhuma capability nova aparece nas migrations da F5-11", () => {
    for (const [nome, fonte] of [
      ["P2", migracaoP2Fonte as string],
      ["P3", migracaoP3Fonte as string],
    ] as const) {
      expect(fonte, nome).not.toContain("insert into public.capabilities");
      expect(fonte, nome).not.toContain("update public.capabilities");
      expect(fonte, nome).not.toContain("observation.communicate");
      expect(fonte, nome).not.toContain("observation.revoke");
    }
    // O catálogo permanece com as 4 canônicas de observação.
    for (const capability of [
      "observation.read",
      "observation.create",
      "observation.edit",
      "observation.delete",
    ]) {
      expect(SQL_DAS_OBSERVACOES, capability).toContain(`'${capability}'`);
    }
  });
});

describe("F5-11 P4 — `service_role` só no wiring e a RPC só DEPOIS do gate", () => {
  it("o núcleo testável NÃO menciona a credencial privilegiada", () => {
    const codigoCore = codigoSemComentarios(edgeCoreFonte as string);
    expect(codigoCore).not.toContain("service_role");
    expect(codigoCore).not.toContain("SERVICE_ROLE");
    expect(codigoCore).not.toContain("serviceRole");
    expect(codigoCore).not.toContain("createClient");
    // O wiring é o ÚNICO que cria o cliente privilegiado.
    expect(codigoSemComentarios(edgeObservacoesFonte as string)).toContain(
      "SUPABASE_SERVICE_ROLE_KEY"
    );
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
    expect(codigoSemComentarios(edgeObservacoesFonte as string)).toContain(
      "avaliarOperacaoAutorizacao"
    );
  });
});

describe("F5-11 P4 — a Edge não replica o domínio de observação", () => {
  it("nenhum estado de domínio é codificado na fronteira", () => {
    const fontes = [
      codigoSemComentarios(edgeObservacoesFonte as string),
      codigoSemComentarios(edgeCoreFonte as string),
    ];
    for (const fonte of fontes) {
      for (const estado of [
        "POSITIVA",
        "NEUTRA",
        "NEGATIVA",
        "DIRECT_REPORTS",
        "DESCENDANTS",
        "CRIADA",
        "EDITADA",
        "EXCLUIDA",
        "REVOGADA",
      ]) {
        expect(fonte, estado).not.toContain(estado);
      }
      // O estado da observação NUNCA é comparado na fronteira: quem decide é o
      // probe do domínio (Policy Engine) + a precondição da RPC.
      expect(fonte).not.toMatch(/comunicado\s*===\s*(true|false)/);
      expect(fonte).not.toMatch(/excluida\s*===\s*(true|false)/);
    }
  });

  it("a fronteira não compara versão, não materializa e não calcula hash", () => {
    for (const proibido of [
      "expectedVersion ===",
      "expectedVersion >",
      "expectedVersion <",
      "sha256",
      "materializar",
      "payloadHash",
    ]) {
      expect(codigoSemComentarios(edgeObservacoesFonte as string), proibido).not.toContain(proibido);
      expect(codigoSemComentarios(edgeCoreFonte as string), proibido).not.toContain(proibido);
    }
  });

  it("a tradução de erro usa os prefixos `F5_11_*` (e só eles)", () => {
    const codigoCore = codigoSemComentarios(edgeCoreFonte as string);
    expect(codigoCore).toContain("F5_11_FORBIDDEN");
    expect(codigoCore).toContain("F5_11_NOT_FOUND");
    expect(codigoCore).toContain("F5_11_CONFLICT");
    expect(codigoCore).toContain("F5_11_INVALID_INPUT");
    // Nenhum resquício das fronteiras de metas/ciclos no caminho de observações.
    expect(codigoCore).not.toContain("F5_10_");
    expect(codigoCore).not.toContain("F5_09_");
    // O caminho de cliente tampouco conhece os prefixos de outros domínios.
    expect(codigoSemComentarios(adapterFonte as string)).not.toMatch(/F5_(09|10)_/);
  });
});

describe("F5-11 P4 — adapter de cliente espelha o contrato (fail-closed)", () => {
  it("o adapter oferece exatamente as oito operações contratadas", () => {
    for (const operacao of OPERACOES_CONTRATADAS) {
      const ocorrencias = (adapterFonte as string).split(`"${operacao}"`).length - 1;
      expect(ocorrencias, operacao).toBe(1);
    }
    expect(adapterFonte as string).toContain('FUNCAO_OBSERVACOES = "observacoes"');
  });

  it("nenhuma autoridade ou fallback do lado do cliente (no CÓDIGO)", () => {
    const codigoAdapter = codigoSemComentarios(adapterFonte as string);
    for (const proibido of [
      "service_role",
      "SERVICE_ROLE",
      "localStorage",
      "sessionStorage",
      ".rpc(",
      "observacaoStorage",
      "payload_hash",
    ]) {
      expect(codigoAdapter, proibido).not.toContain(proibido);
    }
    // A superfície é a Edge, por `functions.invoke`, com fail-closed.
    expect(codigoAdapter).toContain("functions.invoke");
    expect(codigoAdapter).toContain("INTERNAL");
  });

  it("o contrato-fonte documenta e recusa autoria/tenant/estado/data (allowlist é forma)", () => {
    const fonte = contratoFonteFonte as string;
    // O contrato-fonte DECLARA que a allowlist não aceita os campos de
    // identidade/autoridade/estado (a prova comportamental está no gate da RPC
    // e no teste do contrato do cliente).
    for (const campo of [
      "status",
      "comunicado",
      "excluida",
      "version",
      "payload_hash",
      "actor_user_profile_id",
      "membership_id",
      "capability",
      "role",
      "domainState",
    ]) {
      expect(fonte, campo).toContain(campo);
    }
    // Nenhuma chave de identidade/autoridade/estado/data entra na allowlist de
    // NENHUMA operação (a lista é a fonte da recusa por campo desconhecido).
    for (const operacao of OPERACOES_OBSERVACAO) {
      const chaves = CHAVES_POR_OPERACAO[operacao];
      expect(Array.isArray(chaves), operacao).toBe(true);
      for (const proibida of [
        "status",
        "comunicado_em",
        "excluida",
        "excluida_em",
        "version",
        "payload_hash",
        "actor_id",
        "actorId",
        "actor_user_profile_id",
        "author_user_profile_id",
        "author_collaborator_id",
        "membership_id",
        "capability",
        "scope",
        "role",
        "domainState",
        // D21: o instante da decisão é SOBERANO (server-side) — nenhuma operação
        // aceita data declarada pelo chamador, inclusive a listagem por escopo.
        "data",
        "data_referencia",
        "instante",
        "p_data",
      ]) {
        expect(chaves, `${operacao}:${proibida}`).not.toContain(proibida);
      }
      expect(chaves, operacao).toContain("organization_id");
      expect(chaves, operacao).toContain("operacao");
      expect(chaves, operacao).toContain("operation_id");
      expect(DEFINICAO_POR_OPERACAO[operacao]).toBeDefined();
      expect(RPC_POR_OPERACAO[operacao]).toBeDefined();
    }
    // A listagem por escopo resolve a data server-side (`p_data` existe no SQL
    // real da RPC) e o contrato NÃO a expõe como intenção transportável.
    expect(SQL_DAS_OBSERVACOES).toContain("p_data timestamptz");
    expect(CHAVES_POR_OPERACAO["observacao.listar_por_escopo"]).not.toContain("data");
  });

  it("a listagem por escopo é ADMINISTRATIVA e o `p_data` é resolvido SERVER-SIDE (D21)", () => {
    // §8 linha 1 (norma, molde `goal.listar_por_escopo`): a listagem não tem alvo
    // único autorizável ⇒ plano ADMINISTRATIVO com a capability efetiva do ator.
    expect(DEFINICAO_POR_OPERACAO["observacao.listar_por_escopo"].gate).toBe("administrativo");
    expect(DEFINICAO_POR_OPERACAO["observacao.listar_por_escopo"].funcional).toBe(false);
    expect(capacidadeAdministrativaDaOperacao("observacao.listar_por_escopo")).toBe(
      "observation.read"
    );
    expect(ehOperacaoFuncional("observacao.listar_por_escopo")).toBe(false);
    for (const operacao of OPERACOES_OBSERVACAO) {
      if (operacao === "observacao.listar_por_escopo") continue;
      expect(DEFINICAO_POR_OPERACAO[operacao].gate, operacao).toBe("funcional");
      expect(ehOperacaoFuncional(operacao), operacao).toBe(true);
      expect(capacidadeAdministrativaDaOperacao(operacao), operacao).toBeNull();
    }

    // A RPC REAL recebe `p_data` (instante soberano) e o VALIDADOR do contrato
    // recusa `data` declarada pelo chamador em TODAS as operações — o corpo base
    // é o MÍNIMO VÁLIDO da própria operação, de modo que a recusa é atribuível
    // só à chave proibida.
    expect(SQL_DAS_OBSERVACOES).toContain("p_data timestamptz");
    const rejeitadas: string[] = [];
    for (const operacao of OPERACOES_OBSERVACAO) {
      const base = corpoMinimo(operacao);
      if (!validarEntradaObservacao(base).ok) {
        rejeitadas.push(`${operacao}: corpo base inválido`);
        continue;
      }
      const validacao = validarEntradaObservacao({
        ...base,
        data: "2026-04-01T00:00:00.000Z",
      });
      if (validacao.ok) rejeitadas.push(operacao);
      else expect(validacao.code, operacao).toBe("INVALID_INPUT");
    }
    expect(rejeitadas).toEqual([]);
  });
});
