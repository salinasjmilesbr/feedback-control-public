import { describe, expect, it } from "vitest";
import catalogoF401 from "../../../supabase/migrations/20260908000001_authorization_system_catalog.sql?raw";
import catalogoF504 from "../../../supabase/migrations/20260910000000_f5_04_catalog_reconciliation.sql?raw";
import {
  CAPABILIDADES_CANONICAS,
  CAPABILIDADES_DEPRECIADAS,
  CAPABILIDADES_NAO_CONCEDIVEIS_VIA_ROLE,
  capabilityCanonica,
  capabilityConhecida,
} from "./catalogoCapabilities";

/**
 * F5-04 (D14): teste de paridade DB↔TS — o conjunto de códigos do catálogo DB
 * (não-deprecados) deve ser EXATAMENTE o espelho TS canônico. Extrai os códigos
 * das migrations de catálogo (F4-01 + F5-04) e compara com a união canônica do
 * engine. Código desconhecido/deprecado ⇒ DENY (fail-closed, sem tradução
 * fuzzy/permissiva).
 */

/** Captura o campo `code` (2º literal) dos INSERTs de `public.capabilities`. */
function extrairCodigosDoCatalogo(sql: string): Set<string> {
  const codigos = new Set<string>();
  // Tuplas: ('<uuid>', '<code>', 'Name', ...). Captura apenas o 2º campo.
  const regex =
    /'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',\s*'([a-z_]+\.[a-z_.]+)'/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(sql)) !== null) {
    codigos.add(match[1]);
  }
  return codigos;
}

describe("F5-04 — paridade de catálogo DB↔TS (D14)", () => {
  it("o espelho TS canônico tem 29 códigos únicos", () => {
    expect(CAPABILIDADES_CANONICAS).toHaveLength(29);
    expect(new Set(CAPABILIDADES_CANONICAS).size).toBe(29);
  });

  it("catálogo DB (não-deprecado) == união canônica do engine", () => {
    const codigosDb = new Set<string>();
    for (const sql of [catalogoF401, catalogoF504]) {
      for (const code of extrairCodigosDoCatalogo(sql)) codigosDb.add(code);
    }

    const deprecadas = new Set(CAPABILIDADES_DEPRECIADAS);
    const canonicasDb = [...codigosDb].filter((c) => !deprecadas.has(c)).sort();

    expect(canonicasDb).toEqual([...CAPABILIDADES_CANONICAS].sort());
  });

  it("códigos deprecados não pertencem ao catálogo canônico", () => {
    const canonicas = new Set<string>(CAPABILIDADES_CANONICAS);
    for (const code of CAPABILIDADES_DEPRECIADAS) {
      expect(canonicas.has(code)).toBe(false);
    }
  });

  it("capabilities de controle/C-D são canônicas mas não-concedíveis por role (D15)", () => {
    const canonicas = new Set<string>(CAPABILIDADES_CANONICAS);
    expect(CAPABILIDADES_NAO_CONCEDIVEIS_VIA_ROLE).toEqual([
      "membership.manage",
      "access_role.manage",
      "exceptional_access.grant",
      "pilot_full_access.grant",
    ]);
    for (const code of CAPABILIDADES_NAO_CONCEDIVEIS_VIA_ROLE) {
      expect(canonicas.has(code)).toBe(true);
    }
  });
});

describe("F5-04 — fail-closed do vocabulário (D14)", () => {
  it("código canônico conhecido resolve para si mesmo", () => {
    expect(capabilityCanonica("collaborator.read")).toBe("collaborator.read");
    expect(capabilityCanonica("cycle.cancel")).toBe("cycle.cancel");
    expect(capabilityConhecida("evaluation.write")).toBe(true);
  });

  it("código deprecado ⇒ DENY (sem tradução fuzzy/permissiva)", () => {
    expect(capabilityCanonica("collaborator.manage")).toBeUndefined();
    expect(capabilityCanonica("observation.write")).toBeUndefined();
  });

  it("código desconhecido ⇒ DENY (fail-closed)", () => {
    expect(capabilityCanonica("nao.existe")).toBeUndefined();
    expect(capabilityCanonica("hacker.grant")).toBeUndefined();
    expect(capabilityConhecida("qualquer.coisa")).toBe(false);
  });

  it("código de controle é conhecido (mas nunca concedível por role)", () => {
    expect(capabilityCanonica("membership.manage")).toBe("membership.manage");
    expect(capabilityConhecida("exceptional_access.grant")).toBe(true);
  });
});
