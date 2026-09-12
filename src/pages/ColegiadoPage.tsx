/**
 * F5-08 P4 — Colegiado por AVALIADO.
 *
 * - LEITURA: soberana own-tenant pela via RLS (D16). A tela distingue três
 *   estados com significados diferentes: (i) versão vigente com membros;
 *   (ii) versão vigente com ZERO membros = "sem colegiado" EXPLÍCITO;
 *   (iii) nenhuma versão vigente = nunca configurado / encerrado.
 * - ESCRITA: `estrutura.colegiado.definir|encerrar` (plano administrativo D19,
 *   `org.structure.manage`). A lista de membros é 0..N — NENHUM teto é imposto
 *   no cliente; duplicidade, self-member e tenant são validados no servidor.
 * - Membros são selecionados por UUID; nomes são apenas rótulos de exibição.
 */

import { useEffect, useState } from "react";
import { useAuth } from "../auth/AuthContext";
import {
  definirColegiado,
  encerrarColegiado,
  lerEstrutura,
  type DependenciasAcessoColaboradores,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import {
  SEM_ORGANIZACAO_ATIVA,
  colegiadoVigente,
  historicoColegiado,
  hojeLocal,
  nomeDoColaborador,
  novoOperationId,
  rotuloVigencia,
  type ErroOperacao,
  type EstadoEstrutura,
} from "./apoioEstrutura";
import "../styles/estrutura.css";

type ColegiadoPageProps = {
  readonly deps?: DependenciasAcessoColaboradores;
  readonly estadoInicial?: EstadoEstrutura;
  /**
   * Avaliado pré-selecionado (UUID) — semente de estado para SSR/teste. Em
   * produção a seleção é sempre explícita na tela (é INTENÇÃO, não autoridade).
   */
  readonly avaliadoInicial?: string;
};

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

function ColegiadoPage({ deps, estadoInicial, avaliadoInicial }: ColegiadoPageProps = {}) {
  const { organizacaoAtivaId } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [erro, setErro] = useState<ErroOperacao | null>(null);
  const [sucesso, setSucesso] = useState("");
  const [processando, setProcessando] = useState(false);

  const [avaliadoId, setAvaliadoId] = useState(avaliadoInicial ?? "");
  const [membros, setMembros] = useState<readonly string[]>([]);
  const [inicio, setInicio] = useState(hojeLocal);
  const [motivo, setMotivo] = useState("");

  const [encerrando, setEncerrando] = useState(false);
  const [vigencia, setVigencia] = useState(hojeLocal);

  /** Versão de recarga: incrementar descarta a leitura anterior (sem cache). */
  const [versao, setVersao] = useState(0);
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

  const estado: EstadoEstrutura =
    !organizacaoAtivaId && !estadoInicial
      ? { fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ORGANIZACAO_ATIVA }
      : (estadoInicial ??
        (carregamento?.chave === chaveCarregamento
          ? carregamento.estado
          : { fase: "carregando" }));

  async function executar(
    operacao: () => Promise<ResultadoColaboradores<unknown>>,
    motivoInformado: string,
    aoConcluir?: () => void
  ) {
    if (processando) return;
    setErro(null);
    setSucesso("");

    if (!motivoInformado.trim()) {
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

    setSucesso("Configuração de colegiado registrada.");
    aoConcluir?.();
    setVersao((atual) => atual + 1);
  }

  const cabecalho = (
    <section className="virtus-page-header">
      <div className="virtus-page-header__copy">
        <h1>Colegiado</h1>
        <p>
          O colegiado é a configuração de avaliadores por COLABORADOR AVALIADO,
          versionada no tempo. Lista vazia é “sem colegiado” explícito; encerrar a
          versão vigente interrompe a configuração preservando o histórico.
        </p>
      </div>
    </section>
  );

  if (estado.fase === "carregando") {
    return (
      <main className="virtus-page estrutura-page">
        {cabecalho}
        <p className="estrutura-estado" role="status">
          Carregando colegiados…
        </p>
      </main>
    );
  }

  if (estado.fase === "erro") {
    return (
      <main className="virtus-page estrutura-page">
        {cabecalho}
        <p className="estrutura-estado estrutura-estado--erro" role="alert">
          {estado.mensagem} ({estado.codigo})
        </p>
      </main>
    );
  }

  const { colaboradores } = estado.estrutura;
  const vigente = avaliadoId ? colegiadoVigente(estado.estrutura, avaliadoId) : null;
  const historico = avaliadoId ? historicoColegiado(estado.estrutura, avaliadoId) : [];
  const candidatos = colaboradores.filter(
    (colaborador) => colaborador.collaboratorId !== avaliadoId
  );

  return (
    <main className="virtus-page estrutura-page">
      {cabecalho}

      {erro && (
        <p
          className="estrutura-estado estrutura-estado--erro"
          role="alert"
          data-testid="colegiado-erro"
        >
          {erro.mensagem} ({erro.codigo})
        </p>
      )}

      {sucesso && (
        <p className="estrutura-estado estrutura-estado--ok" role="status">
          {sucesso}
        </p>
      )}

      <section className="estrutura-card" data-testid="colegiado-avaliado">
        <header className="estrutura-card__header">
          <h2>Avaliado</h2>
          <span>{colaboradores.length} colaborador(es) na leitura</span>
        </header>

        <label className="virtus-field">
          <span>Colaborador avaliado *</span>
          <select
            value={avaliadoId}
            onChange={(evento) => {
              setAvaliadoId(evento.target.value);
              setMembros([]);
              setEncerrando(false);
            }}
          >
            <option value="">Selecione…</option>
            {colaboradores.map((colaborador) => (
              <option key={colaborador.collaboratorId} value={colaborador.collaboratorId}>
                {colaborador.nome || colaborador.collaboratorId}
              </option>
            ))}
          </select>
        </label>

        {avaliadoId && (
          <div data-testid="colegiado-vigente">
            {vigente ? (
              vigente.membroIds.length > 0 ? (
                <p className="estrutura-estado" role="status">
                  Versão vigente com {vigente.membroIds.length} membro(s):{" "}
                  {vigente.membroIds
                    .map((membroId) => nomeDoColaborador(estado.estrutura, membroId))
                    .join(", ")}
                </p>
              ) : (
                <p className="estrutura-estado" role="status">
                  Sem colegiado: a versão vigente foi definida com ZERO membros
                  (explícito).
                </p>
              )
            ) : (
              <p className="estrutura-estado" role="status">
                Nenhuma versão vigente: o colegiado não está configurado para este
                avaliado (ou foi encerrado).
              </p>
            )}
          </div>
        )}
      </section>

      {avaliadoId && (
        <section className="estrutura-card" data-testid="colegiado-definir">
          <header className="estrutura-card__header">
            <h2>Definir versão do colegiado</h2>
            <span>identidade do avaliado {avaliadoId}</span>
          </header>

          <form
            className="estrutura-form"
            onSubmit={(evento) => {
              evento.preventDefault();
              void executar(
                () =>
                  definirColegiado(
                    {
                      operationId: novoOperationId(),
                      collaboratorId: avaliadoId,
                      memberCollaboratorIds: [...membros],
                      validFrom: inicio,
                      motivo: motivo.trim(),
                      ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                    },
                    depsInjetadas
                  ),
                motivo,
                () => {
                  setMembros([]);
                  setMotivo("");
                }
              );
            }}
          >
            <fieldset className="estrutura-membros">
              <legend>
                Membros (0..N — nenhum membro é “sem colegiado” explícito)
              </legend>
              {candidatos.length === 0 && (
                <p className="estrutura-item--vazio">
                  Nenhum outro colaborador disponível nesta leitura.
                </p>
              )}
              {candidatos.map((colaborador) => {
                const marcado = membros.includes(colaborador.collaboratorId);
                return (
                  <label key={colaborador.collaboratorId} className="estrutura-membro">
                    <input
                      type="checkbox"
                      checked={marcado}
                      value={colaborador.collaboratorId}
                      onChange={(evento) => {
                        setMembros((atuais) =>
                          evento.target.checked
                            ? [...atuais, colaborador.collaboratorId]
                            : atuais.filter((id) => id !== colaborador.collaboratorId)
                        );
                      }}
                    />
                    <span>
                      {colaborador.nome || colaborador.collaboratorId} —{" "}
                      {colaborador.collaboratorId}
                    </span>
                  </label>
                );
              })}
            </fieldset>

            <label className="virtus-field">
              <span>Início da vigência *</span>
              <input
                type="date"
                value={inicio}
                onChange={(evento) => setInicio(evento.target.value)}
                required
              />
            </label>
            <label className="virtus-field">
              <span>Motivo *</span>
              <input
                value={motivo}
                onChange={(evento) => setMotivo(evento.target.value)}
                required
              />
            </label>
            <button
              type="submit"
              className="virtus-btn virtus-btn--primary"
              disabled={processando}
              data-testid="colegiado-definir-confirmar"
            >
              Definir colegiado
            </button>
            {vigente && (
              <button
                type="button"
                className="virtus-btn virtus-btn--outline"
                onClick={() => {
                  setEncerrando(true);
                  setVigencia(hojeLocal());
                  setMotivo("");
                }}
              >
                Encerrar colegiado
              </button>
            )}
          </form>

          {encerrando && (
            <form
              className="estrutura-form"
              data-testid="colegiado-encerrar"
              onSubmit={(evento) => {
                evento.preventDefault();
                void executar(
                  () =>
                    encerrarColegiado(
                      {
                        operationId: novoOperationId(),
                        collaboratorId: avaliadoId,
                        validTo: vigencia,
                        motivo: motivo.trim(),
                        ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                      },
                      depsInjetadas
                    ),
                  motivo,
                  () => setEncerrando(false)
                );
              }}
            >
              <label className="virtus-field">
                <span>Encerramento da vigência *</span>
                <input
                  type="date"
                  value={vigencia}
                  onChange={(evento) => setVigencia(evento.target.value)}
                  required
                />
              </label>
              <label className="virtus-field">
                <span>Motivo do encerramento *</span>
                <input
                  value={motivo}
                  onChange={(evento) => setMotivo(evento.target.value)}
                  required
                />
              </label>
              <button
                type="submit"
                className="virtus-btn virtus-btn--primary"
                disabled={processando}
                data-testid="colegiado-encerrar-confirmar"
              >
                Confirmar encerramento
              </button>
              <button
                type="button"
                className="virtus-btn virtus-btn--outline"
                onClick={() => setEncerrando(false)}
              >
                Cancelar
              </button>
            </form>
          )}
        </section>
      )}

      {avaliadoId && (
        <section className="estrutura-card" data-testid="colegiado-historico">
          <header className="estrutura-card__header">
            <h2>Histórico de versões</h2>
            <span>{historico.length} versão(ões)</span>
          </header>

          <ul className="estrutura-lista">
            {historico.map((versao) => (
              <li key={versao.colegiadoId} className="estrutura-item" data-id={versao.colegiadoId}>
                <div className="estrutura-item__copy">
                  <strong>{rotuloVigencia(versao.validFrom, versao.validTo)}</strong>
                  <span>
                    {versao.membroIds.length === 0
                      ? "sem colegiado (zero membros)"
                      : versao.membroIds
                          .map((membroId) => nomeDoColaborador(estado.estrutura, membroId))
                          .join(", ")}{" "}
                    • identidade {versao.colegiadoId}
                  </span>
                </div>
              </li>
            ))}
            {historico.length === 0 && (
              <li className="estrutura-item estrutura-item--vazio">
                Nenhuma versão registrada para este avaliado.
              </li>
            )}
          </ul>

          <p className="estrutura-nota">
            Alterar o colegiado fecha a versão vigente e cria outra: snapshots de
            ciclos passados não são recalculados (F3-08).
          </p>
        </section>
      )}

      {!avaliadoId && (
        <p className="estrutura-estado" role="status">
          Selecione um colaborador avaliado para ver e administrar o colegiado.
        </p>
      )}
    </main>
  );
}

export default ColegiadoPage;
