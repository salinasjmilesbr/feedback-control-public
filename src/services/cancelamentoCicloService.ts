import { authorize } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { Colaborador } from "../types/Colaborador";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import {
  getCiclosAvaliacao,
  persistirCancelamentoCicloAuditadoInterno,
} from "./cicloAvaliacaoStorage";

export function cancelarCiclo(
  cicloId: string,
  motivoInformado: string,
  autor: Colaborador
): CicloAvaliacao {
  const motivo = motivoInformado.trim();
  if (!motivo) throw new Error("Informe o motivo do cancelamento do ciclo.");

  const ciclo = getCiclosAvaliacao().find((item) => item.id === cicloId);
  if (!ciclo) throw new Error("Ciclo não encontrado.");

  const context: AuthorizationContext = {
    actor: {
      matricula: autor.matricula,
      funcao: autor.funcao,
      status: autor.status,
    },
  };
  authorize(context, "cycle.cancel.manager", { kind: "cycle", cycle: ciclo });

  return persistirCancelamentoCicloAuditadoInterno(
    ciclo.id,
    motivo,
    autor.matricula,
    autor.nome,
    new Date().toISOString()
  );
}
