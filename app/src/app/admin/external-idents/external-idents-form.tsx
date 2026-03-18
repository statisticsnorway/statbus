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
import {
  createExternalIdentType,
  updateExternalIdentType,
} from "./update-external-idents";
import { SwitchField } from "@/components/form/switch-field";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

export function ExternalIdentTypeForm({
  externalIdentType,
  isOpen,
  onOpenChange,
  onSuccess,
}: {
  readonly externalIdentType: Tables<"external_ident_type"> | null;
  readonly isOpen: boolean;
  readonly onOpenChange: (isOpen: boolean) => void;
  readonly onSuccess: () => void;
}) {
  const isEdit = !!externalIdentType;
  const action = isEdit ? updateExternalIdentType.bind(null, externalIdentType.id) : createExternalIdentType;
  const [state, formAction] = useActionState(action, null);
  const [shape, setShape] = useState("regular");

  useGuardedEffect(
    () => {
      if (state?.status === "success") {
        onSuccess();
        onOpenChange(false);
      }
    },
    [state?.status, onOpenChange, onSuccess],
    "ExternalIdentsForm:closeOnSuccess"
  );

  useGuardedEffect(
    () => {
      setShape(isEdit ? externalIdentType.shape : "regular");
    },
    [isEdit, externalIdentType],
    "ExternalIdentsForm:syncShape"
  );

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[525px]">
        <form action={formAction} autoComplete="off">
          <DialogHeader>
            <DialogTitle className="text-center mb-4">
              {isEdit
                ? "Edit external identifier"
                : "Create new external identifier"}
            </DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid grid-cols-2 gap-2">
              <div>
                <FormField
                  label="Name"
                  name="name"
                  response={state}
                  value={isEdit ? externalIdentType.name : ""}
                />
                <span className="text-xs text-gray-500 pl-1">
                  Label shown in Statbus
                </span>
              </div>
              <div>
                <FormField
                  label="Code"
                  name="code"
                  response={state}
                  value={isEdit ? externalIdentType.code : ""}
                />
                <span className="text-xs text-gray-500 pl-1">
                  Used as column name in CSV files
                </span>
              </div>
            </div>
            <FormField
              label="Description"
              name="description"
              response={state}
              value={isEdit ? (externalIdentType.description ?? "") : ""}
              placeholder="Optional description"
            />
            <div className="grid gap-2">
              <Label className="text-xs uppercase text-gray-600">Type</Label>
              <RadioGroup
              name="shape"
                value={shape}
                onValueChange={(value) =>
                  setShape(value as "regular" | "hierarchical")
                }
                className="flex items-center space-x-4"
              >
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="regular" id="regular" />
                  <Label htmlFor="regular">Regular</Label>
                </div>
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="hierarchical" id="hierarchical" />
                  <Label htmlFor="hierarchical">Hierarchical</Label>
                </div>
              </RadioGroup>
            </div>
            {shape === "hierarchical" && (
              <div className="grid gap-2 bg-gray-50 border-1 rounded-md p-3">
                <FormField
                  label="Hierarchy Labels"
                  name="labels"
                  response={state}
                  value={isEdit ? (externalIdentType.labels ?? "") : ""}
                  placeholder="e.g. region.province.city"
                />
                <span className="text-xs text-gray-500">
                  Define hierarchy levels separated by a dot, e.g.
                  "region.province.city"
                </span>
              </div>
            )}
            <FormField
              label="Priority"
              name="priority"
              type="number"
              response={state}
              value={isEdit ? (externalIdentType.priority ?? "") : ""}
              placeholder="Display order"
            />
            <div className="mb-2 bg-gray-50 border-1 rounded-md p-2">
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
                value={isEdit ? externalIdentType.enabled : true}
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
