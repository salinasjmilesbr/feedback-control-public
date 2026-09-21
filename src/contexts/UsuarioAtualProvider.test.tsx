import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it } from "vitest";
import { getColaboradores } from "../services/colaboradorStorage";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { Colaborador } from "../types/Colaborador";
import {
  candidatosImpersonacaoDev,
  CHAVE_USUARIO_ATUAL_DEV,
  resolverMatriculaInicialDev,
  selecionarMatriculaDev,
} from "./impersonacaoDev";
import { useUsuarioAtual } from "./UsuarioAtualContext";
import { UsuarioAtualProvider } from "./UsuarioAtualProvider";
import {
  carregarIdentidadeSoberana,
  colaboradorLegadoDaIdentidade,
  type DependenciasIdentidadeSoberana,
} from "./identidadeSoberana";
import type { ColaboradorSoberano } from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";

const CHAVE_COLABORADORES = "feedback-control-colaboradores";
const CHAVE_SESSAO_SUPABASE = "supabase.auth.token";

/** Apenas dados sintéticos (nunca nomes/e-mails reais da equipe). */
function colaboradorSintetico(parcial: Partial<Colaborador> & Pick<Colaborador, "matricula" | "nome">): Colaborador {
  return {
    status: "ATIVO",
    email: `sintetico.${parcial.matricula}@example.invalid`,
    cargo: "Cargo sintético",
    area: "Área sintética",
    respondePara: "",
    ...parcial,
  };
}

const COLABORADORES_SINTETICOS: Colaborador[] = [
  colaboradorSintetico({
    matricula: 1001,
    nome: "Gerente Sintetico Um",
    funcao: "GERENTE",
  }),
  colaboradorSintetico({
    matricula: 1002,
    nome: "Coordenadora Sintetica Dois",
    funcao: "COORDENADOR",
  }),
  colaboradorSintetico({
    matricula: 1003,
    nome: "Desligado Sintetico Tres",
    funcao: "ANALISTA",
    senioridade: "PLENO",
    status: "DESLIGADO",
  }),
];

function semearColaboradores(): void {
  localStorage.setItem(CHAVE_COLABORADORES, JSON.stringify(COLABORADORES_SINTETICOS));
}

function ContextoAtual() {
  const { usuarioAtual, usuariosDisponiveis, simulacaoDevAtiva } = useUsuarioAtual();
  return (
    <span
      data-simulacao={simulacaoDevAtiva ? "ativa" : "inativa"}
      data-quantidade={usuariosDisponiveis.length}
    >
      {usuarioAtual ? usuarioAtual.nome : "sem-identidade-simulada"}
    </span>
  );
}

function renderizar(gate: boolean, organizacaoAtivaId?: string | null): string {
  return renderToStaticMarkup(
    <UsuarioAtualProvider
      simulacaoDev={gate}
      organizacaoAtivaId={organizacaoAtivaId}
    >
      <ContextoAtual />
    </UsuarioAtualProvider>
  );
}

const VINCULO_FICTICIO = "11111111-1111-4111-8111-111111111111";
const OUTRO_COLLABORATOR = "22222222-2222-4222-8222-222222222222";

function estruturaPessoalDe(
  colaboradores: readonly { readonly collaboratorId: string; readonly nome: string }[]
): EstruturaSoberana {
  return {
    unidades: [],
    periodosParent: [],
    posicoes: [],
    reportingLines: [],
    ocupacoes: [],
    cargos: [],
    senioridades: [],
    colegiados: [],
    colaboradores,
  };
}

function colaboradorSoberanoDe(
  collaboratorId: string,
  matricula: string | null
): ColaboradorSoberano {
  return {
    collaboratorId,
    matricula,
    fullName: "Pessoa Fictícia",
    email: "pessoa.ficticia@example.invalid",
    status: "active",
    admissionDate: null,
    unitId: null,
    unitName: null,
    jobRoleCode: null,
    jobRoleName: null,
    seniorityName: null,
    managerCollaboratorId: null,
    managerFullName: null,
    version: 1,
  };
}

function dependencias(
  over: Partial<DependenciasIdentidadeSoberana> = {}
): DependenciasIdentidadeSoberana {
  return {
    lerAutorizacao: async () => ({
      podeEstrutura: false,
      podeCatalogo: false,
      collaboratorId: VINCULO_FICTICIO,
    }),
    lerEstruturaPessoal: async () => ({
      ok: true,
      dados: estruturaPessoalDe([
        { collaboratorId: VINCULO_FICTICIO, nome: "Carolina Fictícia" },
      ]),
    }),
    listarColaboradores: async () => ({
      ok: false,
      codigo: "FORBIDDEN",
      mensagem: "sem permissão",
    }),
    ...over,
  };
}

describe("#333 — identidade pessoal pelo VÍNCULO soberano (sem matrícula/e-mail)", () => {
  it("vinculado SEM ocupação/hierarquia => identidade definida e sem matrícula", async () => {
    const identidade = await carregarIdentidadeSoberana("org-1", dependencias());

    expect(identidade?.collaboratorId).toBe(VINCULO_FICTICIO);
    expect(identidade?.nome).toBe("Carolina Fictícia");
    expect(identidade?.matricula).toBeUndefined();
    // Sem matrícula não há projeção legada — e nenhum número é inventado.
    expect(colaboradorLegadoDaIdentidade(identidade!)).toBeUndefined();
  });

  it("universo NEGADO (collaborator.listar FORBIDDEN) => identidade preservada", async () => {
    const identidade = await carregarIdentidadeSoberana("org-1", dependencias());

    expect(identidade).toBeDefined();
    expect(identidade?.collaboratorId).toBe(VINCULO_FICTICIO);
    expect(identidade?.nome).toBe("Carolina Fictícia");
  });

  it("universo disponível => matrícula é COMPLEMENTO da apresentação, não requisito", async () => {
    const identidade = await carregarIdentidadeSoberana(
      "org-1",
      dependencias({
        listarColaboradores: async () => ({
          ok: true,
          dados: [colaboradorSoberanoDe(VINCULO_FICTICIO, "4242")],
        }),
      })
    );

    expect(identidade?.matricula).toBe(4242);
    expect(colaboradorLegadoDaIdentidade(identidade!)?.matricula).toBe(4242);
  });

  it("collaborator_id AUSENTE => fail-closed sem sequer ler a estrutura pessoal", async () => {
    let leuPessoal = false;

    const identidade = await carregarIdentidadeSoberana(
      "org-1",
      dependencias({
        lerAutorizacao: async () => ({
          podeEstrutura: false,
          podeCatalogo: false,
          collaboratorId: null,
        }),
        lerEstruturaPessoal: async () => {
          leuPessoal = true;
          return { ok: true, dados: estruturaPessoalDe([]) };
        },
      })
    );

    expect(identidade).toBeUndefined();
    expect(leuPessoal).toBe(false);
  });

  it("estrutura pessoal NEGADA => fail-closed", async () => {
    const identidade = await carregarIdentidadeSoberana(
      "org-1",
      dependencias({
        lerEstruturaPessoal: async () => ({
          ok: false,
          codigo: "FORBIDDEN",
          mensagem: "sem permissão",
        }),
      })
    );

    expect(identidade).toBeUndefined();
  });

  it("cross-tenant NÃO amplia identidade: linha de terceiro nunca vira identidade", async () => {
    const identidade = await carregarIdentidadeSoberana(
      "org-1",
      dependencias({
        lerEstruturaPessoal: async () => ({
          ok: true,
          dados: estruturaPessoalDe([
            { collaboratorId: OUTRO_COLLABORATOR, nome: "Terceiro Fictício" },
          ]),
        }),
        listarColaboradores: async () => ({
          ok: true,
          dados: [colaboradorSoberanoDe(OUTRO_COLLABORATOR, "9999")],
        }),
      })
    );

    expect(identidade).toBeUndefined();
  });
});

describe("impersonação DEV (F2-09) — provider e helpers", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  describe("DEV explícito", () => {
    it("carrega somente colaboradores ativos sintéticos e preserva a seleção anterior válida", () => {
      semearColaboradores();
      localStorage.setItem(CHAVE_USUARIO_ATUAL_DEV, "1002");
      const cadastroAntes = localStorage.getItem(CHAVE_COLABORADORES);

      const html = renderizar(true);

      expect(html).toContain('data-simulacao="ativa"');
      // F5-07 (I7): a fonte do provider é EXATAMENTE o cadastro local — sem
      // migração e sem gestores sintéticos injetados na leitura.
      const esperados = candidatosImpersonacaoDev(true, getColaboradores());
      expect(esperados.map((colaborador) => colaborador.matricula)).toEqual([
        1001, 1002,
      ]);
      expect(html).toContain(`data-quantidade="${esperados.length}"`);
      expect(html).toContain("Coordenadora Sintetica Dois");
      expect(html).not.toContain("Desligado Sintetico Tres");
      // A leitura do provider não regrava a base.
      expect(localStorage.getItem(CHAVE_COLABORADORES)).toBe(cadastroAntes);
    });

    it("sem seleção anterior usa o primeiro perfil GERENTE ativo como padrão", () => {
      semearColaboradores();

      const html = renderizar(true);

      const esperados = candidatosImpersonacaoDev(true, getColaboradores());
      const gerentePadrao = esperados.find((usuario) => usuario.funcao === "GERENTE");

      expect(html).toContain('data-simulacao="ativa"');
      expect(gerentePadrao?.nome).toBeTruthy();
      expect(html).toContain(gerentePadrao!.nome);
    });

    it("troca permitida devolve a matrícula escolhida (mecanismo útil de impersonação)", () => {
      semearColaboradores();
      expect(selecionarMatriculaDev(true, 1002)).toBe(1002);
    });

    it("a impersonação DEV não toca a sessão/chaves do Supabase Auth", () => {
      semearColaboradores();
      localStorage.setItem(CHAVE_SESSAO_SUPABASE, "jwt.sintetico.inalteravel");

      renderizar(true);

      // O provider DEV apenas lê o seed e o marcador local; nada escreve em
      // chaves do Supabase Auth nem altera a sessão real.
      expect(localStorage.getItem(CHAVE_SESSAO_SUPABASE)).toBe("jwt.sintetico.inalteravel");
      expect(localStorage.getItem(CHAVE_USUARIO_ATUAL_DEV)).toBeNull();
    });
  });

  describe("HOMOLOG/PROD (fail-closed)", () => {
    it("não usa a fixture DEV quando há tenant autenticado ativo", () => {
      semearColaboradores();

      const html = renderizar(true, "org-teste-1");

      expect(html).toContain('data-simulacao="inativa"');
      expect(html).toContain('data-quantidade="0"');
      expect(html).toContain("sem-identidade-simulada");
      expect(html).not.toContain("Gerente Sintetico Um");
    });

    it("não carrega identidade simulada mesmo com seed e seleção antiga presentes", () => {
      semearColaboradores();
      localStorage.setItem(CHAVE_USUARIO_ATUAL_DEV, "1002");

      const html = renderizar(false);

      expect(html).toContain('data-simulacao="inativa"');
      expect(html).toContain('data-quantidade="0"');
      expect(html).toContain("sem-identidade-simulada");
      expect(html).not.toContain("Gerente Sintetico Um");
      expect(html).not.toContain("Coordenadora Sintetica Dois");
    });

    it("bloqueia a troca local de identidade e não persiste marcador", () => {
      semearColaboradores();
      localStorage.setItem(CHAVE_USUARIO_ATUAL_DEV, "1001");

      expect(selecionarMatriculaDev(false, 1002)).toBeUndefined();

      // O provider fora de DEV não chega a ler/gravar o marcador como identidade.
      const html = renderizar(false);
      expect(html).toContain("sem-identidade-simulada");
      expect(localStorage.getItem(CHAVE_USUARIO_ATUAL_DEV)).toBe("1001");
    });
  });

  describe("helpers puros", () => {
    it("candidatos DEV filtram ativos e ordenam GERENTE antes de COORDENADOR", () => {
      const ordenados = candidatosImpersonacaoDev(true, COLABORADORES_SINTETICOS);
      expect(ordenados.map((c) => c.matricula)).toEqual([1001, 1002]);
      // Fora de DEV a lista de candidatos é sempre vazia.
      expect(candidatosImpersonacaoDev(false, COLABORADORES_SINTETICOS)).toEqual([]);
    });

    it("resolver matrícula inicial preserva a salva válida, senão cai para o GERENTE", () => {
      const candidatos = candidatosImpersonacaoDev(true, COLABORADORES_SINTETICOS);
      expect(resolverMatriculaInicialDev(1002, candidatos)).toBe(1002);
      expect(resolverMatriculaInicialDev(9999, candidatos)).toBe(1001);
      expect(resolverMatriculaInicialDev(undefined, candidatos)).toBe(1001);
      expect(resolverMatriculaInicialDev(undefined, [])).toBeUndefined();
    });

    it("usa somente dados sintéticos do seed DEV", () => {
      const candidatos = candidatosImpersonacaoDev(true, COLABORADORES_SINTETICOS);
      for (const colaborador of candidatos) {
        expect(colaborador.email).toMatch(/@example\.invalid$/);
      }
    });
  });
});
