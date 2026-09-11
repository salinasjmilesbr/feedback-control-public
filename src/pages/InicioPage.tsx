/**
 * F5-07 — Início: roteamento por ESTADO SOBERANO, nunca por `funcao`.
 *
 * Antes esta tela tratava `funcao === "ANALISTA" || "CONSULTOR"` como se fosse
 * autorização para decidir qual universo exibir. Agora o universo de
 * colaboradores é decidido pela LEITURA SOBERANA (`listarColaboradores`):
 *
 * - leitura autorizada ⇒ a lista soberana é exibida (a mesma projeção já lida é
 *   entregue à tela de colaboradores, sem segunda chamada);
 * - leitura NEGADA pelo servidor ⇒ estado RESTRITO explícito, com o caminho para
 *   o universo pessoal (`/minha-avaliacao`), que não depende dessa autorização;
 * - falha de ambiente/servidor ⇒ erro explícito; nunca há fallback para dados
 *   locais nem decisão por cargo/função textual.
 */

import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import {
  listarColaboradores,
  type ColaboradorSoberano,
  type DependenciasAcessoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import ColaboradoresPage from "./ColaboradoresPage";

/** Estado do universo de colaboradores visto pela tela inicial. */
export type EstadoUniversoColaboradores =
  | { readonly fase: "carregando" }
  | {
      readonly fase: "erro";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | {
      readonly fase: "pronto";
      readonly colaboradores: readonly ColaboradorSoberano[];
    };

type InicioPageProps = {
  /** Operações da porta (injeção de teste); produção usa o caminho padrão. */
  readonly deps?: DependenciasAcessoColaboradores;
  /** Semente de estado (SSR/teste determinístico). */
  readonly estadoInicial?: EstadoUniversoColaboradores;
};

const SEM_DEPENDENCIAS: DependenciasAcessoColaboradores = {};

const SEM_ORGANIZACAO_ATIVA =
  "Selecione uma organização ativa para consultar o universo de colaboradores.";

function InicioPage({ deps, estadoInicial }: InicioPageProps = {}) {
  const { organizacaoAtivaId } = useAuth();
  const [depsInjetadas] = useState<DependenciasAcessoColaboradores>(
    () => deps ?? SEM_DEPENDENCIAS
  );
  const [carregamento, setCarregamento] = useState<{
    readonly chave: string;
    readonly estado: EstadoUniversoColaboradores;
  } | null>(null);
  const [versao, setVersao] = useState(0);

  /** Chave da leitura corrente: organização ativa + versão de recarga. */
  const chaveCarregamento = `${organizacaoAtivaId ?? "sem-organizacao"}|${versao}`;

  useEffect(() => {
    if (estadoInicial || !organizacaoAtivaId) return;

    let vigente = true;

    void listarColaboradores(
      { organizationId: organizacaoAtivaId },
      depsInjetadas
    ).then((resultado) => {
      if (!vigente) return;
      setCarregamento({
        chave: chaveCarregamento,
        estado: resultado.ok
          ? { fase: "pronto", colaboradores: resultado.dados }
          : {
              fase: "erro",
              codigo: resultado.codigo,
              mensagem: resultado.mensagem,
            },
      });
    });

    return () => {
      vigente = false;
    };
  }, [chaveCarregamento, organizacaoAtivaId, estadoInicial, depsInjetadas]);

  /**
   * Estado exibido DERIVADO: sem resultado para a chave corrente a tela está
   * carregando (nenhum `setState` síncrono no efeito). Sem organização ativa o
   * caminho é fail-closed e a leitura nem é tentada.
   */
  const estado: EstadoUniversoColaboradores =
    !organizacaoAtivaId && !estadoInicial
      ? { fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ORGANIZACAO_ATIVA }
      : (estadoInicial ??
        (carregamento?.chave === chaveCarregamento
          ? carregamento.estado
          : { fase: "carregando" }));

  if (estado.fase === "carregando") {
    return (
      <main className="virtus-page">
        <section className="virtus-empty" role="status" aria-live="polite">
          <h2>Carregando…</h2>
          <p>Consultando o universo de colaboradores no servidor.</p>
        </section>
      </main>
    );
  }

  if (estado.fase === "erro") {
    const negado = estado.codigo === "FORBIDDEN" || estado.codigo === "NOT_FOUND";

    return (
      <main className="virtus-page">
        <section className="virtus-empty" role="alert">
          <h2>
            {negado
              ? "Acesso restrito ao universo de colaboradores"
              : "Universo de colaboradores indisponível"}
          </h2>
          <p>{estado.mensagem}</p>
          <p>
            {negado
              ? "A decisão é do servidor (não do cargo exibido na interface). O universo pessoal continua disponível."
              : "O caminho soberano não respondeu; nenhum dado local é exibido como substituto."}
          </p>
          <div className="virtus-page-actions">
            <Link
              className="virtus-btn virtus-btn--outline"
              to="/minha-avaliacao"
            >
              Ir para minha avaliação
            </Link>
            <button
              type="button"
              className="virtus-btn virtus-btn--outline"
              onClick={() => setVersao((valor) => valor + 1)}
            >
              Tentar novamente
            </button>
          </div>
        </section>
      </main>
    );
  }

  // A lista soberana já foi lida aqui: a tela de colaboradores recebe a projeção
  // como semente (mesma leitura, sem segunda chamada). A chave força a releitura
  // quando a organização ativa muda.
  return (
    <ColaboradoresPage
      key={organizacaoAtivaId ?? "sem-organizacao"}
      deps={depsInjetadas}
      estadoInicial={{ fase: "pronto", colaboradores: estado.colaboradores }}
    />
  );
}

export default InicioPage;
