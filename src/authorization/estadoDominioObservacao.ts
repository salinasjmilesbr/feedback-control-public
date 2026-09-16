import type { Capability } from "./Capability.ts";
import type { DomainStateProbe } from "./policyEngine/types.ts";

/**
 * F5-11 P3/P4 (§8; D5, D11, D12) — ESTADO DE DOMÍNIO do recurso OBSERVAÇÃO.
 *
 * O Policy Engine decide **QUEM** pode agir (identidade, membership, capability,
 * escopo e relação); este módulo declara **SE** a ação é possível no estado atual
 * do recurso. É a ÚNICA declaração dessa matriz para a observação: o adaptador de
 * compatibilidade (`authorizationPolicy.ts`) e a **fronteira soberana**
 * (`contextoAutorizacao.ts`, consumida pela Edge) derivam o probe DESTA fonte — a
 * matriz não é duplicada em nenhum dos dois caminhos.
 *
 * A P3 declarou a matriz dentro de `authorizationPolicy.ts`; a P4 a EXTRAIU para
 * este módulo **sem mudança de semântica** porque a fronteira confiável (Edge
 * Function, runtime Deno) precisa consumi-la: `authorizationPolicy.ts` importa
 * `config/ambiente` (`import.meta.env` no topo) e serviços do cliente, e
 * trazê-los ao grafo da Edge quebraria a fronteira. Este módulo só depende de
 * tipos do Policy Engine — como `estadoDominioMeta.ts`/`estadoDominioCiclo.ts`.
 *
 * Matriz contratada (§8; D11/D12) — fonte única:
 *
 * | capability           | exige                                                       |
 * | `observation.create` | ciclo `ATIVO` **e** colaborador-alvo ≠ `DESLIGADO` (D11)     |
 * | `observation.edit`   | ciclo `ATIVO` (editar, comunicar/descomunicar e revogar)     |
 * | `observation.delete` | ciclo `ATIVO`                                                |
 * | `observation.read`   | nada — leitura histórica em QUALQUER estado                  |
 *
 * `LICENCA` **permite** criar (paridade com `authorizationPolicy.test.ts` e com
 * §7.9). Capability fora da matriz ⇒ NEGADO (`default: false`, fail-closed).
 *
 * O que NÃO é estado e por isso NÃO entra aqui: a **autoria** D5
 * (`exigeAutoriaObservacao` a sinaliza para o chamador compor) e a regra de
 * **leitura SELF-comunicada** (D7/D9), que dependem de fatos da LINHA soberana
 * comparados ao ator e são compostas na fronteira.
 */

/** Status de colaborador que impede NOVA observação (D11; `inactive` do §7.9). */
const STATUS_COLABORADOR_INATIVO = "DESLIGADO";

/** Projeção mínima do estado REAL do recurso OBSERVAÇÃO consumida pelo probe. */
export interface EstadoObservacaoSoberano {
  /** Status da LINHA do ciclo da observação (`ATIVO` libera mutação — D12). */
  readonly cicloStatus?: string | null;
  /** Status do colaborador-ALVO da observação (D11). */
  readonly colaboradorStatus?: string | null;
}

function statusNormalizado(valor: unknown): string {
  return typeof valor === "string" ? valor.trim().toUpperCase() : "";
}

/**
 * §8 (D5/D7): capabilities de observação que exigem que o ATOR seja o AUTOR do
 * recurso. Editar, marcar/desmarcar comunicado e revogar a exclusão são
 * `observation.edit`; excluir é `observation.delete`. Criar e ler não exigem
 * autoria (quem cria passa a ser o autor; a leitura tem matriz própria).
 */
export function exigeAutoriaObservacao(capability: Capability): boolean {
  return capability === "observation.edit" || capability === "observation.delete";
}

/**
 * Probe de domínio do recurso OBSERVAÇÃO. Capability desconhecida ⇒ NEGADO: o
 * probe nunca libera uma ação que não esteja na matriz.
 */
export function estadoDominioObservacao(entrada: EstadoObservacaoSoberano): DomainStateProbe {
  const cicloAtivo = statusNormalizado(entrada?.cicloStatus) === "ATIVO";
  const colaboradorInativo =
    statusNormalizado(entrada?.colaboradorStatus) === STATUS_COLABORADOR_INATIVO;

  return {
    allows: (capability: Capability): boolean => {
      switch (capability) {
        case "observation.create":
          return cicloAtivo && !colaboradorInativo;
        case "observation.edit":
        case "observation.delete":
          return cicloAtivo;
        case "observation.read":
          return true;
        default:
          return false;
      }
    },
  };
}
