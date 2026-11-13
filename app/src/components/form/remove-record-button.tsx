"use client";

import { useMemo, useState, useTransition } from "react";
import { useSWRConfig } from "swr";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { useEditManager } from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import { framesNeedingConfirmation } from "@/lib/time-frame";
import { removeTemporalRecord } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { useDescribeValue, useFieldTimeline } from "./field-timeline-view";
import {
  frameMarker,
  frameSegments,
  type TimelinePeriod,
} from "./field-timeline";
import { removalRuns, removalSummary, type RemovalPiece, type RemovalRun } from "./removal";
import type { EditFieldSource } from "./read-edit-range";

/** The tables whose rows are records a unit has, which Remove can take away (STATBUS-611). */
const REMOVABLE = ["contact", "location", "activity", "stat_for_unit"] as const;
type Removable = (typeof REMOVABLE)[number];

/** Whether the field is a record the unit has (a contact, a location), not a field of the unit itself. */
export function isRemovable(
  source: EditFieldSource | undefined
): source is EditFieldSource & { table: Removable } {
  return !!source && (REMOVABLE as readonly string[]).includes(source.table);
}

const formatEnd = (to: string | null | undefined) =>
  !to || to === "infinity" ? "Present" : to;
const runLabel = (r: RemovalRun) => `${r.validFrom} – ${formatEnd(r.validTo)}`;

/**
 * The pieces Remove mode offers: the field's timeline split at every frame
 * boundary (frameSegments), so each frame's part of a value can be removed on
 * its own, oldest first, each with its value.
 */
export function useRemovalPieces(source: EditFieldSource | undefined) {
  const { periods, loaded } = useFieldTimeline(source);
  const { timeFrames } = useTimeFrame();
  const pieces = useMemo(
    () =>
      frameSegments(periods, timeFrames).map((s) => ({
        valid_from: s.valid_from,
        valid_to: s.valid_to,
        frame: s.frame,
        values: (periods[s.period] as TimelinePeriod).values,
      })),
    [periods, timeFrames]
  );
  return { pieces, loaded };
}

/**
 * The Timeline view in Remove mode: one row per piece (a value's part in one
 * frame), ticked to remove. A ticked piece turns red and its value is struck
 * through. Gaps are allowed: each unbroken run of ticked pieces is removed on
 * its own (removalRuns), so the time between them stays.
 */
export function RemovalTimeline() {
  const { currentEdit, setEditRemoving } = useEditManager();
  const describe = useDescribeValue();
  const { pieces, loaded } = useRemovalPieces(currentEdit.source);
  const ticked = currentEdit.removing ?? [];
  if (!loaded)
    return <p className="text-sm text-zinc-500">Reading the timeline…</p>;
  if (pieces.length === 0)
    return (
      <p className="text-sm text-zinc-500">Nothing is recorded to remove.</p>
    );
  const toggle = (i: number) =>
    setEditRemoving(
      ticked.includes(i) ? ticked.filter((x) => x !== i) : [...ticked, i]
    );
  return (
    <div className="space-y-0.5" data-removal-timeline="">
      {pieces.map((p, i) => {
        const on = ticked.includes(i);
        const marker = p.frame ? frameMarker(p.frame) : null;
        const value = describe.value(p.values);
        return (
          <label
            key={p.valid_from}
            className={cn(
              "grid cursor-pointer grid-cols-[4.5rem_1rem_1fr] items-start gap-2 rounded px-1 py-1 text-sm",
              on ? "bg-red-50" : "hover:bg-zinc-50"
            )}
            data-removal-piece={p.valid_from}
            data-ticked={on || undefined}
          >
            <span className="pt-0.5 text-xs leading-tight text-zinc-500">
              {marker ? (
                <>
                  <span className="block">{marker.label}</span>
                  {marker.year && (
                    <span className="tabular-nums">{marker.year}</span>
                  )}
                </>
              ) : (
                "Before frames"
              )}
            </span>
            <Checkbox
              checked={on}
              onCheckedChange={() => toggle(i)}
              className={cn(
                "mt-0.5",
                on && "border-red-700 data-[state=checked]:bg-red-700"
              )}
              aria-label={`Remove ${p.valid_from} – ${formatEnd(p.valid_to)}`}
            />
            <span className="min-w-0">
              <span
                className={cn(
                  "block break-words font-medium",
                  on && "text-red-700 line-through",
                  !value && "italic text-zinc-400"
                )}
              >
                {value ?? "Empty"}
              </span>
              <span
                className={cn(
                  "block text-xs tabular-nums",
                  on ? "text-red-700" : "text-zinc-500"
                )}
              >
                {p.valid_from} – {formatEnd(p.valid_to)}
              </span>
            </span>
          </label>
        );
      })}
    </div>
  );
}

/**
 * Tick all, beside the Change | Remove switch in Remove mode: ticks every
 * piece, so the record is removed completely ("Remove all"), or clears the ticks.
 */
export function TickAllPieces() {
  const { currentEdit, setEditRemoving } = useEditManager();
  const { pieces } = useRemovalPieces(currentEdit.source);
  const ticked = currentEdit.removing ?? [];
  const all = pieces.length > 0 && ticked.length === pieces.length;
  return (
    <button
      type="button"
      onClick={() => setEditRemoving(all ? [] : pieces.map((_, i) => i))}
      className="text-xs text-red-700 underline-offset-2 hover:underline"
      data-removal-tick-all={all ? "clear" : "all"}
    >
      {all ? "Untick all" : "Tick all"}
    </button>
  );
}

/**
 * What Remove mode would remove, in either view. Timeline: the ticked pieces,
 * each unbroken run removed on its own. Frame: the edit's period (the chosen
 * frame, or the specific dates) as one run, with the parts of the record's
 * values inside it (removalSummary). "all" when nothing would stay.
 */
export function useRemoval(source: EditFieldSource | undefined) {
  const { currentEdit } = useEditManager();
  const { timeFrames } = useTimeFrame();
  const { periods } = useFieldTimeline(source);
  const { pieces } = useRemovalPieces(source);
  if (currentEdit.view === "timeline") {
    const ticked = currentEdit.removing ?? [];
    const removed = [...ticked]
      .sort((a, b) => a - b)
      .map((i) => pieces[i])
      .filter(Boolean);
    return {
      runs: removalRuns(pieces, ticked),
      removed,
      kept: [] as RemovalPiece[],
      all: pieces.length > 0 && ticked.length === pieces.length,
    };
  }
  // Frame: the frame's own period; Specific dates: the dates typed.
  const frame =
    currentEdit.validityChoice !== "dates"
      ? timeFrames.find((tf) => tf.ident === currentEdit.frameIdent)
      : undefined;
  const from = frame?.valid_from ?? currentEdit.validFrom;
  const to = frame ? (frame.valid_to === "infinity" ? null : frame.valid_to) : currentEdit.validTo;
  if (!from) return { runs: [], removed: [], kept: [] as RemovalPiece[], all: false };
  const { removed, kept } = removalSummary(periods, from, to);
  return {
    runs: removed.length > 0 ? [{ validFrom: from, validTo: to ?? null }] : [],
    removed,
    kept,
    all: removed.length > 0 && kept.length === 0,
  };
}

/**
 * Remove mode in the Frame view, below the menu: the parts of the record the
 * chosen period removes, struck through in red, and what stays.
 */
export function FrameRemovalSummary() {
  const { currentEdit } = useEditManager();
  const describe = useDescribeValue();
  const { removed, kept } = useRemoval(currentEdit.source);
  if (removed.length === 0)
    return (
      <p className="text-sm text-zinc-500" data-frame-removal="">
        Nothing is recorded in this period.
      </p>
    );
  return (
    <div className="space-y-1 text-sm" data-frame-removal="">
      {removed.map((p) => (
        <div key={p.valid_from} className="rounded bg-red-50 px-2 py-1" data-frame-removal-removed="">
          <span className="block break-words font-medium text-red-700 line-through">
            {describe.value(p.values) ?? "Empty"}
          </span>
          <span className="block text-xs tabular-nums text-red-700">
            {p.valid_from} – {formatEnd(p.valid_to)}
          </span>
        </div>
      ))}
      {kept.length > 0 && (
        <p className="text-xs text-zinc-600" data-frame-removal-kept="">
          Stays: {kept.map((p) => `${p.valid_from} – ${formatEnd(p.valid_to)}`).join(", ")}
        </p>
      )}
    </div>
  );
}

/**
 * The form's action in Remove mode, in Save's place: a red "Remove …" naming
 * the ticked stretches ("Remove all" when every piece is ticked). It asks
 * first: the dialog lists each stretch with its value and the past frames it
 * reaches into. Confirm removes them (removeTemporalRecord), closes the edit
 * and re-reads the page and the timeline.
 */
export function RemoveRecordAction({ label }: { label: string }) {
  const { currentEdit, exitEditMode } = useEditManager();
  const { timeFrames } = useTimeFrame();
  const { mutate } = useSWRConfig();
  const { toast } = useToast();
  const describe = useDescribeValue();
  const source = currentEdit.source;
  const { runs, removed: removedPieces, all } = useRemoval(source);
  const [open, setOpen] = useState(false);
  const [pending, startTransition] = useTransition();
  if (!isRemovable(source)) return null;
  const pastFrames = [
    ...new Map(
      runs
        .flatMap((r) =>
          framesNeedingConfirmation(timeFrames, r.validFrom, r.validTo)
        )
        .map((f) => [f.ident, f])
    ).values(),
  ];
  const frameName =
    currentEdit.view !== "timeline" && currentEdit.validityChoice !== "dates"
      ? timeFrames.find((tf) => tf.ident === currentEdit.frameIdent)?.name
      : undefined;
  const caption = all
    ? "Remove all"
    : runs.length === 0
      ? "Remove"
      : frameName
        ? `Remove ${frameName}`
        : `Remove ${runs.map(runLabel).join(", ")}`;

  const confirm = () => {
    startTransition(async () => {
      const result = await removeTemporalRecord({
        table: source.table,
        match: source.match,
        runs,
      });
      setOpen(false);
      toast({
        title: result?.status === "error" ? "Error" : "Removed",
        description: result?.message,
        className:
          result?.status === "error"
            ? "border-red-700 bg-red-100 text-red-700"
            : "border-green-700 bg-green-100 text-green-700",
      });
      if (result?.status === "success") {
        // The page's details and every timeline read again (SWR array keys).
        await mutate(
          (key) =>
            Array.isArray(key) && ["details", "field-timeline"].includes(key[0])
        );
        exitEditMode();
      }
    });
  };

  return (
    <>
      <Button
        type="button"
        className="bg-red-700 text-white hover:bg-red-800"
        disabled={runs.length === 0 || pending}
        onClick={() => setOpen(true)}
        data-remove-record=""
      >
        {caption}
      </Button>
      {open && (
        <AlertDialog
          open
          onOpenChange={(o) => !o && !pending && setOpen(false)}
        >
          <AlertDialogContent data-remove-confirmation="">
            <AlertDialogHeader>
              <AlertDialogTitle>
                {all
                  ? `Remove the ${label.toLowerCase()} completely?`
                  : `Remove from ${label.toLowerCase()}?`}
              </AlertDialogTitle>
              <AlertDialogDescription asChild>
                <div className="space-y-3 text-sm">
                  <ul className="list-disc pl-5" data-remove-removed="">
                    {removedPieces.map((p) => (
                      <li key={p.valid_from} className="tabular-nums">
                        {p.valid_from} – {formatEnd(p.valid_to)}:{" "}
                        {describe.value(p.values) ?? "Empty"}
                      </li>
                    ))}
                  </ul>
                  {pastFrames.length > 0 && (
                    <div data-remove-past-frames="">
                      <p>
                        This reaches into{" "}
                        {pastFrames.map((f) => f.name).join(", ")}.
                      </p>
                      <p>Reports and figures for these years will change.</p>
                    </div>
                  )}
                </div>
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel disabled={pending}>Cancel</AlertDialogCancel>
              <AlertDialogAction
                className="bg-red-700 hover:bg-red-800"
                disabled={pending}
                onClick={(e) => {
                  e.preventDefault();
                  confirm();
                }}
              >
                {pending ? "Removing…" : "Remove"}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      )}
    </>
  );
}
