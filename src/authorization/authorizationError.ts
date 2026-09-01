import type { Capability } from "./Capability";

export class AuthorizationError extends Error {
  readonly code = "FORBIDDEN";
  readonly capability: Capability;

  constructor(capability: Capability) {
    super(`Operação não permitida: ${capability}`);
    this.name = "AuthorizationError";
    this.capability = capability;
  }
}
