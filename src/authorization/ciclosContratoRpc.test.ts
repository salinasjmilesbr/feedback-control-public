import { describe, expect, it } from "vitest";
import edgeCiclosFonte from "../../supabase/functions/ciclos/index.ts?raw";
import edgeCoreFonte from "../../supabase/functions/ciclos/core.ts?raw";
import migracaoD28Fonte from "../../supabase/migrations/20260921000000_f5_09_p7_catalog_admin_bundle.sql?raw";
import validadorP7Fonte from "../../supabase/validacao/11-validar-f5-09-p7.sql?raw";
import cenarioD28Fonte from "../../supabase/validacao/12-cenario-f5-09-p7-d28.sql?raw";
import validadorD28Fonte from "../../supabase/validacao/13-validar-f5-09-p7-d28.sql?raw";
import adapterFonte from "../infrastructure/supabase/ciclos/edgeCiclos.ts?raw";
import {
  DEFINICAO_POR_OPERACAO,
  OPERACOES_CICLO,
  capacidadeAdministrativaDaOperacao,
  ehOperacaoCiclo,
  ehOperacaoFuncional,
} from "../infrastructure/supabase/ciclos/contrato.ts";
import { capabilityCanonica } from "./catalogoCapabilities.ts";

/**
 * F5-09 P7 (Issue #202) — CONTRATO Edge → RPC e guardas estáticos do domínio.
 *
 * A fronteira confiável chama as funções SQL por NOME + ARGUMENTOS NOMEADOS via
 * PostgREST: um argumento inexistente faz o PostgREST responder "function not
 * found" e a operação inteira quebra (histórico real da F5-06). Este teste lê o
 * código REAL da Edge e exige correspondência EXATA com as assinaturas
 * verificadas nas migrations P2–P4 (`p_payload_hash` NÃO é parâmetro: o hash é
 * derivado server-side, desvio declarado nas fases P2–P4).
 *
 * Também prova que a Edge NÃO replica o domínio (lifecycle, versão, sobreposição,
 * materialização), que `service_role` só aparece como executor depois do gate e
 * que a reconciliação D28 é ESTRITA (só `cycle.manage`, aditivo).
 */

const CONTRATO_EDGE_RPC: Readonly<Record<string, readonly string[]>> = {
  ciclo_criar: [
    "p_organization_id",
    "p_ano",
    "p_numero",
    "p_data_inicio",
    "p_data_fim",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  ciclo_editar: [
    "p_cycle_id",
    "p_organization_id",
    "p_ano",
    "p_numero",
    "p_data_inicio",
    "p_data_fim",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  ciclo_ativar: [
    "p_cycle_id",
    "p_organization_id",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  ciclo_encerrar: [
    "p_cycle_id",
    "p_organization_id",
    "p_motivo",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  ciclo_cancelar: [
    "p_cycle_id",
    "p_organization_id",
    "p_motivo",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  ciclo_reabrir: [
    "p_cycle_id",
    "p_organization_id",
    "p_motivo",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  ciclo_corrigir_periodo: [
    "p_cycle_id",
    "p_organization_id",
    "p_data_inicio",
    "p_data_fim",
    "p_justificativa",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
  ciclo_incluir_admissao: [
    "p_cycle_id",
    "p_organization_id",
    "p_collaborator_id",
    "p_motivo",
    "p_expected_version",
    "p_actor_user_profile_id",
    "p_operation_id",
  ],
};

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

const chamadas = extrairChamadasRpc(edgeCiclosFonte as string);
const chamadasCiclo = chamadas.filter((chamada) => chamada.funcao.startsWith("ciclo_"));

/**
 * Fontes SQL do schema (migrations). Usadas para provar que a Edge só chama
 * funções que EXISTEM — um nome divergente faz o PostgREST responder
 * "function not found" e quebra a operação (BLOCKER 1 da F5-06). A verificação
 * é feita contra o repositório em vez de uma lista fixa de nomes (a lista fixa
 * envelhece e não cobre renomeações de helpers da fronteira).
 */
const MIGRACOES: Readonly<Record<string, string>> = import.meta.glob(
  "../../supabase/migrations/*.sql",
  { query: "?raw", import: "default", eager: true }
) as Readonly<Record<string, string>>;
const SQL_DO_SCHEMA = Object.values(MIGRACOES).join("\n");

const OPERACOES = [
  "cycle.criar",
  "cycle.editar",
  "cycle.ativar",
  "cycle.encerrar",
  "cycle.cancelar",
  "cycle.reabrir",
  "cycle.corrigir_periodo",
  "cycle.admissao.incluir",
] as const;

describe("F5-09 P7 — contrato Edge → RPC (nome + argumentos nomeados)", () => {
  it("a extração encontra as OITO RPCs soberanas de ciclo", () => {
    const nomes = chamadasCiclo.map((chamada) => chamada.funcao).sort();
    expect(nomes).toEqual(Object.keys(CONTRATO_EDGE_RPC).sort());
    // Além das oito, a Edge só chama as TRÊS resolutoras de leitura da fronteira.
    const outras = Array.from(
      new Set(
        chamadas
          .filter((chamada) => !chamada.funcao.startsWith("ciclo_"))
          .map((chamada) => chamada.funcao)
      )
    );
    expect(outras).toHaveLength(3);
  });

  it("TODA função chamada pela Edge existe no schema (guard do BLOCKER 1)", () => {
    const nomes = Array.from(new Set(chamadas.map((chamada) => chamada.funcao)));
    expect(nomes.length).toBeGreaterThanOrEqual(11);

    const inexistentes = nomes.filter(
      (funcao) => !SQL_DO_SCHEMA.includes(`function public.${funcao}(`)
    );
    expect(inexistentes).toEqual([]);
  });

  it("os argumentos de cada RPC batem EXATAMENTE com o contrato declarado", () => {
    const divergencias: string[] = [];

    for (const [funcao, esperado] of Object.entries(CONTRATO_EDGE_RPC)) {
      const chamada = chamadasCiclo.find((item) => item.funcao === funcao);
      if (!chamada) {
        divergencias.push(`${funcao}: a Edge não chama esta RPC`);
        continue;
      }
      const enviado = [...chamada.argumentos].sort();
      const contrato = [...esperado].sort();
      if (JSON.stringify(enviado) !== JSON.stringify(contrato)) {
        divergencias.push(
          `linha ${chamada.linha}: ${funcao} envia [${enviado.join(", ")}] ` +
            `mas o contrato exige [${contrato.join(", ")}]`
        );
      }
    }

    expect(divergencias).toEqual([]);
  });

  it("nenhuma RPC recebe hash/ator vindos do corpo (o ator é o auth.uid verificado)", () => {
    const proibidos = ["p_payload_hash", "p_actor_id", "p_author_id", "p_actor_collaborator_id"];
    for (const chamada of chamadasCiclo) {
      for (const proibido of proibidos) {
        expect(chamada.argumentos, `${chamada.funcao}:${proibido}`).not.toContain(proibido);
      }
      // Toda RPC de ciclo recebe o ATOR verificado.
      expect(chamada.argumentos, chamada.funcao).toContain("p_actor_user_profile_id");
    }
    // Nenhuma RPC de ciclo envia `p_payload_hash` (hash derivado server-side).
    expect(codigoSemComentarios(edgeCiclosFonte as string).includes("p_payload_hash")).toBe(false);
  });
});

describe("F5-09 P7 — mapa de operações e capabilities (P: nenhuma nova)", () => {
  it("o mapa cobre EXATAMENTE as oito operações contratadas", () => {
    expect([...OPERACOES_CICLO].sort()).toEqual([...OPERACOES].sort());
    expect(Object.keys(DEFINICAO_POR_OPERACAO).sort()).toEqual([...OPERACOES].sort());
  });

  it("toda capability do mapa é CANÔNICA e de ciclo (nunca alias, nunca nova)", () => {
    const deCiclo = [
      "cycle.read",
      "cycle.manage",
      "cycle.cancel",
      "cycle.reopen",
      "cycle.period.correct",
    ];
    for (const [operacao, definicao] of Object.entries(DEFINICAO_POR_OPERACAO)) {
      const canonica = capabilityCanonica(definicao.capability);
      expect(canonica, operacao).toBe(definicao.capability);
      expect(deCiclo, operacao).toContain(definicao.capability);
    }
  });

  it("o plano ADMINISTRATIVO existe SÓ para `cycle.criar` (D21) e não tem default", () => {
    const administrativas = OPERACOES_CICLO.filter(
      (operacao) => !ehOperacaoFuncional(operacao)
    );
    expect(administrativas).toEqual(["cycle.criar"]);
    expect(capacidadeAdministrativaDaOperacao("cycle.criar")).toBe("cycle.manage");
    for (const operacao of OPERACOES_CICLO) {
      if (operacao === "cycle.criar") continue;
      expect(capacidadeAdministrativaDaOperacao(operacao), operacao).toBeNull();
    }
    // Operação desconhecida NUNCA é aceita (nenhum caminho com default).
    expect(ehOperacaoCiclo("cycle.excluir")).toBe(false);
    expect(ehOperacaoCiclo("cycle.listar")).toBe(false);
    expect(ehOperacaoCiclo(undefined)).toBe(false);
  });
});

describe("F5-09 P7 — a Edge não replica o domínio (N) e não decide autorização", () => {
  it("nenhum estado de lifecycle é codificado na Edge", () => {
    const codigoEdge = codigoSemComentarios(edgeCiclosFonte as string);
    const codigoCore = codigoSemComentarios(edgeCoreFonte as string);

    for (const fonte of [codigoEdge, codigoCore]) {
      for (const status of ["PLANEJADO", "ENCERRADO", "CANCELADO"]) {
        expect(fonte, status).not.toContain(status);
      }
      // "ATIVO" só pode existir como tenant/membership — nunca como estado de
      // ciclo comparado na fronteira.
      expect(fonte).not.toMatch(/status\s*===\s*"ATIVO"/);
    }
  });

  it("a Edge não materializa, não fecha pendências e não sobrepõe período", () => {
    const proibidos = [
      "materializar_colegiado_ciclo",
      "materializar_responsabilidades_avaliacao",
      "evaluation_fechar_ciclo_pendencias",
      "evaluation_cancelar",
      "daterange",
      "sobrepo",
    ];
    for (const proibido of proibidos) {
      expect(codigoSemComentarios(edgeCiclosFonte as string), proibido).not.toContain(proibido);
      expect(codigoSemComentarios(edgeCoreFonte as string), proibido).not.toContain(proibido);
    }
  });

  it("`service_role` só existe no wiring privilegiado e a RPC só roda DEPOIS do gate", () => {
    const codigoCore = codigoSemComentarios(edgeCoreFonte as string);
    const codigoEdge = codigoSemComentarios(edgeCiclosFonte as string);

    // A credencial privilegiada não aparece no núcleo testável.
    expect(codigoCore).not.toContain("service_role");
    expect(codigoCore).not.toContain("SERVICE_ROLE");
    expect(codigoEdge).toContain("SUPABASE_SERVICE_ROLE_KEY");

    // Ordem inegociável no núcleo: identidade → forma → tenant → gate → execução.
    const posGate = codigoCore.indexOf("const negacao = await avaliarGate");
    const posExecucao = codigoCore.indexOf("await deps.executarRpc(");
    expect(posGate).toBeGreaterThan(-1);
    expect(posExecucao).toBeGreaterThan(posGate);
    expect(codigoCore.indexOf("deps.resolveCaller(")).toBeLessThan(posGate);

    // O gate funcional usa o Policy Engine real; o administrativo usa as
    // capabilities efetivas — nenhum caminho alternativo de decisão.
    expect(codigoEdge).toContain("avaliarOperacaoAutorizacao");
    expect(codigoCore).toContain("deps.avaliarAutorizacao(");
    expect(codigoCore).toContain("resolverCapabilitiesEfetivas");
  });
});

describe("F5-09 P7 — D28 estrito (O) e ausência de capability nova (P)", () => {
  it("a migration faz UM único insert, guiado por `cycle.manage`, e é idempotente", () => {
    const inserts = (migracaoD28Fonte as string).match(
      /insert into public\.access_role_capabilities/g
    );
    expect(inserts).toHaveLength(1);
    expect(migracaoD28Fonte as string).toContain("v_role, v_cap");
    expect(migracaoD28Fonte as string).toContain("where not exists");
    expect(migracaoD28Fonte as string).toContain("where code = 'cycle.manage'");
  });

  it("a migration NÃO cria capability e NÃO concede as três excepcionais", () => {
    expect(migracaoD28Fonte as string).not.toContain("insert into public.capabilities");
    // As excepcionais aparecem apenas em guardas de recusa.
    for (const excepcional of ["cycle.cancel", "cycle.reopen", "cycle.period.correct"]) {
      expect(migracaoD28Fonte as string).toContain(excepcional);
    }
    const trechoInsert = (migracaoD28Fonte as string).slice(
      (migracaoD28Fonte as string).indexOf("insert into public.access_role_capabilities"),
      (migracaoD28Fonte as string).indexOf("-- (5) Guarda final")
    );
    expect(trechoInsert).not.toContain("cycle.cancel");
    expect(trechoInsert).not.toContain("cycle.reopen");
    expect(trechoInsert).not.toContain("cycle.period.correct");
  });

  it("o validador P7 confere o bundle de 9 com cycle.manage e as excepcionais fora", () => {
    expect(validadorP7Fonte as string).toContain("'cycle.manage','cycle.read'");
    expect(validadorP7Fonte as string).toContain(
      "'cycle.cancel', 'cycle.reopen', 'cycle.period.correct'"
    );
    // P5/P6 preservadas pelo validador.
    expect(validadorP7Fonte as string).toContain("user_has_active_membership");
    expect(validadorP7Fonte as string).toContain("relrowsecurity");
    expect(validadorP7Fonte as string).toContain("cycle_events");
  });
});

describe("F5-09 P7 — D28: guardas por TIPO de role e idempotencia (correcao Codex)", () => {
  const marcadorExcepcionais = "('cycle.cancel', 'cycle.reopen', 'cycle.period.correct')";

  it("a proibicao das tres excepcionais vale SOMENTE para roles de SISTEMA", () => {
    const migracao = migracaoD28Fonte as string;
    expect(migracao).toContain("join public.access_roles r on r.id = m.access_role_id");

    // TODA ocorrencia da lista das tres precisa estar sob `r.is_system = true`.
    let indice = migracao.indexOf(marcadorExcepcionais);
    let ocorrencias = 0;
    while (indice !== -1) {
      ocorrencias += 1;
      const contexto = migracao.slice(Math.max(0, indice - 400), indice);
      expect(contexto, `ocorrencia ${ocorrencias}`).toContain("is_system = true");
      indice = migracao.indexOf(marcadorExcepcionais, indice + 1);
    }
    expect(ocorrencias).toBeGreaterThanOrEqual(2); // preflight + guarda final

    // Nao pode existir proibicao global (sem o tipo da role).
    expect(migracao).not.toMatch(
      /where\s+c\.code in \(\s*'cycle\.cancel'[\s\S]{0,220}?\)\s*\)\s*then\s+raise exception/
    );
  });

  it("a migration e realmente IDEMPOTENTE (nao assume +1 fixo)", () => {
    const migracao = migracaoD28Fonte as string;
    expect(migracao).toContain("v_ja_existia");
    expect(migracao).toContain("case when v_ja_existia then 0 else 1 end");
    expect(migracao).toContain("v_bundle_esperado");
    // O antigo `v_bundle_antes + 1` incondicional nao pode voltar.
    expect(migracao).not.toContain("<> v_bundle_antes + 1");
  });

  it("o cenario e o validador D28 cobrem concessoes LEGITIMAS em role customizada", () => {
    // Cenario: role NAO-sistema com as tres excepcionais + estado de idempotencia.
    expect(cenarioD28Fonte as string).toContain("'d28_custom_ciclos_p7'");
    expect(cenarioD28Fonte as string).toMatch(/false,\s*'e7a00000/); // is_system = false
    expect(cenarioD28Fonte as string).toContain(
      "'cycle.cancel', 'cycle.reopen', 'cycle.period.correct'"
    );
    expect(cenarioD28Fonte as string).toContain("delete from public.access_role_capabilities");

    // Validador D28: A-H com semantica por tipo de role e idempotencia.
    const validador = validadorD28Fonte as string;
    expect(validador).toContain("is_system = true");
    expect(validador).toContain("is_system = false");
    expect(validador).toContain("EXATAMENTE uma vez");
    expect(validador).toContain("idempotencia provada");
    expect(validador).toContain("catalogo intacto");
  });

  it("o validador P7 (11) usa a MESMA semantica de sistema (coerencia migration/validator)", () => {
    expect(validadorP7Fonte as string).toContain("r.is_system = true");
  });
});

describe("F5-09 P7 — adapter de cliente espelha o contrato", () => {
  it("o adapter oferece exatamente as oito operações contratadas", () => {
    for (const operacao of OPERACOES) {
      const ocorrencias = (adapterFonte as string).split(`"${operacao}"`).length - 1;
      expect(ocorrencias, operacao).toBe(1);
    }
    expect(adapterFonte as string).toContain('FUNCAO_CICLOS = "ciclos"');
    // Nenhuma autoridade do lado do cliente (no CÓDIGO, não nos comentários).
    const codigoAdapter = codigoSemComentarios(adapterFonte as string);
    expect(codigoAdapter).not.toContain("service_role");
    expect(codigoAdapter).not.toContain("SERVICE_ROLE");
    expect(codigoAdapter).not.toContain("localStorage");
    expect(codigoAdapter).not.toContain(".rpc(");
  });
});
