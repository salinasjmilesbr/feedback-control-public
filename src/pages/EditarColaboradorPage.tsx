import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import type {
  Colaborador,
  FuncaoColaborador,
  SenioridadeColaborador,
  StatusColaborador,
} from "../types/Colaborador";
import {
  getColaboradorByMatricula,
  getColaboradores,
  updateColaborador,
} from "../services/colaboradorStorage";
import "../styles/colaborador-form.css";

function EditarColaboradorPage() {
  const navigate = useNavigate();
  const { id } = useParams();

  const matricula = Number(id);
  const colaborador = Number.isFinite(matricula)
    ? getColaboradorByMatricula(matricula)
    : undefined;

  const colaboradoresExistentes = getColaboradores();

  const [nome, setNome] = useState(colaborador?.nome ?? "");
  const [email, setEmail] = useState(colaborador?.email ?? "");
  const [cargo, setCargo] = useState(colaborador?.cargo ?? "");
  const [area, setArea] = useState(colaborador?.area ?? "");
  const [funcao, setFuncao] = useState<FuncaoColaborador>(
    colaborador?.funcao ?? "ANALISTA"
  );
  const [senioridade, setSenioridade] =
    useState<SenioridadeColaborador>(
      colaborador?.senioridade ?? "JUNIOR"
    );
  const [
    avaliadoresColegiadoMatriculas,
    setAvaliadoresColegiadoMatriculas,
  ] = useState<number[]>(
    colaborador?.avaliadoresColegiadoMatriculas ?? []
  );
  const [gestorDiretoMatricula, setGestorDiretoMatricula] =
    useState(colaborador?.gestorDiretoMatricula?.toString() ?? "");
  const [status, setStatus] = useState<StatusColaborador>(
    colaborador?.status ?? "ATIVO"
  );
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
          ? item.funcao === "GERENTE" ||
            item.funcao === "COORDENADOR"
          : item.funcao === "GERENTE")
    )
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  const avaliadoresDisponiveis = colaboradoresExistentes
    .filter(
      (item) =>
        item.matricula !== colaboradorAtual.matricula &&
        item.status === "ATIVO" &&
        (item.funcao === "GERENTE" ||
          item.funcao === "COORDENADOR")
    )
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

  function toggleAvaliador(matriculaAvaliador: number) {
    setAvaliadoresColegiadoMatriculas((atuais) =>
      atuais.includes(matriculaAvaliador)
        ? atuais.filter(
            (matriculaAtual) =>
              matriculaAtual !== matriculaAvaliador
          )
        : [...atuais, matriculaAvaliador]
    );
  }

  function handleSalvar() {
    setErro("");

    if (
      !nome.trim() ||
      !email.trim() ||
      !cargo.trim() ||
      !area.trim()
    ) {
      setErro("Preencha todos os campos obrigatórios.");
      return;
    }

    const gestorDireto = gestorDiretoMatricula
      ? colaboradoresExistentes.find(
          (item) =>
            item.matricula === Number(gestorDiretoMatricula)
        )
      : undefined;

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
    };

    try {
      updateColaborador(colaboradorAtualizado);
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
            Atualize dados profissionais, estrutura de gestão e participação
            no colegiado.
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
            <span>Matrícula</span>
            <input
              type="number"
              value={colaboradorAtual.matricula}
              disabled
            />
            <small>A matrícula não pode ser alterada.</small>
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>Nome *</span>
            <input
              type="text"
              value={nome}
              onChange={(event) => setNome(event.target.value)}
            />
          </label>

          <label className="collaborator-field collaborator-field--wide">
            <span>E-mail *</span>
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </label>

          <label className="collaborator-field">
            <span>Cargo *</span>
            <input
              type="text"
              value={cargo}
              onChange={(event) => setCargo(event.target.value)}
            />
          </label>

          <label className="collaborator-field">
            <span>Área *</span>
            <input
              type="text"
              value={area}
              onChange={(event) => setArea(event.target.value)}
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
