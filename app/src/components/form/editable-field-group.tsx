"use client";

import { useEditManager } from "@/atoms/edits";
import { Button } from "@/components/ui/button";
import { Pencil } from "lucide-react";
import { useRef, useState } from "react";
import { SubmissionFeedbackDebugInfo } from "./submission-feedback-debug-info";
import { useTimeContext } from "@/atoms/app-derived";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { EditMetadataControls } from "./edit-metadata-controls";

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

  useGuardedEffect(
    () => {
      if (response?.status === "success" && isEditing) {
        exitEditMode();
      }
    },
    [response],
    "EditableFieldGroup:exitOnSuccess"
  );
  const handleCancel = () => {
    setFormKey((prevKey) => prevKey + 1);
    exitEditMode();
  };
  return (
    <form
      ref={formRef}
      action={action}
      className={`flex flex-col space-y-2  p-3 ${isEditing && "bg-ssb-light rounded-md"}`}
      key={formKey}
    >
      <div className="flex justify-between items-center h-8">
        <span className="font-medium">{title}</span>
        {!isEditing && (
          <Button
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
          </Button>
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
