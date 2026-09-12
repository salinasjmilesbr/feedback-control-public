import type { Capability } from "./Capability.ts";
import type { DomainStateProbe } from "./policyEngine/types.ts";

/**
 * F5-09 P6 (§8, D8, D20, D21) — ESTADO DE DOMÍNIO do recurso CICLO.
 *
 * O Policy Engine decide **QUEM** pode agir (identidade, membership, capability
 * efetiva, scope e relação); este módulo declara **SE** a ação é possível no
 * estado atual do ciclo. É a ÚNICA declaração dessa condição para o recurso
 * `cycle`: o adaptador de compatibilidade (`authorizationPolicy.ts`) e a
 * fronteira soberana (`contextoAutorizacao.ts`) consomem este mesmo probe — a
 * matriz não é duplicada em nenhum dos dois caminhos.
 *
 * Matriz contratada (§8 do desenho técnico; Q-F5-09-1 ratificada → D8):
 *
 * | capability             | estados que PERMITEM                        |
 * | `cycle.read`           | ciclo real carregado (qualquer status)      |
 * | `cycle.manage`         | `PLANEJADO`, `ATIVO`                        |
 * | `cycle.cancel`         | `PLANEJADO`, `ATIVO` (ampliação de D8)      |
 * | `cycle.reopen`         | `ENCERRADO`                                 |
 * | `cycle.period.correct` | `ATIVO`                                     |
 *
 * `cycle.manage` cobre operações com recortes de estado DIFERENTES no §8
 * (editar/ativar = `PLANEJADO`; encerrar/admitir = `ATIVO`). O engine só recebe
 * a CAPABILITY, então o probe declara a UNIÃO contratada (`PLANEJADO` ou
 * `ATIVO`) e o recorte por OPERAÇÃO continua sendo revalidado na RPC soberana
 * (P2–P4), que é o enforcement em profundidade do §8 — nenhuma operação passa a
 * ser permitida por essa união: a RPC recusa o estado incompatível.
 *
 * `CANCELADO` é terminal (D8): nega `manage`/`cancel`/`reopen`/`period.correct`.
 * A LEITURA permanece permitida (sujeita a capability/scope/tenant), porque
 * transparência de histórico não é mutação.
 *
 * Estado AUSENTE ou fora do domínio fechado ⇒ probe nega TUDO (fail-closed): um
 * recurso sem status real não é um recurso carregado de fonte soberana.
 */

/** Status do domínio fechado de ciclo (CHECK da F5-09 P1). */
export const STATUS_CICLO_CONHECIDOS = [
  "PLANEJADO",
  "ATIVO",
  "ENCERRADO",
  "CANCELADO",
] as const;

export type StatusCiclo = (typeof STATUS_CICLO_CONHECIDOS)[number];

/** Projeção mínima consumida pelo probe: o status REAL do recurso. */
export interface EstadoCicloSoberano {
  readonly status: string;
}

/** Normaliza o status (trim + maiúsculas) ou `null` quando fora do domínio. */
export function statusCicloConhecido(valor: unknown): StatusCiclo | null {
  if (typeof valor !== "string") return null;
  const normalizado = valor.trim().toUpperCase();
  return (STATUS_CICLO_CONHECIDOS as readonly string[]).includes(normalizado)
    ? (normalizado as StatusCiclo)
    : null;
}

/** `PLANEJADO` ou `ATIVO` — estados que admitem gestão/cancelamento (§8/D8). */
export function cicloGerenciavel(entrada: EstadoCicloSoberano): boolean {
  const status = statusCicloConhecido(entrada?.status);
  return status === "PLANEJADO" || status === "ATIVO";
}

/** Somente `ENCERRADO` pode ser reaberto (T6). */
export function cicloReabrivel(entrada: EstadoCicloSoberano): boolean {
  return statusCicloConhecido(entrada?.status) === "ENCERRADO";
}

/** Somente `ATIVO` tem período corrigível (T7). */
export function cicloPeriodoCorrigivel(entrada: EstadoCicloSoberano): boolean {
  return statusCicloConhecido(entrada?.status) === "ATIVO";
}

/** Ciclo REAL carregado: status dentro do domínio fechado (qualquer um deles). */
export function cicloExistente(entrada: EstadoCicloSoberano): boolean {
  return statusCicloConhecido(entrada?.status) !== null;
}

/**
 * Probe de domínio do recurso CICLO. Capability desconhecida ⇒ NEGADO: o probe
 * nunca libera uma ação que não esteja na matriz.
 */
export function estadoDominioCiclo(entrada: EstadoCicloSoberano): DomainStateProbe {
  const estado: EstadoCicloSoberano = { status: entrada?.status ?? "" };
  return {
    allows: (capability: Capability): boolean => {
      switch (capability) {
        case "cycle.read":
          return cicloExistente(estado);
        case "cycle.manage":
        case "cycle.cancel":
          return cicloGerenciavel(estado);
        case "cycle.reopen":
          return cicloReabrivel(estado);
        case "cycle.period.correct":
          return cicloPeriodoCorrigivel(estado);
        default:
          return false;
      }
    },
  };
}
