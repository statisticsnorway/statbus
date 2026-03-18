"use client";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Tables } from "@/lib/database.types";
import { useActionState } from "react";
import { FormField } from "@/components/form/form-field";
import { SubmissionFeedbackDebugInfo } from "@/components/form/submission-feedback-debug-info";
import { SwitchField } from "@/components/form/switch-field";
import { createUnitSize, updateUnitSize } from "./update-unit-sizes";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";


export function UnitSizeForm({
  unitSize,
  isOpen,
  onOpenChange,
  onSuccess,
}: {
  readonly unitSize: Tables<"unit_size"> | null;
  readonly isOpen: boolean;
  readonly onOpenChange: (isOpen: boolean) => void;
  readonly onSuccess: () => void;
}) {
  const isEdit = !!unitSize;
  const action = isEdit ? updateUnitSize.bind(null, unitSize.id) : createUnitSize;
  const [state, formAction] = useActionState(action, null);

  useGuardedEffect(
    () => {
      if (state?.status === "success") {
        onSuccess();
        onOpenChange(false);
      }
    },
    [state?.status, onOpenChange, onSuccess],
    "UnitSizeForm:closeOnSuccess"
  );

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <form action={formAction} autoComplete="off">
          <DialogHeader>
            <DialogTitle className="text-center mb-4">
              {isEdit ? "Edit unit size" : "Create new unit size"}
            </DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid gap-1">
              <FormField
                label="Name"
                name="name"
                response={state}
                value={isEdit ? unitSize.name : ""}
              />
              <span className="text-xs text-gray-400 pl-1">
                Label shown in Statbus
              </span>
            </div>
            <div className="grid gap-1">
              <FormField
                label="Code"
                name="code"
                response={state}
                value={isEdit ? unitSize.code : ""}
              />
              <span className="text-xs text-gray-400 pl-1">
                Code used in{" "}
                <span className="bg-gray-100 px-0.5 font-mono">
                  unit_size_code
                </span>{" "}
                column in CSV files
              </span>
            </div>
            <div className="my-1 bg-gray-50 border-1 rounded-md p-2">
              <SwitchField
                name="enabled"
                label={
                  <div className="flex flex-col space-x-2 space-y-1">
                    <span>Enabled</span>
                    <span className="text-xs text-gray-400 font-normal">
                      Visible in application and available for loading
                    </span>
                  </div>
                }
                response={state}
                value={isEdit ? unitSize.enabled : true}
              />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit">{isEdit ? "Save changes" : "Create"}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
      <SubmissionFeedbackDebugInfo state={state} />
    </Dialog>
  );
}
