import type { FuncaoColaborador } from "../types/Colaborador";

const PERFIS_COM_FLUXOS_PROPRIOS = new Set<FuncaoColaborador>([
  "COORDENADOR",
  "CONSULTOR",
  "ANALISTA",
  "ESTAGIARIO",
]);

export function perfilPossuiFluxosPropriosAtuais(
  funcao: FuncaoColaborador | undefined
): boolean {
  return funcao !== undefined && PERFIS_COM_FLUXOS_PROPRIOS.has(funcao);
}
