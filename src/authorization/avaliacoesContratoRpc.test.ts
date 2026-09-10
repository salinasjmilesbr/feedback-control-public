import { describe, expect, it } from "vitest";
import edgeFonte from "../../supabase/functions/avaliacoes/index.ts?raw";

/**
 * F5-06 (Issue #103) — CONTRATO Edge Function → RPC (PostgREST).
 *
 * A fronteira confiável chama as funções SQL por NOME + ARGUMENTOS NOMEADOS via
 * PostgREST. Se a Edge enviar um argumento que não existe na assinatura da
 * função, o PostgREST responde "function not found" e a operação quebra — foi
 * exatamente o BLOCKER 1 da auditoria (`evaluation_resolver_ciclo` recebia
 * `p_matricula_avaliado`, que nunca existiu na assinatura).
 *
 * Este teste lê o código REAL da Edge e exige que os argumentos de cada RPC do
 * domínio correspondam ao contrato declarado abaixo. A correspondência com o
 * corpo SQL é verificada em runtime pelo validador `03-validar-f5-06-cutover.sql`
 * (que confere assinatura única, ausência de `participant_id` e a resolução
 * soberana da ocorrência). Mudar a Edge sem atualizar o contrato FALHA aqui.
 */

/** Contrato Edge → RPC do domínio de avaliações (F5-06). */
const CONTRATO_EDGE_RPC: Readonly<Record<string, readonly string[]>> = {
  // A matrícula NÃO é enviada: a ponte matrícula → UUID (F3-01) é resolvida
  // antes do Policy Engine, para o alvo autorizável.
  evaluation_resolver_ciclo: [
    "p_organization_id",
    "p_ano",
    "p_numero",
    "p_actor_user_profile_id",
  ],
  // Sem `p_participant_id`: a ocorrência é resolvida server-side pelo ator.
  evaluation_gravar_notas: [
    "p_evaluation_id",
    "p_notas",
    "p_actor_user_profile_id",
  ],
  evaluation_gravar_comentario: [
    "p_evaluation_id",
    "p_escopo",
    "p_criterion_id",
    "p_texto",
    "p_actor_user_profile_id",
  ],
  evaluation_criar: [
    "p_organization_id",
    "p_cycle_id",
    "p_evaluated_collaborator_id",
    "p_actor_user_profile_id",
  ],
  evaluation_concluir: ["p_evaluation_id", "p_actor_user_profile_id"],
  evaluation_reabrir: ["p_evaluation_id", "p_motivo", "p_actor_user_profile_id"],
  evaluation_cancelar: ["p_evaluation_id", "p_motivo", "p_actor_user_profile_id"],
  evaluation_participante_realinhar: [
    "p_evaluation_id",
    "p_motivo",
    "p_actor_user_profile_id",
  ],
  evaluation_painel_participante: ["p_evaluation_id", "p_actor_user_profile_id"],
  evaluation_leitura_avaliado: ["p_evaluation_id", "p_actor_user_profile_id"],
};

interface ChamadaRpc {
  readonly funcao: string;
  readonly argumentos: readonly string[];
  readonly linha: number;
}

/** Remove comentários de linha para não interpretar exemplos como chamadas. */
function semComentarios(codigo: string): string {
  return codigo
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
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

const chamadas = extrairChamadasRpc(edgeFonte as string);

describe("BLOCKER 1 — contrato Edge → RPC (nome + argumentos nomeados)", () => {
  it("a extração das chamadas RPC do código da Edge funciona", () => {
    const nomes = chamadas.map((chamada) => chamada.funcao);
    expect(nomes).toContain("evaluation_resolver_ciclo");
    expect(nomes).toContain("evaluation_gravar_notas");
    expect(nomes).toContain("evaluation_gravar_comentario");
    expect(nomes.length).toBeGreaterThan(5);
  });

  it("os argumentos de cada RPC batem EXATAMENTE com o contrato declarado", () => {
    const divergencias: string[] = [];

    for (const [funcao, esperado] of Object.entries(CONTRATO_EDGE_RPC)) {
      const chamada = chamadas.find((item) => item.funcao === funcao);
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

  it("evaluation_resolver_ciclo NÃO envia p_matricula_avaliado (BLOCKER 1)", () => {
    const chamada = chamadas.find(
      (item) => item.funcao === "evaluation_resolver_ciclo"
    );
    expect(chamada).toBeDefined();
    expect(chamada!.argumentos).not.toContain("p_matricula_avaliado");
    // E a matrícula continua sendo INTENÇÃO na criação (ponte F3-01).
    expect(
      chamadas.some((item) => item.funcao === "evaluation_criar")
    ).toBe(true);
  });
});

describe("BLOCKER 2 — participant_id fora do contrato e das RPCs", () => {
  it("a Edge NÃO envia participant_id em nenhuma chamada de RPC", () => {
    const comParticipante = chamadas.filter((chamada) =>
      chamada.argumentos.includes("participant_id")
    );
    expect(comParticipante).toEqual([]);
  });

  it("as RPCs de gravação NÃO declaram p_participant_id no contrato", () => {
    for (const funcao of [
      "evaluation_gravar_notas",
      "evaluation_gravar_comentario",
    ]) {
      expect(CONTRATO_EDGE_RPC[funcao], funcao).not.toContain("p_participant_id");
    }
  });
});
