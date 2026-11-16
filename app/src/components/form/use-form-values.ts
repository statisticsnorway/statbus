"use client";

import { useState, type RefObject } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

/**
 * The values the edit's form holds now for `columns`, as it would post them.
 * A save writes these over the ticked periods (edit-changes), so the timeline
 * shows what they change while the user types or chooses. Typed fields report
 * through input events; a chosen value lives in a hidden input whose value
 * attribute changes, which a MutationObserver sees.
 */
export function useFormValues(
  anchorRef: RefObject<HTMLElement | null>,
  columns: readonly string[]
): Record<string, string> {
  const [values, setValues] = useState<Record<string, string>>({});
  const columnsKey = columns.join(",");
  useGuardedEffect(
    () => {
      const form = anchorRef.current?.closest("form");
      if (!form) return;
      const read = () => {
        const data = new FormData(form);
        const next: Record<string, string> = {};
        for (const column of columns)
          if (data.has(column)) next[column] = String(data.get(column) ?? "");
        setValues((prev) =>
          JSON.stringify(prev) === JSON.stringify(next) ? prev : next
        );
      };
      read();
      form.addEventListener("input", read);
      form.addEventListener("change", read);
      const observer = new MutationObserver(read);
      observer.observe(form, {
        subtree: true,
        attributes: true,
        attributeFilter: ["value"],
      });
      return () => {
        form.removeEventListener("input", read);
        form.removeEventListener("change", read);
        observer.disconnect();
      };
    },
    [anchorRef, columnsKey],
    "useFormValues:follow"
  );
  return values;
}
