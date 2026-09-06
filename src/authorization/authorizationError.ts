import type { Capability } from "./Capability";
import { ApplicationError } from "../errors/applicationErrors";
import type { ApplicationErrorOptions } from "../errors/applicationErrors";

export class AuthorizationError extends ApplicationError<"FORBIDDEN"> {
  readonly capability: Capability;

  constructor(capability: Capability, options?: ApplicationErrorOptions) {
    super("FORBIDDEN", options, `Operação não permitida: ${capability}`);
    this.name = "AuthorizationError";
    this.capability = capability;
  }
}
