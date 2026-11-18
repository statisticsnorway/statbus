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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useRouter } from "next/navigation";
import { toast } from "@/hooks/use-toast";
import { Enums } from "@/lib/database.types";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { useSetAtom } from "jotai";
import { RESET } from "jotai/utils";
import { gettingStartedUIStateAtom, refreshGettingStartedAtom } from "@/atoms/getting-started";
import { selectedTimeFrameAtom } from "@/atoms/app";
import { refreshBaseDataAtom } from "@/atoms/base-data";

export function ResetConfirmationDialog() {
  const router = useRouter();
  const setGettingStartedUIState = useSetAtom(gettingStartedUIStateAtom);
  const setSelectedTimeFrame = useSetAtom(selectedTimeFrameAtom);
  const refreshGettingStarted = useSetAtom(refreshGettingStartedAtom);
  const refreshBaseData = useSetAtom(refreshBaseDataAtom);
  const [open, setOpen] = useState(false);
  const [scope, setScope] = useState<Enums<"reset_scope">>("units");
  const [isLoading, setIsLoading] = useState(false);

  useGuardedEffect(
    () => {
      const showDialog = () => {
        setOpen(true);
      };

      document.addEventListener("show-reset-dialog", showDialog);
      return () => {
        document.removeEventListener("show-reset-dialog", showDialog);
      };
    },
    [],
    "ResetConfirmationDialog:showDialogListener"
  );

  const handleConfirm = async (e: React.MouseEvent) => {
    e.preventDefault();
    setIsLoading(true);
    try {
      const client = await getBrowserRestClient();
      const { data: summary, error } = await client.rpc("reset", {
        scope: scope,
        confirmed: true,
      });

      if (error) {
        toast({
          title: "System Reset Failed",
          description: error.message,
        });
      } else {
        console.log("Reset summary", JSON.stringify(summary, null, 2));
        toast({
          title: "System Reset OK",
          description: "All data has been reset.",
        });
        // The app's cached Getting started steps and base data describe the
        // database before the reset; read them again so every screen shows
        // what is there now.
        setGettingStartedUIState(RESET);
        setSelectedTimeFrame(RESET);
        refreshGettingStarted();
        refreshBaseData();
        router.push("/");
      }
    } catch (error) {
      toast({
        title: "System Reset Failed",
        description: "Error resetting data",
      });
    } finally {
      setIsLoading(false);
      setOpen(false);
    }
  };

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Are you sure?</AlertDialogTitle>
          <AlertDialogDescription>
            This action cannot be undone. This will permanently reset the
            selected data.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <div className="py-4">
          <Select
            value={scope}
            onValueChange={(value) => setScope(value as Enums<"reset_scope">)}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select scope" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="units">Units</SelectItem>
              <SelectItem value="getting-started">
                Units and Getting started
              </SelectItem>
              <SelectItem value="customisation">
                Units, Getting started and Customisation
              </SelectItem>
            </SelectContent>
          </Select>
        </div>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={isLoading}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={(e) => handleConfirm(e)}
            disabled={isLoading}
          >
            {isLoading ? "Resetting..." : "Continue"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
