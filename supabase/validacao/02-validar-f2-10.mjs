#!/usr/bin/env node
// ============================================================================
// F2-10 (Issue #77): validação integrada — múltiplas contas e isolamento de
// identidade contra o Supabase LOCAL.
// ----------------------------------------------------------------------------
// Pré-requisitos:
//   1) `npx --yes supabase@2.116.0 start` (stack local);
//   2) aplicar `supabase/validacao/01-cenario-f2-10.sql` no banco local
//      (docker exec / psql — ver README da pasta);
//   3) exportar as variáveis locais (valores do `supabase status -o env`,
//      removendo aspas):
//        SUPABASE_URL              (API_URL)
//        SUPABASE_ANON_KEY         (ANON_KEY)
//        SUPABASE_SERVICE_ROLE_KEY (SERVICE_ROLE_KEY)
//   4) `node supabase/validacao/02-validar-f2-10.mjs`
//
// O script NÃO imprime segredos e NÃO toca nenhum projeto remoto. Saída
// determinística: uma linha [PASS]/[FAIL] por verificação e resumo final;
// exit code 0 somente se todas passarem.
// ============================================================================

import { createClient } from "@supabase/supabase-js";

const API = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;

// Cliente administrativo local (service_role), usado apenas para preparar os
// estados dos passos 8/9 — mesmo papel das Edge Functions server-side.
const adminService = SERVICE ? createClient(API, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } }) : null;

const SENHA = "virtus-senha-f2-10-local";

const UUID = {
  admin: "b0000000-0000-0000-0000-000000000001",
  a: "b0000000-0000-0000-0000-00000000000a",
  b: "b0000000-0000-0000-0000-00000000000b",
  c: "b0000000-0000-0000-0000-00000000000c",
  d: "b0000000-0000-0000-0000-00000000000d",
  e: "b0000000-0000-0000-0000-00000000000e",
};
const ORG = {
  alfa: "c0000000-0000-0000-0000-0000000000a1",
  beta: "c0000000-0000-0000-0000-0000000000b1",
};
const EMAIL = {
  admin: "admin.f2-10@example.invalid",
  a: "conta.a.f2-10@example.invalid",
  b: "conta.b.f2-10@example.invalid",
  c: "conta.c.f2-10@example.invalid",
  d: "conta.d.f2-10@example.invalid",
  e: "conta.e.f2-10@example.invalid",
};
const NOME_ORGANIZACAO = {
  alfa: "Org Sintetica Alfa (F2-10)",
  beta: "Org Sintetica Beta (F2-10)",
};

let passos = 0;
let falhas = 0;

function ok(nome) {
  passos += 1;
  console.log(`[PASS] ${nome}`);
}
function falha(nome, detalhe = "") {
  falhas += 1;
  console.log(`[FAIL] ${nome}${detalhe ? ` — ${detalhe}` : ""}`);
}
function verificar(nome, condicao, detalhe = "") {
  if (condicao) ok(nome);
  else falha(nome, detalhe);
}

async function requisicao(caminho, { metodo = "GET", token, corpo, chave, cabecalhosExtras = {} } = {}) {
  const cabecalhos = {
    apikey: chave ?? ANON,
    "Content-Type": "application/json",
    ...cabecalhosExtras,
  };
  if (token) cabecalhos.Authorization = `Bearer ${token}`;
  const resposta = await fetch(API + caminho, {
    method: metodo,
    headers: cabecalhos,
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  });
  const texto = await resposta.text();
  let dados = null;
  try {
    dados = texto ? JSON.parse(texto) : null;
  } catch {
    dados = texto;
  }
  return { status: resposta.status, dados };
}

async function entrar(email, senha = SENHA) {
  const { status, dados } = await requisicao("/auth/v1/token?grant_type=password", {
    metodo: "POST",
    corpo: { email, password: senha },
  });
  if (status !== 200 || !dados?.access_token) {
    throw new Error(`login ${email} falhou (${status}): ${dados?.error?.message ?? "sem detalhe"}`);
  }
  return dados;
}

function subDoToken(jwt) {
  const payload = jwt.split(".")[1];
  return JSON.parse(Buffer.from(payload, "base64url").toString("utf8")).sub;
}

function consultarTabela(token, tabela, filtros = []) {
  const params = new URLSearchParams();
  params.set("select", "*");
  for (const [coluna, valor] of filtros) params.append(coluna, `eq.${valor}`);
  params.set("limit", "100");
  return requisicao(`/rest/v1/${tabela}?${params.toString()}`, { token });
}

function contemApenasOrg(orgs, idEsperado, nomeEsperado) {
  return (
    Array.isArray(orgs) &&
    orgs.length === 1 &&
    orgs[0].id === idEsperado &&
    orgs[0].name === nomeEsperado
  );
}

function chamarFuncaoAdmin(ponto, token, corpo) {
  return requisicao(`/functions/v1/${ponto}`, {
    metodo: "POST",
    token,
    corpo,
  });
}

(async () => {
  if (!API || !ANON || !SERVICE) {
    console.error(
      "[ERRO] Defina SUPABASE_URL, SUPABASE_ANON_KEY e SUPABASE_SERVICE_ROLE_KEY " +
        "(valores locais de `supabase status -o env`)."
    );
    process.exit(2);
  }

  try {
    // ---------------------------------------------------------------- 1. ADMIN
    const sessaoAdmin = await entrar(EMAIL.admin);
    verificar(
      "admin autentica com identidade própria (auth.uid/JWT sub = admin)",
      subDoToken(sessaoAdmin.access_token) === UUID.admin
    );
    const perfilAdmin = await consultarTabela(sessaoAdmin.access_token, "user_profiles");
    verificar(
      "admin (sem collaborator — conceito ainda inexistente) resolve somente o próprio perfil ativo",
      Array.isArray(perfilAdmin.dados) &&
        perfilAdmin.dados.length === 1 &&
        perfilAdmin.dados[0].id === UUID.admin &&
        perfilAdmin.dados[0].status === "active"
    );

    // ------------------------------------------------------------ 2. CONTA A
    const sessaoA = await entrar(EMAIL.a);
    verificar("A: auth.uid corresponde à conta A (sub do JWT)", subDoToken(sessaoA.access_token) === UUID.a);

    const perfilA = await consultarTabela(sessaoA.access_token, "user_profiles");
    verificar(
      "A: resolve apenas o próprio perfil (1 linha, ativo)",
      Array.isArray(perfilA.dados) && perfilA.dados.length === 1 && perfilA.dados[0].id === UUID.a
    );

    const membershipsA = await consultarTabela(sessaoA.access_token, "user_organization_memberships");
    verificar(
      "A: resolve apenas a membership permitida (Alfa)",
      Array.isArray(membershipsA.dados) &&
        membershipsA.dados.length === 1 &&
        membershipsA.dados[0].user_profile_id === UUID.a &&
        membershipsA.dados[0].organization_id === ORG.alfa
    );

    const orgsA = await consultarTabela(sessaoA.access_token, "organizations");
    verificar(
      "A: enxerga apenas a organização permitida (Alfa)",
      contemApenasOrg(orgsA.dados, ORG.alfa, NOME_ORGANIZACAO.alfa)
    );

    const orgBetaVistaPorA = await consultarTabela(sessaoA.access_token, "organizations", [["id", ORG.beta]]);
    verificar("A: não enxerga dados da organização Beta", Array.isArray(orgBetaVistaPorA.dados) && orgBetaVistaPorA.dados.length === 0);

    const perfilBVistoPorA = await consultarTabela(sessaoA.access_token, "user_profiles", [["id", UUID.b]]);
    verificar("A: não lê o perfil exclusivo de B", Array.isArray(perfilBVistoPorA.dados) && perfilBVistoPorA.dados.length === 0);

    // ------------------------------------------------------------ 3. CONTA B
    const sessaoB = await entrar(EMAIL.b);
    verificar("B: auth.uid corresponde à conta B (sub do JWT)", subDoToken(sessaoB.access_token) === UUID.b);

    const perfilB = await consultarTabela(sessaoB.access_token, "user_profiles");
    verificar(
      "B: resolve apenas o próprio perfil (1 linha, ativo)",
      Array.isArray(perfilB.dados) && perfilB.dados.length === 1 && perfilB.dados[0].id === UUID.b
    );

    const membershipsB = await consultarTabela(sessaoB.access_token, "user_organization_memberships");
    verificar(
      "B: resolve apenas a membership permitida (Beta)",
      Array.isArray(membershipsB.dados) &&
        membershipsB.dados.length === 1 &&
        membershipsB.dados[0].organization_id === ORG.beta
    );

    const orgsB = await consultarTabela(sessaoB.access_token, "organizations");
    verificar(
      "B: enxerga apenas a organização permitida (Beta)",
      contemApenasOrg(orgsB.dados, ORG.beta, NOME_ORGANIZACAO.beta)
    );

    const orgAlfaVistaPorB = await consultarTabela(sessaoB.access_token, "organizations", [["id", ORG.alfa]]);
    verificar("B: não enxerga dados da organização Alfa", Array.isArray(orgAlfaVistaPorB.dados) && orgAlfaVistaPorB.dados.length === 0);

    const perfilAVistoPorB = await consultarTabela(sessaoB.access_token, "user_profiles", [["id", UUID.a]]);
    verificar("B: não lê o perfil exclusivo de A", Array.isArray(perfilAVistoPorB.dados) && perfilAVistoPorB.dados.length === 0);

    const membershipAVistaPorB = await consultarTabela(
      sessaoB.access_token,
      "user_organization_memberships",
      [["user_profile_id", UUID.a]]
    );
    verificar("B: não lê memberships de A", Array.isArray(membershipAVistaPorB.dados) && membershipAVistaPorB.dados.length === 0);

    // ----------------------------------------- 4. Conta válida sem membership (C)
    const sessaoC = await entrar(EMAIL.c);
    verificar("C: auth.uid corresponde à conta C", subDoToken(sessaoC.access_token) === UUID.c);
    const membershipsC = await consultarTabela(sessaoC.access_token, "user_organization_memberships");
    const orgsC = await consultarTabela(sessaoC.access_token, "organizations");
    verificar(
      "C (sem membership): autentica, sem memberships nem organizações",
      Array.isArray(membershipsC.dados) && membershipsC.dados.length === 0 &&
        Array.isArray(orgsC.dados) && orgsC.dados.length === 0
    );

    // --------------------- 5. Estado local/impersonação DEV não altera identidade server-side
    const orgsComCabecalhoLocal = await requisicao(`/rest/v1/organizations?select=id,name&limit=20`, {
      token: sessaoA.access_token,
      cabecalhosExtras: { "X-Virtus-Identidade-Local": UUID.b },
    });
    verificar(
      "impersona/estado local não muda identidade server-side (A segue vendo apenas Alfa)",
      contemApenasOrg(orgsComCabecalhoLocal.dados, ORG.alfa, NOME_ORGANIZACAO.alfa)
    );

    // ------------------------------------------------- 6. Refresh/restauração (A)
    const refrescadaA = await requisicao("/auth/v1/token?grant_type=refresh_token", {
      metodo: "POST",
      corpo: { refresh_token: sessaoA.refresh_token },
    });
    verificar(
      "A: refresh/restauração de sessão preserva a mesma identidade (sub inalterado)",
      refrescadaA.status === 200 && subDoToken(refrescadaA.dados.access_token) === UUID.a
    );
    const orgsAposRefresh = await consultarTabela(refrescadaA.dados.access_token, "organizations");
    verificar(
      "A: após refresh/restauração continua vendo somente Alfa",
      contemApenasOrg(orgsAposRefresh.dados, ORG.alfa, NOME_ORGANIZACAO.alfa)
    );

    // ---------------------------------------------- 7. Logout e troca de conta
    const sessaoA2 = await entrar(EMAIL.a); // sessão limpa para o teste de logout
    const logoutA = await requisicao("/auth/v1/logout?scope=global", {
      metodo: "POST",
      token: sessaoA2.access_token,
    });
    verificar("A: logout explícito encerra a sessão no servidor (204)", logoutA.status === 204);
    const refreshAposLogout = await requisicao("/auth/v1/token?grant_type=refresh_token", {
      metodo: "POST",
      corpo: { refresh_token: sessaoA2.refresh_token },
    });
    verificar("A: refresh token revogado após logout não renova a sessão", refreshAposLogout.status >= 400);

    const sessaoB2 = await entrar(EMAIL.b);
    const orgsB2 = await consultarTabela(sessaoB2.access_token, "organizations");
    const orgAlfaAposTroca = await consultarTabela(sessaoB2.access_token, "organizations", [["id", ORG.alfa]]);
    verificar(
      "troca A→B não vaza estado/identidade da conta anterior (B vê somente Beta)",
      contemApenasOrg(orgsB2.dados, ORG.beta, NOME_ORGANIZACAO.beta) &&
        Array.isArray(orgAlfaAposTroca.dados) && orgAlfaAposTroca.dados.length === 0
    );

    // -------------------------------------------- 8. Usuário desabilitado (D)
    const sessaoDParaRevogar = await entrar(EMAIL.d);
    verificar("D: autentica antes da desativação (identidade própria)", subDoToken(sessaoDParaRevogar.access_token) === UUID.d);

    const desabilitar = await chamarFuncaoAdmin("gerenciar-usuario", sessaoAdmin.access_token, {
      action: "disable",
      user_id: UUID.d,
    });
    verificar("admin desativa D via Edge Function (disable)", desabilitar.status === 200 && desabilitar.dados?.status === "disabled");

    const loginDAposDesativar = await entrar(EMAIL.d).catch((erro) => ({ erro: erro.message }));
    verificar("D: sign-in bloqueado após desativação (ban)", typeof loginDAposDesativar === "object" && Boolean(loginDAposDesativar.erro));

    const userEndpointD = await requisicao("/auth/v1/user", { token: sessaoDParaRevogar.access_token });
    verificar(
      "D: JWT emitido antes da desativação é rejeitado no getUser (revogação efetiva)",
      userEndpointD.status >= 400
    );

    const perfilDVistoPorD = await consultarTabela(sessaoDParaRevogar.access_token, "user_profiles", [["id", UUID.d]]);
    verificar(
      "D: RLS impede a resolução do próprio perfil desabilitado (status=active)",
      Array.isArray(perfilDVistoPorD.dados) && perfilDVistoPorD.dados.length === 0
    );

    const orgsBVistaPorB2 = await consultarTabela(sessaoB2.access_token, "organizations");
    verificar(
      "desativar D não afeta o acesso de B (B segue vendo Beta)",
      contemApenasOrg(orgsBVistaPorB2.dados, ORG.beta, NOME_ORGANIZACAO.beta)
    );

    const reativar = await chamarFuncaoAdmin("gerenciar-usuario", sessaoAdmin.access_token, {
      action: "enable",
      user_id: UUID.d,
    });
    verificar("admin reativa D via Edge Function (enable)", reativar.status === 200 && reativar.dados?.status === "active");

    const loginDRestaurado = await entrar(EMAIL.d);
    const orgsDAposReativar = await consultarTabela(loginDRestaurado.access_token, "organizations");
    verificar(
      "D: após reativação, novo login resolve identidade e enxerga Beta",
      subDoToken(loginDRestaurado.access_token) === UUID.d &&
        contemApenasOrg(orgsDAposReativar.dados, ORG.beta, NOME_ORGANIZACAO.beta)
    );

    // --------------------------------------- 9. Membership desabilitada (E)
    const sessaoE = await entrar(EMAIL.e);
    const orgsEAntes = await consultarTabela(sessaoE.access_token, "organizations");
    verificar(
      "E: antes da desativação da membership enxerga Alfa",
      contemApenasOrg(orgsEAntes.dados, ORG.alfa, NOME_ORGANIZACAO.alfa)
    );

    const listarMembershipE = await consultarTabela(
      sessaoE.access_token,
      "user_organization_memberships",
      [["user_profile_id", UUID.e], ["organization_id", ORG.alfa]]
    );
    const idMembershipE =
      Array.isArray(listarMembershipE.dados) && listarMembershipE.dados.length === 1
        ? listarMembershipE.dados[0].id
        : null;

    const desativarMembershipE = await adminService
      .from("user_organization_memberships")
      .update({ status: "disabled" })
      .eq("id", idMembershipE);
    verificar(
      "administração local (service_role) desabilita a membership de E",
      !desativarMembershipE.error && idMembershipE !== null
    );

    const orgsEAposDesativar = await consultarTabela(sessaoE.access_token, "organizations");
    verificar(
      "E: membership desabilitada remove o acesso à organização (orgs = [])",
      Array.isArray(orgsEAposDesativar.dados) && orgsEAposDesativar.dados.length === 0
    );

    const perfilEApos = await consultarTabela(sessaoE.access_token, "user_profiles");
    const membershipsEApos = await consultarTabela(sessaoE.access_token, "user_organization_memberships");
    verificar(
      "E: perfil segue ativo e a própria membership desabilitada permanece visível (histórico preservado)",
      Array.isArray(perfilEApos.dados) && perfilEApos.dados.length === 1 &&
        Array.isArray(membershipsEApos.dados) &&
        membershipsEApos.dados.some((m) => m.user_profile_id === UUID.e && m.status === "disabled")
    );

    // Restaura a baseline (reenable da membership) para permitir reexecução
    // sem reaplicar o SQL de cenário.
    await adminService
      .from("user_organization_memberships")
      .update({ status: "active" })
      .eq("id", idMembershipE);

    // ------------------------------------------------ 10. Signup público negado
    const signup = await requisicao("/auth/v1/signup", {
      metodo: "POST",
      corpo: { email: "novo.signup.f2-10@example.invalid", password: "senha-local-f2-10" },
    });
    verificar(
      "signup público permanece desabilitado (sem acesso_token)",
      signup.status >= 400 && !Boolean(signup.dados?.access_token)
    );
  } catch (erro) {
    falha(`exceção inesperada durante a validação: ${erro.message}`);
  }

  console.log("------------------------------------------------------------");
  console.log(`Resultado F2-10: ${passos} verificações, ${falhas} falha(s).`);
  process.exit(falhas > 0 ? 1 : 0);
})();
