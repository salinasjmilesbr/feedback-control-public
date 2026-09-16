import { act } from "react";
import { renderToStaticMarkup } from "react-dom/server";

import { describe, expect, it, vi } from "vitest";

import fonteComponenteCru from "./ObservacoesColaborador.tsx?raw";

/**
 * Remove comentários de BLOCO e de LINHA — a barreira vale para o CÓDIGO, nunca
 * para a prosa que DESCREVE o que o componente não faz. Mesma semântica do helper
 * canônico `apenasCodigo` de `src/authorization/estruturaUiSeguranca.test.ts` (que
 * não é exportado): NÃO remove strings, então literal proibido em código segue
 * reprovando.
 */
function apenasCodigo(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

const fonteComponente = apenasCodigo(fonteComponenteCru);
import type { CicloSoberano } from "../application/ports/CycleRepository";
import type {
  EventoHistoricoSoberano,
  ObservacaoSoberana,
} from "../application/ports/ObservationRepository";
import type { ControladorObservacoes } from "../services/observacoesSoberanas/controladorObservacoes";
import {
  criarObservacaoSoberana,
  mensagemDaFalha,
} from "../services/observacoesSoberanas/fluxoMutacaoObservacao";
import {
  eventoTimelineDeUi,
  type FonteDeRotulosDeColaborador,
} from "../services/observacoesSoberanas/mapeadorObservacaoUi";
import type { FiltroCicloObservacoesSoberano } from "./filtroObservacoesPorCiclo";
import ObservacoesColaborador from "./ObservacoesColaborador";

/**
 * F5-11 P5 (Issue #250), L3 — CUTOVER do painel de observações do gestor.
 *
 * O harness do repositório é SSR (`renderToStaticMarkup`, sem jsdom): por isso o
 * painel aceita SEMENTES determinísticas (`estadoInicial`/`timelineInicial`,
 * mesmo padrão de `useEstruturaSoberana`) e o estado de ERRO é injetado pela
 * própria semente. O que se prova:
 * (i) o FONTE do componente não conhece `observacaoStorage`/`localStorage`, não
 * chama RPC e não carrega credencial de serviço;
 * (ii) mutação NEGADA pelo controlador não altera a lista exibida e mostra o
 * código público + mensagem (nenhuma decisão local de autorização);
 * (iii) a timeline é renderizada a partir dos itens SOBERANOS da trilha;
 * (iv) observação sem rótulo do ALVO não é exibida (mapeador devolve `null`) e a
 * omissão é informada.
 *
 * O controlador é um ESPIÃO injetado por props — exatamente a fronteira que o
 * cutover estabelece: nada aqui fala com Supabase.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "22222222-2222-4222-8222-222222222222";
const OBS = "33333333-3333-4333-8333-333333333333";
const OUTRA_OBS = "44444444-4444-4444-8444-444444444444";
const ALVO = "55555555-5555-4555-8555-555555555555";
const AUTOR = "66666666-6666-4666-8666-666666666666";
const PERFIL = "77777777-7777-4777-8777-777777777777";

function cicloSoberano(
  id: string,
  ano: number,
  numero: 1 | 2 | 3,
  status: CicloSoberano["status"]
): CicloSoberano {
  return {
    id,
    organizationId: ORG,
    ano,
    numero,
    status,
    dataInicio: null,
    dataFim: null,
    dataAtivacao: null,
    dataEncerramento: null,
    encerradoComPendencias: false,
    quantidadePendencias: 0,
    version: 0,
    criadoEm: "2026-01-01T00:00:00.000Z",
    atualizadoEm: "2026-01-01T00:00:00.000Z",
  };
}

function soberana(id: string, extra: Partial<ObservacaoSoberana> = {}): ObservacaoSoberana {
  return {
    id,
    organizationId: ORG,
    collaboratorId: ALVO,
    cycleId: CICLO,
    tipo: "POSITIVA",
    texto: `observacao ficticia ${id}`,
    comunicado: false,
    comunicadoEm: null,
    excluida: false,
    motivoExclusao: null,
    autorUserProfileId: PERFIL,
    autorCollaboratorId: AUTOR,
    version: 3,
    criadoEm: "2026-04-01T10:00:00.000Z",
    atualizadoEm: "2026-04-02T10:00:00.000Z",
    ...extra,
  };
}

const EVENTO: EventoHistoricoSoberano = {
  id: "88888888-8888-4888-8888-888888888888",
  evento: "EDITADA",
  dataEfetiva: "2026-04-02T11:00:00.000Z",
  motivo: "Edicao da definicao da observacao",
  beforeValue: { tipo: "POSITIVA", texto: "texto anterior ficticio", version: 1 },
  afterValue: { tipo: "NEGATIVA", texto: "texto atual ficticio", version: 2 },
  payloadHash: "b".repeat(64),
  actorUserProfileId: PERFIL,
  actorCollaboratorId: null,
  operationId: "99999999-9999-4999-8999-999999999999",
  criadoEm: "2026-04-02T11:00:00.000Z",
};

const rotulos: FonteDeRotulosDeColaborador = {
  doColaborador: (collaboratorId) =>
    collaboratorId === ALVO ? { matricula: 10, nome: "Alvo Fictício" } : null,
  doAutor: (collaboratorId) =>
    collaboratorId === AUTOR ? { matricula: 99, nome: "Autora Fictícia" } : null,
};

const CICLO_SOBERANO = cicloSoberano(CICLO, 2027, 1, "ATIVO");

/** Estado de LISTA já devolvido pela porta (semente SSR — nada é decidido aqui). */
function listaPronta(itens: readonly ObservacaoSoberana[]) {
  return { fase: "pronta" as const, escopo: "DIRECT_REPORTS", itens };
}

/** Estado de ERRO já devolvido pela porta (fail-closed, sem dado inventado). */
function listaNegada(codigo: "FORBIDDEN" | "NOT_FOUND") {
  return {
    fase: "erro" as const,
    erro: {
      origem: "mutacao" as const,
      codigo,
      mensagem:
        codigo === "FORBIDDEN"
          ? "Você não tem permissão para esta operação."
          : "Observação não encontrada.",
    },
  };
}

function controleEspiao(negarMutacao: boolean): ControladorObservacoes {
  const negado = {
    ok: false,
    error: {
      code: "FORBIDDEN",
      mensagem: "Você não tem permissão para esta operação.",
    },
  };
  const permitido = { ok: true, data: { observacaoId: OBS, version: 4 } };
  const mutacao = () => Promise.resolve(negarMutacao ? negado : permitido);

  return {
    listarPorEscopo: vi.fn(() =>
      Promise.resolve({
        ok: true,
        data: {
          escopo: "DIRECT_REPORTS",
          selfCollaboratorId: ALVO,
          data: "2026-04-01T00:00:00.000Z",
          total: 0,
          itens: [],
        },
      })
    ),
    obter: vi.fn(),
    historico: vi.fn(() =>
      Promise.resolve({
        ok: true,
        data: { observacaoId: OBS, total: 1, eventos: [EVENTO] },
      })
    ),
    criar: vi.fn(mutacao),
    editar: vi.fn(mutacao),
    definirComunicado: vi.fn(mutacao),
    excluir: vi.fn(mutacao),
    revogar: vi.fn(mutacao),
  } as unknown as ControladorObservacoes;
}

interface OpcoesDeRender {
  readonly itens?: readonly ObservacaoSoberana[];
  readonly timeline?: readonly EventoHistoricoSoberano[];
  readonly historicoAberto?: string | null;
  readonly estadoInicial?: ReturnType<typeof listaPronta> | ReturnType<typeof listaNegada>;
  readonly controlador?: ControladorObservacoes;
  readonly rotulosDeColaborador?: FonteDeRotulosDeColaborador;
  /**
   * Filtro de ciclo do painel (`F5-11 P5`): o padrão do painel restringe à
   * projeção do ciclo, então os casos que exercitam observação de OUTRO ciclo
   * pedem o valor NEUTRO (`"TODOS"`) para que o item não seja filtrado.
   */
  readonly filtroCiclo?: FiltroCicloObservacoesSoberano;
}

function html({
  itens = [],
  timeline,
  historicoAberto = null,
  estadoInicial,
  controlador = controleEspiao(false),
  rotulosDeColaborador = rotulos,
  filtroCiclo = { cycleId: CICLO },
}: OpcoesDeRender): string {
  const timelineInicial =
    timeline === undefined
      ? undefined
      : {
          fase: "pronta" as const,
          observationId: historicoAberto ?? OBS,
          itens: timeline
            .map((evento) =>
              eventoTimelineDeUi(evento, {
                rotuloDoAtor: {
                  doAtor: () => ({ matricula: 99, nome: "Autora Fictícia" }),
                },
              })
            )
            .filter((item) => item !== null),
        };

  return renderToStaticMarkup(
    <ObservacoesColaborador
      colaborador={{ id: ALVO, nome: "Alvo Fictício", matricula: 10 }}
      organizationId={ORG}
      escopo="DIRECT_REPORTS"
      ciclos={[CICLO_SOBERANO]}
      controlador={controlador}
      rotulos={rotulosDeColaborador}
      filtroCiclo={filtroCiclo}
      onFiltroCicloChange={vi.fn()}
      mostrarExcluidas={false}
      onMostrarExcluidasChange={vi.fn()}
      onObservacoesChange={vi.fn()}
      estadoInicial={estadoInicial ?? listaPronta(itens)}
      timelineInicial={timelineInicial}
      historicoAbertoInicial={historicoAberto}
    />
  );
}

/** Apenas o TEXTO visível da marcação (evita casar com atributos/classes). */
function texto(marcacao: string): string {
  return marcacao.replace(/<[^>]*>/g, " ");
}

describe("F5-11 P5 L3 — painel de observações do gestor no contrato soberano", () => {
  it("(i) o FONTE do componente não usa observacaoStorage/localStorage/.rpc(/credencial", () => {
    expect(fonteComponente).not.toMatch(/observacaoStorage/);
    expect(fonteComponente).not.toMatch(/localStorage|sessionStorage/);
    expect(fonteComponente).not.toMatch(/\.rpc\s*\(/);
    expect(fonteComponente).not.toMatch(/SERVICE_ROLE_KEY|serviceRoleKey/);
    // A palavra "supabase" é LEGÍTIMA em caminho de import/tipo; o proibido é o
    // CLIENTE e o acesso direto a tabela (mesma precisão da guarda da página).
    expect(fonteComponente).not.toMatch(/@supabase\/supabase-js|createClient\s*\(/);
    // O gate legado de autorização foi REMOVIDO do componente.
    expect(fonteComponente).not.toMatch(/authorizationPolicy/);
    expect(fonteComponente).not.toMatch(/\bcan\s*\(/);
    expect(fonteComponente).not.toMatch(/\bauthorize\s*\(/);
    expect(fonteComponente).not.toMatch(/usuarioAtual/);
    expect(fonteComponente).not.toMatch(/kind:\s*"observation"/);
    // A fonte é o CONTROLADOR recebido por props.
    // Consumo REAL do controlador: `listarPorEscopo` é ENCADEADO em outra linha
    // (`void controlador\n  .listarPorEscopo(...)`) e as MUTAÇÕES são delegadas
    // ao fluxo soberano, que recebe o controlador no contexto — NÃO existe
    // `controlador.criar`/`.editar`/`.excluir` no componente.
    expect(fonteComponente).toMatch(/controlador\s*\.\s*listarPorEscopo\s*\(/);
    expect(fonteComponente).toMatch(/controlador\s*\.\s*historico\s*\(/);
    expect(fonteComponente).toMatch(/controlador\s*,\s*organizationId/);
    expect(fonteComponente).toMatch(/criarObservacaoSoberana\s*\(/);
    expect(fonteComponente).toMatch(/editarObservacaoSoberana\s*\(/);
    expect(fonteComponente).toMatch(/excluirObservacaoSoberana\s*\(/);
  });

  it("(i-b) a lista vazia é ausência soberana explícita (sem acervo local)", () => {
    const marcação = html({ itens: [] });
    expect(marcação).toContain("Nenhuma observação registrada.");
    expect(marcação).not.toMatch(/feedback-control-observacoes/);
  });

  it("(ii) o erro soberano é exibido com o CÓDIGO PÚBLICO e nenhum dado inventado", () => {
    const marcação = html({ estadoInicial: listaNegada("FORBIDDEN") });
    expect(texto(marcação)).toContain("FORBIDDEN");
    expect(marcação).toContain("Você não tem permissão para esta operação.");
    expect(texto(marcação)).toContain("Observações indisponíveis");
    // Nenhuma lista fabricada a partir da negação.
    expect(marcação).not.toContain("observacao ficticia");
  });

  it("(ii-b) mutação NEGADA é entregue como intenção frustrada: erro público e NENHUM dado novo", async () => {
    const controlador = controleEspiao(true);
    const itens = [soberana(OBS), soberana(OUTRA_OBS)];

    // A negação é decidida no SERVIDOR (controlador). O que o painel recebe é a
    // falha pública: nada de observação nova, nada de lista alterada, nada de
    // decisão local — a lista exibida continua sendo a da LEITURA soberana.
    const resultado = await criarObservacaoSoberana(
      {
        controlador,
        organizationId: ORG,
        collaboratorId: ALVO,
        cycleId: CICLO,
      },
      { tipo: "POSITIVA", texto: "tentativa ficticia negada" }
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) throw new Error("esperado negativa");
    expect(resultado.error.code).toBe("FORBIDDEN");
    expect(resultado.error.mensagem).toBe("Você não tem permissão para esta operação.");
    // A mensagem exibida pelo painel é o par código público + mensagem do
    // controlador (mesma formatação que o componente aplica em `setErro`).
    expect(mensagemDaFalha(resultado.error)).toBe(
      "FORBIDDEN: Você não tem permissão para esta operação."
    );

    const visivel = texto(html({ itens }));
    expect(visivel).toContain(`observacao ficticia ${OBS}`);
    expect(visivel).not.toContain("tentativa ficticia negada");
  });

  it("(iii) a timeline é renderizada a partir dos itens SOBERANOS da trilha", () => {
    const marcação = html({
      itens: [soberana(OBS)],
      timeline: [EVENTO],
      historicoAberto: OBS,
    });

    const visivel = texto(marcação);
    expect(visivel).toContain("Edição");
    expect(visivel).toContain("Motivo: Edicao da definicao da observacao");
    expect(visivel).toContain("Texto anterior: texto anterior ficticio");
    expect(visivel).toContain("Autora Fictícia");
    // O rótulo do evento vem do `event_type` REAL — nada de "CRIACAO" legado.
    expect(visivel).not.toContain("CRIACAO");
  });

  it("(iii-b) trilha vazia é ausência EXPLÍCITA de evento, não timeline inventada", () => {
    const marcação = html({
      itens: [soberana(OBS)],
      timeline: [],
      historicoAberto: OBS,
    });
    expect(texto(marcação)).toContain("Nenhum evento registrado na trilha.");
  });

  it("(iv) observação sem rótulo do ALVO não é exibida e a omissão é informada", () => {
    const semRotulo = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const visivel = texto(
      html({
        itens: [soberana(OBS), soberana(semRotulo, { collaboratorId: semRotulo })],
      })
    );

    expect(visivel).toContain(`observacao ficticia ${OBS}`);
    expect(visivel).not.toContain(`observacao ficticia ${semRotulo}`);
    expect(visivel).toContain("sem rótulo de colaborador na tela");
  });

  it("autor sem rótulo na tela não é substituído por sentinela", () => {
    const marcação = html({ itens: [soberana(OBS, { autorCollaboratorId: null })] });
    expect(marcação).toContain(`observacao ficticia ${OBS}`);
    expect(marcação).not.toContain("Registrada por");
    expect(texto(marcação)).not.toContain("desconhecido");
  });

  it("o KPI por tipo decorre da projeção soberana (sem ano/ciclo)", () => {
    const visivel = texto(
      html({
        itens: [
          soberana(OBS, { tipo: "POSITIVA" }),
          soberana(OUTRA_OBS, { tipo: "NEGATIVA" }),
        ],
      })
    );
    expect(visivel).toContain("Positivas: 1");
    expect(visivel).toContain("Neutras: 0");
    expect(visivel).toContain("Negativas: 1");
  });

  it("a observação é rotulada pelo ciclo SOBERANO da projeção (ano/numero do ciclo)", () => {
    expect(texto(html({ itens: [soberana(OBS)] }))).toContain("2027 • Ciclo 1");
  });

  it("ciclo ausente da projeção recebe rótulo explícito em vez de número inventado", () => {
    const outroCiclo = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    expect(
      texto(
        html({
          itens: [soberana(OBS, { cycleId: outroCiclo })],
          filtroCiclo: "TODOS",
        })
      )
    ).toContain("Ciclo não disponível");
  });
});

/**
 * O painel aceita sementes determinísticas e NÃO dispara leitura quando semeado:
 * a prova abaixo é a garantia de que o SSR depende (efeito inerte, nenhuma
 * chamada ao controlador) sem tocar em `document`.
 */
describe("F5-11 P5 L3 — semente determinística não dispara leitura", () => {
  it("`estadoInicial`/`timelineInicial` desligam os efeitos de leitura soberana", async () => {
    const controlador = controleEspiao(false);
    await act(async () => {
      renderToStaticMarkup(
        <ObservacoesColaborador
          colaborador={{ id: ALVO, nome: "Alvo Fictício", matricula: 10 }}
          organizationId={ORG}
          escopo="DIRECT_REPORTS"
          ciclos={[CICLO_SOBERANO]}
          controlador={controlador}
          rotulos={rotulos}
          filtroCiclo={{ cycleId: CICLO }}
          onFiltroCicloChange={vi.fn()}
          mostrarExcluidas={false}
          onMostrarExcluidasChange={vi.fn()}
          onObservacoesChange={vi.fn()}
          estadoInicial={listaPronta([soberana(OBS)])}
          timelineInicial={null}
        />
      );
    });

    expect(controlador.listarPorEscopo).not.toHaveBeenCalled();
    expect(controlador.historico).not.toHaveBeenCalled();
  });
});
