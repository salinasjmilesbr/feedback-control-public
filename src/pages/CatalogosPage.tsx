/**
 * F5-08 P4 — Catálogos: cargos (`job_roles`) e senioridades
 * (`seniority_levels`).
 *
 * - LEITURA: soberana, own-tenant, pela via RLS (D16) — sem capability.
 * - ESCRITA: pelas operações administrativas do P3 (`catalogo.cargo.*`,
 *   `catalogo.senioridade.*`) via porta única → Edge → RPC; o servidor decide a
 *   autorização (`org.catalog.manage`) e devolve o código público.
 * - A tela NÃO decide autorização, tenant nem vigência: envia `operationId`,
 *   `expectedVersion` LIDO do servidor e `motivo`; trata `FORBIDDEN` (sem
 *   retry), `CONFLICT`/`NOT_FOUND` (com recarga da leitura) e `INVALID_INPUT`.
 * - Nenhuma escrita local: `localStorage` não participa deste fluxo.
 */

import { useEffect, useState } from "react";
import { useAuth } from "../auth/AuthContext";
import {
  alterarStatusCargo,
  alterarStatusSenioridade,
  criarCargo,
  criarSenioridade,
  lerEstrutura,
  renomearCargo,
  renomearSenioridade,
  type DependenciasAcessoColaboradores,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import {
  SEM_ORGANIZACAO_ATIVA,
  TEXTO_ERRO_ESTRUTURA,
  novoOperationId,
  rotuloStatusCatalogo,
  type ErroOperacao,
  type EstadoEstrutura,
} from "./apoioEstrutura";
import "../styles/estrutura.css";

type CatalogosPageProps = {
  /** Operações da porta (injeção de teste); produção usa o caminho padrão. */
  readonly deps?: DependenciasAcessoColaboradores;
  /** Semente de estado (SSR/teste determinístico). */
  readonly estadoInicial?: EstadoEstrutura;
};

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

type EdicaoAtiva = {
  readonly tipo: "cargo" | "senioridade";
  readonly id: string;
  readonly acao: "renomear" | "status";
  readonly nomeAtual: string;
  readonly statusAtual: string;
};

function CatalogosPage({ deps, estadoInicial }: CatalogosPageProps = {}) {
  const { organizacaoAtivaId } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [erro, setErro] = useState<ErroOperacao | null>(null);
  const [sucesso, setSucesso] = useState("");
  const [processando, setProcessando] = useState(false);

  const [cargoNome, setCargoNome] = useState("");
  const [cargoCode, setCargoCode] = useState("");
  const [cargoMotivo, setCargoMotivo] = useState("");

  const [senioridadeNome, setSenioridadeNome] = useState("");
  const [senioridadeMotivo, setSenioridadeMotivo] = useState("");

  const [edicao, setEdicao] = useState<EdicaoAtiva | null>(null);
  const [edicaoNome, setEdicaoNome] = useState("");
  const [edicaoMotivo, setEdicaoMotivo] = useState("");

  /** Versão de recarga: incrementar descarta a leitura anterior (sem cache). */
  const [versao, setVersao] = useState(0);
  /** Chave da leitura corrente: organização ativa + versão de recarga. */
  const chaveCarregamento = `${organizacaoAtivaId ?? "sem-organizacao"}|${versao}`;
  const [carregamento, setCarregamento] = useState<{
    readonly chave: string;
    readonly estado: EstadoEstrutura;
  } | null>(estadoInicial ? { chave: "semente", estado: estadoInicial } : null);

  useEffect(() => {
    if (estadoInicial || !organizacaoAtivaId) return;

    let vigente = true;

    void lerEstrutura({ organizationId: organizacaoAtivaId }, depsInjetadas).then(
      (resultado) => {
        if (!vigente) return;
        setCarregamento({
          chave: chaveCarregamento,
          estado: resultado.ok
            ? { fase: "pronto", estrutura: resultado.dados }
            : {
                fase: "erro",
                codigo: resultado.codigo,
                mensagem: resultado.mensagem,
              },
        });
      }
    );

    return () => {
      vigente = false;
    };
  }, [chaveCarregamento, organizacaoAtivaId, estadoInicial, depsInjetadas]);

  /**
   * Estado exibido DERIVADO (sem `setState` síncrono no efeito): sem organização
   * ativa a leitura é fail-closed e explícita; enquanto não há resultado para a
   * chave corrente, a tela está carregando.
   */
  const estado: EstadoEstrutura =
    !organizacaoAtivaId && !estadoInicial
      ? { fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ORGANIZACAO_ATIVA }
      : (estadoInicial ??
        (carregamento?.chave === chaveCarregamento
          ? carregamento.estado
          : { fase: "carregando" }));

  /**
   * Executa uma mutação e normaliza o desfecho:
   * - sucesso ⇒ recarrega a leitura (nenhum cache sobrevive à mutação);
   * - `CONFLICT`/`NOT_FOUND` ⇒ mensagem do servidor + recarga (o estado exibido
   *   estava desatualizado);
   * - `FORBIDDEN`/`INVALID_INPUT`/demais ⇒ mensagem exibida, SEM retry.
   */
  async function executar(
    operacao: () => Promise<ResultadoColaboradores<unknown>>,
    motivo: string,
    aoConcluir?: () => void
  ) {
    if (processando) return;
    setErro(null);
    setSucesso("");

    if (!motivo.trim()) {
      setErro({ codigo: "INVALID_INPUT", mensagem: "Informe o motivo da alteração." });
      return;
    }

    setProcessando(true);
    const resultado = await operacao();
    setProcessando(false);

    if (!resultado.ok) {
      setErro({ codigo: resultado.codigo, mensagem: resultado.mensagem });
      if (resultado.codigo === "CONFLICT" || resultado.codigo === "NOT_FOUND") {
        setVersao((atual) => atual + 1);
      }
      return;
    }

    setSucesso("Alteração registrada no catálogo.");
    aoConcluir?.();
    setVersao((atual) => atual + 1);
  }

  if (estado.fase === "carregando") {
    return (
      <main className="virtus-page estrutura-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Catálogos</h1>
            <p>Cargos e senioridades da organização.</p>
          </div>
        </section>
        <p className="estrutura-estado" role="status">
          Carregando catálogos…
        </p>
      </main>
    );
  }

  if (estado.fase === "erro") {
    return (
      <main className="virtus-page estrutura-page">
        <section className="virtus-page-header">
          <div className="virtus-page-header__copy">
            <h1>Catálogos</h1>
            <p>Cargos e senioridades da organização.</p>
          </div>
        </section>
        <p className="estrutura-estado estrutura-estado--erro" role="alert">
          {estado.mensagem} ({estado.codigo})
        </p>
      </main>
    );
  }

  const { cargos, senioridades } = estado.estrutura;
  const semItens = cargos.length === 0 && senioridades.length === 0;

  return (
    <main className="virtus-page estrutura-page">
      <section className="virtus-page-header">
        <div className="virtus-page-header__copy">
          <h1>Catálogos</h1>
          <p>
            Cargos e senioridades são RÓTULOS de referência: a identidade é o UUID.
            Renomear não altera histórico; desativar impede apenas referência nova.
          </p>
        </div>
      </section>

      {erro && (
        <p
          className="estrutura-estado estrutura-estado--erro"
          role="alert"
          data-testid="catalogos-erro"
        >
          {erro.mensagem} ({erro.codigo})
        </p>
      )}

      {sucesso && (
        <p className="estrutura-estado estrutura-estado--ok" role="status">
          {sucesso}
        </p>
      )}

      {semItens && (
        <p className="estrutura-estado" role="status">
          {TEXTO_ERRO_ESTRUTURA}
        </p>
      )}

      <section className="estrutura-card" data-testid="catalogo-cargos">
        <header className="estrutura-card__header">
          <h2>Cargos</h2>
          <span>{cargos.length} registro(s)</span>
        </header>

        <form
          className="estrutura-form"
          onSubmit={(evento) => {
            evento.preventDefault();
            void executar(
              () =>
                criarCargo(
                  {
                    operationId: novoOperationId(),
                    nome: cargoNome.trim(),
                    code: cargoCode.trim() ? cargoCode.trim() : null,
                    motivo: cargoMotivo.trim(),
                    ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                  },
                  depsInjetadas
                ),
              cargoMotivo,
              () => {
                setCargoNome("");
                setCargoCode("");
                setCargoMotivo("");
              }
            );
          }}
        >
          <label className="virtus-field">
            <span>Nome do cargo *</span>
            <input
              value={cargoNome}
              onChange={(evento) => setCargoNome(evento.target.value)}
              required
            />
          </label>
          <label className="virtus-field">
            <span>Código (opcional)</span>
            <input
              value={cargoCode}
              onChange={(evento) => setCargoCode(evento.target.value)}
            />
          </label>
          <label className="virtus-field">
            <span>Motivo *</span>
            <input
              value={cargoMotivo}
              onChange={(evento) => setCargoMotivo(evento.target.value)}
              required
            />
          </label>
          <button
            type="submit"
            className="virtus-btn virtus-btn--primary"
            disabled={processando}
            data-testid="cargo-criar"
          >
            Criar cargo
          </button>
        </form>

        <ul className="estrutura-lista">
          {cargos.map((cargo) => (
            <li key={cargo.jobRoleId} className="estrutura-item" data-id={cargo.jobRoleId}>
              <div className="estrutura-item__copy">
                <strong>{cargo.nome}</strong>
                <span>
                  {cargo.code ? `Código ${cargo.code} • ` : ""}
                  {rotuloStatusCatalogo(cargo.status)} • versão {cargo.version}
                </span>
              </div>
              <div className="estrutura-item__actions">
                <button
                  type="button"
                  className="virtus-btn virtus-btn--outline"
                  onClick={() => {
                    setEdicao({
                      tipo: "cargo",
                      id: cargo.jobRoleId,
                      acao: "renomear",
                      nomeAtual: cargo.nome,
                      statusAtual: cargo.status,
                    });
                    setEdicaoNome(cargo.nome);
                    setEdicaoMotivo("");
                  }}
                >
                  Renomear
                </button>
                <button
                  type="button"
                  className="virtus-btn virtus-btn--outline"
                  onClick={() => {
                    setEdicao({
                      tipo: "cargo",
                      id: cargo.jobRoleId,
                      acao: "status",
                      nomeAtual: cargo.nome,
                      statusAtual: cargo.status,
                    });
                    setEdicaoNome(cargo.nome);
                    setEdicaoMotivo("");
                  }}
                >
                  {cargo.status === "active" ? "Desativar" : "Ativar"}
                </button>
              </div>
            </li>
          ))}
          {cargos.length === 0 && (
            <li className="estrutura-item estrutura-item--vazio">
              Nenhum cargo cadastrado nesta organização.
            </li>
          )}
        </ul>
      </section>

      <section className="estrutura-card" data-testid="catalogo-senioridades">
        <header className="estrutura-card__header">
          <h2>Senioridades</h2>
          <span>{senioridades.length} registro(s)</span>
        </header>

        <form
          className="estrutura-form"
          onSubmit={(evento) => {
            evento.preventDefault();
            void executar(
              () =>
                criarSenioridade(
                  {
                    operationId: novoOperationId(),
                    nome: senioridadeNome.trim(),
                    motivo: senioridadeMotivo.trim(),
                    ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                  },
                  depsInjetadas
                ),
              senioridadeMotivo,
              () => {
                setSenioridadeNome("");
                setSenioridadeMotivo("");
              }
            );
          }}
        >
          <label className="virtus-field">
            <span>Nome da senioridade *</span>
            <input
              value={senioridadeNome}
              onChange={(evento) => setSenioridadeNome(evento.target.value)}
              required
            />
          </label>
          <label className="virtus-field">
            <span>Motivo *</span>
            <input
              value={senioridadeMotivo}
              onChange={(evento) => setSenioridadeMotivo(evento.target.value)}
              required
            />
          </label>
          <button
            type="submit"
            className="virtus-btn virtus-btn--primary"
            disabled={processando}
            data-testid="senioridade-criar"
          >
            Criar senioridade
          </button>
        </form>

        <ul className="estrutura-lista">
          {senioridades.map((senioridade) => (
            <li
              key={senioridade.seniorityLevelId}
              className="estrutura-item"
              data-id={senioridade.seniorityLevelId}
            >
              <div className="estrutura-item__copy">
                <strong>{senioridade.nome}</strong>
                <span>
                  {rotuloStatusCatalogo(senioridade.status)} • versão {senioridade.version}
                </span>
              </div>
              <div className="estrutura-item__actions">
                <button
                  type="button"
                  className="virtus-btn virtus-btn--outline"
                  onClick={() => {
                    setEdicao({
                      tipo: "senioridade",
                      id: senioridade.seniorityLevelId,
                      acao: "renomear",
                      nomeAtual: senioridade.nome,
                      statusAtual: senioridade.status,
                    });
                    setEdicaoNome(senioridade.nome);
                    setEdicaoMotivo("");
                  }}
                >
                  Renomear
                </button>
                <button
                  type="button"
                  className="virtus-btn virtus-btn--outline"
                  onClick={() => {
                    setEdicao({
                      tipo: "senioridade",
                      id: senioridade.seniorityLevelId,
                      acao: "status",
                      nomeAtual: senioridade.nome,
                      statusAtual: senioridade.status,
                    });
                    setEdicaoNome(senioridade.nome);
                    setEdicaoMotivo("");
                  }}
                >
                  {senioridade.status === "active" ? "Desativar" : "Ativar"}
                </button>
              </div>
            </li>
          ))}
          {senioridades.length === 0 && (
            <li className="estrutura-item estrutura-item--vazio">
              Nenhuma senioridade cadastrada nesta organização.
            </li>
          )}
        </ul>
      </section>

      {edicao && (
        <section className="estrutura-card" data-testid="catalogo-edicao">
          <header className="estrutura-card__header">
            <h2>
              {edicao.acao === "renomear" ? "Renomear" : "Alterar status"}: {edicao.nomeAtual}
            </h2>
            <span>identidade {edicao.id}</span>
          </header>

          <form
            className="estrutura-form"
            onSubmit={(evento) => {
              evento.preventDefault();
              const proximoStatus = edicao.statusAtual === "active" ? "disabled" : "active";
              if (edicao.tipo === "cargo" && edicao.acao === "renomear") {
                const cargo = cargos.find((item) => item.jobRoleId === edicao.id);
                void executar(
                  () =>
                    renomearCargo(
                      {
                        operationId: novoOperationId(),
                        jobRoleId: edicao.id,
                        nome: edicaoNome.trim(),
                        expectedVersion: cargo?.version ?? 0,
                        motivo: edicaoMotivo.trim(),
                        ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                      },
                      depsInjetadas
                    ),
                  edicaoMotivo,
                  () => setEdicao(null)
                );
                return;
              }
              if (edicao.tipo === "cargo") {
                const cargo = cargos.find((item) => item.jobRoleId === edicao.id);
                void executar(
                  () =>
                    alterarStatusCargo(
                      {
                        operationId: novoOperationId(),
                        jobRoleId: edicao.id,
                        status: proximoStatus,
                        expectedVersion: cargo?.version ?? 0,
                        motivo: edicaoMotivo.trim(),
                        ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                      },
                      depsInjetadas
                    ),
                  edicaoMotivo,
                  () => setEdicao(null)
                );
                return;
              }
              if (edicao.acao === "renomear") {
                const senioridade = senioridades.find(
                  (item) => item.seniorityLevelId === edicao.id
                );
                void executar(
                  () =>
                    renomearSenioridade(
                      {
                        operationId: novoOperationId(),
                        seniorityLevelId: edicao.id,
                        nome: edicaoNome.trim(),
                        expectedVersion: senioridade?.version ?? 0,
                        motivo: edicaoMotivo.trim(),
                        ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                      },
                      depsInjetadas
                    ),
                  edicaoMotivo,
                  () => setEdicao(null)
                );
                return;
              }
              const senioridade = senioridades.find(
                (item) => item.seniorityLevelId === edicao.id
              );
              void executar(
                () =>
                  alterarStatusSenioridade(
                    {
                      operationId: novoOperationId(),
                      seniorityLevelId: edicao.id,
                      status: proximoStatus,
                      expectedVersion: senioridade?.version ?? 0,
                      motivo: edicaoMotivo.trim(),
                      ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                    },
                    depsInjetadas
                  ),
                edicaoMotivo,
                () => setEdicao(null)
              );
            }}
          >
            {edicao.acao === "renomear" && (
              <label className="virtus-field">
                <span>Novo nome *</span>
                <input
                  value={edicaoNome}
                  onChange={(evento) => setEdicaoNome(evento.target.value)}
                  required
                />
              </label>
            )}
            <label className="virtus-field">
              <span>Motivo *</span>
              <input
                value={edicaoMotivo}
                onChange={(evento) => setEdicaoMotivo(evento.target.value)}
                required
              />
            </label>
            <button
              type="submit"
              className="virtus-btn virtus-btn--primary"
              disabled={processando}
              data-testid="catalogo-edicao-confirmar"
            >
              Confirmar
            </button>
            <button
              type="button"
              className="virtus-btn virtus-btn--outline"
              onClick={() => setEdicao(null)}
            >
              Cancelar
            </button>
          </form>
        </section>
      )}

      <p className="estrutura-nota">
        Renomear altera apenas o rótulo; o `code` do cargo é imutável por contrato.
        Unicidade, vigência e integridade são verificadas no servidor.
      </p>
    </main>
  );
}

export default CatalogosPage;
