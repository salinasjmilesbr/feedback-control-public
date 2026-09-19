import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  obterProvisionamentoPlataforma,
  type DependenciasAcessoPlataforma,
} from "../../services/plataforma/controladorProvisionamento";
import type { ProvisionamentoPlataforma } from "../../application/ports/ProvisionamentoPlataforma";
import { ROTA_PLATAFORMA_NOVA_ORGANIZACAO } from "../../routes/plataformaRotas";
import "../../styles/platform.css";

export interface PropsHomePlataforma {
  readonly provisionamento?: ProvisionamentoPlataforma | null;
  readonly deps?: DependenciasAcessoPlataforma;
}

type EstadoHome = "verificando" | "autorizado" | "negado";

export function HomePlataformaAutorizada() {
  return (
    <section className="platform-hero">
      <div>
        <p className="platform-eyebrow">Admin Virtus</p>
        <h1>Administração</h1>
        <p className="platform-hero__lead">
          Gerencie as empresas que utilizam o Virtus.
        </p>
      </div>
      <div className="platform-panel platform-panel--action">
        <div>
          <h2>Nova empresa</h2>
          <p>Cadastre uma empresa e defina seu administrador inicial.</p>
        </div>
        <Link to={ROTA_PLATAFORMA_NOVA_ORGANIZACAO} className="brand-button brand-button--primary">
          Nova empresa
        </Link>
      </div>
    </section>
  );
}

export function HomePlataforma({
  provisionamento,
  deps,
}: PropsHomePlataforma = {}) {
  const controlador = useMemo(
    () => (provisionamento === undefined ? obterProvisionamentoPlataforma(deps) : provisionamento),
    [provisionamento, deps]
  );
  const [estado, setEstado] = useState<EstadoHome>("verificando");

  useEffect(() => {
    let vigente = true;
    if (!controlador) return undefined;

    void controlador.souOperadorDaPlataforma().then((operador) => {
      if (vigente) setEstado(operador ? "autorizado" : "negado");
    });

    return () => {
      vigente = false;
    };
  }, [controlador]);

  if (!controlador) {
    return <p className="platform-feedback">Serviço de plataforma indisponível neste ambiente.</p>;
  }

  if (estado === "verificando") {
    return <p className="platform-feedback" role="status">Verificando acesso à plataforma…</p>;
  }

  if (estado === "negado") {
    return (
      <section className="platform-panel">
        <p className="platform-eyebrow">Virtus</p>
        <h1>Acesso não disponível</h1>
        <p>Esta área não está disponível para esta conta.</p>
      </section>
    );
  }

  return <HomePlataformaAutorizada />;
}

export default HomePlataforma;
