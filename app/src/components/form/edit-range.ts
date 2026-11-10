/**
 * The default period an edit applies to: the stretch where the value the user
 * sees is valid, bounded by the selected time frame.
 *
 * A unit's timeline is a series of rows; a value can span several consecutive
 * rows (another column changing splits it) and differ in rows before or after.
 * The stretch is the run of consecutive rows holding the same value that covers
 * the selected context's start, or the first such run inside the context. The
 * edit is that stretch intersected with the context, so an edit changes exactly
 * what the user saw, and a unit born inside the context starts the edit at its
 * birth (STATBUS-604). The database's for-portion-of views apply it to where the
 * unit exists.
 *
 * Dates are ISO yyyy-mm-dd, valid_to inclusive, "infinity" for open-ended.
 */
export interface TimelineRow<V> {
  valid_from: string;
  valid_to: string;
  value: V;
}

export interface TimeFrameRange {
  valid_from: string;
  valid_to: string;
}

export interface EditRange {
  validFrom: string;
  validTo: string;
}

const INFINITY = "infinity";

// Inclusive-end dates compare as ISO strings; "infinity" sorts after any date.
function before(a: string, b: string): boolean {
  if (a === b) return false;
  if (a === INFINITY) return false;
  if (b === INFINITY) return true;
  return a < b;
}
const maxDate = (a: string, b: string) => (before(a, b) ? b : a);
const minDate = (a: string, b: string) => (before(a, b) ? a : b);

function dayAfter(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

export function defaultEditRange<V>(
  rows: TimelineRow<V>[],
  shownValue: V,
  context: TimeFrameRange,
  sameValue: (a: V, b: V) => boolean = (a, b) => a === b
): EditRange {
  const fallback = { validFrom: context.valid_from, validTo: context.valid_to };
  const ordered = [...rows].sort((a, b) =>
    before(a.valid_from, b.valid_from) ? -1 : a.valid_from === b.valid_from ? 0 : 1
  );

  // Runs of consecutive (adjacent) rows holding the shown value.
  const runs: EditRange[] = [];
  for (const row of ordered) {
    if (!sameValue(row.value, shownValue)) continue;
    const last = runs[runs.length - 1];
    if (last && last.validTo !== INFINITY && dayAfter(last.validTo) === row.valid_from) {
      last.validTo = row.valid_to;
    } else {
      runs.push({ validFrom: row.valid_from, validTo: row.valid_to });
    }
  }

  const overlaps = (r: EditRange) =>
    !before(r.validTo, context.valid_from) && !before(context.valid_to, r.validFrom);
  const covering =
    runs.find((r) => !before(context.valid_from, r.validFrom) && overlaps(r)) ??
    runs.find(overlaps);
  if (!covering) return fallback;

  return {
    validFrom: maxDate(covering.validFrom, context.valid_from),
    validTo: minDate(covering.validTo, context.valid_to),
  };
}
