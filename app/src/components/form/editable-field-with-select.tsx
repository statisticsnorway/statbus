"use client";

import React, { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Check, ChevronsUpDown, Pencil } from "lucide-react";
import { Label } from "../ui/label";
import { useEditManager } from "@/atoms/edits";
import { Popover, PopoverContent, PopoverTrigger } from "../ui/popover";
import { cn } from "@/lib/utils";
import { useStartEdit } from "./use-start-edit";
import type { EditFieldSource } from "./read-edit-range";
import { SubmissionFeedbackDebugInfo } from "./submission-feedback-debug-info";

import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { EditMetadataControls } from "./edit-metadata-controls";
import { useEditableFieldState } from "./use-editable-field-state";
import { EditButton } from "./edit-button";
import { MetadataTooltip } from "./metadata-tooltip";
import { FieldTimelineButton } from "./field-timeline-view";
import { SaveApproval, useSaveApproval } from "./edit-metadata-controls";
import { PrimaryUnitNotice } from "./primary-unit-notice";
import { useEditAnchor } from "./use-edit-anchor";
import { RemoveRecordAction } from "./remove-record-button";
import { groupRuns } from "./code-list-options";

interface Option {
  value: string | number;
  label: string;
  disabled?: boolean;
  /** Group title shown above consecutive options that share it (codeListOptions). */
  group?: string;
}

interface EditableSelectWithMetadataProps {
  fieldId: string;
  name: string;
  label: string;
  value: string | null;
  options: Option[];
  placeholder?: string;
  formAction: (formData: FormData) => void;
  response: UpdateResponse;
  metadata?: Metadata;
  /** The rows this field shows over time; the edit then opens on the shown value's stretch. */
  editSource?: EditFieldSource;
  hiddenFields?: Record<string, string | number>;
}

export const EditableSelectWithMetadata = ({
  fieldId,
  name,
  label,
  value,
  options,
  placeholder = "Select an option",
  formAction,
  response,
  metadata,
  hiddenFields,
  editSource,
}: EditableSelectWithMetadataProps) => {
  const startEdit = useStartEdit();

  const [open, setOpen] = useState(false);
  const formRef = useRef<HTMLFormElement>(null);
  const { currentEdit, exitEditMode } = useEditManager();

  const isEditing = currentEdit?.fieldId === fieldId;
  // Remove mode (the panel's Change | Remove): the value is not changed, so the
  // choice is locked and the red Remove takes Save's place.
  const removing = isEditing && currentEdit.removing != null;

  const {
    currentValue,
    setCurrentValue,
    hasUnsavedChanges,
    handleCancel: baseHandleCancel,
  } = useEditableFieldState(value, response, isEditing, exitEditMode);
  // The choice holds the anchor's value, and follows it when the anchor
  // moves; with several periods ticked the timeline shows what it changes in
  // each (owner 2026-11-16).
  const { blocked } = useSaveApproval();
  const column =
    editSource && !Array.isArray(editSource.column) ? editSource.column : null;
  useEditAnchor(isEditing, editSource, (period) => {
    if (column && column in period.values)
      setCurrentValue(period.empty ? "" : String(period.values[column] ?? ""));
  });

  const handleCancel = () => {
    baseHandleCancel();
  };

  const currentOption = options.find(
    (option) => option.value.toString() === currentValue.toString()
  );

  return (
    <form
      ref={formRef}
      action={formAction}
      className={`flex flex-col space-y-2 p-2 ${isEditing && "bg-ssb-light rounded-md "}`}
    >
      {hiddenFields &&
        Object.entries(hiddenFields).map(([name, value]) => (
          <input key={name} type="hidden" name={name} value={value} />
        ))}
      <input type="hidden" name={name} value={currentValue} />
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
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger asChild>
            <Button
              variant="outline"
              role="combobox"
              aria-expanded={open}
              className="w-full justify-between font-medium disabled:opacity-80"
              disabled={!isEditing || removing}
            >
              <span className="truncate">
                {currentOption?.label ?? `${isEditing ? placeholder : ""}`}
              </span>
              <ChevronsUpDown
                className={`ml-2 h-4 w-4 shrink-0  ${!isEditing ? "opacity-0" : "opacity-50"}`}
              />
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-(--radix-popover-trigger-width) p-0">
            <Command>
              <CommandInput placeholder="Search..." />
              <CommandList>
                <CommandEmpty>No results found.</CommandEmpty>
                {groupRuns(options).map((run, runIndex) => (
                  <CommandGroup
                    key={`${runIndex}-${run.title ?? ""}`}
                    heading={run.title}
                  >
                    {run.options.map((option) => (
                      <CommandItem
                        key={option.value}
                        value={option.label}
                        keywords={option.group ? [option.group] : undefined}
                        disabled={option.disabled}
                        onSelect={() => {
                          setCurrentValue(option.value.toString());
                          setOpen(false);
                        }}
                      >
                        <Check
                          className={cn(
                            "mr-2 h-4 w-4",
                            currentValue.toString() === option.value.toString()
                              ? "opacity-100"
                              : "opacity-0"
                          )}
                        />
                        {option.label}
                      </CommandItem>
                    ))}
                  </CommandGroup>
                ))}
              </CommandList>
            </Command>
          </PopoverContent>
        </Popover>
      </div>

      {isEditing && (
        <div className="space-y-2">
          <EditMetadataControls fieldId={fieldId} />
          <div className="flex items-center justify-end space-x-2">
            <PrimaryUnitNotice />
            {!removing && <SaveApproval />}
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
                disabled={blocked}
                type="submit"
              >
                Save
              </Button>
            )}
          </div>
        </div>
      )}
      <SubmissionFeedbackDebugInfo state={response} />
    </form>
  );
};
