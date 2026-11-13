"use client";

import { useEditManager } from "@/atoms/edits";
import { Button } from "@/components/ui/button";
import { Pencil } from "lucide-react";
import { useMemo, useRef, useState } from "react";
import { SubmissionFeedbackDebugInfo } from "./submission-feedback-debug-info";
import { useStartEdit } from "./use-start-edit";
import type { EditFieldSource } from "./read-edit-range";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { EditMetadataControls } from "./edit-metadata-controls";
import { EditButton } from "./edit-button";
import { MetadataTooltip } from "./metadata-tooltip";
import { FieldTimelineButton, useFieldTimeline } from "./field-timeline-view";
import { RemoveRecordAction } from "./remove-record-button";
import { periodsInRange } from "./field-timeline";
import { editStartValues } from "./edit-values";

/**
 * A field's value in the form: while editing, the ticked stretch's own value
 * for the column (editStartValues); otherwise the value shown on the page.
 */
export type FieldValueOf = (
  column: string,
  shown: string | number | null | undefined
) => string | number | null | undefined;

interface EditableFieldGroupProps {
  fieldGroupId: string;
  title: string;
  action: (formData: FormData) => void;
  response: UpdateResponse;
  metadata?: Metadata;
  /** The rows this group shows over time; the edit then opens on the shown values' stretch. */
  editSource?: EditFieldSource;
  /** The group's shown values by column, compared with editSource's rows. */
  shownValues?: object;
  children: (props: {
    isEditing: boolean;
    valueOf: FieldValueOf;
  }) => React.ReactNode;
  hiddenFields?: Record<string, string | number>;
}

export function EditableFieldGroup({
  fieldGroupId,
  title,
  action,
  response,
  metadata,
  children,
  hiddenFields,
  editSource,
  shownValues,
}: EditableFieldGroupProps) {
  const startEdit = useStartEdit();
  const formRef = useRef<HTMLFormElement>(null);
  const [formKey, setFormKey] = useState(0);

  const { currentEdit, exitEditMode, setEditDataSourceId } = useEditManager();

  const isEditing = currentEdit?.fieldId === fieldGroupId;

  // The edit writes every field over the ticked stretch, so the fields start
  // from that stretch's own values and data source, not the page's (Live's).
  // A field the user leaves alone then keeps its value (owner 2026-11-13).
  const { periods } = useFieldTimeline(isEditing ? editSource : undefined);
  const ticked = isEditing
    ? periodsInRange(periods, currentEdit.validFrom, currentEdit.validTo)
    : [];
  const tickedKey = ticked.join(",");
  const start = useMemo(
    () => editStartValues(periods, ticked),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [periods, tickedKey]
  );
  const valueOf: FieldValueOf = (column, shown) =>
    isEditing && start && column in start.values
      ? (start.values[column] as string | number | null)
      : shown;
  useGuardedEffect(
    () => {
      if (isEditing && start)
        setEditDataSourceId(start.dataSourceId?.toString() ?? null);
    },
    [isEditing, tickedKey, start],
    "EditableFieldGroup:dataSourceFromTicked"
  );
  // Remove mode (the Timeline's Change | Remove switch): the fields are not
  // changed, so they are greyed, and the red Remove takes Save's place.
  const removing = isEditing && currentEdit.removing != null;
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
      {hiddenFields &&
        Object.entries(hiddenFields).map(([name, value]) => (
          <input key={name} type="hidden" name={name} value={value} />
        ))}
      <div className="flex justify-between items-center h-8">
        <div className="flex items-center">
          <span className="font-medium">{title}</span>
          {metadata && <MetadataTooltip metadata={metadata} />}
          {editSource && (
            <FieldTimelineButton source={editSource} label={title} />
          )}
        </div>
        {!isEditing && (
          <EditButton
            variant="ghost"
            size="icon"
            type="button"
            onClick={() =>
              startEdit(fieldGroupId, editSource, shownValues, metadata)
            }
            className="h-8 w-8"
          >
            <Pencil className="h-4 w-4 text-zinc-700" />
          </EditButton>
        )}
      </div>

      <fieldset
        disabled={removing}
        className={removing ? "opacity-50" : undefined}
      >
        {children({ isEditing, valueOf })}
      </fieldset>

      {isEditing && !removing && start && start.differing.length > 0 && (
        <p
          className="text-sm text-amber-800"
          data-edit-differing={start.differing.join(",")}
        >
          The ticked periods hold different values for{" "}
          {start.differing.map((c) => c.replace(/_/g, " ")).join(", ")}. Saving
          gives
          {start.differing.length > 1 ? " each" : " it"} the value shown over
          the whole stretch.
        </p>
      )}

      {isEditing && (
        <div className="space-y-2">
          <EditMetadataControls fieldId={fieldGroupId} />
          <div className="flex justify-end space-x-2">
            <Button variant="outline" type="button" onClick={handleCancel}>
              Cancel
            </Button>
            {removing ? (
              <RemoveRecordAction label={title} />
            ) : (
              <Button type="submit">Save</Button>
            )}
          </div>
        </div>
      )}
      <SubmissionFeedbackDebugInfo state={response} />
    </form>
  );
}
