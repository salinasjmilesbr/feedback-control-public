/**
 * F6 Incremento 1 — CONTRATO ESTÁTICO da migration das projeções de leitura.
 *
 * SQL/Edge real é PENDENTE de certificação neste ambiente (sem PostgreSQL
 * descartável autorizado). Este teste trava as invariantes CONTRATUAIS do SQL:
 * projeções separadas, ausência recursiva de voto/identidade do colegiado na
 * projeção SELF, agregado do colegiado por SUBCRITÉRIO, janela de transparência
 * e privilégio mínimo (service_role).
 */
import { describe, expect, it } from "vitest";
import migration from "../../supabase/migrations/20261027000000_f6_inc1_fronteiras_leitura.sql?raw";

describe("migration do Incremento 1 — projeções de leitura", () => {
  it("define as DUAS projeções separadas com assinatura canônica", () => {
    expect(migration).toContain("create or replace function public.evaluation_painel_participantes");
    expect(migration).toContain("create or replace function public.evaluation_leitura_avaliado");
    expect(migration).toContain("p_evaluation_id uuid");
    expect(migration).toContain("p_actor_user_profile_id uuid");
  });

  it("privilegio mínimo: revoga de public/anon/authenticated e concede só a service_role", () => {
    for (const fn of [
      "evaluation_painel_participantes(uuid, uuid)",
      "evaluation_leitura_avaliado(uuid, uuid)",
    ]) {
      expect(migration).toContain(`revoke all on function public.${fn}`);
      expect(migration).toContain(`grant execute on function public.${fn}`);
    }
    expect(migration).not.toMatch(/grant execute[\s\S]{0,80}to (anon|authenticated)/);
  });

  it("a projeção COLETIVA entrega identidade/papel/notas e progresso FACTUAL", () => {
    expect(migration).toContain("'participantes'");
    expect(migration).toContain("'notas'");
    expect(migration).toContain("'comentarios'");
    expect(migration).toContain("'feedbacksFinais'");
    expect(migration).toContain("'progressoFactual'");
    // α: é apenas contagem — a migration DOCUMENTA a fronteira, mas não traz a
    // lógica de completude/pendência oficial (isso é o Incremento 2).
    expect(migration).not.toContain("evaluation_pendencias_calcular");
    expect(migration).not.toMatch(/NOTA_FALTANTE|PARTICIPANTE_OBRIGATORIO_AUSENTE/);
  });

  it("a projeção SELF mantém a janela CONCLUIDA e a restrição ao avaliado", () => {
    expect(migration).toContain("restrita ao colaborador avaliado");
    expect(migration).toContain("avaliacao ainda nao visivel ao avaliado");
    expect(migration).toMatch(/status <> 'CONCLUIDA'/);
  });

  it("R3/prioridade 5: NENHUMA lista de identidade do colegiado na projeção SELF", () => {
    // O vazamento anterior emitia `'colegiado'` com `colaborador_id`.
    expect(migration).not.toMatch(/'colegiado',\s*coalesce/);
    expect(migration).not.toContain("jsonb_build_object('colaborador_id', p.collaborator_id)");
    // E o agregado do colegiado existe, por SUBCRITÉRIO.
    expect(migration).toContain("'colegiado_agregado'");
    expect(migration).toMatch(/'colegiado_agregado'[\s\S]{0,120}subcriterion_id/);
  });

  it("R3: blocos individuais de gerente e coordenador, com ausência preservada", () => {
    expect(migration).toContain("'gestao'");
    expect(migration).toContain("'GESTAO_CADEIA'");
    expect(migration).toContain("'GESTAO_DIRETA'");
    expect(migration).toContain("'feedback_final'");
    // Ausência do papel não vira zero: o agregado do colegiado é `avg` sobre os
    // votos EXISTENTES e as parcelas só existem com votos.
    expect(migration).toMatch(/avg\(sc\.nota\) as nota/);
  });

  it("o agregado do colegiado usa a MESMA parcela do cálculo oficial", () => {
    // Colegiado = UMA parcela: média dos votos válidos dos membros vigentes,
    // respeitando `contributes_to_score` da configuração CONGELADA.
    expect(migration).toContain("p.role_type = 'COLEGIADO'");
    expect(migration).toContain("pcr.contributes_to_score");
    expect(migration).toContain("p.valid_from <= v_instante");
    expect(migration).toContain("p.valid_to is null or p.valid_to > v_instante");
  });

  it("não antecipa o Incremento 2 (sem completude/pendência por ocorrência)", () => {
    expect(migration).not.toMatch(/NOTA_FALTANTE|PARTICIPANTE_OBRIGATORIO_AUSENTE/);
    expect(migration).not.toMatch(/RASCUNHO\s*->\s*PRONTA|regress/i);
  });

  it("F1 — comentarios e feedbacksFinais excluem COLEGIADO na PRÓPRIA projeção", () => {
    const trecho = (inicio: string): string => {
      const de = migration.indexOf(inicio);
      expect(de, inicio).toBeGreaterThanOrEqual(0);
      const ate = migration.indexOf("), '[]'::jsonb),", de);
      expect(ate, inicio).toBeGreaterThan(de);
      return migration.slice(de, ate);
    };

    // O SQL executável não pode conter COLEGIADO nos dois blocos (o texto pode
    // mencioná-lo apenas na DOCUMENTAÇÃO da fronteira).
    const semComentarios = (texto: string): string =>
      texto
        .split("\n")
        .filter((linha) => !linha.trim().startsWith("--"))
        .join("\n");

    // Endurecimento EXPLÍCITO: a projeção deixa de depender do invariante de
    // escrita (R1) e recusa COLEGIADO mesmo diante de dado histórico/anômalo.
    for (const inicio of ["'comentarios', coalesce((", "'feedbacksFinais', coalesce(("]) {
      const bloco = trecho(inicio);
      const sql = semComentarios(bloco);
      expect(sql, inicio).toContain("p.role_type in ('GESTAO_CADEIA', 'GESTAO_DIRETA')");
      expect(sql, inicio).not.toContain("COLEGIADO");
    }

    // Contraprova: as NOTAS individuais continuam incluindo os colegiados (R2) —
    // o filtro do F1 não pode ser aplicado onde a identidade é legítima.
    const notas = semComentarios(trecho("'notas', coalesce(("));
    expect(notas).not.toContain("role_type in ('GESTAO_CADEIA', 'GESTAO_DIRETA')");
  });
});
