import { useState, type ChangeEvent } from "react";
import { useNavigate } from "react-router-dom";
import { useBranding } from "../contexts/BrandingContext";
import { useUsuarioAtual } from "../contexts/UsuarioAtualContext";
import type { BrandingConfig } from "../types/Branding";

function ConfiguracoesAparenciaPage() {
  const navigate = useNavigate();
  const { usuarioAtual } = useUsuarioAtual();
  const { branding, atualizarBranding, restaurarPadrao } = useBranding();
  const [form, setForm] = useState<BrandingConfig>(branding);
  const [mensagem, setMensagem] = useState("");

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
      subtituloSistema: form.subtituloSistema.trim() || "Performance & Feedback Management",
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
                <span>{form.subtituloSistema || "Performance & Feedback Management"}</span>
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
              style={{ borderColor: form.corDestaque, color: form.corDestaque }}
            >
              Ação secundária
            </button>
          </div>
        </section>
      </div>

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
