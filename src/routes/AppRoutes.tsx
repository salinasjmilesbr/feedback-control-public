import { BrowserRouter, Routes, Route } from "react-router-dom";

import ColaboradoresPage from "../pages/ColaboradoresPage";
import ColaboradorDetalhePage from "../pages/ColaboradorDetalhePage";
import NovoColaboradorPage from "../pages/NovoColaboradorPage";
import NovoFeedbackPage from "../pages/NovoFeedbackPage";
import FeedbackDetalhePage from "../pages/FeedbackDetalhePage";
import EditarFeedbackPage from "../pages/EditarFeedbackPage";

function AppRoutes() {
  return (
    <BrowserRouter>
      <Routes>
        <Route
          path="/"
          element={<ColaboradoresPage />}
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
    </BrowserRouter>
  );
}

export default AppRoutes;