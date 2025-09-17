"use client";

import React, { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Check, ChevronsUpDown, Pencil } from "lucide-react";
import { Label } from "../ui/label";
import { useAuth } from "@/atoms/auth";
import { useEditManager } from "@/atoms/edits";
import { Popover, PopoverContent, PopoverTrigger } from "../ui/popover";
import { cn } from "@/lib/utils";
import { useTimeContext } from "@/atoms/app-derived";
import { SubmissionFeedbackDebugInfo } from "./submission-feedback-debug-info";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { EditMetadataControls } from "./edit-metadata-controls";

interface Option {
  value: string | number;
  label: string;
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
}: EditableSelectWithMetadataProps) => {
  const { user } = useAuth();
  const { selectedTimeContext } = useTimeContext();
  const canEdit =
    user?.statbus_role === "admin_user" ||
    user?.statbus_role === "regular_user";
  const [currentValue, setCurrentValue] = useState<string | number>(
    value ?? ""
  );
  const [open, setOpen] = useState(false);

  const formRef = useRef<HTMLFormElement>(null);

  const { currentEdit, setEditTarget, exitEditMode } = useEditManager();

  const isEditing = currentEdit?.fieldId === fieldId;
  const hasUnsavedChanges = currentValue !== (value ?? "");

  useEffect(() => {
    if (!isEditing) {
      setCurrentValue(value ?? "");
    }
  }, [value, isEditing]);

  useGuardedEffect(
    () => {
      if (response?.status === "success" && isEditing) {
        exitEditMode();
      }
    },
    [response],
    "EditableSelectWithMetadata:exitOnSuccess"
  );

  const handleCancel = () => {
    setCurrentValue(value ?? "");
    exitEditMode();
  };

  const currentOption = options.find(
    (option) => option.value.toString() === currentValue.toString()
  );

  return (
    <form
      ref={formRef}
      action={formAction}
      className={`flex flex-col space-y-2 p-3 ${isEditing && "bg-ssb-light rounded-md "}`}
    >
      <input type="hidden" name={name} value={currentValue} />
      <div className="flex flex-col">
        <div className="flex items-center justify-between">
          <Label className="flex justify-between items-center space-y-2 h-10">
            <span className="text-xs uppercase text-gray-600">{label}</span>
          </Label>
          {canEdit && (
            <div className="flex space-x-2 mb-2">
              {!isEditing && (
                <Button
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
                </Button>
              )}
            </div>
          )}
        </div>
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger asChild>
            <Button
              variant="outline"
              role="combobox"
              aria-expanded={open}
              className="w-full justify-between font-medium disabled:opacity-80"
              disabled={!isEditing}
            >
              <span className="truncate">
                {currentOption?.label ?? placeholder}
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
                <CommandGroup>
                  {options.map((option) => (
                    <CommandItem
                      key={option.value}
                      value={option.label}
                      onSelect={() => {
                        setCurrentValue(option.value);
                        setOpen(false);
                      }}
                    >
                      <Check
                        className={cn(
                          "mr-2 h-4 w-4",
                          currentValue === option.value
                            ? "opacity-100"
                            : "opacity-0"
                        )}
                      />
                      {option.label}
                    </CommandItem>
                  ))}
                </CommandGroup>
              </CommandList>
            </Command>
          </PopoverContent>
        </Popover>
      </div>

      {isEditing && (
        <div className="space-y-2">
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
            <Button className="h-8" disabled={!hasUnsavedChanges} type="submit">
              Save
            </Button>
          </div>
        </div>
      )}
      <SubmissionFeedbackDebugInfo state={response} />
    </form>
  );
};
