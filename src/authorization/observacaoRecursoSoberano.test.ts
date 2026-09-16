import { describe, expect, it } from "vitest";
import type { AuthIdentity } from "../auth/tipos.ts";
import { estadoDominioObservacao as estadoDoAdaptador } from "./authorizationPolicy";
import type { Capability } from "./Capability.ts";
import {
  avaliarOperacaoAutorizacao,
  type DepsContextoAutorizacao,
} from "./contextoAutorizacao.ts";
import {
  estadoDominioObservacao,
  exigeAutoriaObservacao,
} from "./estadoDominioObservacao.ts";
import type { DomainStateProbe, TargetRef } from "./policyEngine/types.ts";
import type { RecursoSoberanoCarregado } from "./resourceContextReal.ts";

/**
 * F5-11 P4 (§8; D3/D5/D7/D9/D11/D12/D15) — OBSERVAÇÃO na FRONTEIRA SOBERANA.
 *
 * Prova, pelo CAMINHO DE PRODUÇÃO (`avaliarOperacaoAutorizacao` →
 * `criarProvidersReais` → Policy Engine REAL, sem `localWorld`/`mundoFuncional`)
 * e com dependências soberanas sintéticas, que a autorização de observação:
 *   - usa o TARGET REAL (`{type:"observation", id: UUID}` de
 *     `evaluation_observations.id`);
 *   - deriva o `domainState` da LINHA SOBERANA (`comunicado`, `excluida`, status
 *     do CICLO e status do colaborador-ALVO) pela fonte única
 *     `estadoDominioObservacao`, NUNCA de estado declarado pelo chamador;
 *   - resolve a RELAÇÃO sobre o colaborador-ALVO da observação (`donoDoAlvo`):
 *     `SELF` = o ator é o próprio alvo; `DIRECT_REPORTS`/`DESCENDANTS` = o alvo
 *     está no escopo resolvido; `ORGANIZATION`/`ASSIGNED`/unidade são NEGADOS
 *     (fail-closed);
 *   - aplica a AUTORIA D5 (`observation.edit`/`observation.delete` só pelo autor
 *     soberano da LINHA) e a leitura SELF-comunicada (D7/D9);
 *   - nega cross-tenant e observação inexistente.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const AUTH = "33333333-3333-4333-8333-333333333333";
const CICLO = "55555555-5555-4555-8555-555555555555";
const OBSERVACAO = "66666666-6666-4666-8666-666666666666";
/** Colaborador-ALVO da observação (`evaluation_observations.collaborator_id`). */
const ALVO = "77777777-7777-4777-8777-777777777777";
/** Colaborador do AUTOR soberano da observação (gestor do alvo). */
const AUTOR = "88888888-8888-4888-8888-888888888888";
/** Gestor SEM relação com o alvo (fora do escopo na data). */
const FORA = "99999999-9999-4999-8999-999999999999";

interface Cenario {
  readonly capability?: Capability;
  readonly capabilitiesAtor?: readonly Capability[];
  readonly scopes?: readonly string[];
  readonly escoposPorCapability?: Readonly<Record<string, readonly string[]>>;
  /** Fatos SOBERANOS da linha `evaluation_observations`. */
  readonly comunicado?: boolean;
  readonly excluida?: boolean;
  readonly cicloStatus?: string;
  readonly authorCollaboratorId?: string | null;
  /** Status SOBERANO vigente do colaborador-ALVO (D11). */
  readonly colaboradorStatus?: string;
  readonly recurso?: RecursoSoberanoCarregado | null;
  /** Alvos pré-resolvidos por scope (F4-02/F3) — a relação VIGENTE na data. */
  readonly alvos?: Readonly<
    Record<string, readonly { collaboratorId: string | null; positionId: string | null }[]>
  >;
  readonly vinculo?: string | null;
  readonly organizationId?: string;
  /** Alvo da operação (default: a própria observação). */
  readonly alvo?: TargetRef;
  /** Estado DECLARADO pelo chamador (o browser nunca declara estado soberano). */
  readonly domainStateDeclarado?: DomainStateProbe;
  /**
   * Contexto SOBERANO resolvido na fronteira (D11/D12): status VIGENTE do
   * colaborador-alvo e status da LINHA do ciclo. `null` ⇒ o resolvedor não
   * devolve contexto (fail-closed). NUNCA é estado declarado pelo chamador.
   */
  readonly contextoAvaliacao?: {
    readonly status?: string;
    readonly colaboradorStatus?: string;
    readonly cicloStatus?: string;
    readonly encerradaComPendencias?: boolean;
    readonly cicloPermiteNovaAvaliacao?: boolean;
    readonly avaliadoApto?: boolean;
  } | null;
}

function identidade(): AuthIdentity {
  return {
    authUserId: AUTH,
    perfil: { id: AUTH, status: "active" },
    memberships: [{ id: "m-1", organizationId: ORG, status: "active" }],
    organizacoes: [{ id: ORG, name: "Org sintetica" }],
  } as unknown as AuthIdentity;
}

function recursoObservacao(cenario: Cenario): RecursoSoberanoCarregado {
  return {
    kind: "observation",
    id: OBSERVACAO,
    organizationId: ORG,
    ownerCollaboratorId: ALVO,
    cycleId: CICLO,
    comunicado: cenario.comunicado ?? false,
    excluida: cenario.excluida ?? false,
    cicloStatus: cenario.cicloStatus ?? "ATIVO",
    authorCollaboratorId:
      cenario.authorCollaboratorId === undefined ? AUTOR : cenario.authorCollaboratorId,
    ...(cenario.colaboradorStatus === undefined
      ? { colaboradorStatus: "ATIVO" }
      : { colaboradorStatus: cenario.colaboradorStatus }),
  };
}

/** Fronteira REAL com dependências soberanas sintéticas (sem mundo local). */
function fronteira(cenario: Cenario): DepsContextoAutorizacao {
  const recurso =
    cenario.recurso === undefined ? recursoObservacao(cenario) : cenario.recurso;

  return {
    agora: () => new Date("2026-05-01T12:00:00Z"),
    resolverIdentidade: async () => identidade(),
    resolverColaboradorVinculado: async () =>
      cenario.vinculo === undefined ? ALVO : cenario.vinculo,
    resolverCapabilitiesEscopos: async () =>
      (cenario.capabilitiesAtor ?? [cenario.capability ?? "observation.read"]).map(
        (capability) => ({
          capability,
          scopes: (cenario.escoposPorCapability?.[capability] ??
            cenario.scopes ?? ["SELF"]) as never,
        })
      ),
    resolverAlvosEscopo: async ({ scope }) => cenario.alvos?.[scope] ?? [],
    carregarRecurso: async () => recurso,
    // Contexto SOBERANO do alvo (D11/D12): quando o cenário não o declara, o
    // resolvedor devolve o status da linha e OMITE os campos novos — exatamente
    // o comportamento retrocompatível das Edges/consumidores anteriores.
    carregarContextoAvaliacao: async () => {
      if (cenario.contextoAvaliacao === null) return null;
      const contexto = cenario.contextoAvaliacao ?? {};
      // A fronteira encaminha o contexto ao probe do DOMÍNIO da capability: o
      // probe da OBSERVAÇÃO consome `colaboradorStatus`/`cicloStatus` (D11/D12)
      // e o probe da CRIAÇÃO de avaliação consome
      // `cicloPermiteNovaAvaliacao`/`avaliadoApto` — omitir qualquer um deles
      // faria o probe alheio negar por ausência de evidência (invariante 6).
      return {
        status: contexto.status ?? "PRONTA_PARA_FEEDBACK",
        ...(contexto.colaboradorStatus === undefined
          ? {}
          : { colaboradorStatus: contexto.colaboradorStatus }),
        ...(contexto.cicloStatus === undefined ? {} : { cicloStatus: contexto.cicloStatus }),
        ...(contexto.encerradaComPendencias === undefined
          ? {}
          : { encerradaComPendencias: contexto.encerradaComPendencias }),
        ...(contexto.cicloPermiteNovaAvaliacao === undefined
          ? {}
          : { cicloPermiteNovaAvaliacao: contexto.cicloPermiteNovaAvaliacao }),
        ...(contexto.avaliadoApto === undefined ? {} : { avaliadoApto: contexto.avaliadoApto }),
      };
    },
  };
}

async function decidir(cenario: Cenario = {}) {
  // `avaliarOperacaoAutorizacao` devolve a DECISÃO diretamente
  // (`AuthorizationDecision { allowed, denial? }` — molde
  // `contextoAutorizacao.test.ts:116-123`). O harness embrulha em `{ decisao }`,
  // que é o padrão de leitura usado por TODOS os cenários deste arquivo.
  const decisao = await avaliarOperacaoAutorizacao(
    {
      authUserId: AUTH,
      organizationId: cenario.organizationId ?? ORG,
      capability: cenario.capability ?? "observation.read",
      alvo: cenario.alvo ?? { type: "observation", id: OBSERVACAO },
      ...(cenario.domainStateDeclarado ? { domainState: cenario.domainStateDeclarado } : {}),
    },
    fronteira(cenario)
  );
  return { decisao };
}

/** Alvos SELF do PRÓPRIO colaborador-alvo da observação (leitura SELF — §8 linha 2). */
const ALVOS_SELF_ALVO = { SELF: [{ collaboratorId: ALVO, positionId: null }] };
/** Alvos SELF de um terceiro sem relação com a observação. */
const ALVOS_SELF_FORA = { SELF: [{ collaboratorId: FORA, positionId: null }] };
/** Relação de gestão vigente sobre o colaborador-alvo. */
const ALVOS_GESTAO_ALVO = {
  DIRECT_REPORTS: [{ collaboratorId: ALVO, positionId: null }],
  DESCENDANTS: [{ collaboratorId: ALVO, positionId: null }],
};
/** Mesma gestão, mas com outro subordinado (alvo FORA do alcance). */
const ALVOS_GESTAO_FORA = {
  DIRECT_REPORTS: [{ collaboratorId: FORA, positionId: null }],
  DESCENDANTS: [{ collaboratorId: FORA, positionId: null }],
};

const DECLARA_TUDO_PERMITIDO: DomainStateProbe = { allows: () => true };
const DECLARA_TUDO_NEGADO: DomainStateProbe = { allows: () => false };

describe("F5-11 P4 — observação na fronteira soberana (probe da linha)", () => {
  it("(a) ALLOW: leitura SELF-comunicada do PRÓPRIO colaborador-alvo (D7/D9)", async () => {
    const { decisao } = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_ALVO,
      vinculo: ALVO,
      comunicado: true,
      excluida: false,
    });

    expect(decisao.allowed).toBe(true);
  });

  it("(b) DENY: SELF NÃO lê observação não comunicada nem excluída (D7/D9)", async () => {
    const base: Cenario = {
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_ALVO,
      vinculo: ALVO,
      comunicado: false,
    };

    const naoComunicada = await decidir({ ...base, comunicado: false });
    expect(naoComunicada.decisao.allowed).toBe(false);
    expect(naoComunicada.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");

    const excluida = await decidir({ ...base, comunicado: true, excluida: true });
    expect(excluida.decisao.allowed).toBe(false);
    expect(excluida.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });

  it("(c) ALLOW: gestão lê a observação NÃO comunicada do alvo pela relação (DIRECT_REPORTS/DESCENDANTS)", async () => {
    for (const scope of ["DIRECT_REPORTS", "DESCENDANTS"]) {
      const { decisao } = await decidir({
        capability: "observation.read",
        capabilitiesAtor: ["observation.read"],
        scopes: [scope],
        alvos: ALVOS_GESTAO_ALVO,
        vinculo: AUTOR,
        comunicado: false,
        excluida: false,
      });

      expect(decisao.allowed, scope).toBe(true);
    }
  });

  it("(d) DENY: alvo FORA do escopo do ator (relação sem alcance)", async () => {
    const { decisao } = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["DIRECT_REPORTS", "DESCENDANTS"],
      alvos: ALVOS_GESTAO_FORA,
      vinculo: FORA,
      comunicado: true,
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");

    // SELF de um terceiro também não alcança a observação do alvo.
    const selfTerceiro = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_FORA,
      vinculo: FORA,
      comunicado: true,
    });
    expect(selfTerceiro.decisao.allowed).toBe(false);
    expect(selfTerceiro.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("(e) DENY: sem `donoDoAlvo` (colaborador-alvo ausente) NENHUMA relação casa (fail-closed)", async () => {
    const { decisao } = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["SELF", "DIRECT_REPORTS", "DESCENDANTS"],
      alvos: { ...ALVOS_SELF_ALVO, ...ALVOS_GESTAO_ALVO },
      vinculo: ALVO,
      comunicado: true,
      recurso: {
        kind: "observation",
        id: OBSERVACAO,
        organizationId: ORG,
        cycleId: CICLO,
        comunicado: true,
        cicloStatus: "ATIVO",
        authorCollaboratorId: AUTOR,
        colaboradorStatus: "ATIVO",
      },
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("(f) DENY: ORGANIZATION não é relação de observação; o MESMO escopo segue valendo para ciclo", async () => {
    const organizacaoObservacao = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["ORGANIZATION"],
      vinculo: FORA,
      comunicado: true,
    });
    expect(organizacaoObservacao.decisao.allowed).toBe(false);
    expect(organizacaoObservacao.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");

    // O caminho ORGANIZATION permanece INALTERADO para os demais alvos soberanos.
    const organizacaoCiclo = await decidir({
      capability: "cycle.read",
      capabilitiesAtor: ["cycle.read"],
      scopes: ["ORGANIZATION"],
      vinculo: FORA,
      alvo: { type: "cycle", id: CICLO },
      recurso: {
        kind: "cycle",
        id: CICLO,
        organizationId: ORG,
        status: "ATIVO",
      },
    });
    expect(organizacaoCiclo.decisao.allowed).toBe(true);
  });

  it("(g) AUTORIA D5: só o autor soberano edita/exclui, e só com ciclo ATIVO", async () => {
    const autorComRelacao: Cenario = {
      capabilitiesAtor: ["observation.edit", "observation.delete"],
      escoposPorCapability: {
        "observation.edit": ["DIRECT_REPORTS"],
        "observation.delete": ["DIRECT_REPORTS"],
      },
      alvos: ALVOS_GESTAO_ALVO,
      vinculo: AUTOR,
      authorCollaboratorId: AUTOR,
      cicloStatus: "ATIVO",
    };

    for (const capability of ["observation.edit", "observation.delete"] as Capability[]) {
      const permitido = await decidir({ ...autorComRelacao, capability });
      expect(permitido.decisao.allowed, capability).toBe(true);
    }

    // Outro ator do MESMO tenant, com a MESMA relação, NÃO é o autor ⇒ DENY (D5).
    for (const capability of ["observation.edit", "observation.delete"] as Capability[]) {
      const negado = await decidir({
        ...autorComRelacao,
        capability,
        vinculo: FORA,
        alvos: { DIRECT_REPORTS: [{ collaboratorId: ALVO, positionId: null }] },
      });
      expect(negado.decisao.allowed, capability).toBe(false);
      expect(negado.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    }

    // Autor SEM autoria provada na linha (coluna nula) ⇒ DENY (fail-closed).
    const semAutoria = await decidir({
      ...autorComRelacao,
      capability: "observation.edit",
      authorCollaboratorId: null,
    });
    expect(semAutoria.decisao.allowed).toBe(false);
    expect(semAutoria.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");

    // Autor sem vínculo de colaborador ⇒ autoria não derivável ⇒ DENY.
    const semVinculo = await decidir({
      ...autorComRelacao,
      capability: "observation.edit",
      vinculo: null,
    });
    expect(semVinculo.decisao.allowed).toBe(false);
    expect(semVinculo.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");

    // Ciclo fora de `ATIVO` ⇒ mutação negada mesmo para o autor (D12).
    for (const cicloStatus of ["PLANEJADO", "ENCERRADO", "CANCELADO", ""]) {
      const encerrado = await decidir({
        ...autorComRelacao,
        capability: "observation.edit",
        cicloStatus,
      });
      expect(encerrado.decisao.allowed, cicloStatus).toBe(false);
      expect(encerrado.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    }
  });

  it("(h) D11/D12: a criação exige ciclo ATIVO e colaborador-alvo NÃO desligado", async () => {
    const base: Cenario = {
      capability: "observation.create",
      capabilitiesAtor: ["observation.create"],
      scopes: ["DIRECT_REPORTS"],
      alvos: ALVOS_GESTAO_ALVO,
      vinculo: AUTOR,
      cicloStatus: "ATIVO",
      colaboradorStatus: "ATIVO",
    };

    const permitida = await decidir(base);
    expect(permitida.decisao.allowed).toBe(true);

    // `LICENCA` também permite criar (D11/§7.9).
    const licenca = await decidir({ ...base, colaboradorStatus: "LICENCA" });
    expect(licenca.decisao.allowed).toBe(true);

    // A matriz de FONTE ÚNICA (P3) nega a criação para `DESLIGADO`. O status
    // NÃO resolvido (`""`/desconhecido) só é distinguível no contexto SOBERANO
    // da criação sobre o colaborador-alvo — coberto no bloco da §8 linha 4.
    const desligado = await decidir({ ...base, colaboradorStatus: "DESLIGADO" });
    expect(desligado.decisao.allowed).toBe(false);
    expect(desligado.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");

    for (const cicloStatus of ["PLANEJADO", "ENCERRADO", "CANCELADO", ""]) {
      const negada = await decidir({ ...base, cicloStatus });
      expect(negada.decisao.allowed, cicloStatus).toBe(false);
      expect(negada.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    }
  });

  it("(i) o `domainState` DECLARADO pelo chamador é IGNORADO (a linha soberana manda)", async () => {
    const base: Cenario = {
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_ALVO,
      vinculo: ALVO,
    };

    // Probe declarado que PERMITE tudo não libera observação não comunicada.
    const naoComunicada = await decidir({
      ...base,
      comunicado: false,
      domainStateDeclarado: DECLARA_TUDO_PERMITIDO,
    });
    expect(naoComunicada.decisao.allowed).toBe(false);
    expect(naoComunicada.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");

    // Probe declarado que NEGA tudo não bloqueia a leitura legítima.
    const comunicada = await decidir({
      ...base,
      comunicado: true,
      domainStateDeclarado: DECLARA_TUDO_NEGADO,
    });
    expect(comunicada.decisao.allowed).toBe(true);
  });

  it("(j) DENY: cross-tenant e observação inexistente (sem oráculo de existência)", async () => {
    const outroTenant = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_ALVO,
      vinculo: ALVO,
      comunicado: true,
      recurso: {
        ...recursoObservacao({ comunicado: true }),
        organizationId: ORG_B,
      },
    });
    expect(outroTenant.decisao.allowed).toBe(false);
    expect(outroTenant.decisao.denial?.reason).toBe("CROSS_TENANT");
    expect(outroTenant.decisao.denial?.publicCode).toBe("NOT_FOUND");

    const inexistente = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_ALVO,
      vinculo: ALVO,
      comunicado: true,
      recurso: null,
    });
    expect(inexistente.decisao.allowed).toBe(false);
    expect(inexistente.decisao.denial?.reason).toBe("TARGET_INVALID");
    expect(inexistente.decisao.denial?.publicCode).toBe("NOT_FOUND");
  });
});

describe("F5-11 P5 — AUTORIA como relação no provider (§8 linha 3; D5)", () => {
  it("(a) ALLOW: o AUTOR lê a própria observação mesmo com o alvo FORA do escopo na data", async () => {
    const { decisao } = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["DIRECT_REPORTS", "DESCENDANTS"],
      alvos: ALVOS_GESTAO_FORA,
      vinculo: AUTOR,
      authorCollaboratorId: AUTOR,
      comunicado: false,
    });

    // O cenário é IDÊNTICO ao caso (d) do bloco P4 (`SCOPE_INSUFFICIENT`); a única
    // diferença é o autor soberano da LINHA chegar ao provider (`observacaoDoAlvo`).
    expect(decisao.allowed).toBe(true);
  });

  it("(b) DENY: NÃO-autor fora do escopo continua sem alcance (fail-closed)", async () => {
    const { decisao } = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["DIRECT_REPORTS", "DESCENDANTS"],
      alvos: ALVOS_GESTAO_FORA,
      vinculo: FORA,
      authorCollaboratorId: AUTOR,
      comunicado: true,
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("(c) DENY: autor AUSENTE na LINHA ou ator SEM vínculo não provam autoria", async () => {
    const semAutor = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["DIRECT_REPORTS"],
      alvos: ALVOS_GESTAO_FORA,
      vinculo: AUTOR,
      authorCollaboratorId: null,
      comunicado: true,
    });
    expect(semAutor.decisao.allowed).toBe(false);
    expect(semAutor.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");

    const semVinculo = await decidir({
      capability: "observation.read",
      capabilitiesAtor: ["observation.read"],
      scopes: ["DIRECT_REPORTS"],
      alvos: ALVOS_GESTAO_FORA,
      vinculo: null,
      authorCollaboratorId: AUTOR,
      comunicado: true,
    });
    expect(semVinculo.decisao.allowed).toBe(false);
    expect(semVinculo.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("(d) NÃO vaza para a CRIAÇÃO (§8 linha 4): autoria na LINHA não dispensa a relação de gestão", async () => {
    const base = {
      capability: "observation.create" as Capability,
      capabilitiesAtor: ["observation.create" as Capability],
      scopes: ["DIRECT_REPORTS"],
      alvos: { DIRECT_REPORTS: [{ collaboratorId: ALVO, positionId: null }] },
      contextoAvaliacao: { colaboradorStatus: "active", cicloStatus: "ATIVO" },
    };

    // Ator é o AUTOR da LINHA e o próprio colaborador-alvo do pedido ⇒ SELF=DENY.
    const self = await decidir({
      ...base,
      alvo: { type: "collaborator", id: AUTOR },
      vinculo: AUTOR,
      authorCollaboratorId: AUTOR,
    });
    expect(self.decisao.allowed).toBe(false);

    // Mesmo ator, alvo DENTRO do escopo de gestão ⇒ ALLOW (relação normal).
    const gestao = await decidir({
      ...base,
      alvo: { type: "collaborator", id: ALVO },
      vinculo: AUTOR,
      authorCollaboratorId: AUTOR,
    });
    expect(gestao.decisao.allowed).toBe(true);
  });
});

describe("F5-11 P5 — vocabulário SOBERANO de status no alvo `observation` (D11)", () => {
  /** Mesma operação/relação: varia SÓ o vocabulário do status do colaborador-alvo. */
  async function criarSobreObservacao(colaboradorStatus?: string) {
    return decidir({
      capability: "observation.create",
      capabilitiesAtor: ["observation.create"],
      scopes: ["DIRECT_REPORTS"],
      alvos: ALVOS_GESTAO_ALVO,
      vinculo: FORA,
      comunicado: true,
      ...(colaboradorStatus === undefined ? {} : { colaboradorStatus }),
    });
  }

  it("`inactive` (vocabulário do banco) é reconhecido como `DESLIGADO`", async () => {
    const banco = await criarSobreObservacao("inactive");
    const probe = await criarSobreObservacao("DESLIGADO");

    expect(banco.decisao.allowed).toBe(false);
    expect(banco.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    // Paridade EXATA entre o vocabulário entregue pelo loader e o do probe.
    expect(banco.decisao.allowed).toBe(probe.decisao.allowed);
    expect(banco.decisao.denial?.reason).toBe(probe.decisao.denial?.reason);
  });

  it("`active`/`leave` não mudaram de comportamento (paridade com `ATIVO`/`LICENCA`)", async () => {
    const ativo = await criarSobreObservacao("active");
    const ativoProbe = await criarSobreObservacao("ATIVO");
    expect(ativo.decisao.allowed).toBe(true);
    expect(ativoProbe.decisao.allowed).toBe(true);

    const licenca = await criarSobreObservacao("leave");
    const licencaProbe = await criarSobreObservacao("LICENCA");
    expect(licenca.decisao.allowed).toBe(true);
    expect(licencaProbe.decisao.allowed).toBe(true);
  });

  it("valor ausente/desconhecido NÃO é confundido com `DESLIGADO`", async () => {
    const ausente = await criarSobreObservacao(undefined);
    const desconhecido = await criarSobreObservacao("em_transferencia");

    // No alvo `observation` a matriz distingue APENAS o colaborador `DESLIGADO`
    // (e o ciclo não `ATIVO`); status não resolvido segue a regra do ciclo. O
    // fail-closed para status NÃO resolvido (D11/invariante 6) vive no ramo de
    // CRIAÇÃO sobre o COLABORADOR-ALVO — coberto pelo caso (e) do bloco P4.
    expect(ausente.decisao.allowed).toBe(true);
    expect(desconhecido.decisao.allowed).toBe(true);
  });
});

describe("F5-11 P4 — probe de domínio da observação (fonte única)", () => {
  it("matriz capability × estado, com fail-closed para dado soberano ausente", () => {
    const ativo = estadoDominioObservacao({
      cicloStatus: "ATIVO",
      colaboradorStatus: "ATIVO",
    });
    expect(ativo.allows("observation.create")).toBe(true);
    expect(ativo.allows("observation.edit")).toBe(true);
    expect(ativo.allows("observation.delete")).toBe(true);
    expect(ativo.allows("observation.read")).toBe(true);
    expect(ativo.allows("cycle.manage")).toBe(false);

    // D11: `LICENCA` permite criar; `DESLIGADO` nega a criação mas NÃO a edição,
    // a exclusão nem a leitura.
    const licenca = estadoDominioObservacao({
      cicloStatus: "ATIVO",
      colaboradorStatus: "LICENCA",
    });
    expect(licenca.allows("observation.create")).toBe(true);

    const desligado = estadoDominioObservacao({
      cicloStatus: "ATIVO",
      colaboradorStatus: "DESLIGADO",
    });
    expect(desligado.allows("observation.create")).toBe(false);
    expect(desligado.allows("observation.edit")).toBe(true);
    expect(desligado.allows("observation.delete")).toBe(true);
    expect(desligado.allows("observation.read")).toBe(true);

    // D12: leitura histórica permanece; mutação exige ciclo `ATIVO`.
    for (const cicloStatus of ["PLANEJADO", "ENCERRADO", "CANCELADO", ""]) {
      const estado = estadoDominioObservacao({ cicloStatus, colaboradorStatus: "ATIVO" });
      expect(estado.allows("observation.create"), cicloStatus).toBe(false);
      expect(estado.allows("observation.edit"), cicloStatus).toBe(false);
      expect(estado.allows("observation.delete"), cicloStatus).toBe(false);
      expect(estado.allows("observation.read"), cicloStatus).toBe(true);
    }

    // Dado soberano AUSENTE ⇒ nada além do que a regra do domínio autoriza.
    const vazio = estadoDominioObservacao({});
    expect(vazio.allows("observation.create")).toBe(false);
    expect(vazio.allows("observation.edit")).toBe(false);
    expect(vazio.allows("observation.delete")).toBe(false);
    expect(vazio.allows("observation.read")).toBe(true);
  });

  it("a AUTORIA D5 é declarada pelo predicado compartilhado (edit/delete)", () => {
    expect(exigeAutoriaObservacao("observation.edit")).toBe(true);
    expect(exigeAutoriaObservacao("observation.delete")).toBe(true);
    expect(exigeAutoriaObservacao("observation.read")).toBe(false);
    expect(exigeAutoriaObservacao("observation.create")).toBe(false);
  });

  it("a fonte é ÚNICA: `authorizationPolicy` reexporta a MESMA função", () => {
    // O adaptador funcional (P3) mantém a superfície pública e consome a fonte
    // única extraída na P4 — nenhuma cópia da matriz.
    expect(estadoDoAdaptador).toBe(estadoDominioObservacao);
  });
});

describe("F5-11 P4 — criação de observação sobre o COLABORADOR-ALVO (§8 linha 4)", () => {
  /** Recurso soberano do colaborador-alvo (a observação ainda NÃO existe). */
  const RECURSO_COLABORADOR: RecursoSoberanoCarregado = {
    kind: "collaborator",
    id: ALVO,
    organizationId: ORG,
  };

  /** Cenário da CRIAÇÃO: alvo funcional = colaborador-alvo (nunca SELF). */
  function criacao(extra: Cenario = {}): Cenario {
    return {
      capability: "observation.create",
      capabilitiesAtor: ["observation.create"],
      scopes: ["DIRECT_REPORTS"],
      alvos: { DIRECT_REPORTS: [{ collaboratorId: ALVO, positionId: null }] },
      vinculo: AUTOR,
      alvo: { type: "collaborator", id: ALVO },
      recurso: RECURSO_COLABORADOR,
      ...extra,
    };
  }

  it("(a) ALLOW: status vigente `active` + ciclo `ATIVO` (criação funcional sobre o alvo)", async () => {
    const { decisao } = await decidir(
      criacao({ contextoAvaliacao: { colaboradorStatus: "active", cicloStatus: "ATIVO" } })
    );

    expect(decisao.allowed).toBe(true);
  });

  it("(b) ALLOW: `leave` também permite criar (D11/§7.9)", async () => {
    const { decisao } = await decidir(
      criacao({ contextoAvaliacao: { colaboradorStatus: "leave", cicloStatus: "ATIVO" } })
    );

    expect(decisao.allowed).toBe(true);
  });

  it("(c) DENY: colaborador `inactive` NÃO recebe observação nova (D11)", async () => {
    const { decisao } = await decidir(
      criacao({ contextoAvaliacao: { colaboradorStatus: "inactive", cicloStatus: "ATIVO" } })
    );

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });

  it("(d) DENY: ciclo fora de `ATIVO` (D12)", async () => {
    for (const cicloStatus of ["PLANEJADO", "ENCERRADO", "CANCELADO"]) {
      const { decisao } = await decidir(
        criacao({ contextoAvaliacao: { colaboradorStatus: "active", cicloStatus } })
      );
      expect(decisao.allowed, cicloStatus).toBe(false);
      expect(decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    }
  });

  it("(e) DENY: dado soberano AUSENTE/desconhecido ⇒ fail-closed (invariante 6)", async () => {
    const casos: readonly Cenario[] = [
      // Campos novos ausentes (resolvedor retrocompatível: só `status`).
      criacao({ contextoAvaliacao: {} }),
      // Contexto ausente por completo.
      criacao({ contextoAvaliacao: null }),
      // Status do colaborador ausente/desconhecido com ciclo `ATIVO`.
      criacao({ contextoAvaliacao: { cicloStatus: "ATIVO" } }),
      criacao({
        contextoAvaliacao: { colaboradorStatus: "ferias", cicloStatus: "ATIVO" },
      }),
      // Ciclo ausente com colaborador resolvido.
      criacao({ contextoAvaliacao: { colaboradorStatus: "active" } }),
    ];

    for (const cenario of casos) {
      const { decisao } = await decidir(cenario);
      expect(decisao.allowed, JSON.stringify(cenario.contextoAvaliacao)).toBe(false);
      expect(decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    }
  });

  it("(f) DENY: SELF NÃO cria observação sobre si (invariante 4)", async () => {
    const { decisao } = await decidir(
      criacao({
        vinculo: ALVO,
        contextoAvaliacao: { colaboradorStatus: "active", cicloStatus: "ATIVO" },
      })
    );

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });

  it("(g) o `domainState` DECLARADO pelo chamador é IGNORADO também na criação", async () => {
    const permitido = await decidir(
      criacao({
        contextoAvaliacao: { colaboradorStatus: "active", cicloStatus: "ATIVO" },
        domainStateDeclarado: DECLARA_TUDO_NEGADO,
      })
    );
    expect(permitido.decisao.allowed).toBe(true);

    const negado = await decidir(
      criacao({
        contextoAvaliacao: null,
        domainStateDeclarado: DECLARA_TUDO_PERMITIDO,
      })
    );
    expect(negado.decisao.allowed).toBe(false);
    expect(negado.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });

  it("(h) os demais domínios NÃO mudaram: `evaluation.create` e `goal.read` intactos", async () => {
    // `evaluation.create` sobre o colaborador segue o probe de CRIAÇÃO da
    // avaliação (não o da observação).
    const avaliacaoPermitida = await decidir(
      criacao({
        capability: "evaluation.create",
        capabilitiesAtor: ["evaluation.create"],
        contextoAvaliacao: { cicloPermiteNovaAvaliacao: true, avaliadoApto: true },
      })
    );
    expect(avaliacaoPermitida.decisao.allowed).toBe(true);

    const avaliacaoNegada = await decidir(
      criacao({
        capability: "evaluation.create",
        capabilitiesAtor: ["evaluation.create"],
        contextoAvaliacao: { cicloPermiteNovaAvaliacao: false, avaliadoApto: true },
      })
    );
    expect(avaliacaoNegada.decisao.allowed).toBe(false);
    expect(avaliacaoNegada.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");

    // `goal.read` continua decidido pela LINHA da meta (probe próprio), mesmo
    // com o contexto soberano do colaborador presente.
    const meta = await decidir({
      capability: "goal.read",
      capabilitiesAtor: ["goal.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_ALVO,
      vinculo: ALVO,
      alvo: { type: "goal", id: OBSERVACAO },
      recurso: {
        kind: "goal",
        id: OBSERVACAO,
        organizationId: ORG,
        ownerCollaboratorId: ALVO,
        cycleId: CICLO,
        status: "EM_ANDAMENTO",
        cicloStatus: "ATIVO",
      },
      contextoAvaliacao: { colaboradorStatus: "inactive", cicloStatus: "ENCERRADO" },
    });
    expect(meta.decisao.allowed).toBe(true);
  });
});
