import { describe, expect, it } from "vitest";
import {
  decidirConclusaoDoPrimeiroAcesso,
  decidirEntradaDoPrimeiroAcesso,
  linhasAfetadasDoRetorno,
  pendenciaConfirmada,
} from "./core";

/**
 * F6-A20 (Issue #321) — decisões puras da conclusão do primeiro acesso.
 *
 * Cobre os dois casos exigidos pela auditoria do SHA d538862:
 * 1. falha DEPOIS da alteração da senha (o segundo passo não concluiu) ⇒ a
 *    fronteira NÃO reporta conclusão, a pendência permanece e o retry converge;
 * 2. UPDATE sem linha afetada ⇒ não há prova pela escrita e a conclusão só é
 *    reportada se a LEITURA de verificação comprovar que não há pendência.
 */

const PENDENTE = { first_access_pending: true };
const CONCLUIDO = { first_access_pending: false };

describe("F6-A20 — gate de entrada do primeiro acesso", () => {
  it("aceita somente perfil existente com pendência true", () => {
    expect(decidirEntradaDoPrimeiroAcesso(PENDENTE, null)).toEqual({ ok: true });
  });

  it("fail-closed sem perfil ou com erro de leitura", () => {
    for (const perfil of [null, undefined, [], "perfil", 42]) {
      const decisao = decidirEntradaDoPrimeiroAcesso(perfil, null);
      expect(decisao.ok).toBe(false);
      if (decisao.ok) return;
      expect(decisao.codigo).toBe("NOT_AUTHORIZED");
      expect(decisao.status).toBe(403);
    }
    const comErro = decidirEntradaDoPrimeiroAcesso(PENDENTE, { code: "PGRST301" });
    expect(comErro.ok).toBe(false);
    if (comErro.ok) return;
    expect(comErro.codigo).toBe("NOT_AUTHORIZED");
  });

  it("sem pendência não há o que concluir (fato soberano)", () => {
    const decisao = decidirEntradaDoPrimeiroAcesso(CONCLUIDO, null);
    expect(decisao.ok).toBe(false);
    if (decisao.ok) return;
    expect(decisao.codigo).toBe("ALREADY_COMPLETED");
    expect(decisao.status).toBe(409);
  });
});

describe("F6-A20 — prova de linha alterada", () => {
  it("conta a representação devolvida pelo UPDATE", () => {
    expect(linhasAfetadasDoRetorno([{ id: "uuid-1" }])).toBe(1);
    expect(linhasAfetadasDoRetorno([])).toBe(0);
    expect(linhasAfetadasDoRetorno([{ id: "a" }, { id: "b" }])).toBe(2);
  });

  it("sem representação não há prova (null, nunca 0)", () => {
    for (const retorno of [null, undefined, "ok", 1, { id: "uuid-1" }]) {
      expect(linhasAfetadasDoRetorno(retorno)).toBeNull();
    }
  });

  it("a leitura de verificação só devolve booleano com estado explícito", () => {
    expect(pendenciaConfirmada(CONCLUIDO, null)).toBe(false);
    expect(pendenciaConfirmada(PENDENTE, null)).toBe(true);
    expect(pendenciaConfirmada(PENDENTE, { code: "XX000" })).toBeNull();
    for (const perfil of [null, undefined, [], {}, { first_access_pending: "true" }]) {
      expect(pendenciaConfirmada(perfil, null)).toBeNull();
    }
  });
});

describe("F6-A20 — conclusão exige prova soberana", () => {
  it("só a linha alterada (exatamente 1) prova a conclusão pela escrita", () => {
    const decisao = decidirConclusaoDoPrimeiroAcesso({
      erroDaAtualizacao: null,
      linhasAfetadas: 1,
      estadoConfirmado: null,
    });
    expect(decisao).toEqual({ tipo: "concluido", prova: "linha_afetada" });
  });

  it("FALHA APÓS A SENHA: erro no segundo passo não reporta conclusão", () => {
    const decisao = decidirConclusaoDoPrimeiroAcesso({
      erroDaAtualizacao: { code: "XX000", message: "falha de escrita" },
      linhasAfetadas: null,
      estadoConfirmado: true,
    });
    expect(decisao.tipo).toBe("nao_concluido");
    if (decisao.tipo !== "nao_concluido") return;
    expect(decisao.codigo).toBe("INCOMPLETE");
    expect(decisao.status).toBe(500);

    // A pendência permaneceu: o RETRY é aceito pelo gate e conclui.
    expect(decidirEntradaDoPrimeiroAcesso(PENDENTE, null)).toEqual({ ok: true });
    expect(
      decidirConclusaoDoPrimeiroAcesso({
        erroDaAtualizacao: null,
        linhasAfetadas: 1,
        estadoConfirmado: null,
      })
    ).toEqual({ tipo: "concluido", prova: "linha_afetada" });
  });

  it("FALHA APÓS A SENHA sem prova possível ⇒ INTERNAL (nunca sucesso)", () => {
    const decisao = decidirConclusaoDoPrimeiroAcesso({
      erroDaAtualizacao: { message: "rede" },
      linhasAfetadas: null,
      estadoConfirmado: null,
    });
    expect(decisao.tipo).toBe("nao_concluido");
    if (decisao.tipo !== "nao_concluido") return;
    expect(decisao.codigo).toBe("INTERNAL");
    expect(decisao.status).toBe(500);
  });

  it("UPDATE SEM LINHA AFETADA não prova nada: 0 linhas não é conclusão", () => {
    const semProva = decidirConclusaoDoPrimeiroAcesso({
      erroDaAtualizacao: null,
      linhasAfetadas: 0,
      estadoConfirmado: true,
    });
    expect(semProva.tipo).toBe("nao_concluido");
    if (semProva.tipo !== "nao_concluido") return;
    expect(semProva.codigo).toBe("INCOMPLETE");
    expect(semProva.status).toBe(500);
  });

  it("UPDATE sem representação não prova nada (prova ausente)", () => {
    const decisao = decidirConclusaoDoPrimeiroAcesso({
      erroDaAtualizacao: null,
      linhasAfetadas: null,
      estadoConfirmado: true,
    });
    expect(decisao.tipo).toBe("nao_concluido");
  });

  it("0 linhas com estado verificado concluído ⇒ conclusão provada pela LEITURA", () => {
    const decisao = decidirConclusaoDoPrimeiroAcesso({
      erroDaAtualizacao: null,
      linhasAfetadas: 0,
      estadoConfirmado: false,
    });
    expect(decisao).toEqual({ tipo: "concluido", prova: "estado_verificado" });
  });

  it("0 linhas sem leitura disponível ⇒ INTERNAL (não afirma conclusão)", () => {
    const decisao = decidirConclusaoDoPrimeiroAcesso({
      erroDaAtualizacao: null,
      linhasAfetadas: 0,
      estadoConfirmado: null,
    });
    expect(decisao.tipo).toBe("nao_concluido");
    if (decisao.tipo !== "nao_concluido") return;
    expect(decisao.codigo).toBe("INTERNAL");
  });

  it("mais de uma linha alterada não é prova (defensivo)", () => {
    const decisao = decidirConclusaoDoPrimeiroAcesso({
      erroDaAtualizacao: null,
      linhasAfetadas: 2,
      estadoConfirmado: null,
    });
    expect(decisao.tipo).toBe("nao_concluido");
  });
});
