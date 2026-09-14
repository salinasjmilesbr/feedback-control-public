import { useEffect, useState } from "react";
import type {
  EscopoMetasSoberanas,
  MetaSoberana,
  ResultadoMetas,
} from "../application/ports/GoalRepository";
import { obterRepositorioMetasSoberanas } from "../services/acessoMetasSoberanas";
import { obterRepositorioCiclosSoberanos } from "../services/acessoCiclosSoberanos";
import { collaboratorIdDoLegado, estruturaSoberanaEfetiva } from "../services/estruturaSoberanaCliente";
import { getColaboradores } from "../services/colaboradorStorage";

/**
 * F5-10 P6 (Issue #220) — METAS DO AVALIADO no formulário de feedback.
 *
 * As telas de feedback só precisam saber se as metas DO AVALIADO estão
 * FORMALMENTE aprovadas (todos os papéis EXIGIDOS vigentes). Esse fato vem da
 * superfície soberana `goal.listar_por_escopo` — nunca de helper do domínio local
 * de metas, de `funcao` textual ou de hierarquia viva.
 *
 * O escopo devolvido pelo servidor é `SELF ∪ APROVADOR_GERENTE_CONGELADO ∪
 * APROVADOR_COORDENADOR_CONGELADO`, e a `relacao` diz COMO o ator está autorizado
 * — nunca QUEM é o dono da meta. O recorte das metas DO AVALIADO é portanto por
 * `collaboratorId` (+ `!excluida`): exigir `relacao === "SELF"` descartaria metas
 * legítimas quando o ator é o aprovador congelado do avaliado (achado HIGH da
 * auditoria do PR #228) e produziria falso estado benigno de "sem pendências".
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

/** Metas do avaliado que NÃO têm todos os papéis EXIGIDOS vigentes. */
export function metasSemAprovacaoFormal(
  metas: readonly MetaSoberana[]
): readonly MetaSoberana[] {
  return metas.filter((meta) => !formalmenteAprovada(meta));
}

/**
 * Metas DO AVALIADO dentro do escopo que o servidor JÁ autorizou.
 *
 * O dono da meta é `collaboratorId`; a `relacao` informa apenas COMO o ator está
 * autorizado (SELF, aprovador gerente congelado ou aprovador coordenador
 * congelado). Exigir `SELF` aqui descartaria metas do avaliado quando o ator é o
 * aprovador congelado dele — e o formulário passaria a dizer "sem pendências".
 */
export function metasDoAvaliadoSoberanas(
  metas: readonly MetaSoberana[],
  collaboratorIdDoAvaliado: string
): readonly MetaSoberana[] {
  return metas.filter(
    (meta) => meta.collaboratorId === collaboratorIdDoAvaliado && !meta.excluida
  );
}

/**
 * Traduz o resultado da leitura soberana no estado exibido: ERRO continua ERRO
 * (nunca sucesso vazio) e o sucesso recorta as metas do avaliado por
 * `collaboratorId` + `!excluida`.
 */
export function resultadoDaLeituraDaAvaliacao(
  resultado: ResultadoMetas<EscopoMetasSoberanas>,
  collaboratorIdDoAvaliado: string
): ResultadoDaLeitura {
  if (!resultado.ok) {
    return { metas: [], carregando: false, erro: ERRO_LEITURA };
  }
  return {
    metas: metasDoAvaliadoSoberanas(
      resultado.data.metas,
      collaboratorIdDoAvaliado
    ),
    carregando: false,
    erro: "",
  };
}

/** Resultado de UMA leitura (o que a tela consome, sem a chave do contexto). */
export interface ResultadoDaLeitura {
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

        // ERRO continua ERRO (nunca sucesso vazio) e o sucesso recorta as metas DO
        // AVALIADO por `collaboratorId` + `!excluida`: a `relacao` diz COMO o ator
        // está autorizado, não quem é o dono da meta.
        publicar(resultadoDaLeituraDaAvaliacao(resultado, colaboradorUuid));
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
    semAprovacaoFormal: metasSemAprovacaoFormal(estado.metas),
    carregando: estado.carregando,
    erro: estado.erro,
  };
}
