"use client";
import { useCallback } from "react";
import { useAtomValue } from "jotai";
import { restClientAtom } from "@/atoms/rest-client";
import { useEditManager } from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import type { TimeFrame } from "@/lib/time-frame";
import { readEditRange, type EditFieldSource, type EditStart } from "./read-edit-range";

/**
 * The period an edit in a frame applies to, and the data source and comment it
 * starts with. Without a source it is the frame; with a source it is the
 * stretch where the shown value is valid within the frame (readEditRange,
 * STATBUS-604), starting with that row's data source and comment. "infinity"
 * as the end is held as an empty valid_to, which the server reads as open-ended.
 */
export async function editPeriodInFrame(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: any,
  frame: Pick<TimeFrame, "valid_from" | "valid_to"> | null,
  source?: EditFieldSource,
  shownValue?: unknown
): Promise<{ validFrom: string | null; validTo: string | null; dataSourceId?: string | null; editComment?: string | null }> {
  const context = {
    valid_from: frame?.valid_from ?? "",
    valid_to: frame?.valid_to ?? "infinity",
  };
  const range: EditStart =
    source && client && context.valid_from
      ? await readEditRange(client, { ...source, shownValue, context })
      : { validFrom: context.valid_from, validTo: context.valid_to };
  return {
    ...range,
    validFrom: range.validFrom || null,
    validTo: range.validTo === "infinity" ? null : range.validTo,
  };
}

/**
 * Starts an edit of one field in the selected time frame. The form shows that
 * frame and lets the user choose another (useChangeEditFrame); the dates follow
 * the frame by the same rule. The data source and comment start as those of the
 * row the edit starts in; for a field without rows to read, those of the row
 * shown (its metadata).
 */
export function useStartEdit() {
  const client = useAtomValue(restClientAtom);
  const { setEditTarget } = useEditManager();
  const { selectedTimeFrame } = useTimeFrame();

  return useCallback(
    async (
      fieldId: string,
      source?: EditFieldSource,
      shownValue?: unknown,
      shown?: { data_source_id?: number | null; edit_comment?: string | null } | null
    ) => {
      const start = await editPeriodInFrame(client, selectedTimeFrame, source, shownValue);
      setEditTarget(fieldId, {
        frameIdent: selectedTimeFrame?.ident ?? null,
        ...start,
        dataSourceId:
          start.dataSourceId !== undefined ? start.dataSourceId : (shown?.data_source_id?.toString() ?? null),
        editComment: start.editComment !== undefined ? start.editComment : shown?.edit_comment || null,
        source,
        shownValue,
      });
    },
    [client, setEditTarget, selectedTimeFrame]
  );
}

/**
 * Moves the open edit to another frame, re-deriving its dates from that frame.
 * The data source and comment follow the row the edit now starts in.
 */
export function useChangeEditFrame() {
  const client = useAtomValue(restClientAtom);
  const { currentEdit, setEditFrame } = useEditManager();
  const { timeFrames } = useTimeFrame();

  return useCallback(
    async (frameIdent: string) => {
      const frame = timeFrames.find((tf) => tf.ident === frameIdent) ?? null;
      if (!frame) return;
      const period = await editPeriodInFrame(client, frame, currentEdit.source, currentEdit.shownValue);
      setEditFrame({ frameIdent, ...period });
    },
    [client, timeFrames, currentEdit.source, currentEdit.shownValue, setEditFrame]
  );
}
