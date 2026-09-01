import { createContext, useContext } from "react";
import type { BrandingConfig } from "../types/Branding";

export type BrandingContextValue = {
  branding: BrandingConfig;
  atualizarBranding: (config: BrandingConfig) => void;
  restaurarPadrao: () => void;
};

export const BrandingContext = createContext<BrandingContextValue | null>(null);

export function useBranding() {
  const context = useContext(BrandingContext);

  if (!context) {
    throw new Error("useBranding deve ser usado dentro de BrandingProvider.");
  }

  return context;
}
