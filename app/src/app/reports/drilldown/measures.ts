import type { DrillDownPoint } from "@/app/reports/types/drill-down";

/**
 * A measure the Drilldown shows: "count", the number of units of the picked type, or a
 * statistical variable's code. Its figure for a region or activity is read from the Drilldown's
 * own answer (statistical_unit_facet_drilldown), whose stats_summary is the canonical merge of the
 * facet rows (jsonb_stats_merge_agg), so the page never adds figures up itself.
 */
export interface Measure {
  key: string;
  label: string;
}

/** The figures of one region or activity, or of the selection as a whole (the answer's `stats`). */
export type Figures = Pick<DrillDownPoint, "count" | "stats_summary">;

/** A measure's figure: the number of units, or the variable's total as its rule makes it (sum or max). */
export function valueOf(figures: Figures, key: string): number {
  if (key === "count") return Number(figures.count ?? 0);
  const m = figures.stats_summary?.[key] as { sum?: number } | undefined;
  return m && typeof m === "object" && m.sum != null ? Number(m.sum) : 0;
}

/** How many units report the variable; none for the number of units itself. */
export function reportingOf(figures: Figures, key: string): number | undefined {
  if (key === "count") return undefined;
  const m = figures.stats_summary?.[key] as { count?: number } | undefined;
  return m && typeof m === "object" && m.count != null ? Number(m.count) : 0;
}
