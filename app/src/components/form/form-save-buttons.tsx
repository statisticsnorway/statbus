"use client";
import { Loader2 } from "lucide-react";
import { useFormStatus } from "react-dom";
import { Button } from "@/components/ui/button";

type ButtonProps = React.ComponentProps<typeof Button>;

/**
 * The pending state of a unit edit form (legal unit, establishment,
 * enterprise): while the form's action runs, its Save reads "Saving…" with a
 * spinner and both Save and Cancel are disabled. On Norway a save waits for the
 * recalculation, seconds with nothing to see, so a user clicked again or left
 * (m6mnnw). The admin dialogs show the same (AdminDialogFooter).
 *
 * Both read the form's own status (useFormStatus), so they must sit inside the
 * <form> whose action they follow.
 */
export function FormSaveButton({
  children,
  disabled,
  ...props
}: Omit<ButtonProps, "children"> & { readonly children: React.ReactNode }) {
  const { pending } = useFormStatus();
  return (
    <Button {...props} disabled={pending || disabled}>
      {pending ? (
        <>
          <Loader2 className="animate-spin" aria-hidden />
          Saving…
        </>
      ) : (
        children
      )}
    </Button>
  );
}

/** Cancel of a unit edit form: disabled while the form's save runs. */
export function FormCancelButton({
  disabled,
  ...props
}: Omit<ButtonProps, "children">) {
  const { pending } = useFormStatus();
  return (
    <Button variant="outline" type="button" {...props} disabled={pending || disabled}>
      Cancel
    </Button>
  );
}
