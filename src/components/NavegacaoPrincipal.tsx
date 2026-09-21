import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { NavLink } from "react-router-dom";
import type { Capability } from "../authorization/Capability";
import { useAuth } from "../auth/AuthContext";
import { listarCapabilitiesEfetivas } from "../services/capabilitiesSoberanas";
import {
  lerAutorizacaoEstrutural,
  SEM_AUTORIZACAO_ESTRUTURAL,
  type AutorizacaoEstruturalSoberana,
} from "../services/autorizacaoEstruturalSoberana";

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

function IconStructure() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="9" y="3" width="6" height="5" rx="1" />
      <rect x="2.5" y="16" width="6" height="5" rx="1" />
      <rect x="15.5" y="16" width="6" height="5" rx="1" />
      <path d="M12 8v4M5.5 16v-4h13v4" />
    </svg>
  );
}

function IconCatalog() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M4 5.5h9M4 12h7M4 18.5h5" />
      <path d="M15 6.5 19 4l2 2.5-4 2.5z" />
      <circle cx="17.5" cy="16" r="3.5" />
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

type NavegacaoPrincipalProps = {
  /** Semente determinística (SSR/teste): desliga a leitura da view. */
  readonly autorizacaoInicial?: AutorizacaoEstruturalSoberana;
  /** Injeção de teste da leitura de `estrutura_autorizacao`. */
  readonly lerAutorizacao?: typeof lerAutorizacaoEstrutural;
};

function NavegacaoPrincipal({
  autorizacaoInicial,
  lerAutorizacao = lerAutorizacaoEstrutural,
}: NavegacaoPrincipalProps = {}) {
  const { organizacaoAtivaId } = useAuth();
  const [snapshot, setSnapshot] = useState<{
    organizationId: string | null;
    capabilities: ReadonlySet<Capability>;
  }>({ organizationId: null, capabilities: new Set() });
  useEffect(() => {
    let vigente = true;
    if (organizacaoAtivaId) {
      void listarCapabilitiesEfetivas(organizacaoAtivaId).then((items) => {
        if (vigente) {
          setSnapshot({
            organizationId: organizacaoAtivaId,
            capabilities: new Set(items),
          });
        }
      });
    }
    return () => {
      vigente = false;
    };
  }, [organizacaoAtivaId]);

  // #327/P2B: projeção do MENU a partir de `estrutura_autorizacao` (view do P1).
  // Ausência de linha/erro ⇒ nenhuma superfície administrativa no menu; a
  // segurança continua na view que entrega os dados (URL direta não ganha
  // autoridade pelo cliente).
  const [autorizacao, setAutorizacao] = useState<{
    organizationId: string | null;
    valor: AutorizacaoEstruturalSoberana;
  }>(() => ({
    organizationId: autorizacaoInicial ? (organizacaoAtivaId ?? null) : null,
    valor: autorizacaoInicial ?? SEM_AUTORIZACAO_ESTRUTURAL,
  }));
  useEffect(() => {
    // Semente determinística (SSR/teste) desliga a leitura da view.
    if (autorizacaoInicial) return;
    let vigente = true;
    if (organizacaoAtivaId) {
      void lerAutorizacao(organizacaoAtivaId).then((valor) => {
        if (vigente) setAutorizacao({ organizationId: organizacaoAtivaId, valor });
      });
    }
    return () => {
      vigente = false;
    };
  }, [organizacaoAtivaId, autorizacaoInicial, lerAutorizacao]);

  const possui = (capability: Capability) =>
    snapshot.organizationId === organizacaoAtivaId &&
    snapshot.capabilities.has(capability);
  /**
   * Bug #170: `cycle.management.view` e `cycle.coordinator.list` são ALIASES da
   * MESMA capability canônica (`cycle.read`, colapso Q1 da F4-09 em
   * `authorization/canonical.ts`). Como Gerente e Coordenador possuem
   * `cycle.read`, as duas condições ficavam verdadeiras ao mesmo tempo e o menu
   * renderizava DOIS itens "Ciclos" consecutivos — um para `/ciclos` e outro
   * para `/painel-ciclos`.
   *
   * A visibilidade do menu é UX (o resource `{ kind: "global" }` é
   * explicitamente transitório no Policy Engine e nunca prova de autorização):
   * a listagem de ciclos tem UM único item, gated pela capability canônica. O
   * painel do coordenador (`/painel-ciclos`) permanece rota autorizada e
   * alcançável a partir de "Minha equipe" (Início).
   */
  const podeAcessarCiclos = possui("cycle.read");
  const podeVerAvaliacoes = possui("evaluation.read");
  const podeVerMetas = possui("goal.read");
  const podeVerRelatorios = possui("report.read");
  const podeGerenciarConfiguracoes = possui("settings.manage");
  const podeAdministrarAvaliadores = possui("access_role.manage");
  // #327/P2B: `org.structure.manage` projeta Unidades/Posições/Colegiado e
  // `org.catalog.manage` projeta Catálogos (decisão da VIEW, não do menu). Uma
  // leitura de OUTRA organização nunca projeta: na troca de tenant o menu fica
  // oculto até a resposta da organização ativa (mesma regra de `possui`).
  const autorizacaoVigente =
    autorizacao.organizationId === organizacaoAtivaId ? autorizacao.valor : null;
  const podeAdministrarEstrutura = autorizacaoVigente?.podeEstrutura === true;
  const podeAdministrarCatalogos = autorizacaoVigente?.podeCatalogo === true;

  return (
    <nav className="app-nav" aria-label="Navegação principal">
      <div className="app-nav__inner">
        <NavItem to="/" end icon={<IconHome />}>
          Início
        </NavItem>

        {podeAcessarCiclos && (
          <NavItem to="/ciclos" icon={<IconCalendar />}>
            Ciclos
          </NavItem>
        )}

        {podeVerAvaliacoes && (
          <NavItem
            to="/minha-avaliacao"
            icon={<IconClipboard />}
          >
            Minhas avaliações
          </NavItem>
        )}

        {podeVerMetas && (
          <NavItem to="/minhas-metas" icon={<IconTarget />}>
            Minhas metas
          </NavItem>
        )}

        {podeVerRelatorios && (
          <NavItem to="/relatorios" icon={<IconChart />}>
            Relatórios
          </NavItem>
        )}

        {/*
          #327/P2B — Estrutura e Catálogos. O MENU apenas PROJETA a decisão da
          view `estrutura_autorizacao`: `org.structure.manage` mostra Unidades,
          Posições e Colegiado; `org.catalog.manage` mostra Catálogos. Sem a
          capability o item não aparece — e a URL direta continua negada pela
          view que entrega os dados (ocultar no menu nunca foi autorização).
        */}
        {podeAdministrarEstrutura && (
          <>
            <NavItem to="/unidades" icon={<IconStructure />}>
              Unidades
            </NavItem>

            <NavItem to="/posicoes" icon={<IconStructure />}>
              Posições
            </NavItem>

            <NavItem to="/colegiado" icon={<IconStructure />}>
              Colegiado
            </NavItem>
          </>
        )}

        {podeAdministrarCatalogos && (
          <NavItem to="/catalogos" icon={<IconCatalog />}>
            Catálogos
          </NavItem>
        )}

        {podeGerenciarConfiguracoes && (
          <NavItem
            to="/configuracoes/aparencia"
            icon={<IconSettings />}
          >
            Configurações
          </NavItem>
        )}
        {podeAdministrarAvaliadores && (
          <NavItem to="/administracao/avaliadores" icon={<IconSettings />}>
            Acesso às avaliações
          </NavItem>
        )}
      </div>
    </nav>
  );
}

export default NavegacaoPrincipal;
