import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import {
  ConfirmacaoOrganizacao,
  FormularioNovaOrganizacao,
  NegativaNeutra,
  ServicoIndisponivel,
} from "./NovaOrganizacaoPlataformaPage";
import NovaOrganizacaoPlataformaPage from "./NovaOrganizacaoPlataformaPage";
import {
  montarEntradaProvisao,
  type FormaPrimeiroAdmin,
} from "../../services/plataforma/formularioPlataforma";
import type { ProvisionamentoPlataforma } from "../../application/ports/ProvisionamentoPlataforma";

/**
 * F6-A03 (Issue #266) — UI mínima de plataforma (§6.5).
 *
 * Prova a RENDERIZAÇÃO: nada de conteúdo antes de o guard resolver, formulário
 * com os DOIS campos de conteúdo e nenhuma escolha de role/tenant/usuário,
 * negativa neutra, indisponibilidade explícita e confirmação SEM identificador
 * interno. Prova também a conversão PURA do formulário em intenção
 * (`montarEntradaProvisao`), com fail-closed para entrada incompleta.
 *
 * F6-A11 (Issue #273): o formulário ganhou a identidade FUNCIONAL mínima do
 * primeiro Admin (nome humano + matrícula, D23/D26/D28) — dois campos
 * `required`, depois do bloco de identificação e antes da mensagem de erro.
 */

const OPERACAO_ID = "f6a3b000-0000-4000-8000-000000000001";
const OPERADOR = "f6a30000-0000-4000-8000-000000000003";
/** Dados FICTÍCIOS da identidade funcional mínima do primeiro Admin (F6-A11). */
const NOME_ADMIN = "Admin Teste A11";
const MATRICULA_ADMIN = "A1100001";

function semearFormulario(
  forma: FormaPrimeiroAdmin = "eu",
  enviando = false,
  mensagem = ""
): string {
  return renderToStaticMarkup(
    <MemoryRouter>
      <FormularioNovaOrganizacao
        nome=""
        forma={forma}
        email=""
        nomeAdmin={NOME_ADMIN}
        matriculaAdmin={MATRICULA_ADMIN}
        mensagem={mensagem}
        enviando={enviando}
        aoMudarNome={() => {}}
        aoMudarForma={() => {}}
        aoMudarEmail={() => {}}
        aoMudarNomeAdmin={() => {}}
        aoMudarMatriculaAdmin={() => {}}
        aoEnviar={() => {}}
      />
    </MemoryRouter>
  );
}

describe("F6-A03 — UI: nada de conteúdo antes do guard", () => {
  it("o primeiro render é o carregamento do guard (sem formulário)", () => {
    // Self-check que nunca resolve: o render inicial NÃO pode antecipar conteúdo.
    const portaLenta: ProvisionamentoPlataforma = {
      provisionarOrganizacao: async () => ({ organizationId: "o-1" }),
      souOperadorDaPlataforma: () => new Promise<boolean>(() => {}),
      identidadeDoOperadorAutenticado: async () => null,
    };

    const html = renderToStaticMarkup(
      <MemoryRouter>
        <NovaOrganizacaoPlataformaPage provisionamento={portaLenta} />
      </MemoryRouter>
    );

    expect(html).toContain("Verificando autorização…");
    expect(html).toContain('role="status"');
    expect(html).not.toContain("<form");
    expect(html).not.toContain("<input");
    expect(html).not.toContain("Criar organização</button>");
  });

  it("sem caminho soberano no ambiente o resultado é INDISPONIBILIDADE explícita", () => {
    const html = renderToStaticMarkup(
      <MemoryRouter>
        <NovaOrganizacaoPlataformaPage provisionamento={null} />
      </MemoryRouter>
    );

    expect(html).toContain("Serviço indisponível");
    expect(html).not.toContain("<form");
    expect(html).not.toContain("<input");
  });
});

describe("F6-A03 — UI: formulário mínimo (critério 23)", () => {
  it("expõe o nome da organização e a escolha do primeiro Admin", () => {
    const html = semearFormulario("eu");

    expect(html).toContain("Nome da empresa");
    expect(html).toContain("Administrador inicial");
    expect(html).toContain("Eu mesmo");
    expect(html).toContain("Outra pessoa (e-mail)");
    // SEM o campo de e-mail enquanto a escolha é "eu mesmo".
    expect(html).not.toContain("E-mail do administrador inicial");
    // Três controles de entrada: nome da organização + os DOIS campos novos do
    // primeiro Admin (nome humano e matrícula — F6-A11/D28).
    expect((html.match(/<input/g) ?? []).length).toBe(3);
    expect((html.match(/<select/g) ?? []).length).toBe(1);
  });

  it("mostra o campo de e-mail quando o primeiro Admin é outra pessoa", () => {
    const html = semearFormulario("outra");
    expect(html).toContain("E-mail do administrador inicial");
    // Nome da organização + e-mail + nome humano + matrícula do primeiro Admin.
    expect((html.match(/<input/g) ?? []).length).toBe(4);
  });

  it("renderiza os DOIS campos novos do primeiro Admin, obrigatórios e na ordem contratada", () => {
    const html = semearFormulario("eu", false, "Verifique os dados informados e tente novamente.");

    expect(html).toContain("Nome do administrador inicial");
    expect(html).toContain("Matrícula do administrador inicial");
    // Os dois campos são `required`: o formulário continua fail-closed.
    expect(html).toMatch(/<span>Nome do administrador inicial<\/span><input[^>]*required/);
    expect(html).toMatch(/<span>Matrícula do administrador inicial<\/span><input[^>]*required/);

    // Ordem contratada: DEPOIS do bloco de identificação e ANTES do erro.
    const identificacao = html.indexOf("<span>Administrador inicial</span>");
    const nomeAdmin = html.indexOf("Nome do administrador inicial");
    const matriculaAdmin = html.indexOf("Matrícula do administrador inicial");
    const erro = html.indexOf("Verifique os dados informados");
    expect(identificacao).toBeGreaterThan(-1);
    expect(nomeAdmin).toBeGreaterThan(identificacao);
    expect(matriculaAdmin).toBeGreaterThan(nomeAdmin);
    expect(erro).toBeGreaterThan(matriculaAdmin);
  });

  it("NÃO oferece escolha de role, organização, tenant nem lista de usuários", () => {
    for (const forma of ["eu", "outra"] as FormaPrimeiroAdmin[]) {
      const html = semearFormulario(forma);
      for (const proibido of [
        "role",
        "admin</option>",
        "metas_dono",
        "observacoes_gestor",
        "organization_id",
        "Organização</span>",
        "Colaborador",
      ]) {
        expect(html, `${forma}:${proibido}`).not.toContain(proibido);
      }
      // A role concedida é fixa e não aparece como escolha do usuário.
      expect(html).not.toContain("<option value=\"admin\"");
    }
  });

  it("mensagem de erro é anunciada e o botão desabilita durante o envio", () => {
    const comErro = semearFormulario("eu", false, "Verifique os dados informados e tente novamente.");
    expect(comErro).toContain('role="alert"');
    expect(comErro).toContain("Verifique os dados informados");

    const enviando = semearFormulario("eu", true);
    expect(enviando).toContain("Criando…");
    expect(enviando).toContain("disabled");
  });
});

describe("F6-A03 — UI: negativa neutra e indisponibilidade", () => {
  it("a negativa não revela dado nem o que a superfície faz", () => {
    const html = renderToStaticMarkup(
      <MemoryRouter>
        <NegativaNeutra />
      </MemoryRouter>
    );
    expect(html).toContain("Acesso não disponível");
    expect(html).not.toContain("<input");
    expect(html).not.toContain("organização");
    expect(html).not.toContain("Admin");
  });

  it("a indisponibilidade é explícita (sem fallback local)", () => {
    const html = renderToStaticMarkup(
      <MemoryRouter>
        <ServicoIndisponivel />
      </MemoryRouter>
    );
    expect(html).toContain("Serviço indisponível");
    expect(html).not.toContain("<input");
  });
});

describe("F6-A03 — UI: confirmação sem identificador interno (critério 24)", () => {
  it("exibe apenas o NOME da organização criada", () => {
    const html = renderToStaticMarkup(
      <MemoryRouter>
        <ConfirmacaoOrganizacao nome="Org Sintetica F6-A03" />
      </MemoryRouter>
    );

    expect(html).toContain("Org Sintetica F6-A03");
    // Nenhum UUID, hash ou código interno de erro é exibido.
    expect(html).not.toMatch(
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    );
    expect(html).not.toContain("[0-9a-f]{64}");
    expect(html).not.toContain("F6_A03_");
    expect(html).not.toContain("payload_hash");
  });
});

describe("F6-A03 — UI: conversão pura do formulário em intenção", () => {
  it("'eu mesmo' usa a identidade da sessão como primeiro Admin", () => {
    const resultado = montarEntradaProvisao({
      operacaoId: OPERACAO_ID,
      nome: "  Org Sintetica  ",
      nomeAdmin: NOME_ADMIN,
      matriculaAdmin: MATRICULA_ADMIN,
      forma: "eu",
      email: "ignorado@example.invalid",
      usuarioAutenticadoId: OPERADOR,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toEqual({
      operationId: OPERACAO_ID,
      organizationName: "Org Sintetica",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderUserId: OPERADOR,
    });
    expect(resultado.entrada.founderEmail).toBeUndefined();
  });

  it("'outra pessoa' normaliza o e-mail e não envia founder_user_id", () => {
    const resultado = montarEntradaProvisao({
      operacaoId: OPERACAO_ID,
      nome: "Org Sintetica",
      nomeAdmin: NOME_ADMIN,
      matriculaAdmin: MATRICULA_ADMIN,
      forma: "outra",
      email: "  Novo.Admin@Example.INVALID ",
      usuarioAutenticadoId: OPERADOR,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toEqual({
      operationId: OPERACAO_ID,
      organizationName: "Org Sintetica",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderEmail: "novo.admin@example.invalid",
    });
    expect(resultado.entrada.founderUserId).toBeUndefined();
  });

  it("entrada incompleta é fail-closed (nome, identidade e e-mail)", () => {
    const identidadeFuncional = { nomeAdmin: NOME_ADMIN, matriculaAdmin: MATRICULA_ADMIN };
    const casos = [
      [
        { ...identidadeFuncional, nome: "   ", forma: "eu" as const, email: "", usuarioAutenticadoId: OPERADOR },
        "nome",
      ],
      [
        { ...identidadeFuncional, nome: "Org", forma: "eu" as const, email: "", usuarioAutenticadoId: null },
        "identidade",
      ],
      [
        { ...identidadeFuncional, nome: "Org", forma: "eu" as const, email: "", usuarioAutenticadoId: "   " },
        "identidade",
      ],
      [
        { ...identidadeFuncional, nome: "Org", forma: "outra" as const, email: "  ", usuarioAutenticadoId: OPERADOR },
        "email",
      ],
    ] as const;

    for (const [entrada, motivo] of casos) {
      const resultado = montarEntradaProvisao({ operacaoId: OPERACAO_ID, ...entrada });
      expect(resultado.ok, motivo).toBe(false);
      if (!resultado.ok) expect(resultado.motivo).toBe(motivo);
    }
  });
});

/**
 * F6-A11 (Issue #273) — identidade FUNCIONAL mínima do primeiro Admin na
 * conversão PURA do formulário (`montarEntradaProvisao`, D23/D26/D28).
 *
 * Prova o fail-closed dos dois campos novos com motivos PRÓPRIOS (`"admin"` e
 * `"matricula"`), a ORDEM de validação do contrato (nome da organização ⇒ nome
 * do Admin ⇒ matrícula ⇒ forma) e que a entrada montada carrega os valores já
 * normalizados por `trim`.
 */
describe("F6-A11 — UI: identidade funcional mínima do primeiro Admin", () => {
  it("nome do primeiro Admin vazio ⇒ motivo 'admin'", () => {
    for (const nomeAdmin of ["", "   ", "\t\n"]) {
      const resultado = montarEntradaProvisao({
        operacaoId: OPERACAO_ID,
        nome: "Org Sintetica",
        nomeAdmin,
        matriculaAdmin: MATRICULA_ADMIN,
        forma: "eu",
        email: "",
        usuarioAutenticadoId: OPERADOR,
      });
      expect(resultado.ok, JSON.stringify(nomeAdmin)).toBe(false);
      if (!resultado.ok) expect(resultado.motivo, JSON.stringify(nomeAdmin)).toBe("admin");
    }
  });

  it("matrícula do primeiro Admin vazia ⇒ motivo 'matricula'", () => {
    for (const matriculaAdmin of ["", "   ", "\t\n"]) {
      const resultado = montarEntradaProvisao({
        operacaoId: OPERACAO_ID,
        nome: "Org Sintetica",
        nomeAdmin: NOME_ADMIN,
        matriculaAdmin,
        forma: "eu",
        email: "",
        usuarioAutenticadoId: OPERADOR,
      });
      expect(resultado.ok, JSON.stringify(matriculaAdmin)).toBe(false);
      if (!resultado.ok) expect(resultado.motivo, JSON.stringify(matriculaAdmin)).toBe("matricula");
    }
  });

  it("a ORDEM da validação é nome da organização ⇒ admin ⇒ matrícula ⇒ forma", () => {
    const base = {
      operacaoId: OPERACAO_ID,
      nome: "Org Sintetica",
      nomeAdmin: NOME_ADMIN,
      matriculaAdmin: MATRICULA_ADMIN,
      forma: "eu" as const,
      email: "",
      usuarioAutenticadoId: OPERADOR,
    };

    // Nome da organização vazio vence os campos novos vazios.
    const semNome = montarEntradaProvisao({ ...base, nome: "  ", nomeAdmin: "  " });
    expect(semNome.ok).toBe(false);
    if (!semNome.ok) expect(semNome.motivo).toBe("nome");

    // Nome do Admin vazio vence a matrícula vazia.
    const semAdmin = montarEntradaProvisao({ ...base, nomeAdmin: "  ", matriculaAdmin: "  " });
    expect(semAdmin.ok).toBe(false);
    if (!semAdmin.ok) expect(semAdmin.motivo).toBe("admin");

    // Matrícula vazia vence a forma inválida ("eu" sem identidade de sessão).
    const semMatricula = montarEntradaProvisao({
      ...base,
      matriculaAdmin: "  ",
      usuarioAutenticadoId: null,
    });
    expect(semMatricula.ok).toBe(false);
    if (!semMatricula.ok) expect(semMatricula.motivo).toBe("matricula");
  });

  it("a entrada montada carrega founderFullName/founderMatricula com trim aplicado", () => {
    const resultado = montarEntradaProvisao({
      operacaoId: OPERACAO_ID,
      nome: "  Org Sintetica  ",
      nomeAdmin: `   ${NOME_ADMIN}  `,
      matriculaAdmin: `\t${MATRICULA_ADMIN} `,
      forma: "outra",
      email: "  Novo.Admin@Example.INVALID ",
      usuarioAutenticadoId: OPERADOR,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada.founderFullName).toBe(NOME_ADMIN);
    expect(resultado.entrada.founderMatricula).toBe(MATRICULA_ADMIN);
    expect(resultado.entrada.organizationName).toBe("Org Sintetica");
    expect(resultado.entrada.founderEmail).toBe("novo.admin@example.invalid");
  });
});
