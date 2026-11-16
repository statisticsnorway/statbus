import type { TimelinePeriod } from "./field-timeline";

/**
 * The values an edit over the ticked periods starts from (owner 2026-11-13).
 *
 * A save writes every field of the form over the whole ticked stretch, so the
 * form must start from that stretch's own values, not from the value shown on
 * the page (the Live frame's). Otherwise a field the user did not touch is
 * overwritten with another period's value.
 *
 * A column whose value is the same in every ticked period starts with it. A
 * column whose value differs between them starts with the newest ticked
 * period's value and is named in `differing`: saving gives it that one value
 * over the whole stretch, which the form tells the user. Starting it empty
 * instead would erase it. The data source is kept when all ticked periods
 * share it.
 */
export interface EditStartValues {
  values: Record<string, unknown>;
  dataSourceId: number | null;
  differing: string[];
  /**
   * Each differing column's values over the ticked stretch, as runs of equal
   * value, oldest first: what the form shows instead of one value, and what a
   * save setting the column replaces (owner 2026-11-16).
   */
  differences: Record<string, ValueRun[]>;
  /** The data sources over the ticked stretch when they differ, as runs; empty when they agree. */
  dataSourceRuns: ValueRun[];
}

/** A stretch of consecutive ticked periods sharing one value. */
export interface ValueRun {
  value: unknown;
  valid_from: string;
  valid_to: string;
}

const same = (a: unknown, b: unknown) =>
  JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

function runs(periods: readonly TimelinePeriod[], valueOf: (p: TimelinePeriod) => unknown): ValueRun[] {
  const out: ValueRun[] = [];
  for (const p of periods) {
    const value = valueOf(p) ?? null;
    const last = out[out.length - 1];
    if (last && same(last.value, value)) last.valid_to = p.valid_to;
    else out.push({ value, valid_from: p.valid_from, valid_to: p.valid_to });
  }
  return out;
}

export function editStartValues(
  periods: readonly TimelinePeriod[],
  ticked: readonly number[]
): EditStartValues | null {
  const chosen = ticked.map((i) => periods[i]).filter(Boolean);
  if (chosen.length === 0) return null;
  // A hole (withGaps) has no value: the edit fills it, so it neither starts a
  // value nor makes one differ. Only ticked holes: the edit starts empty.
  const valued = chosen.filter((p) => !p.empty);
  if (valued.length === 0)
    return { values: { ...chosen[0].values }, dataSourceId: null, differing: [], differences: {}, dataSourceRuns: [] };
  const [first, ...rest] = valued;
  const newest = valued[valued.length - 1];
  const values: Record<string, unknown> = {};
  const differing: string[] = [];
  const differences: Record<string, ValueRun[]> = {};
  for (const [column, value] of Object.entries(first.values)) {
    if (!rest.every((p) => same(p.values[column], value))) {
      differing.push(column);
      differences[column] = runs(valued, (p) => p.values[column]);
    }
    values[column] = newest.values[column] ?? null;
  }
  const sourcesAgree = rest.every(
    (p) => p.data_source_id === first.data_source_id
  );
  const dataSourceId = sourcesAgree ? first.data_source_id : null;
  const dataSourceRuns = sourcesAgree ? [] : runs(valued, (p) => p.data_source_id);
  return { values, dataSourceId, differing, differences, dataSourceRuns };
}
