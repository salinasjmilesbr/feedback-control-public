import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { ProvedorAuthTeste } from "../test/authTeste";
import type { Colaborador } from "../types/Colaborador";
import type { EstadoGestaoCiclos } from "../services/ciclosSoberanos/controladorGestaoCiclos";
import CiclosAvaliacaoPage from "./CiclosAvaliacaoPage";
import { confirmarExclusaoCiclo } from "./confirmarExclusaoCiclo";

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

describe("F5-09 P8 — confirmação de exclusão (utilitário de UX, sem autoridade)", () => {
  it("exige confirmação explícita antes da exclusão", () => {
    const ciclo = {
      id: "ciclo-confirmacao",
      ano: 2026,
      ciclo: 2 as const,
      status: "PLANEJADO" as const,
      dataCriacao: "2026-01-01T00:00:00.000Z",
      dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
    };
    let mensagem = "";

    const confirmado = confirmarExclusaoCiclo(ciclo, (texto) => {
      mensagem = texto;
      return false;
    });

    expect(confirmado).toBe(false);
    expect(mensagem).toContain("Excluir 2026 • Ciclo 2?");
  });
});
