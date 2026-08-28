import { BrowserRouter, Routes, Route } from "react-router-dom";
import UsuarioAtualBar from "../components/UsuarioAtualBar";
import NavegacaoPrincipal from "../components/NavegacaoPrincipal";
import AppFooter from "../components/AppFooter";

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

function AppRoutes() {
  return (
    <BrowserRouter>
      <UsuarioAtualBar />
      <NavegacaoPrincipal />
      <main className="app-main">
        <Routes>
          <Route path="/" element={<InicioPage />} />

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

          <Route
            path="/configuracoes/aparencia"
            element={<ConfiguracoesAparenciaPage />}
          />

          <Route
            path="/colaboradores/novo"
            element={<NovoColaboradorPage />}
          />

          <Route
            path="/colaborador/:id"
            element={<ColaboradorDetalhePage />}
          />

          <Route
            path="/colaborador/:id/editar"
            element={<EditarColaboradorPage />}
          />

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
        </Routes>
      </main>
      <AppFooter />
    </BrowserRouter>
  );
}

export default AppRoutes;
