"use client";

import { useState, useTransition } from "react";
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
import { useEditManager } from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import { useToast } from "@/hooks/use-toast";
import { framesNeedingConfirmation } from "@/lib/time-frame";
import { removeTemporalRecord } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { useDescribeValue, useFieldTimeline } from "./field-timeline-view";
import { removalSummary, type RemovalPiece } from "./removal";
import type { EditFieldSource } from "./read-edit-range";

/** The tables whose rows are records a unit has, which Remove can take away (STATBUS-611). */
const REMOVABLE = ["contact", "location", "activity", "stat_for_unit"] as const;
type Removable = (typeof REMOVABLE)[number];

/** Whether the field is a record the unit has (a contact, a location), not a field of the unit itself. */
export function isRemovable(source: EditFieldSource | undefined): source is EditFieldSource & { table: Removable } {
  return !!source && (REMOVABLE as readonly string[]).includes(source.table);
}

const formatEnd = (to: string | null | undefined) => (!to || to === "infinity" ? "Present" : to);

/**
 * Remove, beside Save in an edit of a record the unit has: takes the record
 * away over the edit's dates, the same stretch Save would change (the frame,
 * the ticked periods, or Advanced's dates). The button names the stretch.
 * It always asks first: the dialog lists what is removed and what stays
 * (removalSummary), and names the past frames the removal reaches into.
 * Confirm removes through removeTemporalRecord, closes the edit and re-reads
 * the page and the timeline.
 */
export function RemoveRecordButton({ label }: { label: string }) {
  const { currentEdit, exitEditMode } = useEditManager();
  const { timeFrames } = useTimeFrame();
  const { mutate } = useSWRConfig();
  const { toast } = useToast();
  const describe = useDescribeValue();
  const source = currentEdit.source;
  const { periods, loaded } = useFieldTimeline(source);
  const [open, setOpen] = useState(false);
  const [pending, startTransition] = useTransition();

  if (!isRemovable(source)) return null;
  const validFrom = currentEdit.validFrom ?? null;
  const validTo = currentEdit.validTo ?? null;
  const summary = validFrom && loaded ? removalSummary(periods, validFrom, validTo) : null;
  // Nothing recorded in the stretch: there is nothing to remove.
  const disabled = !summary || summary.removed.length === 0 || pending;
  const pastFrames = framesNeedingConfirmation(timeFrames, validFrom, validTo);

  const piece = (p: RemovalPiece) => (
    <li key={`${p.valid_from}`} className="tabular-nums">
      {p.valid_from} – {formatEnd(p.valid_to)}: {describe.value(p.values) ?? "Empty"}
    </li>
  );

  const confirm = () => {
    if (!validFrom) return;
    startTransition(async () => {
      const result = await removeTemporalRecord({
        table: source.table,
        match: source.match,
        validFrom,
        validTo,
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
        await mutate((key) => Array.isArray(key) && ["details", "field-timeline"].includes(key[0]));
        exitEditMode();
      }
    });
  };

  return (
    <>
      <Button
        type="button"
        variant="outline"
        className="mr-auto border-red-700 text-red-700 hover:bg-red-50 hover:text-red-800"
        disabled={disabled}
        onClick={() => setOpen(true)}
        data-remove-record=""
        title={disabled && !pending ? "Nothing is recorded in this stretch" : undefined}
      >
        Remove {validFrom ?? ""} – {formatEnd(validTo)}
      </Button>
      {open && summary && (
        <AlertDialog open onOpenChange={(o) => !o && !pending && setOpen(false)}>
          <AlertDialogContent data-remove-confirmation="">
            <AlertDialogHeader>
              <AlertDialogTitle>Remove {label.toLowerCase()}?</AlertDialogTitle>
              <AlertDialogDescription asChild>
                <div className="space-y-3 text-sm">
                  <div>
                    <p className="font-medium text-zinc-900">Removed</p>
                    <ul className="list-disc pl-5" data-remove-removed="">
                      {summary.removed.map(piece)}
                    </ul>
                  </div>
                  <div>
                    <p className="font-medium text-zinc-900">Kept</p>
                    {summary.kept.length > 0 ? (
                      <ul className="list-disc pl-5" data-remove-kept="">
                        {summary.kept.map(piece)}
                      </ul>
                    ) : (
                      <p data-remove-kept="">Nothing: the {label.toLowerCase()} is removed completely.</p>
                    )}
                  </div>
                  {pastFrames.length > 0 && (
                    <div data-remove-past-frames="">
                      <p>This reaches into {pastFrames.map((f) => f.name).join(", ")}.</p>
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
