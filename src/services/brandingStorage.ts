import type { BrandingConfig } from "../types/Branding";

const STORAGE_KEY = "feedback-control-branding";

export const brandingPadrao: BrandingConfig = {
  nomeSistema: "Virtus",
  subtituloSistema: "Performance & Feedback Management",
  corPrimaria: "#0F172A",
  corSecundaria: "#6366F1",
  corDestaque: "#0EA5E9",
  corFundo: "#FFFFFF",
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
