/**
 * F5-07 — Colaboradores: LEITURA SOBERANA pela porta única.
 *
 * O que mudou em relação ao caminho legado:
 * - a lista vem de `listarColaboradores` (porta única → Edge → RPC); não existe
 *   mais leitura síncrona de `colaboradorStorage` durante o render;
 * - o identificador canônico é `collaboratorId` (UUID) e os links usam UUID;
 * - NÃO existe filtro/agrupamento por texto `respondePara` nem separação de
 *   "equipe direta"/"colegiado" derivada de `funcao`: isso era heurística de
 *   cliente, não estrutura soberana (a estrutura é F5-08);
 * - a organização ativa vem de `useAuth()` e é apenas INTENÇÃO de UX; sem
 *   organização a leitura é recusada explicitamente (fail-closed);
 * - `can()` sobrevive SOMENTE como UX de exibição do botão de cadastro, sobre o
 *   dataset soberano já lido (nunca como autorização efetiva);
 * - a massa de teste continua existindo, mas EXPLICITAMENTE restrita ao modo DEV.
 *
 * `estadoInicial` é uma semente de estado (SSR/embutir a tela já com a leitura
 * resolvida): a produção normal sempre carrega pela porta. `deps` permite injetar
 * as operações da porta em teste.
 */

import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import { useAuth } from "../auth/AuthContext";
import { simulacaoDevPermitida } from "../config/ambiente";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import { getCiclosAdministrativos } from "../services/cicloAvaliacaoStorage";
import {
  listarColaboradores,
  type ColaboradorSoberano,
  type DependenciasAcessoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import { gerarDadosTesteDoCiclo } from "../services/geradorDadosTeste";
import type { Colaborador, StatusColaborador } from "../types/Colaborador";
import "../styles/collaborator-identity.css";
import "../styles/dados-teste.css";
import "../styles/equipe-colegiado.css";

/** Estado explícito da leitura: carregando, erro público ou projeção pronta. */
export type EstadoColaboradores =
  | { readonly fase: "carregando" }
  | {
      readonly fase: "erro";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | {
      readonly fase: "pronto";
      readonly colaboradores: readonly ColaboradorSoberano[];
    };

type ColaboradoresPageProps = {
  /** Operações da porta (injeção de teste); produção usa o caminho padrão. */
  readonly deps?: DependenciasAcessoColaboradores;
  /** Semente de estado (SSR/embutir a tela com a leitura já resolvida). */
  readonly estadoInicial?: EstadoColaboradores;
};

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

const SEM_ORGANIZACAO_ATIVA =
  "Selecione uma organização ativa para consultar os colaboradores.";

const AVISO_ESTRUTURA =
  "Sem alocação: não existe ocupação vigente para este colaborador. " +
  "A alocação é definida na ficha do colaborador.";

function rotuloStatus(status: string): string {
  if (status === "active") return "Ativo";
  if (status === "leave") return "Em licença";
  if (status === "inactive") return "Desligado";
  return status || "—";
}

function classeStatus(status: string): string {
  if (status === "active") return "is-active";
  if (status === "leave") return "is-leave";
  return "is-inactive";
}

function iniciaisDe(nome: string): string {
  return nome
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((parte) => parte[0])
    .join("")
    .toUpperCase();
}

/** Existe alocação soberana vigente? A ausência é exibida, nunca inventada. */
function possuiAlocacao(colaborador: ColaboradorSoberano): boolean {
  return Boolean(
    colaborador.unitId ??
      colaborador.unitName ??
      colaborador.jobRoleCode ??
      colaborador.jobRoleName ??
      colaborador.seniorityName ??
      colaborador.managerCollaboratorId ??
      colaborador.managerFullName
  );
}

function statusLegado(status: string): StatusColaborador {
  if (status === "leave") return "LICENCA";
  if (status === "inactive") return "DESLIGADO";
  return "ATIVO";
}

/**
 * Projeção MÍNIMA da projeção soberana para o vocabulário legado usado pelo
 * Policy Engine de UX (`can()`). Nenhum campo de estrutura é inventado: o que não
 * existe na projeção permanece vazio. Isto NÃO é autoridade — a decisão real é do
 * servidor, que devolve `FORBIDDEN`/`NOT_FOUND` quando nega.
 */
function paraVocabularioUx(
  colaboradores: readonly ColaboradorSoberano[]
): readonly Colaborador[] {
  return colaboradores.flatMap((colaborador) => {
    const matricula = Number(colaborador.matricula);
    if (!Number.isInteger(matricula) || matricula <= 0) return [];
    return [
      {
        matricula,
        nome: colaborador.fullName,
        email: colaborador.email,
        cargo: colaborador.jobRoleName ?? "",
        area: colaborador.unitName ?? "",
        status: statusLegado(colaborador.status),
        respondePara: "",
      },
    ];
  });
}

function ColaboradoresPage({
  deps,
  estadoInicial,
}: ColaboradoresPageProps = {}) {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const { organizacaoAtivaId } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [carregamento, setCarregamento] = useState<{
    readonly chave: string;
    readonly estado: EstadoColaboradores;
  } | null>(null);
  const [versao, setVersao] = useState(0);
  const [busca, setBusca] = useState("");
  const [statusFiltro, setStatusFiltro] = useState("TODOS");
  const [cicloTesteId, setCicloTesteId] = useState("");

  /** Chave da leitura corrente: organização ativa + versão de recarga. */
  const chaveCarregamento = `${organizacaoAtivaId ?? "sem-organizacao"}|${versao}`;

  useEffect(() => {
    if (estadoInicial || !organizacaoAtivaId) return;

    let vigente = true;

    void listarColaboradores(
      { organizationId: organizacaoAtivaId },
      depsInjetadas
    ).then((resultado) => {
      if (!vigente) return;
      setCarregamento({
        chave: chaveCarregamento,
        estado: resultado.ok
          ? { fase: "pronto", colaboradores: resultado.dados }
          : {
              fase: "erro",
              codigo: resultado.codigo,
              mensagem: resultado.mensagem,
            },
      });
    });

    return () => {
      vigente = false;
    };
  }, [chaveCarregamento, organizacaoAtivaId, estadoInicial, depsInjetadas]);

  /**
   * Estado exibido DERIVADO: enquanto não há resultado para a chave corrente a
   * tela está carregando (sem `setState` síncrono no efeito). Sem organização
   * ativa a operação é fail-closed: estado restrito explícito, sem leitura.
   */
  const estado: EstadoColaboradores =
    !organizacaoAtivaId && !estadoInicial
      ? { fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ORGANIZACAO_ATIVA }
      : (estadoInicial ??
        (carregamento?.chave === chaveCarregamento
          ? carregamento.estado
          : { fase: "carregando" }));

  // Massa de teste: ferramenta de desenvolvimento, JAMAIS fallback do caminho
  // soberano. Fora do modo DEV explícito ela não é exibida nem executada.
  const painelDev = simulacaoDevPermitida && Boolean(usuarioAtual);
  const ciclosDisponiveis = painelDev ? getCiclosAdministrativos() : [];
  const cicloTesteSelecionado = cicloTesteId || ciclosDisponiveis[0]?.id || "";

  const colaboradores =
    estado.fase === "pronto" ? estado.colaboradores : [];
  const vocabularioUx = paraVocabularioUx(colaboradores);
  const contextoUx: AuthorizationContext | undefined = usuarioAtual
    ? {
        actor: {
          matricula: usuarioAtual.matricula,
          funcao: usuarioAtual.funcao,
          status: usuarioAtual.status,
        },
      }
    : undefined;
  // UX apenas: sem dataset soberano não há decisão local — o botão é omitido e o
  // servidor continua sendo o gate real da operação.
  const podeCriarColaborador =
    contextoUx && vocabularioUx.length > 0
      ? can(contextoUx, "collaborator.create", {
          kind: "global",
          collaborators: vocabularioUx,
        })
      : false;

  const termo = busca.trim().toLowerCase();
  const colaboradoresFiltrados = colaboradores.filter((colaborador) => {
    const correspondeBusca =
      termo === "" ||
      colaborador.fullName.toLowerCase().includes(termo) ||
      colaborador.email.toLowerCase().includes(termo) ||
      (colaborador.matricula ?? "").toLowerCase().includes(termo);
    const correspondeStatus =
      statusFiltro === "TODOS" || colaborador.status === statusFiltro;
    return correspondeBusca && correspondeStatus;
  });

  const temFiltro = termo !== "" || statusFiltro !== "TODOS";

  function limparFiltros() {
    setBusca("");
    setStatusFiltro("TODOS");
  }

  function tentarNovamente() {
    setVersao((valor) => valor + 1);
  }

  function gerarMassaTeste() {
    if (!painelDev || !usuarioAtual) return;

    const ciclo = ciclosDisponiveis.find(
      (item) => item.id === cicloTesteSelecionado
    );

    if (!ciclo) {
      window.alert("Selecione um ciclo para gerar os dados de teste.");
      return;
    }

    const confirmar = window.confirm(
      `Gerar uma nova massa de dados para ${ciclo.ano} • Ciclo ${ciclo.ciclo}?\n\n` +
        "As avaliações, metas e observações já existentes nesse ciclo serão substituídas por dados aleatórios de teste."
    );

    if (!confirmar) return;

    try {
      const resultado = gerarDadosTesteDoCiclo(ciclo, usuarioAtual);
      window.alert(
        `Dados de teste gerados com sucesso.\n\n` +
          `Colaboradores: ${resultado.colaboradores}\n` +
          `Avaliações: ${resultado.avaliacoes}\n` +
          `Metas: ${resultado.metas}\n` +
          `Observações: ${resultado.observacoes}`
      );
      window.location.reload();
    } catch (error) {
      window.alert(
        error instanceof Error
          ? error.message
          : "Não foi possível gerar os dados de teste."
      );
    }
  }

  return (
    <main className="virtus-page collaborators-v2">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Colaboradores</h1>
          <p>
            Cadastro soberano de pessoas, matrícula e status vigentes no
            PostgreSQL. A alocação (unidade, cargo, senioridade e gestor) vem da
            ocupação vigente definida na ficha do colaborador.
          </p>
        </div>

        <div className="virtus-page-actions">
          {podeCriarColaborador && (
            <button
              className="virtus-btn virtus-btn--primary"
              onClick={() => navigate("/colaboradores/novo")}
            >
              <span className="virtus-btn__plus" aria-hidden="true">
                ＋
              </span>
              Novo colaborador
            </button>
          )}
        </div>
      </section>

      {painelDev && ciclosDisponiveis.length > 0 && (
        <section className="test-data-panel">
          <div className="test-data-panel__copy">
            <span className="test-data-panel__eyebrow">
              Ferramenta temporária de desenvolvimento
            </span>
            <strong>Gerar dados de teste (DEV)</strong>
            <p>
              Preenche avaliações, comentários, feedbacks finais, metas e
              observações com dados variados para o ciclo selecionado. Restrita
              ao modo DEV: não é caminho soberano nem fallback.
            </p>
          </div>

          <div className="test-data-panel__actions">
            <label>
              <span>Ciclo</span>
              <select
                value={cicloTesteSelecionado}
                onChange={(event) => setCicloTesteId(event.target.value)}
              >
                {ciclosDisponiveis.map((ciclo) => (
                  <option key={ciclo.id} value={ciclo.id}>
                    {ciclo.ano} • Ciclo {ciclo.ciclo} —{" "}
                    {ciclo.status === "ATIVO"
                      ? "Ativo"
                      : ciclo.status === "PLANEJADO"
                        ? "Planejado"
                        : "Encerrado"}
                  </option>
                ))}
              </select>
            </label>

            <button
              type="button"
              className="virtus-btn virtus-btn--outline test-data-panel__button"
              onClick={gerarMassaTeste}
            >
              Gerar nova massa
            </button>
          </div>
        </section>
      )}

      <section className="virtus-filter-card">
        <div className="virtus-filter-grid">
          <label className="virtus-field virtus-field--search">
            <span>Buscar colaborador</span>
            <div className="virtus-input-wrap">
              <span className="virtus-search-icon" aria-hidden="true">
                ⌕
              </span>
              <input
                value={busca}
                onChange={(event) => setBusca(event.target.value)}
                placeholder="Buscar por nome, e-mail ou matrícula..."
              />
            </div>
          </label>

          <label className="virtus-field">
            <span>Status</span>
            <select
              value={statusFiltro}
              onChange={(event) => setStatusFiltro(event.target.value)}
            >
              <option value="TODOS">Todos os status</option>
              <option value="active">Ativos</option>
              <option value="leave">Em licença</option>
              <option value="inactive">Desligados</option>
            </select>
          </label>

          <button
            className="virtus-btn virtus-btn--filter"
            onClick={limparFiltros}
            disabled={!temFiltro}
          >
            <span aria-hidden="true">▽</span>
            Limpar filtros
          </button>
        </div>

        {estado.fase === "pronto" && (
          <div className="virtus-filter-footer">
            <div>
              <strong>{colaboradoresFiltrados.length}</strong>{" "}
              {colaboradoresFiltrados.length === 1
                ? "colaborador encontrado"
                : "colaboradores encontrados"}
            </div>
            <div className="virtus-view-info">
              Exibindo {colaboradoresFiltrados.length} de {colaboradores.length}
            </div>
          </div>
        )}
      </section>

      {estado.fase === "carregando" && (
        <section className="virtus-empty" role="status" aria-live="polite">
          <h2>Carregando colaboradores…</h2>
          <p>Consultando o cadastro soberano no servidor.</p>
        </section>
      )}

      {estado.fase === "erro" && (
        <section className="virtus-empty" role="alert">
          <h2>
            {estado.codigo === "FORBIDDEN"
              ? "Acesso restrito"
              : "Não foi possível carregar os colaboradores"}
          </h2>
          <p>{estado.mensagem}</p>
          <p>
            Nenhum dado local é exibido como substituto: a lista exige leitura
            autorizada no servidor.
          </p>
          <button
            type="button"
            className="virtus-btn virtus-btn--outline"
            onClick={tentarNovamente}
          >
            Tentar novamente
          </button>
        </section>
      )}

      {estado.fase === "pronto" &&
        (colaboradoresFiltrados.length > 0 ? (
          <section className="virtus-collaborators-grid">
            {colaboradoresFiltrados.map((colaborador) => (
              <article
                className="collaborator-card collaborator-card--identity"
                key={colaborador.collaboratorId}
              >
                <div className="collaborator-identity collaborator-identity--standard">
                  <div
                    className="collaborator-identity__avatar"
                    aria-hidden="true"
                  >
                    {iniciaisDe(colaborador.fullName)}
                  </div>

                  <div className="collaborator-identity__body">
                    <div className="collaborator-identity__title">
                      <strong>{colaborador.fullName}</strong>
                      <span
                        className={`collaborator-identity__status ${classeStatus(
                          colaborador.status
                        )}`}
                      >
                        {rotuloStatus(colaborador.status)}
                      </span>
                    </div>

                    <div className="collaborator-identity__role">
                      {colaborador.jobRoleName ?? "Sem alocação"}
                      {colaborador.seniorityName
                        ? ` • ${colaborador.seniorityName}`
                        : ""}
                    </div>

                    <div className="collaborator-identity__details">
                      {colaborador.unitName && (
                        <span className="collaborator-identity__detail">
                          <span>{colaborador.unitName}</span>
                        </span>
                      )}
                      {colaborador.managerFullName && (
                        <span className="collaborator-identity__detail">
                          <span>
                            Gestor:{" "}
                            <strong>{colaborador.managerFullName}</strong>
                          </span>
                        </span>
                      )}
                      {colaborador.matricula && (
                        <span className="collaborator-identity__detail">
                          <span>Matrícula {colaborador.matricula}</span>
                        </span>
                      )}
                      <span className="collaborator-identity__detail">
                        <span>{colaborador.email}</span>
                      </span>
                    </div>

                    {!possuiAlocacao(colaborador) && (
                      <p className="collaborator-identity__role">
                        {AVISO_ESTRUTURA}
                      </p>
                    )}
                  </div>
                </div>

                <div className="collaborator-card__footer collaborator-card__footer--identity">
                  <Link
                    className="collaborator-card__link"
                    to={`/colaborador/${colaborador.collaboratorId}`}
                  >
                    Ver histórico
                    <span aria-hidden="true">→</span>
                  </Link>
                </div>
              </article>
            ))}
          </section>
        ) : (
          <section className="virtus-empty">
            <h2>Nenhum colaborador encontrado</h2>
            <p>Altere os filtros para ampliar os resultados.</p>
          </section>
        ))}
    </main>
  );
}

export default ColaboradoresPage;
