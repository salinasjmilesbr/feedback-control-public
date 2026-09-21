import {
  lerEstrutura,
  listarColaboradores,
  type ColaboradorSoberano,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import { lerAutorizacaoEstrutural } from "../services/autorizacaoEstruturalSoberana";
import type { ColaboradorResumidoSoberano } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import type {
  Colaborador,
  IdentidadeColaborador,
  StatusColaborador,
} from "../types/Colaborador";

/**
 * #333 — IDENTIDADE PESSOAL pelo VÍNCULO soberano.
 *
 * Módulo (não-componente) que resolve QUEM é o ator no tenant ativo:
 *   1. estrutura_autorizacao.collaborator_id (auth.uid -> membership -> link
 *      ativo) — nenhuma capability é exigida;
 *   2. a PRÓPRIA entrada em estrutura_pessoal (que existe só com o vínculo:
 *      ocupação/hierarquia NÃO são requisito);
 *   3. complemento OPCIONAL da listagem do universo (collaborator.read), usado
 *      apenas para rótulos legados (matrícula/e-mail/cargo/área).
 *
 * Não há casamento por e-mail, MATRÍCULA NÃO É REQUISITO para reconhecer o
 * usuário e nenhum rótulo é inventado: sem matrícula informada a identidade
 * continua definida e a projeção legada simplesmente não existe.
 */

/** Dependências injetáveis (teste determinístico) das leituras de identidade. */
export interface DependenciasIdentidadeSoberana {
  readonly lerAutorizacao?: typeof lerAutorizacaoEstrutural;
  readonly lerEstruturaPessoal?: typeof lerEstrutura;
  readonly listarColaboradores?: typeof listarColaboradores;
}

/** Matrícula legada numérica (rótulo). Ausente/não numérica => undefined. */
function matriculaNumerica(valor: string | null | undefined): number | undefined {
  if (valor === null || valor === undefined || valor.length === 0) return undefined;
  const numero = Number(valor);
  return Number.isSafeInteger(numero) ? numero : undefined;
}

/**
 * Rótulo de status para apresentação. Sem a listagem complementar o estado do
 * CADASTRO não é conhecido; o ator, porém, tem perfil e membership ATIVOS (é
 * pré-condição do vínculo que sustenta a identidade) — o rótulo é ATIVO e nunca
 * participa de autorização.
 */
function statusDeApresentacao(status: string | null | undefined): StatusColaborador {
  if (status === null || status === undefined) return "ATIVO";
  if (status === "active") return "ATIVO";
  if (status === "leave") return "LICENCA";
  return "DESLIGADO";
}

/**
 * Monta a identidade de APRESENTAÇÃO a partir da linha do PRÓPRIO ator na
 * projeção pessoal (UUID + nome) e do complemento OPCIONAL da listagem do
 * universo. Sem o complemento a identidade continua DEFINIDA.
 */
export function identidadeDeApresentacao(
  collaboratorId: string,
  propria: ColaboradorResumidoSoberano,
  enriquecido?: ColaboradorSoberano
): IdentidadeColaborador {
  const matricula = matriculaNumerica(enriquecido?.matricula);
  return {
    ...(matricula === undefined ? {} : { matricula }),
    collaboratorId,
    status: statusDeApresentacao(enriquecido?.status),
    nome: propria.nome.length > 0 ? propria.nome : (enriquecido?.fullName ?? ""),
    email: enriquecido?.email ?? "",
    cargo: enriquecido?.jobRoleName ?? "",
    area: enriquecido?.unitName ?? "",
    respondePara: enriquecido?.managerFullName ?? "",
    ...(enriquecido?.admissionDate ? { dataAdmissao: enriquecido.admissionDate } : {}),
  };
}

/**
 * Projeção LEGADA da identidade (domínios que ainda exigem matrícula numérica).
 * Sem matrícula devolve undefined: nenhum número é inventado e nenhum campo
 * legado é presumido.
 */
export function colaboradorLegadoDaIdentidade(
  identidade: IdentidadeColaborador
): Colaborador | undefined {
  if (identidade.matricula === undefined) return undefined;
  return {
    matricula: identidade.matricula,
    status: identidade.status,
    nome: identidade.nome,
    email: identidade.email,
    cargo: identidade.cargo,
    area: identidade.area,
    respondePara: identidade.respondePara,
    ...(identidade.funcao ? { funcao: identidade.funcao } : {}),
    ...(identidade.senioridade ? { senioridade: identidade.senioridade } : {}),
    ...(identidade.gestorDiretoMatricula === undefined
      ? {}
      : { gestorDiretoMatricula: identidade.gestorDiretoMatricula }),
    ...(identidade.avaliadoresColegiadoMatriculas
      ? { avaliadoresColegiadoMatriculas: [...identidade.avaliadoresColegiadoMatriculas] }
      : {}),
    ...(identidade.gerente ? { gerente: identidade.gerente } : {}),
    ...(identidade.dataAdmissao ? { dataAdmissao: identidade.dataAdmissao } : {}),
    ...(identidade.dataInicioLicenca ? { dataInicioLicenca: identidade.dataInicioLicenca } : {}),
    ...(identidade.dataFimLicenca ? { dataFimLicenca: identidade.dataFimLicenca } : {}),
    ...(identidade.dataDesligamento ? { dataDesligamento: identidade.dataDesligamento } : {}),
  };
}

/**
 * Resolve a identidade do ator pelo VÍNCULO soberano. Fail-closed: sem vínculo,
 * com projeção pessoal negada/indisponível ou sem a própria linha, devolve
 * undefined. A listagem negada NÃO apaga a identidade; nenhuma linha de
 * terceiros é usada como identidade.
 */
export async function carregarIdentidadeSoberana(
  organizationId: string,
  deps: DependenciasIdentidadeSoberana = {}
): Promise<IdentidadeColaborador | undefined> {
  const lerAutorizacao = deps.lerAutorizacao ?? lerAutorizacaoEstrutural;
  const lerPessoal = deps.lerEstruturaPessoal ?? lerEstrutura;
  const listar = deps.listarColaboradores ?? listarColaboradores;

  const autorizacao = await lerAutorizacao(organizationId);
  const collaboratorId = autorizacao.collaboratorId;
  if (!collaboratorId) return undefined;

  const pessoal = await lerPessoal({ organizationId, escopo: "pessoal" });
  if (!pessoal.ok) return undefined;

  const propria = pessoal.dados.colaboradores.find(
    (item) => item.collaboratorId === collaboratorId
  );
  if (!propria) return undefined;

  const listagem = await listar({ organizationId });
  const enriquecido = listagem.ok
    ? listagem.dados.find((item) => item.collaboratorId === collaboratorId)
    : undefined;

  return identidadeDeApresentacao(collaboratorId, propria, enriquecido);
}
