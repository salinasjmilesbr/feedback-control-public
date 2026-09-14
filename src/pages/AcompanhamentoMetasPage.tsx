import { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import CollaboratorIdentity from "../components/CollaboratorIdentity";
import { getColaboradores } from "../services/colaboradorStorage";
import { obterRepositorioMetasSoberanas } from "../services/acessoMetasSoberanas";
import { obterRepositorioCiclosSoberanos } from "../services/acessoCiclosSoberanos";
import type {
  EscopoMetasSoberanas,
  GoalRepository,
  MetaSoberana,
} from "../application/ports/GoalRepository";
import type { PapelAprovacaoMeta } from "../infrastructure/supabase/metas/contrato";
import {
  ERRO_CICLO_NAO_RESOLVIDO,
  ERRO_OPERACAO,
  ERRO_SEM_CAMINHO,
  ERRO_SEM_ORGANIZACAO,
  aprovacaoDoPapel,
  mensagemDoErro,
  metaFormalmenteAprovada,
  pendenteDoPerfil,
  relacaoAutorizaPapel,
} from "./acompanhamentoMetasApoio";
import {
  collaboratorIdDoLegado,
  estruturaSoberanaEfetiva,
} from "../services/estruturaSoberanaCliente";
import { getCiclosAvaliacao } from "./cicloApresentacaoLegada";
import { getColaboradorEfetivoNoCiclo } from "../services/historicoOrganizacionalStorage";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import "../styles/ciclos.css";
import "../styles/metas-gestao.css";
import "../styles/historico-ciclo.css";

/**
 * F5-10 P6 (Issue #220) — CUTOVER FUNCIONAL do acompanhamento de metas.
 *
 * A autoridade de metas desta tela é EXCLUSIVAMENTE a relação CONGELADA devolvida
 * pela superfície soberana (`goal.listar_por_escopo`, via `GoalRepository`):
 * `SELF ∪ APROVADOR_GERENTE_CONGELADO ∪ APROVADOR_COORDENADOR_CONGELADO`. Nada
 * aqui decide autorização: `funcao`, `gestorDiretoMatricula`, `localWorld`,
 * `can()`, `metaStorage` e `localStorage` NÃO participam da leitura nem da
 * aprovação de metas (o colegiado, por consequência, não concede acesso).
 *
 * A tela usa apenas as metas cujo `relacao` autoriza o ator; quando nenhuma meta
 * do alvo está nesse conjunto, a resposta é explícita — nunca uma meta vazada nem
 * um "zero silencioso".
 *
 * As decisões PURAS e as mensagens públicas desta tela vivem no módulo
 * companheiro `./acompanhamentoMetasApoio` (o arquivo exporta só o componente).
 *
 * FASE 4 (tratamento assíncrono): o estado EXIBIDO é DERIVADO de uma leitura
 * CHAVEADA (`leitura?.chave === chave`) — nenhum `setState` síncrono no corpo do
 * efeito; só o resultado é publicado (dentro do `async`/callbacks). Loading e erro
 * são explícitos, o clique duplo é bloqueado, o 409 tem mensagem própria com
 * refresh SOBERANO da leitura e a guarda de unmount (`vigente` no efeito,
 * `montado` nas mutações) impede publicar depois de desmontar.
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** O parâmetro de rota já é a identidade SOBERANA do ciclo? */
function ehUuidCanonico(valor: string | undefined): valor is string {
  return typeof valor === "string" && UUID.test(valor.trim());
}

function formatarDataHora(data?: string | null) {
  if (!data) return "Ainda não atualizado";

  return new Date(data).toLocaleString("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  });
}

function AcompanhamentoMetasPage() {
  const { cicloId, id } = useParams();
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const { organizacaoAtivaId } = useAuth();

  // Contexto de autenticação: organização ativa (intenção de UX, revalidada
  // server-side) e caminho soberano — resolvidos UMA vez (o acessor é memoizado
  // por sessão de página). Sem organização não há leitura de metas.
  const [repo] = useState<GoalRepository | null>(() =>
    obterRepositorioMetasSoberanas()
  );
  const organizacaoId =
    typeof organizacaoAtivaId === "string" && organizacaoAtivaId.length > 0
      ? organizacaoAtivaId
      : null;

  /**
   * Leitura do CICLO, CHAVEADA: `leituraCiclo` só é publicada pelo `async` do
   * efeito e SÓ vale quando a chave dela é a chave corrente. Chave ausente (falta
   * organização ativa) ou chave sem resultado = carregando/indisponível — nunca
   * resolvida por `setState` síncrono no corpo do efeito (fail-closed).
   */
  const [leituraCiclo, setLeituraCiclo] = useState<{
    readonly chave: string;
    readonly uuid: string | null;
    readonly legado: CicloAvaliacao | undefined;
  } | null>(null);

  /**
   * Leitura SOBERANA do escopo de metas, também CHAVEADA: ausência de resultado
   * para a chave CORRENTE significa "carregando", e a chave muda na recarga
   * (refresh soberano pós-409) sem reset de estado local.
   */
  const [leituraMetas, setLeituraMetas] = useState<{
    readonly chave: string;
    readonly escopo: EscopoMetasSoberanas | null;
    readonly erro: string;
  } | null>(null);

  const [erroAprovacao, setErroAprovacao] = useState("");
  const [aprovandoId, setAprovandoId] = useState<string | null>(null);
  const [versaoLeitura, setVersaoLeitura] = useState(0);

  /** Tentativas lógicas de aprovação EM ANDAMENTO (retry reutiliza o mesmo id). */
  const operacoesEmAndamento = useRef(new Map<string, string>());
  /** Evita publicar estado depois do unmount (resposta em voo descartada). */
  const montado = useRef(true);

  useEffect(() => {
    montado.current = true;
    return () => {
      montado.current = false;
    };
  }, []);

  // Chave da leitura do CICLO: parâmetro de rota + organização ativa. Sem
  // organização ativa nada é lido (fail-closed) e não existe chave publicável.
  const chaveCiclo =
    cicloId && organizacaoId ? `${organizacaoId}|${cicloId}` : null;

  /**
   * Identidade soberana do ciclo: o parâmetro é o UUID canônico quando já o é;
   * caso contrário a ÚNICA ponte aceita é a leitura SOBERANA de ciclos (ano/
   * número são só rótulos). SEM fallback local de ciclo.
   */
  useEffect(() => {
    if (chaveCiclo === null || !organizacaoId) return undefined;

    // A chave só existe com organização ativa: o vínculo abaixo é o MESMO da
    // chave corrente (nenhum tenant default, nenhuma identidade inventada).
    const organizationId = organizacaoId;
    const canonico = ehUuidCanonico(cicloId) ? cicloId : null;
    let vigente = true;

    void (async () => {
      if (canonico !== null) {
        if (vigente) {
          setLeituraCiclo({ chave: chaveCiclo, uuid: canonico, legado: undefined });
        }
        return;
      }

      // Ponte de APRESENTAÇÃO apenas (ano/número); a identidade vem do servidor.
      const legado = getCiclosAvaliacao().find((item) => item.id === cicloId);
      const porta = obterRepositorioCiclosSoberanos();

      if (!porta || !legado) {
        if (vigente) {
          setLeituraCiclo({ chave: chaveCiclo, uuid: null, legado: undefined });
        }
        return;
      }

      const resultado = await porta.listarCiclos(organizationId);
      if (!vigente) return;

      const encontrado = resultado.ok
        ? resultado.data.find(
            (ciclo) => ciclo.ano === legado.ano && ciclo.numero === legado.ciclo
          )
        : undefined;

      setLeituraCiclo({
        chave: chaveCiclo,
        uuid: encontrado ? encontrado.id : null,
        legado: encontrado ? legado : undefined,
      });
    })();

    return () => {
      vigente = false;
    };
  }, [chaveCiclo, cicloId, organizacaoId]);

  // A leitura do ciclo só vale para a chave CORRENTE.
  const cicloPublicado =
    leituraCiclo !== null && leituraCiclo.chave === chaveCiclo ? leituraCiclo : null;
  const cicloUuid = cicloPublicado?.uuid ?? null;
  const cicloLegado = cicloPublicado?.legado;
  const erroCiclo =
    cicloId && !organizacaoId
      ? ERRO_SEM_ORGANIZACAO
      : chaveCiclo === null
      ? ""
      : cicloPublicado !== null && cicloPublicado.uuid === null
      ? ERRO_CICLO_NAO_RESOLVIDO
      : "";
  const carregandoCiclo = chaveCiclo !== null && cicloPublicado === null;

  // Chave da leitura de METAS: organização + ciclo soberano + versão de recarga.
  const chaveMetas =
    organizacaoId && cicloUuid
      ? `${organizacaoId}|${cicloUuid}|${versaoLeitura}`
      : null;

  // Leitura SOBERANA do escopo. O ator recebe SOMENTE as metas em que é o dono
  // (SELF) ou o aprovador CONGELADO; nada é decidido no cliente.
  useEffect(() => {
    if (chaveMetas === null || !organizacaoId || !cicloUuid) return undefined;

    // Vínculos NÃO-NULOS da chave corrente: a chave só existe com organização e
    // ciclo soberano resolvidos (nenhum default, nenhuma identidade inventada).
    const organizationId = organizacaoId;
    const cycleId = cicloUuid;
    let vigente = true;

    void (async () => {
      if (!repo) {
        if (vigente) {
          setLeituraMetas({ chave: chaveMetas, escopo: null, erro: ERRO_SEM_CAMINHO });
        }
        return;
      }

      setErroAprovacao("");
      const resultado = await repo.listarMetasPorEscopo(organizationId, cycleId);
      if (!vigente) return;

      if (!resultado.ok) {
        setLeituraMetas({
          chave: chaveMetas,
          escopo: null,
          erro: mensagemDoErro(resultado.error, ERRO_OPERACAO),
        });
        return;
      }

      setLeituraMetas({ chave: chaveMetas, escopo: resultado.data, erro: "" });
    })();

    return () => {
      vigente = false;
    };
  }, [chaveMetas, repo, organizacaoId, cicloUuid, versaoLeitura]);

  const recarregarMetas = useCallback(() => {
    setVersaoLeitura((valor) => valor + 1);
  }, []);

  /**
   * Aprovação soberana de UMA meta por UM papel: `expectedVersion` vem da meta
   * LIDA e o `operationId` é estável por tentativa lógica (retry reutiliza; nova
   * ação gera novo). CONFLICT é tratado explicitamente e força releitura.
   */
  const aprovar = useCallback(
    async (meta: MetaSoberana, papel: PapelAprovacaoMeta) => {
      if (!repo || !organizacaoId) {
        setErroAprovacao(ERRO_SEM_CAMINHO);
        return;
      }

      // Clique duplo/concorrência de UI: uma execução por meta por vez.
      if (aprovandoId !== null) return;
      setAprovandoId(meta.id);
      setErroAprovacao("");

      const operationId =
        operacoesEmAndamento.current.get(meta.id) ?? crypto.randomUUID();
      operacoesEmAndamento.current.set(meta.id, operationId);

      try {
        const resultado = await repo.aprovarMeta({
          organizationId: organizacaoId,
          goalId: meta.id,
          papel,
          expectedVersion: meta.version,
          operationId,
        });

        if (!montado.current) return;

        // Tentativa encerrada (sucesso ou conflito): a próxima ação é NOVA.
        operacoesEmAndamento.current.delete(meta.id);
        setAprovandoId(null);

        if (!resultado.ok) {
          setErroAprovacao(mensagemDoErro(resultado.error, ERRO_OPERACAO));
          // 409/CONFLICT (e qualquer falha): refresh SOBERANO, sem estado local.
          if (resultado.error.code === "CONFLICT") recarregarMetas();
          return;
        }

        recarregarMetas();
      } catch {
        if (!montado.current) return;

        // Falha de transporte: a tentativa lógica CONTINUA (retry reutiliza o id).
        setAprovandoId(null);
        setErroAprovacao(ERRO_OPERACAO);
      }
    },
    [repo, organizacaoId, aprovandoId, recarregarMetas]
  );

  const metasPublicadas =
    leituraMetas !== null && leituraMetas.chave === chaveMetas ? leituraMetas : null;
  const escopo = metasPublicadas?.escopo ?? null;
  const erroMetas = metasPublicadas?.erro ?? "";
  const carregandoMetas = chaveMetas !== null && metasPublicadas === null;

  /**
   * Rota de retorno ao ciclo: SÓ navega com identidade soberana resolvida. Sem
   * UUID o clique volta ao histórico (`navigate(-1)`) — jamais `-1` no lugar de
   * uma rota, jamais uma rota inventada.
   */
  const rotaDoCiclo = cicloUuid ? `/ciclos/${cicloUuid}` : null;
  const voltarAoCiclo = useCallback(() => {
    if (rotaDoCiclo) navigate(rotaDoCiclo);
    else navigate(-1);
  }, [navigate, rotaDoCiclo]);

  if (!usuarioAtual) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Acesso restrito</h1>
          <p>O acompanhamento de metas está disponível para gestores.</p>
        </section>
      </main>
    );
  }

  const colaboradores = getColaboradores();
  const matricula = Number(id);
  const colaboradorAlvo = Number.isFinite(matricula)
    ? colaboradores.find((item) => item.matricula === matricula)
    : undefined;

  // Ponte SOBERANA matrícula → UUID: a matrícula é apenas o rótulo da URL.
  const estruturaSoberana = estruturaSoberanaEfetiva(colaboradores);
  const colaboradorUuid =
    Number.isFinite(matricula) && colaboradorAlvo
      ? collaboratorIdDoLegado(estruturaSoberana, matricula)
      : null;

  if (!colaboradorAlvo || !colaboradorUuid) {
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Metas não encontradas</h1>
          <p>Não foi possível identificar o colaborador pelo caminho soberano.</p>
          <button
            className="cycle-btn cycle-btn--secondary"
            onClick={() => navigate(-1)}
          >
            Voltar
          </button>
        </section>
      </main>
    );
  }

  const metasAutorizadas = (escopo?.metas ?? []).filter(
    (meta) => meta.collaboratorId === colaboradorUuid
  );

  if (metasAutorizadas.length === 0) {
    const aindaCarregando = carregandoCiclo || carregandoMetas;

    if (aindaCarregando || erroCiclo || erroMetas || !escopo) {
      return (
        <main className="virtus-page goals-manager-page">
          <section className="cycle-empty">
            <h1>Acompanhamento de Metas</h1>
            {aindaCarregando ? (
              <p role="status">Carregando metas do ciclo…</p>
            ) : (
              <p role="alert">{erroCiclo || erroMetas || ERRO_OPERACAO}</p>
            )}
            <button
              className="cycle-btn cycle-btn--secondary"
              onClick={() => navigate(-1)}
            >
              Voltar
            </button>
          </section>
        </main>
      );
    }

    // Nenhuma meta do alvo está no escopo autorizado do ator: é exatamente o
    // caso do vínculo apenas de colegiado (e de qualquer relação não congelada).
    return (
      <main className="virtus-page">
        <section className="cycle-empty">
          <h1>Acesso restrito</h1>
          <p>
            A participação como colegiado não concede acesso às metas do
            colaborador.
          </p>
          <button
            className="cycle-btn cycle-btn--secondary"
            onClick={voltarAoCiclo}
          >
            Voltar ao ciclo
          </button>
        </section>
      </main>
    );
  }

  const metas = metasAutorizadas;
  const cicloStatus = escopo?.cicloStatus ?? null;

  const negocio = metas.filter((meta) => meta.tipo === "NEGOCIO_PROJETO");
  const individuais = metas.filter((meta) => meta.tipo === "INDIVIDUAL");
  const aprovadas = metas.filter((meta) => metaFormalmenteAprovada(meta)).length;
  const progressoMedio = metas.length
    ? Math.round(
        metas.reduce(
          (soma, meta) => soma + (meta.progressoPercentual ?? 0),
          0
        ) / metas.length
      )
    : 0;

  // Cada meta responde pela PRÓPRIA relação congelada (o ator pode ser aprovador
  // GERENTE em uma meta e COORDENADOR em outra no mesmo ciclo).
  const pendentesDoPerfil =
    cicloStatus === "CANCELADO" ? 0 : metas.filter(pendenteDoPerfil).length;

  const colaboradorEfetivo =
    cicloLegado === undefined
      ? colaboradorAlvo
      : getColaboradorEfetivoNoCiclo(colaboradorAlvo, cicloLegado, colaboradores);


  function renderMeta(meta: MetaSoberana, indice: number) {
    const aprovacaoGerente = aprovacaoDoPapel(meta, "GERENTE");
    const aprovacaoCoordenador = aprovacaoDoPapel(meta, "COORDENADOR");
    // Autorização POR META: derivada da relação congelada DESTA meta. O conjunto
    // de metas NÃO define papel do ator (achado MEDIUM da auditoria do PR #228).
    const autorizaGerente = relacaoAutorizaPapel(meta.relacao, "GERENTE");
    const autorizaCoordenador = relacaoAutorizaPapel(
      meta.relacao,
      "COORDENADOR"
    );
    const exigeCoordenador = Boolean(aprovacaoCoordenador?.exigida);
    const aprovada = metaFormalmenteAprovada(meta);
    const emExecucao = aprovandoId === meta.id;
    const podeAprovar = cicloStatus === "ATIVO" && !emExecucao;

    return (
      <article className="goals-manager-card" key={meta.id}>
        <div className="goals-manager-card__top">
          <span className="goals-manager-card__number">{indice + 1}</span>
          <div>
            <span className="cycle-eyebrow">
              {meta.tipo === "NEGOCIO_PROJETO"
                ? "Negócio / Projeto"
                : "Individual"}
            </span>
            <h3>{meta.descricao}</h3>
          </div>
          <span
            className={`goals-manager-approval-status ${
              aprovada ? "is-approved" : "is-pending"
            }`}
          >
            {aprovada ? "Aprovada" : "Aguardando aprovação"}
          </span>
        </div>

        <div className="goals-manager-facts">
          <div>
            <span>KPI</span>
            <strong>{meta.kpi}</strong>
          </div>
          <div>
            <span>Valor-alvo</span>
            <strong>{meta.valorAlvo}</strong>
          </div>
          <div>
            <span>Progresso</span>
            <strong>{meta.progressoPercentual ?? 0}%</strong>
          </div>
        </div>

        <div className="goals-manager-progress">
          <div style={{ width: `${meta.progressoPercentual ?? 0}%` }} />
        </div>

        <div className="goals-manager-result">
          <span>Resultado atual</span>
          <strong>{meta.resultadoAtual?.trim() || "Ainda não informado"}</strong>
          <small>
            Última atualização: {formatarDataHora(meta.dataUltimoAcompanhamento)}
          </small>
        </div>

        {meta.resultadoFinal && (
          <div
            className={`goals-manager-final ${
              meta.status === "ATINGIDA" ? "is-success" : "is-danger"
            }`}
          >
            <span>Resultado final</span>
            <strong>{meta.resultadoFinal}</strong>
          </div>
        )}

        <div className="goals-manager-approvals">
          {exigeCoordenador && (
            <label
              className={aprovacaoCoordenador?.vigente ? "is-approved" : ""}
            >
              <input
                type="checkbox"
                checked={Boolean(aprovacaoCoordenador?.vigente)}
                disabled={
                  Boolean(aprovacaoCoordenador?.vigente) ||
                  !autorizaCoordenador ||
                  !podeAprovar
                }
                onChange={() => void aprovar(meta, "COORDENADOR")}
              />
              <span>
                <strong>Aprovação do coordenador direto</strong>
                <small>
                  {aprovacaoCoordenador?.vigente
                    ? `${aprovacaoCoordenador.aprovadorCollaboratorId ?? ""} · ${formatarDataHora(
                        aprovacaoCoordenador.decididoEm
                      )}`
                    : autorizaCoordenador && podeAprovar
                    ? "Marque para aprovar esta meta."
                    : "Aguardando aprovação."}
                </small>
              </span>
            </label>
          )}

          <label className={aprovacaoGerente?.vigente ? "is-approved" : ""}>
            <input
              type="checkbox"
              checked={Boolean(aprovacaoGerente?.vigente)}
              disabled={
                Boolean(aprovacaoGerente?.vigente) ||
                !autorizaGerente ||
                !podeAprovar
              }
              onChange={() => void aprovar(meta, "GERENTE")}
            />
            <span>
              <strong>Aprovação do gerente</strong>
              <small>
                {aprovacaoGerente?.vigente
                  ? `${aprovacaoGerente.aprovadorCollaboratorId ?? ""} · ${formatarDataHora(
                      aprovacaoGerente.decididoEm
                    )}`
                  : autorizaGerente && podeAprovar
                  ? "Marque para aprovar esta meta."
                  : "Aguardando aprovação."}
              </small>
            </span>
          </label>
        </div>

        {!aprovada && cicloStatus === "ENCERRADO" && (
          <div className="goals-manager-warning">
            O ciclo foi encerrado com esta meta sem todas as aprovações formais.
          </div>
        )}
      </article>
    );
  }

  function renderGrupo(
    titulo: string,
    descricao: string,
    metasGrupo: MetaSoberana[]
  ) {
    return (
      <section className="goals-manager-section">
        <header className="goals-manager-section__header">
          <div>
            <span className="cycle-eyebrow">Metas</span>
            <h2>{titulo}</h2>
            <p>{descricao}</p>
          </div>
          <strong>{metasGrupo.length}</strong>
        </header>

        {metasGrupo.length ? (
          <div className="goals-manager-list">
            {metasGrupo.map((meta, indice) => renderMeta(meta, indice))}
          </div>
        ) : (
          <div className="goals-manager-empty">
            Nenhuma meta cadastrada neste bloco.
          </div>
        )}
      </section>
    );
  }

  return (
    <main className="virtus-page goals-manager-page">
      <section className="virtus-page-header goals-manager-page__header goals-manager-page__header--standard">
        <div className="virtus-page-header__copy">
          <h1>Acompanhamento de Metas</h1>
          <p>
            {cicloLegado
              ? `${cicloLegado.ano} • Ciclo ${cicloLegado.ciclo}`
              : "Ciclo soberano"}
          </p>
        </div>

        <div className="virtus-page-actions goals-manager-page__actions">
          <span
            className={`cycle-status ${
              cicloStatus === "ATIVO" ? "is-active" : "is-closed"
            }`}
          >
            {cicloStatus === "ATIVO"
              ? "Ciclo ativo"
              : cicloStatus === "CANCELADO"
              ? "Ciclo cancelado"
              : "Ciclo encerrado"}
          </span>

          <button
            type="button"
            className="virtus-btn virtus-btn--outline"
            onClick={voltarAoCiclo}
          >
            ← Voltar ao ciclo
          </button>
        </div>
      </section>

      <section className="goals-manager-identity">
        <CollaboratorIdentity
          colaborador={colaboradorEfetivo}
          variant="standard"
        />
        {colaboradorEfetivo.gestorDiretoMatricula && (
          <p className="goals-manager-effective-context goals-manager-effective-context--identity">
            Estrutura considerada conforme a vigência registrada no ciclo.
          </p>
        )}
      </section>

      <section className="goals-manager-summary">
        <article>
          <span>Total de metas</span>
          <strong>{metas.length}</strong>
        </article>
        <article>
          <span>Minhas aprovações pendentes</span>
          <strong>{pendentesDoPerfil}</strong>
        </article>
        <article>
          <span>Aprovadas por todos</span>
          <strong>{aprovadas}</strong>
        </article>
        <article>
          <span>Progresso médio</span>
          <strong>{progressoMedio}%</strong>
        </article>
      </section>

      {erroAprovacao && (
        <div className="goals-manager-error" role="alert">
          {erroAprovacao}
        </div>
      )}

      {carregandoMetas && (
        <div className="goals-manager-empty" role="status">
          Atualizando metas…
        </div>
      )}

      <div className="goals-manager-sections">
        {renderGrupo(
          "Negócio / Projetos",
          "Metas relacionadas às entregas, resultados e prioridades do negócio.",
          negocio
        )}
        {renderGrupo(
          "Individuais",
          "Metas de desenvolvimento e evolução individual.",
          individuais
        )}
      </div>
    </main>
  );
}

export default AcompanhamentoMetasPage;
