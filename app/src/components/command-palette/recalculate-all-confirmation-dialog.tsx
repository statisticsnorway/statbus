"use client";

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
import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { toast } from "@/hooks/use-toast";
import { getBrowserRestClient } from "@/context/RestClientStore";

export const SHOW_RECALCULATE_ALL_DIALOG_EVENT = "show-recalculate-all-dialog";

type RecalculateAllClient = {
  rpc: (fn: "recalculate_all") => PromiseLike<{
    data: number | null;
    error: { message: string } | null;
  }>;
};

// The toast the operator sees for each outcome of public.recalculate_all().
export async function startRecalculateAll(client: RecalculateAllClient) {
  try {
    const { data: taskId, error } = await client.rpc("recalculate_all");
    if (error) {
      return { title: "Recalculation not started", description: error.message };
    }
    if (taskId === null) {
      return {
        title: "Nothing to recalculate",
        description: "There are no statistical units yet.",
      };
    }
    return {
      title: "Recalculation started",
      description:
        "Every statistical unit and report is being recalculated. Progress is shown while it runs.",
    };
  } catch (error) {
    return {
      title: "Recalculation not started",
      description: error instanceof Error ? error.message : String(error),
    };
  }
}

// Asks before scheduling public.recalculate_all(): a full recalculation of
// every statistical unit and report runs for many minutes on a large register,
// so a mis-click must not start one. The database grants the call to admins
// only; this dialog is not the authorization.
export function RecalculateAllConfirmationDialog() {
  const [open, setOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  useGuardedEffect(
    () => {
      const showDialog = () => setOpen(true);
      document.addEventListener(SHOW_RECALCULATE_ALL_DIALOG_EVENT, showDialog);
      return () => {
        document.removeEventListener(SHOW_RECALCULATE_ALL_DIALOG_EVENT, showDialog);
      };
    },
    [],
    "RecalculateAllConfirmationDialog:showDialogListener"
  );

  const handleConfirm = async (e: React.MouseEvent) => {
    e.preventDefault();
    setIsLoading(true);
    try {
      toast(await startRecalculateAll(await getBrowserRestClient()));
    } finally {
      setIsLoading(false);
      setOpen(false);
    }
  };

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Recalculate everything?</AlertDialogTitle>
          <AlertDialogDescription>
            This recalculates every statistical unit and every report from the
            registered data. On a large register it takes many minutes, and the
            results update while it runs. No data is changed or lost.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={isLoading}>Cancel</AlertDialogCancel>
          <AlertDialogAction onClick={(e) => handleConfirm(e)} disabled={isLoading}>
            {isLoading ? "Starting..." : "Recalculate"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
