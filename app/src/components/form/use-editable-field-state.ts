"use client";

import { useRef, useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

export function useEditableFieldState(
  initialValue: string | number | null,
  response: UpdateResponse,
  isEditing: boolean,
  exitEditMode: () => void
) {
  const [currentValue, setCurrentValue] = useState(initialValue ?? "");
  const [isSuccessfullySaved, setIsSuccessfullySaved] = useState(false);
  const valueAtSave = useRef(initialValue);

  // Sync with external changes when not editing or after a successful save
  useGuardedEffect(
    () => {
      if (isSuccessfullySaved) {
        // If the initialValue prop has changed since we entered the
        // optimistic state, it means new data has loaded (e.g. time context
        // changed). We must accept the new value and exit the optimistic state.
        if (initialValue !== valueAtSave.current) {
          setCurrentValue(initialValue ?? "");
          setIsSuccessfullySaved(false);
          return;
        }

        // Otherwise, if the initialValue has caught up to our optimistic
        // value, we can clear the successfully saved flag.
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
        // Record the value that was present when the successful save occurred.
        valueAtSave.current = initialValue;
        exitEditMode();
      } else if (response?.status === "error") {
        setIsSuccessfullySaved(false);
      }
    },
    [response, exitEditMode, initialValue],
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
