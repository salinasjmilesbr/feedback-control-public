import { brandingPadrao } from "./brandingStorage";
import type { BrandingConfig } from "../types/Branding";

/**
 * Issue #317 (Fase 1) — TEMA DO TENANT (cálculo puro, sem DOM).
 *
 * Responsabilidades (ver `docs/` da #317 e a decisão soberana):
 * - `--virtus-*` é ESTRUTURA/IDENTIDADE DA PLATAFORMA: não aparece aqui.
 * - `--brand-*` é a superfície de theming do TENANT: este módulo traduz a
 *   configuração da organização no mapa de custom properties que a fase do
 *   Shell aplicará **no container do tenant**.
 *
 * Garantias desta camada:
 * - NÃO escreve em `documentElement`/`body` nem em qualquer elemento global
 *   (não há DOM aqui): a aplicação escopada é responsabilidade do Shell;
 * - sem organização ativa o escopo é `plataforma` e o mapa é **VAZIO** — a
 *   plataforma é imune ao branding de qualquer tenant, por construção;
 * - cores inválidas caem no default seguro (fail-closed), nunca em valor de
 *   outra organização.
 */

export type EscopoBranding = "plataforma" | "tenant";

export interface TemaBranding {
  readonly escopo: EscopoBranding;
  /** Mapa de custom properties do TENANT (vazio no escopo de plataforma). */
  readonly variaveis: Readonly<Record<string, string>>;
}

/** Cor aceita: hexadecimal `#rgb` ou `#rrggbb`. */
const COR_HEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;

/** Título da superfície de PLATAFORMA: identidade Virtus, nunca de tenant. */
export const TITULO_PLATAFORMA = "Virtus";

function corSegura(valor: unknown, padrao: string): string {
  if (typeof valor !== "string") return padrao;
  const normalizado = valor.trim();
  return COR_HEX.test(normalizado) ? normalizado : padrao;
}

/**
 * Mapa de custom properties do tenant. Apenas o conjunto FECHADO de cores do
 * `BrandingConfig` — o restante (`--brand-surface*`, `--brand-text*`,
 * `--brand-border`, `--brand-radius`, `--brand-shadow`) é derivado no CSS a
 * partir destes, como já ocorre hoje.
 */
export function temaDoTenant(
  organizationId: string | null | undefined,
  config: BrandingConfig
): TemaBranding {
  if (!organizationId) {
    return { escopo: "plataforma", variaveis: {} };
  }

  return {
    escopo: "tenant",
    variaveis: {
      "--brand-primary": corSegura(config.corPrimaria, brandingPadrao.corPrimaria),
      "--brand-secondary": corSegura(
        config.corSecundaria,
        brandingPadrao.corSecundaria
      ),
      "--brand-accent": corSegura(config.corDestaque, brandingPadrao.corDestaque),
      "--brand-bg": corSegura(config.corFundo, brandingPadrao.corFundo),
    },
  };
}

/**
 * Título do documento POR CONTEXTO: plataforma ⇒ fixo; tenant ⇒ nome da
 * organização (fallback no fixo). O título não é tema de cor e não vaza valor de
 * tenant para a plataforma.
 */
export function tituloDaPagina(
  organizationId: string | null | undefined,
  config: BrandingConfig
): string {
  if (!organizationId) return TITULO_PLATAFORMA;
  const nome = config.nomeSistema?.trim();
  return nome && nome.length > 0 ? nome : TITULO_PLATAFORMA;
}
