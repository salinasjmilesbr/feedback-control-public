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
  if (localStorage.getItem(RESET_MARKER_KEY) === "ok") {
    return;
  }

  CHAVES_PARA_LIMPAR.forEach((chave) => {
    localStorage.removeItem(chave);
  });

  localStorage.setItem(RESET_MARKER_KEY, "ok");
}
