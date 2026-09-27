import type { SupabaseClient } from "@supabase/supabase-js";

export type EscopoRelatorioSoberano = "DESCENDANTS";
export interface LinhaRelatorioSoberano { readonly collaboratorId: string; readonly nome: string; readonly positionId: string; readonly status: string | null; readonly evaluationId: string | null; readonly evaluationStatus: string | null; readonly notaMedia: number | null; readonly dataConclusao: string | null; }
export interface RelatorioSoberano { readonly organizationId: string; readonly cycleId: string; readonly scope: EscopoRelatorioSoberano; readonly colaboradores: readonly LinhaRelatorioSoberano[]; }
export type ResultadoRelatorioSoberano = { readonly ok: true; readonly data: RelatorioSoberano } | { readonly ok: false; readonly code: "FORBIDDEN" | "NOT_FOUND" | "INTERNAL" | "INVALID_INPUT"; readonly message: string };
const MENSAGEM_FALHA = "Não foi possível carregar o relatório soberano.";
function texto(valor: unknown): string | null { return typeof valor === "string" && valor.length > 0 ? valor : null; }
function linha(valor: unknown): LinhaRelatorioSoberano | null {
  if (typeof valor !== "object" || valor === null || Array.isArray(valor)) return null;
  const bruto = valor as Record<string, unknown>;
  const collaboratorId = texto(bruto.collaboratorId); const nome = texto(bruto.nome); const positionId = texto(bruto.positionId);
  if (!collaboratorId || !nome || !positionId) return null;
  return { collaboratorId, nome, positionId, status: texto(bruto.status), evaluationId: texto(bruto.evaluationId), evaluationStatus: texto(bruto.evaluationStatus), notaMedia: typeof bruto.notaMedia === "number" ? bruto.notaMedia : null, dataConclusao: texto(bruto.dataConclusao) };
}
export function criarRepositorioRelatoriosSoberanos(cliente: SupabaseClient) {
  return { async listar(organizationId: string, cycleId: string): Promise<ResultadoRelatorioSoberano> {
    if (!organizationId || !cycleId) return { ok: false, code: "INVALID_INPUT", message: "Organização e ciclo são obrigatórios." };
    try {
      const { data, error } = await cliente.functions.invoke("avaliacoes", { body: { organization_id: organizationId, operacao: "report.listar", cycle_id: cycleId } });
      if (error || typeof data !== "object" || data === null) return { ok: false, code: "INTERNAL", message: MENSAGEM_FALHA };
      const envelope = data as Record<string, unknown>;
      if (envelope.ok !== true || envelope.operacao !== "report.listar" || typeof envelope.resultado !== "object" || envelope.resultado === null || Array.isArray(envelope.resultado)) {
        return { ok: false, code: "INTERNAL", message: MENSAGEM_FALHA };
      }
      const bruto = envelope.resultado as Record<string, unknown>; const organization = texto(bruto.organizationId); const cycle = texto(bruto.cycleId); const scope = bruto.scope;
      const linhas = Array.isArray(bruto.colaboradores) ? bruto.colaboradores.map(linha).filter((item): item is LinhaRelatorioSoberano => item !== null) : null;
      if (!organization || !cycle || scope !== "DESCENDANTS" || linhas === null) return { ok: false, code: "INTERNAL", message: MENSAGEM_FALHA };
      if (organization !== organizationId || cycle !== cycleId) return { ok: false, code: "FORBIDDEN", message: MENSAGEM_FALHA };
      return { ok: true, data: { organizationId: organization, cycleId: cycle, scope, colaboradores: linhas } };
    } catch { return { ok: false, code: "INTERNAL", message: MENSAGEM_FALHA }; }
  } };
}
