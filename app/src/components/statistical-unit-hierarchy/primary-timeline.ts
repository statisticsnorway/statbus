import type { TimelinePeriod } from "@/components/form/field-timeline";

/** One row of a parent's child units (establishments of a legal unit, or legal units of an enterprise). */
export interface PrimaryRow {
  id: number;
  name: string | null;
  valid_from: string;
  valid_to: string;
  primary: boolean | null;
}

/**
 * Who is primary when (2f4c0z): the parent's timeline of its primary unit, one period per stretch
 * with the same primary, oldest first, as the Set as primary dialog's Timeline view draws it. A
 * stretch where no unit is primary is a period of its own with no primary (values.primary null).
 * Dates are ISO yyyy-mm-dd, valid_to inclusive ("infinity" for no end).
 */
export function primaryTimeline(rows: readonly PrimaryRow[]): TimelinePeriod[] {
  const edges = new Set<string>();
  for (const r of rows) {
    edges.add(r.valid_from);
    if (r.valid_to !== "infinity") edges.add(dayAfter(r.valid_to));
  }
  const starts = [...edges].sort();
  const pieces: { from: string; to: string; name: string | null }[] = [];
  starts.forEach((from, i) => {
    const next = starts[i + 1];
    const to = next ? dayBefore(next) : "infinity";
    const live = rows.filter((r) => r.valid_from <= from && (r.valid_to === "infinity" || r.valid_to >= from));
    if (live.length === 0) return;
    const primary = live.find((r) => r.primary);
    pieces.push({ from, to, name: primary ? (primary.name ?? `#${primary.id}`) : null });
  });
  const periods: TimelinePeriod[] = [];
  for (const p of pieces) {
    const last = periods[periods.length - 1];
    if (last && last.values.primary === p.name && last.valid_to !== "infinity" && dayAfter(last.valid_to) === p.from) {
      last.valid_to = p.to;
      continue;
    }
    periods.push({
      valid_from: p.from,
      valid_to: p.to,
      values: { primary: p.name },
      data_source_id: null,
      edit_comment: null,
      edit_by_user_id: null,
      edit_at: null,
    });
  }
  return periods;
}

function shift(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
const dayAfter = (date: string) => shift(date, 1);
const dayBefore = (date: string) => shift(date, -1);
