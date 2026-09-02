import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { authorize, can } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import type {
  Colaborador,
  FuncaoColaborador,
  SenioridadeColaborador,
  StatusColaborador,
} from "../types/Colaborador";
import { funcaoUsaEstruturaAvaliacaoAnalista } from "../types/Colaborador";
import {
  getColaboradores,
  saveColaborador,
} from "../services/colaboradorStorage";
import { registrarMovimentacaoOrganizacional } from "../services/historicoOrganizacionalStorage";
import "../styles/colaborador-form.css";
import "../styles/historico-organizacional.css";

function hojeLocal() {
  const agora = new Date();
  const offset = agora.getTimezoneOffset();
  return new Date(agora.getTime() - offset * 60000)
    .toISOString()
    .slice(0, 10);
}

function NovoColaboradorPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const colaboradoresExistentes = getColaboradores();

  const [matricula, setMatricula] = useState("");
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [cargo, setCargo] = useState("");
  const [area, setArea] = useState("");
  const [funcao, setFuncao] = useState<FuncaoColaborador>("ANALISTA");
  const [senioridade, setSenioridade] =
    useState<SenioridadeColaborador>("JUNIOR");
  const [avaliadoresColegiadoMatriculas, setAvaliadoresColegiadoMatriculas] =
    useState<number[]>([]);
  const [gestorDiretoMatricula, setGestorDiretoMatricula] = useState("");
  const [status, setStatus] = useState<StatusColaborador>("ATIVO");
  const [dataAdmissao, setDataAdmissao] = useState(hojeLocal());
  const [erro, setErro] = useState("");

  const authorizationContext: AuthorizationContext | undefined = usuarioAtual
    ? {
        actor: {
          matricula: usuarioAtual.matricula,
          funcao: usuarioAtual.funcao,
          status: usuarioAtual.status,
        },
      }
    : undefined;
  const podeCriarColaborador = authorizationContext
    ? can(authorizationContext, "collaborator.create", { kind: "global" })
    : false;

  if (!usuarioAtual || !authorizationContext || !podeCriarColaborador) {
    return (
      <main className="virtus-page collaborator-form-page">
        <section className="collaborator-form-empty-state">
          <h1>Acesso restrito</h1>
          <p>A gestão de colaboradores está disponível apenas para gerentes.</p>
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

  const contextoAutorizado = authorizationContext;
  const autorAtual = usuarioAtual;

  const gestoresDisponiveis = colaboradoresExistentes
    .filter(
      (colaborador) =>
        colaborador.status === "ATIVO" &&
        (funcaoUsaEstruturaAvaliacaoAnalista(funcao)
          ? colaborador.funcao === "GERENTE" ||
            colaborador.funcao === "COORDENADOR"
          : colaborador.funcao === "GERENTE")
    )
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  const avaliadoresDisponiveis = colaboradoresExistentes
    .filter(
      (colaborador) =>
        colaborador.status === "ATIVO" &&
        (colaborador.funcao === "GERENTE" ||
          colaborador.funcao === "COORDENADOR")
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

    if (
      !matricula.trim() ||
      !nome.trim() ||
      !email.trim() ||
      !cargo.trim() ||
      !area.trim() ||
      !dataAdmissao
    ) {
      setErro("Preencha todos os campos obrigatórios.");
      return;
    }

    const novaMatricula = Number(matricula);

    if (!Number.isInteger(novaMatricula) || novaMatricula <= 0) {
      setErro("Informe uma matrícula válida.");
      return;
    }

    const gestorDireto = gestorDiretoMatricula
      ? colaboradoresExistentes.find(
          (colaborador) =>
            colaborador.matricula === Number(gestorDiretoMatricula)
        )
      : undefined;

    const novoColaborador: Colaborador = {
      matricula: novaMatricula,
      nome: nome.trim(),
      email: email.trim(),
      cargo: cargo.trim(),
      area: area.trim(),
      funcao,
      senioridade: funcao === "ANALISTA" ? senioridade : undefined,
      avaliadoresColegiadoMatriculas:
        funcaoUsaEstruturaAvaliacaoAnalista(funcao)
          ? avaliadoresColegiadoMatriculas
          : [],
      gestorDiretoMatricula: gestorDireto?.matricula,
      respondePara: gestorDireto?.nome ?? "",
      status,
      dataAdmissao,
      dataInicioLicenca: status === "LICENCA" ? dataAdmissao : undefined,
      dataDesligamento: status === "DESLIGADO" ? dataAdmissao : undefined,
    };

    try {
      authorize(
        contextoAutorizado,
        "collaborator.create",
        { kind: "global" }
      );
      saveColaborador(novoColaborador);

      registrarMovimentacaoOrganizacional({
        atual: novoColaborador,
        colaboradores: colaboradoresExistentes,
        dataVigencia: dataAdmissao,
        escopo: "CICLO_ATUAL_E_POSTERIORES",
        motivo: "Admissão / inclusão do colaborador no Virtus",
        autorMatricula: autorAtual.matricula,
        autorNome: autorAtual.nome,
      });

      navigate("/");
    } catch (error) {
      setErro(
        error instanceof Error
          ? error.message
          : "Não foi possível salvar o colaborador."
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
            onClick={() => navigate("/")}
          >
            ← Voltar aos colaboradores
          </button>
          <span className="collaborator-form-eyebrow">Cadastro</span>
          <h1>Novo colaborador</h1>
          <p>
            Cadastre os dados profissionais, vínculo de gestão e participação no
            colegiado.
          </p>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">01</span>
          <div>
            <h2>Dados do colaborador</h2>
            <p>Informações básicas e início do vínculo profissional.</p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Matrícula *</span>
            <input type="number" value={matricula} onChange={(e) => setMatricula(e.target.value)} placeholder="Ex.: 123456" />
          </label>

          <label className="collaborator-field">
            <span>Data de admissão *</span>
            <input type="date" value={dataAdmissao} onChange={(e) => setDataAdmissao(e.target.value)} />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>Nome *</span>
            <input type="text" value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome completo" />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>E-mail *</span>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="nome@empresa.com.br" />
          </label>

          <label className="collaborator-field">
            <span>Cargo *</span>
            <input type="text" value={cargo} onChange={(e) => setCargo(e.target.value)} placeholder="Ex.: Analista de Operações" />
          </label>

          <label className="collaborator-field">
            <span>Área *</span>
            <input type="text" value={area} onChange={(e) => setArea(e.target.value)} placeholder="Ex.: Operações Digitais" />
          </label>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">02</span>
          <div>
            <h2>Estrutura organizacional</h2>
            <p>Defina função, senioridade e gestor direto do colaborador.</p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Função *</span>
            <select value={funcao} onChange={(e) => setFuncao(e.target.value as FuncaoColaborador)}>
              <option value="ESTAGIARIO">Estagiário</option>
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

      {funcaoUsaEstruturaAvaliacaoAnalista(funcao) && (
        <section className="collaborator-form-card">
          <div className="collaborator-form-card__heading">
            <span className="collaborator-form-card__icon" aria-hidden="true">03</span>
            <div>
              <h2>Avaliadores do colegiado</h2>
              <p>
                Selecione quantos gestores forem necessários. A composição será
                preservada no histórico de cada vigência.
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

      {erro && <div className="collaborator-form-error">{erro}</div>}

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
          onClick={handleSalvar}
        >
          Salvar colaborador
        </button>
      </div>
    </main>
  );
}

export default NovoColaboradorPage;
