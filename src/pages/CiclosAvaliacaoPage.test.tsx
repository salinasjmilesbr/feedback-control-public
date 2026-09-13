import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { ProvedorAuthTeste } from "../test/authTeste";
import type { Colaborador } from "../types/Colaborador";
import type { EstadoGestaoCiclos } from "../services/ciclosSoberanos/controladorGestaoCiclos";
import CiclosAvaliacaoPage from "./CiclosAvaliacaoPage";

/**
 * F5-09 P8 (Bloco 1) — `CiclosAvaliacaoPage` com LEITURA SOBERANA.
 *
 * O harness segue em SSR (`renderToStaticMarkup`, sem jsdom): ele prova o que o
 * SSR prova legitimamente — estado inicial de LOADING, erro fail-closed, acesso
 * restrito e as guardas estáticas de ligação ao controlador soberano. O
 * comportamento que exige efeitos/DOM (reload pós-mutation, stale de organização,
 * ações por status) é coberto pelos testes node do controlador
 * (`controladorGestaoCiclos.test.ts`), sem enfraquecer a produção.
 */

const gerente: Colaborador = {
  matricula: 1,
  status: "ATIVO",
  nome: "Gerente Fictício",
  email: "gerente@example.com",
  cargo: "Gerente",
  area: "Área fictícia",
  funcao: "GERENTE",
  respondePara: "",
};

/** Controlador falso: apenas `estado()` é observável no SSR. */
function controladorFalso(estado: Partial<EstadoGestaoCiclos>) {
  return {
    estado: () => ({
      fase: "ocioso",
      organizacaoId: null,
      ciclos: [],
      erro: null,
      operacaoEmAndamento: false,
      ...estado,
    }),
    versaoDe: () => Number.NaN,
    registrarVersao: () => undefined,
    carregar: async () => ({ ok: true as const, data: [] }),
    criar: async () => ({ ok: true as const, data: null }),
    editar: async () => ({ ok: true as const, data: null }),
    ativar: async () => ({ ok: true as const, data: null }),
    encerrar: async () => ({ ok: true as const, data: null }),
    cancelar: async () => ({ ok: true as const, data: null }),
    reabrir: async () => ({ ok: true as const, data: null }),
    corrigirPeriodo: async () => ({ ok: true as const, data: null }),
    descartar: () => undefined,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any;
}

function renderizar(
  estado: Partial<EstadoGestaoCiclos> = {},
  usuario: Colaborador | undefined = gerente
): string {
  instalarLocalStorageEmMemoria();
  // O gate de UX (`can`) resolve o mundo funcional dos dados — sem fixture não
  // há decisão de UX e a página cai no estado de acesso restrito.
  localStorage.setItem(
    "feedback-control-colaboradores",
    JSON.stringify(usuario ? [gerente, usuario] : [gerente])
  );
  return renderToStaticMarkup(
    <ProvedorAuthTeste>
      <UsuarioAtualContext.Provider
        value={{
          usuarioAtual: usuario,
          usuariosDisponiveis: usuario ? [usuario] : [],
          selecionarUsuario: () => undefined,
        }}
      >
        <MemoryRouter>
          <CiclosAvaliacaoPage controlador={controladorFalso(estado)} />
        </MemoryRouter>
      </UsuarioAtualContext.Provider>
    </ProvedorAuthTeste>
  );
}

describe("F5-09 P8 Bloco 1 — CiclosAvaliacaoPage: leitura soberana (B1–B6)", () => {
  it("B3/AI: o estado inicial (ocioso/carregando) apresenta carregamento soberano", () => {
    expect(renderizar({ fase: "ocioso" })).toContain("Carregando ciclos");
    expect(renderizar({ fase: "carregando" })).toContain("Carregando ciclos");
  });

  it("B4/AJ: erro de leitura soberana é exibido e NÃO cai para dado local", () => {
    instalarLocalStorageEmMemoria();
    // Dado local preexistente: não pode ser usado como fallback.
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([
        {
          id: "ciclo-local-legado",
          ano: 1999,
          ciclo: 3,
          status: "ATIVO",
          dataCriacao: "1999-01-01T00:00:00.000Z",
          dataUltimaAtualizacao: "1999-01-01T00:00:00.000Z",
        },
      ])
    );

    const html = renderizar({
      fase: "erro",
      erro: { code: "INTERNAL", message: "Não foi possível consultar os ciclos agora." },
    });

    expect(html).toContain("Não foi possível consultar os ciclos agora.");
    expect(html).not.toContain("ciclo-local-legado");
    expect(html).not.toContain("1999");
  });

  it("a página não exibe a lista a partir de dado local (nenhum ciclo local visível)", () => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([
        {
          id: "ciclo-local-legado",
          ano: 1999,
          ciclo: 3,
          status: "ATIVO",
          dataCriacao: "1999-01-01T00:00:00.000Z",
          dataUltimaAtualizacao: "1999-01-01T00:00:00.000Z",
        },
      ])
    );

    const html = renderizar({ fase: "pronto", ciclos: [] });

    expect(html).toContain("Nenhum ciclo cadastrado");
    expect(html).not.toContain("ciclo-local-legado");
    expect(html).not.toContain("1999");
  });
});

describe("F5-09 P8 Bloco 1 — guardas estáticas da PÁGINA (B1/B2/B6)", () => {
  /** Código sem comentários (os comentários documentam o que a página NÃO faz). */
  function codigoSemComentarios(codigo: string): string {
    return codigo
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .split("\n")
      .map((linha) => {
        const indice = linha.indexOf("//");
        return indice === -1 ? linha : linha.slice(0, indice);
      })
      .join("\n");
  }

  it("B1: a página está ligada ao controlador soberano", async () => {
    const fonte = (
      await import("./CiclosAvaliacaoPage.tsx?raw")
    ).default as string;
    expect(fonte).toContain("criarControladorGestaoCiclos");
    expect(fonte).toContain("controlador.carregar(organizacaoAtivaId");
    expect(fonte).toContain("useState(controlador.estado())");
  });

  it("B2/B6: a LISTA não vem de leitura local (nem localStorage direto)", async () => {
    const fonte = codigoSemComentarios(
      (await import("./CiclosAvaliacaoPage.tsx?raw")).default as string
    );
    expect(fonte).toContain("const ciclos = estado.ciclos;");
    expect(fonte).not.toContain("getCiclosAdministrativos");
    expect(fonte).not.toContain("localStorage");
    expect(fonte).not.toContain("localCycleRepository");
    // Enquanto as mutations do Bloco 2 não migram, `getCiclosAvaliacao` pode
    // permanecer para elas — mas NUNCA como fonte da lista exibida.
    expect(fonte).not.toMatch(/const ciclos = getCiclosAvaliacao/);
  });
});

describe("F5-09 P8 Bloco 2 — mutations soberanas (C1–C15)", () => {
  /** Código sem comentários (os comentários citam, por texto, o que foi REMOVIDO). */
  function codigoSemComentarios(codigo: string): string {
    return codigo
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .split("\n")
      .map((linha) => {
        const indice = linha.indexOf("//");
        return indice === -1 ? linha : linha.slice(0, indice);
      })
      .join("\n");
  }

  async function fonteDaPagina(): Promise<string> {
    return codigoSemComentarios(
      (await import("./CiclosAvaliacaoPage.tsx?raw")).default as string
    );
  }

  /** Trecho da chamada `controlador.<metodo>(…)` (para provar o payload). */
  function trechoDaChamada(fonte: string, marcador: string): string {
    const inicio = fonte.indexOf(marcador);
    expect(inicio, marcador).toBeGreaterThan(-1);
    return fonte.slice(inicio, inicio + 320);
  }

  it("C1/C2/C3: criação vai pelo controlador, sem UUID de ciclo, sem metas e sem ativarAgora", async () => {
    const fonte = await fonteDaPagina();
    const trecho = trechoDaChamada(fonte, "controlador.criar({");

    expect(trecho).toContain("ano,");
    expect(trecho).toContain("numero: ciclo,");
    expect(trecho).toContain("dataInicio,");
    expect(trecho).toContain("dataFim,");
    // Nada de identidade no cliente, metas ou ativação implícita.
    expect(trecho).not.toContain("cycleId");
    expect(trecho).not.toContain("quantidadeMetas");
    expect(trecho).not.toContain("ativarAgora");
  });

  it("C4: edição de PLANEJADO usa controlador.editar com o UUID soberano", async () => {
    const fonte = await fonteDaPagina();
    const trecho = trechoDaChamada(fonte, "controlador.editar({");
    expect(trecho).toContain("cicloId: item.id");
    expect(trecho).toContain("dataInicio: periodoInicioEdicao");
    expect(trecho).toContain("dataFim: periodoFimEdicao");
  });

  it("C5/C6: ativação e encerramento usam o controlador (com motivo soberano)", async () => {
    const fonte = await fonteDaPagina();
    expect(fonte).toContain("controlador.ativar(item.id)");
    expect(trechoDaChamada(fonte, "controlador.encerrar(")).toContain(
      "motivo.trim()"
    );
  });

  it("C7/C8: cancelamento (PLANEJADO e ATIVO) usa controlador.cancelar com motivo", async () => {
    const fonte = await fonteDaPagina();
    const trecho = trechoDaChamada(fonte, "controlador.cancelar(");
    expect(trecho).toContain("item.id");
    expect(trecho).toContain("motivo.trim()");
    // O status NÃO é enviado: quem decide o estado permitido é a RPC soberana.
    expect(trecho).not.toContain("status");
  });

  it("C9: reabertura usa controlador.reabrir (ENCERRADO conforme contrato)", async () => {
    const fonte = await fonteDaPagina();
    const trecho = trechoDaChamada(fonte, "controlador.reabrir(");
    expect(trecho).toContain("item.id");
    expect(trecho).toContain("motivo.trim()");
  });

  it("C10: correção de período usa controlador.corrigirPeriodo com justificativa", async () => {
    const fonte = await fonteDaPagina();
    const trecho = trechoDaChamada(fonte, "controlador.corrigirPeriodo({");
    expect(trecho).toContain("cicloId: item.id");
    expect(trecho).toContain("justificativa: justificativaCorrecao.trim()");
    // Impacto NÃO é calculado localmente.
    expect(trecho).not.toContain("analisarImpacto");
  });

  it("C11/C15: NENHUMA mutation local de lifecycle permanece e o cicloEquipeService saiu do lifecycle", async () => {
    const fonte = await fonteDaPagina();
    for (const local of [
      "criarCiclo(",
      "atualizarPeriodoCiclo(",
      "atualizarStatusCiclo(",
      "encerrarCiclo(",
      "cancelarCiclo(",
      "reabrirCiclo(",
      "corrigirPeriodoCicloAtivo(",
      "criarAvaliacoesDoCicloAtivado(",
      "concluirAvaliacoesNoEncerramentoDoCiclo(",
      "analisarPendenciasDoCiclo(",
    ]) {
      expect(fonte, local).not.toContain(local);
    }
    // Bloco 3: o resíduo da exclusão física saiu — `cicloEquipeService` não é
    // mais importado pela página (nem para apagar avaliações vazias).
    expect(fonte).not.toContain("cicloEquipeService");
    expect(fonte).not.toContain("excluirAvaliacoesVaziasDoCiclo(");
    expect(fonte).not.toContain("criarAvaliacoesDoCicloAtivado");
  });

  it("C12: a página não chama RPC diretamente", async () => {
    const fonte = await fonteDaPagina();
    expect(fonte).not.toContain(".rpc(");
    expect(fonte).not.toContain("functions.invoke");
  });

  it("C13/C14: a página publica o estado APÓS a Promise soberana e preserva o anterior em falha", async () => {
    const fonte = await fonteDaPagina();
    const trecho = trechoDaChamada(fonte, "async function publicar(");
    // Publica o estado do controlador (o controlador já fez reload no sucesso e
    // preservou o último estado válido na falha — provado em AC/AD do controlador).
    expect(trecho).toContain("setEstado(controlador.estado())");
    expect(trecho).toContain("if (resultado.ok)");
    // Nenhum rollback/gravação local.
    expect(trecho).not.toContain("localStorage");
    expect(fonte).toContain("await publicar(");
  });
  it("C16 (Bloco 3): guarda estática de ausência — nenhuma autoridade local de ciclo", async () => {
    const fonte = await fonteDaPagina();
    for (const proibido of [
      // leitura/listagem legada
      "getCiclosAdministrativos",
      "getCiclosAvaliacao",
      "localCycleRepository",
      "cicloAvaliacaoStorage.excluirCiclo",
      // mutations locais de lifecycle
      "criarCiclo(",
      "encerrarCiclo(",
      "excluirCiclo(",
      "atualizarPeriodoCiclo(",
      "atualizarStatusCiclo(",
      "atualizarConfiguracaoMetasCiclo",
      "cancelarCiclo(",
      "reabrirCiclo(",
      "corrigirPeriodoCicloAtivo(",
      "criarAvaliacoesDoCicloAtivado(",
      "concluirAvaliacoesNoEncerramentoDoCiclo(",
      // exclusão física e utilitários extintos
      "excluirAvaliacoesVaziasDoCiclo",
      "confirmarExclusaoCiclo",
      "cicloEquipeService",
      // metas (F5-10) e ativação implícita
      "ativarAgora",
      "quantidadeMetasNegocio",
      "quantidadeMetasIndividuais",
      "editandoMetasId",
      // histórico local / contador artificial de rerender
      "EventoHistoricoCiclo",
      "getEventosHistoricoCiclo",
      "formatarDataHoraHistorico",
      "setVersao",
      // persistência local e acesso direto ao banco
      "localStorage",
      "sessionStorage",
      ".rpc(",
      "functions.invoke",
    ]) {
      expect(fonte, proibido).not.toContain(proibido);
    }
  });

  it("C17 (Bloco 3): o que saiu é declarado INDISPONÍVEL, nunca simulado ou esvaziado", async () => {
    const fonte = await fonteDaPagina();
    expect(fonte).toContain(
      "Configuração de metas será disponibilizada na etapa F5-10"
    );
    expect(fonte).toContain(
      "Histórico detalhado indisponível nesta fase da migração"
    );
    expect(fonte).toContain("a ativação é uma operação separada");
    expect(fonte).toContain("Exclusão física indisponível nesta fase");
    // A trilha não é apresentada como lista vazia "real".
    expect(fonte).not.toContain("Nenhuma alteração auditada registrada");
  });
});
