"use client";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Pencil } from "lucide-react";
import { Input } from "../ui/input";
import { Label } from "../ui/label";
import { useEditManager } from "@/atoms/edits";
import { useStartEdit } from "./use-start-edit";
import type { EditFieldSource } from "./read-edit-range";
import { SubmissionFeedbackDebugInfo } from "./submission-feedback-debug-info";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { EditMetadataControls } from "./edit-metadata-controls";
import { useEditableFieldState } from "./use-editable-field-state";
import { EditButton } from "./edit-button";
import { MetadataTooltip } from "./metadata-tooltip";
import { FieldTimelineButton } from "./field-timeline-view";
import { useEditStartValues } from "./use-edit-start-values";
import { RemoveRecordAction } from "./remove-record-button";
import { DIFFERS } from "./edit-payload";
import { DiffersNote } from "./differing-values";

interface EditableFieldWithMetadataProps {
  fieldId: string;
  fieldName?: string;
  label: string;
  value: string | number | null;
  formAction: (formData: FormData) => void;
  response: UpdateResponse;
  hiddenFields?: Record<string, string | number>;
  metadata?: Metadata;
  /** The rows this field shows over time; the edit then opens on the shown value's stretch. */
  editSource?: EditFieldSource;
}
export const EditableFieldWithMetadata = ({
  fieldId,
  fieldName,
  label,
  value,
  formAction,
  response,
  hiddenFields,
  metadata,
  editSource,
}: EditableFieldWithMetadataProps) => {
  const startEdit = useStartEdit();
  const [showResponse, setShowResponse] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const formRef = useRef<HTMLFormElement>(null);

  const { currentEdit, exitEditMode } = useEditManager();
  const isEditing = currentEdit?.fieldId === fieldId;
  // Remove mode (the panel's Change | Remove): the value is not changed, so the
  // input is locked and the red Remove takes Save's place.
  const removing = isEditing && currentEdit.removing != null;
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
  // The input starts from the ticked stretch's own value, so Save keeps it
  // unless the user changes it (owner 2026-11-13). When the ticked periods
  // differ it starts empty with "Differs" shown, and Save keeps each period's
  // own value until the user types one (owner 2026-11-16).
  const column =
    editSource && !Array.isArray(editSource.column) ? editSource.column : null;
  const start = useEditStartValues(isEditing, editSource, (start) => {
    if (column && column in start.values)
      setCurrentValue(
        start.differing.includes(column)
          ? DIFFERS
          : String(start.values[column] ?? "")
      );
  });

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
          <div className="flex items-center h-10">
            <Label className="text-xs uppercase text-gray-600">{label}</Label>
            {/* The icons sit beside the label, not in it: a label passes hover and clicks to its first button. */}
            {metadata && <MetadataTooltip metadata={metadata} />}
            {editSource && (
              <FieldTimelineButton source={editSource} label={label} />
            )}
          </div>
          <div className="flex space-x-2 items-center">
            {!isEditing && (
              <EditButton
                className="h-8"
                variant="ghost"
                size="sm"
                type="button"
                onClick={() => startEdit(fieldId, editSource, value, metadata)}
              >
                <Pencil className="text-zinc-700" />
              </EditButton>
            )}
          </div>
        </div>
        <Input
          ref={inputRef}
          className={`font-medium disabled:opacity-80 bg-white border-zinc-300 placeholder:text-amber-800`}
          disabled={!isEditing || removing}
          value={currentValue === DIFFERS ? "" : currentValue}
          placeholder={currentValue === DIFFERS ? "Differs" : undefined}
          onChange={(e) => setCurrentValue(e.target.value)}
          autoComplete="off"
        />
        {/* The posted value: DIFFERS keeps each period's own (edit-payload). */}
        <input type="hidden" name={fieldName || fieldId} value={currentValue} />
      </div>
      {isEditing && !removing && column && (
        <DiffersNote column={column} start={start} current={String(currentValue)} />
      )}
      {isEditing && (
        <div className="space-y-2">
          {hiddenFields &&
            Object.entries(hiddenFields).map(([name, value]) => (
              <input key={name} type="hidden" name={name} value={value} />
            ))}

          <EditMetadataControls fieldId={fieldId} label={label} />
          <div className="flex justify-end space-x-2">
            <Button
              className="h-8"
              variant="outline"
              type="button"
              onClick={handleCancel}
            >
              Cancel
            </Button>
            {removing ? (
              <RemoveRecordAction label={label} />
            ) : (
              <Button
                className="h-8"
                // disabled={!hasUnsavedChanges}
                type="button"
                onClick={triggerFormSubmit}
              >
                Save
              </Button>
            )}
          </div>
        </div>
      )}
      {showResponse && <SubmissionFeedbackDebugInfo state={response} />}
    </form>
  );
};
