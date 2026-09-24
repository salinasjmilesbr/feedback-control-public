import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import SeletorPosicao from "./SeletorPosicao";

const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CARGO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const SENIORIDADE = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const POSICAO_A = "11111111-1111-4111-8111-111111111111";
const POSICAO_B = "22222222-2222-4222-8222-222222222222";

function estrutura(
  nomes: readonly [string, string] = ["Operacoes", "Vendas"]
): EstruturaSoberana {
  return {
    unidades: [{ unitId: UNIDADE, nome: "Unidade", validFrom: "2020-01-01", validTo: null, version: 1 }],
    periodosParent: [],
    posicoes: [
      { posicaoId: POSICAO_A, nome: nomes[0], unitId: UNIDADE, jobRoleId: CARGO, seniorityLevelId: SENIORIDADE, validFrom: "2020-01-01", validTo: null, version: 1 },
      { posicaoId: POSICAO_B, nome: nomes[1], unitId: UNIDADE, jobRoleId: CARGO, seniorityLevelId: SENIORIDADE, validFrom: "2020-01-01", validTo: null, version: 1 },
    ],
    reportingLines: [], ocupacoes: [], colegiados: [], colaboradores: [],
    cargos: [{ jobRoleId: CARGO, code: "GER", nome: "Gerente", status: "active", version: 1 }],
    senioridades: [{ seniorityLevelId: SENIORIDADE, nome: "Pleno", status: "active", version: 1 }],
  };
}

function html(estruturaSoberana: EstruturaSoberana): string {
  return renderToStaticMarkup(
    <SeletorPosicao id="posicao" estrutura={estruturaSoberana} valor="" aoMudar={() => undefined} rotulo="Posicao" />
  );
}

describe("SeletorPosicao — identidade funcional", () => {
  it("exibe nome e contexto sem UUID quando não há colisão", () => {
    const resultado = html(estrutura());
    expect(resultado).toContain("Operacoes — Unidade • GER — Gerente (Pleno)");
    expect(resultado).not.toContain(`Operacoes — Unidade • GER — Gerente (Pleno) — ${POSICAO_A.slice(0, 8)}`);
  });

  it("exibe UUID abreviado somente quando nome e contexto colidem", () => {
    const resultado = html(estrutura(["Gerente", "Gerente"]));
    expect(resultado).toContain(POSICAO_A.slice(0, 8));
    expect(resultado).toContain(POSICAO_B.slice(0, 8));
    expect(resultado).toContain(`value="${POSICAO_A}"`);
    expect(resultado).toContain(`value="${POSICAO_B}"`);
  });
});
