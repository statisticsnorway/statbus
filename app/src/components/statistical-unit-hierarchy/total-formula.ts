/**
 * The formula after a legal unit's total (Σ) in the Links tree (s465ff): how the total was made from
 * the legal unit's own value and its counted establishments' values.
 *
 * The database decides the total (public.jsonb_stats_lu_es_rollup by stat_definition.lu_es_rollup):
 * `sum` adds the two levels, `max` takes the larger. This only writes it out, so it reads the stored
 * total and names the rule that gives it: "364 + 5" when own + establishments equals the total,
 * "max(364, 5)" when the larger of the two does. With no counted establishment value the total is the
 * legal unit's own value and there is nothing to explain.
 */
export function legalUnitTotalFormula(
  own: number,
  total: number,
  establishmentValues: readonly number[]
): string | undefined {
  if (establishmentValues.length === 0) return undefined;
  const parts = establishmentValues.reduce((acc, v) => acc + v, 0);
  const n = (v: number) => v.toLocaleString("en-US").replace(/,/g, " ");
  if (own + parts === total) return `${n(own)} + ${n(parts)}`;
  if (Math.max(own, parts) === total) return `max(${n(own)}, ${n(parts)})`;
  return undefined;
}

/** A legal unit's counted establishments' values of one variable, as the Links tree holds them. */
export function establishmentValues(
  unit: { establishment?: ReadonlyArray<{ status?: { used_for_counting?: boolean | null } | null; stat_for_unit?: ReadonlyArray<{ stat_definition_id: number | null; value_int?: number | null; value_float?: number | null }> }> },
  statDefinitionId: number
): number[] {
  return (unit.establishment ?? [])
    .filter((es) => es.status?.used_for_counting !== false)
    .flatMap((es) => {
      const stat = es.stat_for_unit?.find((s) => s.stat_definition_id === statDefinitionId);
      const v = stat?.value_int ?? stat?.value_float;
      return typeof v === "number" ? [v] : [];
    });
}
