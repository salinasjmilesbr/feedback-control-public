import { authorize } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import {
  getCiclosAvaliacao,
  persistirReaberturaCicloAuditadaInterno,
} from "./cicloAvaliacaoStorage";

export function reabrirCiclo(
  cicloId: string,
  motivoInformado: string,
  autor: Colaborador
): CicloAvaliacao {
  const motivo = motivoInformado.trim();
  if (!motivo) throw new Error("Informe o motivo da reabertura do ciclo.");

  const ciclo = getCiclosAvaliacao().find((item) => item.id === cicloId);
  if (!ciclo) throw new Error("Ciclo não encontrado.");

  const context: AuthorizationContext = {
    actor: {
      matricula: autor.matricula,
      funcao: autor.funcao,
      status: autor.status,
    },
  };
  authorize(context, "cycle.reopen.manager", { kind: "cycle", cycle: ciclo });

  return persistirReaberturaCicloAuditadaInterno(
    ciclo.id,
    motivo,
    autor.matricula,
    autor.nome,
    new Date().toISOString()
  );
}
