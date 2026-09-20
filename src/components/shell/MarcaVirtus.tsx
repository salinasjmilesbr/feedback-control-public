import { NOME_VIRTUS, SIMBOLO_VIRTUS } from "./identidadeVirtus";

/**
 * Issue #317 (Fase 2) — MARCA OFICIAL no shell (`[V oficial] VIRTUS · contexto`).
 *
 * Apresentação pura: não lê sessão, organização, tema nem autorização. O rótulo
 * de contexto é sempre recebido pronto de quem conhece o contexto (ver
 * `ShellVirtus`), o que impede a marca de "descobrir" tenant por conta própria.
 *
 * O símbolo é decorativo aqui (`alt=""` + `aria-hidden`): o nome acessível é o
 * wordmark VIRTUS ao lado, e repetir "Virtus" seria ruído para leitor de tela.
 */
function MarcaVirtus({ contexto }: { contexto?: string }) {
  return (
    <div className="virtus-shell__brand">
      <img
        className="virtus-shell__symbol"
        src={SIMBOLO_VIRTUS}
        alt=""
        aria-hidden="true"
      />
      <span className="virtus-shell__wordmark">{NOME_VIRTUS}</span>
      {contexto ? (
        <>
          <span className="virtus-shell__separator" aria-hidden="true">
            ·
          </span>
          <span className="virtus-shell__context">{contexto}</span>
        </>
      ) : null}
    </div>
  );
}

export default MarcaVirtus;
