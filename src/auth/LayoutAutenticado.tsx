import { Navigate, Outlet } from "react-router-dom";
import { simulacaoDevPermitida } from "../config/ambiente";
import { useAuth } from "./AuthContext";
import { decidirAcessoARotasFuncionais } from "./rotasProtegidas";
import AguardandoSelecao from "./AguardandoSelecao";
import SemOrganizacao from "./SemOrganizacao";
import SessaoIndisponivel from "./SessaoIndisponivel";

/**
 * Guard/layout autenticado (F2-04), centralizado para todas as rotas
 * funcionais. Reutiliza o estado de sessão do `AuthContext` da F2-03 — não
 * cria um segundo mecanismo de sessão nem assinaturas adicionais do Supabase.
 *
 * - `verificando`: exibe apenas um carregamento neutro (nada de conteúdo
 *   protegido é renderizado antes da resolução da sessão);
 * - sem sessão válida (ou acesso negado, ou HOMOLOG/PROD sem configuração):
 *   redireciona para `/login`, sem loop de redirects (a rota de login é
 *   pública e trata os estados);
 * - em DEV com a simulação preservada (`simulacaoDevPermitida`), o acesso
 *   permanece como na arquitetura atual; fora de DEV nunca há fallback de
 *   identidade simulada.
 */
export default function LayoutAutenticado({
  simulacaoDev = simulacaoDevPermitida,
}: {
  simulacaoDev?: boolean;
} = {}) {
  const { estado } = useAuth();
  const decisao = decidirAcessoARotasFuncionais(estado, simulacaoDev);

  if (decisao.tipo === "carregando") {
    return (
      <div className="auth-loading" role="status" aria-live="polite">
        Verificando sessão…
      </div>
    );
  }

  if (decisao.tipo === "redirecionarLogin") {
    return <Navigate to="/login" replace />;
  }

  if (decisao.tipo === "semOrganizacao") {
    return <SemOrganizacao />;
  }

  if (decisao.tipo === "aguardandoSelecao") {
    return <AguardandoSelecao />;
  }

  if (decisao.tipo === "indisponivelTemporaria") {
    return <SessaoIndisponivel />;
  }

  return <Outlet />;
}
