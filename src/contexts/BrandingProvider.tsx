import { useEffect, useMemo, useState, type ReactNode } from "react";
import {
  brandingPadrao,
  getBranding,
  resetarBranding,
  salvarBranding,
} from "../services/brandingStorage";
import { temaDoTenant, tituloDaPagina } from "../services/temaTenant";
import type { BrandingConfig } from "../types/Branding";
import { useAuth } from "../auth/AuthContext";
import {
  BrandingContext,
  type BrandingContextValue,
} from "./BrandingContext";

/**
 * Issue #317 (Fase 1) — provedor da aparência do TENANT.
 *
 * O que mudou na reconstrução (e por quê):
 * - **Nenhum tema é escrito em `documentElement`/`body`.** O provedor apenas
 *   CALCULA o mapa de custom properties (`temaDoTenant`) para o container do
 *   tenant; a aplicação escopada é da fase do Shell. Era exatamente a escrita
 *   global que fazia o branding de um tenant pintar a plataforma (e qualquer
 *   outro tenant) no mesmo navegador.
 * - **Segregação por organização:** a aparência é lida/gravada por
 *   `organizationId` (ver `brandingStorage`). Sem organização ativa o provedor
 *   opera em escopo `plataforma`, com defaults seguros e mapa VAZIO.
 * - **Depende do contexto de tenant:** por isso este provedor vive DENTRO de
 *   `AuthProvider` (ver `App.tsx`) — antes ele ficava acima e não sabia qual
 *   organização estava ativa.
 * - **Título por contexto:** plataforma ⇒ título fixo; tenant ⇒ nome da
 *   organização. O título é lido de `tituloDaPagina` (função pura) e nunca
 *   recebe valor de tenant quando não há organização ativa.
 */
export function BrandingProvider({ children }: { children: ReactNode }) {
  const { organizacaoAtivaId } = useAuth();
  const [versao, setVersao] = useState(0);

  const branding = useMemo<BrandingConfig>(() => {
    // `versao` é a invalidação EXPLÍCITA após gravar/restaurar a aparência da
    // organização (a leitura é sempre da chave por organização).
    void versao;
    return getBranding(organizacaoAtivaId);
  }, [organizacaoAtivaId, versao]);

  const tema = useMemo(
    () => temaDoTenant(organizacaoAtivaId, branding),
    [organizacaoAtivaId, branding]
  );

  const titulo = tituloDaPagina(organizacaoAtivaId, branding);

  useEffect(() => {
    document.title = titulo;
  }, [titulo]);

  const value = useMemo<BrandingContextValue>(
    () => ({
      branding,
      tema,
      atualizarBranding: (config) => {
        // Fail-closed: sem organização ativa (plataforma) não há o que gravar.
        if (!organizacaoAtivaId) return;
        salvarBranding(organizacaoAtivaId, config);
        setVersao((atual) => atual + 1);
      },
      restaurarPadrao: () => {
        if (!organizacaoAtivaId) return brandingPadrao;
        const padrao = resetarBranding(organizacaoAtivaId);
        setVersao((atual) => atual + 1);
        return padrao;
      },
    }),
    [branding, tema, organizacaoAtivaId]
  );

  return (
    <BrandingContext.Provider value={value}>
      {children}
    </BrandingContext.Provider>
  );
}
