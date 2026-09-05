import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { CycleRepository } from "../../application/ports/CycleRepository";
import { ativarCiclo, encerrarCiclo } from "../../services/cicloAvaliacaoStorage";
import { instalarLocalStorageEmMemoria } from "../../test/localStorageMock";
import type { CicloAvaliacao } from "../../types/CicloAvaliacao";
import { localCycleRepository } from "./localCycleRepository";

const STORAGE_KEY = "feedback-control-ciclos";
const repository: CycleRepository = localCycleRepository;
const agora = "2026-02-01T12:00:00.000Z";

function cicloLegado(): CicloAvaliacao {
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
  };
}

describe("CycleRepository com storage local", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(STORAGE_KEY, "[]");
    vi.useFakeTimers();
    vi.setSystemTime(new Date(agora));
  });

  afterEach(() => vi.useRealTimers());

  it("lê e ordena dados legados sem regravar ou remover campos históricos", () => {
    const legado = cicloLegado();
    const ativo: CicloAvaliacao = { ...legado, id: "ativo", ano: 2026, ciclo: 1, status: "ATIVO" };
    const raw = JSON.stringify([legado, ativo]);
    localStorage.setItem(STORAGE_KEY, raw);

    expect(repository.getCiclosAvaliacao()).toEqual([ativo, legado]);
    expect(repository.getCicloAtivo()).toEqual(ativo);
    expect(localStorage.getItem(STORAGE_KEY)).toBe(raw);
  });

  it.each([null, "json inválido"])("mantém inicialização do storage quando a base é %s", (raw) => {
    if (raw === null) localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, raw);
    localStorage.setItem("feedback-control-feedbacks", "[]");

    const ciclos = repository.getCiclosAvaliacao();

    expect(ciclos).toHaveLength(1);
    expect(ciclos[0]).toMatchObject({ ano: 2026, ciclo: 1, status: "ATIVO", dataCriacao: agora });
    expect(JSON.parse(localStorage.getItem(STORAGE_KEY)!)).toEqual(ciclos);
  });

  it("persiste o cadastro e acompanha lifecycle e auditoria realizados pelo serviço vigente", () => {
    const legado = cicloLegado();
    localStorage.setItem(STORAGE_KEY, JSON.stringify([legado]));
    const novo = repository.criarCiclo(2026, 1, "2026-01-01", "2026-04-30", 2, 1);

    expect(novo).toMatchObject({ status: "PLANEJADO", quantidadeMetasNegocio: 2, quantidadeMetasIndividuais: 1 });
    expect(JSON.parse(localStorage.getItem(STORAGE_KEY)!)).toContainEqual(novo);
    expect(repository.getCicloAtivo()).toBeUndefined();
    ativarCiclo(novo.id);
    expect(repository.getCicloAtivo()?.id).toBe(novo.id);
    encerrarCiclo(novo.id, 2);

    expect(repository.getCiclosAvaliacao()).toContainEqual(legado);
    expect(repository.getCiclosAvaliacao()[0]).toMatchObject({
      status: "ENCERRADO",
      encerramentos: [{ data: agora, encerradoComPendencias: true, quantidadePendencias: 2 }],
    });
    expect(repository.getCicloAtivo()).toBeUndefined();
  });

  it("preserva ativação no cadastro e rejeita outro ativo ou cadastro duplicado sem gravar", () => {
    const ativo = repository.criarCiclo(2026, 1, "2026-01-01", "2026-04-30", 0, 0, true);
    const antes = localStorage.getItem(STORAGE_KEY);

    expect(repository.getCicloAtivo()).toEqual(ativo);
    expect(() => repository.criarCiclo(2026, 2, "2026-05-01", "2026-08-31", 0, 0, true))
      .toThrow("Já existe um ciclo ativo.");
    expect(() => repository.criarCiclo(2026, 1, "2026-01-01", "2026-04-30", 0, 0))
      .toThrow("O ciclo 2026 - Ciclo 1 já está cadastrado.");
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
  });

  it.each([
    ["", "2026-04-30", "Informe as datas de início e fim do ciclo."],
    ["2026-05-01", "2026-04-30", "A data de início não pode ser posterior à data de fim."],
  ])("propaga a validação do período %s / %s", (inicio, fim, erro) => {
    expect(() => repository.criarCiclo(2026, 1, inicio, fim, 0, 0)).toThrow(erro);
    expect(localStorage.getItem(STORAGE_KEY)).toBe("[]");
  });
});
