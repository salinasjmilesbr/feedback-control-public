import { useState, type ChangeEvent } from "react";
import { useNavigate } from "react-router-dom";
import { useBranding } from "../contexts/BrandingContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import type { BrandingConfig } from "../types/Branding";
import type { EscalaAvaliacao } from "../types/EscalaAvaliacao";
import {
  getEscalaAvaliacao,
  getFaixaTexto,
  restaurarEscalaAvaliacao,
  salvarEscalaAvaliacao,
} from "../services/escalaAvaliacaoStorage";

function ConfiguracoesAparenciaPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const { branding, atualizarBranding, restaurarPadrao } = useBranding();
  const [form, setForm] = useState<BrandingConfig>(branding);
  const [mensagem, setMensagem] = useState("");
  const [escala, setEscala] = useState<EscalaAvaliacao>(
    getEscalaAvaliacao()
  );
  const [mensagemEscala, setMensagemEscala] = useState("");

  function salvarEscala() {
    try {
      salvarEscalaAvaliacao(escala);
      setEscala(getEscalaAvaliacao());
      setMensagemEscala("Régua de notas salva com sucesso.");
    } catch (error) {
      setMensagemEscala(
        error instanceof Error
          ? error.message
          : "Não foi possível salvar a régua de notas."
      );
    }
  }

  function restaurarEscala() {
    const confirmar = window.confirm(
      "Restaurar a régua de notas padrão?"
    );
    if (!confirmar) return;

    setEscala(restaurarEscalaAvaliacao());
    setMensagemEscala("Régua de notas restaurada.");
  }

  function atualizarItemEscala(
    nota: number,
    campo: "significado" | "descricao" | "cor",
    valor: string
  ) {
    setEscala((atual) =>
      atual.map((item) =>
        item.nota === nota
          ? {
              ...item,
              [campo]: valor,
              ...(campo === "cor"
                ? { corFundo: `${valor}18` }
                : {}),
            }
          : item
      )
    );
    setMensagemEscala("");
  }

  function atualizarLimiteMinimo(
    nota: number,
    valor: number
  ) {
    setEscala((atual) =>
      atual.map((item) =>
        item.nota === nota
          ? {
              ...item,
              limiteMinimo: valor,
            }
          : item
      )
    );
    setMensagemEscala("");
  }

  if (!usuarioAtual || usuarioAtual.funcao !== "GERENTE") {
    return (
      <div style={{ padding: "30px" }}>
        <h1>Acesso restrito</h1>
        <p>A personalização visual está disponível apenas para gerentes.</p>
      </div>
    );
  }

  function atualizarCampo<K extends keyof BrandingConfig>(
    campo: K,
    valor: BrandingConfig[K]
  ) {
    setForm((atual) => ({ ...atual, [campo]: valor }));
    setMensagem("");
  }

  function carregarLogo(event: ChangeEvent<HTMLInputElement>) {
    const arquivo = event.target.files?.[0];
    if (!arquivo) return;

    if (!arquivo.type.startsWith("image/")) {
      setMensagem("Selecione um arquivo de imagem para o logo.");
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === "string") {
        atualizarCampo("logoDataUrl", reader.result);
      }
    };
    reader.readAsDataURL(arquivo);
  }

  function salvar() {
    atualizarBranding({
      ...form,
      nomeSistema: form.nomeSistema.trim() || "Feedback Control",
      subtituloSistema:
        form.subtituloSistema.trim() ||
        "Performance & Feedback Management",
    });
    setMensagem("Identidade visual salva com sucesso.");
  }

  function restaurar() {
    const confirmar = window.confirm(
      "Restaurar a identidade visual padrão do sistema?"
    );
    if (!confirmar) return;

    restaurarPadrao();
    setForm({
      nomeSistema: "Feedback Control",
      subtituloSistema: "Performance & Feedback Management",
      corPrimaria: "#660099",
      corSecundaria: "#8A2BE2",
      corDestaque: "#0078D4",
      corFundo: "#F6F7FB",
    });
    setMensagem("Identidade visual restaurada.");
  }

  return (
    <div className="branding-page">
      <div className="branding-page__header">
        <div>
          <h1 style={{ margin: 0 }}>Identidade visual</h1>
          <p style={{ margin: "6px 0 0 0", color: "#666" }}>
            Configure a marca exibida no sistema sem alterar regras ou conteúdo.
          </p>
        </div>

        <button
          type="button"
          className="brand-button brand-button--secondary"
          onClick={() => navigate(-1)}
        >
          ← Voltar
        </button>
      </div>

      <div className="branding-grid">
        <section className="branding-card">
          <h2>Produto e identidade</h2>

          <label className="branding-field">
            <span>Nome do sistema</span>
            <input
              value={form.nomeSistema}
              onChange={(event) =>
                atualizarCampo("nomeSistema", event.target.value)
              }
            />
          </label>

          <label className="branding-field">
            <span>Subtítulo do sistema</span>
            <input
              value={form.subtituloSistema}
              onChange={(event) =>
                atualizarCampo("subtituloSistema", event.target.value)
              }
            />
          </label>

          <label className="branding-field">
            <span>Logo</span>
            <input type="file" accept="image/*" onChange={carregarLogo} />
          </label>

          {form.logoDataUrl && (
            <div className="branding-logo-preview">
              <img src={form.logoDataUrl} alt="Prévia do logo" />
              <button
                type="button"
                className="brand-link-button"
                onClick={() => atualizarCampo("logoDataUrl", undefined)}
              >
                Remover logo
              </button>
            </div>
          )}
        </section>

        <section className="branding-card">
          <h2>Paleta da marca</h2>

          {(
            [
              ["corPrimaria", "Cor primária"],
              ["corSecundaria", "Cor secundária"],
              ["corDestaque", "Cor de destaque"],
              ["corFundo", "Fundo da aplicação"],
            ] as Array<[keyof BrandingConfig, string]>
          ).map(([campo, label]) => (
            <label className="branding-color-field" key={campo}>
              <span>{label}</span>
              <div>
                <input
                  type="color"
                  value={String(form[campo] ?? "#000000")}
                  onChange={(event) =>
                    atualizarCampo(
                      campo,
                      event.target.value as BrandingConfig[typeof campo]
                    )
                  }
                />
                <input
                  value={String(form[campo] ?? "")}
                  onChange={(event) =>
                    atualizarCampo(
                      campo,
                      event.target.value as BrandingConfig[typeof campo]
                    )
                  }
                />
              </div>
            </label>
          ))}
        </section>

        <section className="branding-card branding-preview-card">
          <h2>Prévia</h2>
          <div
            className="branding-preview"
            style={{ backgroundColor: form.corFundo }}
          >
            <div className="branding-preview__brand">
              {form.logoDataUrl ? (
                <img src={form.logoDataUrl} alt="Logo" />
              ) : (
                <div
                  className="branding-preview__placeholder"
                  style={{ backgroundColor: form.corPrimaria }}
                >
                  {form.nomeSistema.slice(0, 1).toUpperCase() || "V"}
                </div>
              )}
              <div>
                <strong>{form.nomeSistema || "Feedback Control"}</strong>
                <span>
                  {form.subtituloSistema ||
                    "Performance & Feedback Management"}
                </span>
              </div>
            </div>

            <button
              type="button"
              className="branding-preview__primary"
              style={{ backgroundColor: form.corPrimaria }}
            >
              Ação principal
            </button>

            <button
              type="button"
              className="branding-preview__accent"
              style={{
                borderColor: form.corDestaque,
                color: form.corDestaque,
              }}
            >
              Ação secundária
            </button>
          </div>
        </section>
      </div>

      <section className="score-scale-settings">
        <div className="score-scale-settings__header">
          <div>
            <span>Modelo de avaliação</span>
            <h2>Régua de notas</h2>
            <p>
              Define a faixa, o significado e a referência visual usados em
              todo o Virtus. A classificação de médias decimais respeita os
              limites configurados abaixo.
            </p>
          </div>

          <button
            type="button"
            className="brand-button brand-button--secondary"
            onClick={restaurarEscala}
          >
            Restaurar régua padrão
          </button>
        </div>

        <div className="score-scale-settings__list">
          {escala.map((item) => (
            <article className="score-scale-settings__row" key={item.nota}>
              <div
                className="score-scale-settings__score"
                style={{
                  color: item.cor,
                  backgroundColor: item.corFundo,
                  borderColor: `${item.cor}44`,
                }}
              >
                {item.nota}
              </div>

              <label>
                <span>Faixa da média</span>
                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "110px minmax(105px, 1fr)",
                    gap: "8px",
                    alignItems: "center",
                  }}
                >
                  <input
                    type="number"
                    min={1}
                    max={5}
                    step={0.1}
                    disabled={item.nota === 1}
                    value={item.limiteMinimo}
                    onChange={(event) =>
                      atualizarLimiteMinimo(
                        item.nota,
                        Number(event.target.value)
                      )
                    }
                    aria-label={`Limite inicial da nota ${item.nota}`}
                  />
                  <small
                    style={{
                      color: "#666",
                      fontSize: "11px",
                      lineHeight: 1.3,
                    }}
                  >
                    {getFaixaTexto(item, escala)}
                  </small>
                </div>
              </label>

              <label>
                <span>Significado</span>
                <input
                  value={item.significado}
                  onChange={(event) =>
                    atualizarItemEscala(
                      item.nota,
                      "significado",
                      event.target.value
                    )
                  }
                />
              </label>

              <label className="score-scale-settings__description">
                <span>Descrição</span>
                <textarea
                  value={item.descricao}
                  onChange={(event) =>
                    atualizarItemEscala(
                      item.nota,
                      "descricao",
                      event.target.value
                    )
                  }
                />
              </label>

              <label className="score-scale-settings__color">
                <span>Cor</span>
                <input
                  type="color"
                  value={item.cor}
                  onChange={(event) =>
                    atualizarItemEscala(
                      item.nota,
                      "cor",
                      event.target.value
                    )
                  }
                />
              </label>
            </article>
          ))}
        </div>

        {mensagemEscala && (
          <div className="branding-message">{mensagemEscala}</div>
        )}

        <div className="score-scale-settings__actions">
          <button
            type="button"
            className="brand-button brand-button--primary"
            onClick={salvarEscala}
          >
            Salvar régua de notas
          </button>
        </div>
      </section>

      {mensagem && <div className="branding-message">{mensagem}</div>}

      <div className="branding-actions">
        <button
          type="button"
          className="brand-button brand-button--secondary"
          onClick={restaurar}
        >
          Restaurar padrão
        </button>
        <button
          type="button"
          className="brand-button brand-button--primary"
          onClick={salvar}
        >
          Salvar identidade visual
        </button>
      </div>
    </div>
  );
}

export default ConfiguracoesAparenciaPage;
