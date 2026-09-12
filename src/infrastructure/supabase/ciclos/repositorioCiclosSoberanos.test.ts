/**
 * F5-09 P5 — leitura soberana de ciclos: porta assíncrona, UUID-first,
 * fail-closed (sem fallback local) e projeção sem inventar dados.
 */

import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { criarRepositorioCiclosSoberanos } from "./repositorioCiclosSoberanos";

const ORG = "11111111-1111-4111-8111-111111111111";
const OUTRA_ORG = "99999999-9999-4999-8999-999999999999";
const CICLO = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CICLO_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

interface RespostaTabela {
  readonly data?: unknown;
  readonly error?: { readonly code: string; readonly message: string } | null;
}

interface Consulta {
  readonly tabela: string;
  readonly igualdades: (readonly [string, unknown])[];
  readonly ordens: (readonly [string, boolean])[];
}

function clienteLeituraFalso(
  porTabela: Record<string, RespostaTabela>,
  sessao: { access_token?: string } | null
): { readonly cliente: SupabaseClient; readonly consultas: Consulta[] } {
  const consultas: Consulta[] = [];
  const cliente = {
    auth: {
      getSession: async () => ({ data: { session: sessao }, error: null }),
    },
    from(tabela: string) {
      const registro: Consulta = { tabela, igualdades: [], ordens: [] };
      consultas.push(registro);
      const resposta = porTabela[tabela] ?? { data: [] };
      const resultado = () => ({ data: resposta.data ?? null, error: resposta.error ?? null });
      const construtor = {
        select: () => construtor,
        eq: (coluna: string, valor: unknown) => {
          registro.igualdades.push([coluna, valor]);
          return construtor;
        },
        order: (coluna: string, opcoes?: { ascending?: boolean }) => {
          registro.ordens.push([coluna, opcoes?.ascending !== false]);
          return construtor;
        },
        maybeSingle: () => Promise.resolve(resultado()),
        then: (resolver: (valor: unknown) => unknown) => Promise.resolve(resolver(resultado())),
      };
      return construtor;
    },
  } as unknown as SupabaseClient;
  return { cliente, consultas };
}

function linhaCiclo(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: CICLO,
    organization_id: ORG,
    ano: 2035,
    numero: 1,
    status: "ATIVO",
    data_inicio: "2035-01-01",
    data_fim: "2035-03-31",
    data_ativacao: "2035-01-02T10:00:00.000Z",
    data_encerramento: null,
    encerrado_com_pendencias: false,
    quantidade_pendencias: 0,
    version: 1,
    created_at: "2035-01-01T00:00:00.000Z",
    updated_at: "2035-01-02T10:00:00.000Z",
    ...extra,
  };
}

const SESSAO = { access_token: "jwt" };

describe("F5-09 P5 — repositório soberano de ciclos (RLS own-tenant)", () => {
  it("sem sessão recusa com NOT_AUTHORIZED e NÃO consulta o PostgREST", async () => {
    const { cliente, consultas } = clienteLeituraFalso({}, null);
    const repositorio = criarRepositorioCiclosSoberanos(cliente);

    await expect(repositorio.listarCiclos(ORG)).resolves.toEqual({
      ok: false,
      error: { code: "NOT_AUTHORIZED", message: "Sessão inválida. Entre novamente." },
    });
    expect(consultas).toEqual([]);
  });

  it("organização ausente recusa com FORBIDDEN sem consultar", async () => {
    const { cliente, consultas } = clienteLeituraFalso({}, SESSAO);
    const repositorio = criarRepositorioCiclosSoberanos(cliente);

    await expect(repositorio.listarCiclos("")).resolves.toEqual({
      ok: false,
      error: { code: "FORBIDDEN", message: "Organização ativa ausente." },
    });
    expect(consultas).toEqual([]);
  });

  it("UUID malformado recusa com INVALID_INPUT (identidade nunca vem de ano/numero)", async () => {
    const { cliente, consultas } = clienteLeituraFalso({}, SESSAO);
    const repositorio = criarRepositorioCiclosSoberanos(cliente);

    await expect(repositorio.obterCiclo(ORG, "2035-1")).resolves.toEqual({
      ok: false,
      error: { code: "INVALID_INPUT", message: "Identificador de ciclo inválido." },
    });
    expect(consultas).toEqual([]);
  });

  it("lista com filtro de tenant, ordem determinística e projeção UUID-first", async () => {
    const outra = linhaCiclo({ id: CICLO_B, organization_id: OUTRA_ORG, numero: 2 });
    const { cliente, consultas } = clienteLeituraFalso(
      { evaluation_cycles: { data: [linhaCiclo(), outra] } },
      SESSAO
    );
    const repositorio = criarRepositorioCiclosSoberanos(cliente);

    const resultado = await repositorio.listarCiclos(ORG);

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data).toHaveLength(2);
    // Identidade vem de `id`; `ano`/`numero` são apenas rótulos da projeção.
    expect(resultado.data[0]).toMatchObject({
      id: CICLO,
      organizationId: ORG,
      ano: 2035,
      numero: 1,
      status: "ATIVO",
      version: 1,
    });
    expect(consultas).toHaveLength(1);
    expect(consultas[0].tabela).toBe("evaluation_cycles");
    expect(consultas[0].igualdades).toEqual([["organization_id", ORG]]);
    expect(consultas[0].ordens).toEqual([
      ["ano", false],
      ["numero", false],
      ["id", true],
    ]);
  });

  it("linha fora do contrato é DESCARTADA (nunca inventa número/identidade)", async () => {
    const { cliente } = clienteLeituraFalso(
      {
        evaluation_cycles: {
          data: [
            linhaCiclo(),
            linhaCiclo({ id: CICLO_B, numero: 4 }),
            linhaCiclo({ id: "", numero: 2 }),
            "linha-invalida",
          ],
        },
      },
      SESSAO
    );
    const repositorio = criarRepositorioCiclosSoberanos(cliente);

    const resultado = await repositorio.listarCiclos(ORG);

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data.map((ciclo) => ciclo.id)).toEqual([CICLO]);
  });

  it("negação de RLS/JWT vira FORBIDDEN e erro inesperado vira INTERNAL", async () => {
    const negado = clienteLeituraFalso(
      { evaluation_cycles: { data: null, error: { code: "42501", message: "permission denied" } } },
      SESSAO
    );
    const repositorioNegado = criarRepositorioCiclosSoberanos(negado.cliente);
    const resultadoNegado = await repositorioNegado.listarCiclos(ORG);
    expect(resultadoNegado).toEqual({
      ok: false,
      error: {
        code: "FORBIDDEN",
        message: "Você não tem permissão para consultar os ciclos desta organização.",
      },
    });

    const quebrado = clienteLeituraFalso(
      { evaluation_cycles: { data: null, error: { code: "XX000", message: "boom" } } },
      SESSAO
    );
    const repositorioQuebrado = criarRepositorioCiclosSoberanos(quebrado.cliente);
    const resultadoQuebrado = await repositorioQuebrado.listarCiclos(ORG);
    expect(resultadoQuebrado.ok).toBe(false);
    if (resultadoQuebrado.ok) return;
    expect(resultadoQuebrado.error.code).toBe("INTERNAL");
  });

  it("obterCiclo devolve o ciclo por UUID e ausência explícita quando não há linha", async () => {
    const presente = clienteLeituraFalso({ evaluation_cycles: { data: linhaCiclo() } }, SESSAO);
    const repositorio = criarRepositorioCiclosSoberanos(presente.cliente);
    const encontrado = await repositorio.obterCiclo(ORG, CICLO);
    expect(encontrado.ok).toBe(true);
    if (!encontrado.ok) return;
    expect(encontrado.data?.id).toBe(CICLO);
    expect(presente.consultas[0].igualdades).toEqual([
      ["organization_id", ORG],
      ["id", CICLO],
    ]);

    const ausente = clienteLeituraFalso({ evaluation_cycles: { data: null } }, SESSAO);
    const repositorioAusente = criarRepositorioCiclosSoberanos(ausente.cliente);
    const naoEncontrado = await repositorioAusente.obterCiclo(ORG, CICLO_B);
    expect(naoEncontrado).toEqual({ ok: true, data: null });
  });

  it("obterCicloAtivo filtra status ATIVO e devolve ausência explícita sem ciclo ativo", async () => {
    const ativo = clienteLeituraFalso({ evaluation_cycles: { data: linhaCiclo() } }, SESSAO);
    const repositorio = criarRepositorioCiclosSoberanos(ativo.cliente);
    const resultado = await repositorio.obterCicloAtivo(ORG);
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data?.status).toBe("ATIVO");
    expect(ativo.consultas[0].igualdades).toEqual([
      ["organization_id", ORG],
      ["status", "ATIVO"],
    ]);

    const nenhum = clienteLeituraFalso({ evaluation_cycles: { data: null } }, SESSAO);
    const repositorioSemAtivo = criarRepositorioCiclosSoberanos(nenhum.cliente);
    expect(await repositorioSemAtivo.obterCicloAtivo(ORG)).toEqual({ ok: true, data: null });
  });
});
