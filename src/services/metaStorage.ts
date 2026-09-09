import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Meta, TipoMeta } from "../types/Meta";
import { getCiclosAvaliacao } from "./cicloAvaliacaoStorage";
import { getColaboradorEfetivoNoCiclo } from "./historicoOrganizacionalStorage";
import { getColaboradores } from "./colaboradorStorage";
import { authorize } from "../authorization/policyEngine/policyEngine";
import {
  criarProvidersMundoLocal,
  LOCAL_ORGANIZATION_ID,
} from "../authorization/providers/localWorld";
import {
  autorizar as autorizarFuncional,
  dominioPermite,
} from "../authorization/autorizacaoFuncional";

const STORAGE_KEY = "feedback-control-metas";

function getTodasMetas(): Meta[] {
  const data = localStorage.getItem(STORAGE_KEY);
  if (!data) return [];
  try {
    return JSON.parse(data) as Meta[];
  } catch {
    return [];
  }
}

function persistir(metas: Meta[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(metas));
}

export function getMetasDoColaboradorNoCiclo(
  colaboradorMatricula: number,
  cicloId: string,
  incluirExcluidas = false
): Meta[] {
  return getTodasMetas()
    .filter(
      (meta) =>
        meta.colaboradorMatricula === colaboradorMatricula &&
        meta.cicloId === cicloId &&
        (incluirExcluidas || !meta.excluida)
    )
    .sort(
      (a, b) =>
        new Date(a.dataCriacao).getTime() -
        new Date(b.dataCriacao).getTime()
    );
}

export function getMetasDoCiclo(
  cicloId: string,
  incluirExcluidas = false
): Meta[] {
  return getTodasMetas()
    .filter(
      (meta) =>
        meta.cicloId === cicloId &&
        (incluirExcluidas || !meta.excluida)
    )
    .sort((a, b) =>
      a.colaboradorNome.localeCompare(b.colaboradorNome, "pt-BR")
    );
}

export function contarMetasPorTipo(
  colaboradorMatricula: number,
  cicloId: string,
  tipo: TipoMeta
): number {
  return getMetasDoColaboradorNoCiclo(colaboradorMatricula, cicloId)
    .filter((meta) => meta.tipo === tipo).length;
}

function limiteDoTipo(ciclo: CicloAvaliacao, tipo: TipoMeta): number {
  return tipo === "NEGOCIO_PROJETO"
    ? ciclo.quantidadeMetasNegocio ?? 0
    : ciclo.quantidadeMetasIndividuais ?? 0;
}

function validarCicloAtivo(ciclo: CicloAvaliacao) {
  const cicloPersistido = getCiclosAvaliacao().find(
    (item) => item.id === ciclo.id
  );
  if (cicloPersistido?.status !== "ATIVO") {
    throw new Error(
      "As metas só podem ser cadastradas ou alteradas enquanto o ciclo estiver Ativo."
    );
  }
}

/**
 * F4-03 (fluxo-piloto, D9 = A ajustada): autorização na camada de serviço,
 * imediatamente antes da mutação de meta própria. A decisão vem somente do
 * policy engine (capability `goal.write` + scope SELF + relação "alvo = self"
 * + estado do domínio via probe), sem cargo/job_role.
 */
function autorizarMetaPropria(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao
): void {
  authorize(
    {
      actor: {
        actorId: String(colaborador.matricula),
        organizationId: LOCAL_ORGANIZATION_ID,
      },
      capability: "goal.write",
      target: { type: "collaborator", id: String(colaborador.matricula) },
      context: { date: new Date(), cycleId: ciclo.id },
      domainState: {
        allows: () =>
          getCiclosAvaliacao().find((item) => item.id === ciclo.id)?.status ===
          "ATIVO",
      },
    },
    criarProvidersMundoLocal(colaborador, getColaboradores())
  );
}

function getCicloDaMeta(meta: Meta): CicloAvaliacao | undefined {
  return getCiclosAvaliacao().find((ciclo) => ciclo.id === meta.cicloId);
}

function getColaboradorEfetivoParaCiclo(
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  ciclo?: CicloAvaliacao
): Colaborador {
  return ciclo
    ? getColaboradorEfetivoNoCiclo(colaborador, ciclo, colaboradores)
    : colaborador;
}

function getGerenteResponsavelNoCiclo(
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  ciclo: CicloAvaliacao
): Colaborador | undefined {
  const porMatricula = new Map(
    colaboradores.map((item) => [item.matricula, item])
  );
  const visitados = new Set<number>();
  let atual = getColaboradorEfetivoNoCiclo(
    colaborador,
    ciclo,
    colaboradores
  );

  while (atual.gestorDiretoMatricula) {
    const matriculaGestor = atual.gestorDiretoMatricula;
    if (visitados.has(matriculaGestor)) return undefined;
    visitados.add(matriculaGestor);

    const gestorBase = porMatricula.get(matriculaGestor);
    if (!gestorBase) return undefined;

    const gestor = getColaboradorEfetivoNoCiclo(
      gestorBase,
      ciclo,
      colaboradores
    );
    atual = gestor;
  }

  // F4-09 (D2/D3): responsável = raiz da cadeia (dado), nunca `funcao`.
  return atual;
}

export function metaExigeAprovacaoCoordenador(
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  ciclo?: CicloAvaliacao
): boolean {
  const efetivo = getColaboradorEfetivoParaCiclo(
    colaborador,
    colaboradores,
    ciclo
  );
  if (!efetivo.gestorDiretoMatricula) return false;

  const gestorBase = colaboradores.find(
    (item) => item.matricula === efetivo.gestorDiretoMatricula
  );
  if (!gestorBase) return false;

  const gestor = getColaboradorEfetivoParaCiclo(
    gestorBase,
    colaboradores,
    ciclo
  );
  return gestor.funcao === "COORDENADOR";
}

export function metaEstaAprovada(
  meta: Meta,
  colaborador: Colaborador,
  colaboradores: Colaborador[]
): boolean {
  const ciclo = getCicloDaMeta(meta);
  const coordenadorOk =
    !metaExigeAprovacaoCoordenador(colaborador, colaboradores, ciclo) ||
    Boolean(meta.aprovacaoCoordenador);

  // Aprovações já realizadas continuam válidas mesmo após transferência.
  return coordenadorOk && Boolean(meta.aprovacaoGerente);
}

export function podeAprovarMetaNoCiclo(
  aprovador: Colaborador,
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  ciclo: CicloAvaliacao
): boolean {
  const efetivo = getColaboradorEfetivoNoCiclo(
    colaborador,
    ciclo,
    colaboradores
  );

  // F4-09 (D2/D3): coordenador = gestor direto (dado); gerente = raiz da
  // cadeia (dado). Nunca `funcao`.
  const ehCoordenadorDireto =
    efetivo.gestorDiretoMatricula === aprovador.matricula;
  const ehGerenteResponsavel =
    getGerenteResponsavelNoCiclo(colaborador, colaboradores, ciclo)?.matricula ===
    aprovador.matricula;

  return ehCoordenadorDireto || ehGerenteResponsavel;
}

export function criarMeta(
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  tipo: TipoMeta,
  descricao: string,
  kpi: string,
  valorAlvo: string
): Meta {
  autorizarMetaPropria(colaborador, ciclo);

  const limite = limiteDoTipo(ciclo, tipo);
  const quantidadeAtual = contarMetasPorTipo(
    colaborador.matricula,
    ciclo.id,
    tipo
  );

  if (quantidadeAtual >= limite) {
    throw new Error(
      tipo === "NEGOCIO_PROJETO"
        ? "O limite de metas de Negócio/Projetos deste ciclo já foi atingido."
        : "O limite de metas Individuais deste ciclo já foi atingido."
    );
  }

  if (!descricao.trim() || !kpi.trim() || !valorAlvo.trim()) {
    throw new Error("Preencha a descrição, o KPI e o valor-alvo da meta.");
  }

  const agora = new Date().toISOString();

  const meta: Meta = {
    id: crypto.randomUUID(),
    colaboradorMatricula: colaborador.matricula,
    colaboradorNome: colaborador.nome,
    cicloId: ciclo.id,
    ano: ciclo.ano,
    ciclo: ciclo.ciclo,
    tipo,
    descricao: descricao.trim(),
    kpi: kpi.trim(),
    valorAlvo: valorAlvo.trim(),
    status: "EM_ANDAMENTO",
    dataCriacao: agora,
    dataUltimaAtualizacao: agora,
    excluida: false,
    historico: [{
      id: crypto.randomUUID(),
      acao: "CRIACAO",
      data: agora,
      autorMatricula: colaborador.matricula,
      autorNome: colaborador.nome,
    }],
  };

  persistir([...getTodasMetas(), meta]);
  return meta;
}

export function atualizarMeta(
  id: string,
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  descricao: string,
  kpi: string,
  valorAlvo: string
): void {
  autorizarMetaPropria(colaborador, ciclo);

  if (!descricao.trim() || !kpi.trim() || !valorAlvo.trim()) {
    throw new Error("Preencha a descrição, o KPI e o valor-alvo da meta.");
  }

  const metas = getTodasMetas();
  const atual = metas.find((meta) => meta.id === id);

  if (
    !atual ||
    atual.excluida ||
    atual.colaboradorMatricula !== colaborador.matricula ||
    atual.cicloId !== ciclo.id
  ) {
    throw new Error("Meta não encontrada.");
  }

  const novaDescricao = descricao.trim();
  const novoKpi = kpi.trim();
  const novoValorAlvo = valorAlvo.trim();
  const alteracaoRelevante =
    atual.descricao !== novaDescricao ||
    atual.kpi !== novoKpi ||
    atual.valorAlvo !== novoValorAlvo;
  const agora = new Date().toISOString();

  persistir(
    metas.map((meta) => {
      if (meta.id !== id) return meta;

      const historico = [
        ...meta.historico,
        {
          id: crypto.randomUUID(),
          acao: "EDICAO" as const,
          data: agora,
          autorMatricula: colaborador.matricula,
          autorNome: colaborador.nome,
          descricaoAnterior: meta.descricao,
          kpiAnterior: meta.kpi,
          valorAlvoAnterior: meta.valorAlvo,
        },
      ];

      if (
        alteracaoRelevante &&
        (meta.aprovacaoCoordenador || meta.aprovacaoGerente)
      ) {
        historico.push({
          id: crypto.randomUUID(),
          acao: "INVALIDACAO_APROVACOES",
          data: agora,
          autorMatricula: colaborador.matricula,
          autorNome: colaborador.nome,
        });
      }

      return {
        ...meta,
        descricao: novaDescricao,
        kpi: novoKpi,
        valorAlvo: novoValorAlvo,
        aprovacaoCoordenador: alteracaoRelevante
          ? undefined
          : meta.aprovacaoCoordenador,
        aprovacaoGerente: alteracaoRelevante
          ? undefined
          : meta.aprovacaoGerente,
        dataUltimaAtualizacao: agora,
        historico,
      };
    })
  );
}

export function aprovarMeta(
  id: string,
  aprovador: Colaborador,
  colaborador: Colaborador,
  ciclo: CicloAvaliacao
): void {
  validarCicloAtivo(ciclo);

  const metas = getTodasMetas();
  const atual = metas.find((meta) => meta.id === id);

  if (
    !atual ||
    atual.excluida ||
    atual.colaboradorMatricula !== colaborador.matricula ||
    atual.cicloId !== ciclo.id
  ) {
    throw new Error("Meta não encontrada.");
  }

  const agora = new Date().toISOString();
  const colaboradores = getColaboradores();

  // F4-09 (Q7/D10): mutação administrativa exige authorize() (capability +
  // relação/scope) + domainState. O estado já foi validado acima (ciclo ATIVO).
  autorizarFuncional(aprovador, colaboradores, {
    capability: "goal.approve",
    sujeitoMatricula: colaborador.matricula,
    domainState: dominioPermite(true),
    cicloId: ciclo.id,
  });

  const ehCoordenadorDireto =
    colaborador.gestorDiretoMatricula === aprovador.matricula;
  const ehGerenteResponsavel =
    getGerenteResponsavelNoCiclo(colaborador, colaboradores, ciclo)?.matricula ===
    aprovador.matricula;

  if (ehCoordenadorDireto) {
    if (!podeAprovarMetaNoCiclo(aprovador, colaborador, colaboradores, ciclo)) {
      throw new Error(
        "Somente o coordenador direto responsável neste ciclo pode aprovar esta meta."
      );
    }
    if (atual.aprovacaoCoordenador) return;

    persistir(
      metas.map((meta) =>
        meta.id === id
          ? {
              ...meta,
              aprovacaoCoordenador: {
                matricula: aprovador.matricula,
                nome: aprovador.nome,
                data: agora,
              },
              dataUltimaAtualizacao: agora,
              historico: [
                ...meta.historico,
                {
                  id: crypto.randomUUID(),
                  acao: "APROVACAO_COORDENADOR",
                  data: agora,
                  autorMatricula: aprovador.matricula,
                  autorNome: aprovador.nome,
                },
              ],
            }
          : meta
      )
    );
    return;
  }

  if (ehGerenteResponsavel) {
    if (!podeAprovarMetaNoCiclo(aprovador, colaborador, colaboradores, ciclo)) {
      throw new Error(
        "Somente o gerente responsável neste ciclo pode aprovar esta meta."
      );
    }
    if (atual.aprovacaoGerente) return;

    persistir(
      metas.map((meta) =>
        meta.id === id
          ? {
              ...meta,
              aprovacaoGerente: {
                matricula: aprovador.matricula,
                nome: aprovador.nome,
                data: agora,
              },
              dataUltimaAtualizacao: agora,
              historico: [
                ...meta.historico,
                {
                  id: crypto.randomUUID(),
                  acao: "APROVACAO_GERENTE",
                  data: agora,
                  autorMatricula: aprovador.matricula,
                  autorNome: aprovador.nome,
                },
              ],
            }
          : meta
      )
    );
    return;
  }

  throw new Error("Este perfil não pode aprovar metas.");
}

export function excluirMeta(
  id: string,
  colaborador: Colaborador,
  ciclo: CicloAvaliacao
): void {
  autorizarMetaPropria(colaborador, ciclo);
  const metas = getTodasMetas();
  const atual = metas.find((meta) => meta.id === id);

  if (
    !atual ||
    atual.excluida ||
    atual.colaboradorMatricula !== colaborador.matricula ||
    atual.cicloId !== ciclo.id
  ) {
    throw new Error("Meta não encontrada.");
  }

  const agora = new Date().toISOString();

  persistir(
    metas.map((meta) =>
      meta.id === id
        ? {
            ...meta,
            excluida: true,
            dataExclusao: agora,
            dataUltimaAtualizacao: agora,
            historico: [
              ...meta.historico,
              {
                id: crypto.randomUUID(),
                acao: "EXCLUSAO",
                data: agora,
                autorMatricula: colaborador.matricula,
                autorNome: colaborador.nome,
                descricaoAnterior: meta.descricao,
                kpiAnterior: meta.kpi,
                valorAlvoAnterior: meta.valorAlvo,
              },
            ],
          }
        : meta
    )
  );
}

export function atualizarAcompanhamentoMeta(
  id: string,
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  resultadoAtual: string,
  progressoPercentual: number
): void {
  autorizarMetaPropria(colaborador, ciclo);

  if (!resultadoAtual.trim()) {
    throw new Error("Informe o resultado atual da meta.");
  }
  if (
    !Number.isFinite(progressoPercentual) ||
    progressoPercentual < 0 ||
    progressoPercentual > 100
  ) {
    throw new Error("O progresso deve estar entre 0% e 100%.");
  }

  const metas = getTodasMetas();
  const atual = metas.find((meta) => meta.id === id);

  if (
    !atual ||
    atual.excluida ||
    atual.colaboradorMatricula !== colaborador.matricula ||
    atual.cicloId !== ciclo.id
  ) {
    throw new Error("Meta não encontrada.");
  }

  const agora = new Date().toISOString();

  persistir(
    metas.map((meta) =>
      meta.id === id
        ? {
            ...meta,
            resultadoAtual: resultadoAtual.trim(),
            progressoPercentual,
            dataUltimoAcompanhamento: agora,
            dataUltimaAtualizacao: agora,
            historico: [
              ...meta.historico,
              {
                id: crypto.randomUUID(),
                acao: "ATUALIZACAO_PROGRESSO",
                data: agora,
                autorMatricula: colaborador.matricula,
                autorNome: colaborador.nome,
                resultadoAtualAnterior: meta.resultadoAtual,
                progressoPercentualAnterior: meta.progressoPercentual,
              },
            ],
          }
        : meta
    )
  );
}

export function finalizarMeta(
  id: string,
  colaborador: Colaborador,
  ciclo: CicloAvaliacao,
  resultadoFinal: string,
  atingida: boolean
): void {
  autorizarMetaPropria(colaborador, ciclo);

  if (!resultadoFinal.trim()) {
    throw new Error("Informe o resultado final da meta.");
  }

  const metas = getTodasMetas();
  const atual = metas.find((meta) => meta.id === id);

  if (
    !atual ||
    atual.excluida ||
    atual.colaboradorMatricula !== colaborador.matricula ||
    atual.cicloId !== ciclo.id
  ) {
    throw new Error("Meta não encontrada.");
  }

  const agora = new Date().toISOString();

  persistir(
    metas.map((meta) =>
      meta.id === id
        ? {
            ...meta,
            resultadoFinal: resultadoFinal.trim(),
            atingida,
            status: atingida ? "ATINGIDA" : "NAO_ATINGIDA",
            dataFechamento: agora,
            dataUltimaAtualizacao: agora,
            historico: [
              ...meta.historico,
              {
                id: crypto.randomUUID(),
                acao: "FINALIZACAO",
                data: agora,
                autorMatricula: colaborador.matricula,
                autorNome: colaborador.nome,
                resultadoFinalAnterior: meta.resultadoFinal,
                atingidaAnterior: meta.atingida,
              },
            ],
          }
        : meta
    )
  );
}
