/**
 * F5-08 P4 — Posições: lista por unidade + criar + encerrar, com unidade,
 * cargo, senioridade, ocupante e reporting line exibidos.
 *
 * - LEITURA: soberana own-tenant pela via RLS (D16) — posições, ocupações e
 *   reporting lines vêm da mesma fotografia; o ocupante/superior é DERIVADO das
 *   relações vigentes, nunca de texto de cargo (I4).
 * - ESCRITA: `estrutura.posicao.criar|encerrar` (plano administrativo D19).
 *   A ALOCAÇÃO do colaborador (ocupação) e a reporting line são da F5/P5 —
 *   esta tela não as altera.
 * - Seleções usam UUID; filtro por unidade é apenas recorte de exibição local.
 */

import { useEffect, useState } from "react";
import { useAuth } from "../auth/AuthContext";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import {
  criarPosicao,
  encerrarPosicao,
  lerEstrutura,
  type DependenciasAcessoColaboradores,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import {
  SEM_ORGANIZACAO_ATIVA,
  TEXTO_ERRO_ESTRUTURA,
  decidirVersaoOtimista,
  estaVigente,
  hojeLocal,
  nomeDaUnidade,
  nomeDoColaborador,
  novoOperationId,
  ocupanteDaPosicao,
  rotuloDaPosicao,
  rotuloDaSenioridade,
  rotuloDoCargo,
  rotuloVigencia,
  superiorDaPosicao,
  type DecisaoVersaoOtimista,
  type ErroOperacao,
  type EstadoEstrutura,
} from "./apoioEstrutura";
import "../styles/estrutura.css";

type PosicoesPageProps = {
  readonly deps?: DependenciasAcessoColaboradores;
  readonly estadoInicial?: EstadoEstrutura;
};

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

function PosicoesPage({ deps, estadoInicial }: PosicoesPageProps = {}) {
  const { organizacaoAtivaId } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [erro, setErro] = useState<ErroOperacao | null>(null);
  const [sucesso, setSucesso] = useState("");
  const [processando, setProcessando] = useState(false);

  const [filtroUnidade, setFiltroUnidade] = useState("");
  const [novaUnidade, setNovaUnidade] = useState("");
  const [novoCargo, setNovoCargo] = useState("");
  const [novaSenioridade, setNovaSenioridade] = useState("");
  const [novoInicio, setNovoInicio] = useState(hojeLocal);
  const [novoMotivo, setNovoMotivo] = useState("");

  const [encerrando, setEncerrando] = useState<{
    readonly posicaoId: string;
    readonly rotulo: string;
  } | null>(null);
  const [vigencia, setVigencia] = useState(hojeLocal);
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
   * Versão otimista da posição na fotografia CORRENTE. Nunca fabrica versão: se
   * a posição não está mais na leitura, devolve `fotografia-desatualizada`.
   */
  function versaoDaFotografia(posicaoId: string): DecisaoVersaoOtimista {
    return decidirVersaoOtimista(
      estado.fase === "pronto"
        ? estado.estrutura.posicoes.map((posicao) => ({
            id: posicao.posicaoId,
            version: posicao.version,
          }))
        : [],
      posicaoId
    );
  }

  /** Fecha o encerramento por leitura desatualizada: sem envio, com recarga. */
  function invalidarPorFotografia(mensagem: string, codigo: CodigoPublico) {
    setErro({ codigo, mensagem });
    setEncerrando(null);
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

    setSucesso("Alteração registrada nas posições.");
    aoConcluir?.();
    setVersao((atual) => atual + 1);
  }

  const cabecalho = (
    <section className="virtus-page-header">
      <div className="virtus-page-header__copy">
        <h1>Posições</h1>
        <p>
          Posição formal = unidade + cargo (+ senioridade). Cargo, unidade e
          senioridade são IMUTÁVEIS na posição (D5): mover significa encerrar a
          posição antiga e criar uma nova, realocando as relações vigentes.
        </p>
      </div>
    </section>
  );

  if (estado.fase === "carregando") {
    return (
      <main className="virtus-page estrutura-page">
        {cabecalho}
        <p className="estrutura-estado" role="status">
          Carregando posições…
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

  const { posicoes, cargos, senioridades, unidades } = estado.estrutura;
  // "Vigente" = janela meio-aberta `[valid_from, valid_to)` na data de hoje.
  const unidadesVigentes = unidades.filter((unidade) =>
    estaVigente(unidade.validFrom, unidade.validTo)
  );
  const cargosAtivos = cargos.filter((cargo) => cargo.status === "active");
  const senioridadesAtivas = senioridades.filter(
    (senioridade) => senioridade.status === "active"
  );
  const posicoesExibidas = filtroUnidade
    ? posicoes.filter((posicao) => posicao.unitId === filtroUnidade)
    : posicoes;

  return (
    <main className="virtus-page estrutura-page">
      {cabecalho}

      {erro && (
        <p
          className="estrutura-estado estrutura-estado--erro"
          role="alert"
          data-testid="posicoes-erro"
        >
          {erro.mensagem} ({erro.codigo})
        </p>
      )}

      {sucesso && (
        <p className="estrutura-estado estrutura-estado--ok" role="status">
          {sucesso}
        </p>
      )}

      {posicoes.length === 0 && (
        <p className="estrutura-estado" role="status">
          {TEXTO_ERRO_ESTRUTURA}
        </p>
      )}

      <section className="estrutura-card" data-testid="posicao-criar-card">
        <header className="estrutura-card__header">
          <h2>Nova posição</h2>
          <span>{posicoes.length} posição(ões) registrada(s)</span>
        </header>

        <form
          className="estrutura-form"
          onSubmit={(evento) => {
            evento.preventDefault();
            void executar(
              () =>
                criarPosicao(
                  {
                    operationId: novoOperationId(),
                    unidadeId: novaUnidade,
                    jobRoleId: novoCargo,
                    seniorityLevelId: novaSenioridade ? novaSenioridade : null,
                    validFrom: novoInicio,
                    motivo: novoMotivo.trim(),
                    ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                  },
                  depsInjetadas
                ),
              novoMotivo,
              () => setNovoMotivo("")
            );
          }}
        >
          <label className="virtus-field">
            <span>Unidade *</span>
            <select
              value={novaUnidade}
              onChange={(evento) => setNovaUnidade(evento.target.value)}
              required
            >
              <option value="">Selecione…</option>
              {unidadesVigentes.map((unidade) => (
                <option key={unidade.unitId} value={unidade.unitId}>
                  {unidade.nome}
                </option>
              ))}
            </select>
          </label>
          <label className="virtus-field">
            <span>Cargo *</span>
            <select
              value={novoCargo}
              onChange={(evento) => setNovoCargo(evento.target.value)}
              required
            >
              <option value="">Selecione…</option>
              {cargosAtivos.map((cargo) => (
                <option key={cargo.jobRoleId} value={cargo.jobRoleId}>
                  {cargo.code ? `${cargo.code} — ${cargo.nome}` : cargo.nome}
                </option>
              ))}
            </select>
          </label>
          <label className="virtus-field">
            <span>Senioridade (opcional)</span>
            <select
              value={novaSenioridade}
              onChange={(evento) => setNovaSenioridade(evento.target.value)}
            >
              <option value="">Sem senioridade</option>
              {senioridadesAtivas.map((senioridade) => (
                <option key={senioridade.seniorityLevelId} value={senioridade.seniorityLevelId}>
                  {senioridade.nome}
                </option>
              ))}
            </select>
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
            data-testid="posicao-criar"
          >
            Criar posição
          </button>
        </form>

        <p className="estrutura-nota">
          Somente cargos e senioridades ATIVOS podem ser referenciados em posição
          NOVA (I4); itens inativos continuam válidos para o histórico.
        </p>
      </section>

      <section className="estrutura-card" data-testid="posicoes-lista">
        <header className="estrutura-card__header">
          <h2>Posições</h2>
          <span>{posicoesExibidas.length} exibida(s)</span>
        </header>

        <label className="virtus-field">
          <span>Filtrar por unidade</span>
          <select
            value={filtroUnidade}
            onChange={(evento) => setFiltroUnidade(evento.target.value)}
          >
            <option value="">Todas as unidades</option>
            {unidades.map((unidade) => (
              <option key={unidade.unitId} value={unidade.unitId}>
                {unidade.nome}
              </option>
            ))}
          </select>
        </label>

        <ul className="estrutura-lista">
          {posicoesExibidas.map((posicao) => {
            const vigente = estaVigente(posicao.validFrom, posicao.validTo);
            const ocupanteId = ocupanteDaPosicao(estado.estrutura, posicao.posicaoId);
            const superiorId = superiorDaPosicao(estado.estrutura, posicao.posicaoId);
            const linha = estado.estrutura.reportingLines.some(
              (item) =>
                item.subordinatePositionId === posicao.posicaoId &&
                estaVigente(item.validFrom, item.validTo)
            );

            return (
              <li
                key={posicao.posicaoId}
                className="estrutura-item estrutura-item--bloco"
                data-id={posicao.posicaoId}
              >
                <div className="estrutura-item__copy">
                  <strong>{rotuloDaPosicao(estado.estrutura, posicao.posicaoId)}</strong>
                  <span>
                    Unidade: {nomeDaUnidade(estado.estrutura, posicao.unitId)} • Cargo:{" "}
                    {rotuloDoCargo(estado.estrutura, posicao.jobRoleId)} • Senioridade:{" "}
                    {rotuloDaSenioridade(estado.estrutura, posicao.seniorityLevelId)}
                  </span>
                  <span>
                    Ocupante:{" "}
                    {ocupanteId
                      ? nomeDoColaborador(estado.estrutura, ocupanteId)
                      : "sem ocupante"}{" "}
                    • Reporting line:{" "}
                    {linha
                      ? superiorId
                        ? `superior ${rotuloDaPosicao(estado.estrutura, superiorId)}`
                        : "raiz (sem superior)"
                      : "sem linha de reporting registrada"}
                  </span>
                  <span>
                    {rotuloVigencia(posicao.validFrom, posicao.validTo)} • versão{" "}
                    {posicao.version} • identidade {posicao.posicaoId}
                  </span>
                </div>
                <div className="estrutura-item__actions">
                  {vigente && (
                    <button
                      type="button"
                      className="virtus-btn virtus-btn--outline"
                      onClick={() => {
                        setEncerrando({
                          posicaoId: posicao.posicaoId,
                          rotulo: rotuloDaPosicao(estado.estrutura, posicao.posicaoId),
                        });
                        setVigencia(hojeLocal());
                        setMotivo("");
                      }}
                    >
                      Encerrar posição
                    </button>
                  )}
                </div>
              </li>
            );
          })}
          {posicoesExibidas.length === 0 && (
            <li className="estrutura-item estrutura-item--vazio">
              Nenhuma posição nesta unidade.
            </li>
          )}
        </ul>

        <p className="estrutura-nota">
          A alocação do colaborador (ocupação) e a reporting line são mantidas no
          fluxo próprio de alocação; encerrar posição com ocupação ou reporting
          vigente é recusado pelo servidor.
        </p>
      </section>

      {encerrando && (
        <section className="estrutura-card" data-testid="posicao-encerrar">
          <header className="estrutura-card__header">
            <h2>Encerrar posição: {encerrando.rotulo}</h2>
            <span>identidade {encerrando.posicaoId}</span>
          </header>

          <form
            className="estrutura-form"
            onSubmit={(evento) => {
              evento.preventDefault();
              // `expectedVersion` vem da fotografia CORRENTE (nunca de default
              // sintético): se a posição sumiu da leitura, nada é enviado.
              const decisao = versaoDaFotografia(encerrando.posicaoId);
              if (decisao.tipo === "fotografia-desatualizada") {
                invalidarPorFotografia(decisao.mensagem, decisao.codigo);
                return;
              }
              void executar(
                () =>
                  encerrarPosicao(
                    {
                      operationId: novoOperationId(),
                      posicaoId: encerrando.posicaoId,
                      validTo: vigencia,
                      expectedVersion: decisao.expectedVersion,
                      motivo: motivo.trim(),
                      ...(organizacaoAtivaId ? { organizationId: organizacaoAtivaId } : {}),
                    },
                    depsInjetadas
                  ),
                motivo,
                () => setEncerrando(null)
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
              data-testid="posicao-encerrar-confirmar"
            >
              Confirmar
            </button>
            <button
              type="button"
              className="virtus-btn virtus-btn--outline"
              onClick={() => setEncerrando(null)}
            >
              Cancelar
            </button>
          </form>
        </section>
      )}
    </main>
  );
}

export default PosicoesPage;
