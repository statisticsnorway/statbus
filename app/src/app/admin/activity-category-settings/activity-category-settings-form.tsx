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
import { useActionState } from "react";
import { FormField } from "@/components/form/form-field";
import { SubmissionFeedbackDebugInfo } from "@/components/form/submission-feedback-debug-info";
import { SwitchField } from "@/components/form/switch-field";
import { SelectField } from "@/components/form/select-field";
import { updateActivityCategorySettings } from "./update-activity-category-settings";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

export function ActivityCategorySettingsForm({
  activityCategorySetting,
  isOpen,
  onOpenChange,
  onSuccess,
}: {
  readonly activityCategorySetting: Tables<"activity_category_standard">;
  readonly isOpen: boolean;
  readonly onOpenChange: (isOpen: boolean) => void;
  readonly onSuccess: () => void;
}) {
  const isEdit = !!activityCategorySetting;
  const action = updateActivityCategorySettings.bind(null, activityCategorySetting.id);
  const [state, formAction] = useActionState(action, null);

  useGuardedEffect(
    () => {
      if (state?.status === "success") {
        onSuccess();
        onOpenChange(false);
      }
    },
    [state?.status, onOpenChange, onSuccess],
    "ActivityCategorySettingsForm:closeOnSuccess"
  );

  const codePatternOptions = [
    { value: "digits", label: "Digits" },
    { value: "dot_after_two_digits", label: "Dot after two digits" },
  ];

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <form action={formAction} autoComplete="off">
          <DialogHeader>
            <DialogTitle className="text-center mb-4">
             Edit activity category standard
            </DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <FormField
              label="Name"
              name="name"
              response={state}
              value={isEdit ? activityCategorySetting.name : ""}
            />
            <FormField
              label="Code"
              name="code"
              response={state}
              value={isEdit ? activityCategorySetting.code : ""}
            />
            <FormField
              label="Description"
              name="description"
              response={state}
              value={isEdit ? (activityCategorySetting.description ?? "") : ""}
              placeholder="Optional description"
            />
            <SelectField
              label="Code Pattern"
              name="code_pattern"
              options={codePatternOptions}
              response={state}
              value={isEdit ? (activityCategorySetting.code_pattern ?? "") : ""}
              placeholder="Code pattern of the activity category standard"
            />
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
                value={isEdit ? activityCategorySetting.enabled : true}
              />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit">Save changes</Button>
          </DialogFooter>
        </form>
      </DialogContent>
      <SubmissionFeedbackDebugInfo state={state} />
    </Dialog>
  );
}
