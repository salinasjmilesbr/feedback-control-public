import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import type {
  Colaborador,
  FuncaoColaborador,
  SenioridadeColaborador,
  StatusColaborador,
} from "../types/Colaborador";
import type { EscopoMovimentacaoOrganizacional } from "../types/HistoricoOrganizacional";
import {
  getColaboradorByMatricula,
  getColaboradores,
  updateColaborador,
} from "../services/colaboradorStorage";
import {
  houveMudancaOrganizacional,
  registrarMovimentacaoOrganizacional,
} from "../services/historicoOrganizacionalStorage";
import { getCicloAtivo } from "../services/cicloAvaliacaoStorage";
import "../styles/colaborador-form.css";
import "../styles/historico-organizacional.css";

function hojeLocal() {
  const agora = new Date();
  const offset = agora.getTimezoneOffset();
  return new Date(agora.getTime() - offset * 60000)
    .toISOString()
    .slice(0, 10);
}

function EditarColaboradorPage() {
  const navigate = useNavigate();
  const { id } = useParams();

  const matricula = Number(id);
  const colaborador = Number.isFinite(matricula)
    ? getColaboradorByMatricula(matricula)
    : undefined;

  const colaboradoresExistentes = getColaboradores();
  const cicloAtivo = getCicloAtivo();

  const [nome, setNome] = useState(colaborador?.nome ?? "");
  const [email, setEmail] = useState(colaborador?.email ?? "");
  const [cargo, setCargo] = useState(colaborador?.cargo ?? "");
  const [area, setArea] = useState(colaborador?.area ?? "");
  const [funcao, setFuncao] = useState<FuncaoColaborador>(
    colaborador?.funcao ?? "ANALISTA"
  );
  const [senioridade, setSenioridade] = useState<SenioridadeColaborador>(
    colaborador?.senioridade ?? "JUNIOR"
  );
  const [avaliadoresColegiadoMatriculas, setAvaliadoresColegiadoMatriculas] =
    useState<number[]>(colaborador?.avaliadoresColegiadoMatriculas ?? []);
  const [gestorDiretoMatricula, setGestorDiretoMatricula] =
    useState(colaborador?.gestorDiretoMatricula?.toString() ?? "");
  const [status, setStatus] = useState<StatusColaborador>(
    colaborador?.status ?? "ATIVO"
  );
  const [dataAdmissao, setDataAdmissao] = useState(
    colaborador?.dataAdmissao ?? ""
  );
  const [dataVigencia, setDataVigencia] = useState(hojeLocal());
  const [escopo, setEscopo] =
    useState<EscopoMovimentacaoOrganizacional>(
      "CICLO_ATUAL_E_POSTERIORES"
    );
  const [motivo, setMotivo] = useState("");
  const [erro, setErro] = useState("");

  if (!colaborador) {
    return (
      <main className="virtus-page collaborator-form-page">
        <section className="collaborator-form-empty-state">
          <h1>Colaborador não encontrado</h1>
          <p>Não foi possível localizar o cadastro solicitado.</p>
          <button
            type="button"
            className="collaborator-form-btn collaborator-form-btn--secondary"
            onClick={() => navigate("/")}
          >
            Voltar aos colaboradores
          </button>
        </section>
      </main>
    );
  }

  const colaboradorAtual = colaborador;

  const gestoresDisponiveis = colaboradoresExistentes
    .filter(
      (item) =>
        item.matricula !== colaboradorAtual.matricula &&
        item.status === "ATIVO" &&
        (funcao === "ANALISTA"
          ? item.funcao === "GERENTE" || item.funcao === "COORDENADOR"
          : item.funcao === "GERENTE")
    )
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  const avaliadoresDisponiveis = colaboradoresExistentes
    .filter(
      (item) =>
        item.matricula !== colaboradorAtual.matricula &&
        item.status === "ATIVO" &&
        (item.funcao === "GERENTE" || item.funcao === "COORDENADOR")
    )
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  function toggleAvaliador(matriculaAvaliador: number) {
    setAvaliadoresColegiadoMatriculas((atuais) =>
      atuais.includes(matriculaAvaliador)
        ? atuais.filter((item) => item !== matriculaAvaliador)
        : [...atuais, matriculaAvaliador]
    );
  }

  function handleSalvar() {
    setErro("");

    if (!nome.trim() || !email.trim() || !cargo.trim() || !area.trim()) {
      setErro("Preencha todos os campos obrigatórios.");
      return;
    }

    const gestorDireto = gestorDiretoMatricula
      ? colaboradoresExistentes.find(
          (item) =>
            item.matricula === Number(gestorDiretoMatricula)
        )
      : undefined;

    const mudouParaLicenca =
      colaboradorAtual.status !== "LICENCA" && status === "LICENCA";
    const retornouLicenca =
      colaboradorAtual.status === "LICENCA" && status === "ATIVO";
    const mudouParaDesligado =
      colaboradorAtual.status !== "DESLIGADO" && status === "DESLIGADO";

    const colaboradorAtualizado: Colaborador = {
      ...colaboradorAtual,
      nome: nome.trim(),
      email: email.trim(),
      cargo: cargo.trim(),
      area: area.trim(),
      funcao,
      senioridade:
        funcao === "ANALISTA" ? senioridade : undefined,
      gestorDiretoMatricula: gestorDireto?.matricula,
      respondePara: gestorDireto?.nome ?? "",
      avaliadoresColegiadoMatriculas:
        funcao === "ANALISTA" ? avaliadoresColegiadoMatriculas : [],
      status,
      dataAdmissao: dataAdmissao || colaboradorAtual.dataAdmissao,
      dataInicioLicenca: mudouParaLicenca
        ? dataVigencia
        : colaboradorAtual.dataInicioLicenca,
      dataFimLicenca: retornouLicenca
        ? dataVigencia
        : colaboradorAtual.dataFimLicenca,
      dataDesligamento: mudouParaDesligado
        ? dataVigencia
        : colaboradorAtual.dataDesligamento,
    };

    const mudouEstrutura = houveMudancaOrganizacional(
      colaboradorAtual,
      colaboradorAtualizado
    );

    if (mudouEstrutura && !dataVigencia) {
      setErro("Informe a data de vigência da movimentação.");
      return;
    }

    try {
      updateColaborador(colaboradorAtualizado);

      if (mudouEstrutura) {
        registrarMovimentacaoOrganizacional({
          anterior: colaboradorAtual,
          atual: colaboradorAtualizado,
          colaboradores: colaboradoresExistentes,
          dataVigencia,
          escopo,
          motivo,
        });
      }

      navigate(`/colaborador/${colaboradorAtual.matricula}`);
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível atualizar o colaborador."
      );
    }
  }

  return (
    <main className="virtus-page collaborator-form-page">
      <section className="collaborator-form-header">
        <div>
          <button
            type="button"
            className="collaborator-form-back"
            onClick={() =>
              navigate(`/colaborador/${colaboradorAtual.matricula}`)
            }
          >
            ← Voltar ao colaborador
          </button>
          <span className="collaborator-form-eyebrow">Cadastro</span>
          <h1>Editar colaborador</h1>
          <p>
            Atualize dados profissionais e registre mudanças de estrutura com
            vigência definida.
          </p>
        </div>

        <div className="collaborator-form-profile">
          <span className="collaborator-form-profile__avatar">
            {colaboradorAtual.nome
              .split(" ")
              .filter(Boolean)
              .slice(0, 2)
              .map((parte) => parte[0])
              .join("")
              .toUpperCase()}
          </span>
          <div>
            <strong>{colaboradorAtual.nome}</strong>
            <small>Matrícula {colaboradorAtual.matricula}</small>
          </div>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">01</span>
          <div>
            <h2>Dados do colaborador</h2>
            <p>Informações cadastrais e vínculo profissional.</p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Matrícula</span>
            <input
              type="number"
              value={colaboradorAtual.matricula}
              disabled
            />
            <small>A matrícula não pode ser alterada.</small>
          </label>

          <label className="collaborator-field">
            <span>Data de admissão</span>
            <input
              type="date"
              value={dataAdmissao}
              onChange={(e) => setDataAdmissao(e.target.value)}
            />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>Nome *</span>
            <input type="text" value={nome} onChange={(e) => setNome(e.target.value)} />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>E-mail *</span>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          </label>

          <label className="collaborator-field">
            <span>Cargo *</span>
            <input type="text" value={cargo} onChange={(e) => setCargo(e.target.value)} />
          </label>

          <label className="collaborator-field">
            <span>Área *</span>
            <input type="text" value={area} onChange={(e) => setArea(e.target.value)} />
          </label>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">02</span>
          <div>
            <h2>Estrutura organizacional</h2>
            <p>Defina função, senioridade, gestor direto e situação atual.</p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Função *</span>
            <select value={funcao} onChange={(e) => setFuncao(e.target.value as FuncaoColaborador)}>
              <option value="ANALISTA">Analista</option>
              <option value="COORDENADOR">Coordenador</option>
              <option value="CONSULTOR">Consultor</option>
              <option value="GERENTE">Gerente</option>
            </select>
          </label>

          {funcao === "ANALISTA" && (
            <label className="collaborator-field">
              <span>Senioridade *</span>
              <select value={senioridade} onChange={(e) => setSenioridade(e.target.value as SenioridadeColaborador)}>
                <option value="JUNIOR">Júnior</option>
                <option value="PLENO">Pleno</option>
                <option value="SENIOR">Sênior</option>
              </select>
            </label>
          )}

          <label className="collaborator-field">
            <span>Gestor direto</span>
            <select value={gestorDiretoMatricula} onChange={(e) => setGestorDiretoMatricula(e.target.value)}>
              <option value="">Sem gestor direto</option>
              {gestoresDisponiveis.map((gestor) => (
                <option key={gestor.matricula} value={gestor.matricula}>
                  {gestor.nome}
                </option>
              ))}
            </select>
          </label>

          <label className="collaborator-field">
            <span>Status *</span>
            <select value={status} onChange={(e) => setStatus(e.target.value as StatusColaborador)}>
              <option value="ATIVO">Ativo</option>
              <option value="LICENCA">Em licença</option>
              <option value="DESLIGADO">Desligado</option>
            </select>
          </label>
        </div>
      </section>

      {funcao === "ANALISTA" && (
        <section className="collaborator-form-card">
          <div className="collaborator-form-card__heading">
            <span className="collaborator-form-card__icon" aria-hidden="true">03</span>
            <div>
              <h2>Avaliadores do colegiado</h2>
              <p>
                Selecione quantos gestores forem necessários. Cada alteração
                será preservada no histórico.
              </p>
            </div>
          </div>

          {avaliadoresDisponiveis.length === 0 ? (
            <div className="collaborator-form-empty">
              Nenhum gerente ou coordenador ativo disponível.
            </div>
          ) : (
            <div className="collaborator-reviewers">
              {avaliadoresDisponiveis.map((avaliador) => {
                const selecionado =
                  avaliadoresColegiadoMatriculas.includes(avaliador.matricula);

                return (
                  <label
                    key={avaliador.matricula}
                    className={`collaborator-reviewer ${selecionado ? "is-selected" : ""}`}
                  >
                    <input
                      type="checkbox"
                      checked={selecionado}
                      onChange={() => toggleAvaliador(avaliador.matricula)}
                    />
                    <span className="collaborator-reviewer__avatar">
                      {avaliador.nome
                        .split(" ")
                        .filter(Boolean)
                        .slice(0, 2)
                        .map((parte) => parte[0])
                        .join("")
                        .toUpperCase()}
                    </span>
                    <span className="collaborator-reviewer__copy">
                      <strong>{avaliador.nome}</strong>
                      <small>
                        {avaliador.funcao === "GERENTE" ? "Gerente" : "Coordenador"}
                      </small>
                    </span>
                  </label>
                );
              })}
            </div>
          )}
        </section>
      )}

      <section className="collaborator-form-card collaborator-form-card--movement">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">04</span>
          <div>
            <h2>Vigência da alteração</h2>
            <p>
              Mudanças de estrutura, função, status, gestor ou colegiado ficam
              registradas sem reescrever o histórico anterior.
            </p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Data de vigência *</span>
            <input type="date" value={dataVigencia} onChange={(e) => setDataVigencia(e.target.value)} />
          </label>

          <label className="collaborator-field">
            <span>Aplicar a *</span>
            <select value={escopo} onChange={(e) => setEscopo(e.target.value as EscopoMovimentacaoOrganizacional)}>
              <option value="CICLO_ATUAL_E_POSTERIORES">
                {cicloAtivo
                  ? `Ciclo atual (${cicloAtivo.ano}.${cicloAtivo.ciclo}) e posteriores`
                  : "Estrutura atual e ciclos posteriores"}
              </option>
              <option value="SOMENTE_CICLOS_POSTERIORES">
                Somente ciclos posteriores
              </option>
            </select>
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>Motivo da movimentação</span>
            <input
              type="text"
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="Ex.: transferência de equipe, promoção, reorganização..."
            />
            <small>
              Opcional, mas recomendado para mudanças de gestor, função ou
              desligamento.
            </small>
          </label>
        </div>

        <div className="collaborator-form-info">
          O cadastro representa a situação atual. O histórico preserva a
          estrutura anterior e a nova estrutura com a data efetiva da mudança.
        </div>
      </section>

      {erro && <div className="collaborator-form-error">{erro}</div>}

      <div className="collaborator-form-actions">
        <button
          type="button"
          className="collaborator-form-btn collaborator-form-btn--secondary"
          onClick={() =>
            navigate(`/colaborador/${colaboradorAtual.matricula}`)
          }
        >
          Cancelar
        </button>

        <button
          type="button"
          className="collaborator-form-btn collaborator-form-btn--primary"
          onClick={handleSalvar}
        >
          Salvar alterações
        </button>
      </div>
    </main>
  );
}

export default EditarColaboradorPage;
