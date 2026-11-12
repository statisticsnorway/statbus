"use client";

import { useMemo, useState } from "react";
import { useAtomValue } from "jotai";
import useSWR from "swr";
import {
  ChevronsDownUp,
  ChevronsUpDown,
  GitCommitVertical,
  X,
} from "lucide-react";
import { restClientAtom } from "@/atoms/rest-client";
import { useDetailsPageData } from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import type { TimeFrame } from "@/lib/time-frame";
import type { EditFieldSource } from "./read-edit-range";
import {
  fieldTimeline,
  foldableFrames,
  frameMarker,
  frameSegments,
  periodOn,
  rowSelected,
  unfoldedRuns,
  visibleSegments,
  type TimelinePeriod,
  type TimelineSourceRow,
} from "./field-timeline";

const METADATA_COLUMNS =
  "valid_from,valid_to,data_source_id,edit_comment,edit_by_user_id,edit_at";

/**
 * The field's timeline for one unit, read from the same rows the edit reads
 * (EditFieldSource) and merged where the field did not change (fieldTimeline).
 */
export function useFieldTimeline(source: EditFieldSource | undefined) {
  const client = useAtomValue(restClientAtom);
  const columns = useMemo(
    () =>
      source
        ? Array.isArray(source.column)
          ? source.column
          : [source.column]
        : [],
    [source]
  );
  // The match values are in the key as strings, so a form's refresh after a
  // save (mutate of keys containing the unit id) reads the timeline again.
  const key =
    source && client
      ? [
          "field-timeline",
          source.table,
          ...Object.values(source.match).map(String),
          columns.join(","),
        ]
      : null;
  const { data, error, isLoading, mutate } = useSWR(key, async () => {
    // The table is named at run time (EditFieldSource), as in readEditRange.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let query = (client as any)
      .from(source!.table)
      .select(`${METADATA_COLUMNS},${columns.join(",")}`);
    for (const [k, v] of Object.entries(source!.match)) query = query.eq(k, v);
    const { data: rows, error: readError } = await query.order("valid_from");
    if (readError) throw readError;
    return rows as unknown as TimelineSourceRow[];
  });
  const periods = useMemo(
    () => (data ? fieldTimeline(data, columns) : []),
    [data, columns]
  );
  return { periods, loaded: !!data, error, isLoading, refresh: mutate };
}

/** The frame's marker on a timeline row (frameMarker): kind above year for Live and Previous. */
function FrameMarker({ frame }: { frame: TimeFrame }) {
  const { label, year } = frameMarker(frame);
  return (
    <>
      <span>{label}</span>
      {year && <span className="tabular-nums">{year}</span>}
    </>
  );
}

const formatEnd = (to: string) => (to === "infinity" ? "Present" : to);

/** The period's value in words: a single column's value, or a group's non-empty parts. */
function useDescribeValue() {
  const { regions, countries, dataSources } = useDetailsPageData();
  return useMemo(() => {
    const regionById = new Map(
      regions.map((r) => [r.id, `${r.code} ${r.name}`])
    );
    const countryById = new Map(countries.map((c) => [c.id, c.name]));
    return {
      value: (values: Record<string, unknown>) => {
        const parts = Object.entries(values).flatMap(([column, v]) => {
          if (v == null || v === "") return [];
          if (column === "region_id")
            return [regionById.get(v as number) ?? String(v)];
          if (column === "country_id")
            return [countryById.get(v as number) ?? String(v)];
          return [String(v)];
        });
        return parts.length ? parts.join(", ") : null;
      },
      source: (id: number | null) =>
        id == null
          ? null
          : (dataSources.find((d) => d.id === id)?.code ?? String(id)),
    };
  }, [regions, countries, dataSources]);
}

interface FieldTimelineProps {
  periods: readonly TimelinePeriod[];
  /** The ticked periods; with onToggle the rows have checkboxes (the edit), without they only show. */
  selected?: readonly number[];
  onToggle?: (index: number) => void;
  /** A heading shown at the top, beside the close button (the popover's). */
  title?: string;
  /** Closes the view (the popover's X, top right). Absent, there is no X. */
  onClose?: () => void;
  /**
   * Inside a height-bounded box (the popover): the title row and Show all stay
   * in place and only the values scroll, so neither control leaves the view.
   */
  scrollValues?: boolean;
}

/** A frame with more values than this is folded to two (visibleSegments). */
const MAX_VALUES_PER_FRAME = 3;

/**
 * The field's values over time, oldest at the top, laid out in three columns:
 * the time frames on the left, the line in the middle, and the values on the
 * right. A value that spans several frames stands beside all of them; a frame
 * with a change inside it holds both values. The line has one dot per value;
 * the dot of the value the page shows (the selected frame) is filled. In an
 * edit each value has a checkbox, and the ticked stretch of the line is drawn
 * highlighted: the edit applies to exactly that stretch. A frame with many
 * values is folded (visibleSegments): its control sits on the right edge, the
 * label "Show N more" beside a chevron; opened, a bracket there spans exactly
 * the values that came out (unfoldedRuns), with the same chevron to fold them
 * back. "Show all", bottom right, opens or folds every frame.
 */
export function FieldTimeline({
  periods,
  selected = [],
  onToggle,
  title,
  onClose,
  scrollValues,
}: FieldTimelineProps) {
  const { timeFrames, selectedTimeFrame } = useTimeFrame();
  const describe = useDescribeValue();
  const [expanded, setExpanded] = useState<string[]>([]);
  const shownIndex = periodOn(
    periods,
    selectedTimeFrame?.valid_on ?? selectedTimeFrame?.valid_from
  );
  const isSelected = (i: number) => selected.includes(i);
  const segments = useMemo(
    () => frameSegments(periods, timeFrames),
    [periods, timeFrames]
  );
  const keep = shownIndex === -1 ? [...selected] : [shownIndex, ...selected];
  const foldOptions = {
    maxPerFrame: MAX_VALUES_PER_FRAME,
    expanded,
    keep,
  };
  const rows = visibleSegments(segments, foldOptions);
  const runs = unfoldedRuns(segments, foldOptions);
  const foldable = foldableFrames(segments, MAX_VALUES_PER_FRAME);
  const allOpen =
    foldable.length > 0 && foldable.every((f) => expanded.includes(f));

  if (periods.length === 0)
    return <p className="text-sm text-zinc-500">No values recorded.</p>;

  // Grid rows: one per visible line. A frame's cell spans its consecutive
  // lines, a value's cell spans its period's lines.
  const frameOf = (r: (typeof rows)[number]) =>
    r.kind === "segment" ? r.segment.frame : r.frame;
  const frameCells: { frame: TimeFrame | null; row: number; span: number }[] =
    [];
  rows.forEach((r, i) => {
    const frame = frameOf(r);
    const last = frameCells[frameCells.length - 1];
    if (last && last.frame?.ident === frame?.ident) last.span += 1;
    else frameCells.push({ frame, row: i + 1, span: 1 });
  });
  const periodRows = new Map<number, { row: number; span: number }>();
  rows.forEach((r, i) => {
    if (r.kind !== "segment") return;
    const at = periodRows.get(r.segment.period);
    if (at) at.span += 1;
    else periodRows.set(r.segment.period, { row: i + 1, span: 1 });
  });
  const lookingAt = (tf: TimeFrame | null) =>
    !!tf &&
    (tf.ident === selectedTimeFrame?.ident ||
      tf.ident === selectedTimeFrame?.equals_frame_ident);
  const col = onToggle
    ? { frame: 1, line: 2, box: 3, value: 4, bracket: 5 }
    : { frame: 1, line: 2, box: 0, value: 3, bracket: 4 };
  // Each unfolded run's bracket spans the grid rows of its values.
  const brackets = runs.flatMap((run) => {
    const at = rows.flatMap((r, i) =>
      r.kind === "segment" &&
      (r.segment.frame?.ident ?? "none") === run.frame &&
      run.periods.includes(r.segment.period)
        ? [i + 1]
        : []
    );
    return at.length
      ? [{ frame: run.frame, from: at[0], to: at[at.length - 1] }]
      : [];
  });
  const periodAt = (i: number) => {
    const r = rows[i];
    return r?.kind === "segment" ? r.segment.period : null;
  };
  const toggleFrame = (ident: string) =>
    setExpanded((prev) =>
      prev.includes(ident) ? prev.filter((x) => x !== ident) : [...prev, ident]
    );

  const showAll = foldable.length > 0 && (
    <div className="flex shrink-0 justify-end pt-1">
      <button
        type="button"
        onClick={() => setExpanded(allOpen ? [] : foldable)}
        className="flex items-center gap-1 rounded px-1 py-0.5 text-xs text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900"
        data-timeline-toggle-all={allOpen ? "collapse" : "expand"}
      >
        {allOpen ? "Show fewer" : "Show all"}
        <span className="flex h-4 w-4 items-center justify-center rounded-full border border-zinc-300 bg-white">
          {allOpen ? (
            <ChevronsDownUp className="h-3 w-3" />
          ) : (
            <ChevronsUpDown className="h-3 w-3" />
          )}
        </span>
      </button>
    </div>
  );

  return (
    <div
      className={cn(
        "space-y-0.5",
        scrollValues && "flex max-h-full min-h-0 flex-col"
      )}
    >
      {/* The title (the popover's) and, top right, the X that closes it. */}
      {(title || onClose) && (
        <div className="flex shrink-0 items-center justify-between gap-2 pb-1">
          {title ? (
            <p className="font-medium text-zinc-900">{title}</p>
          ) : (
            <span />
          )}
          {onClose && (
            <button
              type="button"
              onClick={onClose}
              aria-label="Close"
              className="rounded-full p-0.5 text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900"
              data-timeline-close=""
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
      )}
      <div
        className={cn(
          "grid gap-x-2 text-sm",
          onToggle
            ? "grid-cols-[minmax(3.5rem,auto)_1rem_1rem_1fr_1.25rem]"
            : "grid-cols-[minmax(3.5rem,auto)_1rem_1fr_1.25rem]",
          scrollValues && "min-h-0 flex-1 overflow-y-auto"
        )}
        data-field-timeline=""
      >
        {/* A faint solid line across the timeline where one frame ends and
          the next begins, so each dot reads as belonging to the frame beside
          it. Solid, so the dotted bracket ties below stand apart from it. */}
        {frameCells.slice(1).map((c) => (
          <div
            key={`frame-rule-${c.row}`}
            aria-hidden
            style={{ gridColumn: "1 / -1", gridRow: c.row }}
            className="pointer-events-none self-start border-t border-zinc-200"
            data-timeline-frame-rule=""
          />
        ))}

        {frameCells.map((c) => {
          const ident = c.frame?.ident ?? "none";
          return (
            <div
              key={`frame-${c.row}`}
              style={{
                gridColumn: col.frame,
                gridRow: `${c.row} / span ${c.span}`,
              }}
              className={cn(
                "my-0.5 flex flex-col justify-center border-l-2 pl-1.5 text-xs leading-4",
                lookingAt(c.frame)
                  ? "border-zinc-700 font-medium text-zinc-900"
                  : "border-zinc-200 text-zinc-500"
              )}
              title={c.frame?.name ?? "Before the oldest frame"}
              data-timeline-frame={ident}
            >
              {c.frame ? <FrameMarker frame={c.frame} /> : "Earlier"}
            </div>
          );
        })}

        {rows.map((r, i) => {
          const period = periodAt(i);
          const on = rowSelected(r, selected);
          const isTop = i === 0;
          const isBottom = i === rows.length - 1;
          // A fold whose hidden values are all ticked is part of the stretch,
          // so the highlight runs through it to the values on either side.
          const linkUp = on && rowSelected(rows[i - 1], selected);
          const linkDown = on && rowSelected(rows[i + 1], selected);
          const first = r.kind === "segment" && r.segment.first;
          const shown = first && period === shownIndex;
          const foldOn = r.kind === "fold" && on;
          return (
            <div
              key={`line-${i}`}
              style={{ gridColumn: col.line, gridRow: i + 1 }}
              className={cn(
                "relative flex items-start justify-center",
                r.kind === "segment" ? "min-h-10" : "min-h-7"
              )}
              aria-hidden
            >
              <span
                className={cn(
                  "absolute left-1/2 top-0 h-3 -translate-x-1/2",
                  isTop
                    ? "hidden"
                    : linkUp || (on && !first && r.kind === "segment")
                      ? "w-1 bg-ssb-dark"
                      : "w-px bg-zinc-300"
                )}
              />
              <span
                className={cn(
                  "absolute bottom-0 left-1/2 top-3 -translate-x-1/2",
                  isBottom
                    ? "hidden"
                    : linkDown
                      ? "w-1 bg-ssb-dark"
                      : "w-px bg-zinc-300",
                  r.kind === "fold" &&
                    !foldOn &&
                    "border-l border-dashed border-zinc-300 bg-transparent"
                )}
              />
              {first && (
                <span
                  className={cn(
                    "relative z-10 mt-1.5 h-3 w-3 rounded-full border-2",
                    shown
                      ? "border-ssb-dark bg-ssb-dark"
                      : on
                        ? "border-ssb-dark bg-white"
                        : "border-zinc-400 bg-white"
                  )}
                  data-timeline-dot={shown ? "shown" : ""}
                />
              )}
            </div>
          );
        })}

        {/* A fold is one control on the right edge, where its bracket will
            be: the label to the left of the chevron. Opened, the bracket
            spans the values and carries the same chevron. */}
        {rows.map((r, i) =>
          r.kind !== "fold" ? null : (
            <div key={`fold-${i}`} className="contents">
              <button
                type="button"
                style={{
                  gridColumn: `${onToggle ? col.box : col.value} / ${col.bracket}`,
                  gridRow: i + 1,
                }}
                className="my-0.5 self-center justify-self-end rounded px-2 py-0.5 text-right text-xs text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900"
                onClick={() => toggleFrame(r.frame?.ident ?? "none")}
                data-timeline-fold={r.frame?.ident ?? "none"}
              >
                Show {r.hidden} more
                {(() => {
                  const first = periods[r.periods[0]];
                  const last = periods[r.periods[r.periods.length - 1]];
                  return first && last
                    ? ` · ${first.valid_from} – ${formatEnd(last.valid_to)}`
                    : "";
                })()}
              </button>
              <div
                style={{ gridColumn: col.bracket, gridRow: i + 1 }}
                className="flex items-center"
              >
                <button
                  type="button"
                  onClick={() => toggleFrame(r.frame?.ident ?? "none")}
                  className="relative z-10 ml-0.5 flex h-4 w-4 items-center justify-center rounded-full border border-zinc-300 bg-white text-zinc-500 hover:border-zinc-500 hover:text-zinc-900"
                  aria-label={`Show ${r.hidden} more`}
                  data-timeline-toggle="fold"
                >
                  <ChevronsUpDown className="h-3 w-3" />
                </button>
              </div>
            </div>
          )
        )}

        {/* Dotted ties from the line to the bracket's two ends, so the values
            a bracket holds read as cut out of the timeline between them. */}
        {brackets.flatMap((b) => [
          <div
            key={`tie-top-${b.frame}-${b.from}`}
            aria-hidden
            style={{
              gridColumn: `${col.line} / ${col.bracket}`,
              gridRow: b.from,
            }}
            className="pointer-events-none -mr-2 ml-2 mt-1 self-start border-t border-dotted border-zinc-400"
            data-timeline-bracket-tie="top"
          />,
          <div
            key={`tie-bottom-${b.frame}-${b.to}`}
            aria-hidden
            style={{
              gridColumn: `${col.line} / ${col.bracket}`,
              gridRow: b.to,
            }}
            className="pointer-events-none -mr-2 mb-1 ml-2 self-end border-b border-dotted border-zinc-400"
            data-timeline-bracket-tie="bottom"
          />,
        ])}

        {/* An opened frame's values that folding would hide again, bracketed
            on the right. The chevron sits at the bracket's top, where the
            fold's chevron was, so the toggle stays in place: click, the values
            open below it; click again, they fold back into the same spot. */}
        {brackets.map((b) => (
          <div
            key={`bracket-${b.frame}-${b.from}`}
            style={{
              gridColumn: col.bracket,
              gridRow: `${b.from} / ${b.to + 1}`,
            }}
            className="relative my-1 flex items-start"
            data-timeline-bracket={b.frame}
          >
            <span
              aria-hidden
              className="absolute inset-y-0 left-0 w-2 rounded-r border-y border-r border-zinc-300"
            />
            <button
              type="button"
              onClick={() => toggleFrame(b.frame)}
              className="relative z-10 ml-0.5 mt-1 flex h-4 w-4 items-center justify-center rounded-full border border-zinc-300 bg-white text-zinc-500 hover:border-zinc-500 hover:text-zinc-900"
              aria-label="Show fewer"
              title="Show fewer"
              data-timeline-collapse={b.frame}
            >
              <ChevronsDownUp className="h-3 w-3" />
            </button>
          </div>
        ))}

        {periods.map((p, i) => {
          const at = periodRows.get(i);
          if (!at) return null;
          const on = isSelected(i);
          const value = describe.value(p.values);
          const source = describe.source(p.data_source_id);
          return (
            <div
              key={p.valid_from}
              className="contents"
              data-timeline-period={p.valid_from}
              data-selected={on || undefined}
            >
              {onToggle && (
                <div
                  style={{
                    gridColumn: col.box,
                    gridRow: `${at.row} / span ${at.span}`,
                  }}
                  className="pt-1.5"
                >
                  <Checkbox
                    checked={on}
                    onCheckedChange={() => onToggle(i)}
                    aria-label={`Change ${p.valid_from} – ${formatEnd(p.valid_to)}`}
                  />
                </div>
              )}
              <div
                style={{
                  gridColumn: col.value,
                  gridRow: `${at.row} / span ${at.span}`,
                }}
                className={cn(
                  "my-0.5 min-w-0 rounded px-2 py-1",
                  on && "bg-ssb-light"
                )}
                data-shown={i === shownIndex || undefined}
              >
                <div
                  className={cn(
                    "break-words font-medium",
                    !value && "italic text-zinc-400"
                  )}
                >
                  {value ?? "Empty"}
                </div>
                <div className="text-xs text-zinc-500">
                  {p.valid_from} – {formatEnd(p.valid_to)}
                  {source && <span> · {source}</span>}
                  {p.edit_comment && (
                    <span className="block truncate italic">
                      {p.edit_comment}
                    </span>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>
      {showAll}
    </div>
  );
}

/**
 * The timeline icon beside a field's (i): opens the field's timeline, the same
 * view the edit uses, without checkboxes. The popover opens on the side of the
 * icon with more room, chosen at the click, so it opens in the same place
 * whether the timeline is still loading or already read. It grows to fill that
 * side and no further; the values scroll inside it.
 */
export function FieldTimelineButton({
  source,
  label,
}: {
  source: EditFieldSource;
  label: string;
}) {
  const [open, setOpen] = useState(false);
  const [side, setSide] = useState<"top" | "bottom">("bottom");
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label={`Timeline of ${label}`}
          onPointerDown={(e) => {
            const r = e.currentTarget.getBoundingClientRect();
            setSide(window.innerHeight - r.bottom >= r.top ? "bottom" : "top");
          }}
          className="ml-1 rounded-full p-0.5 text-zinc-400 hover:text-zinc-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400"
          data-field-timeline-button=""
        >
          <GitCommitVertical className="h-3.5 w-3.5" />
        </button>
      </PopoverTrigger>
      <PopoverContent
        side={side}
        align="start"
        collisionPadding={8}
        className="flex max-h-(--radix-popover-content-available-height) w-[26rem] flex-col text-sm font-normal normal-case text-zinc-700"
      >
        <FieldTimelineLoaded
          source={source}
          title={`${label} over time`}
          onClose={() => setOpen(false)}
        />
      </PopoverContent>
    </Popover>
  );
}

function FieldTimelineLoaded({
  source,
  title,
  onClose,
}: {
  source: EditFieldSource;
  title: string;
  onClose: () => void;
}) {
  const { periods, loaded, error } = useFieldTimeline(source);
  if (error)
    return <p className="text-sm text-red-700">Could not read the timeline.</p>;
  if (!loaded) return <p className="text-sm text-zinc-500">Loading…</p>;
  return (
    <FieldTimeline
      periods={periods}
      title={title}
      onClose={onClose}
      scrollValues
    />
  );
}
