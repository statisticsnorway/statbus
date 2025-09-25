"use client";

import { useRef, useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { Button } from "@/components/ui/button";
import { Pencil } from "lucide-react";
import { Input } from "../ui/input";
import { DeleteConfirmationDialog } from "./delete-confirmation-dialog";
import { Label } from "../ui/label";
import { useEditManager } from "@/atoms/edits";
import { cn } from "@/lib/utils";
import { useEditableFieldState } from "./use-editable-field-state";

interface EditableFieldProps {
  fieldId: string;
  label: string;
  value: string | null;
  formAction: (formData: FormData) => void;
  response: UpdateResponse;
}

export const EditableField = ({
  fieldId,
  label,
  value,
  formAction,
  response,
}: EditableFieldProps) => {
  const { currentEdit, setEditTarget, exitEditMode } = useEditManager();

  const isEditing = currentEdit?.fieldId === fieldId;
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const {
    currentValue,
    setCurrentValue,
    hasUnsavedChanges,
    handleCancel: baseHandleCancel,
  } = useEditableFieldState(value, response, isEditing, exitEditMode);

  useGuardedEffect(
    () => {
      // Focus the input when entering edit mode
      if (isEditing && inputRef.current) {
        inputRef.current.focus();
        const length = inputRef.current.value.length;
        inputRef.current.setSelectionRange(length, length);
      }
    },
    [isEditing],
    "EditableField:focusOnEdit"
  );


  const triggerFormSubmit = () => {
    formRef.current?.requestSubmit();
    setShowDeleteDialog(false); // Ensure dialog is closed if submission was from it
  };

  const handleSave = () => {
    if (!currentValue) {
      setShowDeleteDialog(true);
      return;
    }
    triggerFormSubmit();
  };

  const handleCancel = () => {

    baseHandleCancel()
    setShowDeleteDialog(false);
  };

  return (
    <form ref={formRef} action={formAction} className="flex flex-col">
      <div className="flex items-center justify-between">
        <Label className="flex flex-col space-y-2">
          <span className="text-xs uppercase text-gray-600">{label}</span>
        </Label>
        <div className="flex space-x-2 mb-1">
          {!isEditing ? (
            <Button
              className="h-8"
              variant="ghost"
              size="sm"
              type="button"
              onClick={() => setEditTarget(fieldId)}
            >
              <Pencil className="text-zinc-700" />
            </Button>
          ) : (
            <>
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
                onClick={handleSave}
              >
                Save
              </Button>
            </>
          )}
        </div>
      </div>
      {showDeleteDialog && (
        <DeleteConfirmationDialog
          label={label}
          onConfirm={triggerFormSubmit}
          onCancel={handleCancel}
        />
      )}
      <Input
        ref={inputRef}
        className={cn(
          "font-medium disabled:opacity-80",
          isEditing && "border-zinc-300"
        )}
        disabled={!isEditing}
        value={currentValue}
        onChange={(e) => setCurrentValue(e.target.value)}
        name={fieldId}
        autoComplete="off"
      />
    </form>
  );
};
