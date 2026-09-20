import { createContext, useContext } from "react";
import type { BrandingConfig } from "../types/Branding";
import type { TemaBranding } from "../services/temaTenant";

export type BrandingContextValue = {
  /** Aparência da organização ativa (ou defaults seguros na plataforma). */
  branding: BrandingConfig;
  /**
   * Tema já traduzido para custom properties, com o ESCOPO explícito
   * (`plataforma` ⇒ mapa vazio). Aplicá-lo ao container do tenant pertence à
   * fase do Shell: a Fase 1 da #317 não escreve tema em elemento global.
   */
  tema: TemaBranding;
  atualizarBranding: (config: BrandingConfig) => void;
  restaurarPadrao: () => BrandingConfig;
};

export const BrandingContext = createContext<BrandingContextValue | null>(null);

export function useBranding() {
  const context = useContext(BrandingContext);

  if (!context) {
    throw new Error("useBranding deve ser usado dentro de BrandingProvider.");
  }

  return context;
}
