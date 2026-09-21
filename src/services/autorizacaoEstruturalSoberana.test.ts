import { describe, expect, it } from "vitest";
import {
  lerAutorizacaoEstrutural,
  SEM_AUTORIZACAO_ESTRUTURAL,
} from "./autorizacaoEstruturalSoberana";

/**
 * #327/P2B — projeção de menu/rotas a partir da view `estrutura_autorizacao`.
 * Toda ausência (sem cliente, sem organização, sem linha, erro) ⇒ NENHUMA
 * capability: o menu não projeta e a view continua sendo a autoridade.
 */

interface Captura {
  view?: string;
  filtro?: unknown;
}

function clienteFake(
  resposta: { readonly data: unknown; readonly error: unknown },
  captura: Captura = {}
): never {
  const cliente = {
    from(view: string) {
      captura.view = view;
      return {
        select() {
          return {
            eq(_coluna: string, valor: unknown) {
              captura.filtro = valor;
              return { maybeSingle: async () => resposta };
            },
          };
        },
      };
    },
  };
  return cliente as never;
}

describe("#327/P2B — leitura da projeção de autorização estrutural", () => {
  it("lê a view prevista com o filtro da organização ativa", async () => {
    const captura: Captura = {};
    const valor = await lerAutorizacaoEstrutural(
      "org-1",
      clienteFake(
        { data: { organization_id: "org-1", pode_estrutura: true, pode_catalogo: false }, error: null },
        captura
      )
    );

    expect(captura.view).toBe("estrutura_autorizacao");
    expect(captura.filtro).toBe("org-1");
    expect(valor).toEqual({ podeEstrutura: true, podeCatalogo: false });
  });

  it("projeta as duas capabilities quando a view as concede", async () => {
    const valor = await lerAutorizacaoEstrutural(
      "org-1",
      clienteFake(
        { data: { organization_id: "org-1", pode_estrutura: true, pode_catalogo: true }, error: null }
      )
    );

    expect(valor).toEqual({ podeEstrutura: true, podeCatalogo: true });
  });

  it("sem linha ⇒ nada (membership-only não projeta superfície administrativa)", async () => {
    const valor = await lerAutorizacaoEstrutural(
      "org-1",
      clienteFake({ data: null, error: null })
    );

    expect(valor).toEqual(SEM_AUTORIZACAO_ESTRUTURAL);
  });

  it("erro, cliente ausente ou organização ausente ⇒ nada (fail-closed)", async () => {
    expect(
      await lerAutorizacaoEstrutural("org-1", clienteFake({ data: null, error: { code: "42501" } }))
    ).toEqual(SEM_AUTORIZACAO_ESTRUTURAL);
    expect(await lerAutorizacaoEstrutural("org-1", null)).toEqual(SEM_AUTORIZACAO_ESTRUTURAL);
    expect(await lerAutorizacaoEstrutural(null, clienteFake({ data: null, error: null }))).toEqual(
      SEM_AUTORIZACAO_ESTRUTURAL
    );
  });

  it("valores não booleanos na view NÃO viram autorização", async () => {
    const valor = await lerAutorizacaoEstrutural(
      "org-1",
      clienteFake({
        data: { organization_id: "org-1", pode_estrutura: "true", pode_catalogo: 1 },
        error: null,
      })
    );

    expect(valor).toEqual(SEM_AUTORIZACAO_ESTRUTURAL);
  });
});
