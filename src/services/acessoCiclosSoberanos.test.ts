/**
 * F5-09 P5 — porta única de leitura de ciclos: fail-closed sem caminho soberano,
 * cache de UX publicada e proteção contra RESPOSTA ATRASADA (stale) por geração
 * monotônica (troca de organização, invalidação e unmount).
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  CicloSoberano,
  CycleRepository,
  ResultadoCiclos,
} from "../application/ports/CycleRepository";
import {
  criarControladorCiclosSoberanos,
  obterRepositorioCiclosSoberanos,
  redefinirAcessoCiclosSoberanos,
} from "./acessoCiclosSoberanos";

const ORG_A = "11111111-1111-4111-8111-111111111111";
const ORG_B = "99999999-9999-4999-8999-999999999999";
const CICLO_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CICLO_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function ciclo(id: string, organizationId: string, status: CicloSoberano["status"] = "ATIVO"): CicloSoberano {
  return {
    id,
    organizationId,
    ano: 2035,
    numero: 1,
    status,
    dataInicio: "2035-01-01",
    dataFim: "2035-03-31",
    dataAtivacao: "2035-01-02T00:00:00.000Z",
    dataEncerramento: null,
    encerradoComPendencias: false,
    quantidadePendencias: 0,
    version: 1,
    criadoEm: "2035-01-01T00:00:00.000Z",
    atualizadoEm: "2035-01-02T00:00:00.000Z",
  };
}

function ok<T>(data: T): ResultadoCiclos<T> {
  return { ok: true, data };
}

const falhaInterna = {
  ok: false as const,
  error: { code: "INTERNAL" as const, message: "Não foi possível consultar os ciclos agora." },
};

function repositorioFalso(
  impl: Partial<CycleRepository>
): CycleRepository & { readonly listarCiclos: ReturnType<typeof vi.fn> } {
  return {
    listarCiclos: vi.fn(async () => ok<readonly CicloSoberano[]>([])),
    obterCiclo: vi.fn(async () => ok<CicloSoberano | null>(null)),
    obterCicloAtivo: vi.fn(async () => ok<CicloSoberano | null>(null)),
    ...impl,
  } as unknown as CycleRepository & { readonly listarCiclos: ReturnType<typeof vi.fn> };
}

/** Promessa com resolução manual (controle de ordem das respostas). */
function adiada<T>(): { readonly promise: Promise<T>; readonly resolver: (valor: T) => void } {
  let resolver!: (valor: T) => void;
  const promise = new Promise<T>((resolve) => {
    resolver = resolve;
  });
  return { promise, resolver };
}

describe("F5-09 P5 — acesso soberano a ciclos (porta única)", () => {
  beforeEach(() => {
    redefinirAcessoCiclosSoberanos();
  });

  it("sem caminho soberano é FAIL-CLOSED: recusa com código público e nunca cai para o local", async () => {
    const controlador = criarControladorCiclosSoberanos({ cliente: null });

    const resultado = await controlador.carregar(ORG_A);

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("INTERNAL");
    expect(controlador.estado()).toEqual({
      fase: "indisponivel",
      organizacaoId: ORG_A,
      ciclos: [],
      codigo: "INTERNAL",
      mensagem: "Leitura soberana de ciclos indisponível neste ambiente.",
    });
  });

  it("a memoização do caminho soberano é fail-closed quando não há configuração", () => {
    expect(obterRepositorioCiclosSoberanos({ cliente: null })).toBeNull();
  });

  it("publica a lista soberana e delega leituras por UUID/ATIVO ao repositório", async () => {
    const repositorio = repositorioFalso({
      listarCiclos: vi.fn(async () => ok<readonly CicloSoberano[]>([ciclo(CICLO_A, ORG_A)])),
      obterCiclo: vi.fn(async () => ok<CicloSoberano | null>(ciclo(CICLO_A, ORG_A))),
      obterCicloAtivo: vi.fn(async () => ok<CicloSoberano | null>(ciclo(CICLO_A, ORG_A))),
    });
    const controlador = criarControladorCiclosSoberanos({ repositorio });

    await controlador.carregar(ORG_A);

    expect(controlador.estado()).toEqual({
      fase: "pronta",
      organizacaoId: ORG_A,
      ciclos: [ciclo(CICLO_A, ORG_A)],
    });
    expect(await controlador.obterCiclo(ORG_A, CICLO_A)).toEqual(ok(ciclo(CICLO_A, ORG_A)));
    expect(await controlador.obterCicloAtivo(ORG_A)).toEqual(ok(ciclo(CICLO_A, ORG_A)));
  });

  it("erro de backend vira INDISPONIVEL com código público (nunca dado local)", async () => {
    const repositorio = repositorioFalso({
      listarCiclos: vi.fn(async () => falhaInterna),
    });
    const controlador = criarControladorCiclosSoberanos({ repositorio });

    const resultado = await controlador.carregar(ORG_A);

    expect(resultado.ok).toBe(false);
    expect(controlador.estado()).toEqual({
      fase: "indisponivel",
      organizacaoId: ORG_A,
      ciclos: [],
      codigo: "INTERNAL",
      mensagem: "Não foi possível consultar os ciclos agora.",
    });
  });

  it("resposta ATRASADA de organização anterior não vence o contexto mais recente", async () => {
    const primeira = adiada<ResultadoCiclos<readonly CicloSoberano[]>>();
    const segunda = adiada<ResultadoCiclos<readonly CicloSoberano[]>>();
    let chamadas = 0;
    const repositorio = repositorioFalso({
      listarCiclos: vi.fn(() => {
        chamadas += 1;
        return (chamadas === 1 ? primeira.promise : segunda.promise) as Promise<
          ResultadoCiclos<readonly CicloSoberano[]>
        >;
      }),
    });
    const controlador = criarControladorCiclosSoberanos({ repositorio });

    const cargaA = controlador.carregar(ORG_A);
    const cargaB = controlador.carregar(ORG_B);

    // A organização NOVA resolve primeiro e publica.
    segunda.resolver(ok<readonly CicloSoberano[]>([ciclo(CICLO_B, ORG_B)]));
    await cargaB;
    expect(controlador.estado()).toEqual({
      fase: "pronta",
      organizacaoId: ORG_B,
      ciclos: [ciclo(CICLO_B, ORG_B)],
    });

    // A resposta ANTIGA chega depois: é descartada (não publica).
    primeira.resolver(ok<readonly CicloSoberano[]>([ciclo(CICLO_A, ORG_A)]));
    await cargaA;
    expect(controlador.estado()).toEqual({
      fase: "pronta",
      organizacaoId: ORG_B,
      ciclos: [ciclo(CICLO_B, ORG_B)],
    });
  });

  it("unmount (descartar) impede que resposta em voo publique estado obsoleto", async () => {
    const pendente = adiada<ResultadoCiclos<readonly CicloSoberano[]>>();
    const repositorio = repositorioFalso({ listarCiclos: vi.fn(() => pendente.promise) });
    const controlador = criarControladorCiclosSoberanos({ repositorio });

    const carga = controlador.carregar(ORG_A);
    controlador.descartar();
    pendente.resolver(ok<readonly CicloSoberano[]>([ciclo(CICLO_A, ORG_A)]));
    await carga;

    expect(controlador.estado()).toEqual({
      fase: "ocioso",
      organizacaoId: null,
      ciclos: [],
    });
  });

  it("invalidar descarta respostas em voo e volta a ocioso (troca de organização)", async () => {
    const pendente = adiada<ResultadoCiclos<readonly CicloSoberano[]>>();
    const repositorio = repositorioFalso({ listarCiclos: vi.fn(() => pendente.promise) });
    const controlador = criarControladorCiclosSoberanos({ repositorio });

    const carga = controlador.carregar(ORG_A);
    controlador.invalidar();
    pendente.resolver(ok<readonly CicloSoberano[]>([ciclo(CICLO_A, ORG_A)]));
    await carga;

    expect(controlador.estado()).toEqual({
      fase: "ocioso",
      organizacaoId: null,
      ciclos: [],
    });
  });

  it("organização ausente na carga recusa com FORBIDDEN sem consultar o repositório", async () => {
    const repositorio = repositorioFalso({});
    const controlador = criarControladorCiclosSoberanos({ repositorio });

    const resultado = await controlador.carregar("");

    expect(resultado.ok).toBe(false);
    expect(repositorio.listarCiclos).not.toHaveBeenCalled();
  });

  it("sem caminho soberano as leituras por UUID/ATIVO também são fail-closed", async () => {
    const controlador = criarControladorCiclosSoberanos({ cliente: null as SupabaseClient | null });

    const porId = await controlador.obterCiclo(ORG_A, CICLO_A);
    const ativo = await controlador.obterCicloAtivo(ORG_A);

    expect(porId.ok).toBe(false);
    expect(ativo.ok).toBe(false);
  });
});
