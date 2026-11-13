"use client";

import { useMemo } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useEditManager } from "@/atoms/edits";
import { useFieldTimeline } from "./field-timeline-view";
import { periodsInRange } from "./field-timeline";
import { editStartValues, type EditStartValues } from "./edit-values";
import type { EditFieldSource } from "./read-edit-range";

/**
 * The values the edit of a field starts from: those of the stretch the edit
 * covers (its ticked periods, editStartValues), read from the field's rows.
 * While editing, the data source follows that stretch too. Each time the
 * ticked stretch changes, `onStart` gets its values, so the form shows what
 * Save will keep (owner 2026-11-13).
 */
export function useEditStartValues(
  isEditing: boolean,
  source: EditFieldSource | undefined,
  onStart?: (start: EditStartValues) => void
): EditStartValues | null {
  const { currentEdit, setEditDataSourceId } = useEditManager();
  const { periods } = useFieldTimeline(isEditing ? source : undefined);
  const ticked = isEditing
    ? periodsInRange(periods, currentEdit.validFrom, currentEdit.validTo)
    : [];
  const tickedKey = ticked.join(",");
  const start = useMemo(
    () => editStartValues(periods, ticked),
    // The ticks are compared by their indices (tickedKey).
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [periods, tickedKey]
  );
  useGuardedEffect(
    () => {
      if (!isEditing || !start) return;
      setEditDataSourceId(start.dataSourceId?.toString() ?? null);
      onStart?.(start);
    },
    [isEditing, start],
    "useEditStartValues:followTicked"
  );
  return start;
}
