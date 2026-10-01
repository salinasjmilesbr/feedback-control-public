/**
 * F6 Incremento 1 (R2) — LEITURA COLETIVA dos participantes.
 *
 * Cobre: contrato/validação estrita da operação, entitlement (regra pura),
 * probe de domínio próprio (L1), M1 (o probe é determinado pela OPERAÇÃO e não
 * por input do cliente) e o encanamento do core (ALLOW/DENY/erro, sem efeito
 * quando negado). A projeção RPC é validada por contrato estático da migration;
 * SQL/Edge real é pendência declarada.
 */
import { describe, expect, it } from "vitest";
import {
  CAPABILITY_POR_OPERACAO,
  SCOPE_LEITURA_LEITURA_COLETIVA,
  SCOPES_ESCRITA_LEITURA_COLETIVA,
  resolverLeituraColetiva,
  tipoAlvoDaOperacao,
  validarEntradaAvaliacao,
  type PainelParticipantesAvaliacao,
} from "../infrastructure/supabase/avaliacoes/contrato.ts";
import { estadoDominioLeituraColetivaAvaliacao } from "./estadoDominioAvaliacao.ts";
import { avaliacoes, type DepsAvaliacoes } from "../../supabase/functions/avaliacoes/core.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const AVALIACAO = "22222222-2222-4222-8222-222222222222";
const USER = "33333333-3333-4333-8333-333333333333";
const SUB = "44444444-4444-4444-8444-444444444444";

const corpoColetivo = {
  organization_id: ORG,
  operacao: "evaluation.painel_participantes",
  alvo: { type: "evaluation", id: AVALIACAO },
};

const payload: PainelParticipantesAvaliacao = {
  evaluationId: AVALIACAO,
  organizationId: ORG,
  cycleId: "55555555-5555-4555-8555-555555555555",
  cycleAno: 2026,
  cycleNumero: 1,
  configVersionId: "66666666-6666-4666-8666-666666666666",
  status: "RASCUNHO",
  evaluatedCollaboratorId: "77777777-7777-4777-8777-777777777777",
  meuParticipante: { ocorrenciaId: "88888888-8888-4888-8888-888888888888", roleType: "GESTAO_CADEIA", meusPapeis: ["GESTAO_CADEIA"] },
  participantes: [],
  criterios: [],
  subcriterios: [],
  notas: [],
  comentarios: [],
  feedbacksFinais: [],
  progressoFactual: [],
};

function requisicao(corpo: unknown): Request {
  return new Request("http://localhost/functions/v1/avaliacoes", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer ok" },
    body: JSON.stringify(corpo),
  });
}

function deps(over: Partial<DepsAvaliacoes> = {}): DepsAvaliacoes {
  return {
    resolveCaller: async () => USER,
    avaliarAutorizacao: async () => ({ allowed: true }),
    executarRpc: async () => ({ data: null }),
    avaliarPainelParticipantes: async () => ({ allowed: true }),
    executarPainelParticipantes: async () => ({ data: payload }),
    ...over,
  };
}

describe("contrato da leitura coletiva (R2)", () => {
  it("a operação usa alvo avaliação e capability nominal já existente", () => {
    expect(tipoAlvoDaOperacao("evaluation.painel_participantes")).toBe("evaluation");
    expect(CAPABILITY_POR_OPERACAO["evaluation.painel_participantes"]).toBe("evaluation.write");
    // Catálogo FECHADO: nenhuma capability nova.
    expect(new Set(Object.values(CAPABILITY_POR_OPERACAO))).toEqual(
      new Set([
        "evaluation.create",
        "evaluation.read",
        "evaluation.write",
        "evaluation.reopen",
        "evaluation.cancel",
        "report.read",
      ])
    );
  });

  it("declara os entitlements do R2 sem criar scope novo", () => {
    expect(SCOPES_ESCRITA_LEITURA_COLETIVA).toEqual([
      "DIRECT_REPORTS",
      "DESCENDANTS",
      "ASSIGNED",
    ]);
    expect(SCOPE_LEITURA_LEITURA_COLETIVA).toBe("ASSIGNED");
  });

  it("validação estrita: só operacao/organization_id/alvo", () => {
    expect(validarEntradaAvaliacao(corpoColetivo).ok).toBe(true);
    for (const extra of [
      { notas: [] },
      { cycle_id: "55555555-5555-4555-8555-555555555555" },
      { participant_id: "88888888-8888-4888-8888-888888888888" },
      { probeLeituraColetiva: true },
    ]) {
      const r = validarEntradaAvaliacao({ ...corpoColetivo, ...extra });
      expect(r.ok, JSON.stringify(extra)).toBe(false);
    }
  });

  it("recusa alvo de colaborador (a projeção é da avaliação)", () => {
    const r = validarEntradaAvaliacao({
      ...corpoColetivo,
      alvo: { type: "collaborator", id: SUB },
    });
    expect(r.ok).toBe(false);
  });
});

describe("entitlement da leitura coletiva (regra pura, fail-closed)", () => {
  it("participante vigente com write OU com read+ASSIGNED ⇒ ALLOW", () => {
    expect(
      resolverLeituraColetiva({
        participanteVigente: true,
        autorizaEscrita: true,
        autorizaLeituraAssigned: false,
      }).allowed
    ).toBe(true);
    expect(
      resolverLeituraColetiva({
        participanteVigente: true,
        autorizaEscrita: false,
        autorizaLeituraAssigned: true,
      }).allowed
    ).toBe(true);
  });

  it("sem participação vigente ⇒ DENY mesmo com capability", () => {
    for (const autorizaEscrita of [true, false]) {
      for (const autorizaLeituraAssigned of [true, false]) {
        expect(
          resolverLeituraColetiva({
            participanteVigente: false,
            autorizaEscrita,
            autorizaLeituraAssigned,
          }).allowed
        ).toBe(false);
      }
    }
  });

  it("participante sem nenhum dos dois caminhos ⇒ DENY (read isolado não basta)", () => {
    expect(
      resolverLeituraColetiva({
        participanteVigente: true,
        autorizaEscrita: false,
        autorizaLeituraAssigned: false,
      }).allowed
    ).toBe(false);
  });
});

describe("L1 — o probe coletivo não aceita evaluation.create", () => {
  it("admite read/write nos três estados e nega create", () => {
    for (const status of ["RASCUNHO", "PRONTA_PARA_FEEDBACK", "CONCLUIDA"]) {
      const probe = estadoDominioLeituraColetivaAvaliacao({ status });
      expect(probe.allows("evaluation.read"), status).toBe(true);
      expect(probe.allows("evaluation.write"), status).toBe(true);
      expect(probe.allows("evaluation.create"), status).toBe(false);
    }
  });

  it("CANCELADA e status ausente falham fechado", () => {
    for (const status of ["CANCELADA", ""]) {
      const probe = estadoDominioLeituraColetivaAvaliacao({ status });
      expect(probe.allows("evaluation.read"), status).toBe(false);
      expect(probe.allows("evaluation.write"), status).toBe(false);
    }
  });
});

describe("core: projeção coletiva (ALLOW/DENY/erro)", () => {
  it("ALLOW devolve a projeção com 200", async () => {
    const resposta = await avaliacoes(requisicao(corpoColetivo), deps());
    expect(resposta.status).toBe(200);
    const json = (await resposta.json()) as { ok: boolean; resultado: unknown };
    expect(json.ok).toBe(true);
    expect(json.resultado).toMatchObject({ evaluationId: AVALIACAO });
  });

  it("M1 — o cliente NÃO seleciona o probe: chave extra ⇒ 400 e nenhum efeito", async () => {
    let autorizou = false;
    const resposta = await avaliacoes(
      requisicao({ ...corpoColetivo, probeLeituraColetiva: true }),
      deps({
        avaliarPainelParticipantes: async () => {
          autorizou = true;
          return { allowed: true };
        },
      })
    );
    expect(resposta.status).toBe(400);
    expect(autorizou).toBe(false);
  });

  it("DENY não executa a RPC (fail-closed)", async () => {
    let executou = false;
    const resposta = await avaliacoes(
      requisicao(corpoColetivo),
      deps({
        avaliarPainelParticipantes: async () => ({ allowed: false, code: "FORBIDDEN" }),
        executarPainelParticipantes: async () => {
          executou = true;
          return { data: payload };
        },
      })
    );
    expect(resposta.status).toBe(403);
    expect(executou).toBe(false);
  });

  it("sem as deps da operação ⇒ 500 (operação indisponível)", async () => {
    const resposta = await avaliacoes(
      requisicao(corpoColetivo),
      deps({ avaliarPainelParticipantes: undefined, executarPainelParticipantes: undefined })
    );
    expect(resposta.status).toBe(500);
  });

  it("payload ausente após ALLOW ⇒ 500 (sem revelar existência)", async () => {
    const resposta = await avaliacoes(
      requisicao(corpoColetivo),
      deps({ executarPainelParticipantes: async () => ({ data: null }) })
    );
    expect(resposta.status).toBe(500);
  });

  it("erro do executor é mapeado em código público", async () => {
    const resposta = await avaliacoes(
      requisicao(corpoColetivo),
      deps({
        executarPainelParticipantes: async () => ({ error: { code: "CONFLICT" } }),
      })
    );
    expect(resposta.status).toBe(409);
  });
});
