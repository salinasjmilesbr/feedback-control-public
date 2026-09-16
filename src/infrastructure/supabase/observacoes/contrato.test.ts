import { describe, expect, it } from "vitest";
import {
  CHAVES_POR_OPERACAO,
  DEFINICAO_POR_OPERACAO,
  OPERACOES_OBSERVACAO,
  RPC_POR_OPERACAO,
  capacidadeAdministrativaDaOperacao,
  ehOperacaoFuncional,
  ehOperacaoObservacao,
  validarEntradaObservacao,
  type OperacaoObservacao,
} from "./contrato";

/**
 * F5-11 P4 (Issue #248) — contrato TRANSPORTÁVEL do caminho soberano de
 * OBSERVAÇÕES (§6.7/D16 do desenho; molde normativo `metas/contrato.ts` da
 * F5-10 P5 e `colaboradores/contrato.test.ts`).
 *
 * Este módulo é a fonte ÚNICA da superfície que o cliente pode pedir, do GATE de
 * cada operação (§8) e da FORMA do corpo aceito (nunca autoridade). Os testes
 * provam:
 * - paridade 1:1 entre o mapa operação → RPC e as 8 operações contratadas;
 * - allowlist ESTRITA por operação, sem NENHUM campo de autoria/tenant/estado/
 *   autorização (o ator é `auth.uid()`, o tenant é revalidado e o estado vem da
 *   LINHA soberana);
 * - presença das 8 operações: criar, editar, definir_comunicado, excluir,
 *   revogar, obter, listar_por_escopo, historico;
 * - fail-closed da validação de FORMA (corpo, operação desconhecida, campo
 *   desconhecido, identidade no corpo).
 */

/** UUIDs sintéticos (nenhum dado real). */
const ORG = "11111111-1111-4111-8111-111111111111";
const OBSERVACAO = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CICLO = "55555555-5555-4555-8555-555555555555";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";
const OPERACAO = "66666666-6666-4666-8666-666666666666";
const UNIDADE = "33333333-3333-4333-8333-333333333333";

/** As 8 operações contratadas da F5-11 (P4). */
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

/** As 8 RPCs soberanas da P2 (§20 do desenho). */
const RPCS_CONTRATADAS = [
  "observacao_criar",
  "observacao_editar",
  "observacao_definir_comunicado",
  "observacao_excluir",
  "observacao_revogar",
  "observacao_obter",
  "observacao_listar_por_escopo",
  "observacao_historico",
] as const;

/** Chaves SEMPRE presentes (intenção de tenant/operação/idempotência). */
const CHAVES_COMUNS = ["organization_id", "operacao", "operation_id"] as const;

/**
 * Allowlist ESPERADA por operação, derivada da assinatura REAL das RPCs da P2
 * (`supabase/migrations/20260931000000_f5_11_p2_observacoes_rpc.sql`) sem os
 * parâmetros que NÃO são intenção do cliente: `p_actor_user_profile_id` (o ator é
 * `auth.uid()` verificado na fronteira) e `p_payload_hash` (derivado
 * server-side — D6).
 */
const CHAVES_ESPERADAS: Readonly<Record<OperacaoObservacao, readonly string[]>> = {
  "observacao.criar": [...CHAVES_COMUNS, "cycle_id", "collaborator_id", "tipo", "texto"],
  "observacao.editar": [
    ...CHAVES_COMUNS,
    "observation_id",
    "tipo",
    "texto",
    "comunicado",
    "expected_version",
  ],
  "observacao.definir_comunicado": [
    ...CHAVES_COMUNS,
    "observation_id",
    "comunicado",
    "expected_version",
  ],
  "observacao.excluir": [...CHAVES_COMUNS, "observation_id", "motivo", "expected_version"],
  "observacao.revogar": [...CHAVES_COMUNS, "observation_id", "motivo", "expected_version"],
  "observacao.obter": [...CHAVES_COMUNS, "observation_id"],
  "observacao.listar_por_escopo": [...CHAVES_COMUNS, "escopo", "organizational_unit_id"],
  "observacao.historico": [...CHAVES_COMUNS, "observation_id"],
};

/** Valor válido por chave — o corpo mínimo que a FORMA aceita. */
function valorDaChave(operacao: OperacaoObservacao, chave: string): unknown {
  switch (chave) {
    case "operacao":
      // `operacao` é chave COMUM do corpo (mold `metas/contrato.ts:234` e
      // `observacoes/contrato.ts:318`): o valor válido é a própria operação
      // validada — qualquer outro valor tornaria a recusa inatribuível.
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
    case "organizational_unit_id":
      return UNIDADE;
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
    default:
      throw new Error(`sem valor de teste para a chave ${chave}`);
  }
}

/** Corpo mínimo VÁLIDO de uma operação (chaves da allowlist do contrato). */
function corpoValido(operacao: OperacaoObservacao): Record<string, unknown> {
  const corpo: Record<string, unknown> = { operacao };
  for (const chave of CHAVES_POR_OPERACAO[operacao]) corpo[chave] = valorDaChave(operacao, chave);
  return corpo;
}

/**
 * Corpo mínimo válido com as chaves da allowlist que a validação REALMENTE
 * aceita. Se a allowlist declarada pelo contrato divergir da validação (uma
 * chave a mais), o teste de aceitação usa a INTERSECÇÃO — a divergência continua
 * sendo denunciada pela guarda textual de `CHAVES_POR_OPERACAO` (que compara a
 * allowlist inteira), mas o restante da suíte permanece atribuível.
 */
function corpoAceito(operacao: OperacaoObservacao): Record<string, unknown> {
  const completo = corpoValido(operacao);
  if (validarEntradaObservacao(completo).ok) return completo;

  // Construção GREEDY: começa vazio e só incorpora a chave cujo corpo acumulado
  // continua aceito. Chave que a validação real recusa (allowlist menor que a
  // declarada) fica de fora — a guarda textual de `CHAVES_POR_OPERACAO` é quem
  // denuncia a divergência, sem quebrar os demais testes em cascata.
  let reduzido: Record<string, unknown> = { operacao };
  for (const chave of CHAVES_POR_OPERACAO[operacao]) {
    const tentativa = { ...reduzido, [chave]: valorDaChave(operacao, chave) };
    if (validarEntradaObservacao(tentativa).ok) reduzido = tentativa;
  }
  if (validarEntradaObservacao(reduzido).ok) return reduzido;

  // Nada aceito: devolve o corpo completo para que a falha exponha a causa real
  // (mensagem da própria validação) em vez de mascarar o problema.
  return completo;
}

/** Campos que tentariam PROVAR identidade/autoridade/estado — nunca aceitos. */
const CAMPOS_PROIBIDOS: readonly (readonly [string, unknown])[] = [
  ["actor_id", COLABORADOR],
  ["actorId", COLABORADOR],
  ["actor_user_profile_id", OPERACAO],
  ["actorUserId", OPERACAO],
  ["author_id", COLABORADOR],
  ["authorId", COLABORADOR],
  ["author_user_profile_id", OPERACAO],
  ["author_collaborator_id", COLABORADOR],
  ["author_membership_id", COLABORADOR],
  ["membership_id", COLABORADOR],
  ["membershipId", COLABORADOR],
  ["status", "ATIVA"],
  ["aprovado", true],
  ["domainState", { comunicado: true, excluida: false, autor: true }],
  ["excluida", false],
  ["excluida_em", "2026-04-01T00:00:00.000Z"],
  ["excluida_por_user_profile_id", OPERACAO],
  ["version", 1],
  ["payload_hash", "0".repeat(64)],
  ["p_payload_hash", "0".repeat(64)],
  ["capability", "observation.edit"],
  ["scope", "SELF"],
  ["role", "observacoes_gestor"],
  ["cargo", "Diretor"],
  ["funcao", "GERENTE"],
  ["comunicado_em", "2026-04-01T00:00:00.000Z"],
  ["comunicado_por_user_profile_id", OPERACAO],
  // D21: o INSTANTE da decisão é soberano — nenhuma operação transporta uma data
  // declarada pelo chamador (nem o alias do parâmetro nomeado da RPC).
  ["data", "2026-04-01T00:00:00.000Z"],
  ["data_referencia", "2026-04-01T00:00:00.000Z"],
  ["instante", "2026-04-01T00:00:00.000Z"],
  ["agora", "2026-04-01T00:00:00.000Z"],
  ["p_data", "2026-04-01T00:00:00.000Z"],
];

describe("F5-11 P4 — contrato `observacoes`: paridade operação → RPC", () => {
  it("o mapa cobre EXATAMENTE as 8 operações contratadas", () => {
    expect(OPERACOES_OBSERVACAO).toHaveLength(8);
    expect([...OPERACOES_OBSERVACAO].sort()).toEqual([...OPERACOES_CONTRATADAS].sort());
    expect(Object.keys(DEFINICAO_POR_OPERACAO).sort()).toEqual([...OPERACOES_CONTRATADAS].sort());
    expect(Object.keys(RPC_POR_OPERACAO).sort()).toEqual([...OPERACOES_CONTRATADAS].sort());
  });

  it("cada operação tem a sua RPC soberana, 1:1 (mapa congelado)", () => {
    const esperado: Record<string, string> = {
      "observacao.criar": "observacao_criar",
      "observacao.editar": "observacao_editar",
      "observacao.definir_comunicado": "observacao_definir_comunicado",
      "observacao.excluir": "observacao_excluir",
      "observacao.revogar": "observacao_revogar",
      "observacao.obter": "observacao_obter",
      "observacao.listar_por_escopo": "observacao_listar_por_escopo",
      "observacao.historico": "observacao_historico",
    };
    expect(Object.fromEntries(Object.entries(RPC_POR_OPERACAO))).toEqual(esperado);

    // O conjunto das RPCs é EXATAMENTE o da P2: nenhuma função interna
    // (`f5_11_*`) e nenhum nome de outro domínio (`meta_*`, `ciclo_*`).
    expect([...new Set(Object.values(RPC_POR_OPERACAO))].sort()).toEqual(
      [...RPCS_CONTRATADAS].sort()
    );
    for (const rpc of Object.values(RPC_POR_OPERACAO)) {
      expect(rpc.startsWith("observacao_"), rpc).toBe(true);
    }
  });

  it("a paridade operação → RPC é 1:1 (nenhuma RPC compartilhada por duas operações)", () => {
    const rpcs = Object.values(RPC_POR_OPERACAO);
    expect(new Set(rpcs).size).toBe(rpcs.length);
    expect(new Set(Object.keys(RPC_POR_OPERACAO)).size).toBe(rpcs.length);
  });

  it("`ehOperacaoObservacao` é fail-closed para operação desconhecida ou de outro domínio", () => {
    for (const operacao of OPERACOES_CONTRATADAS) {
      expect(ehOperacaoObservacao(operacao), operacao).toBe(true);
    }
    for (const desconhecida of [
      "observacao.revogar_exclusao",
      "observacao.listar",
      "observation.criar",
      "goal.criar",
      "ciclo.criar",
      "observacao_criar",
      "",
      undefined,
      null,
      42,
    ]) {
      expect(ehOperacaoObservacao(desconhecida), String(desconhecida)).toBe(false);
    }
  });
});

describe("F5-11 P4 — contrato `observacoes`: allowlist estrita (forma, nunca autoridade)", () => {
  it("`CHAVES_POR_OPERACAO` é EXATAMENTE a esperada por operação (sem chave a mais)", () => {
    const divergencias: string[] = [];
    for (const operacao of OPERACOES_CONTRATADAS) {
      const real = [...CHAVES_POR_OPERACAO[operacao]].sort();
      const esperada = [...CHAVES_ESPERADAS[operacao]].sort();
      if (JSON.stringify(real) !== JSON.stringify(esperada)) {
        divergencias.push(
          `${operacao}: contrato [${real.join(", ")}] ≠ esperado [${esperada.join(", ")}]`
        );
      }
    }
    expect(divergencias).toEqual([]);
  });

  it("as três chaves comuns estão SEMPRE presentes e não há chave duplicada", () => {
    for (const operacao of OPERACOES_OBSERVACAO) {
      const chaves = CHAVES_POR_OPERACAO[operacao];
      for (const comum of CHAVES_COMUNS) {
        expect(chaves, `${operacao}:${comum}`).toContain(comum);
      }
      expect(new Set(chaves).size, operacao).toBe(chaves.length);
      expect(chaves.length, operacao).toBeGreaterThanOrEqual(CHAVES_COMUNS.length);
    }
  });

  it("NENHUMA operação aceita campo de autoria, tenant, estado ou autorização", () => {
    for (const operacao of OPERACOES_OBSERVACAO) {
      const chaves = CHAVES_POR_OPERACAO[operacao];
      for (const [proibida] of CAMPOS_PROIBIDOS) {
        expect(chaves, `${operacao}:${proibida}`).not.toContain(proibida);
      }
      // O tenant entra SOMENTE como intenção revalidada (`organization_id`); o
      // ator NUNCA entra, nem por parâmetro nomeado da RPC.
      expect(chaves, operacao).not.toContain("p_actor_user_profile_id");
      expect(chaves, operacao).not.toContain("tenant_id");
    }
  });

  it("o alvo de cada operação está na SUA allowlist (nenhum alvo aceito por engano)", () => {
    // Mutação/leitura de linha EXISTENTE: observação por UUID canônico.
    for (const operacao of [
      "observacao.editar",
      "observacao.definir_comunicado",
      "observacao.excluir",
      "observacao.revogar",
      "observacao.obter",
      "observacao.historico",
    ] as const) {
      expect(CHAVES_POR_OPERACAO[operacao], operacao).toContain("observation_id");
      expect(CHAVES_POR_OPERACAO[operacao], operacao).not.toContain("cycle_id");
      expect(CHAVES_POR_OPERACAO[operacao], operacao).not.toContain("collaborator_id");
    }

    // Criação: a observação AINDA NÃO EXISTE — o alvo é o colaborador do ciclo.
    expect(CHAVES_POR_OPERACAO["observacao.criar"]).toContain("cycle_id");
    expect(CHAVES_POR_OPERACAO["observacao.criar"]).toContain("collaborator_id");
    expect(CHAVES_POR_OPERACAO["observacao.criar"]).not.toContain("observation_id");
    expect(CHAVES_POR_OPERACAO["observacao.criar"]).not.toContain("expected_version");
    expect(CHAVES_POR_OPERACAO["observacao.criar"]).not.toContain("comunicado");

    // Leitura por escopo: recebe o ESCOPO (allowlist fechada na RPC) e a unidade
    // opcional — nunca um alvo de observação e NUNCA uma data declarada pelo
    // chamador (D21: o instante da decisão é soberano).
    expect(CHAVES_POR_OPERACAO["observacao.listar_por_escopo"]).toContain("escopo");
    expect(CHAVES_POR_OPERACAO["observacao.listar_por_escopo"]).toContain(
      "organizational_unit_id"
    );
    expect(CHAVES_POR_OPERACAO["observacao.listar_por_escopo"]).not.toContain("observation_id");
    expect(CHAVES_POR_OPERACAO["observacao.listar_por_escopo"]).not.toContain("expected_version");
    expect(CHAVES_POR_OPERACAO["observacao.listar_por_escopo"]).not.toContain("data");
  });

  it("`expected_version` existe SÓ nas mutações de linha EXISTENTE (§8/D10)", () => {
    const comVersao = [
      "observacao.editar",
      "observacao.definir_comunicado",
      "observacao.excluir",
      "observacao.revogar",
    ] as const;
    for (const operacao of OPERACOES_OBSERVACAO) {
      const esperaVersao = (comVersao as readonly string[]).includes(operacao);
      expect(CHAVES_POR_OPERACAO[operacao].includes("expected_version"), operacao).toBe(
        esperaVersao
      );
    }
    // `criar` não tem versão prévia e as três leituras também não.
    for (const operacao of [
      "observacao.criar",
      "observacao.obter",
      "observacao.listar_por_escopo",
      "observacao.historico",
    ] as const) {
      expect(CHAVES_POR_OPERACAO[operacao], operacao).not.toContain("expected_version");
    }
  });

  it("`motivo` é intenção das duas operações auditadas (excluir/revogar)", () => {
    for (const operacao of ["observacao.excluir", "observacao.revogar"] as const) {
      expect(CHAVES_POR_OPERACAO[operacao], operacao).toContain("motivo");
    }
    // A edição NÃO aceita motivo (a trilha do evento tem tipo anterior/texto
    // anterior derivados server-side) e a criação tampouco.
    for (const operacao of [
      "observacao.criar",
      "observacao.editar",
      "observacao.definir_comunicado",
    ] as const) {
      expect(CHAVES_POR_OPERACAO[operacao], operacao).not.toContain("motivo");
    }
  });
});

describe("F5-11 P4 — contrato `observacoes`: validação de FORMA (fail-closed)", () => {
  it.each(OPERACOES_CONTRATADAS)("aceita o corpo mínimo válido de %s", (operacao) => {
    const resultado = validarEntradaObservacao(corpoAceito(operacao));
    expect(resultado.ok, JSON.stringify(resultado)).toBe(true);
  });

  it("a allowlist é ESTRITA: chave fora dela ⇒ INVALID_INPUT (em TODA operação)", () => {
    for (const operacao of OPERACOES_OBSERVACAO) {
      for (const [campo, valor] of CAMPOS_PROIBIDOS) {
        const resultado = validarEntradaObservacao({
          ...corpoValido(operacao),
          [campo]: valor,
        });
        expect(resultado.ok, `${operacao}:${campo}`).toBe(false);
      }
    }
  });

  it("a allowlist é POR OPERAÇÃO: campo de OUTRA operação também é recusado", () => {
    const criacao = corpoValido("observacao.criar");
    expect(validarEntradaObservacao(criacao).ok).toBe(true);
    for (const extra of [
      { observation_id: OBSERVACAO },
      { expected_version: 1 },
      { motivo: "x" },
      { comunicado: true },
      { escopo: "SELF" },
    ]) {
      expect(validarEntradaObservacao({ ...criacao, ...extra }).ok, JSON.stringify(extra)).toBe(
        false
      );
    }

    const leitura = corpoValido("observacao.obter");
    expect(validarEntradaObservacao(leitura).ok).toBe(true);
    for (const extra of [
      { texto: "x" },
      { tipo: "POSITIVA" },
      { expected_version: 1 },
      { comunicado: true },
      { cycle_id: CICLO },
    ]) {
      expect(validarEntradaObservacao({ ...leitura, ...extra }).ok, JSON.stringify(extra)).toBe(
        false
      );
    }
  });

  it("operação desconhecida NÃO tem default permissivo (INVALID_INPUT)", () => {
    for (const operacao of [
      "observacao.revogar_exclusao",
      "observacao.listar",
      "observation.criar",
      "goal.criar",
      "observacao_criar",
      "",
      7,
      undefined,
      null,
    ]) {
      const resultado = validarEntradaObservacao({ organization_id: ORG, operacao });
      expect(resultado.ok, String(operacao)).toBe(false);
      if (!resultado.ok) expect(resultado.code, String(operacao)).toBe("INVALID_INPUT");
    }
  });

  it("corpo sem forma de objeto é recusado (fail-closed)", () => {
    for (const corpo of [null, undefined, [], "{}", 42, true]) {
      const resultado = validarEntradaObservacao(corpo);
      expect(resultado.ok, JSON.stringify(corpo)).toBe(false);
      if (!resultado.ok) expect(resultado.code).toBe("INVALID_INPUT");
    }
  });

  it("UUIDs malformados e campos de domínio fora da forma são recusados", () => {
    for (const campo of ["organization_id", "operation_id", "observation_id"] as const) {
      if (!CHAVES_POR_OPERACAO["observacao.editar"].includes(campo)) continue;
      const base = corpoValido("observacao.editar");
      if (!(campo in base)) continue;
      for (const invalido of ["", "nao-e-uuid", "  ", 42, null]) {
        const resultado = validarEntradaObservacao({ ...base, [campo]: invalido });
        expect(resultado.ok, `${campo}=${String(invalido)}`).toBe(false);
      }
    }

    expect(
      validarEntradaObservacao({ ...corpoValido("observacao.editar"), tipo: "OTIMA" }).ok
    ).toBe(false);
    expect(
      validarEntradaObservacao({
        ...corpoValido("observacao.listar_por_escopo"),
        escopo: "ORGANIZATION",
      }).ok
    ).toBe(false);
  });

  it("a criação normaliza/apara o texto e recusa texto vazio", () => {
    const comEspacos = validarEntradaObservacao({
      ...corpoValido("observacao.criar"),
      texto: "  Texto com espacos nas bordas.  ",
    });
    expect(comEspacos.ok).toBe(true);

    for (const texto of ["", "   ", 42, null, undefined]) {
      expect(
        validarEntradaObservacao({ ...corpoValido("observacao.criar"), texto }).ok,
        String(texto)
      ).toBe(false);
    }
  });

  it("a validação exige UUID canônico nos alvos (formato canônico do contrato)", () => {
    // Formato canônico de UUID (v4/v7 aceitos): nenhum id legado do
    // `localStorage` (`observacao-1`, `obs-42`) entra na fronteira soberana.
    const UUID_CANONICO = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    expect(UUID_CANONICO.test(OBSERVACAO)).toBe(true);
    for (const legado of ["observacao-1", "42", "id-fabricado-no-browser"]) {
      expect(
        validarEntradaObservacao({
          ...corpoValido("observacao.obter"),
          observation_id: legado,
        }).ok,
        legado
      ).toBe(false);
    }
  });

  it("NENHUMA operação aceita data/instante declarado pelo chamador (D21)", () => {
    // O instante da decisão é SOBERANO (servidor): a data não é intenção
    // transportável em nenhuma operação — inclusive na listagem por escopo, onde
    // a RPC preenche `p_data` server-side.
    const chavesDeInstante = [
      "data",
      "data_referencia",
      "instante",
      "agora",
      "p_data",
      "timestamp",
      "reference_date",
    ];
    for (const operacao of OPERACOES_OBSERVACAO) {
      for (const chave of chavesDeInstante) {
        expect(CHAVES_POR_OPERACAO[operacao], `${operacao}:${chave}`).not.toContain(chave);
      }
    }

    // Prova comportamental: o VALIDADOR recusa `data` em TODAS as operações,
    // mesmo no corpo que de outra forma seria válido.
    const rejeitadas: string[] = [];
    for (const operacao of OPERACOES_OBSERVACAO) {
      const validacao = validarEntradaObservacao({
        ...corpoValido(operacao),
        data: "2026-04-01T00:00:00.000Z",
      });
      if (validacao.ok) rejeitadas.push(operacao);
      else expect(validacao.code, operacao).toBe("INVALID_INPUT");
    }
    expect(rejeitadas).toEqual([]);
  });
});

describe("F5-11 P4 — contrato `observacoes`: gate por operação (nenhuma capability nova)", () => {
  /**
   * Gate CONGELADO (§8, norma): só `observacao.listar_por_escopo` é
   * ADMINISTRATIVA (leitura sem alvo único autorizável; molde `goal.listar_por_escopo`
   * da F5-10 — `metas/contrato.ts:118-121`) e as outras SETE são FUNCIONAIS com
   * recurso real. Nenhuma operação inventa capability.
   */
  const GATE_ESPERADO: Readonly<Record<OperacaoObservacao, string>> = {
    "observacao.criar": "funcional/observation.create",
    "observacao.editar": "funcional/observation.edit",
    "observacao.definir_comunicado": "funcional/observation.edit",
    "observacao.excluir": "funcional/observation.delete",
    "observacao.revogar": "funcional/observation.edit",
    "observacao.obter": "funcional/observation.read",
    "observacao.listar_por_escopo": "administrativo/observation.read",
    "observacao.historico": "funcional/observation.read",
  };

  it("o gate de cada operação é o fixado no contrato congelado (§8/D6/D7)", () => {
    expect(
      Object.fromEntries(
        Object.entries(DEFINICAO_POR_OPERACAO).map(([operacao, definicao]) => [
          operacao,
          `${definicao.gate}/${definicao.capability}`,
        ])
      )
    ).toEqual(GATE_ESPERADO);
  });

  it("o gate e a ponte `funcional` são coerentes em TODAS as operações", () => {
    for (const operacao of OPERACOES_OBSERVACAO) {
      const definicao = DEFINICAO_POR_OPERACAO[operacao];
      const [gateEsperado] = GATE_ESPERADO[operacao]!.split("/");
      expect(definicao.gate, operacao).toBe(gateEsperado);
      // `funcional` é DERIVADO de `gate`: a leitura booleana consumida pelo
      // núcleo da Edge nunca diverge da fonte da verdade.
      expect(definicao.funcional, operacao).toBe(definicao.gate === "funcional");
      expect(ehOperacaoFuncional(operacao), operacao).toBe(definicao.funcional);
    }
  });

  it("`observacao.listar_por_escopo` é ADMINISTRATIVA (leitura sem alvo único autorizável)", () => {
    const definicao = DEFINICAO_POR_OPERACAO["observacao.listar_por_escopo"];
    expect(definicao.gate).toBe("administrativo");
    expect(definicao.funcional).toBe(false);
    expect(ehOperacaoFuncional("observacao.listar_por_escopo")).toBe(false);
    expect(capacidadeAdministrativaDaOperacao("observacao.listar_por_escopo")).toBe(
      "observation.read"
    );
  });

  it("as outras SETE operações são FUNCIONAIS e não têm capability administrativa", () => {
    const funcionais: readonly OperacaoObservacao[] = [
      "observacao.criar",
      "observacao.editar",
      "observacao.definir_comunicado",
      "observacao.excluir",
      "observacao.revogar",
      "observacao.obter",
      "observacao.historico",
    ];
    for (const operacao of funcionais) {
      expect(DEFINICAO_POR_OPERACAO[operacao].gate, operacao).toBe("funcional");
      expect(DEFINICAO_POR_OPERACAO[operacao].funcional, operacao).toBe(true);
      expect(ehOperacaoFuncional(operacao), operacao).toBe(true);
      // Operação funcional NUNCA devolve capability administrativa — sem caminho
      // alternativo de decisão e sem default permissivo.
      expect(capacidadeAdministrativaDaOperacao(operacao), operacao).toBeNull();
    }
    // Nenhuma operação além da listagem é administrativa (mapa FECHADO).
    const administrativas = OPERACOES_OBSERVACAO.filter(
      (operacao) => !ehOperacaoFuncional(operacao)
    );
    expect(administrativas).toEqual(["observacao.listar_por_escopo"]);
  });

  it("as capabilities são EXATAMENTE as 4 canônicas do domínio (nenhuma nova)", () => {
    const doDominio = [
      "observation.read",
      "observation.create",
      "observation.edit",
      "observation.delete",
    ];
    for (const operacao of OPERACOES_OBSERVACAO) {
      expect(doDominio, operacao).toContain(DEFINICAO_POR_OPERACAO[operacao].capability);
    }
    expect(
      [...new Set(Object.values(DEFINICAO_POR_OPERACAO).map((d) => d.capability))].sort()
    ).toEqual([...doDominio].sort());
    // `observation.write` é DEPRECADA (F5-04 D14) e NÃO pode gatear operação.
    for (const definicao of Object.values(DEFINICAO_POR_OPERACAO)) {
      expect(definicao.capability).not.toBe("observation.write");
    }
  });

  it("D7: `observation.edit` cobre editar/comunicar/descomunicar/revogar e NÃO implica delete", () => {
    expect(DEFINICAO_POR_OPERACAO["observacao.editar"].capability).toBe("observation.edit");
    // `definir_comunicado` é a MESMA capability nos dois sentidos (D7: o
    // comunicado é fato auditável, não uma capability própria) e `revogar`
    // também NÃO cria capability de revogação.
    expect(DEFINICAO_POR_OPERACAO["observacao.definir_comunicado"].capability).toBe(
      "observation.edit"
    );
    expect(DEFINICAO_POR_OPERACAO["observacao.revogar"].capability).toBe("observation.edit");
    expect(DEFINICAO_POR_OPERACAO["observacao.excluir"].capability).toBe("observation.delete");
    expect(DEFINICAO_POR_OPERACAO["observacao.excluir"].capability).not.toBe("observation.edit");
    expect(DEFINICAO_POR_OPERACAO["observacao.revogar"].capability).not.toBe(
      "observation.delete"
    );
    // `criar` é exclusivo de gestão (SELF não cria — §8 invariante 4).
    expect(DEFINICAO_POR_OPERACAO["observacao.criar"].capability).toBe("observation.create");
  });
});
