/**
 * F5-09 P8 (Issue #204) — CONTROLADOR de UI da gestão de ciclos (PURO, sem DOM).
 *
 * Encapsula TODO o comportamento assíncrono que a `CiclosAvaliacaoPage`
 * precisa, para que ele seja testável em node (sem jsdom) e para que a página
 * seja uma view fina:
 *
 * - LEITURA soberana (P5/P6) com fase explícita (`carregando`/`pronto`/`erro`);
 * - MUTAÇÕES pela Edge (P7) com `expectedVersion` da LINHA SOBERANA;
 * - RELOAD soberano após sucesso (nenhuma mutação otimista é autoridade);
 * - FALHA preserva o estado soberano anterior e publica erro público;
 * - organização vazia ⇒ NÃO opera (fail-closed);
 * - troca de organização invalida respostas em voo (nada de resposta obsoleta);
 * - GERAÇÃO MONOTÔNICA de leitura: duas leituras concorrentes da MESMA
 *   organização são resolvidas pela mais recente (a atrasada não publica lista,
 *   fase, erro nem mapa de versões);
 * - reload pós-mutation PRESERVA o filtro ("Mostrar cancelados") da última
 *   leitura da UI — o reload pertence ao controlador, não à página;
 * - `operacaoEmAndamento` impede a UI de presumir sucesso antes da resposta.
 *
 * Sem `localStorage`, sem UUID de ciclo gerado no cliente, sem fallback local.
 */

import type { CicloAvaliacao } from "../../types/CicloAvaliacao";
import {
  criarGestaoCiclosSoberanos,
  type DependenciasGestaoCiclos,
  type FalhaGestaoCiclos,
  type ResultadoGestao,
} from "./gestaoCiclosSoberanos";

export type FaseGestaoCiclos = "ocioso" | "carregando" | "pronto" | "erro";

export interface EstadoGestaoCiclos {
  readonly fase: FaseGestaoCiclos;
  /** Organização do estado publicado (nunca de dado local). */
  readonly organizacaoId: string | null;
  readonly ciclos: readonly CicloAvaliacao[];
  readonly erro: FalhaGestaoCiclos | null;
  /** `true` enquanto uma mutação está em voo (botões não presumem sucesso). */
  readonly operacaoEmAndamento: boolean;
}

const ESTADO_INICIAL: EstadoGestaoCiclos = {
  fase: "ocioso",
  organizacaoId: null,
  ciclos: [],
  erro: null,
  operacaoEmAndamento: false,
};

export function criarControladorGestaoCiclos(deps: DependenciasGestaoCiclos = {}) {
  const gestao = criarGestaoCiclosSoberanos(deps);
  /** Versão SOBERANA por ciclo (base de `expectedVersion`). Nunca local. */
  const versoes = new Map<string, number>();
  let estado: EstadoGestaoCiclos = ESTADO_INICIAL;
  /**
   * BLOCKER 1 — opções da ÚLTIMA leitura da UI. O reload disparado por mutation
   * reusa EXATAMENTE esta intenção; sem isso, "Mostrar cancelados" desmarcado
   * poderia ver cancelados reaparecerem depois de uma mutation (filtro perdido).
   */
  let opcoesLeituraAtuais: { readonly incluirCancelados: boolean } = {
    incluirCancelados: false,
  };
  /**
   * BLOCKER 2 — geração monotônica de LEITURA deste controlador. Cada `carregar`
   * captura a sua geração e SOMENTE a geração corrente publica `fase`, `ciclos`,
   * `erro` e o mapa de versões. A geração do P5 protege o repositório, mas
   * `gestao.listar()` ainda DEVOLVE a resposta atrasada — a proteção precisa
   * existir aqui também para duas leituras da MESMA organização.
   */
  let geracaoDeLeitura = 0;

  function publicar(parcial: Partial<EstadoGestaoCiclos>): void {
    estado = { ...estado, ...parcial };
  }

  /** Lê o soberano e publica. Sem organização ⇒ não opera (fail-closed). */
  async function carregar(
    organizationId: string | null,
    opcoes: { readonly incluirCancelados?: boolean } = {}
  ): Promise<ResultadoGestao<readonly CicloAvaliacao[]>> {
    // Toda chamada abre uma NOVA geração: a partir daqui, respostas de leituras
    // anteriores (mesma organização ou não) estão obsoletas e não publicam nada.
    const minhaGeracao = ++geracaoDeLeitura;
    opcoesLeituraAtuais = {
      incluirCancelados: opcoes.incluirCancelados ?? false,
    };

    if (!organizationId) {
      const erro: FalhaGestaoCiclos = {
        code: "FORBIDDEN",
        message: "Organização ativa ausente.",
      };
      gestao.invalidar();
      publicar({ fase: "erro", organizacaoId: null, ciclos: [], erro });
      return { ok: false, error: erro };
    }

    const trocouDeOrganizacao = estado.organizacaoId !== organizationId;
    // Troca de organização limpa a lista imediatamente (nada do tenant anterior
    // permanece visível) e invalida respostas em voo da organização antiga.
    if (trocouDeOrganizacao) gestao.invalidar();
    publicar({
      fase: "carregando",
      organizacaoId: organizationId,
      ciclos: trocouDeOrganizacao ? [] : estado.ciclos,
      erro: null,
    });

    const resultado = await gestao.listar(organizationId, opcoesLeituraAtuais);
    // Geração obsoleta (uma leitura mais recente já começou) ⇒ não publica NADA:
    // nem lista, nem fase, nem erro, nem mapa de versões.
    if (minhaGeracao !== geracaoDeLeitura) return resultado;
    // Resposta de uma leitura anterior (organização antiga) NUNCA publica.
    if (estado.organizacaoId !== organizationId) return resultado;

    if (!resultado.ok) {
      publicar({ fase: "erro", ciclos: estado.ciclos, erro: resultado.error });
      return resultado;
    }

    // Versões SOBERANAS da leitura recém-publicada (base de `expectedVersion`):
    // vêm do estado do controlador P5 (linhas reais), nunca de dado local.
    versoes.clear();
    for (const soberano of gestao.estado().ciclos) {
      versoes.set(soberano.id, soberano.version);
    }
    publicar({ fase: "pronto", ciclos: resultado.data, erro: null });
    return resultado;
  }

  /**
   * Versão soberana do ciclo. A projeção de view não carrega `version`, então o
   * controlador guarda o mapa a partir do estado soberano lido (nunca de dado
   * local). Sem versão conhecida ⇒ `null` ⇒ a mutação é recusada fail-closed.
   */
  function versaoSoberanaDe(cicloId: string): number {
    const versao = versoes.get(cicloId);
    return typeof versao === "number" ? versao : Number.NaN;
  }

  /** Registra a versão soberana de um ciclo lido (uso interno/testes). */
  function registrarVersao(cicloId: string, version: number): void {
    versoes.set(cicloId, version);
  }

  type Operacao = (organizationId: string) => Promise<ResultadoGestao<unknown>>;

  /**
   * Executa uma MUTAÇÃO com organização obrigatória, marca `operacaoEmAndamento`,
   * RELÊ o soberano após sucesso e preserva o estado anterior em caso de falha.
   */
  async function executarMutacao(
    operationId: string,
    operacao: Operacao
  ): Promise<ResultadoGestao<unknown>> {
    void operationId;
    const organizationId = estado.organizacaoId;
    if (!organizationId) {
      const erro: FalhaGestaoCiclos = {
        code: "FORBIDDEN",
        message: "Organização ativa ausente.",
      };
      publicar({ erro });
      return { ok: false, error: erro };
    }

    publicar({ operacaoEmAndamento: true, erro: null });
    const resultado = await operacao(organizationId);

    if (!resultado.ok) {
      // FALHA: o estado soberano anterior permanece (nenhuma alteração local).
      publicar({ operacaoEmAndamento: false, erro: resultado.error });
      return resultado;
    }

    // SUCESSO: recarrega do soberano; nunca presume o novo estado localmente.
    // O reload preserva o FILTRO da última leitura da UI (Blocker 1) e participa
    // da mesma geração monotônica (Blocker 2): uma leitura mais recente vence e
    // este reload não sobrescreve nada. Se a organização mudou no meio, o reload
    // do tenant antigo não acontece (quem manda é o contexto novo).
    if (estado.organizacaoId === organizationId) {
      await carregar(organizationId, opcoesLeituraAtuais);
    }
    publicar({ operacaoEmAndamento: false });
    return resultado;
  }

  return {
    estado: () => estado,
    versaoDe: (cicloId: string) => versaoSoberanaDe(cicloId),
    registrarVersao,
    carregar,

    async criar(entrada: {
      readonly ano: number;
      readonly numero: 1 | 2 | 3;
      readonly dataInicio: string;
      readonly dataFim: string;
    }): Promise<ResultadoGestao<unknown>> {
      return executarMutacao("cycle.criar", (organizationId) =>
        gestao.criar({ ...entrada, organizationId })
      );
    },

    async editar(entrada: {
      readonly cicloId: string;
      readonly ano: number;
      readonly numero: 1 | 2 | 3;
      readonly dataInicio: string;
      readonly dataFim: string;
    }): Promise<ResultadoGestao<unknown>> {
      const expectedVersion = versaoSoberanaDe(entrada.cicloId);
      if (Number.isNaN(expectedVersion)) {
        return { ok: false, error: { code: "CONFLICT", message: "Versão soberana indisponível." } };
      }
      return executarMutacao("cycle.editar", (organizationId) =>
        gestao.editar({
          organizationId,
          cycleId: entrada.cicloId,
          ano: entrada.ano,
          numero: entrada.numero,
          dataInicio: entrada.dataInicio,
          dataFim: entrada.dataFim,
          expectedVersion,
        })
      );
    },

    async ativar(cicloId: string): Promise<ResultadoGestao<unknown>> {
      const expectedVersion = versaoSoberanaDe(cicloId);
      if (Number.isNaN(expectedVersion)) {
        return { ok: false, error: { code: "CONFLICT", message: "Versão soberana indisponível." } };
      }
      return executarMutacao("cycle.ativar", (organizationId) =>
        gestao.ativar({ organizationId, cycleId: cicloId, expectedVersion })
      );
    },

    async encerrar(cicloId: string, motivo: string): Promise<ResultadoGestao<unknown>> {
      const expectedVersion = versaoSoberanaDe(cicloId);
      if (Number.isNaN(expectedVersion)) {
        return { ok: false, error: { code: "CONFLICT", message: "Versão soberana indisponível." } };
      }
      return executarMutacao("cycle.encerrar", (organizationId) =>
        gestao.encerrar({ organizationId, cycleId: cicloId, expectedVersion, motivo })
      );
    },

    /** Cancelamento vale para PLANEJADO e ATIVO (P4/P6) — o domínio decide. */
    async cancelar(cicloId: string, motivo: string): Promise<ResultadoGestao<unknown>> {
      const expectedVersion = versaoSoberanaDe(cicloId);
      if (Number.isNaN(expectedVersion)) {
        return { ok: false, error: { code: "CONFLICT", message: "Versão soberana indisponível." } };
      }
      return executarMutacao("cycle.cancelar", (organizationId) =>
        gestao.cancelar({ organizationId, cycleId: cicloId, expectedVersion, motivo })
      );
    },

    async reabrir(cicloId: string, motivo: string): Promise<ResultadoGestao<unknown>> {
      const expectedVersion = versaoSoberanaDe(cicloId);
      if (Number.isNaN(expectedVersion)) {
        return { ok: false, error: { code: "CONFLICT", message: "Versão soberana indisponível." } };
      }
      return executarMutacao("cycle.reabrir", (organizationId) =>
        gestao.reabrir({ organizationId, cycleId: cicloId, expectedVersion, motivo })
      );
    },

    async corrigirPeriodo(entrada: {
      readonly cicloId: string;
      readonly dataInicio: string;
      readonly dataFim: string;
      readonly justificativa: string;
    }): Promise<ResultadoGestao<unknown>> {
      const expectedVersion = versaoSoberanaDe(entrada.cicloId);
      if (Number.isNaN(expectedVersion)) {
        return { ok: false, error: { code: "CONFLICT", message: "Versão soberana indisponível." } };
      }
      return executarMutacao("cycle.corrigir_periodo", (organizationId) =>
        gestao.corrigirPeriodo({
          organizationId,
          cycleId: entrada.cicloId,
          dataInicio: entrada.dataInicio,
          dataFim: entrada.dataFim,
          justificativa: entrada.justificativa,
          expectedVersion,
        })
      );
    },

    /** Unmount/logout: descarta respostas em voo e limpa o estado publicado. */
    descartar(): void {
      // Invalida a geração: nada em voo publica depois do descarte.
      geracaoDeLeitura++;
      opcoesLeituraAtuais = { incluirCancelados: false };
      gestao.descartar();
      estado = ESTADO_INICIAL;
    },
  };
}

export type ControladorGestaoCiclos = ReturnType<typeof criarControladorGestaoCiclos>;
