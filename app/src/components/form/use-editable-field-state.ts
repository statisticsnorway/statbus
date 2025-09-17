"use client";

import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

export function useEditableFieldState(
  initialValue: string | number | null,
  response: UpdateResponse,
  isEditing: boolean,
  exitEditMode: () => void
) {
  const [currentValue, setCurrentValue] = useState(initialValue ?? "");
  const [isSuccessfullySaved, setIsSuccessfullySaved] = useState(false);

  // Sync with external changes when not editing or after a successful save
  useGuardedEffect(
    () => {
      if (isSuccessfullySaved) {
        if (initialValue === currentValue) {
          setIsSuccessfullySaved(false);
        }
        return;
      }
      if (!isEditing) {
        setCurrentValue(initialValue ?? "");
      }
    },
    [initialValue, isEditing, isSuccessfullySaved, currentValue],
    "useEditableFieldState:syncValue"
  );

  // Handle successful save — exit edit mode
  useGuardedEffect(
    () => {
      if (response?.status === "success" && isEditing) {
        setIsSuccessfullySaved(true);
        exitEditMode();
      } else if (response?.status === "error") {
        setIsSuccessfullySaved(false);
      }
    },
    [response, exitEditMode],
    "useEditableFieldState:exitOnSuccess"
  );

  const hasUnsavedChanges = currentValue !== (initialValue ?? "");

  const handleCancel = () => {
    setCurrentValue(initialValue ?? "");
    setIsSuccessfullySaved(false);
    exitEditMode();
  };

  return {
    currentValue,
    setCurrentValue,
    hasUnsavedChanges,
    handleCancel,
    isSuccessfullySaved,
  };
}
