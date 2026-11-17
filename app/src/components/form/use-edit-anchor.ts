"use client";

import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useEditManager } from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import { useEditTimeline } from "./field-timeline-view";
import { periodOn, periodsInRange, type TimelinePeriod } from "./field-timeline";
import { editAnchor } from "./edit-changes";
import type { EditFieldSource } from "./read-edit-range";

export interface EditAnchor {
  periods: readonly TimelinePeriod[];
  ticked: number[];
  /** The anchor's index in `periods`, or -1 (nothing ticked, rows not read). */
  anchor: number;
  /** The period of the frame the page shows: the anchor until the user moves it. */
  shown: number;
  /** The anchor period's values: what the form holds (null without an anchor or for a hole). */
  values: Record<string, unknown> | null;
}

/**
 * The open edit's anchor (editAnchor) for a field: the ticked period whose
 * values the form holds (owner 2026-11-16). It starts on the period of the
 * frame the page shows; when the user unticks it the nearest ticked period
 * takes over, and when the ticks are cleared the next tick becomes it. The
 * anchor lives with the edit (EditTarget.anchorFrom), so the form, the
 * timeline and the save agree. Each time it moves, `onAnchor` gets its period
 * and the data source follows it.
 */
export function useEditAnchor(
  isEditing: boolean,
  source: EditFieldSource | undefined,
  onAnchor?: (period: TimelinePeriod) => void
): EditAnchor {
  const { currentEdit, setEditDataSourceId, setEditAnchor } = useEditManager();
  const { selectedTimeFrame } = useTimeFrame();
  const { periods } = useEditTimeline(isEditing ? source : undefined);
  const ticked = isEditing
    ? periodsInRange(periods, currentEdit.validFrom, currentEdit.validTo)
    : [];
  const shown = periodOn(periods, selectedTimeFrame?.valid_on ?? selectedTimeFrame?.valid_from);
  const held =
    currentEdit.anchorFrom === undefined
      ? shown
      : periods.findIndex((p) => p.valid_from === currentEdit.anchorFrom);
  const anchor = editAnchor(held, ticked, shown);
  const period = anchor >= 0 ? periods[anchor] : undefined;
  const anchorFrom = period?.valid_from ?? null;
  // The anchor period's identity and contents: the form follows the anchor
  // when this changes, and only then, so the user's own choices stand.
  const anchorKey = period
    ? JSON.stringify([period.valid_from, period.values, period.data_source_id, !!period.empty])
    : "";
  const stored = currentEdit.anchorFrom;
  useGuardedEffect(
    () => {
      if (!isEditing || periods.length === 0) return;
      if (anchorFrom !== stored) setEditAnchor(anchorFrom);
    },
    [isEditing, periods.length, anchorFrom, stored, setEditAnchor],
    "useEditAnchor:hold"
  );
  useGuardedEffect(
    () => {
      if (!isEditing || !period) return;
      setEditDataSourceId(period.empty ? null : (period.data_source_id?.toString() ?? null));
      onAnchor?.(period);
    },
    // The anchor is compared by anchorKey.
    [isEditing, anchorKey],
    "useEditAnchor:follow"
  );
  return {
    periods,
    ticked,
    anchor,
    shown,
    values: period && !period.empty ? period.values : null,
  };
}
