import { describe, expect, it } from "vitest";
import type { Colaborador } from "../types/Colaborador";
import { getColaboradoresVisiveis } from "./visibilidadeColaboradores";

function colaborador(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number,
  avaliadoresColegiadoMatriculas?: number[]
): Colaborador {
  return {
    matricula,
    status: "ATIVO",
    nome: `Pessoa ${matricula}`,
    email: `${matricula}@example.com`,
    cargo: funcao ?? "Sem função",
    area: "Área de teste",
    funcao,
    gestorDiretoMatricula,
    avaliadoresColegiadoMatriculas,
    respondePara: "",
  };
}

describe("getColaboradoresVisiveis", () => {
  const gerente = colaborador(1, "GERENTE");
  const coordenador = colaborador(2, "COORDENADOR", gerente.matricula);
  const subordinadoDireto = colaborador(3, "ANALISTA", coordenador.matricula);
  const descendenteIndireto = colaborador(4, "ESTAGIARIO", subordinadoDireto.matricula);
  const outroCoordenador = colaborador(5, "COORDENADOR", gerente.matricula);
  const participanteColegiado = colaborador(
    6,
    "ANALISTA",
    outroCoordenador.matricula,
    [coordenador.matricula]
  );
  const foraDaHierarquia = colaborador(7, "ANALISTA");
  const colaboradores = [
    gerente,
    coordenador,
    subordinadoDireto,
    descendenteIndireto,
    outroCoordenador,
    participanteColegiado,
    foraDaHierarquia,
  ];

  it("retorna todos os descendentes recursivos do gerente", () => {
    expect(
      getColaboradoresVisiveis(gerente, colaboradores).map(({ matricula }) => matricula)
    ).toEqual([2, 5, 3, 6, 4]);
  });

  it("retorna os subordinados diretos do coordenador", () => {
    expect(getColaboradoresVisiveis(coordenador, colaboradores)).toContainEqual(
      subordinadoDireto
    );
  });

  it("inclui participantes em que o coordenador integra o colegiado", () => {
    expect(getColaboradoresVisiveis(coordenador, colaboradores)).toContainEqual(
      participanteColegiado
    );
  });

  it.each(["ANALISTA", "CONSULTOR", "ESTAGIARIO"] as const)(
    "não concede escopo administrativo ao perfil %s",
    (funcao) => {
      expect(
        getColaboradoresVisiveis(colaborador(100, funcao), colaboradores)
      ).toEqual([]);
    }
  );
});
