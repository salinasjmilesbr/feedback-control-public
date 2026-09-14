import { useEffect, useState } from "react";
import type { MetaSoberana } from "../application/ports/GoalRepository";
import { obterRepositorioMetasSoberanas } from "../services/acessoMetasSoberanas";
import { obterRepositorioCiclosSoberanos } from "../services/acessoCiclosSoberanos";
import { collaboratorIdDoLegado, estruturaSoberanaEfetiva } from "../services/estruturaSoberanaCliente";
import { getColaboradores } from "../services/colaboradorStorage";

/**
 * F5-10 P6 (Issue #220) — METAS DO AVALIADO (relação SELF) para o formulário de
 * feedback.
 *
 * As telas de feedback só precisam saber se a meta do colaborador avaliado está
 * FORMALMENTE aprovada (todos os papéis EXIGIDOS vigentes). Esse fato vem da
 * superfície soberana `goal.listar_por_escopo` — nunca de helper do domínio
 * local de metas, de `funcao` textual ou de hierarquia viva.
 *
 * Fail-closed e SEM fallback: sem caminho soberano, sem organização, sem UUID do
 * avaliado ou sem ciclo resolvido, a leitura fica INDISPONÍVEL com aviso
 * explícito (`erro`) — nunca uma lista vazia silenciosa ("tudo aprovado").
 * O formulário NÃO é bloqueado por esse erro: ele apenas avisa.
 */

export interface MetasSoberanasDaAvaliacao {
  readonly metas: readonly MetaSoberana[];
  /** Metas do avaliado que NÃO têm todas as aprovações EXIGIDAS vigentes. */
  readonly semAprovacaoFormal: readonly MetaSoberana[];
  readonly carregando: boolean;
  /** Aviso explícito quando a leitura soberana não pôde ser concluída. */
  readonly erro: string;
}

const ERRO_SEM_CAMINHO =
  "As metas do ciclo não estão disponíveis pelo caminho soberano neste ambiente.";
const ERRO_CICLO =
  "Não foi possível resolver o ciclo da avaliação pelo caminho soberano.";
const ERRO_LEITURA = "Não foi possível carregar as metas do ciclo.";

/** Meta formalmente aprovada: TODOS os papéis EXIGIDOS estão vigentes. */
function formalmenteAprovada(meta: MetaSoberana): boolean {
  return meta.aprovacoes.every(
    (aprovacao) => !aprovacao.exigida || aprovacao.vigente
  );
}

/** Resultado de UMA leitura (o que a tela consome, sem a chave do contexto). */
interface ResultadoDaLeitura {
  readonly metas: readonly MetaSoberana[];
  readonly carregando: boolean;
  readonly erro: string;
}

/** Sem ENTRADA (organização/ano/ciclo/avaliado): nada a ler e nenhum erro. */
const SEM_ENTRADA: ResultadoDaLeitura = {
  metas: [],
  carregando: false,
  erro: "",
};

/** Há entrada, mas a leitura da chave CORRENTE ainda não foi publicada. */
const LEITURA_PENDENTE: ResultadoDaLeitura = {
  metas: [],
  carregando: true,
  erro: "",
};

/** Leitura publicada, PRESA à chave do contexto que a produziu. */
interface LeituraPublicada extends ResultadoDaLeitura {
  readonly chave: string;
}

export function useMetasSoberanasDaAvaliacao(entrada: {
  readonly organizationId: string | null;
  readonly ano: number | undefined;
  readonly ciclo: number | undefined;
  readonly matriculaDoAvaliado: number | undefined;
}): MetasSoberanasDaAvaliacao {
  const { organizationId, ano, ciclo, matriculaDoAvaliado } = entrada;

  /**
   * Estado EXIBIDO DERIVADO (mesmo padrão de `MinhasMetasPage`, sem `setState`
   * no corpo do efeito): o resultado é publicado com a CHAVE do contexto
   * (organização/ano/ciclo/avaliado) e só é exibido quando a chave confere —
   * resposta de contexto anterior é descartada e a tela segue `carregando`
   * (nunca "tudo aprovado" por negação silenciosa).
   */
  const [leitura, setLeitura] = useState<LeituraPublicada | null>(null);

  const semEntrada =
    !organizationId ||
    ano === undefined ||
    ciclo === undefined ||
    matriculaDoAvaliado === undefined;
  const chave = `${organizationId ?? "sem-organizacao"}|${ano ?? "sem-ano"}|${
    ciclo ?? "sem-ciclo"
  }|${matriculaDoAvaliado ?? "sem-avaliado"}`;

  useEffect(() => {
    if (
      !organizationId ||
      ano === undefined ||
      ciclo === undefined ||
      matriculaDoAvaliado === undefined
    ) {
      return;
    }

    // Chave e entradas ficam FIXAS nesta execução: só ela pode publicar.
    const organizationIdAtual = organizationId;
    const matriculaAtual = matriculaDoAvaliado;

    let ativo = true;
    // Publica SEMPRE com a chave do contexto corrente — resposta de contexto
    // anterior não é exibida — e `ativo` descarta `setState` pós-desmonte.
    const publicar = (estado: ResultadoDaLeitura) => {
      if (ativo) setLeitura({ chave, ...estado });
    };

    void (async () => {
      const repositorio = obterRepositorioMetasSoberanas();
      const portaCiclos = obterRepositorioCiclosSoberanos();
      const colaboradorUuid = collaboratorIdDoLegado(
        estruturaSoberanaEfetiva(getColaboradores()),
        matriculaAtual
      );

      if (!repositorio || !portaCiclos || !colaboradorUuid) {
        publicar({ metas: [], carregando: false, erro: ERRO_SEM_CAMINHO });
        return;
      }

      publicar({ metas: [], carregando: true, erro: "" });

      try {
        const ciclos = await portaCiclos.listarCiclos(organizationIdAtual);

        const cicloSoberano = ciclos.ok
          ? ciclos.data.find(
              (item) => item.ano === ano && item.numero === ciclo
            )
          : undefined;

        if (!cicloSoberano) {
          publicar({ metas: [], carregando: false, erro: ERRO_CICLO });
          return;
        }

        const resultado = await repositorio.listarMetasPorEscopo(
          organizationIdAtual,
          cicloSoberano.id
        );

        if (!resultado.ok) {
          publicar({ metas: [], carregando: false, erro: ERRO_LEITURA });
          return;
        }

        // Somente o SELF do AVALIADO: a relação SELF é o que autoriza o ator a ler
        // a própria meta; metas de terceiros nunca entram aqui.
        publicar({
          metas: resultado.data.metas.filter(
            (meta) =>
              meta.relacao === "SELF" &&
              meta.collaboratorId === colaboradorUuid &&
              !meta.excluida
          ),
          carregando: false,
          erro: "",
        });
      } catch {
        publicar({ metas: [], carregando: false, erro: ERRO_LEITURA });
      }
    })();

    return () => {
      ativo = false;
    };
  }, [chave, organizationId, ano, ciclo, matriculaDoAvaliado]);

  const estado: ResultadoDaLeitura = semEntrada
    ? SEM_ENTRADA
    : leitura?.chave === chave
    ? leitura
    : LEITURA_PENDENTE;

  return {
    metas: estado.metas,
    semAprovacaoFormal: estado.metas.filter((meta) => !formalmenteAprovada(meta)),
    carregando: estado.carregando,
    erro: estado.erro,
  };
}
