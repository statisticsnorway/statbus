"use client";

import { useEditManager } from "@/atoms/edits";
import { Button } from "@/components/ui/button";
import { Pencil } from "lucide-react";
import { useRef, useState } from "react";
import { SubmissionFeedbackDebugInfo } from "./submission-feedback-debug-info";
import { useTimeContext } from "@/atoms/app-derived";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { EditMetadataControls } from "./edit-metadata-controls";
import { EditButton } from "./edit-button";

interface EditableFieldGroupProps {
  fieldGroupId: string;
  title: string;
  action: (formData: FormData) => void;
  response: UpdateResponse;
  children: (props: { isEditing: boolean }) => React.ReactNode;
}

export function EditableFieldGroup({
  fieldGroupId,
  title,
  action,
  response,
  children,
}: EditableFieldGroupProps) {
  const { selectedTimeContext } = useTimeContext();
  const formRef = useRef<HTMLFormElement>(null);
  const [formKey, setFormKey] = useState(0);

  const { currentEdit, setEditTarget, exitEditMode } = useEditManager();

  const isEditing = currentEdit?.fieldId === fieldGroupId;
  const wasEditing = useRef(isEditing);
  const isExitingOnSuccess = useRef(false);

  useGuardedEffect(
    () => {
      // If we were editing but are no longer...
      if (wasEditing.current && !isEditing) {
        if (isExitingOnSuccess.current) {
          // It was a successful save, so don't reset the form.
          // Just reset the flag for the next interaction.
          isExitingOnSuccess.current = false;
        } else {
          // It was a cancel or context switch, so reset the form.
          setFormKey((prevKey) => prevKey + 1);
        }
      }
      wasEditing.current = isEditing;
    },
    [isEditing],
    "EditableFieldGroup:resetOnEditChange"
  );
  useGuardedEffect(
    () => {
      if (response?.status === "success" && isEditing) {
        isExitingOnSuccess.current = true;
        exitEditMode();
      }
    },
    [response],
    "EditableFieldGroup:exitOnSuccess"
  );
  const handleCancel = () => {
    exitEditMode();
  };
  return (
    <form
      ref={formRef}
      action={action}
      className={`flex flex-col space-y-2 p-3 ${isEditing && "bg-ssb-light rounded-md"}`}
      key={formKey}
    >
      <div className="flex justify-between items-center h-8">
        <span className="font-medium">{title}</span>
        {!isEditing && (
          <EditButton
            variant="ghost"
            size="icon"
            type="button"
            onClick={() =>
              setEditTarget(fieldGroupId, {
                validFrom: selectedTimeContext?.valid_from,
                validTo:
                  selectedTimeContext?.valid_to === "infinity"
                    ? null
                    : selectedTimeContext?.valid_to,
              })
            }
            className="h-8 w-8"
          >
            <Pencil className="h-4 w-4 text-zinc-700" />
          </EditButton>
        )}
      </div>

      {children({ isEditing })}

      {isEditing && (
        <div className="space-y-2">
          <EditMetadataControls fieldId={fieldGroupId} />
          <div className="flex justify-end space-x-2">
            <Button variant="outline" type="button" onClick={handleCancel}>
              Cancel
            </Button>
            <Button type="submit">Save</Button>
          </div>
        </div>
      )}
      <SubmissionFeedbackDebugInfo state={response} />
    </form>
  );
}
