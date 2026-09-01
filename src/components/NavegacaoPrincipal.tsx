import type { ReactNode } from "react";
import { NavLink } from "react-router-dom";
import { can } from "../authorization/authorizationPolicy";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";

function IconHome() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M3 11.5 12 4l9 7.5" />
      <path d="M5.5 10.5V20h13v-9.5" />
      <path d="M9.5 20v-6h5v6" />
    </svg>
  );
}

function IconCalendar() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="3.5" y="5.5" width="17" height="15" rx="2" />
      <path d="M7 3v5M17 3v5M3.5 10h17" />
    </svg>
  );
}

function IconChart() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />
    </svg>
  );
}

function IconSettings() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-2.83 2.83-.06-.06A1.7 1.7 0 0 0 15 19.4a1.7 1.7 0 0 0-1 .6 1.7 1.7 0 0 0-.4 1.1V21h-4v-.09a1.7 1.7 0 0 0-1.1-1.58 1.7 1.7 0 0 0-1.88.34l-.06.06-2.83-2.83.06-.06A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-.6-1 1.7 1.7 0 0 0-1.1-.4H3v-4h.09A1.7 1.7 0 0 0 4.67 8.5a1.7 1.7 0 0 0-.34-1.88l-.06-.06 2.83-2.83.06.06A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-.6 1.7 1.7 0 0 0 .4-1.1V3h4v.09A1.7 1.7 0 0 0 15.5 4.67a1.7 1.7 0 0 0 1.88-.34l.06-.06 2.83 2.83-.06.06A1.7 1.7 0 0 0 19.4 9c.13.37.34.72.6 1 .3.3.69.48 1.1.5H21v4h-.09A1.7 1.7 0 0 0 19.4 15Z" />
    </svg>
  );
}

function IconClipboard() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="5" y="4.5" width="14" height="16" rx="2" />
      <path d="M9 4.5V3h6v1.5M8.5 10h7M8.5 14h7M8.5 18h4" />
    </svg>
  );
}

function IconTarget() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="8" />
      <circle cx="12" cy="12" r="4" />
      <circle cx="12" cy="12" r="1" />
    </svg>
  );
}

interface ItemProps {
  to: string;
  end?: boolean;
  icon: ReactNode;
  children: ReactNode;
}

function NavItem({ to, end, icon, children }: ItemProps) {
  return (
    <NavLink to={to} end={end}>
      <span className="app-nav__icon">{icon}</span>
      <span>{children}</span>
    </NavLink>
  );
}

function NavegacaoPrincipal() {
  const { usuarioAtual } = useUsuarioAtual();
  if (!usuarioAtual) return null;

  const gerente = usuarioAtual.funcao === "GERENTE";
  const coordenador = usuarioAtual.funcao === "COORDENADOR";
  const avaliado =
    coordenador ||
    usuarioAtual.funcao === "ANALISTA" ||
    usuarioAtual.funcao === "CONSULTOR";
  const podeVerRelatorios = can(
    {
      actor: {
        matricula: usuarioAtual.matricula,
        funcao: usuarioAtual.funcao,
        status: usuarioAtual.status,
      },
    },
    "report.view",
    { kind: "global" }
  );
  const podeGerenciarCiclos = can(
    {
      actor: {
        matricula: usuarioAtual.matricula,
        funcao: usuarioAtual.funcao,
        status: usuarioAtual.status,
      },
    },
    "cycle.management.view",
    { kind: "global" }
  );
  const podeListarCiclosComoCoordenador = can(
    {
      actor: {
        matricula: usuarioAtual.matricula,
        funcao: usuarioAtual.funcao,
        status: usuarioAtual.status,
      },
    },
    "cycle.coordinator.list",
    { kind: "global" }
  );

  return (
    <nav className="app-nav" aria-label="Navegação principal">
      <div className="app-nav__inner">
        <NavItem to="/" end icon={<IconHome />}>
          Início
        </NavItem>

        {podeGerenciarCiclos && (
          <NavItem to="/ciclos" icon={<IconCalendar />}>
            Ciclos
          </NavItem>
        )}

        {podeListarCiclosComoCoordenador && (
          <NavItem to="/painel-ciclos" icon={<IconCalendar />}>
            Ciclos
          </NavItem>
        )}

        {avaliado && (
          <NavItem
            to="/minha-avaliacao"
            icon={<IconClipboard />}
          >
            Minhas avaliações
          </NavItem>
        )}

        {avaliado && (
          <NavItem to="/minhas-metas" icon={<IconTarget />}>
            Minhas metas
          </NavItem>
        )}

        {podeVerRelatorios && (
          <NavItem to="/relatorios" icon={<IconChart />}>
            Relatórios
          </NavItem>
        )}

        {gerente && (
          <NavItem
            to="/configuracoes/aparencia"
            icon={<IconSettings />}
          >
            Configurações
          </NavItem>
        )}
      </div>
    </nav>
  );
}

export default NavegacaoPrincipal;
