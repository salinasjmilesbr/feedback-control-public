/**
 * F5-10 P6 (Issue #220) — CUTOVER FUNCIONAL de "Minhas Metas".
 *
 * A autoridade funcional desta tela deixou de ser LOCAL (acervo do navegador
 * e autorizacao de mundo local) e passou a ser a PORTA SOBERANA de metas
 * (`GoalRepository`, via `obterRepositorioMetasSoberanas`). O que a tela decide é
 * apenas UX: nada aqui concede autoridade, tenant, papel ou estado.
 *
 * Invariantes desta migração (D1–D24 do desenho F5-10):
 * - **identidade UUID-first**: organização do contexto de auth, ciclo pelo
 *   `CycleRepository` (ciclo ATIVO), colaborador resolvido pela via soberana da
 *   F5-07 a partir da matrícula de APRESENTAÇÃO (o servidor resolve o UUID);
 * - **leitura própria**: `goal.listar_por_escopo` devolve o escopo autorizado
 *   (`SELF` + aprovadores CONGELADOS). Esta tela exibe e opera SOMENTE as metas
 *   com `relacao === "SELF"` e `!excluida` — a relação é FATO do servidor;
 * - **quota do CICLO/tipo**: vem de `limites` do envelope; AUSÊNCIA de limite =
 *   quota ZERO (nunca "ilimitado", nunca herdada do armazenamento local). O
 *   consumo (`usado`) é derivado das PRÓPRIAS metas `SELF` não excluídas;
 * - **aprovação como FATO**: `aprovacoes[]` traz sempre os dois papéis com
 *   `exigida`/`vigente`; a UI NÃO reconstrói a regra de exigência;
 * - **datas soberanas**: `dataUltimoAcompanhamento`, `dataFechamento` (nunca
 *   "último acompanhamento" a partir de `atualizadoEm`);
 * - **fail-closed**: faltando organização, ciclo, colaborador ou caminho
 *   soberano a tela mostra indisponibilidade EXPLÍCITA. Não existe fallback
 *   local, dual-read, cache de decisão nem lista vazia silenciosa.
 *
 * Os auxiliares PUROS desta tela (chave da tentativa lógica, quota do tipo,
 * projeção de aprovação, mensagens públicas e identidade de apresentação) vivem
 * no módulo COMPANHEIRO `./minhasMetasApoio` — a página exporta apenas o
 * COMPONENTE e os TIPOS do seu estado, como as demais páginas do repositório.
 *
 * FASE 4 (tratamento assíncrono): loading POR OPERAÇÃO, erro explícito (jamais
 * sucesso otimista), clique duplo BLOQUEADO enquanto a operação executa,
 * `CONFLICT` (409) com mensagem própria + REFRESH SOBERANO da lista, nenhum
 * `setState` após unmount e `operation_id` estável por TENTATIVA LÓGICA
 * (idempotência: o retry da mesma tentativa reutiliza o id; a próxima ação gera
 * um novo).
 */

import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import CollaboratorIdentity from "../components/CollaboratorIdentity";
import type { CicloSoberano } from "../application/ports/CycleRepository";
import type {
  EscopoMetasSoberanas,
  GoalRepository,
  LimiteSoberano,
  MetaMutadaSoberana,
  MetaSoberana,
  ResultadoMetas,
} from "../application/ports/GoalRepository";
import type {
  CodigoPublico,
  PapelAprovacaoMeta,
  TipoMetaSoberana,
} from "../infrastructure/supabase/metas/contrato";
import { obterRepositorioMetasSoberanas } from "../services/acessoMetasSoberanas";
import type { DependenciasAcessoMetas } from "../services/acessoMetasSoberanas";
import { obterRepositorioCiclosSoberanos } from "../services/acessoCiclosSoberanos";
import type { DependenciasAcessoCiclos } from "../services/acessoCiclosSoberanos";
import { obterColaborador } from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { DependenciasAcessoColaboradores } from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { StatusCicloAvaliacao } from "../types/CicloAvaliacao";
import {
  chaveDaTentativa,
  criarRegistroDeTentativas,
  identidadeDe,
  limiteDoTipo,
  mensagemDeFalhaDeMetas,
  mensagemDeFalhaDeOperacao,
  metaAprovada,
  metasDoAtor,
} from "./minhasMetasApoio";
import type { IdentidadeDasMinhasMetas } from "./minhasMetasApoio";
import "../styles/ciclos.css";
import "../styles/minhas-metas.css";

const SEM_ORGANIZACAO_ATIVA = "Selecione uma organização ativa para acessar suas metas.";
const SEM_ATOR = "Não foi possível resolver a identidade do colaborador vinculado à sua sessão.";
const SEM_CAMINHO_METAS = "O caminho soberano de metas não está disponível neste ambiente.";
const SEM_CAMINHO_CICLOS = "O caminho soberano de ciclos não está disponível neste ambiente.";
const CICLO_AUSENTE = "Não existe um ciclo ativo para cadastro ou acompanhamento de metas.";
const META_NAO_ENCONTRADA =
  "A meta não está mais no escopo autorizado desta leitura. A lista foi atualizada.";
const FALHA_DE_TRANSPORTE =
  "Não foi possível concluir a operação de meta. Nenhum dado local foi usado como resposta.";

/** Operações da tela: uma por AÇÃO lógica (loading e bloqueio por operação). */
export type OperacaoMinhasMetas =
  | "criando"
  | "editando"
  | "progresso"
  | "finalizando"
  | "revisando"
  | "excluindo";

/** Ciclo exibido: identidade por UUID; ano/número são RÓTULOS de projeção. */
export interface CicloDasMinhasMetas {
  readonly id: string;
  readonly ano: number;
  readonly numero: number;
  readonly status: StatusCicloAvaliacao;
}

/**
 * Estado da tela. `carregando`/`erro`/`sem-ciclo` são EXPLÍCITOS: nenhum deles
 * significa "sem metas" por negação silenciosa.
 */
export type EstadoMinhasMetas =
  | { readonly fase: "carregando" }
  | { readonly fase: "sem-ciclo" }
  | { readonly fase: "erro"; readonly codigo: CodigoPublico; readonly mensagem: string }
  | {
      readonly fase: "pronto";
      readonly ciclo: CicloDasMinhasMetas;
      readonly identidade: IdentidadeDasMinhasMetas;
      readonly metas: readonly MetaSoberana[];
      readonly limites: readonly LimiteSoberano[];
    };

export type MinhasMetasPageProps = {
  /** Porta soberana de metas (injeção de teste); produção usa o caminho padrão. */
  readonly depsMetas?: DependenciasAcessoMetas;
  /** Porta soberana de ciclos (injeção de teste). */
  readonly depsCiclos?: DependenciasAcessoCiclos;
  /** Porta soberana de colaboradores (injeção de teste). */
  readonly depsColaboradores?: DependenciasAcessoColaboradores;
  /** Semente de estado (teste determinístico). */
  readonly estadoInicial?: EstadoMinhasMetas;
  /** Semente da operação em curso (teste de loading/clique duplo). */
  readonly operacaoInicial?: OperacaoMinhasMetas | null;
};

const SEM_DEPENDENCIAS_METAS: DependenciasAcessoMetas = {};
const SEM_DEPENDENCIAS_CICLOS: DependenciasAcessoCiclos = {};
const SEM_DEPENDENCIAS_COLABORADORES: DependenciasAcessoColaboradores = {};

// ---------------------------------------------------------------------------
// Apresentação LOCAL da página (auxiliares PUROS, não exportados)
// ---------------------------------------------------------------------------

function rotuloPapel(papel: PapelAprovacaoMeta): string {
  return papel === "GERENTE" ? "Gerente" : "Coordenador direto";
}

function statusLabel(meta: MetaSoberana): string {
  if (meta.status === "ATINGIDA") return "Atingida";
  if (meta.status === "NAO_ATINGIDA") return "Não atingida";
  return "Em andamento";
}

function statusClass(meta: MetaSoberana): string {
  if (meta.status === "ATINGIDA") return "is-success";
  if (meta.status === "NAO_ATINGIDA") return "is-danger";
  return "is-progress";
}

function formatarDataHora(data?: string | null): string {
  if (!data) return "Ainda não atualizado";
  const valor = new Date(data);
  if (Number.isNaN(valor.getTime())) return "Ainda não atualizado";
  return valor.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

/**
 * Falha de TRANSPORTE (exceção do adapter) vira erro público explícito: nenhum
 * caminho alternativo é tentado e nada local é apresentado como resposta.
 */
function falhaDeTransporte<T>(): ResultadoMetas<T> {
  return { ok: false, error: { code: "INTERNAL", message: FALHA_DE_TRANSPORTE } };
}

async function lerEscopo(
  repositorio: GoalRepository,
  organizationId: string,
  cycleId: string
): Promise<ResultadoMetas<EscopoMetasSoberanas>> {
  try {
    return await repositorio.listarMetasPorEscopo(organizationId, cycleId);
  } catch {
    return falhaDeTransporte<EscopoMetasSoberanas>();
  }
}

async function executarMutacao(
  acao: () => Promise<ResultadoMetas<MetaMutadaSoberana>>
): Promise<ResultadoMetas<MetaMutadaSoberana>> {
  try {
    return await acao();
  } catch {
    return falhaDeTransporte<MetaMutadaSoberana>();
  }
}

function MinhasMetasPage({
  depsMetas,
  depsCiclos,
  depsColaboradores,
  estadoInicial,
  operacaoInicial,
}: MinhasMetasPageProps = {}) {
  const navigate = useNavigate();
  const { organizacaoAtivaId } = useAuth();
  const { usuarioAtual } = useUsuarioAtual();

  const [depsMetasInjetadas] = useState<DependenciasAcessoMetas>(
    () => depsMetas ?? SEM_DEPENDENCIAS_METAS
  );
  const [depsCiclosInjetadas] = useState<DependenciasAcessoCiclos>(
    () => depsCiclos ?? SEM_DEPENDENCIAS_CICLOS
  );
  const [depsColaboradoresInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => depsColaboradores ?? SEM_DEPENDENCIAS_COLABORADORES
  );
  const [tentativas] = useState(criarRegistroDeTentativas);

  const [leitura, setLeitura] = useState<{
    readonly chave: string;
    readonly estado: EstadoMinhasMetas;
  } | null>(null);
  const [versao, setVersao] = useState(0);

  const [tipo, setTipo] = useState<TipoMetaSoberana>("NEGOCIO_PROJETO");
  const [descricao, setDescricao] = useState("");
  const [kpi, setKpi] = useState("");
  const [valorAlvo, setValorAlvo] = useState("");
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [acompanhandoId, setAcompanhandoId] = useState<string | null>(null);
  const [resultadoAtual, setResultadoAtual] = useState("");
  const [progressoPercentual, setProgressoPercentual] = useState(0);
  const [fechandoId, setFechandoId] = useState<string | null>(null);
  const [resultadoFinal, setResultadoFinal] = useState("");
  const [atingida, setAtingida] = useState<boolean | null>(null);
  const [excluindoId, setExcluindoId] = useState<string | null>(null);
  const [motivoExclusao, setMotivoExclusao] = useState("");
  const [erro, setErro] = useState("");
  const [avisoLista, setAvisoLista] = useState<string | null>(null);
  const [operacao, setOperacao] = useState<OperacaoMinhasMetas | null>(
    operacaoInicial ?? null
  );
  const [recarregandoLista, setRecarregandoLista] = useState(false);

  /**
   * Guarda de UNMOUNT: nenhuma resposta em voo publica estado depois que a tela
   * saiu (logout, navegação). O corpo do efeito restaura `true` para sobreviver
   * ao duplo efeito do StrictMode.
   */
  const montadoRef = useRef(true);
  useEffect(() => {
    montadoRef.current = true;
    return () => {
      montadoRef.current = false;
    };
  }, []);

  const matriculaApresentacao = usuarioAtual ? String(usuarioAtual.matricula) : null;
  /** Chave da leitura corrente: organização + ator + versão de recarga. */
  const chaveLeitura = `${organizacaoAtivaId ?? "sem-organizacao"}|${
    matriculaApresentacao ?? "sem-ator"
  }|${versao}`;

  useEffect(() => {
    if (estadoInicial) return;

    let vigente = true;
    const publicar = (estado: EstadoMinhasMetas) => {
      if (vigente) setLeitura({ chave: chaveLeitura, estado });
    };

    void (async () => {
      if (!organizacaoAtivaId) {
        publicar({ fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ORGANIZACAO_ATIVA });
        return;
      }
      if (!matriculaApresentacao) {
        publicar({ fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ATOR });
        return;
      }

      const repositorioMetas = obterRepositorioMetasSoberanas(depsMetasInjetadas);
      if (!repositorioMetas) {
        publicar({ fase: "erro", codigo: "INTERNAL", mensagem: SEM_CAMINHO_METAS });
        return;
      }

      const repositorioCiclos = obterRepositorioCiclosSoberanos(depsCiclosInjetadas);
      if (!repositorioCiclos) {
        publicar({ fase: "erro", codigo: "INTERNAL", mensagem: SEM_CAMINHO_CICLOS });
        return;
      }

      // Ciclo ATIVO por UUID soberano — jamais por `ano`/`numero` nem do storage.
      const ciclo = await repositorioCiclos.obterCicloAtivo(organizacaoAtivaId);
      if (!vigente) return;
      if (!ciclo.ok) {
        publicar({ fase: "erro", codigo: ciclo.error.code, mensagem: ciclo.error.message });
        return;
      }
      const cicloDoAtor: CicloSoberano | null = ciclo.data;
      if (!cicloDoAtor) {
        publicar({ fase: "sem-ciclo" });
        return;
      }

      // Colaborador por via SOBERANA: a matrícula é apenas a INTENÇÃO; o UUID é
      // resolvido no servidor (ausente/ambíguo ⇒ erro explícito, nunca chute).
      const colaborador = await obterColaborador(
        { matricula: matriculaApresentacao, organizationId: organizacaoAtivaId },
        depsColaboradoresInjetadas
      );
      if (!vigente) return;
      if (!colaborador.ok) {
        publicar({ fase: "erro", codigo: colaborador.codigo, mensagem: colaborador.mensagem });
        return;
      }

      const escopo = await lerEscopo(repositorioMetas, organizacaoAtivaId, cicloDoAtor.id);
      if (!vigente) return;
      if (!escopo.ok) {
        publicar({ fase: "erro", codigo: escopo.error.code, mensagem: escopo.error.message });
        return;
      }

      publicar({
        fase: "pronto",
        ciclo: {
          id: cicloDoAtor.id,
          ano: cicloDoAtor.ano,
          numero: cicloDoAtor.numero,
          status: cicloDoAtor.status,
        },
        identidade: identidadeDe(colaborador.dados),
        metas: escopo.data.metas,
        limites: escopo.data.limites,
      });
    })();

    return () => {
      vigente = false;
    };
  }, [
    chaveLeitura,
    organizacaoAtivaId,
    matriculaApresentacao,
    estadoInicial,
    depsMetasInjetadas,
    depsCiclosInjetadas,
    depsColaboradoresInjetadas,
  ]);

  /**
   * Estado exibido DERIVADO (sem `setState` síncrono no efeito): sem resultado
   * para a chave corrente a tela está carregando; sem organização ativa o caminho
   * é fail-closed e nada é lido.
   */
  const estado: EstadoMinhasMetas =
    estadoInicial ??
    (!organizacaoAtivaId
      ? { fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ORGANIZACAO_ATIVA }
      : leitura?.chave === chaveLeitura
        ? leitura.estado
        : { fase: "carregando" });

  function recarregar() {
    setVersao((valor) => valor + 1);
  }

  if (estado.fase === "carregando") {
    return (
      <main className="virtus-page goals-page">
        <section className="goals-empty" role="status" aria-live="polite">
          <h1>Minhas Metas</h1>
          <p>Carregando suas metas no servidor…</p>
        </section>
      </main>
    );
  }

  if (estado.fase === "sem-ciclo") {
    return (
      <main className="virtus-page">
        <section className="cycle-page-header goals-page-header">
          <div>
            <h1>Minhas Metas</h1>
            <p>Acompanhe seus objetivos de negócio e desenvolvimento individual.</p>
          </div>
          <button
            type="button"
            className="cycle-btn cycle-btn--secondary"
            onClick={() => navigate(-1)}
          >
            ← Voltar
          </button>
        </section>
        <section className="goals-empty">
          <h2>Nenhum ciclo ativo</h2>
          <p>{CICLO_AUSENTE}</p>
        </section>
      </main>
    );
  }

  if (estado.fase === "erro") {
    return (
      <main className="virtus-page">
        <section className="goals-empty" role="alert">
          <h1>
            {estado.codigo === "FORBIDDEN" || estado.codigo === "NOT_AUTHORIZED"
              ? "Acesso restrito"
              : "Não foi possível carregar suas metas"}
          </h1>
          <p>{estado.mensagem}</p>
          <p>Nenhuma meta é lida do armazenamento local: a autoridade é sempre o servidor.</p>
          <button type="button" className="cycle-btn cycle-btn--secondary" onClick={recarregar}>
            Tentar novamente
          </button>
        </section>
      </main>
    );
  }

  const { ciclo, identidade, metas, limites } = estado;
  const cicloAtivo = ciclo.status === "ATIVO";
  const metasVisiveis = metasDoAtor(metas);
  const metasNegocio = metasVisiveis.filter((meta) => meta.tipo === "NEGOCIO_PROJETO");
  const metasIndividuais = metasVisiveis.filter((meta) => meta.tipo === "INDIVIDUAL");

  const limiteNegocio = limiteDoTipo(limites, "NEGOCIO_PROJETO");
  const limiteIndividuais = limiteDoTipo(limites, "INDIVIDUAL");
  const limiteAtual = limiteDoTipo(limites, tipo);
  const quantidadeAtual =
    tipo === "NEGOCIO_PROJETO" ? metasNegocio.length : metasIndividuais.length;
  const podeAdicionar = quantidadeAtual < limiteAtual;

  const totalConfigurado = limiteNegocio + limiteIndividuais;
  const totalCadastrado = metasVisiveis.length;
  const emAndamento = metasVisiveis.filter((meta) => meta.status === "EM_ANDAMENTO").length;
  const aprovadas = metasVisiveis.filter(metaAprovada).length;
  const progressoMedio = totalCadastrado
    ? Math.round(
        metasVisiveis.reduce((soma, meta) => soma + (meta.progressoPercentual ?? 0), 0) /
          totalCadastrado
      )
    : 0;

  /** Clique duplo BLOQUEADO: qualquer operação (ou refresh) em curso desabilita. */
  const ocupado = operacao !== null || recarregandoLista;
  const semEditores = !editandoId && !acompanhandoId && !fechandoId && !excluindoId;

  function limparFormulario() {
    setDescricao("");
    setKpi("");
    setValorAlvo("");
    setEditandoId(null);
    setErro("");
  }

  function limparAcompanhamento() {
    setAcompanhandoId(null);
    setResultadoAtual("");
    setProgressoPercentual(0);
    setErro("");
  }

  function limparFechamento() {
    setFechandoId(null);
    setResultadoFinal("");
    setAtingida(null);
    setErro("");
  }

  function limparExclusao() {
    setExcluindoId(null);
    setMotivoExclusao("");
    setErro("");
  }

  function iniciarAcompanhamento(meta: MetaSoberana) {
    limparFormulario();
    limparFechamento();
    limparExclusao();
    setAcompanhandoId(meta.id);
    setResultadoAtual(meta.resultadoAtual ?? "");
    setProgressoPercentual(meta.progressoPercentual ?? 0);
  }

  function iniciarFechamento(meta: MetaSoberana) {
    limparFormulario();
    limparAcompanhamento();
    limparExclusao();
    setFechandoId(meta.id);
    setResultadoFinal(meta.resultadoFinal ?? "");
    setAtingida(typeof meta.atingida === "boolean" ? meta.atingida : null);
    setErro("");
  }

  function editar(meta: MetaSoberana) {
    limparAcompanhamento();
    limparFechamento();
    limparExclusao();
    setTipo(meta.tipo);
    setDescricao(meta.descricao);
    setKpi(meta.kpi);
    setValorAlvo(meta.valorAlvo);
    setEditandoId(meta.id);
    setErro("");
  }

  function iniciarExclusao(meta: MetaSoberana) {
    limparFormulario();
    limparAcompanhamento();
    limparFechamento();
    setExcluindoId(meta.id);
    setMotivoExclusao("");
    setErro("");
  }

  /**
   * REFRESH SOBERANO da lista: relê o escopo autorizado e publica o que o
   * servidor devolveu. Se a releitura falhar, a lista anterior permanece visível
   * COM aviso explícito — nunca uma sobrescrita silenciosa por estado inventado.
   */
  async function atualizarLista(): Promise<void> {
    const organizacaoId = organizacaoAtivaId;
    if (estado.fase !== "pronto" || !organizacaoId) return;
    const cicloDaLista = estado.ciclo;
    const identidadeAtual = estado.identidade;

    const repositorioMetas = obterRepositorioMetasSoberanas(depsMetasInjetadas);
    if (!repositorioMetas) {
      setAvisoLista(SEM_CAMINHO_METAS);
      return;
    }

    setRecarregandoLista(true);
    const escopo = await lerEscopo(repositorioMetas, organizacaoId, cicloDaLista.id);
    if (!montadoRef.current) return;
    setRecarregandoLista(false);

    if (!escopo.ok) {
      setAvisoLista(
        `Não foi possível recarregar a lista: ${mensagemDeFalhaDeMetas(escopo.error)}`
      );
      return;
    }

    setLeitura({
      chave: chaveLeitura,
      estado: {
        fase: "pronto",
        ciclo: cicloDaLista,
        identidade: identidadeAtual,
        metas: escopo.data.metas,
        limites: escopo.data.limites,
      },
    });
    setAvisoLista(null);
  }

  /**
   * Executa UMA ação lógica com o tratamento da FASE 4: bloqueio de clique duplo,
   * loading por operação, erro explícito, 409 com refresh soberano e nenhum
   * `setState` depois do unmount.
   */
  async function executarAcao(
    alvo: OperacaoMinhasMetas,
    chave: string,
    acao: () => Promise<ResultadoMetas<MetaMutadaSoberana>>
  ): Promise<boolean> {
    if (operacao !== null) return false;

    setErro("");
    setAvisoLista(null);
    setOperacao(alvo);

    const resultado = await executarMutacao(acao);
    if (!montadoRef.current) return false;

    if (!resultado.ok) {
      const conflito = resultado.error.code === "CONFLICT";
      // Conflito invalida a intenção: o retry precisa de um `operationId` novo.
      if (conflito) tentativas.encerrar(chave);
      setOperacao(null);
      setErro(mensagemDeFalhaDeOperacao(resultado.error));
      // 409: a verdade é do servidor — a lista é relida (nunca sobrescrita às cegas).
      if (conflito) await atualizarLista();
      return false;
    }

    tentativas.encerrar(chave);
    setOperacao(null);
    // Sucesso só é exibido depois do refresh soberano (nada de estado otimista).
    await atualizarLista();
    return true;
  }

  async function salvar() {
    if (ocupado) return;
    setErro("");

    const organizacaoId = organizacaoAtivaId;
    const repositorioMetas = obterRepositorioMetasSoberanas(depsMetasInjetadas);
    if (!organizacaoId || !repositorioMetas) {
      setErro(!organizacaoId ? SEM_ORGANIZACAO_ATIVA : SEM_CAMINHO_METAS);
      return;
    }
    if (!descricao.trim() || !kpi.trim() || !valorAlvo.trim()) {
      setErro("Informe a descrição, o KPI mensurável e o valor-alvo da meta.");
      return;
    }

    if (editandoId) {
      const meta = metasVisiveis.find((item) => item.id === editandoId);
      if (!meta) {
        setErro(META_NAO_ENCONTRADA);
        recarregar();
        return;
      }
      const chave = chaveDaTentativa([
        "editar",
        meta.id,
        meta.version,
        descricao,
        kpi,
        valorAlvo,
      ]);
      const concluiu = await executarAcao("editando", chave, () =>
        repositorioMetas.editarMeta({
          organizationId: organizacaoId,
          goalId: meta.id,
          descricao: descricao.trim(),
          kpi: kpi.trim(),
          valorAlvo: valorAlvo.trim(),
          // Versão da meta LIDA: a comparação pertence à RPC (D12).
          expectedVersion: meta.version,
          operationId: tentativas.idDa(chave),
        })
      );
      if (concluiu) limparFormulario();
      return;
    }

    const chave = chaveDaTentativa([
      "criar",
      ciclo.id,
      identidade.colaboradorId,
      tipo,
      descricao,
      kpi,
      valorAlvo,
    ]);
    const concluiu = await executarAcao("criando", chave, () =>
      repositorioMetas.criarMeta({
        organizationId: organizacaoId,
        cycleId: ciclo.id,
        collaboratorId: identidade.colaboradorId,
        tipo,
        descricao: descricao.trim(),
        kpi: kpi.trim(),
        valorAlvo: valorAlvo.trim(),
        operationId: tentativas.idDa(chave),
      })
    );
    if (concluiu) limparFormulario();
  }

  async function salvarAcompanhamento() {
    if (ocupado || !acompanhandoId) return;
    setErro("");

    const organizacaoId = organizacaoAtivaId;
    const repositorioMetas = obterRepositorioMetasSoberanas(depsMetasInjetadas);
    if (!organizacaoId || !repositorioMetas) {
      setErro(!organizacaoId ? SEM_ORGANIZACAO_ATIVA : SEM_CAMINHO_METAS);
      return;
    }
    if (!resultadoAtual.trim()) {
      setErro("Informe o resultado atual da meta.");
      return;
    }

    const meta = metasVisiveis.find((item) => item.id === acompanhandoId);
    if (!meta) {
      setErro(META_NAO_ENCONTRADA);
      recarregar();
      return;
    }

    const chave = chaveDaTentativa([
      "progresso",
      meta.id,
      meta.version,
      resultadoAtual,
      progressoPercentual,
    ]);
    const concluiu = await executarAcao("progresso", chave, () =>
      repositorioMetas.atualizarProgressoMeta({
        organizationId: organizacaoId,
        goalId: meta.id,
        resultadoAtual: resultadoAtual.trim(),
        progressoPercentual,
        expectedVersion: meta.version,
        operationId: tentativas.idDa(chave),
      })
    );
    if (concluiu) limparAcompanhamento();
  }

  async function salvarFechamento() {
    if (ocupado || !fechandoId) return;
    if (atingida === null) {
      setErro("Informe se a meta foi atingida ou não.");
      return;
    }
    setErro("");

    const organizacaoId = organizacaoAtivaId;
    const repositorioMetas = obterRepositorioMetasSoberanas(depsMetasInjetadas);
    if (!organizacaoId || !repositorioMetas) {
      setErro(!organizacaoId ? SEM_ORGANIZACAO_ATIVA : SEM_CAMINHO_METAS);
      return;
    }
    if (!resultadoFinal.trim()) {
      setErro("Informe o resultado final da meta.");
      return;
    }

    const meta = metasVisiveis.find((item) => item.id === fechandoId);
    if (!meta) {
      setErro(META_NAO_ENCONTRADA);
      recarregar();
      return;
    }

    const atingidaFinal = atingida;
    const resultado = resultadoFinal.trim();
    // Revisão de fechamento é operação PRÓPRIA (`meta_revisar_finalizacao`),
    // nunca um segundo `finalizar`.
    const revisao = meta.status !== "EM_ANDAMENTO";
    const chave = chaveDaTentativa([
      revisao ? "revisar" : "finalizar",
      meta.id,
      meta.version,
      resultado,
      atingidaFinal,
    ]);
    const concluiu = await executarAcao(revisao ? "revisando" : "finalizando", chave, () =>
      revisao
        ? repositorioMetas.revisarFinalizacaoMeta({
            organizationId: organizacaoId,
            goalId: meta.id,
            resultadoFinal: resultado,
            atingida: atingidaFinal,
            expectedVersion: meta.version,
            operationId: tentativas.idDa(chave),
          })
        : repositorioMetas.finalizarMeta({
            organizationId: organizacaoId,
            goalId: meta.id,
            resultadoFinal: resultado,
            atingida: atingidaFinal,
            expectedVersion: meta.version,
            operationId: tentativas.idDa(chave),
          })
    );
    if (concluiu) limparFechamento();
  }

  async function confirmarExclusao() {
    if (ocupado || !excluindoId) return;
    if (!motivoExclusao.trim()) {
      setErro("Informe o motivo da exclusão: ele é obrigatório na operação soberana.");
      return;
    }
    setErro("");

    const organizacaoId = organizacaoAtivaId;
    const repositorioMetas = obterRepositorioMetasSoberanas(depsMetasInjetadas);
    if (!organizacaoId || !repositorioMetas) {
      setErro(!organizacaoId ? SEM_ORGANIZACAO_ATIVA : SEM_CAMINHO_METAS);
      return;
    }

    const meta = metasVisiveis.find((item) => item.id === excluindoId);
    if (!meta) {
      setErro(META_NAO_ENCONTRADA);
      recarregar();
      return;
    }

    const motivo = motivoExclusao.trim();
    const chave = chaveDaTentativa(["excluir", meta.id, meta.version, motivo]);
    const concluiu = await executarAcao("excluindo", chave, () =>
      repositorioMetas.excluirMeta({
        organizationId: organizacaoId,
        goalId: meta.id,
        motivo,
        expectedVersion: meta.version,
        operationId: tentativas.idDa(chave),
      })
    );
    if (concluiu) limparExclusao();
  }

  function renderEditorAcompanhamento(meta: MetaSoberana) {
    if (acompanhandoId !== meta.id || fechandoId) return null;

    return (
      <div className="goal-inline-editor">
        <div className="goal-inline-editor__header">
          <div>
            <span className="cycle-eyebrow">Acompanhamento</span>
            <h4>Atualizar andamento</h4>
            <p>Atualize o resultado parcial e o percentual de progresso desta meta.</p>
          </div>
        </div>

        <label className="goals-field">
          <span>Resultado atual</span>
          <textarea
            value={resultadoAtual}
            onChange={(event) => setResultadoAtual(event.target.value)}
            placeholder="Ex.: O tempo médio atual caiu para 5,1 horas."
          />
        </label>

        <label className="goals-field">
          <div className="goals-field__row">
            <span>Progresso</span>
            <strong>{progressoPercentual}%</strong>
          </div>
          <input
            type="range"
            min={0}
            max={100}
            step={5}
            value={progressoPercentual}
            onChange={(event) => setProgressoPercentual(Number(event.target.value))}
          />
        </label>

        <label className="goals-progress-number">
          <input
            type="number"
            min={0}
            max={100}
            value={progressoPercentual}
            onChange={(event) => {
              const valor = Number(event.target.value);
              setProgressoPercentual(Math.min(100, Math.max(0, valor)));
            }}
          />
          <span>%</span>
        </label>

        {erro && <div className="goals-error">{erro}</div>}

        <div className="goals-editor__actions">
          <button
            type="button"
            className="cycle-btn cycle-btn--secondary"
            onClick={limparAcompanhamento}
            disabled={ocupado}
          >
            Cancelar
          </button>
          <button
            type="button"
            className="cycle-btn cycle-btn--primary"
            onClick={() => void salvarAcompanhamento()}
            disabled={ocupado || !cicloAtivo}
          >
            {operacao === "progresso" ? "Salvando…" : "Salvar andamento"}
          </button>
        </div>
      </div>
    );
  }

  function renderEditorFechamento(meta: MetaSoberana) {
    if (fechandoId !== meta.id) return null;

    return (
      <div className="goal-inline-editor">
        <div className="goal-inline-editor__header">
          <div>
            <span className="cycle-eyebrow">Conclusão</span>
            <h4>{meta.status === "EM_ANDAMENTO" ? "Fechar meta" : "Revisar fechamento"}</h4>
            <p>Registre o resultado alcançado e indique se a meta foi atingida.</p>
          </div>
        </div>

        <label className="goals-field">
          <span>Resultado final</span>
          <textarea
            value={resultadoFinal}
            onChange={(event) => setResultadoFinal(event.target.value)}
            placeholder="Descreva o resultado obtido de acordo com o KPI e o valor-alvo."
          />
        </label>

        <fieldset className="goals-radio-group">
          <legend>Meta atingida?</legend>
          <label>
            <input
              type="radio"
              checked={atingida === true}
              onChange={() => setAtingida(true)}
            />{" "}
            Sim
          </label>
          <label>
            <input
              type="radio"
              checked={atingida === false}
              onChange={() => setAtingida(false)}
            />{" "}
            Não
          </label>
        </fieldset>

        {erro && <div className="goals-error">{erro}</div>}

        <div className="goals-editor__actions">
          <button
            type="button"
            className="cycle-btn cycle-btn--secondary"
            onClick={limparFechamento}
            disabled={ocupado}
          >
            Cancelar
          </button>
          <button
            type="button"
            className="cycle-btn cycle-btn--primary"
            onClick={() => void salvarFechamento()}
            disabled={ocupado || !cicloAtivo}
          >
            {operacao === "finalizando" || operacao === "revisando"
              ? "Salvando…"
              : "Salvar fechamento"}
          </button>
        </div>
      </div>
    );
  }

  function renderEditorExclusao(meta: MetaSoberana) {
    if (excluindoId !== meta.id) return null;

    return (
      <div className="goal-inline-editor">
        <div className="goal-inline-editor__header">
          <div>
            <span className="cycle-eyebrow">Exclusão</span>
            <h4>Excluir meta</h4>
            <p>
              A exclusão é lógica e o registro permanece no histórico do servidor. O motivo é
              obrigatório.
            </p>
          </div>
        </div>

        <label className="goals-field">
          <span>Motivo da exclusão</span>
          <textarea
            value={motivoExclusao}
            onChange={(event) => setMotivoExclusao(event.target.value)}
            placeholder="Ex.: Meta cadastrada em duplicidade neste ciclo."
          />
        </label>

        {erro && <div className="goals-error">{erro}</div>}

        <div className="goals-editor__actions">
          <button
            type="button"
            className="cycle-btn cycle-btn--secondary"
            onClick={limparExclusao}
            disabled={ocupado}
          >
            Cancelar
          </button>
          <button
            type="button"
            className="cycle-btn cycle-btn--primary"
            onClick={() => void confirmarExclusao()}
            disabled={ocupado || !cicloAtivo}
          >
            {operacao === "excluindo" ? "Excluindo…" : "Confirmar exclusão"}
          </button>
        </div>
      </div>
    );
  }

  function renderEditorMeta(meta: MetaSoberana) {
    if (editandoId !== meta.id || acompanhandoId || fechandoId || excluindoId) return null;

    return (
      <div className="goal-inline-editor">
        <div className="goal-inline-editor__header">
          <div>
            <span className="cycle-eyebrow">Edição</span>
            <h4>Editar meta</h4>
            <p>Atualize a descrição, o KPI mensurável ou o valor-alvo desta meta.</p>
          </div>
        </div>

        <label className="goals-field">
          <span>Descrição da meta</span>
          <textarea
            value={descricao}
            onChange={(event) => setDescricao(event.target.value)}
            placeholder="Ex.: Reduzir o tempo médio de publicação"
          />
        </label>

        <div className="goals-editor__grid">
          <label className="goals-field">
            <span>KPI mensurável</span>
            <input
              value={kpi}
              onChange={(event) => setKpi(event.target.value)}
              placeholder="Ex.: Tempo médio entre aprovação e publicação"
            />
          </label>

          <label className="goals-field">
            <span>Valor-alvo</span>
            <input
              value={valorAlvo}
              onChange={(event) => setValorAlvo(event.target.value)}
              placeholder="Ex.: ≤ 4 horas, 95%, R$ 1 milhão"
            />
          </label>
        </div>

        {erro && <div className="goals-error">{erro}</div>}

        <div className="goals-editor__actions">
          <button
            type="button"
            className="cycle-btn cycle-btn--secondary"
            onClick={limparFormulario}
            disabled={ocupado}
          >
            Cancelar
          </button>
          <button
            type="button"
            className="cycle-btn cycle-btn--primary"
            onClick={() => void salvar()}
            disabled={ocupado || !cicloAtivo}
          >
            {operacao === "editando" ? "Salvando…" : "Salvar alterações"}
          </button>
        </div>
      </div>
    );
  }

  function renderGrupo(
    titulo: string,
    descricaoGrupo: string,
    tipoGrupo: TipoMetaSoberana,
    itens: readonly MetaSoberana[],
    limite: number
  ) {
    return (
      <section className="goals-group">
        <div className="goals-group__header">
          <div>
            <span className="cycle-eyebrow">
              {tipoGrupo === "NEGOCIO_PROJETO" ? "Performance" : "Desenvolvimento"}
            </span>
            <h2>{titulo}</h2>
            <p>{descricaoGrupo}</p>
          </div>
          <span className="goals-count">
            {itens.length} de {limite}
          </span>
        </div>

        {limite === 0 ? (
          <div className="goals-group__empty">
            Esta categoria não foi habilitada para este ciclo.
          </div>
        ) : itens.length === 0 ? (
          <div className="goals-group__empty">Nenhuma meta cadastrada nesta categoria.</div>
        ) : (
          <div className="goals-list">
            {itens.map((meta, indice) => (
              <article className="goal-card" key={meta.id}>
                <div className="goal-card__top">
                  <div className="goal-card__identity">
                    <span className="goal-card__index">{indice + 1}</span>
                    <div>
                      <h3>{meta.descricao}</h3>
                      <span className={`goal-status ${statusClass(meta)}`}>
                        {statusLabel(meta)}
                      </span>
                    </div>
                  </div>

                  <div className="goal-card__actions">
                    {meta.status === "EM_ANDAMENTO" && (
                      <button
                        type="button"
                        className="goal-action-btn goal-action-btn--primary"
                        onClick={() => iniciarAcompanhamento(meta)}
                        disabled={ocupado || !cicloAtivo}
                      >
                        Atualizar andamento
                      </button>
                    )}
                    <button
                      type="button"
                      className="goal-action-btn goal-action-btn--success"
                      onClick={() => iniciarFechamento(meta)}
                      disabled={ocupado || !cicloAtivo}
                    >
                      {meta.status === "EM_ANDAMENTO" ? "Fechar meta" : "Revisar fechamento"}
                    </button>
                    <button
                      type="button"
                      className="goal-action-btn"
                      onClick={() => editar(meta)}
                      disabled={ocupado || !cicloAtivo}
                    >
                      Editar
                    </button>
                    <button
                      type="button"
                      className="goal-action-btn goal-action-btn--danger"
                      onClick={() => iniciarExclusao(meta)}
                      disabled={ocupado || !cicloAtivo}
                    >
                      Excluir
                    </button>
                  </div>
                </div>

                <div className="goal-card__facts">
                  <div>
                    <span>KPI</span>
                    <strong>{meta.kpi}</strong>
                  </div>
                  <div>
                    <span>Valor-alvo</span>
                    <strong>{meta.valorAlvo}</strong>
                  </div>
                  <div>
                    <span>Última atualização</span>
                    <strong>{formatarDataHora(meta.dataUltimoAcompanhamento)}</strong>
                  </div>
                </div>

                <div
                  className={`goal-approval ${metaAprovada(meta) ? "is-approved" : "is-pending"}`}
                >
                  <div className="goal-approval__title">
                    <strong>
                      {metaAprovada(meta) ? "Meta aprovada" : "Aguardando aprovação"}
                    </strong>
                    <span>Aprovação formal</span>
                  </div>
                  <div className="goal-approval__checks">
                    {meta.aprovacoes.map((aprovacao) => (
                      <span key={aprovacao.papel} className={aprovacao.vigente ? "is-ok" : ""}>
                        {aprovacao.vigente ? "✓" : aprovacao.exigida ? "○" : "—"}{" "}
                        {rotuloPapel(aprovacao.papel)}
                        {!aprovacao.exigida && <small> • não exigida neste ciclo</small>}
                        {aprovacao.vigente && aprovacao.decididoEm && (
                          <small> • {formatarDataHora(aprovacao.decididoEm)}</small>
                        )}
                      </span>
                    ))}
                  </div>
                </div>

                <div className="goal-progress">
                  <div className="goal-progress__label">
                    <span>Progresso</span>
                    <strong>{meta.progressoPercentual ?? 0}%</strong>
                  </div>
                  <div className="goal-progress__track">
                    <div style={{ width: `${meta.progressoPercentual ?? 0}%` }} />
                  </div>
                </div>

                <div className="goal-result">
                  <span>Resultado atual</span>
                  <strong className={!meta.resultadoAtual?.trim() ? "is-muted" : ""}>
                    {meta.resultadoAtual?.trim() ? meta.resultadoAtual : "Ainda não informado"}
                  </strong>
                </div>

                {meta.status !== "EM_ANDAMENTO" && (
                  <div
                    className={`goal-final-result ${
                      meta.status === "ATINGIDA" ? "is-success" : "is-danger"
                    }`}
                  >
                    <div>
                      <span>Resultado final</span>
                      <strong>{meta.resultadoFinal}</strong>
                    </div>
                    <small>Fechada em {formatarDataHora(meta.dataFechamento)}</small>
                  </div>
                )}

                {renderEditorAcompanhamento(meta)}
                {renderEditorFechamento(meta)}
                {renderEditorExclusao(meta)}
                {renderEditorMeta(meta)}
              </article>
            ))}
          </div>
        )}

        {itens.length < limite && semEditores && (
          <button
            type="button"
            className="goals-add-btn"
            onClick={() => {
              setTipo(tipoGrupo);
              setDescricao("");
              setKpi("");
              setValorAlvo("");
              setErro("");
            }}
            disabled={ocupado || !cicloAtivo}
          >
            + Adicionar meta
          </button>
        )}
      </section>
    );
  }

  return (
    <main className="virtus-page goals-page">
      <section className="cycle-page-header goals-page-header">
        <div>
          <h1>Minhas Metas</h1>
          <p>Acompanhe seus objetivos de negócio e desenvolvimento individual no ciclo atual.</p>
        </div>
        <button
          type="button"
          className="cycle-btn cycle-btn--secondary"
          onClick={() => navigate(-1)}
        >
          ← Voltar
        </button>
      </section>

      {usuarioAtual && (
        <section className="goals-identity-card">
          <CollaboratorIdentity colaborador={usuarioAtual} variant="standard" />
        </section>
      )}

      <section className="goals-cycle-card">
        <div>
          <span className="cycle-eyebrow">Ciclo atual</span>
          <h2>
            {ciclo.ano} • Ciclo {ciclo.numero}
          </h2>
          <p>
            Até <strong>{limiteNegocio}</strong> meta{limiteNegocio === 1 ? "" : "s"} de
            Negócio/Projetos e <strong>{limiteIndividuais}</strong> meta
            {limiteIndividuais === 1 ? "" : "s"} individual
            {limiteIndividuais === 1 ? "" : "is"}.
          </p>
          {!cicloAtivo && (
            <p>
              Este ciclo não está ativo: a tela está em modo somente leitura e o servidor recusa
              mutações.
            </p>
          )}
        </div>
      </section>

      <section className="goals-kpis" aria-label="Resumo das metas">
        <article>
          <span>Metas cadastradas</span>
          <strong>
            {totalCadastrado}
            <small>/{totalConfigurado}</small>
          </strong>
        </article>
        <article>
          <span>Aguardando aprovação</span>
          <strong>{totalCadastrado - aprovadas}</strong>
        </article>
        <article>
          <span>Em andamento</span>
          <strong>{emAndamento}</strong>
        </article>
        <article>
          <span>Progresso médio</span>
          <strong>
            {progressoMedio}
            <small>%</small>
          </strong>
        </article>
      </section>

      <div className="goals-groups">
        {renderGrupo(
          "Metas de Negócio / Projetos",
          "Resultados ligados às prioridades, entregas e indicadores do negócio.",
          "NEGOCIO_PROJETO",
          metasNegocio,
          limiteNegocio
        )}
        {renderGrupo(
          "Metas Individuais",
          "Objetivos voltados ao desenvolvimento e à evolução profissional.",
          "INDIVIDUAL",
          metasIndividuais,
          limiteIndividuais
        )}
      </div>

      {semEditores && podeAdicionar && (limiteNegocio > 0 || limiteIndividuais > 0) && (
        <section className="goals-editor">
          <div className="goals-editor__header">
            <div>
              <span className="cycle-eyebrow">Cadastro</span>
              <h2>Nova meta</h2>
              <p>Defina a descrição, o KPI mensurável e o valor-alvo.</p>
            </div>
          </div>

          <label className="goals-field">
            <span>Categoria</span>
            <select
              value={tipo}
              onChange={(event) => {
                setTipo(event.target.value as TipoMetaSoberana);
                setErro("");
              }}
              disabled={ocupado || !cicloAtivo}
            >
              {limiteNegocio > 0 && (
                <option value="NEGOCIO_PROJETO" disabled={metasNegocio.length >= limiteNegocio}>
                  Negócio / Projetos
                </option>
              )}
              {limiteIndividuais > 0 && (
                <option
                  value="INDIVIDUAL"
                  disabled={metasIndividuais.length >= limiteIndividuais}
                >
                  Desenvolvimento Individual
                </option>
              )}
            </select>
          </label>

          <label className="goals-field">
            <span>Descrição da meta</span>
            <textarea
              value={descricao}
              onChange={(event) => setDescricao(event.target.value)}
              placeholder="Ex.: Reduzir o tempo médio de publicação"
            />
          </label>

          <div className="goals-editor__grid">
            <label className="goals-field">
              <span>KPI mensurável</span>
              <input
                value={kpi}
                onChange={(event) => setKpi(event.target.value)}
                placeholder="Ex.: Tempo médio entre aprovação e publicação"
              />
            </label>

            <label className="goals-field">
              <span>Valor-alvo</span>
              <input
                value={valorAlvo}
                onChange={(event) => setValorAlvo(event.target.value)}
                placeholder="Ex.: ≤ 4 horas, 95%, R$ 1 milhão"
              />
            </label>
          </div>

          {erro && <div className="goals-error">{erro}</div>}

          <div className="goals-editor__actions">
            <button
              type="button"
              className="cycle-btn cycle-btn--primary"
              onClick={() => void salvar()}
              disabled={ocupado || !cicloAtivo || !podeAdicionar}
            >
              {operacao === "criando" ? "Salvando…" : "Salvar meta"}
            </button>
          </div>
        </section>
      )}

      {ocupado && (
        <p role="status" aria-live="polite" className="cycle-muted">
          {recarregandoLista
            ? "Atualizando a lista pelo servidor…"
            : "Executando a operação no servidor…"}
        </p>
      )}

      {avisoLista && (
        <div className="goals-error" role="alert">
          {avisoLista}
        </div>
      )}
    </main>
  );
}

export default MinhasMetasPage;
