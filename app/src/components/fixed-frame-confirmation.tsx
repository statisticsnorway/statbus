"use client";
import { useCallback, useState } from "react";
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
import { useTimeFrame } from "@/atoms/app-derived";
import { framesNeedingConfirmation, type TimeFrame } from "@/lib/time-frame";

/**
 * Asks before a change reaches into a relative or fixed frame
 * (framesNeedingConfirmation). `ask(validFrom, validTo, onConfirm)` returns
 * false for a change in the live frame, so the caller goes ahead at once.
 * Otherwise it opens the dialog naming the frames and returns true: the caller
 * holds the change, onConfirm runs on Confirm, and Cancel stores nothing.
 * The question lives in the UI only: the database stores what it is given.
 */
export function useFixedFrameConfirmation() {
  const { timeFrames } = useTimeFrame();
  const [pending, setPending] = useState<{ frames: TimeFrame[]; action: () => void } | null>(null);

  const ask = useCallback(
    (validFrom: string | null | undefined, validTo: string | null | undefined, onConfirm: () => void): boolean => {
      const frames = framesNeedingConfirmation(timeFrames, validFrom, validTo);
      if (frames.length === 0) return false;
      setPending({ frames, action: onConfirm });
      return true;
    },
    [timeFrames]
  );

  const dialog = pending ? (
    <AlertDialog open onOpenChange={(open) => !open && setPending(null)}>
      <AlertDialogContent data-fixed-frame-confirmation>
        <AlertDialogHeader>
          <AlertDialogTitle>Change a past frame?</AlertDialogTitle>
          <AlertDialogDescription asChild>
            <div className="space-y-2">
              <p>This change reaches into:</p>
              <ul className="list-disc pl-5" data-fixed-frame-names>
                {pending.frames.map((f) => (
                  <li key={f.ident!}>{f.name}</li>
                ))}
              </ul>
              <p>Reports and figures for these years will change.</p>
            </div>
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel onClick={() => setPending(null)}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={() => {
              const { action } = pending;
              setPending(null);
              action();
            }}
          >
            Change {pending.frames.length === 1 ? "this frame" : "these frames"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  ) : null;

  return { ask, dialog };
}
