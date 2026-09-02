import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type {
  EscopoMovimentacaoOrganizacional,
  MovimentacaoOrganizacional,
  SnapshotOrganizacional,
  TipoMovimentacaoOrganizacional,
} from "../types/HistoricoOrganizacional";
import { getCicloAtivo, getCiclosAvaliacao } from "./cicloAvaliacaoStorage";

const STORAGE_KEY = "feedback-control-historico-organizacional";

function lerTodas(): MovimentacaoOrganizacional[] {
  const data = localStorage.getItem(STORAGE_KEY);
  if (!data) return [];

  try {
    return JSON.parse(data) as MovimentacaoOrganizacional[];
  } catch {
    return [];
  }
}

function persistir(movimentacoes: MovimentacaoOrganizacional[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(movimentacoes));
}

function timestampData(data?: string): number {
  if (!data) return Number.NaN;
  const valor = new Date(`${data}T12:00:00`).getTime();
  return Number.isFinite(valor) ? valor : new Date(data).getTime();
}

function dataHojeLocal(): string {
  const agora = new Date();
  const ano = agora.getFullYear();
  const mes = String(agora.getMonth() + 1).padStart(2, "0");
  const dia = String(agora.getDate()).padStart(2, "0");
  return `${ano}-${mes}-${dia}`;
}

function nomesDasMatriculas(
  matriculas: number[] | undefined,
  colaboradores: Colaborador[]
): string[] {
  return (matriculas ?? []).map(
    (matricula) =>
      colaboradores.find((item) => item.matricula === matricula)?.nome ??
      `Matrícula ${matricula}`
  );
}

export function criarSnapshotOrganizacional(
  colaborador: Colaborador,
  colaboradores: Colaborador[]
): SnapshotOrganizacional {
  const gestor = colaborador.gestorDiretoMatricula
    ? colaboradores.find(
        (item) => item.matricula === colaborador.gestorDiretoMatricula
      )
    : undefined;

  return {
    status: colaborador.status,
    cargo: colaborador.cargo,
    area: colaborador.area,
    funcao: colaborador.funcao,
    senioridade: colaborador.senioridade,
    gestorDiretoMatricula: colaborador.gestorDiretoMatricula,
    gestorDiretoNome: gestor?.nome ?? (colaborador.respondePara || undefined),
    avaliadoresColegiadoMatriculas: [
      ...(colaborador.avaliadoresColegiadoMatriculas ?? []),
    ],
    avaliadoresColegiadoNomes: nomesDasMatriculas(
      colaborador.avaliadoresColegiadoMatriculas,
      colaboradores
    ),
  };
}

export function getHistoricoOrganizacional(
  colaboradorMatricula: number
): MovimentacaoOrganizacional[] {
  return lerTodas()
    .filter((item) => item.colaboradorMatricula === colaboradorMatricula)
    .sort(
      (a, b) =>
        timestampData(b.dataVigencia) - timestampData(a.dataVigencia) ||
        new Date(b.dataRegistro).getTime() - new Date(a.dataRegistro).getTime()
    );
}

function detectarTipo(
  anterior: Colaborador | undefined,
  atual: Colaborador
): TipoMovimentacaoOrganizacional {
  if (!anterior) return "ADMISSAO";

  if (anterior.status !== atual.status) {
    if (atual.status === "DESLIGADO") return "DESLIGAMENTO";
    if (atual.status === "LICENCA") return "LICENCA";
    if (anterior.status === "LICENCA" && atual.status === "ATIVO") {
      return "RETORNO_LICENCA";
    }
  }

  return "ALTERACAO_ESTRUTURA";
}

export function houveMudancaOrganizacional(
  anterior: Colaborador,
  atual: Colaborador
): boolean {
  const colegiadoAnterior = [
    ...(anterior.avaliadoresColegiadoMatriculas ?? []),
  ].sort((a, b) => a - b);

  const colegiadoAtual = [
    ...(atual.avaliadoresColegiadoMatriculas ?? []),
  ].sort((a, b) => a - b);

  return (
    anterior.status !== atual.status ||
    anterior.cargo !== atual.cargo ||
    anterior.area !== atual.area ||
    anterior.funcao !== atual.funcao ||
    anterior.senioridade !== atual.senioridade ||
    anterior.gestorDiretoMatricula !== atual.gestorDiretoMatricula ||
    JSON.stringify(colegiadoAnterior) !== JSON.stringify(colegiadoAtual)
  );
}

export function registrarMovimentacaoOrganizacional(params: {
  anterior?: Colaborador;
  atual: Colaborador;
  colaboradores: Colaborador[];
  dataVigencia: string;
  escopo: EscopoMovimentacaoOrganizacional;
  motivo?: string;
  autorMatricula: number;
  autorNome: string;
}): MovimentacaoOrganizacional {
  const cicloAtivo = getCicloAtivo();
  const agora = new Date().toISOString();

  const movimentacao: MovimentacaoOrganizacional = {
    id: crypto.randomUUID(),
    colaboradorMatricula: params.atual.matricula,
    colaboradorNome: params.atual.nome,
    tipo: detectarTipo(params.anterior, params.atual),
    dataVigencia: params.dataVigencia,
    dataRegistro: agora,
    escopo: params.escopo,
    cicloIdReferencia: cicloAtivo?.id,
    cicloReferenciaLabel: cicloAtivo
      ? `${cicloAtivo.ano}.${cicloAtivo.ciclo}`
      : undefined,
    motivo: params.motivo?.trim() || undefined,
    anterior: params.anterior
      ? criarSnapshotOrganizacional(params.anterior, params.colaboradores)
      : undefined,
    atual: criarSnapshotOrganizacional(params.atual, [
      ...params.colaboradores.filter(
        (item) => item.matricula !== params.atual.matricula
      ),
      params.atual,
    ]),
    autorMatricula: params.autorMatricula,
    autorNome: params.autorNome,
  };

  persistir([...lerTodas(), movimentacao]);
  return movimentacao;
}

function movimentoValeParaCiclo(
  movimento: MovimentacaoOrganizacional,
  ciclo?: CicloAvaliacao
): boolean {
  if (!ciclo) return true;

  if (
    movimento.escopo === "SOMENTE_CICLOS_POSTERIORES" &&
    movimento.cicloIdReferencia === ciclo.id
  ) {
    return false;
  }

  return true;
}

function dataReferenciaDoCiclo(ciclo: CicloAvaliacao): string {
  if (ciclo.status === "ENCERRADO") {
    return ciclo.dataFim ?? ciclo.dataEncerramento?.slice(0, 10) ?? dataHojeLocal();
  }

  if (ciclo.status === "PLANEJADO") {
    return ciclo.dataInicio ?? dataHojeLocal();
  }

  const hoje = dataHojeLocal();
  if (ciclo.dataFim && timestampData(hoje) > timestampData(ciclo.dataFim)) {
    return ciclo.dataFim;
  }
  if (ciclo.dataInicio && timestampData(hoje) < timestampData(ciclo.dataInicio)) {
    return ciclo.dataInicio;
  }
  return hoje;
}

function aplicarDeltaSnapshot(
  base: SnapshotOrganizacional,
  movimento: MovimentacaoOrganizacional
): SnapshotOrganizacional {
  if (!movimento.anterior) {
    return movimento.atual;
  }

  const anterior = movimento.anterior;
  const atual = movimento.atual;
  const proximo: SnapshotOrganizacional = {
    ...base,
    avaliadoresColegiadoMatriculas: [
      ...(base.avaliadoresColegiadoMatriculas ?? []),
    ],
    avaliadoresColegiadoNomes: [...(base.avaliadoresColegiadoNomes ?? [])],
  };

  if (anterior.status !== atual.status) proximo.status = atual.status;
  if (anterior.cargo !== atual.cargo) proximo.cargo = atual.cargo;
  if (anterior.area !== atual.area) proximo.area = atual.area;
  if (anterior.funcao !== atual.funcao) proximo.funcao = atual.funcao;
  if (anterior.senioridade !== atual.senioridade) {
    proximo.senioridade = atual.senioridade;
  }
  if (anterior.gestorDiretoMatricula !== atual.gestorDiretoMatricula) {
    proximo.gestorDiretoMatricula = atual.gestorDiretoMatricula;
    proximo.gestorDiretoNome = atual.gestorDiretoNome;
  }

  const colegiadoAnterior = JSON.stringify(
    [...(anterior.avaliadoresColegiadoMatriculas ?? [])].sort((a, b) => a - b)
  );
  const colegiadoAtual = JSON.stringify(
    [...(atual.avaliadoresColegiadoMatriculas ?? [])].sort((a, b) => a - b)
  );
  if (colegiadoAnterior !== colegiadoAtual) {
    proximo.avaliadoresColegiadoMatriculas = [
      ...(atual.avaliadoresColegiadoMatriculas ?? []),
    ];
    proximo.avaliadoresColegiadoNomes = [
      ...(atual.avaliadoresColegiadoNomes ?? []),
    ];
  }

  return proximo;
}

/**
 * Reconstrói a estrutura válida na data solicitada. Quando existe histórico,
 * o snapshot anterior da primeira movimentação funciona como base, evitando
 * que alterações atuais reescrevam períodos anteriores.
 */
export function getSnapshotOrganizacionalEmData(
  colaborador: Colaborador,
  dataReferencia: string,
  ciclo?: CicloAvaliacao
): SnapshotOrganizacional {
  const historico = getHistoricoOrganizacional(colaborador.matricula)
    .slice()
    .sort(
      (a, b) =>
        timestampData(a.dataVigencia) - timestampData(b.dataVigencia) ||
        new Date(a.dataRegistro).getTime() - new Date(b.dataRegistro).getTime()
    );

  if (historico.length === 0) {
    return criarSnapshotOrganizacional(colaborador, [colaborador]);
  }

  let snapshot = historico[0].anterior ?? historico[0].atual;
  const limite = timestampData(dataReferencia);

  for (const movimento of historico) {
    if (!movimentoValeParaCiclo(movimento, ciclo)) continue;
    if (timestampData(movimento.dataVigencia) <= limite) {
      snapshot = aplicarDeltaSnapshot(snapshot, movimento);
    }
  }

  return {
    ...snapshot,
    avaliadoresColegiadoMatriculas: [
      ...(snapshot.avaliadoresColegiadoMatriculas ?? []),
    ],
    avaliadoresColegiadoNomes: [
      ...(snapshot.avaliadoresColegiadoNomes ?? []),
    ],
  };
}

export function getSnapshotOrganizacionalNoCiclo(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  dataReferencia = dataReferenciaDoCiclo(ciclo)
): SnapshotOrganizacional {
  return getSnapshotOrganizacionalEmData(colaborador, dataReferencia, ciclo);
}

export function getColaboradorEfetivoNoCiclo(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  colaboradores: Colaborador[],
  dataReferencia = dataReferenciaDoCiclo(ciclo)
): Colaborador {
  const snapshot = getSnapshotOrganizacionalNoCiclo(
    colaborador,
    ciclo,
    dataReferencia
  );

  const gestor = snapshot.gestorDiretoMatricula
    ? colaboradores.find(
        (item) => item.matricula === snapshot.gestorDiretoMatricula
      )
    : undefined;

  return {
    ...colaborador,
    status: snapshot.status,
    cargo: snapshot.cargo,
    area: snapshot.area,
    funcao: snapshot.funcao,
    senioridade: snapshot.senioridade,
    gestorDiretoMatricula: snapshot.gestorDiretoMatricula,
    avaliadoresColegiadoMatriculas: [
      ...(snapshot.avaliadoresColegiadoMatriculas ?? []),
    ],
    respondePara: snapshot.gestorDiretoNome ?? gestor?.nome ?? "",
    gerente: colaborador.gerente,
  };
}

export function getColaboradoresEfetivosNoCiclo(
  ciclo: CicloAvaliacao,
  colaboradores: Colaborador[],
  dataReferencia = dataReferenciaDoCiclo(ciclo)
): Colaborador[] {
  return colaboradores.map((colaborador) =>
    getColaboradorEfetivoNoCiclo(
      colaborador,
      ciclo,
      colaboradores,
      dataReferencia
    )
  );
}

export function getCicloPorAnoECiclo(
  ano: number,
  ciclo: 1 | 2 | 3
): CicloAvaliacao | undefined {
  return getCiclosAvaliacao().find(
    (item) => item.ano === ano && item.ciclo === ciclo
  );
}

export function getDataReferenciaCiclo(ciclo: CicloAvaliacao): string {
  return dataReferenciaDoCiclo(ciclo);
}

export type AplicabilidadeOrganizacional =
  | { aplicavel: true; motivo?: undefined }
  | { aplicavel: false; motivo: string };

export function getAplicabilidadeNoCiclo(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao
): AplicabilidadeOrganizacional {
  const dataReferencia = dataReferenciaDoCiclo(ciclo);
  const snapshot = getSnapshotOrganizacionalNoCiclo(
    colaborador,
    ciclo,
    dataReferencia
  );

  if (
    colaborador.dataAdmissao &&
    ciclo.dataFim &&
    timestampData(colaborador.dataAdmissao) > timestampData(ciclo.dataFim)
  ) {
    return {
      aplicavel: false,
      motivo: `Não aplicável — admissão em ${new Date(
        `${colaborador.dataAdmissao}T12:00:00`
      ).toLocaleDateString("pt-BR")}`,
    };
  }

  if (snapshot.status === "DESLIGADO") {
    const desligamento = getHistoricoOrganizacional(colaborador.matricula)
      .find(
        (item) =>
          item.tipo === "DESLIGAMENTO" &&
          movimentoValeParaCiclo(item, ciclo) &&
          timestampData(item.dataVigencia) <= timestampData(dataReferencia)
      );

    return {
      aplicavel: false,
      motivo: desligamento
        ? `Não aplicável — desligado em ${new Date(
            `${desligamento.dataVigencia}T12:00:00`
          ).toLocaleDateString("pt-BR")}`
        : "Não aplicável — colaborador desligado",
    };
  }

  if (snapshot.status === "LICENCA") {
    const licenca = getHistoricoOrganizacional(colaborador.matricula)
      .find(
        (item) =>
          item.tipo === "LICENCA" &&
          movimentoValeParaCiclo(item, ciclo) &&
          timestampData(item.dataVigencia) <= timestampData(dataReferencia)
      );

    return {
      aplicavel: false,
      motivo: licenca
        ? `Suspensa — licença desde ${new Date(
            `${licenca.dataVigencia}T12:00:00`
          ).toLocaleDateString("pt-BR")}`
        : "Suspensa — colaborador em licença",
    };
  }

  return { aplicavel: true };
}
