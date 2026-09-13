import { describe, expect, it } from "vitest";
import type { AuthIdentity } from "../auth/tipos.ts";
import type { Capability } from "./Capability.ts";
import {
  avaliarOperacaoAutorizacao,
  type DepsContextoAutorizacao,
} from "./contextoAutorizacao.ts";
import {
  estadoDominioMeta,
  metaEditavel,
  statusMetaConhecido,
} from "./estadoDominioMeta.ts";
import type { DomainStateProbe, TargetRef } from "./policyEngine/types.ts";
import type {
  AprovadoresCongeladosMeta,
  RecursoSoberanoCarregado,
} from "./resourceContextReal.ts";

/**
 * F5-10 P4 (§9.1/§10, D6–D9, D14/D25) — META na FRONTEIRA SOBERANA.
 *
 * Prova, pelo CAMINHO DE PRODUÇÃO (`avaliarOperacaoAutorizacao` →
 * `criarProvidersReais` → Policy Engine REAL, sem `localWorld`/`mundoFuncional`)
 * e com dependências soberanas sintéticas, que a autorização de meta:
 *   - usa o TARGET REAL (`{type:"goal", id: UUID}` de `evaluation_goals.id`);
 *   - deriva o `domainState` da LINHA SOBERANA (`status`, `excluida` e o status
 *     do ciclo da meta), nunca de estado declarado pelo chamador;
 *   - resolve a ESCRITA por SELF do DONO (`evaluation_goals.collaborator_id`);
 *   - resolve `goal.approve` SOMENTE pelos aprovadores CONGELADOS da avaliação
 *     ORIGINAL do dono — estrutura viva divergente NUNCA aprova;
 *   - nega `ASSIGNED`, `ORGANIZATION` e os demais escopos para meta
 *     (fail-closed), e `goal.approve` NÃO implica `goal.write`;
 *   - nega cross-tenant, meta inexistente e meta excluída fora da leitura.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const AUTH = "33333333-3333-4333-8333-333333333333";
const CICLO = "55555555-5555-4555-8555-555555555555";
const META = "66666666-6666-4666-8666-666666666666";
const DONO = "77777777-7777-4777-8777-777777777777";
/** GERENTE congelado (`GESTAO_CADEIA` da avaliação original do dono). */
const GERENTE = "88888888-8888-4888-8888-888888888888";
/** COORDENADOR congelado (`GESTAO_DIRETA` original, distinta da cadeia). */
const COORDENADOR = "99999999-9999-4999-8999-999999999999";
/** Gestor APENAS na estrutura VIVA (não é o participante congelado). */
const GESTOR_VIVO = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const COLEGA = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
/** Overlay POSTERIOR de gestão (sucessão/substituição após a ativação). */
const GERENTE_OVERLAY = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

interface Cenario {
  /** Capability da OPERAÇÃO avaliada. */
  readonly capability?: Capability;
  /** Capabilities efetivas do ator (resolver da F5-04) — revogada = ausente. */
  readonly capabilitiesAtor?: readonly Capability[];
  readonly scopes?: readonly string[];
  readonly escoposPorCapability?: Readonly<Record<string, readonly string[]>>;
  /** Status SOBERANO da linha `evaluation_goals`. */
  readonly status?: string;
  readonly excluida?: boolean;
  /** Status SOBERANO da linha do CICLO da meta. */
  readonly cicloStatus?: string;
  readonly recurso?: RecursoSoberanoCarregado | null;
  /** Alvos pré-resolvidos por scope (F4-02/F3) — a "estrutura VIVA". */
  readonly alvos?: Readonly<
    Record<string, readonly { collaboratorId: string | null; positionId: string | null }[]>
  >;
  readonly vinculo?: string | null;
  /** Organização pretendida (intenção) — revalidada contra membership. */
  readonly organizationId?: string;
  /** Estado DECLARADO pelo chamador (o browser nunca declara estado soberano). */
  readonly domainStateDeclarado?: DomainStateProbe;
  /** Resultado do resolvedor SOBERANO de aprovadores congelados. */
  readonly aprovadoresCongelados?: AprovadoresCongeladosMeta | null;
}

/** Entrada recebida pelo resolvedor soberano (prova da rota/argumentos). */
interface EntradaAprovadorCongelado {
  readonly authUserId: string;
  readonly collaboratorId: string | null;
  readonly organizationId: string;
  readonly target: TargetRef;
  readonly cycleId?: string;
}

function identidade(): AuthIdentity {
  return {
    authUserId: AUTH,
    perfil: { id: AUTH, status: "active" },
    memberships: [{ id: "m-1", organizationId: ORG, status: "active" }],
    organizacoes: [{ id: ORG, name: "Org sintetica" }],
  } as unknown as AuthIdentity;
}

/**
 * Fronteira REAL: `avaliarOperacaoAutorizacao` (F5-05) com dependências
 * soberanas sintéticas — identidade, vínculo, capabilities × scopes, alvos por
 * scope (estrutura VIVA), recurso carregado e resolvedor de aprovador
 * CONGELADO.
 */
function fronteira(
  cenario: Cenario,
  registro: EntradaAprovadorCongelado[]
): DepsContextoAutorizacao {
  const recurso =
    cenario.recurso === undefined
      ? ({
          kind: "goal",
          id: META,
          organizationId: ORG,
          ownerCollaboratorId: DONO,
          cycleId: CICLO,
          status: cenario.status ?? "EM_ANDAMENTO",
          excluida: cenario.excluida ?? false,
          cicloStatus: cenario.cicloStatus ?? "ATIVO",
        } as RecursoSoberanoCarregado)
      : cenario.recurso;

  return {
    agora: () => new Date("2026-05-01T12:00:00Z"),
    resolverIdentidade: async () => identidade(),
    resolverColaboradorVinculado: async () =>
      cenario.vinculo === undefined ? DONO : cenario.vinculo,
    resolverCapabilitiesEscopos: async () =>
      (cenario.capabilitiesAtor ?? [cenario.capability ?? "goal.read"]).map(
        (capability) => ({
          capability,
          scopes: (cenario.escoposPorCapability?.[capability] ??
            cenario.scopes ?? ["SELF"]) as never,
        })
      ),
    resolverAlvosEscopo: async ({ scope }) => cenario.alvos?.[scope] ?? [],
    carregarRecurso: async () => recurso,
    resolverAprovadorCongelado: async (entrada) => {
      registro.push({ ...entrada });
      return cenario.aprovadoresCongelados ?? null;
    },
  };
}

async function decidir(cenario: Cenario = {}) {
  const registro: EntradaAprovadorCongelado[] = [];
  const decisao = await avaliarOperacaoAutorizacao(
    {
      authUserId: AUTH,
      organizationId: cenario.organizationId ?? ORG,
      capability: cenario.capability ?? "goal.read",
      alvo: { type: "goal", id: META },
      ...(cenario.domainStateDeclarado
        ? { domainState: cenario.domainStateDeclarado }
        : {}),
    },
    fronteira(cenario, registro)
  );
  return { decisao, registro };
}

/** Alvos SELF do DONO (vínculo do ator = titular da meta). */
const ALVOS_SELF_DONO = {
  SELF: [{ collaboratorId: DONO, positionId: null }],
};
/** Alvos SELF de um TERCEIRO sem relação com a meta. */
const ALVOS_SELF_TERCEIRO = {
  SELF: [{ collaboratorId: COLEGA, positionId: null }],
};

const DECLARA_TUDO_PERMITIDO: DomainStateProbe = { allows: () => true };

// ---------------------------------------------------------------------------
// Modelo do resolvedor SOBERANO de aprovadores (ocorrência ORIGINAL)
// ---------------------------------------------------------------------------

type PapelCongelado = "GESTAO_CADEIA" | "GESTAO_DIRETA";

interface ParticipanteCongelado {
  readonly roleType: PapelCongelado;
  readonly collaboratorId: string;
  readonly status: "active" | "ended";
  readonly validFrom: Date;
  readonly validTo: Date | null;
}

/**
 * MODELO do resolvedor da fronteira confiável (o resolver REAL lê
 * `evaluation_participants` server-side). Reproduz a regra da ocorrência
 * ORIGINAL de `f5_10_aprovador_congelado`
 * (`supabase/migrations/20260924000000_f5_10_p3_approvals_rpc.sql:273-383`):
 * participante `status='active'` e `valid_to is null`; entre as ocorrências do
 * papel, a de MENOR `valid_from` (empate ⇒ menor `collaborator_id`); o
 * COORDENADOR só é reconhecido se DISTINTO do GERENTE; ausência ⇒ papel não
 * reconhecido (fail-closed).
 */
function aprovadoresDaOcorrenciaOriginal(
  participantes: readonly ParticipanteCongelado[]
): AprovadoresCongeladosMeta {
  // REGRA DO SQL (`f5_10_aprovador_congelado`, P3): escolhe-se a ocorrência
  // ORIGINAL do papel (MENOR `valid_from`; empate ⇒ menor `collaborator_id`)
  // entre TODAS as ocorrências — inclusive encerradas — e SÓ DEPOIS se exige
  // que a escolhida esteja `active` com `valid_to` nulo. Ocorrência original
  // encerrada ⇒ papel NÃO reconhecido (fail-closed), ainda que exista overlay
  // ativo posterior.
  const original = (roleType: PapelCongelado): string | null => {
    const doPapel = participantes
      .filter((p) => p.roleType === roleType)
      .slice()
      .sort(
        (a, b) =>
          a.validFrom.getTime() - b.validFrom.getTime() ||
          (a.collaboratorId < b.collaboratorId
            ? -1
            : a.collaboratorId > b.collaboratorId
              ? 1
              : 0)
      );
    const escolhida = doPapel[0];
    if (!escolhida || escolhida.status !== "active" || escolhida.validTo !== null) {
      return null;
    }
    return escolhida.collaboratorId;
  };

  const gerente = original("GESTAO_CADEIA");
  const coordenador = original("GESTAO_DIRETA");
  return {
    ...(gerente ? { gerente } : {}),
    ...(coordenador && coordenador !== gerente ? { coordenador } : {}),
  };
}

describe("F5-10 P4 — meta na fronteira soberana (dono, ciclo e estado da linha)", () => {
  it("(a) ALLOW real: DONO com goal.write/goal.read por SELF cria/edita/progride/finaliza/lê", async () => {
    // Criar/editar/progredir/finalizar/revisar/excluir = `goal.write`; leitura =
    // `goal.read` — ambos por SELF do titular (D7/D9).
    for (const capability of ["goal.write", "goal.read"] as Capability[]) {
      const { decisao } = await decidir({
        capability,
        capabilitiesAtor: [capability],
        scopes: ["SELF"],
        alvos: ALVOS_SELF_DONO,
        vinculo: DONO,
      });
      expect(decisao.allowed, capability).toBe(true);
    }

    // Revisão de fechamento: `ATINGIDA`/`NAO_ATINGIDA` seguem admitindo escrita.
    for (const status of ["ATINGIDA", "NAO_ATINGIDA"]) {
      const { decisao } = await decidir({
        capability: "goal.write",
        capabilitiesAtor: ["goal.write"],
        scopes: ["SELF"],
        alvos: ALVOS_SELF_DONO,
        vinculo: DONO,
        status,
      });
      expect(decisao.allowed, status).toBe(true);
    }
  });

  it("(b) DENY: capability sem relação — tem goal.write mas NÃO é o dono", async () => {
    const { decisao } = await decidir({
      capability: "goal.write",
      capabilitiesAtor: ["goal.write"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_TERCEIRO,
      vinculo: COLEGA,
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("(c) DENY: relação sem capability — é o dono mas não tem goal.write", async () => {
    const { decisao } = await decidir({
      capability: "goal.write",
      capabilitiesAtor: ["goal.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_DONO,
      vinculo: DONO,
    });

    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("(d) ALLOW: GERENTE e COORDENADOR CONGELADOS aprovam; gestor só VIVO não", async () => {
    const gerente = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DESCENDANTS"],
      vinculo: GERENTE,
      aprovadoresCongelados: { gerente: GERENTE },
    });
    expect(gerente.decisao.allowed).toBe(true);

    const coordenador = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DIRECT_REPORTS"],
      vinculo: COORDENADOR,
      aprovadoresCongelados: { gerente: GERENTE, coordenador: COORDENADOR },
    });
    expect(coordenador.decisao.allowed).toBe(true);

    // Gestor apenas na ESTRUTURA VIVA (divergente do congelado) ⇒ DENY: a
    // hierarquia viva não é fonte de legitimidade de meta (D14/D25).
    const vivo = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DESCENDANTS"],
      vinculo: GESTOR_VIVO,
      alvos: { DESCENDANTS: [{ collaboratorId: DONO, positionId: null }] },
      aprovadoresCongelados: { gerente: GERENTE },
    });
    expect(vivo.decisao.allowed).toBe(false);
    expect(vivo.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
    // O resolvedor recebe a ROTA soberana: ator, vínculo, tenant, alvo REAL e o
    // ciclo da linha da meta.
    expect(vivo.registro).toEqual([
      {
        authUserId: AUTH,
        collaboratorId: GESTOR_VIVO,
        organizationId: ORG,
        target: { type: "goal", id: META },
        cycleId: CICLO,
      },
    ]);

    // Sem avaliação/participante ⇒ papel não reconhecido (fail-closed).
    const semCongelado = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DESCENDANTS"],
      vinculo: GERENTE,
      aprovadoresCongelados: null,
    });
    expect(semCongelado.decisao.allowed).toBe(false);
    expect(semCongelado.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");

    // `GESTAO_DIRETA` coincidente com a cadeia NÃO é reconhecida: o resolvedor
    // não devolve COORDENADOR ⇒ DIRECT_REPORTS nega (fail-closed).
    const coordenadorCoincidente = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DIRECT_REPORTS"],
      vinculo: GERENTE,
      aprovadoresCongelados: { gerente: GERENTE },
    });
    expect(coordenadorCoincidente.decisao.allowed).toBe(false);
    expect(coordenadorCoincidente.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");

    // ASSIGNED nunca aprova meta (preserva f4-10-integrated.test.ts:204-211).
    const assigned = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["ASSIGNED"],
      vinculo: COLEGA,
    });
    expect(assigned.decisao.allowed).toBe(false);
    expect(assigned.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("(e) DENY: goal.approve NÃO autoriza escrita (goal.write) sobre a mesma meta", async () => {
    // O gerente congelado tem `goal.approve` por DESCENDANTS (relação congelada)
    // e `goal.write` apenas por SELF — a escrita é do DONO (D7/D9).
    const aprovador: Cenario = {
      capabilitiesAtor: ["goal.approve", "goal.write"],
      escoposPorCapability: {
        "goal.approve": ["DESCENDANTS"],
        "goal.write": ["SELF"],
      },
      // SELF do gerente: ele NÃO é o titular da meta.
      alvos: { SELF: [{ collaboratorId: GERENTE, positionId: null }] },
      vinculo: GERENTE,
      aprovadoresCongelados: { gerente: GERENTE },
    };

    const aprovacao = await decidir({ ...aprovador, capability: "goal.approve" });
    expect(aprovacao.decisao.allowed).toBe(true);

    // Mesmo ator, mesma meta: aprovar não concede editar/progredir/finalizar —
    // a escrita é SELF do dono (D9).
    const escrita = await decidir({ ...aprovador, capability: "goal.write" });
    expect(escrita.decisao.allowed).toBe(false);
    expect(escrita.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("(f) DENY: domainState declarado pelo cliente é IGNORADO (a linha soberana manda)", async () => {
    const base: Cenario = {
      capabilitiesAtor: ["goal.write", "goal.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_DONO,
      vinculo: DONO,
      domainStateDeclarado: DECLARA_TUDO_PERMITIDO,
    };

    // Meta EXCLUÍDA ⇒ somente leitura histórica (§10).
    const escritaExcluida = await decidir({
      ...base,
      capability: "goal.write",
      excluida: true,
    });
    expect(escritaExcluida.decisao.allowed).toBe(false);
    expect(escritaExcluida.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");

    const leituraExcluida = await decidir({
      ...base,
      capability: "goal.read",
      excluida: true,
    });
    expect(leituraExcluida.decisao.allowed).toBe(true);

    // Ciclo fora de `ATIVO` ⇒ nega escrita mesmo com "domínio permite tudo".
    for (const cicloStatus of ["ENCERRADO", "CANCELADO", "PLANEJADO"]) {
      const escrita = await decidir({ ...base, capability: "goal.write", cicloStatus });
      expect(escrita.decisao.allowed, cicloStatus).toBe(false);
      expect(escrita.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    }

    // Ciclo fora de `ATIVO` ⇒ nega também a APROVAÇÃO do gerente congelado.
    const aprovacaoEncerrada = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DESCENDANTS"],
      vinculo: GERENTE,
      aprovadoresCongelados: { gerente: GERENTE },
      cicloStatus: "ENCERRADO",
      domainStateDeclarado: DECLARA_TUDO_PERMITIDO,
    });
    expect(aprovacaoEncerrada.decisao.allowed).toBe(false);
    expect(aprovacaoEncerrada.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");

    // Status ausente/fora do domínio fechado ⇒ nega TUDO (fail-closed).
    for (const status of ["", "ARQUIVADA"]) {
      const leitura = await decidir({
        ...base,
        capability: "goal.read",
        status,
      });
      expect(leitura.decisao.allowed, status).toBe(false);
      expect(leitura.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    }

    // `ATINGIDA` + ciclo fora de `ATIVO`: a revisão de fechamento também é
    // negada pelo estado SOBERANO da linha.
    const revisaoEncerrada = await decidir({
      ...base,
      capability: "goal.write",
      status: "ATINGIDA",
      cicloStatus: "ENCERRADO",
    });
    expect(revisaoEncerrada.decisao.allowed).toBe(false);
    expect(revisaoEncerrada.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");

    // O caminho INVERSO também é ignorado: um probe declarado que NEGA tudo não
    // bloqueia a operação — a autoridade é a linha soberana (nunca o cliente).
    const negaTudo: DomainStateProbe = { allows: () => false };
    const escritaPermitida = await decidir({
      capability: "goal.write",
      capabilitiesAtor: ["goal.write"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_DONO,
      vinculo: DONO,
      domainStateDeclarado: negaTudo,
    });
    expect(escritaPermitida.decisao.allowed).toBe(true);
  });

  it("(g) DENY: cross-tenant, meta inexistente e excluída fora da leitura", async () => {
    const outroTenant = await decidir({
      capability: "goal.read",
      capabilitiesAtor: ["goal.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_DONO,
      vinculo: DONO,
      recurso: {
        kind: "goal",
        id: META,
        organizationId: ORG_B,
        ownerCollaboratorId: DONO,
        cycleId: CICLO,
        status: "EM_ANDAMENTO",
        cicloStatus: "ATIVO",
      },
    });
    expect(outroTenant.decisao.allowed).toBe(false);
    expect(outroTenant.decisao.denial?.reason).toBe("CROSS_TENANT");
    expect(outroTenant.decisao.denial?.publicCode).toBe("NOT_FOUND");

    const inexistente = await decidir({
      capability: "goal.read",
      capabilitiesAtor: ["goal.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_DONO,
      vinculo: DONO,
      recurso: null,
    });
    expect(inexistente.decisao.allowed).toBe(false);
    expect(inexistente.decisao.denial?.reason).toBe("TARGET_INVALID");
    expect(inexistente.decisao.denial?.publicCode).toBe("NOT_FOUND");

    // Organização spoofada no corpo ⇒ membership inválida (tenant sempre
    // validado server-side).
    const spoof = await decidir({
      capability: "goal.read",
      capabilitiesAtor: ["goal.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_DONO,
      vinculo: DONO,
      organizationId: ORG_B,
    });
    expect(spoof.decisao.allowed).toBe(false);
    expect(spoof.decisao.denial?.reason).toBe("MEMBERSHIP_INVALID");

    // Meta excluída não aceita aprovação (aprovações ficam como fato histórico).
    const aprovacaoExcluida = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DESCENDANTS"],
      vinculo: GERENTE,
      aprovadoresCongelados: { gerente: GERENTE },
      excluida: true,
    });
    expect(aprovacaoExcluida.decisao.allowed).toBe(false);
    expect(aprovacaoExcluida.decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });

  it("(h) leitura de terceiro SOMENTE pela relação congelada; sem relação ⇒ DENY", async () => {
    const gerenteLe = await decidir({
      capability: "goal.read",
      capabilitiesAtor: ["goal.read"],
      scopes: ["DESCENDANTS"],
      vinculo: GERENTE,
      aprovadoresCongelados: { gerente: GERENTE },
    });
    expect(gerenteLe.decisao.allowed).toBe(true);

    const coordenadorLe = await decidir({
      capability: "goal.read",
      capabilitiesAtor: ["goal.read"],
      scopes: ["DIRECT_REPORTS"],
      vinculo: COORDENADOR,
      aprovadoresCongelados: { gerente: GERENTE, coordenador: COORDENADOR },
    });
    expect(coordenadorLe.decisao.allowed).toBe(true);

    const colega = await decidir({
      capability: "goal.read",
      capabilitiesAtor: ["goal.read"],
      scopes: ["SELF"],
      alvos: ALVOS_SELF_TERCEIRO,
      vinculo: COLEGA,
    });
    expect(colega.decisao.allowed).toBe(false);
    expect(colega.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");

    // Nem o alcance do tenant (`ORGANIZATION`) é relação de meta (fail-closed).
    const organizacao = await decidir({
      capability: "goal.read",
      capabilitiesAtor: ["goal.read"],
      scopes: ["ORGANIZATION"],
      vinculo: COLEGA,
    });
    expect(organizacao.decisao.allowed).toBe(false);
    expect(organizacao.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("(i) ocorrência ORIGINAL: overlay posterior NÃO transfere a aprovação", async () => {
    const comOverlay: readonly ParticipanteCongelado[] = [
      {
        roleType: "GESTAO_CADEIA",
        collaboratorId: GERENTE,
        status: "active",
        validFrom: new Date("2026-01-01T00:00:00Z"),
        validTo: null,
      },
      {
        roleType: "GESTAO_CADEIA",
        collaboratorId: GERENTE_OVERLAY,
        status: "active",
        validFrom: new Date("2026-04-01T00:00:00Z"),
        validTo: null,
      },
    ];
    const aprovadores = aprovadoresDaOcorrenciaOriginal(comOverlay);
    expect(aprovadores).toEqual({ gerente: GERENTE });

    const original = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DESCENDANTS"],
      vinculo: GERENTE,
      aprovadoresCongelados: aprovadores,
    });
    expect(original.decisao.allowed).toBe(true);

    // O overlay é "gestor" na estrutura VIVA, mas não na materialização
    // congelada ⇒ não aprova a meta do dono.
    const overlay = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DESCENDANTS"],
      vinculo: GERENTE_OVERLAY,
      alvos: { DESCENDANTS: [{ collaboratorId: DONO, positionId: null }] },
      aprovadoresCongelados: aprovadores,
    });
    expect(overlay.decisao.allowed).toBe(false);
    expect(overlay.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");

    // Ocorrência original ENCERRADA (`valid_to` preenchido) ⇒ papel não
    // reconhecido (fail-closed), ainda que exista overlay ativo.
    const comOriginalEncerrada: readonly ParticipanteCongelado[] = [
      {
        roleType: "GESTAO_CADEIA",
        collaboratorId: GERENTE,
        status: "ended",
        validFrom: new Date("2026-01-01T00:00:00Z"),
        validTo: new Date("2026-04-01T00:00:00Z"),
      },
      {
        roleType: "GESTAO_CADEIA",
        collaboratorId: GERENTE_OVERLAY,
        status: "active",
        validFrom: new Date("2026-04-01T00:00:00Z"),
        validTo: null,
      },
    ];
    const semPapel = aprovadoresDaOcorrenciaOriginal(comOriginalEncerrada);
    expect(semPapel).toEqual({});

    const negado = await decidir({
      capability: "goal.approve",
      capabilitiesAtor: ["goal.approve"],
      scopes: ["DESCENDANTS"],
      vinculo: GERENTE_OVERLAY,
      aprovadoresCongelados: semPapel,
    });
    expect(negado.decisao.allowed).toBe(false);
    expect(negado.decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });
});

describe("F5-10 P4 — probe de domínio da meta (fonte única)", () => {
  it("matriz capability × estado e fail-closed para status desconhecido", () => {
    expect(statusMetaConhecido("em_andamento")).toBe("EM_ANDAMENTO");
    expect(statusMetaConhecido(" ATINGIDA ")).toBe("ATINGIDA");
    expect(statusMetaConhecido("ARQUIVADA")).toBeNull();
    expect(statusMetaConhecido(undefined)).toBeNull();

    const emAndamento = estadoDominioMeta({
      status: "EM_ANDAMENTO",
      excluida: false,
      cicloStatus: "ATIVO",
    });
    expect(emAndamento.allows("goal.read")).toBe(true);
    expect(emAndamento.allows("goal.write")).toBe(true);
    expect(emAndamento.allows("goal.approve")).toBe(true);
    expect(emAndamento.allows("cycle.manage")).toBe(false);

    const concluida = estadoDominioMeta({
      status: "ATINGIDA",
      excluida: false,
      cicloStatus: "ATIVO",
    });
    expect(concluida.allows("goal.read")).toBe(true);
    expect(concluida.allows("goal.approve")).toBe(true);
    expect(concluida.allows("goal.write")).toBe(true); // revisão de fechamento

    const excluida = estadoDominioMeta({
      status: "NAO_ATINGIDA",
      excluida: true,
      cicloStatus: "ATIVO",
    });
    expect(excluida.allows("goal.read")).toBe(true);
    expect(excluida.allows("goal.write")).toBe(false);
    expect(excluida.allows("goal.approve")).toBe(false);

    const cicloEncerrado = estadoDominioMeta({
      status: "EM_ANDAMENTO",
      excluida: false,
      cicloStatus: "ENCERRADO",
    });
    expect(cicloEncerrado.allows("goal.write")).toBe(false);
    expect(cicloEncerrado.allows("goal.approve")).toBe(false);
    expect(cicloEncerrado.allows("goal.read")).toBe(true);

    expect(metaEditavel({ status: "", cicloStatus: "ATIVO" })).toBe(false);
    expect(metaEditavel({ status: "EM_ANDAMENTO", cicloStatus: "ATIVO" })).toBe(true);
    expect(metaEditavel({ status: "EM_ANDAMENTO", cicloStatus: "" })).toBe(false);
  });
});
