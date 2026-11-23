"use client";

import {
  useTableColumnsManager as useTableColumns,
  useSearchFilters,
} from "@/atoms/search";
import { TableColumn } from "../search.d";

interface FilterWrapperProps {
  columnCode: TableColumn["code"];
  statCode?: string | null;
  /** Search filter keys this wrapper's filter sets (filtersAtom keys). */
  filterKeys?: string[];
  children: React.ReactNode;
}

const hasValue = (value: unknown): boolean =>
  Array.isArray(value)
    ? value.length > 0
    : value !== undefined && value !== null && value !== "";

// A filter is shown when its column is visible, and always while it narrows the
// search: the toolbar names every filter in effect, so the list never shows
// fewer units than the visible filters explain and each can be cleared.
export function FilterWrapper({
  columnCode,
  statCode = null,
  filterKeys = [],
  children,
}: FilterWrapperProps) {
  const { visibleColumns } = useTableColumns();
  const { filters } = useSearchFilters();

  const isVisible = visibleColumns.some((column: TableColumn) => {
    if (column.code !== columnCode) return false;
    if (columnCode === "statistic" && column.type === "Adaptable") {
      return column.stat_code === statCode;
    }
    return true;
  });
  const isActive = filterKeys.some((key) => hasValue(filters[key]));

  if (!isVisible && !isActive) return null;

  return <>{children}</>;
}
