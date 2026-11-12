import type { TimeFrame } from "@/lib/time-frame";

/**
 * A field's timeline: its values over time for one unit, as the edit form's
 * Timeline view shows them. One period per stretch where the field's value
 * (all its columns, for a field group such as an address) stayed the same,
 * oldest first. Rows that differ only in other columns merge; a gap where the
 * unit did not exist splits. An edit picks one stretch of periods and gets
 * that stretch's dates (selectionRange).
 *
 * Dates are ISO yyyy-mm-dd, valid_to inclusive, "infinity" for open-ended.
 */
export interface TimelineSourceRow {
  valid_from: string;
  valid_to: string;
  data_source_id?: number | null;
  edit_comment?: string | null;
  edit_by_user_id?: number | null;
  edit_at?: string | null;
  [column: string]: unknown;
}

export interface TimelinePeriod {
  valid_from: string;
  valid_to: string;
  /** The field's columns and their value in this period. */
  values: Record<string, unknown>;
  /** Where the period's latest change came from: its newest row's metadata. */
  data_source_id: number | null;
  edit_comment: string | null;
  edit_by_user_id: number | null;
  edit_at: string | null;
}

const INFINITY = "infinity";

function dayAfter(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

// ISO dates compare as strings; "infinity" is after every date.
const endsBefore = (end: string, start: string) =>
  end !== INFINITY && end < start;

export function fieldTimeline(
  rows: readonly TimelineSourceRow[],
  columns: readonly string[]
): TimelinePeriod[] {
  const ordered = [...rows].sort((a, b) =>
    a.valid_from < b.valid_from ? -1 : a.valid_from > b.valid_from ? 1 : 0
  );
  const key = (r: TimelineSourceRow) =>
    JSON.stringify(columns.map((c) => r[c] ?? null));
  const periods: (TimelinePeriod & { key: string })[] = [];
  for (const row of ordered) {
    const last = periods[periods.length - 1];
    const adjacent =
      last &&
      last.valid_to !== INFINITY &&
      dayAfter(last.valid_to) === row.valid_from;
    const meta = {
      data_source_id: row.data_source_id ?? null,
      edit_comment: row.edit_comment ?? null,
      edit_by_user_id: row.edit_by_user_id ?? null,
      edit_at: row.edit_at ?? null,
    };
    if (adjacent && last.key === key(row)) {
      last.valid_to = row.valid_to;
      if ((row.edit_at ?? "") >= (last.edit_at ?? ""))
        Object.assign(last, meta);
      continue;
    }
    periods.push({
      key: key(row),
      valid_from: row.valid_from,
      valid_to: row.valid_to,
      values: Object.fromEntries(columns.map((c) => [c, row[c] ?? null])),
      ...meta,
    });
  }
  return periods.map(({ key: _key, ...period }) => period);
}

/**
 * The frames a period reaches into, as markers on its row: the live frame,
 * relative frames and fixed frames, newest first. A fixed frame equal to a
 * relative frame (equals_frame_ident) is named once, by the relative frame.
 */
export function framesOverlapping(
  period: Pick<TimelinePeriod, "valid_from" | "valid_to">,
  frames: readonly TimeFrame[]
): TimeFrame[] {
  return frames.filter(
    (f) =>
      !f.equals_frame_ident &&
      f.valid_from != null &&
      f.valid_to != null &&
      !endsBefore(f.valid_to, period.valid_from) &&
      !endsBefore(period.valid_to, f.valid_from)
  );
}

/**
 * The dates an edit over the selected periods applies to: from the earliest
 * selected period's start to the latest one's end. One stretch, so periods
 * between two selected ones are covered too.
 */
export function selectionRange(
  periods: readonly TimelinePeriod[],
  selected: readonly number[]
): { validFrom: string; validTo: string } | null {
  if (selected.length === 0) return null;
  const first = Math.min(...selected);
  const last = Math.max(...selected);
  return {
    validFrom: periods[first].valid_from,
    validTo: periods[last].valid_to,
  };
}

/**
 * A stretch of the timeline inside one frame: the timeline drawn as frames
 * (left) holding the field's values (right). Periods split at frame
 * boundaries; `period` is the timeline period the stretch belongs to and
 * `first` marks its first stretch, where the value is written. Time outside
 * every frame (before the oldest fixed frame) has frame null. A fixed frame
 * equal to a relative frame is counted once, as the relative frame.
 */
export interface FrameSegment {
  valid_from: string;
  valid_to: string;
  frame: TimeFrame | null;
  period: number;
  first: boolean;
}

function dayBefore(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

export function frameSegments(
  periods: readonly TimelinePeriod[],
  frames: readonly TimeFrame[]
): FrameSegment[] {
  const ordered = frames
    .filter(
      (f) => !f.equals_frame_ident && f.valid_from != null && f.valid_to != null
    )
    .sort((a, b) => (a.valid_from! < b.valid_from! ? -1 : 1));
  const segments: FrameSegment[] = [];
  periods.forEach((p, index) => {
    let from = p.valid_from;
    let first = true;
    for (;;) {
      const frame =
        ordered.find(
          (f) => f.valid_from! <= from && !endsBefore(f.valid_to!, from)
        ) ?? null;
      const next = ordered.find((f) => f.valid_from! > from);
      const frameEnd = frame
        ? frame.valid_to!
        : next
          ? dayBefore(next.valid_from!)
          : INFINITY;
      const to = endsBefore(frameEnd, p.valid_to) ? frameEnd : p.valid_to;
      segments.push({
        valid_from: from,
        valid_to: to,
        frame,
        period: index,
        first,
      });
      first = false;
      if (to === p.valid_to || to === INFINITY) break;
      from = dayAfter(to);
    }
  });
  return segments;
}

/**
 * The selection after the user ticks or unticks a period's box. The selection
 * is always one unbroken stretch, as the edit's dates are: ticking extends it
 * to the ticked period; unticking an end shrinks it by one; unticking a
 * period inside keeps the part before it.
 */
export function toggleSelection(
  selected: readonly number[],
  index: number
): number[] {
  if (selected.length === 0) return [index];
  const first = Math.min(...selected);
  const last = Math.max(...selected);
  const range = (a: number, b: number) =>
    Array.from({ length: b - a + 1 }, (_, i) => a + i);
  if (index < first || index > last)
    return range(Math.min(first, index), Math.max(last, index));
  if (first === last) return [];
  if (index === first) return range(first + 1, last);
  if (index === last) return range(first, last - 1);
  return range(first, index - 1);
}

/**
 * The periods an edit's dates cover, so the Timeline view opens with the
 * edit's current stretch ticked. validTo null is open-ended.
 */
export function periodsInRange(
  periods: readonly TimelinePeriod[],
  validFrom: string | null | undefined,
  validTo: string | null | undefined
): number[] {
  if (!validFrom) return [];
  const end = validTo || INFINITY;
  return periods.flatMap((p, i) =>
    !endsBefore(p.valid_to, validFrom) && !endsBefore(end, p.valid_from)
      ? [i]
      : []
  );
}

/** The period holding the value on a date, e.g. the selected frame's valid_on. */
export function periodOn(
  periods: readonly TimelinePeriod[],
  date: string | null | undefined
): number {
  if (!date) return -1;
  return periods.findIndex(
    (p) => p.valid_from <= date && !endsBefore(p.valid_to, date)
  );
}

/**
 * Whether Edit opens in the Timeline view: the frame being edited holds more
 * than one value of the field. When one value covers the whole frame (it may
 * run on before or after it), the frame is the edit and the Simple view says
 * it all; when the frame holds a change, which stretch to change is the
 * question, and the timeline shows it.
 */
export function opensInTimeline(
  periods: readonly TimelinePeriod[],
  frame: Pick<TimeFrame, "valid_from" | "valid_to"> | null | undefined
): boolean {
  if (!frame?.valid_from || !frame.valid_to) return false;
  const inFrame = periods.filter(
    (p) =>
      !endsBefore(p.valid_to, frame.valid_from!) &&
      !endsBefore(frame.valid_to!, p.valid_from)
  );
  return inFrame.length > 1;
}

/** One line of the timeline as drawn: a segment, or a fold standing for hidden values. */
export type VisibleSegment =
  | { kind: "segment"; segment: FrameSegment; index: number }
  | {
      kind: "fold";
      frame: TimeFrame | null;
      hidden: number;
      periods: number[];
    };

/**
 * The frames holding more than maxPerFrame values, by ident ("none" for time
 * before the oldest frame): the frames visibleSegments folds, which expand
 * all opens and collapse all folds.
 */
export function foldableFrames(
  segments: readonly FrameSegment[],
  maxPerFrame: number
): string[] {
  const counts = new Map<string, number>();
  for (const s of segments) {
    const ident = s.frame?.ident ?? "none";
    counts.set(ident, (counts.get(ident) ?? 0) + 1);
  }
  return [...counts].filter(([, n]) => n > maxPerFrame).map(([ident]) => ident);
}

/** A crowded frame, folded, shows this many of its values (visibleSegments). */
const FOLDED_VALUES = 2;

/**
 * The timeline with crowded frames folded, so a field with many changes stays
 * readable. A frame holding up to maxPerFrame values shows them all; a frame
 * holding more shows two (FOLDED_VALUES): the values in `keep` first (the
 * shown value, then ticked ones), else the newest and the oldest. The runs
 * between fold into one line saying how many are hidden; the user unfolds a
 * frame by naming it in `expanded`. An unfolded frame shows all its values,
 * and unfoldedRuns says which of them would fold again.
 */
export function visibleSegments(
  segments: readonly FrameSegment[],
  options: {
    maxPerFrame: number;
    expanded: readonly string[];
    keep: readonly number[];
  }
): VisibleSegment[] {
  const out: VisibleSegment[] = [];
  for (const { frame, group, hiddenRuns } of foldedFrames(segments, options)) {
    const open = options.expanded.includes(frame?.ident ?? "none");
    const hiddenAt = new Map(hiddenRuns.map((run) => [run[0], run]));
    let k = 0;
    while (k < group.length) {
      const run = open ? undefined : hiddenAt.get(k);
      if (run) {
        const periods = run.map((h) => group[h].segment.period);
        out.push({ kind: "fold", frame, hidden: periods.length, periods });
        k += run.length;
      } else {
        out.push({ kind: "segment", ...group[k] });
        k += 1;
      }
    }
  }
  return out;
}

/**
 * A frame's marker in the timeline's left column. Live and Previous move with
 * the calendar, so the marker names the kind with its year below it ("Live" /
 * "2026"): the reader sees which year each stands for today. A fixed frame is
 * one year, so the year alone names it.
 */
export function frameMarker(tf: TimeFrame): {
  label: string;
  year: string | null;
} {
  const year = tf.year != null ? String(tf.year) : null;
  if (tf.kind === "live") return { label: "Live", year };
  if (tf.kind === "relative") return { label: "Previous", year };
  return { label: year ?? tf.name ?? "", year: null };
}

/** A run of an opened frame's values that folding would hide again, by period. */
export interface UnfoldedRun {
  frame: string;
  periods: number[];
}

/**
 * Whether a drawn line is part of the edit's ticked stretch: a value when it
 * is ticked, a fold when every value it hides is ticked. The line is drawn
 * highlighted through such rows, so one selection reads as one unbroken
 * stretch whether its middle is folded or open.
 */
export function rowSelected(
  row: VisibleSegment | undefined,
  selected: readonly number[]
): boolean {
  if (!row) return false;
  if (row.kind === "segment") return selected.includes(row.segment.period);
  return (
    row.periods.length > 0 && row.periods.every((p) => selected.includes(p))
  );
}

/**
 * The runs of values an opened frame shows only because it is open: exactly
 * what its fold lines hide when it is folded. The timeline marks each with a
 * bracket on the right whose control folds the frame again, so the user sees
 * which values will go before they click.
 */
export function unfoldedRuns(
  segments: readonly FrameSegment[],
  options: {
    maxPerFrame: number;
    expanded: readonly string[];
    keep: readonly number[];
  }
): UnfoldedRun[] {
  return foldedFrames(segments, options).flatMap(
    ({ frame, group, hiddenRuns }) => {
      const ident = frame?.ident ?? "none";
      if (!options.expanded.includes(ident)) return [];
      return hiddenRuns.map((run) => ({
        frame: ident,
        periods: run.map((h) => group[h].segment.period),
      }));
    }
  );
}

/**
 * Each frame's segments, with the runs (positions within the frame) that
 * folding hides: none for a frame with up to maxPerFrame values; otherwise all
 * but two values (FOLDED_VALUES), keeping the kept ones first (the shown
 * value, then ticked ones), then the newest, then the oldest.
 */
function foldedFrames(
  segments: readonly FrameSegment[],
  { maxPerFrame, keep }: { maxPerFrame: number; keep: readonly number[] }
) {
  const frames: {
    frame: TimeFrame | null;
    group: { segment: FrameSegment; index: number }[];
    hiddenRuns: number[][];
  }[] = [];
  let i = 0;
  while (i < segments.length) {
    const frame = segments[i].frame;
    let j = i;
    while (j < segments.length && segments[j].frame?.ident === frame?.ident)
      j++;
    const group = segments
      .slice(i, j)
      .map((segment, k) => ({ segment, index: i + k }));
    const hiddenRuns: number[][] = [];
    if (group.length > maxPerFrame) {
      const chosen = new Set<number>();
      for (const p of keep) {
        const k = group.findIndex((g) => g.segment.period === p);
        if (k !== -1 && chosen.size < FOLDED_VALUES) chosen.add(k);
      }
      if (chosen.size < FOLDED_VALUES) chosen.add(group.length - 1);
      if (chosen.size < FOLDED_VALUES) chosen.add(0);
      let run: number[] = [];
      group.forEach((_, k) => {
        if (chosen.has(k)) {
          if (run.length) hiddenRuns.push(run);
          run = [];
        } else run.push(k);
      });
      if (run.length) hiddenRuns.push(run);
    }
    frames.push({ frame, group, hiddenRuns });
    i = j;
  }
  return frames;
}
