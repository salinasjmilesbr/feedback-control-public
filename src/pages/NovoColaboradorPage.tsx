/**
 * F5-08 P5 — Novo colaborador: cadastro soberano + ALOCAÇÃO opcional.
 *
 * Escopo desta tela:
 * - criação da PESSOA (nome, e-mail, admissão), matrícula como INTENÇÃO e status
 *   inicial, pela porta única (Edge `colaboradores`);
 * - ALOCAÇÃO opcional logo após o cadastro, com as operações JÁ EXISTENTES da
 *   F5-07: `definirOcupacao` (posição escolhida por UUID) e, se o usuário quiser,
 *   `definirReportingLine` (posição gerente escolhida por UUID);
 * - criação do colaborador e criação da ocupação são operações DISTINTAS: não há
 *   transação única no frontend. Se o colaborador for criado e a alocação falhar,
 *   o colaborador PERMANECE criado, nenhuma estrutura é fabricada e a tela diz
 *   explicitamente que ele ficou SEM ALOCAÇÃO, permitindo nova tentativa.
 *
 * Nada é gravado localmente: nenhuma chamada a `localStorage`, nenhum dual-write
 * e nenhum fallback. A autorização é do servidor (as mutações devolvem o código
 * público) e a leitura das posições é a fotografia soberana own-tenant (RLS).
 */

import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import SeletorPosicao from "../components/SeletorPosicao";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import {
  confirmarDefinicaoOcupacao,
  confirmarReportingLine,
} from "./alocacaoSoberana";
import {
  criarColaborador,
  type DependenciasAcessoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import { posicoesVigentes } from "./alocacaoSoberana";
import { hojeLocal, type EstadoEstrutura } from "./apoioEstrutura";
import { useEstruturaSoberana } from "./useEstruturaSoberana";
import "../styles/colaborador-form.css";

/** Estado explícito do fluxo de criação (nunca inferido de storage local). */
export type EstadoCriacaoColaborador =
  | { readonly fase: "inicial" }
  | { readonly fase: "processando" }
  | {
      readonly fase: "erro";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | { readonly fase: "sucesso"; readonly collaboratorId: string };

/**
 * Estado da ALOCAÇÃO pedida no mesmo fluxo. `parcial` descreve o que NÃO foi
 * aplicado, para a tela não fingir atomicidade: `sem-ocupacao` (colaborador
 * criado sem alocação) ou `sem-gestor` (ocupação gravada, gestor não).
 */
export type EstadoAlocacaoColaborador =
  | { readonly fase: "inativa" }
  | { readonly fase: "processando" }
  | {
      readonly fase: "erro";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
      readonly parcial: "sem-ocupacao" | "sem-gestor";
    }
  | { readonly fase: "concluida" };

type NovoColaboradorPageProps = {
  /** Operações da porta (injeção de teste); produção usa o caminho padrão. */
  readonly deps?: DependenciasAcessoColaboradores;
  /** Semente de estado (SSR/teste determinístico). */
  readonly estadoInicial?: EstadoCriacaoColaborador;
  /** Semente da fotografia soberana (SSR/teste determinístico). */
  readonly estruturaInicial?: EstadoEstrutura;
  /** Semente do formulário de alocação aberto (SSR/teste determinístico). */
  readonly alocacaoInicial?: boolean;
};

type StatusInicialSoberano = "active" | "leave";

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

const SEM_ORGANIZACAO_ATIVA =
  "Selecione uma organização ativa para cadastrar colaboradores.";

/**
 * `operation_id` (idempotência da mutação, §13.5) gerado pelo chamador. Não é
 * identidade nem autoridade: serve apenas para a fronteira não duplicar efeitos.
 * Cada operação distinta (cadastro, ocupação, reporting line) recebe o SEU id.
 */
function novoOperationId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (caractere) => {
    const aleatorio = Math.floor(Math.random() * 16);
    const valor = caractere === "x" ? aleatorio : (aleatorio & 0x3) | 0x8;
    return valor.toString(16);
  });
}

function NovoColaboradorPage({
  deps,
  estadoInicial,
  estruturaInicial,
  alocacaoInicial,
}: NovoColaboradorPageProps = {}) {
  const navigate = useNavigate();
  const { organizacaoAtivaId } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [estado, setEstado] = useState<EstadoCriacaoColaborador>(
    estadoInicial ?? { fase: "inicial" }
  );
  const [estadoAlocacao, setEstadoAlocacao] = useState<EstadoAlocacaoColaborador>({
    fase: "inativa",
  });

  const [matricula, setMatricula] = useState("");
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [dataAdmissao, setDataAdmissao] = useState(hojeLocal);
  const [statusInicial, setStatusInicial] =
    useState<StatusInicialSoberano>("active");
  const [erroLocal, setErroLocal] = useState("");

  // Alocação opcional (ocupação + gestor), decidida pelo usuário no formulário.
  const [alocar, setAlocar] = useState(alocacaoInicial ?? false);
  const [posicaoId, setPosicaoId] = useState("");
  const [vigenciaAlocacao, setVigenciaAlocacao] = useState(hojeLocal);
  const [motivoAlocacao, setMotivoAlocacao] = useState("");
  const [definirGestor, setDefinirGestor] = useState(false);
  const [gestorPosicaoId, setGestorPosicaoId] = useState("");

  const estrutura = useEstruturaSoberana({
    organizacaoAtivaId,
    deps: depsInjetadas,
    ...(estruturaInicial ? { estadoInicial: estruturaInicial } : {}),
  });

  const processando = estado.fase === "processando";
  const alocando = estadoAlocacao.fase === "processando";
  const ocupado = processando || alocando;
  const estruturaPronta = estrutura.estado.fase === "pronto";
  const posicoes = estruturaPronta ? posicoesVigentes(estrutura.estado.estrutura) : [];
  const alocacaoDisponivel = estruturaPronta && posicoes.length > 0;

  /** Executa a alocação pedida, com desfechos parciais EXPLÍCITOS. */
  async function alocarColaborador(collaboratorId: string) {
    if (!organizacaoAtivaId || !estruturaPronta) return;

    const fotografia = estrutura.estado.estrutura;
    const comum = {
      estrutura: fotografia,
      collaboratorId,
      vigencia: vigenciaAlocacao,
      motivo: motivoAlocacao.trim(),
      organizationId: organizacaoAtivaId,
    };

    setEstadoAlocacao({ fase: "processando" });

    const ocupacao = await confirmarDefinicaoOcupacao(
      { ...comum, posicaoId, operationId: novoOperationId() },
      depsInjetadas
    );

    if (ocupacao.tipo === "fotografia-desatualizada") {
      estrutura.recarregar();
      setEstadoAlocacao({
        fase: "erro",
        codigo: ocupacao.codigo,
        mensagem: ocupacao.mensagem,
        parcial: "sem-ocupacao",
      });
      return;
    }
    if (ocupacao.tipo !== "concluida") {
      setEstadoAlocacao({
        fase: "erro",
        codigo: "INVALID_INPUT",
        mensagem:
          ocupacao.tipo === "sem-vigencia"
            ? "Informe a vigência da alocação."
            : "Informe o motivo da alocação.",
        parcial: "sem-ocupacao",
      });
      return;
    }
    if (!ocupacao.resultado.ok) {
      if (
        ocupacao.resultado.codigo === "CONFLICT" ||
        ocupacao.resultado.codigo === "NOT_FOUND"
      ) {
        estrutura.recarregar();
      }
      setEstadoAlocacao({
        fase: "erro",
        codigo: ocupacao.resultado.codigo,
        mensagem: ocupacao.resultado.mensagem,
        parcial: "sem-ocupacao",
      });
      return;
    }

    if (definirGestor && gestorPosicaoId) {
      const linha = await confirmarReportingLine(
        {
          estrutura: fotografia,
          subordinatePositionId: posicaoId,
          managerPositionId: gestorPosicaoId,
          vigencia: vigenciaAlocacao,
          motivo: motivoAlocacao.trim(),
          operationId: novoOperationId(),
          organizationId: organizacaoAtivaId,
        },
        depsInjetadas
      );

      const falhaReporting =
        linha.tipo === "concluida"
          ? linha.resultado.ok
            ? null
            : linha.resultado
          : {
              codigo: linha.tipo === "fotografia-desatualizada" ? linha.codigo : "INVALID_INPUT",
              mensagem:
                linha.tipo === "fotografia-desatualizada"
                  ? linha.mensagem
                  : "Informe a vigência e o motivo para definir o gestor.",
            };

      if (falhaReporting) {
        if (falhaReporting.codigo === "CONFLICT" || falhaReporting.codigo === "NOT_FOUND") {
          estrutura.recarregar();
        }
        // A ocupação FOI gravada; o gestor não. Estado parcial explícito.
        setEstadoAlocacao({
          fase: "erro",
          codigo: falhaReporting.codigo,
          mensagem: falhaReporting.mensagem,
          parcial: "sem-gestor",
        });
        return;
      }
    }

    setEstadoAlocacao({ fase: "concluida" });
    navigate(`/colaborador/${collaboratorId}`);
  }

  async function handleSalvar() {
    if (ocupado) return;

    setErroLocal("");

    if (!matricula.trim() || !nome.trim() || !email.trim()) {
      setErroLocal("Preencha todos os campos obrigatórios.");
      return;
    }

    if (!/^\d+$/.test(matricula.trim()) || Number(matricula.trim()) <= 0) {
      setErroLocal("Informe uma matrícula válida (somente dígitos).");
      return;
    }

    if (alocar) {
      if (!posicaoId || !vigenciaAlocacao || !motivoAlocacao.trim()) {
        setErroLocal(
          "Para alocar, informe a posição vigente, a vigência e o motivo da alocação."
        );
        return;
      }
      if (definirGestor && !gestorPosicaoId) {
        setErroLocal("Selecione a posição do gestor ou desmarque a opção de gestor.");
        return;
      }
    }

    if (!organizacaoAtivaId) {
      setEstado({
        fase: "erro",
        codigo: "FORBIDDEN",
        mensagem: SEM_ORGANIZACAO_ATIVA,
      });
      return;
    }

    setEstado({ fase: "processando" });

    const resultado = await criarColaborador(
      {
        fullName: nome.trim(),
        email: email.trim(),
        matricula: matricula.trim(),
        ...(dataAdmissao ? { admissionDate: dataAdmissao } : {}),
        statusInicial,
        operationId: novoOperationId(),
        organizationId: organizacaoAtivaId,
      },
      depsInjetadas
    );

    if (!resultado.ok) {
      setEstado({
        fase: "erro",
        codigo: resultado.codigo,
        mensagem: resultado.mensagem,
      });
      return;
    }

    setEstado({ fase: "sucesso", collaboratorId: resultado.dados });

    if (!alocar) {
      navigate(`/colaborador/${resultado.dados}`);
      return;
    }

    await alocarColaborador(resultado.dados);
  }

  const colaboradorCriado =
    estado.fase === "sucesso" ? estado.collaboratorId : null;

  return (
    <main className="virtus-page collaborator-form-page">
      <section className="collaborator-form-header">
        <div>
          <button
            type="button"
            className="collaborator-form-back"
            onClick={() => navigate("/")}
          >
            ← Voltar aos colaboradores
          </button>
          <span className="collaborator-form-eyebrow">Cadastro</span>
          <h1>Novo colaborador</h1>
          <p>
            Cadastre os dados de pessoa, a matrícula e o status inicial. O
            cadastro é gravado no PostgreSQL pela porta soberana.
          </p>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">
            01
          </span>
          <div>
            <h2>Dados do colaborador</h2>
            <p>
              Informações de pessoa, matrícula vigente e situação inicial do
              vínculo.
            </p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Matrícula *</span>
            <input
              type="text"
              inputMode="numeric"
              value={matricula}
              onChange={(event) => setMatricula(event.target.value)}
              placeholder="Ex.: 123456"
            />
            <small>
              A matrícula é uma intenção: o servidor resolve o identificador.
            </small>
          </label>

          <label className="collaborator-field">
            <span>Data de admissão</span>
            <input
              type="date"
              value={dataAdmissao}
              onChange={(event) => setDataAdmissao(event.target.value)}
            />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>Nome *</span>
            <input
              type="text"
              value={nome}
              onChange={(event) => setNome(event.target.value)}
              placeholder="Nome completo"
            />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>E-mail *</span>
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="nome@empresa.com.br"
            />
          </label>

          <label className="collaborator-field">
            <span>Status inicial *</span>
            <select
              value={statusInicial}
              onChange={(event) =>
                setStatusInicial(event.target.value as StatusInicialSoberano)
              }
            >
              <option value="active">Ativo</option>
              <option value="leave">Em licença</option>
            </select>
          </label>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">
            02
          </span>
          <div>
            <h2>Alocação (opcional)</h2>
            <p>
              A ocupação e a reporting line são operações próprias, gravadas
              depois do cadastro. Sem alocação o colaborador permanece
              explicitamente “sem alocação”.
            </p>
          </div>
        </div>

        {estrutura.estado.fase === "carregando" && (
          <div className="collaborator-form-info" role="status">
            Carregando as posições soberanas…
          </div>
        )}

        {estrutura.estado.fase === "erro" && (
          <div className="collaborator-form-error" role="alert">
            <strong>Não foi possível carregar as posições</strong>
            <p>
              {estrutura.estado.mensagem} ({estrutura.estado.codigo})
            </p>
            <p>
              O cadastro do colaborador continua disponível; a alocação pode ser
              feita depois na ficha do colaborador.
            </p>
          </div>
        )}

        {estruturaPronta && (
          <>
            <label className="collaborator-field collaborator-field--inline">
              <input
                type="checkbox"
                checked={alocar}
                onChange={(evento) => setAlocar(evento.target.checked)}
                disabled={!alocacaoDisponivel || ocupado}
              />
              <span>Alocar este colaborador agora</span>
            </label>

            {!alocacaoDisponivel && (
              <div className="collaborator-form-empty">
                Nenhuma posição vigente disponível nesta organização: cadastre a
                posição em Estrutura → Posições. Nada é criado automaticamente.
              </div>
            )}

            {alocar && (
              <div className="collaborator-form-grid">
                <SeletorPosicao
                  id="novo-colaborador-posicao"
                  estrutura={estrutura.estado.estrutura}
                  valor={posicaoId}
                  aoMudar={setPosicaoId}
                  rotulo="Posição (unidade • cargo • senioridade) *"
                  desabilitado={ocupado}
                />

                <label className="collaborator-field">
                  <span>Vigência da ocupação *</span>
                  <input
                    type="date"
                    value={vigenciaAlocacao}
                    onChange={(evento) => setVigenciaAlocacao(evento.target.value)}
                    disabled={ocupado}
                  />
                </label>

                <label className="collaborator-field collaborator-field--wide">
                  <span>Motivo da alocação *</span>
                  <input
                    type="text"
                    value={motivoAlocacao}
                    onChange={(evento) => setMotivoAlocacao(evento.target.value)}
                    disabled={ocupado}
                  />
                </label>

                <label className="collaborator-field collaborator-field--inline">
                  <input
                    type="checkbox"
                    checked={definirGestor}
                    onChange={(evento) => setDefinirGestor(evento.target.checked)}
                    disabled={ocupado || !posicaoId}
                  />
                  <span>Definir também o gestor (reporting line)</span>
                </label>

                {definirGestor && posicaoId && (
                  <SeletorPosicao
                    id="novo-colaborador-gestor"
                    estrutura={estrutura.estado.estrutura}
                    valor={gestorPosicaoId}
                    aoMudar={setGestorPosicaoId}
                    rotulo="Posição do gestor (reporting line)"
                    vazio="Selecione a posição gerente…"
                    excluirPosicaoId={posicaoId}
                    mostrarOcupante
                    desabilitado={ocupado}
                  />
                )}
              </div>
            )}
          </>
        )}
      </section>

      {erroLocal && (
        <div className="collaborator-form-error" role="alert">
          {erroLocal}
        </div>
      )}

      {processando && (
        <div className="collaborator-form-info" role="status" aria-live="polite">
          Gravando o cadastro no servidor…
        </div>
      )}

      {alocando && (
        <div className="collaborator-form-info" role="status" aria-live="polite">
          Aplicando a alocação soberana…
        </div>
      )}

      {estado.fase === "sucesso" && (
        <div className="collaborator-form-info" role="status">
          Colaborador criado no cadastro soberano.
        </div>
      )}

      {estado.fase === "erro" && (
        <div className="collaborator-form-error" role="alert">
          <strong>
            {estado.codigo === "FORBIDDEN"
              ? "Acesso restrito"
              : estado.codigo === "CONFLICT"
                ? "Conflito ao cadastrar"
                : "Não foi possível cadastrar o colaborador"}
          </strong>
          <p>{estado.mensagem}</p>
          <p>Nenhum registro foi gravado localmente.</p>
        </div>
      )}

      {estadoAlocacao.fase === "erro" && (
        <div className="collaborator-form-error" role="alert" data-testid="alocacao-erro">
          <strong>
            {estadoAlocacao.parcial === "sem-ocupacao"
              ? "Colaborador criado SEM ALOCAÇÃO"
              : "Ocupação criada, gestor NÃO definido"}
          </strong>
          <p>
            {estadoAlocacao.mensagem} ({estadoAlocacao.codigo})
          </p>
          <p>
            {estadoAlocacao.parcial === "sem-ocupacao"
              ? "O colaborador permanece criado e sem alocação: a ocupação é uma operação separada e não houve rollback local."
              : "A ocupação vigente já está gravada e a reporting line não: o servidor é a fonte do estado real."}
          </p>
          {colaboradorCriado && (
            <div className="collaborator-form-actions">
              <button
                type="button"
                className="collaborator-form-btn collaborator-form-btn--primary"
                onClick={() => {
                  void alocarColaborador(colaboradorCriado);
                }}
                disabled={ocupado || !alocacaoDisponivel}
              >
                Tentar alocar novamente
              </button>
              <button
                type="button"
                className="collaborator-form-btn collaborator-form-btn--secondary"
                onClick={() => navigate(`/colaborador/${colaboradorCriado}/editar`)}
              >
                Abrir a ficha do colaborador
              </button>
            </div>
          )}
        </div>
      )}

      <div className="collaborator-form-actions">
        <button
          type="button"
          className="collaborator-form-btn collaborator-form-btn--secondary"
          onClick={() => navigate("/")}
        >
          Cancelar
        </button>

        <button
          type="button"
          className="collaborator-form-btn collaborator-form-btn--primary"
          onClick={() => {
            void handleSalvar();
          }}
          disabled={ocupado}
        >
          {processando
            ? "Salvando…"
            : alocando
              ? "Alocando…"
              : "Salvar colaborador"}
        </button>
      </div>
    </main>
  );
}

export default NovoColaboradorPage;
