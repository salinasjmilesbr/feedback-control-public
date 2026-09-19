import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { obterProvisionamentoPlataforma } from "../services/plataforma/controladorProvisionamento";
import { ROTA_PLATAFORMA } from "../routes/plataformaRotas";
import type { ProvisionamentoPlataforma } from "../application/ports/ProvisionamentoPlataforma";

/**
 * F6-A04 (Issue #269) — ENTRADA da superfície de PLATAFORMA (contrato §3.1, D3).
 *
 * Componente ÚNICO (sonda + link) reutilizado pelas telas de sessão viva para
 * que o operador autorizado chegue a `/plataforma/nova-organizacao` **sem
 * digitar a URL**:
 *
 * - faz o **self-check de UX** já existente (`souOperadorDaPlataforma`, D20), que
 *   é **FAIL-CLOSED**: qualquer falha resolve `false` e a entrada **não** aparece.
 *   Sem caminho soberano no ambiente (`null`), também não aparece;
 * - enquanto a sonda não responde, a entrada permanece **oculta** (nada de
 *   superfície exposta antes da resposta);
 * - **NÃO** decide autorização, **NÃO** lê/escreve storage, **NÃO** chama RPC e
 *   **NÃO** carrega dado de tenant: a autoridade continua exclusivamente
 *   server-side (Edge `provisionar-organizacao` + RPC soberana) e ocultar/mostrar
 *   é apenas UX (`.ai/architecture-rules.md` §1.7);
 * - **NÃO** entra na navegação funcional do produto (F6-A03 D21/§6.5.4).
 */

/**
 * Apresentação PURA da entrada: **nada** é renderizado enquanto `visivel` não for
 * `true`. Separada do portão assíncrono para ser verificável sem ambiente DOM (o
 * tooling de teste do projeto renderiza sem DOM, onde effects não executam).
 */
export function EntradaPlataformaVisivel({ visivel }: { readonly visivel: boolean }) {
  if (!visivel) return null;
  return (
    <Link to={ROTA_PLATAFORMA} className="auth-status__entrar">
      Acessar administração
    </Link>
  );
}

export interface PropsEntradaPlataforma {
  /**
   * Injeção do controlador (teste). `undefined` = caminho de produção
   * (fail-closed: sem caminho soberano, a entrada não é oferecida).
   */
  readonly provisionamento?: ProvisionamentoPlataforma | null;
  readonly redirecionar?: boolean;
}

function EntradaPlataforma({ provisionamento, redirecionar = false }: PropsEntradaPlataforma = {}) {
  const navigate = useNavigate();
  const [visivel, setVisivel] = useState(false);

  useEffect(() => {
    let vigente = true;
    const controlador =
      provisionamento === undefined ? obterProvisionamentoPlataforma() : provisionamento;

    // Fail-closed: sem caminho soberano no ambiente, nenhuma entrada é oferecida.
    if (!controlador) return undefined;

    void controlador.souOperadorDaPlataforma().then((operador) => {
      if (vigente) setVisivel(operador);
      if (!vigente) return;
      if (operador && redirecionar) {
        navigate(ROTA_PLATAFORMA, { replace: true });
        return;
      }
    });

    return () => {
      vigente = false;
    };
  }, [navigate, provisionamento, redirecionar]);

  return redirecionar ? null : <EntradaPlataformaVisivel visivel={visivel} />;
}

export default EntradaPlataforma;
