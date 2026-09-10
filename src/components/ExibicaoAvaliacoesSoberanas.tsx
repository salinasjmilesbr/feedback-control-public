/**
 * F5-06 (Issue #103) — APRESENTAÇÃO (pura) do acervo soberano de avaliações.
 *
 * Componente SEM estado, sem efeitos e sem I/O: recebe apenas o `Estado` já
 * resolvido pelo controlador. Isso garante que nenhuma regra de negócio,
 * autorização ou acesso a dados vaze para a camada visual — e permite testar a
 * renderização de qualquer estado sem rede, DOM de browser ou efeitos React.
 */

import type { EstadoAvaliacoesSoberanas } from "../services/avaliacoesSoberanas/controladorAvaliacoes.ts";

export interface ExibicaoAvaliacoesSoberanasProps<Registro = unknown> {
  readonly estado: EstadoAvaliacoesSoberanas<Registro>;
}

export function ExibicaoAvaliacoesSoberanas<Registro = unknown>({
  estado,
}: ExibicaoAvaliacoesSoberanasProps<Registro>) {
  const { carregando, erro, acervo } = estado;

  if (carregando && (!acervo || acervo.avaliacoes.length === 0)) {
    return (
      <section data-testid="painel-avaliacoes" aria-busy="true">
        <p>Carregando avaliações…</p>
      </section>
    );
  }

  if (erro) {
    return (
      <section data-testid="painel-avaliacoes" role="alert">
        <p data-testid="painel-erro">{erro}</p>
      </section>
    );
  }

  const avaliacoes = acervo?.avaliacoes ?? [];
  const legado = acervo?.legado ?? [];

  return (
    <section data-testid="painel-avaliacoes">
      <h2>Avaliações no PostgreSQL</h2>
      {avaliacoes.length === 0 ? (
        <p data-testid="avaliacoes-vazio">Nenhuma avaliação nova neste ciclo.</p>
      ) : (
        <ul data-testid="avaliacoes-lista">
          {avaliacoes.map((item) => (
            <li
              key={item.avaliacao.id}
              data-testid="avaliacao-item"
              data-editavel={item.editavel ? "sim" : "nao"}
            >
              <span data-testid="avaliacao-status">{item.avaliacao.status}</span>
              <span data-testid="avaliacao-nota">
                {item.avaliacao.notaMedia === null || item.avaliacao.notaMedia === undefined
                  ? "sem nota"
                  : String(item.avaliacao.notaMedia)}
              </span>
            </li>
          ))}
        </ul>
      )}

      {legado.length > 0 && (
        <div data-testid="acervo-legado">
          <h3>Avaliações legadas (somente leitura)</h3>
          {acervo?.avisoLegado ? <p>{acervo.avisoLegado}</p> : null}
          <ul>
            {legado.map((item, indice) => (
              <li key={indice} data-testid="legado-item" data-editavel="nao">
                {item.motivo}
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}
