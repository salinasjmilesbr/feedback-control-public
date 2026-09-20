import type { CSSProperties, ReactNode } from "react";
import AuthStatus from "../../auth/AuthStatus";
import MarcaVirtus from "./MarcaVirtus";
import {
  CONTEXTO_PLATAFORMA,
  TAGLINE_VIRTUS,
  VERSAO_VIRTUS,
} from "./identidadeVirtus";
import "../../styles/virtus-shell.css";

/**
 * Issue #317 (Fase 2) — SHELL UNIVERSAL (header + conteúdo + footer).
 *
 * O contexto é **explícito**, nunca inferido de `organizacaoAtivaId`: um
 * operador da plataforma pode ter organização ativa na sessão, e inferir o
 * contexto faria o branding do cliente pintar a Gestão Virtus (§5, reprovação
 * automática na matriz de aceite).
 *
 * Garantias de segregação:
 * - `contexto="plataforma"` ⇒ identidade Virtus fixa e mapa de tema **ignorado
 *   por construção** (fail-closed): mesmo que um chamador passe `tema`, nada é
 *   aplicado;
 * - `contexto="empresa"` ⇒ o mapa de custom properties do TENANT é aplicado
 *   **somente no container do shell** (`style` inline neste `<div>`), jamais em
 *   `documentElement`/`body` — é o que impede o vazamento entre tenants e para a
 *   plataforma no mesmo navegador;
 * - a plataforma NÃO recebe navegação funcional nem estrutura soberana de tenant
 *   (D19/D21): o shell é uma moldura; `acoes`/`navegacao` são injetados por quem
 *   monta o layout, e o layout de plataforma não injeta nada de tenant.
 */
export type ContextoShell = "plataforma" | "empresa";

type ShellVirtusProps = {
  contexto: ContextoShell;
  /** `[empresa]` do header (§6). Ignorado no contexto de plataforma. */
  nomeEmpresa?: string;
  /**
   * Custom properties do TENANT (`temaDoTenant`). Vazio/ausente no contexto de
   * plataforma — e ignorado se enviado por engano.
   */
  tema?: Readonly<Record<string, string>>;
  /** Controles do contexto (ex.: seletor de organização/DEV), injetados pelo layout. */
  acoes?: ReactNode;
  /** Navegação funcional do produto (não existe na plataforma — D21). */
  navegacao?: ReactNode;
  children: ReactNode;
};

function ShellVirtus({
  contexto,
  nomeEmpresa,
  tema,
  acoes,
  navegacao,
  children,
}: ShellVirtusProps) {
  const plataforma = contexto === "plataforma";

  // Sem nome de empresa não há rótulo: nunca repetir a marca ("VIRTUS · VIRTUS").
  const rotuloContexto = plataforma
    ? CONTEXTO_PLATAFORMA
    : nomeEmpresa?.trim() || undefined;

  // Fail-closed: a plataforma nunca carrega custom properties de tenant.
  const estiloDoContainer = plataforma
    ? undefined
    : (tema as CSSProperties | undefined);

  return (
    <div
      className="virtus-shell"
      data-contexto={contexto}
      style={estiloDoContainer}
    >
      <header className="virtus-shell__header">
        <div className="virtus-shell__header-inner">
          <MarcaVirtus contexto={rotuloContexto} />
          <div className="virtus-shell__actions">
            {acoes}
            <AuthStatus />
          </div>
        </div>
      </header>

      {navegacao}

      <main className="app-main virtus-shell__main">{children}</main>

      <footer className="virtus-shell__footer">
        <div className="virtus-shell__footer-inner">
          <MarcaVirtus contexto={TAGLINE_VIRTUS} />
          <span className="virtus-shell__version">Versão {VERSAO_VIRTUS}</span>
        </div>
      </footer>
    </div>
  );
}

export default ShellVirtus;
