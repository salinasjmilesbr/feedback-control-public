import { describe, expect, it } from "vitest";
import {
  InvalidCredentialsError,
  TechnicalError,
} from "../errors/applicationErrors";
import { classificarErroValidacaoSessao, mapearErroDeLogin, mapearErroTecnico } from "./erros";

describe("mapeamento de erros de autenticação (F2-03)", () => {
  it("converte credencial inválida para erro público seguro da taxonomia F0-05", () => {
    const erro = mapearErroDeLogin({
      code: "invalid_credentials",
      message: "Invalid login credentials",
    });

    expect(erro).toBeInstanceOf(InvalidCredentialsError);
    expect(erro.code).toBe("INVALID_CREDENTIALS");
    expect(erro.publicMessage).toBe("E-mail ou senha inválidos.");
    expect(erro.cause).toBeDefined();
  });

  it("não infere credencial inválida por texto; demais erros viram falha técnica", () => {
    const erro = mapearErroDeLogin({
      code: "over_request_rate_limit",
      message: "Invalid login credentials",
    });

    expect(erro).toBeInstanceOf(TechnicalError);
    expect(erro.code).toBe("TECHNICAL_ERROR");
  });

  it("erros sem código estruturado viram falha técnica", () => {
    expect(mapearErroDeLogin(new Error("detalhe interno fictício"))).toBeInstanceOf(TechnicalError);
    expect(mapearErroDeLogin("texto qualquer")).toBeInstanceOf(TechnicalError);
    expect(mapearErroDeLogin(null)).toBeInstanceOf(TechnicalError);
  });

  it("mapeia erro técnico preservando a causa interna", () => {
    const causa = new Error("causa fictícia");
    const erro = mapearErroTecnico(causa);
    expect(erro).toBeInstanceOf(TechnicalError);
    expect(erro.cause).toBe(causa);
  });
});

describe("classificação de erro de revalidação (F5-01, Q1 aprovada)", () => {
  it("erros 4xx (sessão inválida/ban/removido) são classificados como sessão inválida", () => {
    expect(classificarErroValidacaoSessao({ status: 401 })).toBe("sessaoInvalida");
    expect(classificarErroValidacaoSessao({ status: 403 })).toBe("sessaoInvalida");
  });

  it("AuthSessionMissingError é sessão inválida", () => {
    expect(classificarErroValidacaoSessao({ name: "AuthSessionMissingError" })).toBe(
      "sessaoInvalida"
    );
  });

  it("falha de transporte (sem status) e 5xx são falhas transitórias", () => {
    expect(classificarErroValidacaoSessao(new TypeError("fetch failed"))).toBe(
      "falhaTransitoria"
    );
    expect(classificarErroValidacaoSessao({ status: 500 })).toBe("falhaTransitoria");
    expect(classificarErroValidacaoSessao({ status: 503 })).toBe("falhaTransitoria");
    expect(classificarErroValidacaoSessao({})).toBe("falhaTransitoria");
  });
});
