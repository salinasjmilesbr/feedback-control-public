import { renderToStaticMarkup } from "react-dom/server";
import type { ComponentProps } from "react";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import AccessRestrictedState from "./AccessRestrictedState";

function renderizar(
  props: ComponentProps<typeof AccessRestrictedState>
) {
  return renderToStaticMarkup(
    <MemoryRouter>
      <AccessRestrictedState {...props} />
    </MemoryRouter>
  );
}

describe("AccessRestrictedState", () => {
  it("renderiza o padrão visual com ação para o início", () => {
    const html = renderizar({ message: "Mensagem de acesso negado." });

    expect(html).toContain("Acesso restrito");
    expect(html).toContain("Mensagem de acesso negado.");
    expect(html).toContain('href="/"');
    expect(html).toContain("Voltar ao início");
  });

  it("permite configurar o destino e o label da ação", () => {
    const html = renderizar({
      message: "Acesso administrativo indisponível.",
      actionTo: "/colaborador/123",
      actionLabel: "Voltar ao colaborador",
    });

    expect(html).toContain("Acesso administrativo indisponível.");
    expect(html).toContain('href="/colaborador/123"');
    expect(html).toContain("Voltar ao colaborador");
  });

  it("permite preservar uma ação de retorno contextual", () => {
    const html = renderizar({
      message: "Acesso administrativo indisponível.",
      actionLabel: "Voltar",
      onAction: () => undefined,
    });

    expect(html).toContain("<button");
    expect(html).toContain("Voltar");
  });
});
