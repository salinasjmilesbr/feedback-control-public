import { useEffect } from "react";
import {
  BrowserRouter,
  Navigate,
  Outlet,
  Route,
  Routes,
  useLocation,
} from "react-router-dom";
import UsuarioAtualBar from "../components/UsuarioAtualBar";
import NavegacaoPrincipal from "../components/NavegacaoPrincipal";
import AppFooter from "../components/AppFooter";
import LayoutAutenticado from "../auth/LayoutAutenticado";
import { useAuth } from "../auth/AuthContext";
import { useEstruturaSoberanaDoCliente } from "../pages/useEstruturaSoberanaDoCliente";
import LoginPage from "../auth/LoginPage";
import RecuperarSenhaPage from "../auth/RecuperarSenhaPage";
import RedefinirSenhaPage from "../auth/RedefinirSenhaPage";
import ConvidarUsuarioPage from "../auth/ConvidarUsuarioPage";

import InicioPage from "../pages/InicioPage";
import MinhaAvaliacaoPage from "../pages/MinhaAvaliacaoPage";
import MinhaAvaliacaoDetalhePage from "../pages/MinhaAvaliacaoDetalhePage";
import CiclosAvaliacaoPage from "../pages/CiclosAvaliacaoPage";
import PainelCicloPage from "../pages/PainelCicloPage";
import PainelCiclosCoordenadorPage from "../pages/PainelCiclosCoordenadorPage";
import MinhasMetasPage from "../pages/MinhasMetasPage";
import AcompanhamentoMetasPage from "../pages/AcompanhamentoMetasPage";
import ColaboradorDetalhePage from "../pages/ColaboradorDetalhePage";
import NovoColaboradorPage from "../pages/NovoColaboradorPage";
import EditarColaboradorPage from "../pages/EditarColaboradorPage";
import NovoFeedbackPage from "../pages/NovoFeedbackPage";
import FeedbackDetalhePage from "../pages/FeedbackDetalhePage";
import EditarFeedbackPage from "../pages/EditarFeedbackPage";
import ConfiguracoesAparenciaPage from "../pages/ConfiguracoesAparenciaPage";
import RelatoriosPage from "../pages/RelatoriosPage";
import CatalogosPage from "../pages/CatalogosPage";
import UnidadesPage from "../pages/UnidadesPage";
import PosicoesPage from "../pages/PosicoesPage";
import ColegiadoPage from "../pages/ColegiadoPage";

function ScrollToTop() {
  const { pathname } = useLocation();

  useEffect(() => {
    window.scrollTo({
      top: 0,
      left: 0,
      behavior: "auto",
    });
  }, [pathname]);

  return null;
}

/** Rota pública do fluxo de autenticação (somente o necessário). */
function LayoutPublico() {
  return (
    <main className="app-main">
      <Outlet />
    </main>
  );
}

/**
 * Shell das rotas funcionais: cabeçalho, navegação, conteúdo e rodapé. Só é
 * renderizado quando o `LayoutAutenticado` (guard) permitir o acesso.
 *
 * F5-08 P6: aqui a ESTRUTURA SOBERANA é carregada pelo caminho normal já
 * existente (RLS P4 + porta de colaboradores F5-07) e publicada para os
 * consumidores legados de ciclo/metas. Sem injeção manual e sem fonte local em
 * produção; falha real ⇒ fail-closed nos consumidores.
 */
function LayoutFuncional() {
  const { organizacaoAtivaId } = useAuth();
  useEstruturaSoberanaDoCliente(organizacaoAtivaId);

  return (
    <>
      <UsuarioAtualBar />
      <NavegacaoPrincipal />
      <main className="app-main">
        <Outlet />
      </main>
      <AppFooter />
    </>
  );
}

function AppRoutes() {
  return (
    <BrowserRouter>
      <ScrollToTop />
      <Routes>
        <Route element={<LayoutPublico />}>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/recuperar-senha" element={<RecuperarSenhaPage />} />
          <Route path="/redefinir-senha" element={<RedefinirSenhaPage />} />
        </Route>

        <Route element={<LayoutAutenticado />}>
          <Route element={<LayoutFuncional />}>
            <Route index element={<InicioPage />} />

            <Route
              path="/convidar-usuario"
              element={<ConvidarUsuarioPage />}
            />

            <Route
              path="/minha-avaliacao"
              element={<MinhaAvaliacaoPage />}
            />

            <Route
              path="/minha-avaliacao/:feedbackId"
              element={<MinhaAvaliacaoDetalhePage />}
            />

            <Route path="/ciclos" element={<CiclosAvaliacaoPage />} />

            <Route
              path="/ciclos/:cicloId"
              element={<PainelCicloPage />}
            />

            <Route
              path="/ciclos/:cicloId/colaborador/:id/metas"
              element={<AcompanhamentoMetasPage />}
            />

            <Route
              path="/painel-ciclos"
              element={<PainelCiclosCoordenadorPage />}
            />

            <Route path="/minhas-metas" element={<MinhasMetasPage />} />

            <Route path="/relatorios" element={<RelatoriosPage />} />

            <Route
              path="/configuracoes/aparencia"
              element={<ConfiguracoesAparenciaPage />}
            />

            {/*
              F5-08 P4: administração de estrutura e catálogos. A LEITURA é
              soberana e own-tenant por RLS (D16) — nenhuma capability é exigida
              para ler; as MUTAÇÕES vão à Edge `colaboradores`, que decide por
              capability efetiva (`org.structure.manage` / `org.catalog.manage`)
              e devolve o código público. Nenhuma regra de autorização é
              replicada no React.
            */}
            <Route path="/unidades" element={<UnidadesPage />} />
            <Route path="/posicoes" element={<PosicoesPage />} />
            <Route path="/colegiado" element={<ColegiadoPage />} />
            <Route path="/catalogos" element={<CatalogosPage />} />

            <Route
              path="/colaboradores/novo"
              element={<NovoColaboradorPage />}
            />

            {/*
              F5-07: identidade canônica por UUID (`collaboratorId`). A URL legada
              com matrícula continua aceita no MESMO caminho — a matrícula é
              resolvida no servidor pela porta única (ausente/ambígua ⇒ erro
              fail-closed), nunca no cliente.
            */}
            <Route
              path="/colaborador/:collaboratorId"
              element={<ColaboradorDetalhePage />}
            />

            <Route
              path="/colaborador/:collaboratorId/editar"
              element={<EditarColaboradorPage />}
            />

            {/*
              Rotas ainda por MATRÍCULA: consumidores fora do escopo F5-07
              (avaliação/observação legadas) continuam recebendo `:id` numérico.
            */}
            <Route
              path="/colaborador/:id/novo-feedback"
              element={<NovoFeedbackPage />}
            />

            <Route
              path="/colaborador/:id/feedback/:feedbackId"
              element={<FeedbackDetalhePage />}
            />

            <Route
              path="/colaborador/:id/feedback/:feedbackId/editar"
              element={<EditarFeedbackPage />}
            />

            <Route path="*" element={<Navigate to="/" replace />} />
          </Route>
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default AppRoutes;
