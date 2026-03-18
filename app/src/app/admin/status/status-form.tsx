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
import { createStatusCode, updateStatusCode } from "./update-statuses";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

export function StatusForm({
  statusCode,
  isOpen,
  onOpenChange,
  onSuccess,
}: {
  readonly statusCode: Tables<"status"> | null;
  readonly isOpen: boolean;
  readonly onOpenChange: (isOpen: boolean) => void;
  readonly onSuccess: () => void;
}) {
  const isEdit = !!statusCode;
  const action = isEdit
    ? updateStatusCode.bind(null, statusCode.id)
    : createStatusCode;
  const [state, formAction] = useActionState(action, null);

  useGuardedEffect(
    () => {
      if (state?.status === "success") {
        onSuccess();
        onOpenChange(false);
      }
    },
    [state?.status, onOpenChange, onSuccess],
    "StatusForm:closeOnSuccess"
  );

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <form action={formAction} autoComplete="off">
          <DialogHeader>
            <DialogTitle className="text-center mb-4">
              {isEdit ? "Edit status" : "Create new status"}
            </DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid gap-2">
              <FormField
                label="Name"
                name="name"
                response={state}
                value={isEdit ? statusCode.name : ""}
              />
              <span className="text-xs text-gray-400 pl-1">
                Label shown in Statbus
              </span>
            </div>
            <div className="grid gap-2">
              <FormField
                label="Code"
                name="code"
                response={state}
                value={isEdit ? statusCode.code : ""}
              />
              <span className="text-xs text-gray-400 pl-1">
                Code used in{" "}
                <span className="bg-gray-100 px-0.5 font-mono">
                  status_code
                </span>{" "}
                column in CSV files
              </span>
            </div>
            <FormField
              label="Priority"
              name="priority"
              type="number"
              response={state}
              value={isEdit ? (statusCode.priority ?? "") : ""}
              placeholder="Display order"
            />

            <div className="flex flex-col gap-4 p-2">
              <div className="grid gap-2">
                <SwitchField
                  name="assigned_by_default"
                  label={
                    <div className="flex flex-col space-x-2 space-y-1">
                      <span>Assigned by default</span>
                      <span className="text-xs text-gray-400 font-normal">
                        New units get this status automatically
                      </span>
                    </div>
                  }
                  response={state}
                  value={isEdit ? statusCode.assigned_by_default : false}
                />
              </div>
              <div className="grid gap-2">
                <SwitchField
                  name="used_for_counting"
                  label={
                    <div className="flex flex-col space-x-2 space-y-1">
                      <span>Used in statistics</span>
                      <span className="text-xs text-gray-400 font-normal">
                        Include units with this status in counts and reports
                      </span>
                    </div>
                  }
                  response={state}
                  value={isEdit ? statusCode.used_for_counting : true}
                />
              </div>{" "}
            </div>
            <div className="grid gap-2 mb-1 bg-gray-50 border-1 rounded-md p-2">
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
                value={isEdit ? statusCode.enabled : true}
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
