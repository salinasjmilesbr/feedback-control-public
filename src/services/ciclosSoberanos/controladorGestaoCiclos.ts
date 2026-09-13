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
 * - MUTATIONS com geração/contexto PRÓPRIOS: retorno tardio de uma mutation da
 *   organização anterior NÃO publica erro, sucesso, flag nem estado algum no
 *   contexto posterior — a invalidação vale para troca A → B, contexto SEM
 *   organização (`carregar(null)`) e `descartar()`;
 * - mutations CONCORRENTES no mesmo contexto são recusadas fail-closed
 *   (`CONFLICT`, sem chamar a Edge): uma única `operacaoEmAndamento` por vez;
 * - Edge ok + reload soberano falho ⇒ resultado final `ok: false` para a UI
 *   (confirmação indisponível): sem presunção de estado, sem rollback, sem
 *   fallback local e sem afirmar que a operação "não aconteceu";
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

/** Mensagens públicas ESTÁVEIS (nenhum detalhe interno, nenhuma autoridade). */
const MSG_MUTATION_CONCORRENTE = "Já existe uma operação de ciclo em andamento.";
const MSG_CONTEXTO_MUTATION =
  "Operação descartada: a organização ativa mudou antes da resposta.";
const MSG_CONFIRMACAO_INDISPONIVEL =
  "Operação enviada, mas o novo estado soberano não pôde ser confirmado agora.";

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
  /**
   * AUDITORIA CODEX — geração monotônica de MUTATION + dono da flag. Cada
   * mutation captura a SUA geração; o retorno tardio de uma mutation antiga não
   * publica erro, sucesso, `operacaoEmAndamento` nem qualquer estado no contexto
   * posterior. `mutationCorrente === null` significa "nenhuma mutation em voo":
   * uma segunda mutation concorrente é recusada SEM chamar a Edge.
   */
  let geracaoDeMutacao = 0;
  let mutationCorrente: number | null = null;

  function publicar(parcial: Partial<EstadoGestaoCiclos>): void {
    estado = { ...estado, ...parcial };
  }

  /**
   * Invalida MUTATIONS em voo — doutrina ÚNICA para troca A → B, contexto SEM
   * organização (`carregar(null)`) e `descartar()`: a geração avança e a flag é
   * liberada, então o retorno tardio da mutation antiga não publica nada e não
   * reintroduz o contexto anterior pelo reload.
   */
  function invalidarMutacoesEmVoo(): void {
    geracaoDeMutacao++;
    mutationCorrente = null;
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
      // Contexto SEM organização também invalida mutations em voo: sem isso, uma
      // mutation da organização anterior seguiria "corrente", poderia publicar
      // erro/flag no contexto vazio e, no sucesso, releria A e reintroduziria o
      // contexto antigo.
      invalidarMutacoesEmVoo();
      publicar({
        fase: "erro",
        organizacaoId: null,
        ciclos: [],
        erro,
        operacaoEmAndamento: false,
      });
      return { ok: false, error: erro };
    }

    const trocouDeOrganizacao = estado.organizacaoId !== organizationId;
    // Troca de organização limpa a lista imediatamente (nada do tenant anterior
    // permanece visível) e invalida respostas em voo da organização antiga.
    if (trocouDeOrganizacao) {
      gestao.invalidar();
      // Invalida MUTATIONS em voo do contexto anterior: o retorno tardio delas
      // não publica nada aqui e a flag fica livre para o contexto novo.
      invalidarMutacoesEmVoo();
    }
    publicar({
      fase: "carregando",
      organizacaoId: organizationId,
      ciclos: trocouDeOrganizacao ? [] : estado.ciclos,
      erro: null,
      operacaoEmAndamento: trocouDeOrganizacao
        ? false
        : estado.operacaoEmAndamento,
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

    // CONCORRÊNCIA (fail-closed): com uma mutation em voo, a segunda é recusada
    // sem chamar a Edge e sem alterar a mutation em andamento. Sem fila local.
    if (mutationCorrente !== null) {
      return {
        ok: false,
        error: { code: "CONFLICT", message: MSG_MUTATION_CONCORRENTE },
      };
    }

    // Contexto/geração desta mutation: só ela publica enquanto for a corrente.
    const minhaGeracao = ++geracaoDeMutacao;
    mutationCorrente = minhaGeracao;
    publicar({ operacaoEmAndamento: true, erro: null });

    const resultado = await operacao(organizationId);

    // CONTEXTO: troca de organização/descarte invalidam esta geração. O retorno
    // tardio NÃO publica erro, sucesso, flag nem estado no contexto novo.
    if (mutationCorrente !== minhaGeracao) {
      return {
        ok: false,
        error: { code: "CONFLICT", message: MSG_CONTEXTO_MUTATION },
      };
    }

    if (!resultado.ok) {
      // FALHA da Edge: o estado soberano anterior permanece (nada local).
      mutationCorrente = null;
      publicar({ operacaoEmAndamento: false, erro: resultado.error });
      return resultado;
    }

    // SUCESSO da Edge: a confirmação vem SEMPRE do reload soberano, nunca de
    // presunção. O reload preserva o filtro da última leitura da UI e obedece à
    // geração de LEITURA (uma leitura mais recente vence e nada é sobrescrito).
    const recarga = await carregar(organizationId, opcoesLeituraAtuais);

    // Se o contexto/geração mudou durante o reload, esta mutation não publica.
    if (mutationCorrente !== minhaGeracao) {
      return {
        ok: false,
        error: { code: "CONFLICT", message: MSG_CONTEXTO_MUTATION },
      };
    }
    mutationCorrente = null;
    publicar({ operacaoEmAndamento: false });

    if (!recarga.ok) {
      // A Edge PODE ter efetivado no PostgreSQL: a UI não pode tratar como
      // confirmada. `fase`/`erro` publicados pelo reload permanecem (falha de
      // confirmação), o último estado soberano válido é preservado e o próximo
      // reload reconcilia. Sem rollback client-side e sem desfazer no backend.
      return {
        ok: false,
        error: {
          code: recarga.error.code,
          message: MSG_CONFIRMACAO_INDISPONIVEL,
        },
      };
    }
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
      // MUTATIONS em voo também são invalidadas (resposta tardia não publica).
      invalidarMutacoesEmVoo();
      opcoesLeituraAtuais = { incluirCancelados: false };
      gestao.descartar();
      estado = ESTADO_INICIAL;
    },
  };
}

export type ControladorGestaoCiclos = ReturnType<typeof criarControladorGestaoCiclos>;
