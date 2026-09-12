/**
 * F5-09 P5 — `localCycleRepository` é **LEGACY/transitório**: cumpre a porta
 * assíncrona projetando o storage local, com sentinelas explícitas de legado
 * (`version: 0`, organização = intenção) e fail-closed quando o storage falha.
 *
 * Ele NÃO é o caminho soberano e NÃO é fallback do adapter de RLS (a prova
 * estática está em `src/services/ciclosSoberanosSemFallback.test.ts`).
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { CycleRepository } from "../../application/ports/CycleRepository";
import { instalarLocalStorageEmMemoria } from "../../test/localStorageMock";
import type { CicloAvaliacao } from "../../types/CicloAvaliacao";
import { localCycleRepository } from "./localCycleRepository";

const STORAGE_KEY = "feedback-control-ciclos";
const ORG = "11111111-1111-4111-8111-111111111111";

const repository: CycleRepository = localCycleRepository;

function cicloLegado(extra: Partial<CicloAvaliacao> = {}): CicloAvaliacao {
  return {
    id: "ciclo-legado",
    ano: 2025,
    ciclo: 3,
    status: "ENCERRADO",
    dataCriacao: "2025-09-01T12:00:00.000Z",
    dataUltimaAtualizacao: "2025-12-31T12:00:00.000Z",
    dataEncerramento: "2025-12-31T12:00:00.000Z",
    quantidadePendencias: 2,
    encerradoComPendencias: true,
    ...extra,
  };
}

function persistir(...ciclos: CicloAvaliacao[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(ciclos));
}

describe("F5-09 P5 — CycleRepository local (LEGACY, porta assíncrona)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(STORAGE_KEY, "[]");
  });

  afterEach(() => vi.restoreAllMocks());

  it("projeta o ciclo local com identidade UUID e sentinelas explícitas de LEGADO", async () => {
    persistir(cicloLegado());

    const resultado = await repository.listarCiclos(ORG);

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data).toHaveLength(1);
    expect(resultado.data[0]).toEqual({
      id: "ciclo-legado",
      organizationId: ORG,
      ano: 2025,
      numero: 3,
      status: "ENCERRADO",
      dataInicio: null,
      dataFim: null,
      dataAtivacao: null,
      dataEncerramento: "2025-12-31T12:00:00.000Z",
      encerradoComPendencias: true,
      quantidadePendencias: 2,
      // Sentinela de LEGADO: o storage local não possui versão otimista.
      version: 0,
      criadoEm: "2025-09-01T12:00:00.000Z",
      atualizadoEm: "2025-12-31T12:00:00.000Z",
    });
  });

  it("descarta registro legado fora do contrato (número fora de 1..3)", async () => {
    persistir(cicloLegado(), cicloLegado({ id: "invalido", ciclo: 4 as unknown as 1 }));

    const resultado = await repository.listarCiclos(ORG);

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data.map((ciclo) => ciclo.id)).toEqual(["ciclo-legado"]);
  });

  it("obterCiclo resolve por UUID e devolve ausência explícita quando não há registro", async () => {
    persistir(cicloLegado({ status: "PLANEJADO" }));

    const encontrado = await repository.obterCiclo(ORG, "ciclo-legado");
    expect(encontrado.ok).toBe(true);
    if (!encontrado.ok) return;
    expect(encontrado.data?.id).toBe("ciclo-legado");

    expect(await repository.obterCiclo(ORG, "inexistente")).toEqual({ ok: true, data: null });
    expect(await repository.obterCicloAtivo(ORG)).toEqual({ ok: true, data: null });
  });

  it("obterCicloAtivo devolve o ciclo ativo do storage legado", async () => {
    persistir(cicloLegado({ status: "ATIVO" }), cicloLegado({ id: "outro", status: "PLANEJADO" }));

    const ativo = await repository.obterCicloAtivo(ORG);

    expect(ativo.ok).toBe(true);
    if (!ativo.ok) return;
    expect(ativo.data?.id).toBe("ciclo-legado");
    expect(ativo.data?.status).toBe("ATIVO");
  });

  it("falha do storage vira INTERNAL (fail-closed, nunca lança nem inventa ciclo)", async () => {
    vi.spyOn(localStorage, "getItem").mockImplementation(() => {
      throw new Error("storage indisponível");
    });

    expect(await repository.listarCiclos(ORG)).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Leitura local (LEGACY) indisponível." },
    });
    expect(await repository.obterCiclo(ORG, "ciclo-legado")).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Leitura local (LEGACY) indisponível." },
    });
    expect(await repository.obterCicloAtivo(ORG)).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Leitura local (LEGACY) indisponível." },
    });
  });
});
