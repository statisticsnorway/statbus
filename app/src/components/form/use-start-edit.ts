"use client";
import { useCallback } from "react";
import { useAtomValue } from "jotai";
import { restClientAtom } from "@/atoms/rest-client";
import { useEditManager } from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import { readEditRange, type EditFieldSource } from "./read-edit-range";

/**
 * Starts an edit of one field on the period the user is looking at. Without a
 * source the edit opens on the selected time frame; with a source it opens on
 * the stretch where the shown value is valid within that context (readEditRange).
 * "infinity" as the end is sent as an empty valid_to, which the server reads as
 * open-ended.
 */
export function useStartEdit() {
  const client = useAtomValue(restClientAtom);
  const { setEditTarget } = useEditManager();
  const { selectedTimeFrame } = useTimeFrame();

  return useCallback(
    async (fieldId: string, source?: EditFieldSource, shownValue?: unknown) => {
      const context = {
        valid_from: selectedTimeFrame?.valid_from ?? "",
        valid_to: selectedTimeFrame?.valid_to ?? "infinity",
      };
      const range =
        source && client && context.valid_from
          ? await readEditRange(client, { ...source, shownValue, context })
          : { validFrom: context.valid_from, validTo: context.valid_to };
      setEditTarget(fieldId, {
        validFrom: range.validFrom || null,
        validTo: range.validTo === "infinity" ? null : range.validTo,
      });
    },
    [client, setEditTarget, selectedTimeFrame]
  );
}
