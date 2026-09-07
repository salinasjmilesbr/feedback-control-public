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

function renderizar(gate: boolean): string {
  return renderToStaticMarkup(
    <UsuarioAtualProvider simulacaoDev={gate}>
      <ContextoAtual />
    </UsuarioAtualProvider>
  );
}

describe("impersonação DEV (F2-09) — provider e helpers", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  describe("DEV explícito", () => {
    it("carrega somente colaboradores ativos sintéticos e preserva a seleção anterior válida", () => {
      semearColaboradores();
      localStorage.setItem(CHAVE_USUARIO_ATUAL_DEV, "1002");

      const html = renderizar(true);

      expect(html).toContain('data-simulacao="ativa"');
      // A fonte do provider é o seed sintético (getColaboradores mescla os
      // gestores iniciais sintéticos ausentes) — a expectativa é derivada dela.
      const esperados = candidatosImpersonacaoDev(true, getColaboradores());
      expect(html).toContain(`data-quantidade="${esperados.length}"`);
      expect(html).toContain("Coordenadora Sintetica Dois");
      expect(html).not.toContain("Desligado Sintetico Tres");
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
