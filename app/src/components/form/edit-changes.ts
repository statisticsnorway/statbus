import type { TimelinePeriod } from "./field-timeline";

/**
 * What a save over the ticked periods does to each of them (owner 2026-11-16).
 *
 * The form holds one set of values, and Save writes them, with the edit's data
 * source, over every ticked period. A ticked period that holds other values
 * loses them. The timeline shows those losses beside each period, struck out,
 * with the form's value as the addition, and a save that changes any ticked
 * period besides the one the form shows waits for the user's approval
 * (needsApproval).
 */
export interface ColumnChange {
  column: string;
  /** The period's value now. */
  from: unknown;
  /** The form's value, as the form holds it ("" for none). */
  to: string;
}

export interface PeriodChange {
  columns: ColumnChange[];
  /** The data source the save writes over the period's own, or null when they agree. */
  dataSource: { from: number | null; to: number | null } | null;
}

/** A value as the form holds it: the empty string for no value. */
export const asFormValue = (v: unknown) => (v == null ? "" : String(v));

/**
 * Each ticked period the save changes, by index into `periods`, with what it
 * loses. A column the form does not hold is left out: the save does not
 * write it. A period that already holds the form's values is not listed.
 */
export function editChanges(
  periods: readonly TimelinePeriod[],
  ticked: readonly number[],
  formValues: Readonly<Record<string, string>>,
  dataSourceId: string | null | undefined
): Map<number, PeriodChange> {
  const changes = new Map<number, PeriodChange>();
  const toSource = dataSourceId ? Number(dataSourceId) : null;
  for (const index of ticked) {
    const period = periods[index];
    if (!period) continue;
    const columns = Object.keys(period.values).flatMap((column) =>
      column in formValues &&
      asFormValue(period.values[column]) !== formValues[column]
        ? [{ column, from: period.values[column] ?? null, to: formValues[column] }]
        : []
    );
    const dataSource =
      period.data_source_id !== toSource
        ? { from: period.data_source_id, to: toSource }
        : null;
    if (columns.length > 0 || dataSource) changes.set(index, { columns, dataSource });
  }
  return changes;
}

/**
 * The edit's anchor: the ticked period whose values the form holds, against
 * which every other ticked period's changes are shown (owner 2026-11-16). The
 * edit opens anchored on the period the page shows. Ticking more periods keeps
 * the anchor; unticking it moves the anchor to the nearest ticked period, and
 * the form takes that period's values. With nothing ticked there is no anchor
 * (-1): the next tick becomes it, or, when several come at once (Tick all),
 * the period the page shows (`shown`) if it is among them.
 */
export function editAnchor(
  anchor: number,
  ticked: readonly number[],
  shown = -1
): number {
  if (ticked.length === 0) return -1;
  if (ticked.includes(anchor)) return anchor;
  if (anchor < 0) return ticked.includes(shown) ? shown : ticked[0];
  return ticked.reduce((best, i) =>
    Math.abs(i - anchor) < Math.abs(best - anchor) ? i : best
  );
}

/**
 * Whether Save waits for the user's approval: it changes a ticked period other
 * than the anchor, the one whose values the form shows. Changing the anchor
 * alone is an ordinary edit of what the user sees; any other period's changes
 * are only seen in the timeline, so the user approves them there.
 */
export function needsApproval(
  changes: ReadonlyMap<number, PeriodChange>,
  anchor: number
): boolean {
  return [...changes.keys()].some((index) => index !== anchor);
}
