"use client";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Tables } from "@/lib/database.types";
import { useActionState, useState } from "react";
import { FormField } from "@/components/form/form-field";
import { SubmissionFeedbackDebugInfo } from "@/components/form/submission-feedback-debug-info";
import { SwitchField } from "@/components/form/switch-field";
import {
  createStatDefinition,
  updateStatDefinition,
} from "./update-statistical-variables";
import { SelectField } from "@/components/form/select-field";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
 const typeOptions = [
   { value: "int", label: "Integer" },
   { value: "float", label: "Float" },
 ];
export function StatDefinitionForm({
  statDefinition,
  isOpen,
  onOpenChange,
  onSuccess,
}: {
  readonly statDefinition: Tables<"stat_definition"> | null;
  readonly isOpen: boolean;
  readonly onOpenChange: (isOpen: boolean) => void;
  readonly onSuccess: () => void;
}) {
  const isEdit = !!statDefinition;
  const action = isEdit
    ? updateStatDefinition.bind(null, statDefinition.id)
    : createStatDefinition;
  const [state, formAction] = useActionState(action, null);

  useGuardedEffect(
    () => {
      if (state?.status === "success") {
        onSuccess();
        onOpenChange(false);
      }
    },
    [state?.status, onOpenChange, onSuccess],
    "StatisticalVariablesForm:closeOnSuccess"
  );

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[525px]">
        <form action={formAction} autoComplete="off">
          <DialogHeader>
            <DialogTitle className="text-center mb-4">
              {isEdit
                ? "Edit statistical variable"
                : "Create new statistical variable"}
            </DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid grid-cols-2 gap-2">
              <div>
                <FormField
                  label="Name"
                  name="name"
                  response={state}
                  value={isEdit ? statDefinition.name : ""}
                />
                <span className="text-xs text-gray-400 pl-1">
                  Label shown in Statbus
                </span>
              </div>
              <div>
                <FormField
                  label="Code"
                  name="code"
                  response={state}
                  value={isEdit ? statDefinition.code : ""}
                />
                <span className="text-xs text-gray-400 pl-1">
                  Used as column name in CSV files
                </span>
              </div>
            </div>
            <div className="grid gap-2">
              <FormField
                label="Description"
                name="description"
                response={state}
                value={isEdit ? (statDefinition.description ?? "") : ""}
                placeholder="Optional description"
              />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <SelectField
                label="Type"
                name="type"
                options={typeOptions}
                response={state}
                value={isEdit ? (statDefinition.type ?? "") : ""}
                placeholder="Variable type"
              />
              <FormField
                label="Priority"
                name="priority"
                type="number"
                response={state}
                value={isEdit ? (statDefinition.priority ?? "") : ""}
                placeholder="Display order"
              />
            </div>
            <div className="mb-1 bg-gray-50 border-1 rounded-md p-2">
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
                value={isEdit ? statDefinition.enabled : true}
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
