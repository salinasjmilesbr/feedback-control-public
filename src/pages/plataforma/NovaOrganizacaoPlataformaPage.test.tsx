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
 */

const OPERACAO_ID = "f6a3b000-0000-4000-8000-000000000001";
const OPERADOR = "f6a30000-0000-4000-8000-000000000003";

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
        mensagem={mensagem}
        enviando={enviando}
        aoMudarNome={() => {}}
        aoMudarForma={() => {}}
        aoMudarEmail={() => {}}
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

    expect(html).toContain("Nome da organização");
    expect(html).toContain("Primeiro Admin");
    expect(html).toContain("Eu mesmo");
    expect(html).toContain("Outra pessoa (e-mail)");
    // SEM o campo de e-mail enquanto a escolha é "eu mesmo".
    expect(html).not.toContain("E-mail do primeiro Admin");
    // Exatamente dois controles de entrada: nome e a seleção do primeiro Admin.
    expect((html.match(/<input/g) ?? []).length).toBe(1);
    expect((html.match(/<select/g) ?? []).length).toBe(1);
  });

  it("mostra o campo de e-mail quando o primeiro Admin é outra pessoa", () => {
    const html = semearFormulario("outra");
    expect(html).toContain("E-mail do primeiro Admin");
    expect((html.match(/<input/g) ?? []).length).toBe(2);
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
    expect(html).toContain("Não autorizado");
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
      forma: "eu",
      email: "ignorado@example.invalid",
      usuarioAutenticadoId: OPERADOR,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toEqual({
      operationId: OPERACAO_ID,
      organizationName: "Org Sintetica",
      founderUserId: OPERADOR,
    });
    expect(resultado.entrada.founderEmail).toBeUndefined();
  });

  it("'outra pessoa' normaliza o e-mail e não envia founder_user_id", () => {
    const resultado = montarEntradaProvisao({
      operacaoId: OPERACAO_ID,
      nome: "Org Sintetica",
      forma: "outra",
      email: "  Novo.Admin@Example.INVALID ",
      usuarioAutenticadoId: OPERADOR,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toEqual({
      operationId: OPERACAO_ID,
      organizationName: "Org Sintetica",
      founderEmail: "novo.admin@example.invalid",
    });
    expect(resultado.entrada.founderUserId).toBeUndefined();
  });

  it("entrada incompleta é fail-closed (nome, identidade e e-mail)", () => {
    const casos = [
      [
        { nome: "   ", forma: "eu" as const, email: "", usuarioAutenticadoId: OPERADOR },
        "nome",
      ],
      [
        { nome: "Org", forma: "eu" as const, email: "", usuarioAutenticadoId: null },
        "identidade",
      ],
      [
        { nome: "Org", forma: "eu" as const, email: "", usuarioAutenticadoId: "   " },
        "identidade",
      ],
      [
        { nome: "Org", forma: "outra" as const, email: "  ", usuarioAutenticadoId: OPERADOR },
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
