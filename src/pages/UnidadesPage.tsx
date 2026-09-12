/**
 * F5-08 P4 — Unidades: lista + hierarquia (parent) + criar/renomear/encerrar.
 *
 * - LEITURA: soberana own-tenant pela via RLS (D16) — sem capability.
 * - ESCRITA: `estrutura.unidade.criar|renomear|encerrar` e
 *   `estrutura.unidade.parent.definir|encerrar` (plano administrativo D19:
 *   `org.structure.manage` revalidada na Edge e no banco).
 * - A árvore exibida é APRESENTAÇÃO: ausência de ciclo é garantia do banco
 *   (I1 + trigger anti-ciclo); nenhuma regra de hierarquia é decidida aqui.
 * - Encerrado NÃO é reaberto (D21): a tela informa e a criação de nova unidade é
 *   o caminho. Nenhuma escrita local.
 */

import { useEffect, useState } from "react";
import { useAuth } from "../auth/AuthContext";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import {
  criarUnidade,
  definirParentUnidade,
  encerrarParentUnidade,
  encerrarUnidade,
  lerEstrutura,
  renomearUnidade,
  type DependenciasAcessoColaboradores,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import {
  SEM_ORGANIZACAO_ATIVA,
  TEXTO_ERRO_ESTRUTURA,
  decidirVersaoOtimista,
  estaVigente,
  hojeLocal,
  novoOperationId,
  profundidadeDaUnidade,
  rotuloVigencia,
  type DecisaoVersaoOtimista,
  type ErroOperacao,
  type EstadoEstrutura,
} from "./apoioEstrutura";
import "../styles/estrutura.css";

type UnidadesPageProps = {
  readonly deps?: DependenciasAcessoColaboradores;
  readonly estadoInicial?: EstadoEstrutura;
};

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

type AcaoUnidade = "renomear" | "encerrar" | "parent" | "encerrarParent";

function UnidadesPage({ deps, estadoInicial }: UnidadesPageProps = {}) {
  const { organizacaoAtivaId } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [erro, setErro] = useState<ErroOperacao | null>(null);
  const [sucesso, setSucesso] = useState("");
  const [processando, setProcessando] = useState(false);

  const [novaUnidade, setNovaUnidade] = useState("");
  const [novoInicio, setNovoInicio] = useState(hojeLocal);
  const [novoMotivo, setNovoMotivo] = useState("");

  const [selecionada, setSelecionada] = useState<{
    readonly unitId: string;
    readonly nome: string;
    readonly version: number;
    readonly acao: AcaoUnidade;
  } | null>(null);
  const [nome, setNome] = useState("");
  const [vigencia, setVigencia] = useState(hojeLocal);
  const [parentId, setParentId] = useState<string>("");
  const [motivo, setMotivo] = useState("");

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

  /**
   * Versão otimista da unidade na fotografia CORRENTE. Nunca fabrica versão: se
   * a unidade não está mais na leitura, devolve `fotografia-desatualizada`.
   */
  function versaoDaFotografia(unitId: string): DecisaoVersaoOtimista {
    return decidirVersaoOtimista(
      estado.fase === "pronto"
        ? estado.estrutura.unidades.map((unidade) => ({
            id: unidade.unitId,
            version: unidade.version,
          }))
        : [],
      unitId
    );
  }

  /** Fecha a edição por leitura desatualizada: sem envio, com recarga. */
  function invalidarPorFotografia(mensagem: string, codigo: CodigoPublico) {
    setErro({ codigo, mensagem });
    setSelecionada(null);
    setVersao((atual) => atual + 1);
  }

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

    setSucesso("Alteração registrada na estrutura de unidades.");
    aoConcluir?.();
    setVersao((atual) => atual + 1);
  }

  const cabecalho = (
    <section className="virtus-page-header">
      <div className="virtus-page-header__copy">
        <h1>Unidades</h1>
        <p>
          Unidade é entidade formal com vigência própria. A relação pai/filho é
          temporal e não admite ciclo; encerrar uma unidade exige que não exista
          posição nem relação de parent vigente.
        </p>
      </div>
    </section>
  );

  if (estado.fase === "carregando") {
    return (
      <main className="virtus-page estrutura-page">
        {cabecalho}
        <p className="estrutura-estado" role="status">
          Carregando unidades…
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

  const { unidades } = estado.estrutura;
  // "Vigente" = janela meio-aberta `[valid_from, valid_to)` na data de hoje —
  // uma unidade com `valid_to` FUTURO continua vigente; uma com `valid_from`
  // futuro ainda NÃO está vigente.
  const unidadesVigentes = unidades.filter((unidade) =>
    estaVigente(unidade.validFrom, unidade.validTo)
  );

  return (
    <main className="virtus-page estrutura-page">
      {cabecalho}

      {erro && (
        <p
          className="estrutura-estado estrutura-estado--erro"
          role="alert"
          data-testid="unidades-erro"
        >
          {erro.mensagem} ({erro.codigo})
        </p>
      )}

      {sucesso && (
        <p className="estrutura-estado estrutura-estado--ok" role="status">
          {sucesso}
        </p>
      )}

      {unidades.length === 0 && (
        <p className="estrutura-estado" role="status">
          {TEXTO_ERRO_ESTRUTURA}
        </p>
      )}

      <section className="estrutura-card" data-testid="unidade-criar-card">
        <header className="estrutura-card__header">
          <h2>Nova unidade</h2>
          <span>{unidadesVigentes.length} unidade(s) vigente(s)</span>
        </header>

        <form
          className="estrutura-form"
          onSubmit={(evento) => {
            evento.preventDefault();
            void executar(
              () =>
                criarUnidade(
                  {
                    operationId: novoOperationId(),
                    nome: novaUnidade.trim(),
                    validFrom: novoInicio,
                    motivo: novoMotivo.trim(),
                    ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                  },
                  depsInjetadas
                ),
              novoMotivo,
              () => {
                setNovaUnidade("");
                setNovoMotivo("");
              }
            );
          }}
        >
          <label className="virtus-field">
            <span>Nome da unidade *</span>
            <input
              value={novaUnidade}
              onChange={(evento) => setNovaUnidade(evento.target.value)}
              required
            />
          </label>
          <label className="virtus-field">
            <span>Início da vigência *</span>
            <input
              type="date"
              value={novoInicio}
              onChange={(evento) => setNovoInicio(evento.target.value)}
              required
            />
          </label>
          <label className="virtus-field">
            <span>Motivo *</span>
            <input
              value={novoMotivo}
              onChange={(evento) => setNovoMotivo(evento.target.value)}
              required
            />
          </label>
          <button
            type="submit"
            className="virtus-btn virtus-btn--primary"
            disabled={processando}
            data-testid="unidade-criar"
          >
            Criar unidade
          </button>
        </form>
      </section>

      <section className="estrutura-card" data-testid="unidades-lista">
        <header className="estrutura-card__header">
          <h2>Unidades da organização</h2>
          <span>{unidades.length} registro(s)</span>
        </header>

        <ul className="estrutura-lista estrutura-arvore">
          {unidades.map((unidade) => {
            const profundidade = profundidadeDaUnidade(estado.estrutura, unidade.unitId);
            const relacao = estado.estrutura.periodosParent.find(
              (periodo) =>
                periodo.unitId === unidade.unitId &&
                estaVigente(periodo.validFrom, periodo.validTo)
            );
            const pai = relacao
              ? relacao.parentUnitId
                ? unidades.find((item) => item.unitId === relacao.parentUnitId)?.nome ?? "—"
                : "Raiz (sem unidade pai)"
              : "Sem relação pai registrada";
            const vigente = estaVigente(unidade.validFrom, unidade.validTo);

            return (
              <li
                key={unidade.unitId}
                className="estrutura-item estrutura-item--bloco"
                data-id={unidade.unitId}
                style={{ marginLeft: `${profundidade * 18}px` }}
              >
                <div className="estrutura-item__copy">
                  <strong>{unidade.nome}</strong>
                  <span>
                    {rotuloVigencia(unidade.validFrom, unidade.validTo)} • versão{" "}
                    {unidade.version} • Pai: {pai}
                  </span>
                </div>
                <div className="estrutura-item__actions">
                  <button
                    type="button"
                    className="virtus-btn virtus-btn--outline"
                    onClick={() => {
                      setSelecionada({
                        unitId: unidade.unitId,
                        nome: unidade.nome,
                        version: unidade.version,
                        acao: "renomear",
                      });
                      setNome(unidade.nome);
                      setMotivo("");
                    }}
                  >
                    Renomear
                  </button>
                  <button
                    type="button"
                    className="virtus-btn virtus-btn--outline"
                    onClick={() => {
                      setSelecionada({
                        unitId: unidade.unitId,
                        nome: unidade.nome,
                        version: unidade.version,
                        acao: "parent",
                      });
                      setParentId(relacao?.parentUnitId ?? "");
                      setVigencia(hojeLocal());
                      setMotivo("");
                    }}
                  >
                    {relacao ? "Alterar pai" : "Definir pai"}
                  </button>
                  {vigente && relacao && (
                    <button
                      type="button"
                      className="virtus-btn virtus-btn--outline"
                      onClick={() => {
                        setSelecionada({
                          unitId: unidade.unitId,
                          nome: unidade.nome,
                          version: unidade.version,
                          acao: "encerrarParent",
                        });
                        setVigencia(hojeLocal());
                        setMotivo("");
                      }}
                    >
                      Encerrar relação
                    </button>
                  )}
                  {vigente && (
                    <button
                      type="button"
                      className="virtus-btn virtus-btn--outline"
                      onClick={() => {
                        setSelecionada({
                          unitId: unidade.unitId,
                          nome: unidade.nome,
                          version: unidade.version,
                          acao: "encerrar",
                        });
                        setVigencia(hojeLocal());
                        setMotivo("");
                      }}
                    >
                      Encerrar unidade
                    </button>
                  )}
                </div>
              </li>
            );
          })}
        </ul>

        <p className="estrutura-nota">
          Unidade encerrada não é reaberta (decisão D21): uma nova vigência exige
          uma NOVA unidade. “Mover” uma unidade existente preserva o histórico no
          período anterior.
        </p>
      </section>

      {selecionada && (
        <section className="estrutura-card" data-testid="unidade-acao">
          <header className="estrutura-card__header">
            <h2>
              {selecionada.acao === "renomear"
                ? "Renomear unidade"
                : selecionada.acao === "encerrar"
                  ? "Encerrar unidade"
                  : selecionada.acao === "parent"
                    ? "Definir/Alterar unidade pai"
                    : "Encerrar relação pai/filho"}
              : {selecionada.nome}
            </h2>
            <span>identidade {selecionada.unitId}</span>
          </header>

          <form
            className="estrutura-form"
            onSubmit={(evento) => {
              evento.preventDefault();
              const base = {
                operationId: novoOperationId(),
                unidadeId: selecionada.unitId,
                ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
              };

              if (selecionada.acao === "renomear") {
                // `expectedVersion` vem da fotografia CORRENTE (nunca de default
                // sintético): se a unidade sumiu da leitura, nada é enviado.
                const decisao = versaoDaFotografia(selecionada.unitId);
                if (decisao.tipo === "fotografia-desatualizada") {
                  invalidarPorFotografia(decisao.mensagem, decisao.codigo);
                  return;
                }
                void executar(
                  () =>
                    renomearUnidade(
                      {
                        ...base,
                        nome: nome.trim(),
                        expectedVersion: decisao.expectedVersion,
                        motivo: motivo.trim(),
                      },
                      depsInjetadas
                    ),
                  motivo,
                  () => setSelecionada(null)
                );
                return;
              }

              if (selecionada.acao === "encerrar") {
                const decisao = versaoDaFotografia(selecionada.unitId);
                if (decisao.tipo === "fotografia-desatualizada") {
                  invalidarPorFotografia(decisao.mensagem, decisao.codigo);
                  return;
                }
                void executar(
                  () =>
                    encerrarUnidade(
                      {
                        ...base,
                        validTo: vigencia,
                        expectedVersion: decisao.expectedVersion,
                        motivo: motivo.trim(),
                      },
                      depsInjetadas
                    ),
                  motivo,
                  () => setSelecionada(null)
                );
                return;
              }

              if (selecionada.acao === "parent") {
                void executar(
                  () =>
                    definirParentUnidade(
                      {
                        ...base,
                        parentUnitId: parentId ? parentId : null,
                        validFrom: vigencia,
                        motivo: motivo.trim(),
                      },
                      depsInjetadas
                    ),
                  motivo,
                  () => setSelecionada(null)
                );
                return;
              }

              void executar(
                () =>
                  encerrarParentUnidade(
                    {
                      ...base,
                      validTo: vigencia,
                      motivo: motivo.trim(),
                    },
                    depsInjetadas
                  ),
                motivo,
                () => setSelecionada(null)
              );
            }}
          >
            {selecionada.acao === "renomear" && (
              <label className="virtus-field">
                <span>Novo nome *</span>
                <input
                  value={nome}
                  onChange={(evento) => setNome(evento.target.value)}
                  required
                />
              </label>
            )}

            {selecionada.acao === "parent" && (
              <label className="virtus-field">
                <span>Unidade pai *</span>
                <select
                  value={parentId}
                  onChange={(evento) => setParentId(evento.target.value)}
                >
                  <option value="">Raiz (sem unidade pai)</option>
                  {unidadesVigentes
                    .filter((unidade) => unidade.unitId !== selecionada.unitId)
                    .map((unidade) => (
                      <option key={unidade.unitId} value={unidade.unitId}>
                        {unidade.nome}
                      </option>
                    ))}
                </select>
              </label>
            )}

            {(selecionada.acao === "encerrar" ||
              selecionada.acao === "encerrarParent") && (
              <label className="virtus-field">
                <span>Encerramento da vigência *</span>
                <input
                  type="date"
                  value={vigencia}
                  onChange={(evento) => setVigencia(evento.target.value)}
                  required
                />
              </label>
            )}

            {selecionada.acao === "parent" && (
              <label className="virtus-field">
                <span>Início da vigência *</span>
                <input
                  type="date"
                  value={vigencia}
                  onChange={(evento) => setVigencia(evento.target.value)}
                  required
                />
              </label>
            )}

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
              data-testid="unidade-acao-confirmar"
            >
              Confirmar
            </button>
            <button
              type="button"
              className="virtus-btn virtus-btn--outline"
              onClick={() => setSelecionada(null)}
            >
              Cancelar
            </button>
          </form>
        </section>
      )}
    </main>
  );
}

export default UnidadesPage;
