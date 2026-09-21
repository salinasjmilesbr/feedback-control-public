import { useEffect, useMemo, useState, type ReactNode } from "react";
import { simulacaoDevPermitida } from "../config/ambiente";
import { getColaboradores } from "../services/colaboradorStorage";
import type { IdentidadeColaborador } from "../types/Colaborador";
import { UsuarioAtualContext } from "./UsuarioAtualContext";
import {
  carregarIdentidadeSoberana,
  colaboradorLegadoDaIdentidade,
  type DependenciasIdentidadeSoberana,
} from "./identidadeSoberana";
import {
  candidatosImpersonacaoDev,
  CHAVE_USUARIO_ATUAL_DEV,
  resolverMatriculaInicialDev,
  selecionarMatriculaDev,
} from "./impersonacaoDev";

/**
 * Contexto de identidade do ator.
 *
 * - Em DEV explícito e SEM tenant ativo (F2-09) a identidade é a impersonação
 *   sintética do seed local; fora disso nenhuma fixture é lida nem gravada.
 * - Com tenant autenticado (#333) a identidade vem do VÍNCULO soberano
 *   (ver identidadeSoberana.ts): estrutura_autorizacao.collaborator_id + a
 *   PRÓPRIA entrada em estrutura_pessoal. Não há casamento por e-mail, não é
 *   exigida ocupação/hierarquia e MATRÍCULA NÃO É REQUISITO para reconhecer o
 *   usuário; a projeção legada (usuarioAtualLegado) só existe quando a matrícula
 *   é informada.
 * - O Supabase Auth permanece soberano e separado: nada aqui altera auth.uid(),
 *   JWT, sessão nem participa de autorização server-side.
 */
export function UsuarioAtualProvider({
  children,
  simulacaoDev = simulacaoDevPermitida,
  organizacaoAtivaId = null,
  deps,
}: {
  children: ReactNode;
  /** F2-09: permite injetar o gate nos testes; em runtime usa a config central. */
  simulacaoDev?: boolean;
  /** Tenant autenticado ativo; impede contaminar sua apresentação com fixture global. */
  organizacaoAtivaId?: string | null;
  /** Injeção de teste das leituras soberanas da identidade (#333). */
  deps?: DependenciasIdentidadeSoberana;
}) {
  const simulacaoDevDaSessao = simulacaoDev && !organizacaoAtivaId;
  const [depsInjetadas] = useState<DependenciasIdentidadeSoberana>(() => deps ?? {});
  const usuariosDev = useMemo(
    () =>
      simulacaoDevDaSessao
        ? candidatosImpersonacaoDev(true, getColaboradores())
        : [],
    [simulacaoDevDaSessao]
  );
  const [leituraSoberana, setLeituraSoberana] = useState<{
    chave: string;
    usuario: IdentidadeColaborador | undefined;
  } | null>(null);
  const chaveSoberana = organizacaoAtivaId ?? "sem-organizacao";

  useEffect(() => {
    if (simulacaoDevDaSessao || !organizacaoAtivaId) return;
    let vigente = true;
    void carregarIdentidadeSoberana(organizacaoAtivaId, depsInjetadas).then(
      (usuario) => {
        if (vigente) setLeituraSoberana({ chave: chaveSoberana, usuario });
      }
    );
    return () => {
      vigente = false;
    };
  }, [chaveSoberana, organizacaoAtivaId, simulacaoDevDaSessao, depsInjetadas]);

  const usuarioSoberano =
    leituraSoberana?.chave === chaveSoberana ? leituraSoberana.usuario : undefined;
  const usuarioSoberanoLegado = usuarioSoberano
    ? colaboradorLegadoDaIdentidade(usuarioSoberano)
    : undefined;
  const usuariosDisponiveis = organizacaoAtivaId
    ? usuarioSoberanoLegado
      ? [usuarioSoberanoLegado]
      : []
    : usuariosDev;

  const [matriculaAtual, setMatriculaAtual] = useState<number | undefined>(() => {
    if (!simulacaoDevDaSessao) return undefined;
    const salva = Number(localStorage.getItem(CHAVE_USUARIO_ATUAL_DEV) ?? "");
    return resolverMatriculaInicialDev(
      Number.isFinite(salva) ? salva : undefined,
      usuariosDev
    );
  });

  const usuarioAtual = organizacaoAtivaId
    ? usuarioSoberano
    : usuariosDisponiveis.find((usuario) => usuario.matricula === matriculaAtual);
  // Projeção legada para os domínios que ainda exigem matrícula numérica.
  const usuarioAtualLegado = usuarioAtual
    ? colaboradorLegadoDaIdentidade(usuarioAtual)
    : undefined;

  function selecionarUsuario(matricula: number) {
    const proxima = selecionarMatriculaDev(simulacaoDevDaSessao, matricula);
    if (proxima === undefined) return;
    setMatriculaAtual(proxima);
    localStorage.setItem(CHAVE_USUARIO_ATUAL_DEV, String(proxima));
  }

  return (
    <UsuarioAtualContext.Provider
      value={{
        usuarioAtual,
        usuarioAtualLegado,
        usuariosDisponiveis,
        selecionarUsuario,
        simulacaoDevAtiva: simulacaoDevDaSessao,
      }}
    >
      {children}
    </UsuarioAtualContext.Provider>
  );
}
