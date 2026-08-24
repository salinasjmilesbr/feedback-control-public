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

function NovoColaboradorPage() {
  const navigate = useNavigate();
  const colaboradoresExistentes = getColaboradores();

  const [matricula, setMatricula] = useState("");
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [cargo, setCargo] = useState("");
  const [area, setArea] = useState("");
  const [funcao, setFuncao] = useState<FuncaoColaborador>("ANALISTA");
  const [senioridade, setSenioridade] = useState<SenioridadeColaborador>("JUNIOR");
  const [avaliadoresColegiadoMatriculas, setAvaliadoresColegiadoMatriculas] = useState<number[]>([]);
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
        ? atuais.filter((matricula) => matricula !== matriculaAvaliador)
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
    <div style={{ padding: "30px", maxWidth: "700px" }}>
      <h1>Novo colaborador</h1>

      <div style={{ display: "grid", gap: "16px" }}>
        <label>
          Matrícula
          <input
            type="number"
            value={matricula}
            onChange={(e) => setMatricula(e.target.value)}
          />
        </label>

        <label>
          Nome
          <input
            type="text"
            value={nome}
            onChange={(e) => setNome(e.target.value)}
          />
        </label>

        <label>
          E-mail
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </label>

        <label>
          Cargo
          <input
            type="text"
            value={cargo}
            onChange={(e) => setCargo(e.target.value)}
          />
        </label>

        <label>
          Área
          <input
            type="text"
            value={area}
            onChange={(e) => setArea(e.target.value)}
          />
        </label>

        <label>
          Função
          <select
            value={funcao}
            onChange={(e) =>
              setFuncao(e.target.value as FuncaoColaborador)
            }
          >
            <option value="ANALISTA">Analista</option>
            <option value="COORDENADOR">Coordenador</option>
            <option value="CONSULTOR">Consultor</option>
            <option value="GERENTE">Gerente</option>
          </select>
        </label>

        {funcao === "ANALISTA" && (
          <label>
            Senioridade
            <select
              value={senioridade}
              onChange={(e) =>
                setSenioridade(
                  e.target.value as SenioridadeColaborador
                )
              }
            >
              <option value="JUNIOR">Júnior</option>
              <option value="PLENO">Pleno</option>
              <option value="SENIOR">Sênior</option>
            </select>
          </label>
        )}

        <label>
          Gestor direto
          <select
            value={gestorDiretoMatricula}
            onChange={(e) => setGestorDiretoMatricula(e.target.value)}
          >
            <option value="">Sem gestor direto</option>
            {gestoresDisponiveis.map((gestor) => (
              <option
                key={gestor.matricula}
                value={gestor.matricula}
              >
                {gestor.nome}
              </option>
            ))}
          </select>
        </label>

        {funcao === "ANALISTA" && (
          <fieldset
          style={{
            border: "1px solid #ccc",
            borderRadius: "8px",
            padding: "12px",
          }}
        >
          <legend>Avaliadores do colegiado</legend>

          <div style={{ display: "grid", gap: "8px" }}>
            {avaliadoresDisponiveis.map((avaliador) => (
              <label
                key={avaliador.matricula}
                style={{ display: "flex", gap: "8px", alignItems: "center" }}
              >
                <input
                  type="checkbox"
                  checked={avaliadoresColegiadoMatriculas.includes(
                    avaliador.matricula
                  )}
                  onChange={() => toggleAvaliador(avaliador.matricula)}
                />
                {avaliador.nome}
              </label>
            ))}
          </div>
          </fieldset>
        )}

        <label>
          Status
          <select
            value={status}
            onChange={(e) =>
              setStatus(e.target.value as StatusColaborador)
            }
          >
            <option value="ATIVO">Ativo</option>
            <option value="LICENCA">Em licença</option>
            <option value="DESLIGADO">Desligado</option>
          </select>
        </label>

        {erro && (
          <p style={{ margin: 0, color: "#b00020" }}>{erro}</p>
        )}

        <div style={{ display: "flex", gap: "12px", marginTop: "10px" }}>
          <button
            type="button"
            onClick={() => navigate("/")}
          >
            Cancelar
          </button>

          <button
            type="button"
            onClick={handleSalvar}
          >
            Salvar colaborador
          </button>
        </div>
      </div>
    </div>
  );
}

export default NovoColaboradorPage;
