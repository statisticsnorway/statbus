"use client";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Pencil } from "lucide-react";
import { Input } from "../ui/input";
import { Label } from "../ui/label";
import { useEditManager } from "@/atoms/edits";
import { useTimeContext } from "@/atoms/app-derived";
import { SubmissionFeedbackDebugInfo } from "./submission-feedback-debug-info";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { EditMetadataControls } from "./edit-metadata-controls";
import { useEditableFieldState } from "./use-editable-field-state";
import { EditButton } from "./edit-button";

interface EditableFieldWithMetadataProps {
  fieldId: string;
  name?: string;
  label: string;
  value: string | number | null;
  formAction: (formData: FormData) => void;
  response: UpdateResponse;
  statType?: "int" | "float" | "string" | "bool";
  statDefinitionId?: number;
}
export const EditableFieldWithMetadata = ({
  fieldId,
  name,
  label,
  value,
  formAction,
  response,
  statType,
  statDefinitionId,
}: EditableFieldWithMetadataProps) => {
  const { selectedTimeContext } = useTimeContext();
  const [showResponse, setShowResponse] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const formRef = useRef<HTMLFormElement>(null);

  const { currentEdit, setEditTarget, exitEditMode } = useEditManager();
  const isEditing = currentEdit?.fieldId === fieldId;
  useGuardedEffect(
    () => {
      if (isEditing && inputRef.current) {
        inputRef.current.focus();
        const length = inputRef.current.value.length;
        inputRef.current.setSelectionRange(length, length);
      }
    },
    [isEditing],
    "EditableFieldWithMetadata:focusOnEdit"
  );

  const {
    currentValue,
    setCurrentValue,
    hasUnsavedChanges,
    handleCancel: baseHandleCancel,
  } = useEditableFieldState(value, response, isEditing, exitEditMode);

  const handleCancel = () => {
    baseHandleCancel();
    setShowResponse(false);
  };

  const triggerFormSubmit = () => {
    formRef.current?.requestSubmit();
    setShowResponse(true);
  };
  return (
    <form
      ref={formRef}
      action={formAction}
      className={`flex flex-col space-y-2 p-2 ${isEditing && "bg-ssb-light rounded-md "}`}
    >
      <div className="flex flex-col">
        <div className="flex items-center justify-between">
          <Label className="flex justify-between items-center h-10">
            <span className="text-xs uppercase text-gray-600">{label}</span>
          </Label>
          <div className="flex space-x-2 items-center">
            {!isEditing && (
              <EditButton
                className="h-8"
                variant="ghost"
                size="sm"
                type="button"
                onClick={() =>
                  setEditTarget(fieldId, {
                    validFrom: selectedTimeContext?.valid_from,
                    validTo:
                      selectedTimeContext?.valid_to === "infinity"
                        ? null
                        : selectedTimeContext?.valid_to,
                  })
                }
              >
                <Pencil className="text-zinc-700" />
              </EditButton>
            )}
          </div>
        </div>
        <Input
          ref={inputRef}
          className={`font-medium disabled:opacity-80 bg-white border-zinc-300`}
          disabled={!isEditing}
          value={currentValue}
          onChange={(e) => setCurrentValue(e.target.value)}
          name={name && statType ? `${name}_${statType}` : fieldId}
          autoComplete="off"
        />
      </div>
      {isEditing && (
        <div className="space-y-2">
          {statDefinitionId && (
            <input
              type="hidden"
              name="stat_definition_id"
              value={statDefinitionId}
            />
          )}
          <EditMetadataControls fieldId={fieldId} />
          <div className="flex justify-end space-x-2">
            <Button
              className="h-8"
              variant="outline"
              type="button"
              onClick={handleCancel}
            >
              Cancel
            </Button>
            <Button
              className="h-8"
              disabled={!hasUnsavedChanges}
              type="button"
              onClick={triggerFormSubmit}
            >
              Save
            </Button>
          </div>
        </div>
      )}
      {showResponse && <SubmissionFeedbackDebugInfo state={response} />}
    </form>
  );
};
