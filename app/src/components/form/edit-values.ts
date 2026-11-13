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
}

const same = (a: unknown, b: unknown) =>
  JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

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
    return { values: { ...chosen[0].values }, dataSourceId: null, differing: [] };
  const [first, ...rest] = valued;
  const newest = valued[valued.length - 1];
  const values: Record<string, unknown> = {};
  const differing: string[] = [];
  for (const [column, value] of Object.entries(first.values)) {
    if (!rest.every((p) => same(p.values[column], value)))
      differing.push(column);
    values[column] = newest.values[column] ?? null;
  }
  const dataSourceId = rest.every(
    (p) => p.data_source_id === first.data_source_id
  )
    ? first.data_source_id
    : null;
  return { values, dataSourceId, differing };
}
