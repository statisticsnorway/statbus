'use client';

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
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useToast } from "@/hooks/use-toast";
import { Enums } from "@/lib/database.types";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { useSetAtom } from "jotai";
import { RESET } from "jotai/utils";
import { gettingStartedUIStateAtom } from "@/atoms/getting-started";
import { selectedTimeContextAtom } from "@/atoms/app";

export function ResetConfirmationDialog() {
  const { toast } = useToast();
  const router = useRouter();
  const setGettingStartedUIState = useSetAtom(gettingStartedUIStateAtom);
  const setSelectedTimeContext = useSetAtom(selectedTimeContextAtom);

  useEffect(() => {
    const showDialog = () => {
      setOpen(true);
    };

    document.addEventListener('show-reset-dialog', showDialog);
    return () => {
      document.removeEventListener('show-reset-dialog', showDialog);
    };
  }, []);
  const [open, setOpen] = useState(false);
  const [scope, setScope] = useState<Enums<"reset_scope">>('data');
  const [isLoading, setIsLoading] = useState(false);

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
        // Clear persisted client-side state to avoid inconsistencies after a
        // server data reset. The page reload will handle re-fetching data.
        setGettingStartedUIState(RESET);
        setSelectedTimeContext(RESET);
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
              <SelectItem value="data">Units only</SelectItem>
              <SelectItem value="getting-started">
                Units and classifications
              </SelectItem>
              <SelectItem value="all">
                Units, classifications and customizations
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
