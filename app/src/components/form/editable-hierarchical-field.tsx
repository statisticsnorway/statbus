"use client";

import { useRef, useState, useMemo } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { Button } from "@/components/ui/button";
import { Pencil } from "lucide-react";
import { Input } from "../ui/input";
import { DeleteConfirmationDialog } from "./delete-confirmation-dialog";
import { Label } from "../ui/label";
import { useEditManager } from "@/atoms/edits";
import { cn } from "@/lib/utils";
import { EditButton } from "./edit-button";
import { Tables } from "@/lib/database.types";

/**
 * Parse labels ltree (e.g., "census.region.surveyor.unit_no") into an array of level labels.
 */
function parseLabels(labels: unknown): string[] {
  if (typeof labels === "string") {
    return labels.split(".");
  }
  return [];
}

/**
 * Parse a hierarchical identifier value (e.g., "CENSUS2024.CENTRAL.OKELLO.001") into individual level values.
 */
function parseHierarchicalValue(value: string | null | undefined, levelCount: number): string[] {
  const result = new Array(levelCount).fill("");
  if (!value) return result;

  const parts = value.split(".");
  for (let i = 0; i < Math.min(parts.length, levelCount); i++) {
    result[i] = parts[i];
  }

  return result;
}

/**
 * Compose individual level values into a hierarchical identifier path.
 * Returns null if all values are empty.
 */
function composeHierarchicalValue(values: string[]): string | null {
  const trimmedValues = values.map((v) => v.trim());
  
  // Find the last non-empty position
  let lastNonEmpty = trimmedValues.length - 1;
  while (lastNonEmpty >= 0 && trimmedValues[lastNonEmpty] === "") {
    lastNonEmpty--;
  }

  // If all empty, return null
  if (lastNonEmpty < 0) {
    return null;
  }

  // Build the path up to the last non-empty value
  return trimmedValues.slice(0, lastNonEmpty + 1).join(".");
}

/**
 * Capitalize the label for display (e.g., "census" => "Census", "unit_no" => "Unit no")
 */
function formatLabel(label: string): string {
  return label.charAt(0).toUpperCase() + label.slice(1).replace(/_/g, " ");
}

interface EditableHierarchicalFieldProps {
  fieldId: string;
  label: string;
  value: string | null;
  identType: Tables<"external_ident_type_active">;
  formAction: (formData: FormData) => void;
  response: UpdateResponse;
}

export const EditableHierarchicalField = ({
  fieldId,
  label,
  value,
  identType,
  formAction,
  response,
}: EditableHierarchicalFieldProps) => {
  const { currentEdit, setEditTarget, exitEditMode } = useEditManager();
  const isEditing = currentEdit?.fieldId === fieldId;
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const formRef = useRef<HTMLFormElement>(null);
  const inputRefs = useRef<(HTMLInputElement | null)[]>([]);

  // Parse the level labels from the identifier type
  const levelLabels = useMemo(() => parseLabels(identType.labels), [identType.labels]);

  // Initialize and track level values
  const [levelValues, setLevelValues] = useState<string[]>(() =>
    parseHierarchicalValue(value, levelLabels.length)
  );

  // Track original value to detect changes
  const [originalValue, setOriginalValue] = useState(value);

  // Reset when value changes from external source
  useGuardedEffect(
    () => {
      if (value !== originalValue) {
        setLevelValues(parseHierarchicalValue(value, levelLabels.length));
        setOriginalValue(value);
      }
    },
    [value, originalValue, levelLabels.length],
    "EditableHierarchicalField:syncValue"
  );

  // Exit edit mode and reset on successful save
  useGuardedEffect(
    () => {
      if (response?.status === "success" && isEditing) {
        exitEditMode();
      }
    },
    [response, isEditing, exitEditMode],
    "EditableHierarchicalField:exitOnSuccess"
  );

  // Sync values when not editing (e.g., after external data change)
  useGuardedEffect(
    () => {
      if (!isEditing) {
        setLevelValues(parseHierarchicalValue(value, levelLabels.length));
      }
    },
    [isEditing, value, levelLabels.length],
    "EditableHierarchicalField:syncWhenNotEditing"
  );

  // Focus first input when entering edit mode
  useGuardedEffect(
    () => {
      if (isEditing && inputRefs.current[0]) {
        inputRefs.current[0].focus();
      }
    },
    [isEditing],
    "EditableHierarchicalField:focusOnEdit"
  );

  // Check if there are unsaved changes
  const composedValue = composeHierarchicalValue(levelValues);
  const hasUnsavedChanges = composedValue !== value;
  const isDeleting = composedValue === null && hasUnsavedChanges;

  const handleLevelChange = (index: number, newValue: string) => {
    setLevelValues((prev) => {
      const updated = [...prev];
      updated[index] = newValue;
      return updated;
    });
  };

  const triggerFormSubmit = () => {
    formRef.current?.requestSubmit();
    setShowDeleteDialog(false);
  };

  const handleSave = () => {
    const newValue = composeHierarchicalValue(levelValues);
    if (!newValue) {
      setShowDeleteDialog(true);
      return;
    }
    triggerFormSubmit();
  };

  const handleCancel = () => {
    setLevelValues(parseHierarchicalValue(value, levelLabels.length));
    exitEditMode();
    setShowDeleteDialog(false);
  };

  return (
    <form ref={formRef} action={formAction} className="flex flex-col col-span-2">
      <div className="flex items-center justify-between">
        <Label className="flex items-center space-y-2 h-10">
          <span className="text-xs uppercase text-gray-600">{label}</span>
        </Label>
        <div className="flex space-x-2 items-center">
          {!isEditing ? (
            <EditButton
              className="h-8"
              variant="ghost"
              size="sm"
              type="button"
              onClick={() => setEditTarget(fieldId)}
            >
              <Pencil className="text-zinc-700" />
            </EditButton>
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
                variant={isDeleting ? "destructive" : "default"}
              >
                {isDeleting ? "Delete" : "Save"}
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
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-2">
        {levelLabels.map((levelLabel, index) => (
          <div key={`${fieldId}-${levelLabel}`} className="grid gap-1">
            <Label
              htmlFor={`${fieldId}-${index}`}
              className="text-xs text-muted-foreground"
            >
              {formatLabel(levelLabel)}
            </Label>
            <Input
              ref={(el) => {
                inputRefs.current[index] = el;
              }}
              id={`${fieldId}-${index}`}
              className={cn(
                "font-medium disabled:opacity-80 h-9",
                isEditing && "border-zinc-300"
              )}
              disabled={!isEditing}
              value={levelValues[index] || ""}
              onChange={(e) => handleLevelChange(index, e.target.value)}
              name={`${identType.code}_${levelLabel}`}
              placeholder={formatLabel(levelLabel)}
              autoComplete="off"
            />
          </div>
        ))}
      </div>
    </form>
  );
};
