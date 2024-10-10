"use client";
import { ReactNode, useCallback, useMemo, useState } from "react";
import { Tables } from "@/lib/database.types";
import { SelectionContext } from "@/app/search/selection-context";

interface SelectionProviderProps {
  readonly children: ReactNode;
}

export const SelectionProvider = ({ children }: SelectionProviderProps) => {
  const [selected, setSelected] = useState<Tables<"statistical_unit">[]>([]);

  const toggle = useCallback(
    (unit: Tables<"statistical_unit">) => {
      setSelected((prev) => {
        const existing = prev.find(
          (s) => s.unit_id === unit.unit_id && s.unit_type === unit.unit_type
        );
        return existing ? prev.filter((s) => s !== existing) : [...prev, unit];
      });
    },
    [setSelected]
  );

  const ctx = useMemo(
    () => ({
      selected,
      toggle,
      clearSelected: () => setSelected([]),
    }),
    [toggle, selected]
  );

  return <SelectionContext.Provider value={ctx}>{children}</SelectionContext.Provider>;
};
