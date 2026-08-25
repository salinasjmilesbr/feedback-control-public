import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import type { BrandingConfig } from "../types/Branding";
import {
  brandingPadrao,
  getBranding,
  resetarBranding,
  salvarBranding,
} from "../services/brandingStorage";

type BrandingContextValue = {
  branding: BrandingConfig;
  atualizarBranding: (config: BrandingConfig) => void;
  restaurarPadrao: () => void;
};

const BrandingContext = createContext<BrandingContextValue | null>(null);

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

export function useBranding() {
  const context = useContext(BrandingContext);

  if (!context) {
    throw new Error("useBranding deve ser usado dentro de BrandingProvider.");
  }

  return context;
}
