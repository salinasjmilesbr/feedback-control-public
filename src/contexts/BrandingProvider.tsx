import { useEffect, useMemo, useState, type ReactNode } from "react";
import {
  brandingPadrao,
  getBranding,
  resetarBranding,
  salvarBranding,
} from "../services/brandingStorage";
import type { BrandingConfig } from "../types/Branding";
import {
  BrandingContext,
  type BrandingContextValue,
} from "./BrandingContext";

function aplicarTema(config: BrandingConfig) {
  const root = document.documentElement;

  root.style.setProperty("--brand-primary", config.corPrimaria);
  root.style.setProperty("--brand-secondary", config.corSecundaria);
  root.style.setProperty("--brand-accent", config.corDestaque);
  root.style.setProperty("--brand-bg", config.corFundo);
}

export function BrandingProvider({ children }: { children: ReactNode }) {
  const [branding, setBranding] = useState<BrandingConfig>(() => getBranding());

  useEffect(() => {
    aplicarTema(branding);
    document.title = branding.nomeSistema || brandingPadrao.nomeSistema;
  }, [branding]);

  const value = useMemo<BrandingContextValue>(
    () => ({
      branding,
      atualizarBranding: (config) => {
        salvarBranding(config);
        setBranding(config);
      },
      restaurarPadrao: () => {
        const padrao = resetarBranding();
        setBranding(padrao);
      },
    }),
    [branding]
  );

  return (
    <BrandingContext.Provider value={value}>
      {children}
    </BrandingContext.Provider>
  );
}
