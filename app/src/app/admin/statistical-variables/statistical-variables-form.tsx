"use client";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { AdminDialogFooter } from "@/app/admin/admin-dialog-footer";
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
// How a legal unit's total of this variable combines its own value with its establishments'
// (stat_definition.lu_es_rollup, s465ff). Shown as the formula after Σ in the Links tree.
const luEsRollupOptions = [
  { value: "sum", label: "Add: legal unit + establishments" },
  { value: "max", label: "Larger of: legal unit or establishments" },
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
  const [state, formAction, pending] = useActionState(action, null);

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
                <span className="text-xs text-gray-400 pl-1 pt-1 block">
                  Used as column name in CSV files (no spaces or capital
                  letters)
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
            <div className="grid gap-1">
              <SelectField
                label="Legal unit total"
                name="lu_es_rollup"
                options={luEsRollupOptions}
                response={state}
                value={isEdit ? (statDefinition.lu_es_rollup ?? "sum") : "sum"}
                placeholder="How a legal unit's total is made"
              />
              <span className="text-xs text-gray-400 pl-1">
                Add when each value is reported on one level only. Larger of when the legal unit and
                its establishments both report the same people. Changing it recalculates the totals.
              </span>
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
          <AdminDialogFooter submitLabel={isEdit ? "Save changes" : "Create"} pending={pending} state={state} />
        </form>
      </DialogContent>
      <SubmissionFeedbackDebugInfo state={state} />
    </Dialog>
  );
}
