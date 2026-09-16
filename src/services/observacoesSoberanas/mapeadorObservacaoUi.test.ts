import { describe, expect, it } from "vitest";

import fonteMapeador from "./mapeadorObservacaoUi.ts?raw";
import type {
  EventoHistoricoSoberano,
  ObservacaoSoberana,
} from "../../application/ports/ObservationRepository";
import {
  eventoTimelineDeUi,
  observacaoDeUi,
  textoAnteriorDoEvento,
  timelineDeUi,
  type FonteDeRotulosDeColaborador,
} from "./mapeadorObservacaoUi";

/**
 * F5-11 P5 (Issue #250), L2/L3 — o mapeador é a fronteira de APRESENTAÇÃO:
 * identidade por UUID, rótulos por PARÂMETRO, timeline com tipo NOVO e
 * independente, e `null` (item não apresentado) quando falta o rótulo do alvo.
 * Nenhum valor é inventado: nada de matrícula derivada, `0`, `""` ou
 * "desconhecido".
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "22222222-2222-4222-8222-222222222222";
const OBS = "33333333-3333-4333-8333-333333333333";
const ALVO = "44444444-4444-4444-8444-444444444444";
const AUTOR = "55555555-5555-4555-8555-555555555555";
const PERFIL = "66666666-6666-4666-8666-666666666666";

function soberana(extra: Partial<ObservacaoSoberana> = {}): ObservacaoSoberana {
  return {
    id: OBS,
    organizationId: ORG,
    collaboratorId: ALVO,
    cycleId: CICLO,
    tipo: "POSITIVA",
    texto: "observacao ficticia",
    comunicado: false,
    comunicadoEm: null,
    excluida: false,
    motivoExclusao: null,
    autorUserProfileId: PERFIL,
    autorCollaboratorId: AUTOR,
    version: 3,
    criadoEm: "2026-04-01T10:00:00.000Z",
    atualizadoEm: "2026-04-02T10:00:00.000Z",
    ...extra,
  };
}

function evento(extra: Partial<EventoHistoricoSoberano> = {}): EventoHistoricoSoberano {
  return {
    id: "77777777-7777-4777-8777-777777777777",
    evento: "CRIADA",
    dataEfetiva: "2026-04-01T10:00:00.000Z",
    motivo: "Criacao de observacao",
    beforeValue: null,
    afterValue: { tipo: "POSITIVA", texto: "inicial", version: 0 },
    payloadHash: "a".repeat(64),
    actorUserProfileId: PERFIL,
    actorCollaboratorId: null,
    operationId: "88888888-8888-4888-8888-888888888888",
    criadoEm: "2026-04-01T10:00:00.000Z",
    ...extra,
  };
}

const rotulos: FonteDeRotulosDeColaborador = {
  doColaborador: (collaboratorId) =>
    collaboratorId === ALVO ? { matricula: 10, nome: "Alvo Fictício" } : null,
  doAutor: (collaboratorId) =>
    collaboratorId === AUTOR ? { matricula: 99, nome: "Autora Fictícia" } : null,
};

describe("F5-11 P5 — mapeador soberano de observações", () => {
  it("mantém o UUID como identidade e usa os rótulos por PARÂMETRO", () => {
    const mapeada = observacaoDeUi(soberana(), rotulos);
    if (!mapeada) throw new Error("esperado item apresentável");

    expect(mapeada.id).toBe(OBS);
    expect(mapeada.colaboradorId).toBe(ALVO);
    expect(mapeada.colaboradorMatricula).toBe(10);
    expect(mapeada.colaboradorNome).toBe("Alvo Fictício");
    expect(mapeada.autorCollaboratorId).toBe(AUTOR);
    expect(mapeada.autorMatricula).toBe(99);
    expect(mapeada.dataCriacao).toBe("2026-04-01T10:00:00.000Z");
    expect(mapeada.timeline).toEqual([]);
  });

  it("DISCRIMINANTE: sem rótulo do ALVO a observação NÃO é exibida (null)", () => {
    const semAlvo = observacaoDeUi(soberana(), {
      doColaborador: () => null,
      doAutor: () => ({ matricula: 99, nome: "Autora Fictícia" }),
    });
    expect(semAlvo).toBeNull();
  });

  it("autor ausente na LINHA fica `null` — nunca sentinela (0, '' ou 'desconhecido')", () => {
    const mapeada = observacaoDeUi(
      soberana({ autorCollaboratorId: null }),
      rotulos
    );
    if (!mapeada) throw new Error("esperado item apresentável");
    expect(mapeada.autorCollaboratorId).toBeNull();
    expect(mapeada.autorMatricula).toBeNull();
    expect(mapeada.autorNome).toBeNull();
  });

  it("autor presente na LINHA mas sem rótulo na tela não vira identidade inventada", () => {
    const mapeada = observacaoDeUi(soberana(), {
      doColaborador: rotulos.doColaborador,
      doAutor: () => null,
    });
    if (!mapeada) throw new Error("esperado item apresentável");
    expect(mapeada.autorMatricula).toBeNull();
    expect(mapeada.autorNome).toBeNull();
  });

  it("não deriva `ano`/`ciclo`: o view-model não expõe numeração de ciclo", () => {
    const mapeada = observacaoDeUi(soberana(), rotulos);
    if (!mapeada) throw new Error("esperado item apresentável");
    expect(mapeada).not.toHaveProperty("ano");
    expect(mapeada).not.toHaveProperty("ciclo");
    expect(mapeada).not.toHaveProperty("cycleId");
  });
});

describe("F5-11 P5 — timeline soberana (tipo NOVO e independente)", () => {
  it("mapeia o evento da TRILHA com instante efetivo e rótulo do ATOR por parâmetro", () => {
    const item = eventoTimelineDeUi(evento(), {
      rotuloDoAtor: {
        doAtor: (actorUserProfileId) =>
          actorUserProfileId === PERFIL ? { matricula: 99, nome: "Autora Fictícia" } : null,
      },
    });
    if (!item) throw new Error("esperado item apresentável");

    expect(item.eventId).toBe(evento().id);
    expect(item.evento).toBe("CRIADA");
    expect(item.dataEfetiva).toBe("2026-04-01T10:00:00.000Z");
    expect(item.motivo).toBe("Criacao de observacao");
    expect(item.actorUserProfileId).toBe(PERFIL);
    expect(item.actorMatricula).toBe(99);
    expect(item.actorNome).toBe("Autora Fictícia");
    expect(item.payloadHash).toBe("a".repeat(64));
    expect(item.textoAnterior).toBeNull();
    // O tipo da timeline NÃO é o legado `HistoricoObservacao` (sem `acao`/`data`).
    expect(item).not.toHaveProperty("acao");
    expect(item).not.toHaveProperty("data");
  });

  it("ator sem rótulo na tela fica `null` (nunca 'desconhecido' nem matrícula 0)", () => {
    const item = eventoTimelineDeUi(evento(), {
      rotuloDoAtor: { doAtor: () => null },
    });
    if (!item) throw new Error("esperado item apresentável");
    expect(item.actorMatricula).toBeNull();
    expect(item.actorNome).toBeNull();
  });

  it("preserva o 'Texto anterior' a partir do `before_value` do evento de EDIÇÃO", () => {
    const item = eventoTimelineDeUi(
      evento({
        evento: "EDITADA",
        beforeValue: { tipo: "NEUTRA", texto: "texto anterior ficticio", version: 1 },
        afterValue: { texto: "texto novo ficticio", version: 2 },
      })
    );
    if (!item) throw new Error("esperado item apresentável");
    expect(item.textoAnterior).toBe("texto anterior ficticio");
  });

  it("`before_value` sem texto ⇒ `textoAnterior` null (nunca string vazia)", () => {
    expect(textoAnteriorDoEvento(evento({ beforeValue: { version: 1 } }))).toBeNull();
    expect(textoAnteriorDoEvento(evento({ beforeValue: null }))).toBeNull();
  });

  it("o gancho `getEventoHistorico` tem precedência e pode DESCARTAR o item", () => {
    const descartado = timelineDeUi([evento(), evento({ id: "99999999-9999-4999-8999-999999999999" })], {
      getEventoHistorico: () => null,
    });
    expect(descartado).toEqual([]);

    const preservado = timelineDeUi([evento()], {
      getEventoHistorico: () =>
        eventoTimelineDeUi(evento(), {
          rotuloDoAtor: { doAtor: () => ({ matricula: 1, nome: "Rotulo Externo" }) },
        }),
    });
    expect(preservado).toHaveLength(1);
    expect(preservado[0].actorNome).toBe("Rotulo Externo");
  });

  it("DISCRIMINANTE de fronteira: o FONTE não cria identidade, não lê storage e não fala RPC", () => {
    // Código SEM comentários (bloco e linha — mesma semântica de `apenasCodigo`
    // em `src/authorization/estruturaUiSeguranca.test.ts`); strings NÃO são
    // removidas, então literal proibido em código continua reprovando.
    const apenasCodigo = (fonte: string): string =>
      fonte
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .split("\n")
        .map((linha) => {
          const indice = linha.indexOf("//");
          return indice === -1 ? linha : linha.slice(0, indice);
        })
        .join("\n");
    const codigoMapeador = apenasCodigo(fonteMapeador);
    expect(codigoMapeador).not.toMatch(/localStorage|sessionStorage/);
    expect(codigoMapeador).not.toMatch(/observacaoStorage/);
    expect(codigoMapeador).not.toMatch(/\.rpc\s*\(/);
    expect(codigoMapeador).not.toMatch(/\.from\s*\(/);
    expect(codigoMapeador).not.toMatch(/SERVICE_ROLE_KEY|serviceRoleKey/);
    expect(codigoMapeador).not.toMatch(/randomUUID/);
    // O legado `HistoricoObservacao` não é mais o tipo da timeline.
    expect(codigoMapeador).not.toMatch(/HistoricoObservacao/);
  });
});
