"use client";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DialogClose, DialogFooter } from "@/components/ui/dialog";

/**
 * The footer of every admin dialog form (statistical variables, identifier
 * types, data sources, statuses, unit sizes, activity category settings,
 * users): Cancel and the submit button. While the server action runs (the
 * `pending` of useActionState) both are disabled and the submit button reads
 * "Saving…", because some saves take seconds on a full register (a statistical
 * variable on Norway: 9 to 13 s, STATBUS-619). A failed save shows the server's
 * message above the buttons; field errors stay on their fields.
 */
export function AdminDialogFooter({
  submitLabel,
  pending,
  state,
}: {
  readonly submitLabel: string;
  readonly pending: boolean;
  readonly state: UpdateResponse;
}) {
  return (
    <>
      {!pending && state?.status === "error" && (
        <p role="alert" className="text-sm text-red-600">
          {state.message}
        </p>
      )}
      <DialogFooter>
        <DialogClose asChild>
          <Button variant="outline" disabled={pending}>
            Cancel
          </Button>
        </DialogClose>
        <Button type="submit" disabled={pending}>
          {pending ? (
            <>
              <Loader2 className="animate-spin" aria-hidden />
              Saving…
            </>
          ) : (
            submitLabel
          )}
        </Button>
      </DialogFooter>
    </>
  );
}
