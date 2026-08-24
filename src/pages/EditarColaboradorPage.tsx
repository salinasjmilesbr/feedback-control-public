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
    useState(
      colaborador?.gestorDiretoMatricula?.toString() ?? ""
    );
  const [status, setStatus] = useState<StatusColaborador>(
    colaborador?.status ?? "ATIVO"
  );
  const [erro, setErro] = useState("");

  if (!colaborador) {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Colaborador não encontrado</h1>
        <button type="button" onClick={() => navigate("/")}>
          Voltar
        </button>
      </div>
    );
  }

  const colaboradorAtual = colaborador;

  const gestoresDisponiveis = colaboradoresExistentes
    .filter(
      (item) =>
        item.matricula !== colaboradorAtual.matricula &&
        item.status === "ATIVO" &&
        (item.funcao === "GERENTE" ||
          item.funcao === "COORDENADOR")
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
      avaliadoresColegiadoMatriculas,
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
    <div style={{ padding: "30px", maxWidth: "700px" }}>
      <h1>Editar colaborador</h1>

      <div style={{ display: "grid", gap: "16px" }}>
        <label>
          Matrícula
          <input
            type="number"
            value={colaboradorAtual.matricula}
            disabled
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
            onChange={(e) =>
              setGestorDiretoMatricula(e.target.value)
            }
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
                style={{
                  display: "flex",
                  gap: "8px",
                  alignItems: "center",
                }}
              >
                <input
                  type="checkbox"
                  checked={avaliadoresColegiadoMatriculas.includes(
                    avaliador.matricula
                  )}
                  onChange={() =>
                    toggleAvaliador(avaliador.matricula)
                  }
                />
                {avaliador.nome}
              </label>
            ))}
          </div>
        </fieldset>

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
          <p style={{ margin: 0, color: "#b00020" }}>
            {erro}
          </p>
        )}

        <div
          style={{
            display: "flex",
            gap: "12px",
            marginTop: "10px",
          }}
        >
          <button
            type="button"
            onClick={() =>
              navigate(`/colaborador/${colaboradorAtual.matricula}`)
            }
          >
            Cancelar
          </button>

          <button type="button" onClick={handleSalvar}>
            Salvar alterações
          </button>
        </div>
      </div>
    </div>
  );
}

export default EditarColaboradorPage;
