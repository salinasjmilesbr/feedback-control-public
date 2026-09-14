/**
 * F5-10 P6 (Issue #220) — HELPERS PUROS DO PAINEL DE CICLO no domínio de METAS
 * SOBERANAS.
 *
 * Módulo COMPANHEIRO de `PainelCicloPage.tsx`: o arquivo da página exporta o
 * componente (e tipos), como exige `react-refresh/only-export-components`. Nada
 * aqui importa a página em RUNTIME — só tipos — e nenhum destes helpers decide
 * autoridade: a relação e os FATOS (`aprovacoes[].exigida`/`vigente`) vêm da
 * leitura soberana `goal.listar_por_escopo`.
 */
import type {
  MetaSoberana,
  RelacaoMetaSoberana,
} from "../application/ports/GoalRepository";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import type { CicloSoberano } from "../services/acessoCiclosSoberanos";
import type { EstadoAprovacoesPainel } from "./PainelCicloPage";

/** Papel do ator DENTRO do conjunto autorizado (vocabulário da leitura). */
export type PapelAprovadorSoberano = Extract<
  RelacaoMetaSoberana,
  `APROVADOR_${string}`
>;

/**
 * Colaboradores (UUID soberano) com ao menos UMA meta no conjunto AUTORIZADO da
 * leitura (não excluída) — a propriedade BOOLEANA que o Painel consome.
 *
 * A `relacao` diz COMO o ator está autorizado, e o MESMO colaborador pode ter
 * metas em que o ator é APROVADOR_GERENTE_CONGELADO e outras em que é
 * APROVADOR_COORDENADOR_CONGELADO: reduzir isso a "a última relação vista" era
 * uma modelagem arbitrária (achado LOW da auditoria do PR #228). Como o único
 * consumidor pergunta "existe meta autorizada deste colaborador?", modelamos
 * exatamente essa propriedade — sem escolher relação e sem decidir autorização
 * (o conjunto já vem autorizado pelo servidor).
 */
export function colaboradoresComMetaSoberana(
  metas: readonly MetaSoberana[]
): ReadonlySet<string> {
  const colaboradores = new Set<string>();
  for (const meta of metas) {
    if (meta.excluida) continue;
    colaboradores.add(meta.collaboratorId);
  }
  return colaboradores;
}

/** O item de `aprovacoes[]` do papel soberano do ator (fato da leitura). */
function aprovacaoDoPapel(meta: MetaSoberana, papel: PapelAprovadorSoberano) {
  return meta.aprovacoes.find((aprovacao) =>
    papel === "APROVADOR_GERENTE_CONGELADO"
      ? aprovacao.papel === "GERENTE"
      : aprovacao.papel === "COORDENADOR"
  );
}

/**
 * Uma meta entra no KPI "Minhas aprovações de metas" quando TODAS as condições
 * valem — todas sobre FATOS da leitura soberana, sem reconstruir regra no
 * cliente:
 *
 * 1. `meta.relacao === "SELF"` é DESCARTADO — o ator é APROVADOR CONGELADO
 *    aplicável (meta de que o ator é apenas dono não é "minha aprovação");
 * 2. a meta não está excluída logicamente;
 * 3. o colaborador NÃO está `NAO_APLICAVEL` nem `SUSPENSA` no ciclo (D6);
 * 4. o item de `aprovacoes[]` do papel correspondente tem `exigida === true` e
 *    `vigente === false` (exigida e pendente).
 */
export function metaEntraNoKpiDeAprovacoes(
  meta: MetaSoberana,
  colaboradorElegivel: (collaboratorId: string) => boolean
): boolean {
  if (meta.relacao === "SELF") return false;
  if (meta.excluida) return false;
  if (!colaboradorElegivel(meta.collaboratorId)) return false;

  const papel: PapelAprovadorSoberano = meta.relacao;
  const aprovacao = aprovacaoDoPapel(meta, papel);
  return aprovacao?.exigida === true && aprovacao.vigente === false;
}

/**
 * Contagem do KPI sobre o conjunto autorizado. A elegibilidade por
 * aplicabilidade (D6) entra por `colaboradorElegivel` — a leitura soberana não
 * projeta aplicabilidade, então o cruzamento usa a `situacao` do painel.
 */
export function contarAprovacoesPendentes(
  metas: readonly MetaSoberana[],
  colaboradorElegivel: (collaboratorId: string) => boolean
): number {
  let pendentes = 0;
  for (const meta of metas) {
    if (metaEntraNoKpiDeAprovacoes(meta, colaboradorElegivel)) pendentes += 1;
  }
  return pendentes;
}

/**
 * INDISPONIBILIDADE explícita da leitura do KPI: erro de leitura jamais pode ser
 * lido como "não há aprovação pendente" (nunca zero silencioso).
 */
export function indisponivel(
  codigo: CodigoPublico,
  mensagem: string
): EstadoAprovacoesPainel {
  return { fase: "indisponivel", codigo, mensagem };
}

/**
 * Ponte de APRESENTAÇÃO `CicloSoberano` → `CicloAvaliacao` (legado).
 *
 * `getPainelCiclo`/`getAplicabilidadeNoCiclo`/`formatarPeriodoCiclo` são
 * consumidores LEGADOS que indexam por `ano`+`numero` e leem datas/status: a
 * projeção abaixo é montada SOMENTE a partir da LINHA SOBERANA (sem
 * armazenamento do navegador, sem fallback, sem inventar período). `id` e `status` são os
 * fatos soberanos — a identidade canônica continua sendo o UUID.
 */
export function cicloLegadoDeApresentacao(ciclo: CicloSoberano) {
  return {
    id: ciclo.id,
    ano: ciclo.ano,
    ciclo: ciclo.numero,
    status: ciclo.status,
    dataCriacao: ciclo.criadoEm,
    dataUltimaAtualizacao: ciclo.atualizadoEm,
    encerradoComPendencias: ciclo.encerradoComPendencias,
    quantidadePendencias: ciclo.quantidadePendencias,
    ...(ciclo.dataInicio ? { dataInicio: ciclo.dataInicio } : {}),
    ...(ciclo.dataFim ? { dataFim: ciclo.dataFim } : {}),
    ...(ciclo.dataAtivacao ? { dataAtivacao: ciclo.dataAtivacao } : {}),
    ...(ciclo.dataEncerramento
      ? { dataEncerramento: ciclo.dataEncerramento }
      : {}),
  };
}
