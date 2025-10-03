"use client";

import { usePathname } from "next/navigation";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useEditManager } from "@/atoms/edits";
import { useTimeContext } from "@/atoms/app-derived";

/**
 * This component has no UI. It exists solely to reset the global edit mode state
 * whenever the user navigates to a new page, ensuring that edit mode does not
 * persist across different statistical units.
 */
export function EditStateResetter() {
  const { selectedTimeContext } = useTimeContext();
  const pathname = usePathname();
  const { exitEditMode } = useEditManager();

  useGuardedEffect(
    () => {
      exitEditMode();
    },
    [pathname, exitEditMode, selectedTimeContext?.ident],
    "EditStateResetter:resetOnPathChange"
  );

  useGuardedEffect(
    () => {
      const handleKeyDown = (e: KeyboardEvent) => {
        if (e.key === "Escape") {
          exitEditMode();
        }
      };

      document.addEventListener("keydown", handleKeyDown);

      return () => {
        document.removeEventListener("keydown", handleKeyDown);
      };
    },
    [exitEditMode],
    "EditStateResetter:handleEscapeKey"
  );                                    

  return null;
}
