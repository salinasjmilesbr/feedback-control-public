import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import HomePlataforma, { HomePlataformaAutorizada } from "./HomePlataformaPage";
import type { ProvisionamentoPlataforma } from "../../application/ports/ProvisionamentoPlataforma";

const controlador: ProvisionamentoPlataforma = {
  provisionarOrganizacao: async () => ({ organizationId: "org-sintetica" }),
  souOperadorDaPlataforma: async () => true,
  identidadeDoOperadorAutenticado: async () => "user-sintetico",
};

describe("HomePlataforma", () => {
  it("mantém o conteúdo fechado enquanto o self-check não responde", () => {
    const pendente: ProvisionamentoPlataforma = {
      ...controlador,
      souOperadorDaPlataforma: () => new Promise<boolean>(() => {}),
    };
    const html = renderToStaticMarkup(
      <MemoryRouter>
        <HomePlataforma provisionamento={pendente} />
      </MemoryRouter>
    );

    expect(html).toContain("Verificando acesso à plataforma");
    expect(html).not.toContain("Criar organização");
  });

  it("oferece uma home de plataforma distinta do tenant após autorização", () => {
    const html = renderToStaticMarkup(
      <MemoryRouter>
        <HomePlataformaAutorizada />
      </MemoryRouter>
    );

    expect(html).toContain("Administração da plataforma");
    expect(html).toContain('href="/plataforma/nova-organizacao"');
    expect(html).toContain("Criar organização");
    expect(html).not.toContain("Acesso negado");
  });
});
