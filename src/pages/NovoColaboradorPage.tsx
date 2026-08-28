import { useState } from "react";
import { useNavigate } from "react-router-dom";
import type {
  Colaborador,
  FuncaoColaborador,
  SenioridadeColaborador,
  StatusColaborador,
} from "../types/Colaborador";
import {
  getColaboradores,
  saveColaborador,
} from "../services/colaboradorStorage";
import "../styles/colaborador-form.css";

function NovoColaboradorPage() {
  const navigate = useNavigate();
  const colaboradoresExistentes = getColaboradores();

  const [matricula, setMatricula] = useState("");
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [cargo, setCargo] = useState("");
  const [area, setArea] = useState("");
  const [funcao, setFuncao] = useState<FuncaoColaborador>("ANALISTA");
  const [senioridade, setSenioridade] =
    useState<SenioridadeColaborador>("JUNIOR");
  const [
    avaliadoresColegiadoMatriculas,
    setAvaliadoresColegiadoMatriculas,
  ] = useState<number[]>([]);
  const [gestorDiretoMatricula, setGestorDiretoMatricula] = useState("");
  const [status, setStatus] = useState<StatusColaborador>("ATIVO");
  const [erro, setErro] = useState("");

  const gestoresDisponiveis = colaboradoresExistentes
    .filter(
      (colaborador) =>
        colaborador.status === "ATIVO" &&
        (funcao === "ANALISTA"
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
        ? atuais.filter((matriculaAtual) => matriculaAtual !== matriculaAvaliador)
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
      !area.trim()
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
        funcao === "ANALISTA" ? avaliadoresColegiadoMatriculas : [],
      gestorDiretoMatricula: gestorDireto?.matricula,
      respondePara: gestorDireto?.nome ?? "",
      status,
    };

    try {
      saveColaborador(novoColaborador);
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
          <span className="collaborator-form-card__icon" aria-hidden="true">
            01
          </span>
          <div>
            <h2>Dados do colaborador</h2>
            <p>Informações básicas usadas em toda a experiência do Virtus.</p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Matrícula *</span>
            <input
              type="number"
              value={matricula}
              onChange={(event) => setMatricula(event.target.value)}
              placeholder="Ex.: 123456"
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
            <span>Cargo *</span>
            <input
              type="text"
              value={cargo}
              onChange={(event) => setCargo(event.target.value)}
              placeholder="Ex.: Analista de Operações"
            />
          </label>

          <label className="collaborator-field">
            <span>Área *</span>
            <input
              type="text"
              value={area}
              onChange={(event) => setArea(event.target.value)}
              placeholder="Ex.: Operações Digitais"
            />
          </label>
        </div>
      </section>

      <section className="collaborator-form-card">
        <div className="collaborator-form-card__heading">
          <span className="collaborator-form-card__icon" aria-hidden="true">
            02
          </span>
          <div>
            <h2>Estrutura organizacional</h2>
            <p>Defina função, senioridade e gestor direto do colaborador.</p>
          </div>
        </div>

        <div className="collaborator-form-grid">
          <label className="collaborator-field">
            <span>Função *</span>
            <select
              value={funcao}
              onChange={(event) =>
                setFuncao(event.target.value as FuncaoColaborador)
              }
            >
              <option value="ANALISTA">Analista</option>
              <option value="COORDENADOR">Coordenador</option>
              <option value="CONSULTOR">Consultor</option>
              <option value="GERENTE">Gerente</option>
            </select>
          </label>

          {funcao === "ANALISTA" && (
            <label className="collaborator-field">
              <span>Senioridade *</span>
              <select
                value={senioridade}
                onChange={(event) =>
                  setSenioridade(
                    event.target.value as SenioridadeColaborador
                  )
                }
              >
                <option value="JUNIOR">Júnior</option>
                <option value="PLENO">Pleno</option>
                <option value="SENIOR">Sênior</option>
              </select>
            </label>
          )}

          <label className="collaborator-field">
            <span>Gestor direto</span>
            <select
              value={gestorDiretoMatricula}
              onChange={(event) =>
                setGestorDiretoMatricula(event.target.value)
              }
            >
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
            <select
              value={status}
              onChange={(event) =>
                setStatus(event.target.value as StatusColaborador)
              }
            >
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
            <span className="collaborator-form-card__icon" aria-hidden="true">
              03
            </span>
            <div>
              <h2>Avaliadores do colegiado</h2>
              <p>
                Selecione os gestores que participarão da avaliação colegiada.
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
                    className={`collaborator-reviewer ${
                      selecionado ? "is-selected" : ""
                    }`}
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
                        {avaliador.funcao === "GERENTE"
                          ? "Gerente"
                          : "Coordenador"}
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
