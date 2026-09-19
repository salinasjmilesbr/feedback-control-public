import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import AppFooter from "./AppFooter";
import VirtusBrand from "./VirtusBrand";
import ShellFonte from "../styles/virtus-shell.css?raw";
import LayoutPlataformaFonte from "../routes/LayoutPlataforma.tsx?raw";

describe("Issue #315 — marca e footer oficiais", () => {
  it("consome o PNG oficial sem reconstruir o símbolo", () => {
    const html = renderToStaticMarkup(<VirtusBrand context="Gestão Virtus" />);

    expect(html).toContain('src="/brand/virtus-symbol.png"');
    expect(html).toContain("VIRTUS");
    expect(html).toContain("Gestão Virtus");
    expect(html).not.toContain("<svg");
  });

  it("renderiza a composição normativa do footer e a versão separada", () => {
    const html = renderToStaticMarkup(<AppFooter />);

    expect(html).toContain('src="/brand/virtus-symbol.png"');
    expect(html).toContain("VIRTUS");
    expect(html).toContain("Performance &amp; Feedback Management");
    expect(html).toContain('class="app-footer__version">Versão 1.0.0');
  });

  it("mantém o verde fora do branding do shell e compõe a Gestão Virtus", () => {
    expect(ShellFonte as string).not.toContain("#10b981");
    expect(LayoutPlataformaFonte as string).toContain('context="Gestão Virtus"');
    expect(LayoutPlataformaFonte as string).toContain("<AppFooter />");
  });
});
