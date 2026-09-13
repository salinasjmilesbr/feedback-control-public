/**
 * F5-09 P7 (Issue #202) — contrato TRANSPORTÁVEL do caminho soberano de CICLOS.
 *
 * Fonte ÚNICA da superfície que o cliente pode pedir, do GATE de cada operação
 * (§8/D19/D21) e da FORMA do corpo aceito (nunca autoridade). É importado pela
 * Edge Function (`supabase/functions/ciclos`) e pelo adapter de cliente
 * (`src/infrastructure/supabase/ciclos/edgeCiclos.ts`), como o contrato da
 * F5-06/F5-08 — nenhuma cópia da lista de operações em nenhum dos lados.
 *
 * Invariantes (D20/D21/D25/D26/§13.1):
 * - o corpo carrega apenas INTENÇÃO: operação, alvo (UUID), versão esperada,
 *   datas, motivo e `operationId`;
 * - `organization_id` é intenção REVALIDA DA contra membership ativa — nunca
 *   autoridade de tenant;
 * - `actorId`/`authorId`/`userId` do corpo NUNCA definem autoria (o ator é
 *   `auth.uid` verificado na fronteira); enviá-los é `INVALID_INPUT`;
 * - `status`, `capability`, `role`, `cargo`/`funcao`/`papel` textuais NÃO fazem
 *   parte do contrato: o estado do ciclo vem da LINHA SOBERANA (P5/P6) e a
 *   autorização vem do Policy Engine;
 * - campos ESTRUTURAIS (posição, unidade, gestor, reporting line, colegiado,
 *   `reference_date`, lista de colaboradores) são RECUSADOS (§13.1 regra 9): a
 *   estrutura de uma admissão é resolvida server-side na RPC;
 * - `payload_hash` NÃO é parâmetro: os RPCs derivam o hash canônico server-side
 *   (desvio já declarado e aceito nas fases P2–P4).
 *
 * O que este módulo NÃO faz: lifecycle de ciclo, validação de versão,
 * sobreposição de período, unicidade de ATIVO, transação, materialização ou
 * autoria. Tudo isso pertence às RPCs PostgreSQL (§13.3) — a Edge apenas
 * autentica, autoriza e executa.
 */

/** Códigos públicos (F0-05) — a mensagem crua do banco nunca chega ao cliente. */
export type CodigoPublico =
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "INVALID_INPUT"
  | "INTERNAL"
  | "NOT_AUTHORIZED"
  | "METHOD_NOT_ALLOWED";

/** Operações contratadas da F5-09 (todas com RPC soberana já existente). */
export type OperacaoCiclo =
  | "cycle.criar"
  | "cycle.editar"
  | "cycle.ativar"
  | "cycle.encerrar"
  | "cycle.cancelar"
  | "cycle.reabrir"
  | "cycle.corrigir_periodo"
  | "cycle.admissao.incluir";

/**
 * Gate da operação (§8):
 * - `funcional`: Policy Engine com recurso REAL (`{type:"cycle", id: UUID}`) e
 *   `domainState` derivado do status da linha soberana (P6);
 * - `administrativo`: plano administrativo (F5-04 D19) — a capability efetiva do
 *   ator na organização, sem alvo no engine (o ciclo ainda não existe — D21).
 */
export type TipoGate = "funcional" | "administrativo";

export interface DefinicaoOperacaoCiclo {
  readonly gate: TipoGate;
  /** Capability CANÔNICA exigida (nenhuma capability nova — D20). */
  readonly capability: string;
}

/**
 * Mapa EXPLÍCITO operação → gate/capability, sem fallback: operação fora deste
 * mapa é recusada antes de qualquer decisão (fail-closed).
 */
export const DEFINICAO_POR_OPERACAO: Readonly<
  Record<OperacaoCiclo, DefinicaoOperacaoCiclo>
> = {
  // D21: a criação é ADMINISTRATIVA — o recurso ainda não existe e alvo
  // sintético é proibido como prova de autorização (F5-05 D19/D22).
  "cycle.criar": { gate: "administrativo", capability: "cycle.manage" },
  "cycle.editar": { gate: "funcional", capability: "cycle.manage" },
  "cycle.ativar": { gate: "funcional", capability: "cycle.manage" },
  "cycle.encerrar": { gate: "funcional", capability: "cycle.manage" },
  "cycle.admissao.incluir": { gate: "funcional", capability: "cycle.manage" },
  // Fluxos excepcionais: capabilities próprias, fora do bundle `admin` (D28).
  "cycle.cancelar": { gate: "funcional", capability: "cycle.cancel" },
  "cycle.reabrir": { gate: "funcional", capability: "cycle.reopen" },
  "cycle.corrigir_periodo": { gate: "funcional", capability: "cycle.period.correct" },
};

export const OPERACOES_CICLO: readonly OperacaoCiclo[] = Object.keys(
  DEFINICAO_POR_OPERACAO
) as readonly OperacaoCiclo[];

export function ehOperacaoCiclo(valor: unknown): valor is OperacaoCiclo {
  return typeof valor === "string" && (OPERACOES_CICLO as readonly string[]).includes(valor);
}

export function ehOperacaoFuncional(operacao: OperacaoCiclo): boolean {
  return DEFINICAO_POR_OPERACAO[operacao].gate === "funcional";
}

/**
 * Capability exigida no plano ADMINISTRATIVO (D19). Operação que não seja
 * administrativa devolve `null` e o chamador NEGA (sem capability por default).
 */
export function capacidadeAdministrativaDaOperacao(operacao: OperacaoCiclo): string | null {
  const definicao = DEFINICAO_POR_OPERACAO[operacao];
  return definicao && definicao.gate === "administrativo" ? definicao.capability : null;
}

/** Intenção já validada em FORMA (nunca autoridade). */
export interface EntradaCiclo {
  readonly organization_id: string;
  readonly operacao: OperacaoCiclo;
  readonly operation_id: string;
  readonly cycle_id?: string;
  readonly ano?: number;
  readonly numero?: number;
  readonly data_inicio?: string;
  readonly data_fim?: string;
  readonly expected_version?: number;
  readonly motivo?: string;
  readonly justificativa?: string;
  /** Admissão: UUID do colaborador (preferencial) ou matrícula (intenção). */
  readonly collaborator_id?: string;
  readonly matricula?: number | string;
}

export type ValidacaoEntradaCiclo =
  | { readonly ok: true; readonly entrada: EntradaCiclo }
  | { readonly ok: false; readonly code: CodigoPublico; readonly message: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATA_ISO = /^\d{4}-\d{2}-\d{2}$/;
const LIMITE_TEXTO = 500;

function ehUuid(valor: unknown): valor is string {
  return typeof valor === "string" && UUID.test(valor.trim());
}

function ehInteiro(valor: unknown): valor is number {
  return typeof valor === "number" && Number.isInteger(valor);
}

/** Data `YYYY-MM-DD` REAL (recusa 2026-02-30 e afins). */
function ehDataCivil(valor: unknown): valor is string {
  if (typeof valor !== "string" || !DATA_ISO.test(valor)) return false;
  const convertida = new Date(`${valor}T00:00:00Z`);
  return !Number.isNaN(convertida.getTime()) && convertida.toISOString().slice(0, 10) === valor;
}

function textoObrigatorio(valor: unknown): string | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  if (limpo.length === 0 || limpo.length > LIMITE_TEXTO) return null;
  return limpo;
}

/**
 * Chaves aceitas por operação. Allowlist ESTRITA: qualquer chave fora dela —
 * `actorId`, `authorId`, `status`, `capability`, `role`, `cargo`, `funcao`,
 * `papel`, `posicao_id`, `unidade_id`, `gestor_id`, `reference_date`,
 * `collaborator_ids` etc. — é `INVALID_INPUT`. Forma nunca é autoridade.
 */
const CHAVES_COMUNS = ["organization_id", "operacao", "operation_id"] as const;

const CHAVES_POR_OPERACAO: Readonly<Record<OperacaoCiclo, readonly string[]>> = {
  "cycle.criar": [...CHAVES_COMUNS, "ano", "numero", "data_inicio", "data_fim"],
  "cycle.editar": [
    ...CHAVES_COMUNS,
    "cycle_id",
    "ano",
    "numero",
    "data_inicio",
    "data_fim",
    "expected_version",
  ],
  "cycle.ativar": [...CHAVES_COMUNS, "cycle_id", "expected_version"],
  "cycle.encerrar": [...CHAVES_COMUNS, "cycle_id", "expected_version", "motivo"],
  "cycle.cancelar": [...CHAVES_COMUNS, "cycle_id", "expected_version", "motivo"],
  "cycle.reabrir": [...CHAVES_COMUNS, "cycle_id", "expected_version", "motivo"],
  "cycle.corrigir_periodo": [
    ...CHAVES_COMUNS,
    "cycle_id",
    "data_inicio",
    "data_fim",
    "justificativa",
    "expected_version",
  ],
  // §13.1 regra 9: a ÚNICA ampliação de população de um ciclo ATIVO. Aceita o
  // UUID do colaborador OU a matrícula (intenção resolvida na fronteira, F3-01)
  // — jamais qualquer campo estrutural.
  "cycle.admissao.incluir": [
    ...CHAVES_COMUNS,
    "cycle_id",
    "expected_version",
    "motivo",
    "collaborator_id",
    "matricula",
  ],
};

function invalido(message: string): ValidacaoEntradaCiclo {
  return { ok: false, code: "INVALID_INPUT", message };
}

function exigirUuid(entrada: Record<string, unknown>, chave: string): string | null {
  return ehUuid(entrada[chave]) ? (entrada[chave] as string).trim() : null;
}

/**
 * Valida a FORMA da intenção (nunca a autoridade). Fail-closed: qualquer campo
 * desconhecido, identidade no corpo, UUID malformado, data impossível, versão
 * ausente ou motivo vazio ⇒ `INVALID_INPUT`.
 */
export function validarEntradaCiclo(corpo: unknown): ValidacaoEntradaCiclo {
  if (typeof corpo !== "object" || corpo === null || Array.isArray(corpo)) {
    return invalido("Corpo da requisição inválido.");
  }
  const bruto = corpo as Record<string, unknown>;

  if (!ehOperacaoCiclo(bruto.operacao)) {
    return invalido("Operação de ciclo não suportada.");
  }
  const operacao = bruto.operacao;

  const permitidas = CHAVES_POR_OPERACAO[operacao];
  const desconhecidas = Object.keys(bruto).filter((chave) => !permitidas.includes(chave));
  if (desconhecidas.length > 0) {
    return invalido(`Campo não aceito nesta operação: ${desconhecidas.sort().join(", ")}.`);
  }

  const organizationId = exigirUuid(bruto, "organization_id");
  if (!organizationId) return invalido("organization_id inválido.");
  const operationId = exigirUuid(bruto, "operation_id");
  if (!operationId) return invalido("operation_id inválido.");

  const entrada: Record<string, unknown> = {
    organization_id: organizationId,
    operacao: operacao,
    operation_id: operationId,
  };

  // Alvo de ciclo existente: SEMPRE UUID canônico (`evaluation_cycles.id`).
  if (operacao !== "cycle.criar") {
    const cycleId = exigirUuid(bruto, "cycle_id");
    if (!cycleId) return invalido("cycle_id inválido.");
    entrada.cycle_id = cycleId;

    const versao = bruto.expected_version;
    if (!ehInteiro(versao) || versao < 0) return invalido("expected_version inválido.");
    entrada.expected_version = versao;
  }

  switch (operacao) {
    case "cycle.criar": {
      const ano = bruto.ano;
      const numero = bruto.numero;
      if (!ehInteiro(ano) || ano < 2000 || ano > 2100) return invalido("ano inválido.");
      if (!ehInteiro(numero) || numero < 1 || numero > 3) return invalido("numero inválido.");
      if (!ehDataCivil(bruto.data_inicio) || !ehDataCivil(bruto.data_fim)) {
        return invalido("data_inicio/data_fim inválidas.");
      }
      entrada.ano = ano;
      entrada.numero = numero;
      entrada.data_inicio = bruto.data_inicio;
      entrada.data_fim = bruto.data_fim;
      break;
    }
    case "cycle.editar": {
      // A RPC `ciclo_editar` recebe o estado COMPLETO do período (não há edição
      // parcial): a fronteira exige todos os campos e não faz merge de domínio.
      const ano = bruto.ano;
      const numero = bruto.numero;
      if (!ehInteiro(ano) || ano < 2000 || ano > 2100) return invalido("ano inválido.");
      if (!ehInteiro(numero) || numero < 1 || numero > 3) return invalido("numero inválido.");
      if (!ehDataCivil(bruto.data_inicio) || !ehDataCivil(bruto.data_fim)) {
        return invalido("data_inicio/data_fim inválidas.");
      }
      entrada.ano = ano;
      entrada.numero = numero;
      entrada.data_inicio = bruto.data_inicio;
      entrada.data_fim = bruto.data_fim;
      break;
    }
    case "cycle.ativar":
      break;
    case "cycle.encerrar":
    case "cycle.cancelar":
    case "cycle.reabrir": {
      const motivo = textoObrigatorio(bruto.motivo);
      if (!motivo) return invalido("motivo obrigatório.");
      entrada.motivo = motivo;
      break;
    }
    case "cycle.corrigir_periodo": {
      if (!ehDataCivil(bruto.data_inicio) || !ehDataCivil(bruto.data_fim)) {
        return invalido("data_inicio/data_fim inválidas.");
      }
      const justificativa = textoObrigatorio(bruto.justificativa);
      if (!justificativa) return invalido("justificativa obrigatória.");
      entrada.data_inicio = bruto.data_inicio;
      entrada.data_fim = bruto.data_fim;
      entrada.justificativa = justificativa;
      break;
    }
    case "cycle.admissao.incluir": {
      const motivo = textoObrigatorio(bruto.motivo);
      if (!motivo) return invalido("motivo obrigatório.");
      entrada.motivo = motivo;

      const temUuid = bruto.collaborator_id !== undefined && bruto.collaborator_id !== null;
      const temMatricula = bruto.matricula !== undefined && bruto.matricula !== null;
      if (temUuid === temMatricula) {
        return invalido("Informe collaborator_id (UUID) ou matricula — exatamente um.");
      }
      if (temUuid) {
        const colaboradorId = exigirUuid(bruto, "collaborator_id");
        if (!colaboradorId) return invalido("collaborator_id inválido.");
        entrada.collaborator_id = colaboradorId;
      } else {
        const matricula = bruto.matricula;
        const valida =
          (typeof matricula === "number" && Number.isInteger(matricula) && matricula > 0) ||
          (typeof matricula === "string" &&
            matricula.trim().length > 0 &&
            matricula.trim().length <= 40);
        if (!valida) return invalido("matricula inválida.");
        entrada.matricula = typeof matricula === "string" ? matricula.trim() : matricula;
      }
      break;
    }
  }

  return { ok: true, entrada: entrada as unknown as EntradaCiclo };
}
