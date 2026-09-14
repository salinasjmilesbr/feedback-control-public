/**
 * F5-10 P6 (Issue #220) — PONTE DE APRESENTAÇÃO do ciclo LEGADO, ISOLADA.
 *
 * As telas desta atividade resolvem o ciclo FUNCIONAL pelo UUID soberano
 * (`acessoCiclosSoberanos`, leitura por RLS). O que ainda é legado é apenas
 * RÓTULO de apresentação — o período formatado e a lista local usada para casar
 * `ano`/`numero` com o rótulo exibido — e é isso que este módulo isola.
 *
 * Este módulo NÃO importa o caminho soberano de ciclos: ele não decide
 * identidade, não é autoridade e não pode servir de fallback. O isolamento é o
 * que a guarda anti-dual-read (`src/services/ciclosSoberanosSemFallback.test.ts`)
 * exige de quem importa o caminho soberano.
 */
export {
  formatarPeriodoCiclo,
  getCiclosAvaliacao,
} from "../services/cicloAvaliacaoStorage";