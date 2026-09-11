import { resetDesenvolvimentoPermitido } from "../config/ambiente";

/**
 * F5-07 — ÚNICO caminho autorizado a APAGAR chaves locais, e somente em DEV.
 *
 * `resetBaseDesenvolvimentoHabilitado` deriva de `resetDesenvolvimentoPermitido`
 * (`import.meta.env.DEV && !PROD && ambiente === "development"`), que é
 * estaticamente `false` em HOMOLOG/PROD — logo o reset é eliminado do bundle e
 * nunca é usado como fallback de produção. O único consumidor de produção é o
 * bootstrap (`src/main.tsx`), que só o chama sob esse gate; nenhuma outra
 * camada (storage, barreiras de escrita, telas) apaga chaves locais.
 * A função também revalida o gate internamente (defesa para chamadas diretas).
 */
export const resetBaseDesenvolvimentoHabilitado = resetDesenvolvimentoPermitido;

const RESET_VERSION = "2026-08-26-base-enxuta-v1";
const RESET_MARKER_KEY = `feedback-control-reset-${RESET_VERSION}`;

const CHAVES_PARA_LIMPAR = [
  "feedback-control-colaboradores",
  "feedback-control-feedbacks",
  "feedback-control-observacoes",
  "feedback-control-metas",
  "feedback-control-ciclos",
  "feedback-control-usuario-atual",
];

export function executarResetBaseDesenvolvimento(): void {
  // Protege também chamadas diretas fora do bootstrap, antes de acessar dados.
  if (!resetBaseDesenvolvimentoHabilitado) return;

  if (localStorage.getItem(RESET_MARKER_KEY) === "ok") {
    return;
  }

  CHAVES_PARA_LIMPAR.forEach((chave) => {
    localStorage.removeItem(chave);
  });

  localStorage.setItem(RESET_MARKER_KEY, "ok");
}
