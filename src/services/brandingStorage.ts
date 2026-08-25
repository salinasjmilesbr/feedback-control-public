import type { BrandingConfig } from "../types/Branding";

const STORAGE_KEY = "feedback-control-branding";

export const brandingPadrao: BrandingConfig = {
  nomeSistema: "Feedback Control",
  subtituloSistema: "Performance & Feedback Management",
  corPrimaria: "#660099",
  corSecundaria: "#8A2BE2",
  corDestaque: "#0078D4",
  corFundo: "#F6F7FB",
};

export function getBranding(): BrandingConfig {
  const data = localStorage.getItem(STORAGE_KEY);
  if (!data) return brandingPadrao;

  try {
    const salvo = JSON.parse(data) as Partial<BrandingConfig> & {
      nomeEmpresa?: string;
    };

    return {
      ...brandingPadrao,
      ...salvo,
      subtituloSistema:
        salvo.subtituloSistema?.trim() ||
        salvo.nomeEmpresa?.trim() ||
        brandingPadrao.subtituloSistema,
    };
  } catch {
    return brandingPadrao;
  }
}

export function salvarBranding(config: BrandingConfig): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
}

export function resetarBranding(): BrandingConfig {
  localStorage.removeItem(STORAGE_KEY);
  return brandingPadrao;
}
