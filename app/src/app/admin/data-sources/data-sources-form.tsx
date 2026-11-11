"use client";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { AdminDialogFooter } from "@/app/admin/admin-dialog-footer";
import { Tables } from "@/lib/database.types";
import { useActionState } from "react";
import { FormField } from "@/components/form/form-field";
import { SubmissionFeedbackDebugInfo } from "@/components/form/submission-feedback-debug-info";
import { SwitchField } from "@/components/form/switch-field";
import { createDataSource, updateDataSource } from "./update-data-sources";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";


export function DataSourceForm({
  dataSource,
  isOpen,
  onOpenChange,
  onSuccess,
}: {
  readonly dataSource: Tables<"data_source"> | null;
  readonly isOpen: boolean;
  readonly onOpenChange: (isOpen: boolean) => void;
  readonly onSuccess: () => void;
}) {
  const isEdit = !!dataSource;
  const action = isEdit ? updateDataSource.bind(null, dataSource.id) : createDataSource;
  const [state, formAction, pending] = useActionState(action, null);

  useGuardedEffect(
    () => {
      if (state?.status === "success") {
        onSuccess();
        onOpenChange(false);
      }
    },
    [state?.status, onOpenChange, onSuccess],
    "DataSourcesForm:closeOnSuccess"
  );

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <form action={formAction} autoComplete="off">
          <DialogHeader>
            <DialogTitle className="text-center mb-4">
              {isEdit ? "Edit data source" : "Create new data source"}
            </DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid gap-1">
              <FormField
                label="Name"
                name="name"
                response={state}
                value={isEdit ? dataSource.name : ""}
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
                value={isEdit ? dataSource.code : ""}
              />
              <span className="text-xs text-gray-400 pl-1">
                Code used in{" "}
                <span className="bg-gray-100 px-0.5 font-mono">
                  data_source_code
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
                value={isEdit ? dataSource.enabled : true}
              />
            </div>
          </div>
          <AdminDialogFooter submitLabel={isEdit ? "Save changes" : "Create"} pending={pending} state={state} />
        </form>
      </DialogContent>
      <SubmissionFeedbackDebugInfo state={state} />
    </Dialog>
  );
}
