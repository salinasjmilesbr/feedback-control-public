/// <reference types="node" />
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * F6-A19 (Issue #319) — guardas estáticas do CONVITE COM VÍNCULO SOBERANO.
 *
 * O que estas guardas impedem de voltar:
 * 1. o gate impossível por capability de CONTROLE (membership.manage via
 *    resolver de capabilities), que negava TODO administrador legítimo — a
 *    capability é grantable_via_role = false (F5-04 D15) e nenhuma role pode
 *    carregá-la;
 * 2. allowlist de ambiente como autorização (dívida G11 de docs/F5-01);
 * 3. convite SEM colaboradora (conta "solta") ou com DML direto no vínculo em
 *    vez do primitivo canônico da F5-02;
 * 4. concessão automática de role no convite;
 * 5. SECURITY DEFINER novo (invariante de exatamente 4 da F4-08), alteração de
 *    catálogo/grantable_via_role, RLS/policy ou remoção de função.
 *
 * Leitura por node:fs: aqui os alvos são fontes reais do repositório.
 */

const RAIZ = fileURLToPath(new URL("../..", import.meta.url));

function fonte(caminho: string): string {
  return readFileSync(join(RAIZ, caminho), "utf8");
}

/** Visão de CÓDIGO do TypeScript: comentários de linha e de bloco fora. */
function semComentariosTs(conteudo: string): string {
  return conteudo
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/(^|[^:])\/\/[^\n]*/g, "$1");
}

/** Visão de CÓDIGO do SQL: comentários de linha e de bloco fora. */
function semComentariosSql(conteudo: string): string {
  return conteudo.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/--[^\n]*/g, " ");
}

/**
 * Corpo da função criada pela migration (entre o delimitador de abertura do
 * corpo e o de fechamento). As asserções negativas que a PRÓPRIA guarda da
 * migration cita — ela procura esses termos justamente para provar que não
 * existem no corpo — só fazem sentido dentro do corpo da função.
 */
function corpoDaFuncao(sql: string): string {
  const inicio = sql.indexOf("as $fn$");
  const fim = sql.indexOf("$fn$;", inicio + 1);
  if (inicio === -1 || fim === -1) {
    throw new Error("corpo da função não encontrado na migration");
  }
  return sql.slice(inicio, fim);
}

const EDGE_INDEX = "supabase/functions/convidar-usuario/index.ts";
const EDGE_CORE = "supabase/functions/convidar-usuario/core.ts";
const MIGRATION = "supabase/migrations/20260946000000_f6_a19_convite_vinculo_soberano.sql";

describe("F6-A19 — a Edge não volta ao gate impossível", () => {
  it("não usa membership.manage, resolver de capabilities, allowlist nem capability do cliente", () => {
    for (const caminho of [EDGE_INDEX, EDGE_CORE]) {
      const codigo = semComentariosTs(fonte(caminho));
      for (const proibido of [
        "membership.manage",
        "resolver_capabilities_efetivas",
        "INVITE_ADMIN_USER_IDS",
        "allowlist",
        "capability",
      ]) {
        expect(codigo, caminho + " → " + proibido).not.toContain(proibido);
      }
    }
  });

  it("autoriza pelo predicado canônico e provisiona o vínculo pela RPC nova", () => {
    const index = semComentariosTs(fonte(EDGE_INDEX));

    expect(index).toContain("usuario_eh_administrador");
    expect(index).toContain("convidado_acesso_criar");
    expect(index).toContain("p_collaborator_id");
    expect(index).toContain("p_organization_id");
    // Compensação do usuário recém-criado quando o provisionamento falha.
    expect(index).toContain("deleteUser");
  });

  it("aceita SOMENTE o booleano true do predicado (fail-closed)", () => {
    const core = semComentariosTs(fonte(EDGE_CORE));

    expect(core).toContain("valor === true");
    expect(core).not.toContain("!!valor");
  });
});

describe("F6-A19 — o convite exige e encaminha a colaboradora", () => {
  it("valida collaborator_id na fronteira (UUID) e devolve código público próprio", () => {
    const core = semComentariosTs(fonte(EDGE_CORE));

    expect(core).toContain("collaborator_id");
    expect(core).toContain("INVALID_COLLABORATOR");
  });

  it("o cliente envia collaborator_id no corpo da Edge", () => {
    const provider = semComentariosTs(fonte("src/auth/AuthProvider.tsx"));

    expect(provider).toContain("collaborator_id");
  });

  it("a tela de cadastro informa a colaboradora recém-criada (nunca a chamada antiga)", () => {
    const pagina = semComentariosTs(fonte("src/pages/NovoColaboradorPage.tsx"));

    expect(pagina).toContain("colaboradorCriado");
    expect(pagina).not.toContain("convidarUsuario(email.trim(), organizacaoAtivaId)");
  });

  it("a tela de convite usa a fotografia soberana, sem lista local inventada", () => {
    const pagina = semComentariosTs(fonte("src/auth/ConvidarUsuarioPage.tsx"));

    expect(pagina).toContain("useEstruturaSoberana");
    expect(pagina).toContain("colaboradorId");
    expect(pagina).not.toContain("localStorage");
  });
});

describe("F6-A19 — a migration é aditiva, INVOKER e sem concessão de role", () => {
  const sql = semComentariosSql(fonte(MIGRATION));

  it("cria a RPC INVOKER que reutiliza os primitivos canônicos", () => {
    expect(sql).toContain("security invoker");
    expect(sql).toContain("convidado_acesso_criar");
    expect(sql).toContain("criar_perfil_membership");
    expect(sql).toContain("vincular_colaborador");
    expect(sql).toContain("organization_id = p_organization_id");
  });

  it("restringe a execução a service_role", () => {
    expect(sql).toContain("revoke all on function public.convidado_acesso_criar");
    expect(sql).toContain("grant execute on function public.convidado_acesso_criar");
    expect(sql).toContain("to service_role");
    expect(sql).not.toContain("to authenticated");
    expect(sql).not.toContain("to anon");
  });

  it("não cria DEFINER e não mexe em catálogo, RLS ou schema", () => {
    for (const proibido of [
      "security definer",
      "update public.capabilities",
      "set grantable_via_role",
      "drop function",
      "alter table",
      "create policy",
      "alter policy",
    ]) {
      expect(sql, proibido).not.toContain(proibido);
    }
  });

  it("a função criada não concede role nem faz DML direto no vínculo", () => {
    const corpo = corpoDaFuncao(sql);

    for (const proibido of [
      "conceder_acesso_role",
      "membership_access_role_assignments",
      "insert into public.membership_collaborator_links",
    ]) {
      expect(corpo, proibido).not.toContain(proibido);
    }
    expect(corpo).toContain("criar_perfil_membership");
    expect(corpo).toContain("vincular_colaborador");
  });

  it("a própria migration guarda as invariantes herdadas (4 DEFINER, D15)", () => {
    expect(sql).toContain("SECURITY DEFINER");
    expect(sql).toContain("esperado exatamente 4 SECURITY DEFINER");
    expect(sql).toContain("grantable_via_role = false");
  });
});
