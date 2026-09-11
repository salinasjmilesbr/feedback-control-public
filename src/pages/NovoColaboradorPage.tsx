/**
 * F5-07 — Novo colaborador: cadastro SOMENTE pela porta única.
 *
 * Escopo desta tela: dados de PESSOA (nome, e-mail, data de admissão), matrícula
 * como INTENÇÃO e status inicial. Nada de estrutura organizacional aqui — cargo,
 * unidade, gestor, senioridade e colegiado pertencem à F5-08 e saíram do
 * formulário; o colaborador nasce explicitamente SEM ALOCAÇÃO.
 *
 * Não existe escrita local: nenhuma chamada a `localStorage`, nenhum dual-write e
 * nenhum fallback. A autorização é do servidor (`collaborator.create`): a porta
 * devolve `FORBIDDEN`/`INVALID_INPUT`/`CONFLICT` e a tela mostra o estado.
 */

import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import {
  criarColaborador,
  type DependenciasAcessoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
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

type NovoColaboradorPageProps = {
  /** Operações da porta (injeção de teste); produção usa o caminho padrão. */
  readonly deps?: DependenciasAcessoColaboradores;
  /** Semente de estado (SSR/teste determinístico). */
  readonly estadoInicial?: EstadoCriacaoColaborador;
};

type StatusInicialSoberano = "active" | "leave";

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

const SEM_ORGANIZACAO_ATIVA =
  "Selecione uma organização ativa para cadastrar colaboradores.";

const AVISO_ESTRUTURA =
  "Cargo, unidade, gestor direto, senioridade e colegiado não são definidos neste cadastro: " +
  "eles pertencem à estrutura organizacional (F5-08). O colaborador é criado SEM ALOCAÇÃO e " +
  "passa a exibir \"sem alocação\" até que a ocupação seja definida no módulo de estrutura.";

function hojeLocal(): string {
  const agora = new Date();
  const offset = agora.getTimezoneOffset();
  return new Date(agora.getTime() - offset * 60000).toISOString().slice(0, 10);
}

/**
 * `operation_id` (idempotência da mutação, §13.5) gerado pelo chamador. Não é
 * identidade nem autoridade: serve apenas para a fronteira não duplicar efeitos.
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
}: NovoColaboradorPageProps = {}) {
  const navigate = useNavigate();
  const { organizacaoAtivaId } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [estado, setEstado] = useState<EstadoCriacaoColaborador>(
    estadoInicial ?? { fase: "inicial" }
  );

  const [matricula, setMatricula] = useState("");
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [dataAdmissao, setDataAdmissao] = useState(hojeLocal);
  const [statusInicial, setStatusInicial] =
    useState<StatusInicialSoberano>("active");
  const [erroLocal, setErroLocal] = useState("");

  const processando = estado.fase === "processando";

  async function handleSalvar() {
    if (processando) return;

    setErroLocal("");

    if (!matricula.trim() || !nome.trim() || !email.trim()) {
      setErroLocal("Preencha todos os campos obrigatórios.");
      return;
    }

    if (!/^\d+$/.test(matricula.trim()) || Number(matricula.trim()) <= 0) {
      setErroLocal("Informe uma matrícula válida (somente dígitos).");
      return;
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
    navigate(`/colaborador/${resultado.dados}`);
  }

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
            <h2>Estrutura organizacional (F5-08)</h2>
            <p>
              Cargo, unidade, gestor, senioridade e colegiado não fazem parte
              deste cadastro.
            </p>
          </div>
        </div>

        <div className="collaborator-form-empty">{AVISO_ESTRUTURA}</div>
      </section>

      {erroLocal && (
        <div className="collaborator-form-error" role="alert">
          {erroLocal}
        </div>
      )}

      {estado.fase === "processando" && (
        <div className="collaborator-form-info" role="status" aria-live="polite">
          Gravando o cadastro no servidor…
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
          disabled={processando}
        >
          {processando ? "Salvando…" : "Salvar colaborador"}
        </button>
      </div>
    </main>
  );
}

export default NovoColaboradorPage;
