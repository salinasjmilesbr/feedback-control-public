/**
 * F5-08 P5 — leitura soberana da estrutura para as telas de ALOCAÇÃO.
 *
 * Encapsula o MESMO caminho já usado pelas telas do P4 (`lerEstrutura` → RLS
 * own-tenant por JWT, sem capability e sem RPC de listagem — D16) no padrão
 * derivado de estado: a leitura é disparada por efeito e o estado exibido é
 * derivado da chave corrente, sem `setState` síncrono em efeito e sem cache de
 * decisão.
 *
 * Nada aqui é autoridade: a fotografia é uma LEITURA; as mutações continuam na
 * Edge (`colaborador.ocupacao.*`, `estrutura.reporting.*`) e são decididas
 * server-side. Nenhuma escrita local, nenhum fallback.
 */

import { useEffect, useState } from "react";
import {
  lerEstrutura,
  type DependenciasAcessoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import { SEM_ORGANIZACAO_ATIVA, type EstadoEstrutura } from "./apoioEstrutura";

export interface EntradaUseEstruturaSoberana {
  /** Organização ativa do contexto de UX (INTENÇÃO; o servidor revalida). */
  readonly organizacaoAtivaId: string | null | undefined;
  /** Dependências da porta (injeção de teste). Deve ser estável entre renders. */
  readonly deps?: DependenciasAcessoColaboradores;
  /** Semente de estado (SSR/teste determinístico): desliga a leitura. */
  readonly estadoInicial?: EstadoEstrutura;
  /** `false` desliga a leitura (ex.: seção opcional não utilizada). */
  readonly habilitado?: boolean;
}

export interface EstruturaSoberanaUso {
  /** Fotografia corrente (carregando/erro/pronta) — derivada, nunca inventada. */
  readonly estado: EstadoEstrutura;
  /** Descarta a fotografia anterior e lê novamente (após mutação/conflito). */
  readonly recarregar: () => void;
}

export function useEstruturaSoberana(
  entrada: EntradaUseEstruturaSoberana
): EstruturaSoberanaUso {
  const { organizacaoAtivaId, deps, estadoInicial } = entrada;
  const habilitado = entrada.habilitado !== false;

  const [versao, setVersao] = useState(0);
  const chaveCarregamento = `${organizacaoAtivaId ?? "sem-organizacao"}|${versao}`;
  const [carregamento, setCarregamento] = useState<{
    readonly chave: string;
    readonly estado: EstadoEstrutura;
  } | null>(estadoInicial ? { chave: "semente", estado: estadoInicial } : null);

  useEffect(() => {
    if (estadoInicial || !habilitado || !organizacaoAtivaId) return;

    let vigente = true;

    void lerEstrutura({ organizationId: organizacaoAtivaId }, deps ?? {}).then((resultado) => {
      if (!vigente) return;
      setCarregamento({
        chave: chaveCarregamento,
        estado: resultado.ok
          ? { fase: "pronto", estrutura: resultado.dados }
          : {
              fase: "erro",
              codigo: resultado.codigo,
              mensagem: resultado.mensagem,
            },
      });
    });

    return () => {
      vigente = false;
    };
  }, [chaveCarregamento, organizacaoAtivaId, estadoInicial, habilitado, deps]);

  const estado: EstadoEstrutura =
    !organizacaoAtivaId && !estadoInicial
      ? { fase: "erro", codigo: "FORBIDDEN", mensagem: SEM_ORGANIZACAO_ATIVA }
      : (estadoInicial ??
        (carregamento?.chave === chaveCarregamento
          ? carregamento.estado
          : { fase: "carregando" }));

  return {
    estado,
    recarregar: () => setVersao((atual) => atual + 1),
  };
}
