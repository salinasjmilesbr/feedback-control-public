/**
 * Issue #317 (Fase 2) — IDENTIDADE VIRTUS (oficial e FIXA).
 *
 * Fonte normativa: `docs/brand/virtus-brand-guide.md` (#312) e
 * `docs/brand/virtus-visual-acceptance.md`.
 *
 * Estas constantes são a ÚNICA origem das strings de marca do produto. Elas não
 * dependem de organização, de sessão nem de configuração: a identidade Virtus é
 * imutável e nunca recebe valor de tenant (§5 — "Virtus puro").
 */

/** §1 — nome da marca. */
export const NOME_VIRTUS = "VIRTUS";

/** §1 — tagline oficial. */
export const TAGLINE_VIRTUS = "Performance & Feedback Management";

/** Versão exibida no rodapé (§7). */
export const VERSAO_VIRTUS = "1.0.0";

/**
 * §4/§6 — rótulo do contexto de plataforma. A UX usa **Gestão Virtus**;
 * "Admin Virtus" é reprovado automaticamente na matriz de aceite.
 */
export const CONTEXTO_PLATAFORMA = "Gestão Virtus";

/**
 * §1 — símbolo oficial. O asset versionado é soberano: a aplicação o CONSOME e
 * nunca o reconstrói em CSS/texto/SVG aproximado. `public/` é servido na raiz.
 */
export const SIMBOLO_VIRTUS = "/brand/virtus-symbol.png";
