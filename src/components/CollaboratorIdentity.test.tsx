import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { IdentidadeColaborador } from "../types/Colaborador";
import CollaboratorIdentity from "./CollaboratorIdentity";

/**
 * #333 — a identidade soberana pode NÃO ter função cadastrada (função/cargo é
 * rótulo legado, não identidade). O componente não pode inventar "Analista".
 */
function identidade(
  parcial: Partial<IdentidadeColaborador> = {}
): IdentidadeColaborador {
  return {
    collaboratorId: "11111111-1111-4111-8111-111111111111",
    status: "ATIVO",
    nome: "Carolina Mendes Rocha",
    email: "",
    cargo: "",
    area: "",
    respondePara: "",
    ...parcial,
  };
}

function renderizar(colaborador: IdentidadeColaborador): string {
  return renderToStaticMarkup(<CollaboratorIdentity colaborador={colaborador} />);
}

describe("#333 — CollaboratorIdentity não presume papel", () => {
  it('sem funcao NÃO exibe "Analista" nem o bloco de papel', () => {
    const html = renderizar(identidade());

    expect(html).toContain("Carolina Mendes Rocha");
    expect(html).not.toContain("Analista");
    expect(html).not.toContain("collaborator-identity__role");
  });

  it("com funcao preserva os rótulos existentes", () => {
    expect(renderizar(identidade({ funcao: "GERENTE" }))).toContain("Gerente");
    expect(renderizar(identidade({ funcao: "COORDENADOR" }))).toContain("Coordenador");
    expect(renderizar(identidade({ funcao: "CONSULTOR" }))).toContain("Consultor");
    expect(renderizar(identidade({ funcao: "ESTAGIARIO" }))).toContain("Estagiário");

    const analistaPleno = renderizar(
      identidade({ funcao: "ANALISTA", senioridade: "PLENO" })
    );
    expect(analistaPleno).toContain("Analista");
    expect(analistaPleno).toContain("Pleno");
  });
});