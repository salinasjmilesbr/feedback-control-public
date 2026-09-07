import {
  ConflictError,
  ForbiddenError,
  NotFoundError,
} from "../../errors/applicationErrors";
import type { DenialReason } from "./types";

/**
 * Mapeia razões internas de negação para códigos públicos F0-05 (D6).
 *
 * Razões internas permanecem internas; o frontend só recebe o código público
 * (e a mensagem do catálogo F0-05). Cross-tenant vira NOT_FOUND para não
 * revelar a existência do recurso.
 */
export function codigoPublicoDeNegacao(reason: DenialReason):
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT" {
  switch (reason) {
    case "CROSS_TENANT":
    case "TARGET_INVALID":
      return "NOT_FOUND";
    case "DOMAIN_STATE_INVALID":
      return "CONFLICT";
    case "NO_IDENTITY":
    case "PROFILE_DISABLED":
    case "MEMBERSHIP_INVALID":
    case "CAPABILITY_MISSING":
    case "SCOPE_INSUFFICIENT":
    case "INDETERMINATE":
      return "FORBIDDEN";
  }
}

/** Converte uma negação em erro público F0-05 (usado por authorize). */
export function erroDeNegacao(reason: DenialReason): Error {
  const code = codigoPublicoDeNegacao(reason);
  if (code === "NOT_FOUND") return new NotFoundError();
  if (code === "CONFLICT") return new ConflictError();
  return new ForbiddenError();
}
