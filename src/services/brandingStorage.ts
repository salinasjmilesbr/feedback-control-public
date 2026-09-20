import type { BrandingConfig } from "../types/Branding";

/**
 * Issue #317 (Fase 1) — APARÊNCIA DO TENANT, SEGREGADA POR ORGANIZAÇÃO.
 *
 * Decisão soberana: a **plataforma** tem identidade Virtus fixa; cada
 * **organização** tem a sua própria aparência (logo, nome e cores). Este módulo
 * é a ÚNICA persistência dessa aparência e a guarda do isolamento:
 *
 * - a chave inclui o `organizationId` ⇒ duas organizações no mesmo navegador
 *   nunca compartilham configuração;
 * - sem organização ativa (superfície de plataforma) devolve sempre os
 *   **defaults seguros** — nunca o que estiver gravado para alguma organização;
 * - a chave legada `feedback-control-branding` (escopo do NAVEGADOR) é
 *   **deliberadamente ignorada**: adotá-la reintroduziria exatamente o vazamento
 *   entre tenants que motivou a reconstrução. Dívida registrada: se existir
 *   instalação real com essa chave, a migração tem de ser explícita e por
 *   organização.
 */

/** Prefixo da chave por organização. O sufixo é o `organizationId`. */
export const PREFIXO_CHAVE_BRANDING = "feedback-control-branding:";

/** Chave legada (global do navegador) — NÃO é lida nem escrita por este módulo. */
export const CHAVE_LEGADA_BRANDING = "feedback-control-branding";

/**
 * Defaults SEGUROS: identidade OFICIAL Virtus (`docs/brand/virtus-brand-guide.md`
 * §1/§2 — Issue #312), usada quando não há tenant e quando a organização não
 * personalizou. **Nunca** a identidade legada ("Feedback Control" / roxo).
 */
export const brandingPadrao: BrandingConfig = {
  nomeSistema: "Virtus",
  subtituloSistema: "Performance & Feedback Management",
  corPrimaria: "#6366F1", // Destaque — CTA primário, seleção, foco
  corSecundaria: "#0F172A", // Primário — navy, estabilidade
  corDestaque: "#0EA5E9", // Apoio da identidade
  corFundo: "#F1F5F9", // Superfície — fundo da página
};

function chaveDaOrganizacao(organizationId: string): string {
  return `${PREFIXO_CHAVE_BRANDING}${organizationId}`;
}

/**
 * Aparência da organização informada. `null`/`undefined`/vazio ⇒ plataforma ⇒
 * defaults seguros (fail-closed: nada de tenant chega à plataforma).
 */
export function getBranding(
  organizationId: string | null | undefined
): BrandingConfig {
  if (!organizationId) return brandingPadrao;

  let data: string | null;
  try {
    data = localStorage.getItem(chaveDaOrganizacao(organizationId));
  } catch {
    // Sem storage disponível ⇒ defaults seguros (nunca dados de outro tenant).
    return brandingPadrao;
  }
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

/** Grava a aparência DE UMA organização (nunca de escopo global). */
export function salvarBranding(
  organizationId: string,
  config: BrandingConfig
): void {
  if (!organizationId) return;
  localStorage.setItem(chaveDaOrganizacao(organizationId), JSON.stringify(config));
}

/** Restaura os defaults seguros DE UMA organização e os devolve. */
export function resetarBranding(organizationId: string): BrandingConfig {
  if (!organizationId) return brandingPadrao;
  localStorage.removeItem(chaveDaOrganizacao(organizationId));
  return brandingPadrao;
}
